#!/bin/bash

# Остановка при ошибках
set -e

echo "=== Установка ноды Remnawave ==="
echo ""

# Запрос данных у пользователя
read -p "Введите домен вашей ноды (например, node.example.com): " DOMAIN
read -p "Введите Email для SSL сертификата Let's Encrypt: " EMAIL
read -p "Введите SECRET_KEY (private-key) для ноды: " SECRET_KEY

echo ""
echo "Начинаем установку..."
echo "=============================="

# 1. Обновление системы
echo "[1/6] Обновление пакетов системы..."
sudo apt update && sudo apt upgrade -y

# 2. Установка Docker
echo "[2/6] Установка Docker..."
if ! command -v docker &> /dev/null; then
    sudo curl -fsSL https://get.docker.com | sh
else
    echo "Docker уже установлен, пропускаем..."
fi

# 3. Настройка Certbot
echo "[3/6] Настройка Certbot..."
sudo mkdir -p /opt/certbot
cd /opt/certbot

# Создание docker-compose.yml для certbot
sudo cat <<EOF > /opt/certbot/docker-compose.yml
services:
  certbot:
    container_name: certbot
    image: certbot/certbot
    network_mode: host
    volumes:
      - ./certs:/etc/letsencrypt
EOF

# 4. Получение SSL сертификата
echo "[4/6] Получение SSL сертификата для домена $DOMAIN..."
sudo docker run --rm \
  -v /opt/certbot/certs:/etc/letsencrypt \
  -v /opt/certbot/var-lib-letsencrypt:/var/lib/letsencrypt \
  --network host \
  certbot/certbot certonly --standalone \
  --non-interactive --agree-tos \
  --email "$EMAIL" \
  -d "$DOMAIN"

# 5. Настройка и запуск Remnanode
echo "[5/6] Настройка и запуск Remnanode..."
sudo mkdir -p /opt/remnanode
cd /opt/remnanode

# Создание docker-compose.yml для remnanode
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
    volumes:
      - /opt/certbot/certs:/etc/letsencrypt:ro
EOF

# Запуск контейнера
sudo docker compose down 2>/dev/null || true
sudo docker compose up -d

# 6. Настройка Cron для автопродления сертификата
echo "[6/6] Настройка автопродления SSL сертификата (cron)..."
# Проверяем, есть ли уже такая задача в cron, чтобы не дублировать
CRON_JOB="0 0 28 * * cd /opt/certbot && docker compose run --rm certbot renew"
(crontab -l 2>/dev/null | grep -F "$CRON_JOB") || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo "=============================="
echo "Установка успешно завершена!"
echo "Нода запущена и работает на порту 2222."
echo "Проверить логи ноды можно командой: sudo docker logs -f remnanode"