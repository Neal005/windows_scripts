# Automatically request Administrator privileges if missing
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges to check system..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Get detailed system information
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
$osName = $osInfo.Caption.Trim()
$osVersion = $osInfo.Version
$osArchitecture = $osInfo.OSArchitecture

Clear-Host
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "SYSTEM INFORMATION:" -ForegroundColor Cyan
Write-Host "  - Version: $osName" -ForegroundColor White
Write-Host "  - Build:   $osVersion ($osArchitecture)" -ForegroundColor White
Write-Host "================================================" -ForegroundColor Cyan

Write-Host "`nScanning system license status..." -ForegroundColor White

# Silently run slmgr.vbs
$slmgrPath = "$env:SystemRoot\System32\slmgr.vbs"
$dliOutput = (cscript.exe //nologo $slmgrPath /dli) -join "`n"
$xprOutput = (cscript.exe //nologo $slmgrPath /xpr) -join "`n"

# Analyze status and license type
$isGenuineChannel = $false
$licenseType = "Unknown"

if ($dliOutput -match "RETAIL") {
    $isGenuineChannel = $true
    $licenseType = "Retail"
} elseif ($dliOutput -match "OEM") {
    $isGenuineChannel = $true
    $licenseType = "OEM (System Bound)"
} elseif ($dliOutput -match "VOLUME_MAK") {
    $isGenuineChannel = $true
    $licenseType = "Volume MAK (Enterprise Key)"
}

$isKmsChannel = ($dliOutput -match "VOLUME_KMSCLIENT")
$isPermanent = ($xprOutput -match "permanently activated" -or $xprOutput -match "vinh vien")

Write-Host "------------------------------------------------" -ForegroundColor Cyan

if ($isGenuineChannel -and $isPermanent) {
    Write-Host "[+] RESULT: GENUINE WINDOWS LICENSE" -ForegroundColor Green
    Write-Host "    - License Type: $licenseType" -ForegroundColor Green
    Write-Host "    - Status: Permanently Activated" -ForegroundColor Green
} elseif ($isKmsChannel) {
    Write-Host "[!] RESULT: ENTERPRISE LICENSE (KMS)" -ForegroundColor Yellow
    Write-Host "    - License Type: Volume KMS Client" -ForegroundColor Yellow
    Write-Host "    - Note: Activated via server." -ForegroundColor Yellow
    Write-Host "      + If this is a personal PC: Likely using cracked software (e.g., KMSpico)." -ForegroundColor Yellow
    Write-Host "      + If this is a corporate PC: This might be a genuine organization license." -ForegroundColor Yellow
} elseif (-not $isPermanent -and ($xprOutput -match "expire" -or $xprOutput -match "het han")) {
    Write-Host "[-] RESULT: UNAUTHORIZED (CRACKED) WINDOWS / EXPIRED LICENSE" -ForegroundColor Red
    Write-Host "    - License Type: Unknown or Expired" -ForegroundColor Red
} else {
    Write-Host "[!] RESULT: AMBIGUOUS STATUS" -ForegroundColor DarkYellow
    Write-Host "    - Please manually check at:" -ForegroundColor DarkYellow
    Write-Host "      Settings > System > Activation" -ForegroundColor DarkYellow
}

Write-Host "------------------------------------------------" -ForegroundColor Cyan
Write-Host "`nPress any key to exit..." -ForegroundColor White
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')