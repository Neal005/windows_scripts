param (
    [string]$FilePath = ""
)

# Xoa sach man hinh cho thanh bach
Clear-Host

# IN TIEU DE NGAY KHI VUA MO
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "      SCRIPT XOA SACH METADATA V1.0      " -ForegroundColor Red
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Neu chua co duong dan thi hien thong bao yeu cau nhap/keo tha
if ([string]::IsNullOrWhiteSpace($FilePath)) {
    $FilePath = Read-Host "Vui long nhap (hoac keo tha) duong dan file vao day"
}

# Tu dong loai bo dau ngoac kep neu sep keo tha file vao
$FilePath = $FilePath.Trim('"', "'")

# Kiem tra xem file co ton tai khong
if (Test-Path $FilePath) {
    Write-Host ""
    Write-Host " DANG XOA SACH METADATA CHO FILE: " -NoNewline -ForegroundColor Cyan
    Write-Host $FilePath -ForegroundColor Yellow
    Write-Host "-----------------------------------------" -ForegroundColor Cyan
    
    # Goi exiftool de xoa tat ca metadata va ghi de thang len file goc
    exiftool -all= -overwrite_original $FilePath
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Tuyet voi! File da duoc lam thanh bach hoan toan." -ForegroundColor Green
    } else {
        Write-Host "Co loi xay ra trong qua trinh xu ly cua ExifTool." -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "Loi: Khong tim thay file tai duong dan '$FilePath'. Sep vui long kiem tra lai." -ForegroundColor Red
}

Write-Host ""
# Dung man hinh de xem ket qua
Read-Host -Prompt "Nhan Enter de thoat"