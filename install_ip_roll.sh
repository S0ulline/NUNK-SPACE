#!/bin/bash

# ============================================================
#  Selectel Roller — установщик
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/root/selectel_roller"
SERVICE_NAME="ip-roll"
MENU_CMD="/usr/local/bin/ip-roll"

is_installed() {
    [ -d "$INSTALL_DIR" ]
}

print_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║        Selectel Roller Setup         ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"
}

do_install() {
    echo -e "${YELLOW}[*] Обновление пакетов и установка зависимостей...${NC}"
    sudo apt update && sudo apt install -y python3.12 python3.12-venv python3-pip git

    if is_installed; then
        echo -e "${YELLOW}[!] Директория уже существует: ${INSTALL_DIR}${NC}"
    else
        echo -e "${YELLOW}[*] Клонирование репозитория...${NC}"
        cd /root/ && git clone https://github.com/bymakk/selectel_roller.git
    fi

    cd "$INSTALL_DIR" || exit 1

    echo -e "${YELLOW}[*] Создание виртуального окружения...${NC}"
    python3.12 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt 2>/dev/null || true

    # ── Заполнение .env ──────────────────────────────────────
    echo -e "${CYAN}${BOLD}"
    echo "  ┌─────────────────────────────────────────┐"
    echo "  │   Настройка .env — Аккаунт 1 (SEL)     │"
    echo "  └─────────────────────────────────────────┘"
    echo -e "${NC}"

    read -rp "  SEL_USERNAME       : " SEL_USERNAME
    read -rsp "  SEL_PASSWORD       : " SEL_PASSWORD; echo
    read -rp "  SEL_ACCOUNT_ID     : " SEL_ACCOUNT_ID
    read -rp "  SEL_PROJECT_NAME   : " SEL_PROJECT_NAME

    echo -e "${CYAN}${BOLD}"
    echo "  ┌─────────────────────────────────────────┐"
    echo "  │   Настройка .env — Аккаунт 2 (SEL2)    │"
    echo "  └─────────────────────────────────────────┘"
    echo -e "${NC}"

    read -rp "  SEL2_USERNAME      : " SEL2_USERNAME
    read -rsp "  SEL2_PASSWORD      : " SEL2_PASSWORD; echo
    read -rp "  SEL2_ACCOUNT_ID    : " SEL2_ACCOUNT_ID
    read -rp "  SEL2_PROJECT_NAME  : " SEL2_PROJECT_NAME

    cat > "$INSTALL_DIR/.env" <<EOF
SEL_USERNAME=${SEL_USERNAME}
SEL_PASSWORD="${SEL_PASSWORD}"
SEL_ACCOUNT_ID=${SEL_ACCOUNT_ID}
SEL_PROJECT_NAME=${SEL_PROJECT_NAME}
SEL_PROJECT_ID=

SEL2_USERNAME=${SEL2_USERNAME}
SEL2_PASSWORD="${SEL2_PASSWORD}"
SEL2_ACCOUNT_ID=${SEL2_ACCOUNT_ID}
SEL2_PROJECT_NAME=${SEL2_PROJECT_NAME}
SEL2_PROJECT_ID=

# --- Регионы (опционально) ---
# SEL1_SCANNER_REGIONS=ru-1,ru-2,ru-3
# SEL2_SCANNER_REGIONS=ru-1,ru-2,ru-3

# ========== Скорость перебора IP и тайминги (опционально) ==========
# SEL_MAX_IPS_PER_MINUTE=30
# SEL_TARGET_COUNT=1
# SEL_BATCH_SIZE=1
# SEL_MAX_BATCH_SIZE=1
# SEL_DELETE_CONCURRENCY=8
# SEL_COOLDOWN_BASE=2.0
# SEL_COOLDOWN_MAX=60
# SEL_RECONCILE_INTERVAL=7
# SEL_ALLOCATION_POLL_ATTEMPTS=5
# SEL_ALLOCATION_POLL_DELAY=0.45
# SEL_REFRESH_PER_SECOND=6
EOF

    chmod +x "$INSTALL_DIR/run.sh" 2>/dev/null || true

    # ── Регистрация команды ip-roll ──────────────────────────
    sudo tee "$MENU_CMD" > /dev/null <<'SCRIPT'
#!/bin/bash
bash /root/selectel_roller/menu.sh
SCRIPT
    sudo chmod +x "$MENU_CMD"

    # ── Сохранение menu.sh рядом с проектом ─────────────────
    cat > "$INSTALL_DIR/menu.sh" <<'MENU'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/root/selectel_roller"

is_installed() { [ -d "$INSTALL_DIR" ]; }

while true; do
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║         ip-roll  |  Главное меню     ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"

    if is_installed; then
        echo -e "  ${GREEN}[✓] Статус: установлено${NC}"
    else
        echo -e "  ${RED}[✗] Статус: не установлено${NC}"
    fi

    echo ""
    echo -e "  ${BOLD}1)${NC} Установить / Запустить"
    echo -e "  ${BOLD}2)${NC} Удалить"
    echo -e "  ${BOLD}0)${NC} Выход"
    echo ""
    read -rp "  Выберите пункт: " choice

    case "$choice" in
        1)
            if is_installed; then
                echo -e "\n${YELLOW}[*] Запуск...${NC}"
                cd "$INSTALL_DIR" || exit 1
                source venv/bin/activate 2>/dev/null || true
                bash run.sh
            else
                echo -e "\n${YELLOW}[!] Не установлено. Запустите установщик.${NC}"
                sleep 2
            fi
            ;;
        2)
            if is_installed; then
                read -rp "  Удалить ${INSTALL_DIR}? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    rm -rf "$INSTALL_DIR"
                    sudo rm -f /usr/local/bin/ip-roll
                    echo -e "${GREEN}[✓] Удалено.${NC}"
                    sleep 2
                    exit 0
                fi
            else
                echo -e "\n${RED}[!] Не установлено.${NC}"
                sleep 2
            fi
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "\n${RED}[!] Неверный выбор.${NC}"
            sleep 1
            ;;
    esac
done
MENU

    chmod +x "$INSTALL_DIR/menu.sh"

    echo -e "\n${GREEN}${BOLD}[✓] Установка завершена!${NC}"
    echo -e "  Для управления введите: ${CYAN}${BOLD}ip-roll${NC}\n"
}

# ── Точка входа ──────────────────────────────────────────────
print_banner

if is_installed; then
    echo -e "${GREEN}[✓] Уже установлено.${NC} Открываю меню...\n"
    sleep 1
    bash "$INSTALL_DIR/menu.sh"
else
    do_install
fi
