#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Запрашиваю права администратора для запуска тестов..."
    exec sudo bash "$0" "$@"
    exit $?
fi

TEST_LOG="./test_log"
MAIN_SCRIPT="./log_manager.sh"

generate_logs() {
    echo -e "\n[*] Генерируем объемные логи (18 МБ суммарно)..."
    fallocate -l 9M "$TEST_LOG/old_log1.log"
    fallocate -l 9M "$TEST_LOG/old_log2.log"
    touch -d "5 days ago" "$TEST_LOG/old_log1.log"
    touch -d "4 days ago" "$TEST_LOG/old_log2.log"
}

# Перед запуском очистим старый маленький диск, чтобы пересоздать его на 40 МБ
if mountpoint -q "$TEST_LOG"; then
    sudo umount "$TEST_LOG"
    rm -f "${TEST_LOG}_disk.img"
    rm -rf "$TEST_LOG"
fi

echo "=== ПОДГОТОВКА СРЕДЫ ==="
# Выделяем диск на 40 МБ
bash "$MAIN_SCRIPT" "$TEST_LOG" 40 90 2

echo -e "\n=== ТЕСТ 1: Порог 99% (Архивации быть не должно) ==="
generate_logs
# Занятость будет ~55%, порог 99% не сработает
bash "$MAIN_SCRIPT" "$TEST_LOG" 40 99 2

echo -e "\n=== ТЕСТ 2: Порог 50% (Должен сработать триггер и очистить диск) ==="
# Занятость все еще ~55%, порог 50% сработает и запустит архивацию
bash "$MAIN_SCRIPT" "$TEST_LOG" 40 50 2

echo -e "\n=== ТЕСТЫ ЗАВЕРШЕНЫ ==="
echo "Окружение СОХРАНЕНО для демонстрации."
echo "Файлы архивов находятся внутри ./backup_archives"
echo "Чтобы посмотреть состояние диска сейчас, выполните: df -h $TEST_LOG"
echo "Чтобы очистить всё, выполните:"
echo "sudo umount $TEST_LOG && rm -f ${TEST_LOG}_disk.img && rm -rf $TEST_LOG ./backup_archives"
