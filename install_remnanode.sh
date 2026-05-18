#!/usr/bin/env bash
set -euo pipefail

# ══════════════════════════════════════════════
#   NUNK SPACE — Remnanode + WARP installer
# ══════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

# ─── WARP config ───────────────────────────────
WARP_DIR="/etc/warp-remnanode"
CONF_FILE="$WARP_DIR/config"
LOG_FILE="/var/log/warp-remnanode.log"
DEFAULT_WARP_PORT="40000"
SOCKS_PORT="$DEFAULT_WARP_PORT"

# ══════════════════════════════════════════════
#  Helpers
# ══════════════════════════════════════════════

log() { echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"; }
msg() { echo -e "$*"; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Запустите скрипт от root"
    exit 1
  fi
}

need_cmds() {
  local pkgs=()
  command -v curl  >/dev/null 2>&1 || pkgs+=(curl)
  command -v gpg   >/dev/null 2>&1 || pkgs+=(gnupg)
  command -v jq    >/dev/null 2>&1 || pkgs+=(jq)
  command -v ss    >/dev/null 2>&1 || pkgs+=(iproute2)
  if [[ ${#pkgs[@]} -gt 0 ]]; then
    apt-get update -y
    apt-get install -y "${pkgs[@]}"
  fi
}

# ══════════════════════════════════════════════
#  WARP — config persistence
# ══════════════════════════════════════════════

init_warp_config() {
  mkdir -p "$WARP_DIR"
  touch "$LOG_FILE"
  if [[ ! -f "$CONF_FILE" ]]; then
    echo "SOCKS_PORT=\"${DEFAULT_WARP_PORT}\"" > "$CONF_FILE"
  fi
  # shellcheck disable=SC1090
  source "$CONF_FILE"
  SOCKS_PORT="${SOCKS_PORT:-$DEFAULT_WARP_PORT}"
}

save_warp_config() {
  echo "SOCKS_PORT=\"${SOCKS_PORT}\"" > "$CONF_FILE"
}

# ══════════════════════════════════════════════
#  WARP — install & lifecycle
# ══════════════════════════════════════════════

detect_os() {
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" && "${ID:-}" != "debian" ]]; then
    msg "${RED}Поддерживаются только Ubuntu/Debian${NC}"
    exit 1
  fi
  OS_CODENAME="${VERSION_CODENAME:-noble}"
}

warp_installed()   { command -v warp-cli >/dev/null 2>&1; }
warp_status_raw()  { warp-cli --accept-tos status 2>/dev/null || true; }
warp_connected()   { warp_status_raw | grep -qi "Connected"; }
port_in_use()      { ss -lntup | awk '{print $5}' | grep -qE "[:.]${1}$"; }

install_warp_pkg() {
  detect_os
  mkdir -p /usr/share/keyrings
  curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
    | gpg --dearmor --yes -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

  cat > /etc/apt/sources.list.d/cloudflare-client.list <<EOF
deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${OS_CODENAME} main
EOF
  apt-get update -y
  apt-get install -y cloudflare-warp
}

ensure_registered() {
  if warp_status_raw | grep -qi "Registration Missing"; then
    msg "${YELLOW}Регистрация отсутствует, создаю новую...${NC}"
    warp-cli --accept-tos registration new
  fi
}

set_proxy_mode() {
  ensure_registered
  warp-cli --accept-tos mode proxy
  warp-cli --accept-tos proxy port "${SOCKS_PORT}"
  log "Proxy mode set on ${SOCKS_PORT}"
}

install_and_connect_warp() {
  if warp_installed; then
    msg "${YELLOW}WARP уже установлен, пропускаем установку пакета...${NC}"
  else
    msg "${CYAN}Устанавливаю Cloudflare WARP...${NC}"
    install_warp_pkg
    warp-cli --accept-tos registration new
  fi

  set_proxy_mode
  warp-cli --accept-tos connect || true
  sleep 3

  if warp_connected; then
    msg "${GREEN}WARP успешно подключён (SOCKS5 127.0.0.1:${SOCKS_PORT})${NC}"
    log "WARP installed and connected, port ${SOCKS_PORT}"
  else
    msg "${YELLOW}WARP установлен, но соединение ещё не установлено. Проверьте статус позже.${NC}"
  fi
}

connect_warp() {
  ensure_registered
  set_proxy_mode
  warp-cli --accept-tos connect || true
  sleep 3
  if warp_connected; then
    msg "${GREEN}WARP подключён${NC}"
    log "WARP connected"
  else
    msg "${RED}WARP не подключился${NC}"
  fi
}

disconnect_warp() {
  warp-cli --accept-tos disconnect || true
  msg "${YELLOW}WARP отключён${NC}"
  log "WARP disconnected"
}

restart_warp() {
  disconnect_warp
  sleep 1
  connect_warp
}

re_register_warp() {
  msg "${YELLOW}Перерегистрация WARP...${NC}"
  warp-cli --accept-tos disconnect       || true
  warp-cli --accept-tos registration delete >/dev/null 2>&1 || true
  warp-cli --accept-tos registration new
  set_proxy_mode
  connect_warp
  log "WARP re-registered"
}

change_warp_port() {
  read -r -p "Новый SOCKS5 порт [1-65535]: " new_port
  [[ "$new_port" =~ ^[0-9]+$ ]] || { msg "${RED}Некорректный порт${NC}"; return; }
  (( new_port >= 1 && new_port <= 65535 )) || { msg "${RED}Некорректный порт${NC}"; return; }
  if port_in_use "$new_port"; then
    msg "${RED}Порт ${new_port} уже занят${NC}"; return
  fi
  SOCKS_PORT="$new_port"
  save_warp_config
  set_proxy_mode
  restart_warp
  msg "${GREEN}Порт изменён на ${SOCKS_PORT}${NC}"
  log "Port changed to ${SOCKS_PORT}"
}

show_warp_ips() {
  local direct_ip warp_ip
  direct_ip="$(curl -4 -s --max-time 8  https://ifconfig.me 2>/dev/null || echo 'N/A')"
  warp_ip="$(curl -4 -s --max-time 12 --proxy "socks5h://127.0.0.1:${SOCKS_PORT}" https://ifconfig.me 2>/dev/null || echo 'N/A')"
  echo
  msg "${WHITE}Обычный IP:${NC}       ${CYAN}${direct_ip}${NC}"
  msg "${WHITE}IP через WARP:${NC}    ${CYAN}${warp_ip}${NC}"
  echo
}

show_warp_status() {
  echo
  msg "${WHITE}=== WARP status ===${NC}"
  warp_status_raw
  echo
  msg "${WHITE}=== SOCKS прослушка (порт ${SOCKS_PORT}) ===${NC}"
  ss -lntup | grep -E "[:.]${SOCKS_PORT}\b" || echo "Порт ${SOCKS_PORT} не слушается"
  echo
  show_warp_ips
}

# ══════════════════════════════════════════════
#  Remnanode — install / remove
# ══════════════════════════════════════════════

install_docker() {
  if ! command -v docker &>/dev/null; then
    msg "${CYAN}Устанавливаю Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
  else
    msg "Docker уже установлен, пропускаем..."
  fi
}

configure_firewall() {
  local panel_domain="$1"
  apt-get install -y ufw >/dev/null 2>&1

  local panel_ip
  panel_ip="$(getent hosts "$panel_domain" | awk '{print $1}' | head -n1)"

  sudo ufw allow 22/tcp  >/dev/null 2>&1
  sudo ufw allow 80/tcp  >/dev/null 2>&1
  sudo ufw allow 443     >/dev/null 2>&1
  sudo ufw delete allow 2222/tcp >/dev/null 2>&1 || true

  if [[ -n "$panel_ip" ]]; then
    msg "IP панели: ${GREEN}${panel_ip}${NC} — открываем 2222 только для него"
    sudo ufw allow from "$panel_ip" to any port 2222 proto tcp >/dev/null 2>&1
  else
    msg "${RED}Не удалось определить IP из домена ${panel_domain}.${NC} Порт 2222 будет открыт для всех."
    sudo ufw allow 2222/tcp >/dev/null 2>&1
    panel_ip=""
  fi

  sudo ufw --force enable >/dev/null 2>&1
  echo "$panel_ip"   # возвращаем IP для итогового вывода
}

write_docker_compose() {
  local secret_key="$1"
  local use_warp="$2"

  sudo mkdir -p /opt/remnanode
  cd /opt/remnanode

  if [[ "$use_warp" == "yes" ]]; then
    # Монтируем WARP-каталог, чтобы warp-cli был доступен внутри контейнера
    # через host-сеть это не нужно — нода и WARP работают на одном хосте
    cat > /opt/remnanode/docker-compose.yml <<EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=2222
      - SECRET_KEY="${secret_key}"
EOF
  else
    cat > /opt/remnanode/docker-compose.yml <<EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=2222
      - SECRET_KEY="${secret_key}"
EOF
  fi
}

install_node() {
  clear
  echo -e "${CYAN}"
  cat << "EOF"
 ███╗   ██╗██╗   ██╗███╗   ██╗██╗  ██╗    ███████╗██████╗  █████╗  ██████╗ ███████╗
 ████╗  ██║██║   ██║████╗  ██║██║ ██╔╝    ██╔════╝██╔══██╗██╔══██╗██╔════╝ ██╔════╝
 ██╔██╗ ██║██║   ██║██╔██╗ ██║█████╔╝     ███████╗██████╔╝███████║██║      █████╗
 ██║╚██╗██║██║   ██║██║╚██╗██║██╔═██╗     ╚════██║██╔═══╝ ██╔══██║██║      ██╔══╝
 ██║ ╚████║╚██████╔╝██║ ╚████║██║  ██╗    ███████║██║     ██║  ██║╚██████╗ ███████╗
 ╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝    ╚══════╝╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
EOF
  echo -e "${NC}"
  msg "${GREEN}=== Установка / Обновление Remnanode ===${NC}\n"

  # ─── Сбор данных ────────────────────────────
  msg "${YELLOW}--- Сбор данных ---${NC}"
  read -r -p "Введите домен вашей ПАНЕЛИ (например, remna.nunk.space): " PANEL_DOMAIN
  read -r -p "Введите SECRET_KEY для связи с панелью: " SECRET_KEY

  echo ""
  read -r -p "Установить Cloudflare WARP на ноду? [y/N]: " WARP_CHOICE
  WARP_CHOICE="${WARP_CHOICE,,}"   # lowercase

  if [[ "$WARP_CHOICE" == "y" || "$WARP_CHOICE" == "yes" ]]; then
    read -r -p "SOCKS5 порт для WARP [${DEFAULT_WARP_PORT}]: " WARP_PORT_INPUT
    if [[ -n "$WARP_PORT_INPUT" ]]; then
      SOCKS_PORT="$WARP_PORT_INPUT"
    fi
    save_warp_config
    USE_WARP="yes"
  else
    USE_WARP="no"
  fi

  msg "\n${GREEN}Начинаем установку...${NC}"
  echo "=============================="

  # 1. Система
  msg "${CYAN}[1/5] Обновление пакетов системы...${NC}"
  apt-get update && apt-get upgrade -y

  # 2. Docker
  msg "${CYAN}[2/5] Установка Docker...${NC}"
  install_docker

  # 3. Firewall
  msg "${CYAN}[3/5] Настройка UFW...${NC}"
  PANEL_IP="$(configure_firewall "$PANEL_DOMAIN")"

  # 4. WARP (опционально)
  if [[ "$USE_WARP" == "yes" ]]; then
    msg "${CYAN}[4/5] Установка и подключение WARP...${NC}"
    need_cmds
    install_and_connect_warp
  else
    msg "${CYAN}[4/5] WARP пропущен по выбору пользователя.${NC}"
  fi

  # 5. Remnanode
  msg "${CYAN}[5/5] Создание конфигурации и запуск Remnanode...${NC}"
  write_docker_compose "$SECRET_KEY" "$USE_WARP"
  cd /opt/remnanode
  docker compose down 2>/dev/null || true
  docker compose up -d

  # ─── Итог ───────────────────────────────────
  echo ""
  echo "======================================================="
  msg "${GREEN}✨ Установка успешно завершена! ✨${NC}"
  echo "======================================================="
  msg "Нода работает в режиме 'Глупой ноды' (сертификаты доставит панель)."
  if [[ -n "$PANEL_IP" ]]; then
    msg "Порт 2222 защищён: доступ разрешён только для IP ${CYAN}${PANEL_IP}${NC}."
  fi
  if [[ "$USE_WARP" == "yes" ]]; then
    msg "WARP SOCKS5: ${CYAN}127.0.0.1:${SOCKS_PORT}${NC}"
    msg "Добавьте outbound в Config Profile ноды (см. меню WARP → пункт 8)."
  fi
  msg "Логи ноды: ${YELLOW}sudo docker logs -f remnanode${NC}"
  echo "Теперь идите в веб-интерфейс панели и привяжите эту ноду!"
}

remove_node() {
  msg "\n${YELLOW}Удаление ноды...${NC}"
  cd /opt/remnanode 2>/dev/null && docker compose down 2>/dev/null || true
  rm -rf /opt/remnanode
  ufw delete allow 2222/tcp >/dev/null 2>&1 || true
  msg "${GREEN}Нода успешно удалена!${NC}"
}

# ══════════════════════════════════════════════
#  WARP sub-menu (вызывается из главного меню)
# ══════════════════════════════════════════════

warp_menu() {
  init_warp_config
  need_cmds

  while true; do
    clear
    msg "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    msg "${CYAN}║         WARP for Remnanode — управление      ║${NC}"
    msg "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo
    msg " 1) Установить / подключить WARP"
    msg " 2) Показать статус"
    msg " 3) Перезапустить WARP"
    msg " 4) Отключить WARP"
    msg " 5) Перерегистрировать WARP"
    msg " 6) Изменить порт SOCKS5 (сейчас: ${SOCKS_PORT})"
    msg " 7) Сгенерировать X25519 ключи"
    msg " 8) Сгенерировать shortId"
    msg " 9) Показать outbound для Remnawave"
    msg "10) Показать routing rules для Remnawave"
    msg "11) Перезапустить remnanode"
    msg " 0) ← Назад"
    echo
    read -r -p "Выбор: " choice

    case "$choice" in
      1)  install_and_connect_warp; read -r -p "Enter..." ;;
      2)  show_warp_status;          read -r -p "Enter..." ;;
      3)  restart_warp; show_warp_status; read -r -p "Enter..." ;;
      4)  disconnect_warp;            read -r -p "Enter..." ;;
      5)  re_register_warp; show_warp_status; read -r -p "Enter..." ;;
      6)  change_warp_port;           read -r -p "Enter..." ;;
      7)  docker exec -it remnanode sh -lc 'xray x25519'; read -r -p "Enter..." ;;
      8)  docker exec -it remnanode sh -lc 'head -c 8 /dev/urandom | xxd -p -c 256'; read -r -p "Enter..." ;;
      9)  show_remnawave_outbound;    read -r -p "Enter..." ;;
      10) show_remnawave_routing;     read -r -p "Enter..." ;;
      11) docker compose -f /opt/remnanode/docker-compose.yml restart; read -r -p "Enter..." ;;
      0)  return ;;
      *)  msg "${RED}Неверный выбор${NC}"; sleep 1 ;;
    esac
  done
}

show_remnawave_outbound() {
  cat <<EOF
{
  "tag": "WARP",
  "protocol": "socks",
  "settings": {
    "servers": [
      {
        "address": "127.0.0.1",
        "port": ${SOCKS_PORT}
      }
    ]
  },
  "streamSettings": {
    "sockopt": {
      "mark": 255
    }
  }
}
EOF
}

show_remnawave_routing() {
  cat <<'EOF'
[
  {
    "domain": [
      "geosite:openai",
      "domain:chatgpt.com",
      "domain:chat.openai.com",
      "domain:claude.ai",
      "domain:anthropic.com",
      "domain:gemini.google.com"
    ],
    "outboundTag": "WARP"
  }
]
EOF
}

# ══════════════════════════════════════════════
#  Главное меню
# ══════════════════════════════════════════════

main_menu() {
  while true; do
    clear
    echo -e "${CYAN}"
    cat << "EOF"
 ███╗   ██╗██╗   ██╗███╗   ██╗██╗  ██╗    ███████╗██████╗  █████╗  ██████╗ ███████╗
 ████╗  ██║██║   ██║████╗  ██║██║ ██╔╝    ██╔════╝██╔══██╗██╔══██╗██╔════╝ ██╔════╝
 ██╔██╗ ██║██║   ██║██╔██╗ ██║█████╔╝     ███████╗██████╔╝███████║██║      █████╗
 ██║╚██╗██║██║   ██║██║╚██╗██║██╔═██╗     ╚════██║██╔═══╝ ██╔══██║██║      ██╔══╝
 ██║ ╚████║╚██████╔╝██║ ╚████║██║  ██╗    ███████║██║     ██║  ██║╚██████╗ ███████╗
 ╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝    ╚══════╝╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
EOF
    echo -e "${NC}"
    msg "${GREEN}=== Менеджер Remnanode (Без SSL) ===${NC}\n"
    msg "Выберите действие:"
    msg " 1) Установить / Обновить ноду"
    msg " 2) Удалить ноду"
    msg " 3) Управление WARP"
    msg " 0) Выход"
    echo
    read -r -p "Ваш выбор [0-3]: " MENU_CHOICE

    case "$MENU_CHOICE" in
      1) install_node ;;
      2) remove_node ;;
      3) warp_menu ;;
      0) msg "Выход..."; exit 0 ;;
      *) msg "${RED}Неверный выбор.${NC}"; sleep 1 ;;
    esac
  done
}

# ══════════════════════════════════════════════
#  Entry point
# ══════════════════════════════════════════════
need_root
main_menu
