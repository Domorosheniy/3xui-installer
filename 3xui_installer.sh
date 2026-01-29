#!/usr/bin/env bash
set -euo pipefail

# ========== ИНТЕРАКТИВНЫЙ ВВОД ==========
clear
echo "=== Ubuntu 22.04 + 3x-ui (FULL SECURITY) ==="
echo ""

# 1. Проверка root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Запусти от root: sudo bash $0"
  exit 1
fi

# 2. Проверка ОС
if ! grep -qi "ubuntu" /etc/os-release || ! grep -q "22.04" /etc/os-release; then
  echo "❌ Только Ubuntu 22.04"
  exit 1
fi

# Функция запроса с валидацией
ask_input() {
  local prompt="$1"
  local default="$2"
  local validator="$3"
  local input=""
  
  while true; do
    if [[ -n "$default" ]]; then
      read -p "$prompt [$default]: " input
      [[ -z "$input" ]] && input="$default"
    else
      read -p "$prompt: " input
    fi
    
    if [[ "$validator" == "non_empty" && -z "$input" ]]; then
      echo "❌ Поле не может быть пустым!"
      continue
    elif [[ "$validator" == "port" ]]; then
      if [[ ! "$input" =~ ^[0-9]+$ ]] || [[ "$input" -lt 1 || "$input" -gt 65535 ]]; then
        echo "❌ Порт должен быть числом от 1 до 65535"
        continue
      fi
    elif [[ "$validator" == "username" ]]; then
      if [[ ! "$input" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        echo "❌ Имя пользователя должно начинаться с буквы и содержать только a-z, 0-9, _, -"
        continue
      fi
    fi
    
    break
  done
  
  echo "$input"
}

# Запрос данных у пользователя
echo "📝 Введите параметры установки:"
echo "--------------------------------"
USER_NAME=$(ask_input "Имя нового пользователя" "user" "username")
USER_PASS=$(ask_input "Пароль пользователя (для sudo/emergency)" "user" "non_empty")
SSH_PORT=$(ask_input "Кастомный SSH порт (НЕ 22!)" "40024" "port")
PANEL_PORT=$(ask_input "Порт панели 3x-ui" "54321" "port")

# Подтверждение
echo ""
echo "=== ПОДТВЕРЖДЕНИЕ ==="
echo "👤 Пользователь: $USER_NAME"
echo "🔑 Пароль: $USER_PASS"
echo "🔐 SSH порт: $SSH_PORT"
echo "🌐 Порт панели: $PANEL_PORT"
echo ""

read -p "Начать установку? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "❌ Установка отменена"
  exit 0
fi

# ========== НАСТРОЙКИ ==========
echo "=== Ubuntu 22.04 + 3x-ui (FULL SECURITY) ==="

# 1. ВРЕМЯ (фикс x509)
echo "[1/9] ⏰ Время и NTP..."
timedatectl set-timezone Europe/Moscow
timedatectl set-ntp true
apt install -y ca-certificates
update-ca-certificates

# 2. Система
echo "[2/9] 🔄 Обновление..."
apt update -y && apt upgrade -y -o Dpkg::Options::="--force-confold"

# 3. 🔐 ПОЛЬЗОВАТЕЛЬ + SSH КЛЮЧИ
echo "[3/9] 👤 Пользователь $USER_NAME..."
if id "$USER_NAME" &>/dev/null; then
  echo "⚠️  Пользователь $USER_NAME уже существует, меняем пароль"
else
  useradd -m -s /bin/bash "$USER_NAME"
fi
echo "$USER_NAME:$USER_PASS" | chpasswd
usermod -aG sudo "$USER_NAME"

# Копируем SSH ключи (ТОЛЬКО ключи!)
mkdir -p "/home/$USER_NAME/.ssh"
cp /root/.ssh/authorized_keys "/home/$USER_NAME/.ssh/" 2>/dev/null || true
chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.ssh"
chmod 700 "/home/$USER_NAME/.ssh"
chmod 600 "/home/$USER_NAME/.ssh/authorized_keys" 2>/dev/null || true

# 4. 🔒 SSH: МАКСИМАЛЬНАЯ БЕЗОПАСНОСТЬ
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

# 5. 🛡️ UFW
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
ufw status numbered

# 6. 🔑 Сертификат
echo "[6/9] 📜 SSL сертификат..."
mkdir -p /etc/ssl/certs
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout /etc/ssl/certs/3x-ui.key \
  -out /etc/ssl/certs/3x-ui.pem \
  -subj "/C=RU/ST=./L=./O=3x-ui/OU=3x-ui/CN=$(hostname -f)"
chmod 600 /etc/ssl/certs/3x-ui.key

# 7. 🌐 3x-ui
echo "[7/9] 🚀 3x-ui..."
apt install -y curl
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<EOF
y
$PANEL_PORT
EOF

# 8. ✅ ПРОВЕРКА
echo "[8/9] ✅ ПРОВЕРКА..."
x-ui status
ufw status numbered

# 9. 📋 ИТОГО + СОХРАНЕНИЕ КОНФИГА
CONFIG_FILE="/root/3x-ui-install-config.txt"
cat <<EOF > "$CONFIG_FILE"
=== 3x-UI УСТАНОВКА ===
Дата: $(date)
Пользователь: $USER_NAME
Пароль: $USER_PASS
SSH порт: $SSH_PORT
Порт панели: $PANEL_PORT
---
🔗 SSH: ssh -p $SSH_PORT $USER_NAME@$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
🔑 Пароль '$USER_PASS' ТОЛЬКО для sudo/emergency!
🌐 Панель: https://$(curl -s ifconfig.me || hostname -I | awk '{print $1}'):$PANEL_PORT
⚠️ Inbound порты: 443, 8443, 2053
⚠️ Панель — Настройки — Сертификаты:
  Публичный ключ: /etc/ssl/certs/3x-ui.pem
  Приватный ключ: /etc/ssl/certs/3x-ui.key
EOF

cat <<EOF
[9/9] 🎉 УСТАНОВКА ЗАВЕРШЕНА!

🔗 SSH: ssh -p $SSH_PORT $USER_NAME@$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
🔑 Пароль '$USER_PASS' ТОЛЬКО для sudo/emergency!
🌐 Панель: https://$(curl -s ifconfig.me || hostname -I | awk '{print $1}'):$PANEL_PORT
⚠️ Inbound порты: 443,8443,2053 (НЕ $PANEL_PORT!)
⚠️ Панель — Настройки — Сертификаты — вставить пути:
⚠️ Публичный ключ: /etc/ssl/certs/3x-ui.pem
⚠️ Приватный ключ: /etc/ssl/certs/3x-ui.key
⏰ Время: $(timedatectl | head -1)

📁 Конфиг сохранен: $CONFIG_FILE

🧪 Тесты:
  x-ui status
  x-ui log
  ss -tulpn | grep :$SSH_PORT
  ssh -p $SSH_PORT $USER_NAME@localhost  # тест ключа
EOF