Clear-Host
Write-Host "=== TRAM CHI HUY FFMPEG TONG HOP (MASTER HUB) ===" -ForegroundColor Cyan

# 1. Quet phan cung he thong de lay so ma
Write-Host "Dang kiem tra vu khi hang nang tren he thong..." -ForegroundColor DarkCyan
$gpus = Get-CimInstance Win32_VideoController
$gpuNames = $gpus.Name

$encoder = "libx264"
$techName = "CPU (Cham nhat)"

if ($gpuNames -match "NVIDIA") {
    $encoder = "h264_nvenc"
    $techName = "NVIDIA NVENC"
} elseif ($gpuNames -match "AMD" -or $gpuNames -match "Radeon") {
    $encoder = "h264_amf"
    $techName = "AMD AMF"
} elseif ($gpuNames -match "Intel") {
    $encoder = "h264_qsv"
    $techName = "Intel QuickSync"
}

# Day bien encoder vao moi truong de cac script con (neu can) co the dung xai
[Environment]::SetEnvironmentVariable("FFMPEG_GPU_ENCODER", $encoder, "Process")

Write-Host "-> Phat hien dong co: $techName" -ForegroundColor Magenta
Write-Host "------------------------------------------------"

# 2. Vong lap trung tam (Dock Station)
while ($true) {
    Write-Host ""
    Write-Host ">>> TRAM CHI HUY DANG CHO LENH <<<" -ForegroundColor Yellow
    Write-Host "- Sep keo tha Script 1, 2 hoac 3 (.ps1) vao day de bat dau luong cong viec." -ForegroundColor White
    $droppedItem = Read-Host "- Hoac go 'exit' de thoat"
    
    if ($droppedItem.ToLower() -eq 'exit') {
        Write-Host "Dang dong dong co. Chuc sep mot ngay thanh bach!" -ForegroundColor DarkGray
        break
    }

    # Lam sach duong dan neu co dau nhay kep
    $droppedItem = $droppedItem.Trim('"').Trim("'")

    if (-not (Test-Path $droppedItem)) {
        Write-Host "Loi: Khong tim thay file! Sep co keo nham khong day?" -ForegroundColor Red
        continue
    }

    # Bat loi neu sep lo tay keo video vao thay vi script
    if ($droppedItem -notmatch "\.ps1$") {
        Write-Host "Loi to roi: Tram chi huy chi nhan lenh tu cac file Script (.ps1) thoi nhe!" -ForegroundColor Red
        Write-Host "Sep keo file ps1 vao day, con video thi ty nua keo vao cua so cua script do." -ForegroundColor Red
        continue
    }

    Write-Host "------------------------------------------------"
    Write-Host "Dang kich hoat luong cong viec: $droppedItem" -ForegroundColor Green
    Start-Sleep -Seconds 1
    
    # Thuc thi file script con
    & $droppedItem
    
    # Sau khi script con chay xong (bam Enter de thoat ra), Hub se khoi dong lai
    Clear-Host
    Write-Host "=== TRAM CHI HUY FFMPEG TONG HOP (MASTER HUB) ===" -ForegroundColor Cyan
    Write-Host "-> Dong co hien tai: $techName" -ForegroundColor Magenta
    Write-Host "=> Luong cong viec truoc do da hoan tat thanh cong!" -ForegroundColor Green
    Write-Host "------------------------------------------------"
}