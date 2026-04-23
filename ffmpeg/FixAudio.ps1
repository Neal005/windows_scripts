Clear-Host
Write-Host "=== SCRIPT 1: XUONG DO AM THANH (FIX LECH TIENG) ===" -ForegroundColor Cyan

# 1. Nhan duong dan file tu sep
$inputFile = Read-Host "Buoc 1: Keo tha file AVI can sua vao day (roi nhan Enter)"
$inputFile = $inputFile.Trim('"').Trim("'")

if (-not (Test-Path $inputFile)) {
    Write-Host "Loi to roi: Khong tim thay file. Sep kiem tra lai duong dan nhe!" -ForegroundColor Red
    Write-Host "Nhan Enter de thoat..."
    Read-Host
    exit
}

Write-Host "------------------------------------------------"
# 2. Nhan ty le dieu chinh
Write-Host "Buoc 2: Nhap ty le am thanh can thay doi." -ForegroundColor Yellow
Write-Host "- Co the nhap so thap phan (VD: 0.916)" -ForegroundColor DarkGray
Write-Host "- Hoac nhap luon phan so cho le (VD: 55/60 hoac 60/55)" -ForegroundColor DarkGray
$ratioInput = Read-Host "Moi sep nhap ty le"

$tempo = 1.0

# Xu ly IQ 200: Doc hieu ca phan so lan so thap phan
try {
    # Thay dau phay thanh dau cham de tranh loi format kieu Viet Nam
    $ratioInput = $ratioInput.Replace(",", ".") 
    
    if ($ratioInput -match "/") {
        $parts = $ratioInput.Split("/")
        $tuSo = [double]::Parse($parts[0].Trim())
        $mauSo = [double]::Parse($parts[1].Trim())
        $tempo = $tuSo / $mauSo
    } else {
        $tempo = [double]::Parse($ratioInput.Trim())
    }
} catch {
    Write-Host "Loi: Dinh dang khong hop le! Nhap so hoac phan so thoi sep oi." -ForegroundColor Red
    Read-Host
    exit
}

# FFmpeg filter atempo chi nhan gia tri tu 0.5 den 100
if ($tempo -lt 0.5 -or $tempo -gt 100.0) {
    Write-Host "Loi: FFmpeg chi cho phep ep xung am thanh trong khoang 0.5 (cham mot nua) den 100 (nhanh gap 100 lan)!" -ForegroundColor Red
    Read-Host
    exit
}

# Chuyen ra so thap phan chuan de FFmpeg doc khong bi loi
$tempoStr = [math]::Round($tempo, 6).ToString([cultureinfo]::InvariantCulture)

Write-Host "=> Chot don: Ty le atempo may tinh ra la $tempoStr" -ForegroundColor Magenta
Write-Host "------------------------------------------------"

# 3. Xu ly ten file dau ra
$fileInfo = Get-Item $inputFile
$outputFile = Join-Path -Path $fileInfo.DirectoryName -ChildPath ($fileInfo.BaseName + "_synced" + $fileInfo.Extension)

Write-Host "Dang khoi dong dong co FFmpeg! Tien hanh phau thuat am thanh..." -ForegroundColor DarkCyan
Write-Host "Lenh: ffmpeg -i file_goc -filter:a `"atempo=$tempoStr`" -c:v copy file_dich" -ForegroundColor DarkGray
Write-Host "Vui long doi trong giay lat..." -ForegroundColor Yellow

# Thuc thi FFmpeg (chi render am thanh, copy giu nguyen hinh anh)
ffmpeg -i $inputFile -filter:a "atempo=$tempoStr" -c:v copy $outputFile

if (Test-Path $outputFile) {
    Write-Host ""
    Write-Host "THANH CONG RUC RO! Da fix xong am thanh cho file cua sep." -ForegroundColor Green
    Write-Host "Thanh pham o day: $outputFile" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "Co loi khi render. Sep check lai xem file goc co dang bi phan mem khac khoa khong nhe!" -ForegroundColor Red
}

Write-Host ""
Write-Host "Xong viec! Nhan Enter de thoat va chuyen sang file khac..." -ForegroundColor Cyan
Read-Host