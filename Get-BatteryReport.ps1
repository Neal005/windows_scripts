# Lay duong dan thu muc Desktop cua nguoi dung hien tai
$desktopPath = [Environment]::GetFolderPath("Desktop")

# Xac dinh duong dan day du va ten file bao cao
$reportPath = Join-Path -Path $desktopPath -ChildPath "battery_report.html"

# Thong bao dang xu ly
Write-Host "Dang tao bao cao pin..." -ForegroundColor Cyan

# Chay lenh powercfg de xuat bao cao thang ra Desktop
powercfg /batteryreport /output $reportPath

# Kiem tra xem file da duoc tao thanh cong chua
if (Test-Path $reportPath) {
    Write-Host "Thanh cong! Bao cao da duoc luu tai: $reportPath" -ForegroundColor Green
    
    # Tu dong mo file bao cao bang trinh duyet mac dinh
    Invoke-Item $reportPath
} else {
    Write-Host "Co loi xay ra. Khong the tao bao cao pin." -ForegroundColor Red
}