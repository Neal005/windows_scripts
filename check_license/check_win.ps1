# Tu dong xin quyen Administrator neu chua co
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Dang yeu cau cap quyen Administrator de kiem tra..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Lay thong tin he thong chi tiet
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
$osName = $osInfo.Caption.Trim()
$osVersion = $osInfo.Version
$osArchitecture = $osInfo.OSArchitecture

Clear-Host
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "THONG TIN HE THONG:" -ForegroundColor Cyan
Write-Host "  - Phien ban: $osName" -ForegroundColor White
Write-Host "  - Build:     $osVersion ($osArchitecture)" -ForegroundColor White
Write-Host "================================================" -ForegroundColor Cyan

Write-Host "`nDang quet trang thai ban quyen he thong..." -ForegroundColor White

# Goi ngam slmgr.vbs
$slmgrPath = "$env:SystemRoot\System32\slmgr.vbs"
$dliOutput = (cscript.exe //nologo $slmgrPath /dli) -join "`n"
$xprOutput = (cscript.exe //nologo $slmgrPath /xpr) -join "`n"

# Phan tich co trang thai va loai giay phep
$isGenuineChannel = $false
$licenseType = "Khong ro"

if ($dliOutput -match "RETAIL") {
    $isGenuineChannel = $true
    $licenseType = "Retail (Ban le)"
} elseif ($dliOutput -match "OEM") {
    $isGenuineChannel = $true
    $licenseType = "OEM (Theo may)"
} elseif ($dliOutput -match "VOLUME_MAK") {
    $isGenuineChannel = $true
    $licenseType = "Volume MAK (Key Doanh nghiep)"
}

$isKmsChannel = ($dliOutput -match "VOLUME_KMSCLIENT")
$isPermanent = ($xprOutput -match "permanently activated" -or $xprOutput -match "vinh vien")

Write-Host "------------------------------------------------" -ForegroundColor Cyan

if ($isGenuineChannel -and $isPermanent) {
    Write-Host "[+] KET QUA: WINDOWS BAN QUYEN CHINH HANG (XIN)" -ForegroundColor Green
    Write-Host "    - Loai giay phep: $licenseType" -ForegroundColor Green
    Write-Host "    - Trang thai: Kich hoat vinh vien" -ForegroundColor Green
} elseif ($isKmsChannel) {
    Write-Host "[!] KET QUA: GIAY PHEP DOANH NGHIEP (KMS)" -ForegroundColor Yellow
    Write-Host "    - Loai giay phep: Volume KMS Client" -ForegroundColor Yellow
    Write-Host "    - Luu y: Kich hoat qua may chu (Server)." -ForegroundColor Yellow
    Write-Host "      + Neu la may ca nhan o nha: 99% la dung hang Crack (KMSpico...)." -ForegroundColor Yellow
    Write-Host "      + Neu la may cong ty: Day co the la ban quyen xin cua to chuc!" -ForegroundColor Yellow
} elseif (-not $isPermanent -and ($xprOutput -match "expire" -or $xprOutput -match "het han")) {
    Write-Host "[-] KET QUA: WINDOWS CRACK (LAU) / GIAY PHEP HET HAN" -ForegroundColor Red
    Write-Host "    - Loai giay phep: Khong xac dinh hoac da het thoi han" -ForegroundColor Red
} else {
    Write-Host "[!] KET QUA: KHONG RO RANG" -ForegroundColor DarkYellow
    Write-Host "    - Vui long kiem tra thu cong tai:" -ForegroundColor DarkYellow
    Write-Host "      Settings > System > Activation" -ForegroundColor DarkYellow
}

Write-Host "------------------------------------------------" -ForegroundColor Cyan
Write-Host "`nNhan phim bat ky de thoat..." -ForegroundColor White
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')