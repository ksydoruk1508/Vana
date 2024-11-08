#!/bin/bash

# Цвета текста
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # Нет цвета (сброс цвета)

# Установка ноды Vana
function install_vana_node {
    echo -e "${BLUE}Обновляем систему и устанавливаем необходимые инструменты...${NC}"
    sudo apt-get update -y && sudo apt-get upgrade -y
    sudo apt-get install git unzip nano -y
    sudo apt-get install software-properties-common -y
    sudo add-apt-repository ppa:deadsnakes/ppa -y
    sudo apt-get update
    sudo apt-get install python3.11 -y
    echo -e "${GREEN}Python установлен: $(python3.11 --version)${NC}"
    sudo apt install python3-pip python3-venv curl -y
    curl -sSL https://install.python-poetry.org | python3 -
    export PATH="$HOME/.local/bin:$PATH"
    source ~/.bashrc
    echo -e "${GREEN}Poetry установлен: $(poetry --version)${NC}"

    echo -e "${BLUE}Устанавливаем Node.js и npm...${NC}"
    curl -fsSL https://fnm.vercel.app/install | bash
    source ~/.bashrc
    fnm use --install-if-missing 22
    echo -e "${GREEN}Node.js и npm установлены: $(node -v && npm -v)${NC}"
    sudo apt-get install nodejs -y
    npm install -g yarn
    echo -e "${GREEN}Yarn установлен: $(yarn --version)${NC}"

    echo -e "${BLUE}Клонируем репозиторий и заходим в него...${NC}"
    git clone https://github.com/vana-com/vana-dlp-chatgpt.git
    cd vana-dlp-chatgpt || exit
    cp .env.example .env
    echo -e "${BLUE}Устанавливаем зависимости...${NC}"
    poetry install
    echo -e "${BLUE}Устанавливаем CLI...${NC}"
    pip install vana
    echo -e "${GREEN}Установка ноды Vana завершена!${NC}"
}

# Создание кошелька и экспорт приватных ключей
function create_and_export_wallet_keys {
    echo -e "${BLUE}Выберите способ работы с кошельком:${NC}"
    echo -e "${CYAN}1. Создать новый кошелек${NC}"
    echo -e "${CYAN}2. Импортировать существующие ключи${NC}"
    read -r wallet_choice
    case $wallet_choice in
        1)
            echo -e "${BLUE}Создаем кошелек...${NC}"
            vanacli wallet create --wallet.name default --wallet.hotkey default
            echo -e "${BLUE}Экспортируем приватные ключи...${NC}"
            vanacli wallet export_private_key --wallet.name default --key.type coldkey --accept-risk yes
            vanacli wallet export_private_key --wallet.name default --key.type hotkey --accept-risk yes
            ;;
        2)
            echo -e "${YELLOW}Введите ваш приватный ключ или мнемонику Coldkey:${NC}"
            vanacli wallet regen_coldkey --wallet.name default
            echo -e "${YELLOW}Введите ваш приватный ключ или мнемонику Hotkey:${NC}"
            vanacli wallet regen_hotkey --wallet.name default
            echo -e "${GREEN}Ключи успешно импортированы!${NC}"
            ;;
        *)
            echo -e "${RED}Неверный выбор, попробуйте снова.${NC}"
            create_and_export_wallet_keys
            ;;
    esac
}

# Генерация ключей для валидатора
function generate_keys {
    echo -e "${BLUE}Генерация ключей для валидатора...${NC}"
    ./keygen.sh
}

# Деплой смарт-контракта DLP
function deploy_smart_contract {
    echo -e "${BLUE}Удаляем старую папку для деплоя и скачиваем новую...${NC}"
    cd $HOME
    rm -rf vana-dlp-smart-contracts
    git clone https://github.com/Josephtran102/vana-dlp-smart-contracts
    cd vana-dlp-smart-contracts || exit
    npm install -g yarn
    yarn install
    cp .env.example .env
    nano .env
    echo -e "${BLUE}Деплоим контракт...${NC}"
    npx hardhat deploy --network moksha --tags DLPDeploy
}

# Установка валидатора
function install_validator {
    echo -e "${BLUE}Регистрируем валидатора...${NC}"
    ./vanacli dlp register_validator --stake_amount 10
    echo -e "${YELLOW}Введите ваш адрес кошелька Hotkey:${NC}"
    read -r validator_address
    ./vanacli dlp approve_validator --validator_address=$validator_address
    echo -e "${BLUE}Запускаем валидатор...${NC}"
    poetry run python -m chatgpt.nodes.validator
}

# Создание и запуск сервиса для валидатора
function create_validator_service {
    echo -e "${BLUE}Создаем сервисный файл для валидатора...${NC}"
    SERVICE_PATH=$(which poetry)
    sudo tee /etc/systemd/system/vana.service << EOF
[Unit]
Description=Vana Validator Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/vana-dlp-chatgpt
ExecStart=${SERVICE_PATH} run python -m chatgpt.nodes.validator
Restart=on-failure
RestartSec=10
Environment=PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin:/root/vana-dlp-chatgpt/myenv/bin
Environment=PYTHONPATH=/root/vana-dlp-chatgpt

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable vana.service
    sudo systemctl start vana.service
    sudo systemctl status vana.service
}

# Удаление ноды Vana
function remove_vana_node {
    echo -e "${BLUE}Удаление ноды Vana...${NC}"
    if [ -d "$HOME/vana-dlp-chatgpt" ]; then
        cd $HOME/vana-dlp-chatgpt || exit
        sudo systemctl stop vana.service
        sudo systemctl disable vana.service
        sudo rm /etc/systemd/system/vana.service
        sudo systemctl daemon-reload
        cd $HOME
        rm -rf vana-dlp-chatgpt
        echo -e "${GREEN}Нода Vana успешно удалена!${NC}"
    else
        echo -e "${RED}Нода Vana не найдена.${NC}"
    fi
}

# Главное меню
function main_menu {
    while true; do
        echo -e "${YELLOW}Выберите действие:${NC}"
        echo -e "${CYAN}1. Установка ноды Vana${NC}"
        echo -e "${CYAN}2. Создание или импорт кошелька и ключей${NC}"
        echo -e "${CYAN}3. Генерация ключей валидатора${NC}"
        echo -e "${CYAN}4. Деплой смарт-контракта DLP${NC}"
        echo -e "${CYAN}5. Установка валидатора${NC}"
        echo -e "${CYAN}6. Создание сервиса валидатора${NC}"
        echo -e "${CYAN}7. Удаление ноды Vana${NC}"
        echo -e "${CYAN}8. Выход${NC}"
       
        echo -e "${YELLOW}Введите номер действия:${NC} "
        read -r choice
        case $choice in
            1) install_vana_node ;;
            2) create_and_export_wallet_keys ;;
            3) generate_keys ;;
            4) deploy_smart_contract ;;
            5) install_validator ;;
            6) create_validator_service ;;
            7) remove_vana_node ;;
            8) break ;;
            *) echo -e "${RED}Неверный выбор, попробуйте снова.${NC}" ;;
        esac
    done
}

main_menu
