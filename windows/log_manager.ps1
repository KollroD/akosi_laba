param (
    [Parameter(Mandatory=$true)] [string]$LogDir,
    [Parameter(Mandatory=$true)] [int]$Threshold,
    [Parameter(Mandatory=$true)] [int]$M_Files
)

$BackupDir = Join-Path $PSScriptRoot "backup_archives"

if (!(Test-Path $LogDir)) {
    Write-Host "Ошибка: Путь $LogDir не найден." -ForegroundColor Red
    exit
}

$resolvedPath = (Resolve-Path $LogDir).Path
$driveLetter = (Get-Item $resolvedPath).Root.Name.Trim('\')
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$driveLetter'"
$percentUsed = [math]::Round(((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100), 2)

Write-Host "Виртуальный диск $driveLetter занят на $percentUsed% (Порог: $Threshold%)" -ForegroundColor Cyan

if ($percentUsed -ge $Threshold) {
    Write-Host "Внимание: Занятость превысила порог ($Threshold%). Начинаем архивацию..." -ForegroundColor Yellow
    
    if (!(Test-Path $BackupDir)) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }

    $oldFiles = Get-ChildItem -Path $resolvedPath -File | Sort-Object LastWriteTime | Select-Object -First $M_Files
    
    if (!$oldFiles) { 
        Write-Host "Нет файлов для архивации." -ForegroundColor Yellow
        exit 
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $archiveName = Join-Path $BackupDir "archive_$timestamp.tar.gz"

    $fileNames = $oldFiles | ForEach-Object { $_.Name }

    $currentLocation = Get-Location
    Set-Location $resolvedPath
    try {
        tar -czf $archiveName $fileNames
        Write-Host "Архив успешно создан: $archiveName" -ForegroundColor Green
        
        Set-Location $currentLocation
        Remove-Item -Path $oldFiles.FullName -Force
        Write-Host "Исходные файлы удалены, место на диске освобождено." -ForegroundColor Green
    }
    catch {
        Write-Host "Произошла ошибка при архивации." -ForegroundColor Red
        Set-Location $currentLocation
    }
} else {
    Write-Host "Занятость в пределах нормы. Архивация не требуется." -ForegroundColor Green
}

