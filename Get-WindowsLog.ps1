# Lay duong dan thu muc Desktop cua sep
$desktopPath = [Environment]::GetFolderPath("Desktop")

Clear-Host
Write-Host "=== CONG CU TRICH XUAT LOG WINDOWS ===" -ForegroundColor Cyan
Write-Host "1. System (Log He thong)"
Write-Host "2. Application (Log Ung dung)"
Write-Host "========================================" -ForegroundColor Cyan

# Cho sep chon loai log
$choice = Read-Host "Sep muon xem log nao? (Nhap 1 hoac 2)"

if ($choice -eq "1") {
    $logName = "System"
} elseif ($choice -eq "2") {
    $logName = "Application"
} else {
    Write-Host "Lua chon khong hop le! Dang thoat chuong trinh..." -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit
}

# Cho sep chon ngay muon xuat log
Write-Host ""
$dateInput = Read-Host "Nhap ngay muon xem (Dinh dang dd/MM/yyyy, vi du 23/04/2026). Nhan Enter de lay ngay hom nay"

if ([string]::IsNullOrWhiteSpace($dateInput)) {
    $startDate = (Get-Date).Date
} else {
    try {
        $startDate = [datetime]::ParseExact($dateInput, "dd/MM/yyyy", $null).Date
    } catch {
        Write-Host "Ngay nhap sai dinh dang! Tu dong chuyen ve ngay hom nay." -ForegroundColor Yellow
        $startDate = (Get-Date).Date
    }
}

$endDate = $startDate.AddDays(1)

# Dat ten file va duong dan xuat ra Desktop
$dateString = $startDate.ToString("dd-MM-yyyy")
$fileName = "Log_$($logName)_$dateString.txt"
$exportPath = Join-Path -Path $desktopPath -ChildPath $fileName

Write-Host ""
Write-Host "Dang quet log $logName trong ngay $($startDate.ToString('dd/MM/yyyy'))..." -ForegroundColor Cyan

try {
    # Quet toan bo log trong khoang thoi gian da chon
    $events = Get-WinEvent -FilterHashtable @{LogName=$logName; StartTime=$startDate; EndTime=$endDate} -ErrorAction Stop
    
    # Format va xuat ra file txt. Dung Format-List de de doc cac message dai.
    $events | Select-Object TimeCreated, LevelDisplayName, Id, Message | Format-List | Out-File -FilePath $exportPath -Encoding UTF8
    
    Write-Host "Thanh cong! File log da duoc vut ra Desktop tai: $exportPath" -ForegroundColor Green
    
    # Tu dong mo file log cho sep xem luon
    Invoke-Item $exportPath
} catch {
    Write-Host "Khong co du lieu log nao trong ngay nay hoac file log dang bi khoa." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Xong viec! Nhan Enter de dong cua so..." -ForegroundColor Cyan
Read-Host