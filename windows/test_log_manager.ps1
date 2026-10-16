param (
    [string]\$TestLog = "Z:",
    [string]\$MainScript = "./log_manager.ps1"
)

scriptPath = Resolve-Path MainScript
imgFile = Join-Path PSScriptRoot "test_disk.vhd"
mountPoint = TestLog.Trim('\')

function Generate-Logs {
    Write-Host "`n[*] Генерируем объемные логи (18 МБ суммарно)..." -ForegroundColor Cyan
    $f1 = Join-Path $mountPoint "old_log1.log"
    $f2 = Join-Path $mountPoint "old_log2.log"
    
    $fs1 = [System.IO.File]::Create($f1)
    $fs1.SetLength(9MB)
    $fs1.Close()
    
    $fs2 = [System.IO.File]::Create($f2)
    $fs2.SetLength(9MB)
    $fs2.Close()

    (Get-Item $f1).LastWriteTime = (Get-Date).AddDays(-5)
    (Get-Item $f2).LastWriteTime = (Get-Date).AddDays(-4)
}

function Cleanup-Environment {
    if (Get-Volume -DriveLetter $mountPoint.Trim(':') -ErrorAction SilentlyContinue) {
        $diskNumber = (Get-DiskImage -ImagePath $imgFile).DiskNumber
        if ($diskNumber) {
            Dismount-DiskImage -ImagePath $imgFile | Out-Null
        }
    }
    if (Test-Path $imgFile) { Remove-Item $imgFile -Force }
    if (Test-Path (Join-Path $PSScriptRoot "backup_archives")) { Remove-Item (Join-Path $PSScriptRoot "backup_archives") -Recurse -Force -ErrorAction SilentlyContinue }
}

Cleanup-Environment

Write-Host "=== ПОДГОТОВКА СРЕДЫ ===" -ForegroundColor Blue
$diskpartScript = Join-Path $PSScriptRoot "diskpart.txt"
@"
create vdisk file="$imgFile" maximum=40 type=fixed
attach vdisk
create partition primary
format fs=ntfs quick
assign letter=$($mountPoint.Trim(':'))
"@ | Out-File $diskpartScript -Encoding ascii

Start-Process diskpart -ArgumentList "/s `"\$diskpartScript`"" -Wait -NoNewWindow
Remove-Item $diskpartScript -Force

Write-Host "`n=== ТЕСТ 1: Порог 99% (Архивации быть не должно) ===" -ForegroundColor Blue
Generate-Logs
Powershell.exe -File scriptPath -LogDir "mountPoint\" -Threshold 99 -M_Files 2

Write-Host "`n=== ТЕСТ 2: Порог 50% (Должен сработать триггер и очистить диск) ===" -ForegroundColor Blue
Powershell.exe -File $scriptPath -LogDir "$mountPoint\" -Threshold 50 -M_Files 2

Write-Host "`n=== ТЕСТЫ ЗАВЕРШЕНЫ ===" -ForegroundColor Blue
Write-Host "Окружение СОХРАНЕНО для демонстрации."
Write-Host "Файлы архивов находятся в папке.\backup_archives"
Write-Host "Чтобы очистить всё, выполните команду:"
Write-Host "Dismount-DiskImage -ImagePath 'imgFile'; Remove-Item 'imgFile' -Force; Remove-Item '.\backup_archives' -Recurse -Force" -ForegroundColor Yellow
