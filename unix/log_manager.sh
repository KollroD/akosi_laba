#!/bin/bash

GREEN='\e[32m'
YELLOW='\e[33m'
RED='\e[31m'
BLUE='\e[34m'
NC='\e[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}[*] Скрипту требуются права root для работы с виртуальными дисками.${NC}"
    echo -e "${YELLOW}[*] Введите пароль для sudo:${NC}"
    exec sudo bash "$0" "$@"
    exit $?
fi

if [ "$#" -ne 4 ]; then
    echo -e "${BLUE}=== Умный менеджер логов ===${NC}"
    echo -e "Использование: $0 <путь> <размер_МБ> <порог_%> <кол-во_файлов>"
    echo -e "Пример: $0 ./log 40 80 5"
    exit 1
fi

LOG_DIR=$(realpath -m "$1")
DISK_SIZE_MB=$2
THRESHOLD=$3
M_FILES=$4
BACKUP_DIR="$(pwd)/backup_archives"
IMAGE_FILE="${LOG_DIR}_disk.img"

echo -e "${BLUE}[*] Инициализация менеджера логов для $LOG_DIR...${NC}"

if ! mountpoint -q "$LOG_DIR"; then
    echo -e "${YELLOW}[!] Папка не является отдельным разделом.${NC}"
    echo -e "${YELLOW}[*] Создаем изолированный виртуальный диск на $DISK_SIZE_MB МБ...${NC}"
    
    mkdir -p "$LOG_DIR"
    
    TEMP_BACKUP=$(mktemp -d)
    cp -a "$LOG_DIR/." "$TEMP_BACKUP/" 2>/dev/null
    
    dd if=/dev/zero of="$IMAGE_FILE" bs=1M count="$DISK_SIZE_MB" status=none
    mkfs.ext4 -F -q "$IMAGE_FILE"
    mount -o loop "$IMAGE_FILE" "$LOG_DIR"
    
    cp -a "$TEMP_BACKUP/." "$LOG_DIR/"
    rm -rf "$TEMP_BACKUP"
    
    echo -e "${GREEN}[+] Виртуальный диск успешно примонтирован!${NC}"
fi

USAGE=$(df -P "$LOG_DIR" | awk 'NR==2 {print $5}' | tr -d '%')
echo -e "\n${BLUE}Текущая занятость диска: ${USAGE}%${NC} (Порог срабатывания: ${THRESHOLD}%)"

if [ "$USAGE" -ge "$THRESHOLD" ]; then
    echo -e "${YELLOW}[!] Занятость превысила порог. Начинаем архивацию...${NC}"
    
    mkdir -p "$BACKUP_DIR"
    
    FILES_TO_ARCHIVE=$(find "$LOG_DIR" -maxdepth 1 -type f -printf '%f\n' | sort | head -n "$M_FILES")
    
    if [ -z "$FILES_TO_ARCHIVE" ]; then
        echo -e "${YELLOW}[!] В директории нет файлов для архивации.${NC}"
        exit 0
    fi

    ARCHIVE_NAME="$BACKUP_DIR/archive_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    if (cd "$LOG_DIR" && tar -czf "$ARCHIVE_NAME" $FILES_TO_ARCHIVE); then
        echo -e "${GREEN}[+] Заархивировано старых файлов в: $ARCHIVE_NAME${NC}"
        (cd "$LOG_DIR" && rm -f $FILES_TO_ARCHIVE)
        NEW_USAGE=$(df -P "$LOG_DIR" | awk 'NR==2 {print $5}' | tr -d '%')
        echo -e "${GREEN}[+] Исходные файлы удалены. Новая занятость диска: ${NEW_USAGE}%${NC}"
    else
        echo -e "${RED}[-] Произошла ошибка при создании архива.${NC}"
    fi
else
    echo -e "${GREEN}[v] Занятость в пределах нормы. Архивация не требуется.${NC}"
fi

