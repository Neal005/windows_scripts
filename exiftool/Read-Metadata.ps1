param (
    # Khong dung Mandatory nua de script chay thang vao trong
    [string]$FilePath = ""
)

# Xoa sach man hinh cho thanh bach
Clear-Host

# IN TIEU DE NGAY KHI VUA MO
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "       SCRIPT DOC METADATA (EXIFTOOL)    " -ForegroundColor Green
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
    Write-Host " DANG DOC METADATA CHO FILE: " -NoNewline -ForegroundColor Cyan
    Write-Host $FilePath -ForegroundColor Yellow
    Write-Host "-----------------------------------------" -ForegroundColor Cyan
    
    # Goi exiftool de doc thong tin
    exiftool $FilePath
    
    Write-Host "-----------------------------------------" -ForegroundColor Cyan
    Write-Host " Hoan tat qua trinh doc." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Loi: Khong tim thay file tai duong dan '$FilePath'. Sep vui long kiem tra lai." -ForegroundColor Red
}

Write-Host ""
# Dung man hinh de sep doc thong tin
Read-Host -Prompt "Nhan Enter de thoat"