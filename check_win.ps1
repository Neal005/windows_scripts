# Tu dong xin quyen Administrator neu chua co
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Dang yeu cau cap quyen Administrator de kiem tra..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "Dang quet trang thai he thong..." -ForegroundColor Cyan

# Lay thong tin phien ban Windows
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
$osName = $osInfo.Caption
$osBuild = $osInfo.BuildNumber

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
}

$isKmsChannel = ($dliOutput -match "VOLUME_KMSCLIENT")
$isPermanent = ($xprOutput -match "permanently activated" -or $xprOutput -match "vinh vien")

Write-Host "------------------------------------------------"
Write-Host "PHIEN BAN: $osName (Build $osBuild)" -ForegroundColor White
Write-Host "------------------------------------------------"

if ($isGenuineChannel -and $isPermanent) {
    Write-Host "[+] KET QUA: WINDOWS BAN QUYEN CHINH HANG (XIN)" -ForegroundColor Green
    Write-Host "    - Loai giay phep: $licenseType" -ForegroundColor Green
    Write-Host "    - Trang thai: Kich hoat vinh vien" -ForegroundColor Green
} elseif ($isKmsChannel -or (-not $isPermanent -and ($xprOutput -match "expire" -or $xprOutput -match "het han"))) {
    Write-Host "[-] KET QUA: WINDOWS CRACK (LAU)" -ForegroundColor Red
    Write-Host "    - Loai giay phep: Volume KMS Client" -ForegroundColor Red
    Write-Host "    - Trang thai: Kich hoat co thoi han" -ForegroundColor Red
} else {
    Write-Host "[!] KET QUA: KHONG RO RANG" -ForegroundColor Yellow
    Write-Host "    - Vui long kiem tra thu cong tai: Settings > System > Activation" -ForegroundColor Yellow
}
Write-Host "------------------------------------------------"
Write-Host "Nhan phim bat ky de thoat..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')