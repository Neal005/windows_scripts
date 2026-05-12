# Yeu cau sep nhap duong dan file (ho tro keo tha file truc tiep vao cua so)
$imagePath = (Read-Host "Nhap duong dan den file anh (File 1)").Trim('"').Trim("'")
$zipPath = (Read-Host "Nhap duong dan den file zip (File 2)").Trim('"').Trim("'")

# Kiem tra xem file co ton tai khong
if (!(Test-Path $imagePath -PathType Leaf)) {
    Write-Host "Loi: Khong tim thay file anh tai duong dan tren!" -ForegroundColor Red
    Pause
    exit
}

if (!(Test-Path $zipPath -PathType Leaf)) {
    Write-Host "Loi: Khong tim thay file zip tai duong dan tren!" -ForegroundColor Red
    Pause
    exit
}

# Lay duong dan ra man hinh Desktop
$desktopPath = [Environment]::GetFolderPath("Desktop")

# Lay thong tin ten file anh goc de tao ten file moi
$imageFile = Get-Item $imagePath
$outputFileName = $imageFile.BaseName + "_hidden" + $imageFile.Extension
$outputPath = Join-Path -Path $desktopPath -ChildPath $outputFileName

Write-Host "Dang xu ly ghep file, sep doi chut..." -ForegroundColor Cyan

# Thuc thi lenh copy /b thong qua cmd
cmd.exe /c copy /y /b `"$imagePath`" + `"$zipPath`" `"$outputPath`" > $null

# Kiem tra ket qua va thong bao
if (Test-Path $outputPath) {
    Write-Host "`nThanh cong! File da duoc xuat ra Desktop:" -ForegroundColor Green
    Write-Host "--> $outputPath" -ForegroundColor Yellow
} else {
    Write-Host "`nCo loi xay ra trong qua trinh ghep file." -ForegroundColor Red
}

Write-Host "`n"
Pause