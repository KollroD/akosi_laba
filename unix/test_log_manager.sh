#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Запрашиваю права администратора для запуска тестов..."
    exec sudo bash "$0" "$@"
    exit $?
fi

# Работаем из папки со скриптами, чтобы пути не зависели от того, откуда запущен тест
cd "$(dirname "$(realpath "$0")")" || exit 1

TEST_LOG="./test_log"
MAIN_SCRIPT="./log_manager.sh"
BACKUP_DIR="./backup_archives"
FAILED=0

check() {
    # check "описание" команда...
    local description="$1"
    shift
    if "$@"; then
        echo "  [PASS] $description"
    else
        echo "  [FAIL] $description"
        FAILED=1
    fi
}

generate_logs() {
    echo -e "\n[*] Генерируем объемные логи (18 МБ суммарно)..."
    fallocate -l 9M "$TEST_LOG/old_log1.log"
    fallocate -l 9M "$TEST_LOG/old_log2.log"
    touch -d "5 days ago" "$TEST_LOG/old_log1.log"
    touch -d "4 days ago" "$TEST_LOG/old_log2.log"
}

archive_count() { ls "$BACKUP_DIR"/archive_*.tar.gz 2>/dev/null | wc -l; }
logs_present()  { [ -f "$TEST_LOG/old_log1.log" ] && [ -f "$TEST_LOG/old_log2.log" ]; }
logs_absent()   { [ ! -e "$TEST_LOG/old_log1.log" ] && [ ! -e "$TEST_LOG/old_log2.log" ]; }
no_archives()   { [ "$(archive_count)" -eq 0 ]; }
one_archive()   { [ "$(archive_count)" -eq 1 ]; }
archive_has_both_logs() {
    local listing
    listing=$(tar -tzf "$BACKUP_DIR"/archive_*.tar.gz 2>/dev/null)
    echo "$listing" | grep -q "old_log1.log" && echo "$listing" | grep -q "old_log2.log"
}

# Перед запуском очищаем остатки прошлых запусков
if mountpoint -q "$TEST_LOG"; then
    umount "$TEST_LOG"
fi
rm -f "${TEST_LOG}_disk.img"
rm -rf "$TEST_LOG" "$BACKUP_DIR"

echo "=== ПОДГОТОВКА СРЕДЫ ==="
# Выделяем диск на 40 МБ (порог 90% - лишь бы ничего не архивировать)
bash "$MAIN_SCRIPT" "$TEST_LOG" 40 90 2 || { echo "[FAIL] Не удалось подготовить диск"; exit 1; }

echo -e "\n=== ТЕСТ 1: Порог 99% (Архивации быть не должно) ==="
generate_logs
# Занятость будет ~55%, порог 99% не сработает
bash "$MAIN_SCRIPT" "$TEST_LOG" 40 99 2
check "оба лога остались на диске" logs_present
check "архив не создавался" no_archives

echo -e "\n=== ТЕСТ 2: Порог 50% (Должен сработать триггер и очистить диск) ==="
# Занятость все еще ~55%, порог 50% сработает и запустит архивацию
bash "$MAIN_SCRIPT" "$TEST_LOG" 40 50 2
check "логи удалены с диска" logs_absent
check "создан ровно один архив" one_archive
check "в архиве лежат оба лога" archive_has_both_logs

echo -e "\n=== ТЕСТЫ ЗАВЕРШЕНЫ ==="
if [ "$FAILED" -eq 0 ]; then
    echo "РЕЗУЛЬТАТ: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ"
else
    echo "РЕЗУЛЬТАТ: ЕСТЬ ПРОВАЛЕННЫЕ ПРОВЕРКИ"
fi
echo "Окружение СОХРАНЕНО для демонстрации."
echo "Файлы архивов находятся внутри $BACKUP_DIR"
echo "Чтобы посмотреть состояние диска сейчас, выполните: df -h $TEST_LOG"
echo "Чтобы очистить всё, выполните:"
echo "sudo umount $TEST_LOG && rm -f ${TEST_LOG}_disk.img && rm -rf $TEST_LOG $BACKUP_DIR"
exit "$FAILED"
