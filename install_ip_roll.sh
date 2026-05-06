#!/bin/bash
# ============================================================
#  Selectel Roller — установщик
#  Поддерживает два режима:
#    1. Интерактивный:   bash install_ip_roll.sh
#    2. Автоматический:  AUTOINSTALL=1 bash install_ip_roll.sh
#       (используется оркестратором при удалённой установке)
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/root/selectel_roller"
MENU_CMD="/usr/local/bin/ip-roll"

# ── Флаг автоматического режима (передаётся оркестратором) ──
AUTOINSTALL="${AUTOINSTALL:-0}"

is_installed() {
    [ -f "$INSTALL_DIR/main.py" ]
}

print_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║        Selectel Roller Setup         ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"
}

# ── Вывод ошибки и выход с кодом 1 ──────────────────────────
fail() {
    echo -e "${RED}${BOLD}[✗] ОШИБКА: $1${NC}" >&2
    exit 1
}

do_install() {
    echo -e "${YELLOW}[*] Обновление пакетов и установка зависимостей...${NC}"
    apt-get update -qq \
        && apt-get install -y -qq python3.12 python3.12-venv python3-pip git curl \
        || fail "Не удалось установить системные зависимости"

    if is_installed; then
        echo -e "${YELLOW}[!] Директория уже существует: ${INSTALL_DIR}${NC}"
    else
        echo -e "${YELLOW}[*] Клонирование репозитория...${NC}"
        git clone https://github.com/bymakk/selectel_roller.git "$INSTALL_DIR" \
            || fail "Не удалось клонировать репозиторий"
    fi

    cd "$INSTALL_DIR" || fail "Не удалось войти в $INSTALL_DIR"

    echo -e "${YELLOW}[*] Создание виртуального окружения...${NC}"
    python3.12 -m venv venv                                         || fail "venv не создан"
    source venv/bin/activate
    pip install -q --upgrade pip
    pip install -q -r requirements.txt                              || fail "pip install завершился с ошибкой"

    # ── .env: в автоматическом режиме создаём пустой шаблон ─
    if [ ! -f "$INSTALL_DIR/.env" ]; then
        echo -e "${YELLOW}[*] Создаю шаблон .env...${NC}"
        cat > "$INSTALL_DIR/.env" <<'EOF'
# Первый аккаунт Selectel
SEL_USERNAME=
SEL_PASSWORD=
SEL_ACCOUNT_ID=
SEL_PROJECT_NAME=
SEL_PROJECT_ID=
SEL_SERVER_ID_RU2=
SEL_SERVER_ID_RU3=

# Второй аккаунт Selectel (если нужен)
SEL2_USERNAME=
SEL2_PASSWORD=
SEL2_ACCOUNT_ID=
SEL2_PROJECT_NAME=
SEL2_PROJECT_ID=
SEL2_SERVER_ID_RU2=
SEL2_SERVER_ID_RU3=

# Регионы (через запятую: ru-1,ru-2,ru-3)
SEL1_SCANNER_REGIONS=ru-1,ru-2,ru-3
SEL2_SCANNER_REGIONS=ru-1,ru-2,ru-3

# Скорость
SEL_MAX_IPS_PER_MINUTE=30
SEL_BATCH_SIZE=1
SEL_MAX_BATCH_SIZE=1
SEL_DELETE_CONCURRENCY=8
EOF
        echo -e "${YELLOW}[!] Заполните .env своими данными перед первым запуском!${NC}"
    fi

    chmod +x "$INSTALL_DIR/run.sh" 2>/dev/null || true

    # ── Команда ip-roll ─────────────────────────────────────
    cat > "$MENU_CMD" <<'SCRIPT'
#!/bin/bash
bash /root/selectel_roller/menu.sh
SCRIPT
    chmod +x "$MENU_CMD"

    # ── menu.sh ─────────────────────────────────────────────
    cat > "$INSTALL_DIR/menu.sh" <<'MENU'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/root/selectel_roller"

is_installed() { [ -f "$INSTALL_DIR/main.py" ]; }

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
    echo -e "  ${BOLD}1)${NC} Запустить"
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
                    rm -f /usr/local/bin/ip-roll
                    echo -e "${GREEN}[✓] Удалено.${NC}"
                    sleep 2
                    exit 0
                fi
            else
                echo -e "\n${RED}[!] Не установлено.${NC}"
                sleep 2
            fi
            ;;
        0) exit 0 ;;
        *)
            echo -e "\n${RED}[!] Неверный выбор.${NC}"
            sleep 1
            ;;
    esac
done
MENU
    chmod +x "$INSTALL_DIR/menu.sh"

    echo -e "\n${GREEN}${BOLD}[✓] Установка завершена!${NC}"
    if [ "$AUTOINSTALL" = "1" ]; then
        echo -e "  Оркестратор продолжит работу автоматически."
    else
        echo -e "  Для управления введите: ${CYAN}${BOLD}ip-roll${NC}\n"
    fi
}

# ── Точка входа ──────────────────────────────────────────────
print_banner

if [ "$AUTOINSTALL" = "1" ]; then
    # ── Автоматический режим (вызван оркестратором) ──────────
    if is_installed; then
        echo -e "${GREEN}[✓] selectel_roller уже установлен. Пропускаю.${NC}"
        exit 0
    fi
    echo -e "${YELLOW}[*] Автоматическая установка...${NC}"
    do_install
else
    # ── Интерактивный режим ──────────────────────────────────
    if is_installed; then
        echo -e "${GREEN}[✓] Уже установлено.${NC} Открываю меню...\n"
        sleep 1
        bash "$INSTALL_DIR/menu.sh"
    else
        do_install
    fi
fi
