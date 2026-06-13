#!/usr/bin/env bash
#
# Ручное обновление ядра Xray для ноды Remnawave.
# Скачивает указанный релиз Xray-core, распаковывает его в
# /opt/remnanode/custom-xray, проверяет наличие volume-монтирования
# в docker-compose.yml, перезапускает контейнер и сверяет версию.
#
# Использование:
#   ./update-xray.sh                 # установит версию по умолчанию (v26.6.1)
#   ./update-xray.sh v26.6.1         # явно указать тег релиза
#
set -euo pipefail

# --- Настройки -------------------------------------------------------------
XRAY_VERSION="${1:-v26.6.1}"          # тег релиза на GitHub (с префиксом v)
MIN_VERSION="26.3.27"                 # минимально допустимая версия
NODE_DIR="/opt/remnanode"
CUSTOM_DIR="${NODE_DIR}/custom-xray"
COMPOSE_FILE="${NODE_DIR}/docker-compose.yml"
VOLUME_LINE="- '/opt/remnanode/custom-xray/xray:/usr/local/bin/xray:ro'"
VOLUME_MATCH="custom-xray/xray:/usr/local/bin/xray"

# --- Цвета и логирование ---------------------------------------------------
RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; NC=$'\e[0m'
info()  { echo "${BLUE}[*]${NC} $*"; }
ok()    { echo "${GREEN}[+]${NC} $*"; }
warn()  { echo "${YELLOW}[!]${NC} $*"; }
err()   { echo "${RED}[-]${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

# --- Предварительные проверки ----------------------------------------------
[[ "${EUID}" -eq 0 ]] || die "Запусти скрипт от root (sudo)."

command -v docker >/dev/null 2>&1 || die "docker не найден."
docker compose version >/dev/null 2>&1 || die "плагин 'docker compose' не найден."

# Определяем архитектуру, чтобы взять правильный архив.
case "$(uname -m)" in
  x86_64|amd64)        ZIP="Xray-linux-64.zip"    ;;
  aarch64|arm64)       ZIP="Xray-linux-arm64-v8a.zip" ;;
  *) die "Неизвестная архитектура: $(uname -m). Поправь переменную ZIP вручную." ;;
esac

URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${ZIP}"

# --- 1) Каталог ------------------------------------------------------------
info "Создаю каталог ${CUSTOM_DIR}"
mkdir -p "${CUSTOM_DIR}"
cd "${CUSTOM_DIR}"

# --- 2) Зависимости --------------------------------------------------------
info "Устанавливаю unzip / wget при необходимости"
apt-get update -y
apt-get install -y unzip wget

# --- 3) Скачивание ---------------------------------------------------------
info "Скачиваю ${URL}"
wget -q --show-progress -O "${ZIP}" "${URL}" \
  || die "Не удалось скачать ${ZIP}. Проверь, что релиз ${XRAY_VERSION} существует."

# --- 4) Распаковка ---------------------------------------------------------
info "Распаковываю ${ZIP}"
unzip -o "${ZIP}" >/dev/null
chmod +x "${CUSTOM_DIR}/xray"
ok "Бинарник распакован: ${CUSTOM_DIR}/xray"

# Покажем версию свежескачанного бинарника ещё до перезапуска контейнера.
info "Версия скачанного бинарника:"
"${CUSTOM_DIR}/xray" version | head -n 1 || true

# --- 5) + 6) Проверка docker-compose.yml -----------------------------------
[[ -f "${COMPOSE_FILE}" ]] || die "Не найден ${COMPOSE_FILE}"

if grep -q "${VOLUME_MATCH}" "${COMPOSE_FILE}"; then
  ok "Volume-монтирование уже прописано в docker-compose.yml"
else
  warn "В ${COMPOSE_FILE} отсутствует нужный volume."
  warn "В секцию services -> remnanode -> volumes добавь строку:"
  echo
  echo "    volumes:"
  echo "        ${VOLUME_LINE}"
  echo
  read -rp "Открыть docker-compose.yml в nano для правки сейчас? [y/N] " ans
  if [[ "${ans,,}" == "y" ]]; then
    "${EDITOR:-nano}" "${COMPOSE_FILE}"
    grep -q "${VOLUME_MATCH}" "${COMPOSE_FILE}" \
      || die "Volume так и не найден — прерываю, чтобы не запускать со старым ядром."
    ok "Volume теперь на месте."
  else
    die "Без volume контейнер продолжит использовать встроенное ядро. Прерываю."
  fi
fi

# --- 7) Перезапуск контейнера ----------------------------------------------
cd "${NODE_DIR}"
info "Перезапускаю ноду (down -> up -d)"
docker compose down
docker compose up -d

# --- 8) Проверка версии в контейнере ---------------------------------------
info "Жду запуска контейнера..."
sleep 3

RAW_VER="$(docker exec -i remnanode xray version 2>/dev/null | head -n 1 || true)"
[[ -n "${RAW_VER}" ]] || die "Не удалось получить версию из контейнера. Проверь логи: docker compose logs -f -t"

# Вытаскиваем номер версии вида 26.6.1
RUNNING="$(echo "${RAW_VER}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
info "Контейнер сообщает: ${RAW_VER}"

# Сравнение версий (sort -V): берём минимальную из пары — если это MIN_VERSION,
# значит RUNNING >= MIN_VERSION.
LOWEST="$(printf '%s\n%s\n' "${RUNNING}" "${MIN_VERSION}" | sort -V | head -n 1)"
if [[ "${RUNNING}" == "${MIN_VERSION}" ]]; then
  warn "Версия ровно ${MIN_VERSION} — это и есть нижняя граница, нужно ВЫШЕ."
  EXIT=1
elif [[ "${LOWEST}" == "${MIN_VERSION}" ]]; then
  ok "Версия ${RUNNING} > ${MIN_VERSION} — обновление прошло успешно."
  EXIT=0
else
  err "Версия ${RUNNING} НЕ выше ${MIN_VERSION}. Что-то пошло не так."
  EXIT=1
fi

echo
info "Логи ноды (Ctrl+C для выхода):"
exec docker compose logs -f -t
