# 🚀 3x-ui Автоустановка на Ubuntu 22.04 

## 🛡 Установка с проверкой (рекомендуется)

1. Скачать скрипт:  
curl -fsSL -o install.sh https://raw.githubusercontent.com/Domorosheniy/3xui-installer/refs/heads/main/3xui_installer.sh

2. (Необязательно) Открыть и посмотреть содержимое. Можно изменить порт, логин, пароль:  
nano install.sh

3. Сделать исполняемым и запустить:  
  chmod +x install.sh  
  sudo ./install.sh 

## 🔥 Установка одной командой:
curl -fSL --retry 5 --retry-delay 2 --connect-timeout 10 -o 3xui_installer.sh https://raw.githubusercontent.com/Domorosheniy/3xui-installer/refs/heads/main/3xui_installer.sh && chmod +x 3xui_installer.sh && sudo ./3xui_installer.sh

- ✅ SSH: порт 40024, только ключи, без root  
- 👤 Пользователь: user, Пароль: user  
- 🔐 Путь к публичному ключу: `/etc/ssl/certs/3x-ui.pem`  
- 🔐 Путь к приватному ключу: `/etc/ssl/certs/3x-ui.key`  
- 🌐 Панель PORT: 54321  
- 🔥 UFW, время, SSL — всё настроено
