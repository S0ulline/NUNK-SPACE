#!/bin/bash
#
# Единый установщик для Ubuntu:
#   1) Блокировка входящих коннектов из Индии (ipset + iptables + cron)
#   2) Установка и настройка telemt (MTProto)
#   3) Интерактивный MTProto fix
#
# Запуск:  sudo bash install_telemt.sh
#
set -euo pipefail

# ───────────────────────────── проверки ─────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo "Скрипт нужно запускать от root:  sudo bash $0"
    exit 1
fi

echo "=================================================================="
echo "  Установщик telemt + блокировка Индии"
echo "=================================================================="
echo

# ──────────────────────── интерактивный ввод ────────────────────────
read -rp "ad_tag (32 hex-символа, из @MTProxybot): " AD_TAG
while ! [[ "$AD_TAG" =~ ^[0-9a-fA-F]{32}$ ]]; do
    echo "  ! ad_tag должен быть ровно 32 hex-символа."
    read -rp "ad_tag: " AD_TAG
done

read -rp "tls_domain (напр. www.microsoft.com): " TLS_DOMAIN
while [ -z "$TLS_DOMAIN" ]; do
    read -rp "tls_domain: " TLS_DOMAIN
done

read -rp "secret 'hello' (32 hex; Enter — сгенерировать): " HELLO
if [ -z "$HELLO" ]; then
    HELLO="$(openssl rand -hex 16)"
    echo "  → сгенерирован secret: $HELLO"
elif ! [[ "$HELLO" =~ ^[0-9a-fA-F]{32}$ ]]; then
    echo "  ! secret должен быть 32 hex-символа."
    exit 1
fi

read -rp "Порт прокси [443]: " PORT
PORT="${PORT:-443}"

echo
echo "Параметры:  port=$PORT  domain=$TLS_DOMAIN"
echo

# ════════════════════ 1. БЛОКИРОВКА КОННЕКТОВ ИЗ ИНДИИ ═══════════════
echo ">>> [1/3] Блокировка Индии"

apt update
apt install -y ipset curl jq iptables openssl

# --- пишем /usr/local/bin/block_india.sh ---
# первый heredoc (без кавычек) подставляет выбранный порт
cat > /usr/local/bin/block_india.sh <<EOF
#!/bin/bash
# Порт, на котором работает telemt
PROXY_PORT=${PORT}
EOF

# второй heredoc (в кавычках) — тело без подстановок ($line / $PROXY_PORT остаются как есть)
cat >> /usr/local/bin/block_india.sh <<'EOF'

# Создаём основной сет, если его ещё нет
ipset create india hash:net 2>/dev/null

# Создаём временный сет для загрузки обновлений
ipset create india_temp hash:net 2>/dev/null
ipset flush india_temp

echo "Загрузка актуальных IP-адресов Индии..."
# Скачиваем подсети с агрегатора ipverse.net
curl -s https://www.ipverse.net/ipblocks/data/countries/in.zone | grep -v "^#" | while read line; do
    if [ ! -z "$line" ]; then
        ipset add india_temp $line 2>/dev/null
    fi
done

# Атомарно меняем старый список на новый (без сбоев в работе файрвола)
ipset swap india_temp india
ipset destroy india_temp

# Добавляем правило в iptables, если его ещё нет
if ! iptables -C INPUT -p tcp --dport $PROXY_PORT -m set --match-set india src -j DROP 2>/dev/null; then
    iptables -I INPUT -p tcp --dport $PROXY_PORT -m set --match-set india src -j DROP
    echo "Правило блокировки для порта $PROXY_PORT добавлено в iptables."
else
    echo "Правило для порта $PROXY_PORT уже существует."
fi
EOF

chmod +x /usr/local/bin/block_india.sh

# первый прогон
/usr/local/bin/block_india.sh

# --- cron: @reboot и ежедневное обновление в 03:00, без дублей ---
CRON_TMP="$(mktemp)"
crontab -l 2>/dev/null > "$CRON_TMP" || true
if ! grep -q '/usr/local/bin/block_india.sh' "$CRON_TMP"; then
    echo '@reboot /usr/local/bin/block_india.sh'   >> "$CRON_TMP"
    echo '0 3 * * * /usr/local/bin/block_india.sh'  >> "$CRON_TMP"
    crontab "$CRON_TMP"
    echo "cron-задания добавлены."
else
    echo "cron-задания уже присутствуют."
fi
rm -f "$CRON_TMP"

echo "Проверка сета (первые строки):"
ipset list india | head -n 10
echo

# ══════════════════════════ 2. УСТАНОВКА telemt ══════════════════════
echo ">>> [2/3] Установка telemt"

cd /tmp
wget -qO- "https://github.com/telemt/telemt/releases/latest/download/telemt-$(uname -m)-linux-$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu).tar.gz" | tar -xz
mv -f telemt /bin/telemt
chmod +x /bin/telemt

mkdir -p /etc/telemt

# --- конфиг telemt.toml (подстановка введённых значений) ---
cat > /etc/telemt/telemt.toml <<EOF
[general]
use_middle_proxy = true
log_level = "normal"
ad_tag = "${AD_TAG}"

[general.modes]
classic = false
secure = false
tls = true

[general.links]
show = "*"

[server]
port = ${PORT}

[server.api]
enabled = true
listen = "127.0.0.1:9091"
whitelist = ["127.0.0.1/32", "::1/128"]
minimal_runtime_enabled = false
minimal_runtime_cache_ttl_ms = 1000

[[server.listeners]]
ip = "0.0.0.0"

[censorship]
tls_domain = "${TLS_DOMAIN}"
mask = true
tls_emulation = true
tls_front_dir = "tlsfront"
unknown_sni_action = "reject_handshake"

[access.users]
# format: "username" = "32_hex_chars_secret"
hello = "${HELLO}"
EOF

# --- пользователь telemt (идемпотентно) ---
if ! id telemt >/dev/null 2>&1; then
    useradd -d /opt/telemt -m -r -U telemt
fi
chown -R telemt:telemt /etc/telemt
chmod 600 /etc/telemt/telemt.toml

# --- systemd unit ---
cat > /etc/systemd/system/telemt.service <<'EOF'
[Unit]
Description=Telemt
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=telemt
Group=telemt
WorkingDirectory=/opt/telemt
ExecStart=/bin/telemt /etc/telemt/telemt.toml
Restart=on-failure
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable telemt
systemctl start telemt

# даём демону подняться и забираем ссылки через API
sleep 2
echo
echo "Ссылки для подключения:"
curl -s http://127.0.0.1:9091/v1/users \
  | jq -r '.data[] | "[\(.username)]", (.links.classic[]? | "classic: \(.)"), (.links.secure[]? | "secure: \(.)"), (.links.tls[]? | "tls: \(.)"), ""' \
  || echo "  (API ещё не ответил — проверьте позже: curl -s http://127.0.0.1:9091/v1/users | jq)"

echo
systemctl status telemt --no-pager || true
echo

# ═══════════════════════════ 3. MTProto FIX ═════════════════════════
echo ">>> [3/3] Интерактивный MTProto fix"
read -rp "Запустить внешний MTProto fix (curl | bash из репозитория Mekotofeuka)? [y/N]: " RUN_FIX
if [[ "$RUN_FIX" =~ ^[yYдД]$ ]]; then
    curl -fsSL https://raw.githubusercontent.com/Mekotofeuka/MTPROTO_FIX_By_MEKO/main/install.sh | bash
else
    echo "Пропущено. При необходимости запустите вручную:"
    echo "  curl -fsSL https://raw.githubusercontent.com/Mekotofeuka/MTPROTO_FIX_By_MEKO/main/install.sh | sudo bash"
fi

echo
echo "=================================================================="
echo "  Готово."
echo "=================================================================="
