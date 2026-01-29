#!/usr/bin/env bash
set -euo pipefail

# ========== ИНТЕРАКТИВНЫЙ ВВОД ==========
if [[ $EUID -ne 0 ]]; then
  echo "Запусти от root: sudo bash $0"
  exit 1
fi

echo "=== Ubuntu 22.04 + 3x-ui (FULL SECURITY) ==="
echo ""

# Запрос данных
read -p "Имя нового пользователя [user]: " USER_NAME
USER_NAME=${USER_NAME:-user}

read -p "Пароль пользователя (для sudo/emergency) [user]: " USER_PASS
USER_PASS=${USER_PASS:-user}

read -p "Кастомный SSH порт (НЕ 22!) [40024]: " SSH_PORT
SSH_PORT=${SSH_PORT:-40024}

read -p "Порт панели 3x-ui [54321]: " PANEL_PORT
PANEL_PORT=${PANEL_PORT:-54321}

# ========== ОРИГИНАЛЬНЫЙ СКРИПТ БЕЗ ИЗМЕНЕНИЙ ==========
if [[ $EUID -ne 0 ]]; then
  echo "Запусти от root: sudo bash $0"
  exit 1
fi

echo "=== Ubuntu 22.04 + 3x-ui (FULL SECURITY) ==="

# 1. Проверка ОС
if ! grep -qi "ubuntu" /etc/os-release || ! grep -q "22.04" /etc/os-release; then
  echo "❌ Только Ubuntu 22.04"
  exit 1
fi

# 2. ВРЕМЯ (фикс x509)
echo "[1/9] ⏰ Время и NTP..."
timedatectl set-timezone Europe/Moscow
timedatectl set-ntp true
apt install -y ca-certificates
update-ca-certificates

# 3. Система
echo "[2/9] 🔄 Обновление..."
apt update -y && apt upgrade -y -o Dpkg::Options::="--force-confold"

# 4. 🔐 ПОЛЬЗОВАТЕЛЬ + SSH КЛЮЧИ
echo "[3/9] 👤 Пользователь $USER_NAME..."
id "$USER_NAME" &>/dev/null || useradd -m -s /bin/bash "$USER_NAME"
echo "$USER_NAME:$USER_PASS" | chpasswd
usermod -aG sudo "$USER_NAME"

# Копируем SSH ключи (ТОЛЬКО ключи!)
mkdir -p "/home/$USER_NAME/.ssh"
cp /root/.ssh/authorized_keys "/home/$USER_NAME/.ssh/" 2>/dev/null || true
chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.ssh"
chmod 700 "/home/$USER_NAME/.ssh"
chmod 600 "/home/$USER_NAME/.ssh/authorized_keys" 2>/dev/null || true

# 5. 🔒 SSH: МАКСИМАЛЬНАЯ БЕЗОПАСНОСТЬ
echo "[4/9] 🛡️ SSH (только ключи, без root, порт $SSH_PORT)..."
SSHD_CFG="/etc/ssh/sshd_config"

# Бэкап
cp "$SSHD_CFG" "${SSHD_CFG}.backup"

# Настройки безопасности
sed -i "s/^#*Port .*/Port $SSH_PORT/" "$SSHD_CFG"
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' "$SSHD_CFG"
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' "$SSHD_CFG"
sed -i 's/^#*PubkeyAuthentication .*/PubkeyAuthentication yes/' "$SSHD_CFG"
sed -i 's/^#*PermitEmptyPasswords .*/PermitEmptyPasswords no/' "$SSHD_CFG"
sed -i 's/^#*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' "$SSHD_CFG"

# Отключаем socket activation
systemctl stop ssh.socket 2>/dev/null || true
systemctl disable ssh.socket 2>/dev/null || true
systemctl mask ssh.socket 2>/dev/null || true

systemctl restart ssh
sleep 2
echo "SSH статус: $(systemctl is-active ssh)"

# 6. 🛡️ UFW
echo "[5/9] 🔥 UFW..."
apt install -y ufw
ufw --force reset

ufw allow "$SSH_PORT/tcp"    # ✅ Новый SSH
ufw allow 80/tcp             # HTTP
ufw allow 443/tcp            # HTTPS + inbound
ufw allow 8080/tcp           # доп. веб
ufw allow 8443/tcp           # inbound
ufw allow 2053/tcp           # inbound
ufw allow "$PANEL_PORT/tcp"  # ✅ ПАНЕЛЬ
ufw deny 22/tcp              # ✅ ЗАКРЫВАЕМ 22!
ufw --force enable

echo "UFW:"
ufw status

# 7. 🔑 Сертификат
echo "[6/9] 📜 SSL сертификат..."
mkdir -p /etc/ssl/certs
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout /etc/ssl/certs/3x-ui.key \
  -out /etc/ssl/certs/3x-ui.pem \
  -subj "/C=RU/ST=./L=./O=3x-ui/OU=3x-ui/CN=$(hostname -f)"

# 8. 🌐 3x-ui
echo "[7/9] 🚀 3x-ui..."
apt install -y curl
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<EOF
y
$PANEL_PORT
EOF

# 9. ✅ ПРОВЕРКА
echo "[8/9] ✅ ПРОВЕРКА..."
x-ui status
ufw status

# 10. 📋 ИТОГО
cat <<EOF
[9/9] 🎉 УСТАНОВКА ЗАВЕРШЕНА!

🔗 SSH: ssh -p $SSH_PORT $USER_NAME@IP_СЕРВЕРА
🔑 Пароль '$USER_PASS' ТОЛЬКО для sudo/emergency!
🌐 Панель: http://IP_СЕРВЕРА:$PANEL_PORT
⚠️ Inbound: 443,8443,2053 (НЕ $PANEL_PORT!)
⚠️ Панель — Настройки — Сертификаты — вставить пути:
⚠️ Публичный ключ: /etc/ssl/certs/3x-ui.pem
⚠️ Приватный ключ: /etc/ssl/certs/3x-ui.key
⏰ Время: $(timedatectl | head -1)

🧪 Тесты:
  x-ui status
  x-ui log
  ss -tulpn | grep :$SSH_PORT
  ssh -p $SSH_PORT $USER_NAME@localhost  # тест ключа
EOF