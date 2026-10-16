param (
    [string]$TestLog = "Z:",
    [string]$MainScript = (Join-Path $PSScriptRoot "log_manager.ps1")
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Запрашиваю права администратора для запуска тестов..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -TestLog $TestLog -MainScript `"$MainScript`""
    exit
}

$scriptPath = (Resolve-Path $MainScript).Path
$imgFile    = Join-Path $PSScriptRoot "test_disk.vhd"
$backupDir  = Join-Path $PSScriptRoot "backup_archives"
$letter     = $TestLog.Trim('\', ':')
$mountPoint = "${letter}:\"
$failed     = $false

# Снимаем блокировку "файл скачан из интернета", иначе политика выполнения может не пустить скрипт
Unblock-File -Path $scriptPath -ErrorAction SilentlyContinue

function Generate-Logs {
    Write-Host "`n[*] Генерируем объемные логи (20 МБ суммарно)..." -ForegroundColor Cyan
    $f1 = "${mountPoint}old_log1.log"
    $f2 = "${mountPoint}old_log2.log"

    $fs1 = [System.IO.File]::Create($f1)
    $fs1.SetLength(10MB)
    $fs1.Close()

    $fs2 = [System.IO.File]::Create($f2)
    $fs2.SetLength(10MB)
    $fs2.Close()

    (Get-Item $f1).LastWriteTime = (Get-Date).AddDays(-5)
    (Get-Item $f2).LastWriteTime = (Get-Date).AddDays(-4)
}

function Cleanup-Environment {
    if (Test-Path $imgFile) {
        $image = Get-DiskImage -ImagePath $imgFile -ErrorAction SilentlyContinue
        if ($image -and $image.Attached) {
            Dismount-DiskImage -ImagePath $imgFile | Out-Null
        }
        Remove-Item $imgFile -Force
    }
    if (Test-Path $backupDir) { Remove-Item $backupDir -Recurse -Force -ErrorAction SilentlyContinue }
}

function Run-Manager {
    param ([int]$Threshold, [int]$Files)
    # Отдельный процесс с Bypass: тест работает независимо от политики выполнения скриптов в системе
    # Out-Host показывает вывод скрипта на экране и не подмешивает его в возвращаемое значение
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -LogDir $mountPoint -Threshold $Threshold -M_Files $Files | Out-Host
    return $LASTEXITCODE
}

function Check {
    param ([string]$Description, [bool]$Condition)
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        $script:failed = $true
    }
}

function Get-Archives {
    if (Test-Path $backupDir) { @(Get-ChildItem $backupDir -Filter "archive_*.tar.gz") } else { @() }
}

Cleanup-Environment

if (Test-Path $mountPoint) {
    Write-Host "Ошибка: буква ${letter}: уже занята. Укажите другую: .\test_log_manager.ps1 -TestLog Y:" -ForegroundColor Red
    exit 1
}

Write-Host "=== ПОДГОТОВКА СРЕДЫ ===" -ForegroundColor Blue
$diskpartScript = Join-Path $PSScriptRoot "diskpart.txt"
@"
create vdisk file="$imgFile" maximum=40 type=fixed
select vdisk file="$imgFile"
attach vdisk
create partition primary
format fs=ntfs quick
assign letter=$letter
"@ | Out-File $diskpartScript -Encoding ascii

Start-Process diskpart -ArgumentList "/s `"$diskpartScript`"" -Wait -NoNewWindow
Remove-Item $diskpartScript -Force

if (-not (Test-Path $mountPoint)) {
    Write-Host "Ошибка: не удалось создать виртуальный диск ${letter}:" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== ТЕСТ 1: Порог 99% (Архивации быть не должно) ===" -ForegroundColor Blue
Generate-Logs
$rc = Run-Manager -Threshold 99 -Files 2
Check "скрипт завершился без ошибок" ($rc -eq 0)
Check "оба лога остались на диске" ((Test-Path "${mountPoint}old_log1.log") -and (Test-Path "${mountPoint}old_log2.log"))
Check "архив не создавался" ((Get-Archives).Count -eq 0)

Write-Host "`n=== ТЕСТ 2: Порог 50% (Должен сработать триггер и очистить диск) ===" -ForegroundColor Blue
$rc = Run-Manager -Threshold 50 -Files 2
Check "скрипт завершился без ошибок" ($rc -eq 0)
Check "логи удалены с диска" (-not (Test-Path "${mountPoint}old_log1.log") -and -not (Test-Path "${mountPoint}old_log2.log"))
$archives = Get-Archives
Check "создан ровно один архив" ($archives.Count -eq 1)
if ($archives.Count -eq 1) {
    $content = (tar -tzf $archives[0].FullName) -join ","
    Check "в архиве лежат оба лога" (($content -match "old_log1.log") -and ($content -match "old_log2.log"))
}

Write-Host "`n=== ТЕСТЫ ЗАВЕРШЕНЫ ===" -ForegroundColor Blue
if ($failed) {
    Write-Host "РЕЗУЛЬТАТ: ЕСТЬ ПРОВАЛЕННЫЕ ПРОВЕРКИ" -ForegroundColor Red
} else {
    Write-Host "РЕЗУЛЬТАТ: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ" -ForegroundColor Green
}
Write-Host "Окружение СОХРАНЕНО для демонстрации."
Write-Host "Файлы архивов находятся в папке $backupDir"
Write-Host "Чтобы очистить всё, выполните команду:"
Write-Host "Dismount-DiskImage -ImagePath '$imgFile'; Remove-Item '$imgFile' -Force; Remove-Item '$backupDir' -Recurse -Force" -ForegroundColor Yellow
