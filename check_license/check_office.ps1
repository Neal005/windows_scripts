# ==============================================================================
# MICROSOFT OFFICE LICENSE STATUS CHECKER (V8 - WMI/CIM ULTIMATE)
# ==============================================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges to scan system..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "       MICROSOFT OFFICE LICENSE STATUS CHECK (V8)         " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check for genuine vNext Cloud Token (Scan all Users)
$isVNext = $false
$userProfiles = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue
foreach ($user in $userProfiles) {
    $vNextPath = Join-Path $user.FullName "AppData\Local\Microsoft\Office\16.0\Licensing"
    if (Test-Path -LiteralPath $vNextPath) {
        $tokens = Get-ChildItem -Path $vNextPath -ErrorAction SilentlyContinue
        if ($tokens -and $tokens.Count -gt 0) {
            $isVNext = $true
            break
        }
    }
}

# 2. Read license using WMI/CIM (Language-agnostic, ultra-fast)
Write-Host "Querying WMI to read Office license object..." -ForegroundColor White

# Office ApplicationID is always 0ff1ce15-a989-479d-af46-f275c6370663
$wmiQuery = "SELECT * FROM SoftwareLicensingProduct WHERE ApplicationId = '0ff1ce15-a989-479d-af46-f275c6370663' AND PartialProductKey IS NOT NULL"
$officeProducts = Get-CimInstance -Query $wmiQuery -ErrorAction SilentlyContinue

$isM365 = $false
$isKMS = $false
$isGrace = $false
$isLicensed = $false

if ($officeProducts) {
    foreach ($prod in $officeProducts) {
        $desc = $prod.Description
        $status = $prod.LicenseStatus

        # LicenseStatus: 1 = Licensed, 2/3/4/5/6 = Grace/Notification (Not/Failed Activation)
        if ($desc -match "(?i)O365|TIMEBASED_SUB|Subscription") { $isM365 = $true }
        if ($desc -match "(?i)KMS_Client|VOLUME_KMSCLIENT") { $isKMS = $true }
        
        if ($status -eq 1) { $isLicensed = $true }
        elseif ($status -in 2..6) { $isGrace = $true }
    }
}

Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
if ($isVNext) {
    Write-Host " [+] OFFICE STATUS: MICROSOFT 365 (vNext CLOUD TOKEN)" -ForegroundColor Green
    Write-Host "   -> 100% Genuine Next-Gen Cloud License." -ForegroundColor Green
} elseif ($isM365) {
    Write-Host " [+] OFFICE STATUS: MICROSOFT 365 (SUBSCRIPTION)" -ForegroundColor Green
} elseif ($isKMS) {
    Write-Host " [?] OFFICE STATUS: ENTERPRISE LICENSE (KMS CLIENT)" -ForegroundColor Yellow
} elseif ($isLicensed) {
    Write-Host " [+] OFFICE STATUS: ACTIVATED (LICENSED)" -ForegroundColor Green
} elseif ($isGrace) {
    Write-Host " [-] OFFICE STATUS: NOT ACTIVATED (TRIAL / GRACE PERIOD)" -ForegroundColor Red
} else {
    Write-Host " [!] OFFICE STATUS: UNKNOWN OR NOT INSTALLED" -ForegroundColor DarkYellow
}

# 3. COMPREHENSIVE HEURISTIC SCAN (NO -DEPTH TO DETECT OHOOK)
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Running Heuristic scan for unauthorized tools (Cracks)..." -ForegroundColor White
$crackFound = $false

$sppReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform" -ErrorAction SilentlyContinue
if ($sppReg -and -not [string]::IsNullOrWhiteSpace($sppReg.KeyManagementServiceName)) {
    $crackFound = $true
    Write-Host " -> [CRACK DETECTED] Unauthorized KMS Server: $($sppReg.KeyManagementServiceName)" -ForegroundColor Red
}

$officeInstallPaths = @("$env:ProgramFiles\Microsoft Office", "${env:ProgramFiles(x86)}\Microsoft Office")
foreach ($installPath in $officeInstallPaths) {
    if (Test-Path -LiteralPath $installPath) {
        $fakeDlls = Get-ChildItem -Path $installPath -Filter "sppc.dll" -Recurse -ErrorAction SilentlyContinue
        foreach ($dll in $fakeDlls) {
            $sig = Get-AuthenticodeSignature -LiteralPath $dll.FullName -ErrorAction SilentlyContinue
            if ($sig.Status -ne 'Valid') {
                $crackFound = $true
                Write-Host " -> [CRACK DETECTED] Fake Ohook file hidden: $($dll.FullName)" -ForegroundColor Red
            }
        }
    }
}

$kmsTasks = Get-ScheduledTask | Where-Object { $_.TaskName -match "(?i)KMS|AutoKMS|SppExtComObjHook" } -ErrorAction SilentlyContinue
if ($kmsTasks) {
    $crackFound = $true
    Write-Host " -> [CRACK DETECTED] Unauthorized automatic renewal task:" -ForegroundColor Red
    foreach ($task in $kmsTasks) { Write-Host "    + $($task.TaskName)" -ForegroundColor DarkRed }
}

$ohookReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\sppsvc.exe" -ErrorAction SilentlyContinue
if ($ohookReg) {
    $crackFound = $true
    Write-Host " -> [CRACK DETECTED] Registry modified (Ohook Bypass)!" -ForegroundColor Red
}

$crackDirs = @("$env:SystemDrive\Windows\KMS", "$env:ProgramData\KMSAutoS", "$env:ProgramData\KMSAuto")
foreach ($dir in $crackDirs) {
    if (Test-Path -LiteralPath $dir) {
        $crackFound = $true
        Write-Host " -> [CRACK DETECTED] Crack/Junk folder exists: $dir" -ForegroundColor Red
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
if ($crackFound) {
    Write-Host " [!!!] CONCLUSION: OFFICE IS USING UNAUTHORIZED/CRACKED TOOLS!" -ForegroundColor Red
} elseif ($isKMS) {
    Write-Host " [?] CONCLUSION: USING KMS CHANNEL. PLEASE VERIFY WITH YOUR ORGANIZATION." -ForegroundColor DarkYellow
} elseif ($isM365 -or $isVNext -or ($isLicensed -and -not $crackFound)) {
    Write-Host " [v] CONCLUSION: GENUINE OFFICE LICENSE, SYSTEM IS CLEAN!" -ForegroundColor Green
} else {
    Write-Host " [!] CONCLUSION: SYSTEM IS CLEAN BUT OFFICE IS NOT ACTIVATED." -ForegroundColor DarkYellow
}
Write-Host "==========================================================`n"

Write-Host "Press any key to exit..." -ForegroundColor White
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')