#!/bin/bash

# Остановка при критических ошибках
set -e

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Очистка экрана перед запуском
clear

# Красивый ASCII заголовок NUNK SPACE
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
echo -e "${GREEN}=== Установка глупой ноды Remnawave (Без SSL) ===${NC}\n"

# Интерактивное меню
echo "Выберите действие:"
echo "1) Установить / Обновить ноду"
echo "2) Удалить ноду"
echo "3) Выход"
read -p "Ваш выбор [1-3]: " MENU_CHOICE

if [ "$MENU_CHOICE" == "3" ]; then
    echo "Выход..."
    exit 0
elif [ "$MENU_CHOICE" == "2" ]; then
    echo -e "\n${YELLOW}Удаление ноды...${NC}"
    cd /opt/remnanode 2>/dev/null && sudo docker compose down 2>/dev/null || true
    sudo rm -rf /opt/remnanode
    sudo ufw delete allow 2222/tcp 2>/dev/null || true
    echo -e "${GREEN}Нода успешно удалена!${NC}"
    exit 0
elif [ "$MENU_CHOICE" != "1" ]; then
    echo -e "${RED}Неверный выбор. Выход.${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}--- Сбор данных ---${NC}"
# Запрос данных у пользователя
read -p "Введите домен вашей ПАНЕЛИ (например, remna.nunk.space): " PANEL_DOMAIN
read -p "Введите SECRET_KEY для связи с панелью: " SECRET_KEY

echo ""
echo -e "${GREEN}Начинаем установку...${NC}"
echo "=============================="

# 1. Обновление системы
echo -e "${CYAN}[1/5] Обновление пакетов системы...${NC}"
sudo apt update && sudo apt upgrade -y

# 2. Установка Docker
echo -e "${CYAN}[2/5] Установка Docker...${NC}"
if ! command -v docker &> /dev/null; then
    sudo curl -fsSL https://get.docker.com | sh
else
    echo "Docker уже установлен, пропускаем..."
fi

# 3. Настройка Firewall (UFW) для защиты порта 2222
echo -e "${CYAN}[3/5] Настройка защиты порта (UFW)...${NC}"
# Устанавливаем UFW, если его нет
sudo apt-get install -y ufw >/dev/null 2>&1

# Пытаемся получить IP-адрес панели из введенного домена
PANEL_IP=$(getent hosts "$PANEL_DOMAIN" | awk '{ print $1 }' | head -n 1)

if [ -n "$PANEL_IP" ]; then
    echo -e "IP панели успешно определён: ${GREEN}$PANEL_IP${NC}"
    echo "Разрешаем доступ к порту 2222 только с этого IP..."

    # Включаем UFW, разрешаем SSH и порты для VPN, а 2222 только для панели
    sudo ufw allow 22/tcp >/dev/null 2>&1   # Обязательно оставляем SSH!
    sudo ufw allow 80/tcp >/dev/null 2>&1
    sudo ufw allow 443 >/dev/null 2>&1      # Для Xray/Hysteria

    # Удаляем старые правила для 2222 (если были) и добавляем новое строгое
    sudo ufw delete allow 2222/tcp >/dev/null 2>&1 || true
    sudo ufw allow from "$PANEL_IP" to any port 2222 proto tcp >/dev/null 2>&1

    # Включаем файрвол (force, чтобы не спрашивал подтверждения)
    sudo ufw --force enable >/dev/null 2>&1
else
    echo -e "${RED}Не удалось определить IP из домена $PANEL_DOMAIN.${NC}"
    echo "Порт 2222 будет открыт для всех."
    sudo ufw allow 2222/tcp >/dev/null 2>&1
fi


# 4. Настройка и запуск Remnanode
echo -e "${CYAN}[4/5] Создание конфигурации Remnanode...${NC}"
sudo mkdir -p /opt/remnanode
cd /opt/remnanode

# Создание docker-compose.yml (без монтирования сертификатов!)
sudo cat <<EOF > /opt/remnanode/docker-compose.yml
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
      - SECRET_KEY="$SECRET_KEY"
EOF

# 5. Запуск контейнера
echo -e "${CYAN}[5/5] Запуск ноды...${NC}"
sudo docker compose down 2>/dev/null || true
sudo docker compose up -d

echo ""
echo "======================================================="
echo -e "${GREEN}✨ Установка успешно завершена! ✨${NC}"
echo "======================================================="
echo -e "Нода работает в режиме 'Глупой ноды' (сертификаты доставит панель)."
if [ -n "$PANEL_IP" ]; then
    echo -e "Порт 2222 защищен: доступ разрешен только для IP ${CYAN}$PANEL_IP${NC}."
fi
echo -e "Проверить логи ноды можно командой: ${YELLOW}sudo docker logs -f remnanode${NC}"
echo "Теперь идите в веб-интерфейс панели и привяжите эту ноду!"