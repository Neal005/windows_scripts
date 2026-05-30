# ==============================================================================
# SCRIPT KIEM TRA BAN QUYEN OFFICE (V8 - WMI/CIM ULTIMATE THANH BACH)
# ==============================================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Dang yeu cau cap quyen Administrator de quet loi he thong..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   KIEM TRA TRANG THAI BAN QUYEN MICROSOFT OFFICE (V8)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Kiem tra vNext Cloud Token xịn (Quet tat ca User)
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

# 2. Doc ban quyen bang WMI/CIM (Tuyet chieu xuyen ngon ngu, sieu toc)
Write-Host "Dang truy van WMI doc Object ban quyen Office..." -ForegroundColor White

# ApplicationID cua Office luon la 0ff1ce15-a989-479d-af46-f275c6370663
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

        # Trang thai LicenseStatus: 1 = Licensed, 2/3/4/5/6 = Grace/Notification (Chua/Loi Kich hoat)
        if ($desc -match "(?i)O365|TIMEBASED_SUB|Subscription") { $isM365 = $true }
        if ($desc -match "(?i)KMS_Client|VOLUME_KMSCLIENT") { $isKMS = $true }
        
        if ($status -eq 1) { $isLicensed = $true }
        elseif ($status -in 2..6) { $isGrace = $true }
    }
}

Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
if ($isVNext) {
    Write-Host " [+] TRANG THAI OFFICE: MICROSOFT 365 (vNext CLOUD TOKEN)" -ForegroundColor Green
    Write-Host "   -> Giay phep dam may the he moi xịn 100%." -ForegroundColor Green
} elseif ($isM365) {
    Write-Host " [+] TRANG THAI OFFICE: MICROSOFT 365 (SUBSCRIPTION)" -ForegroundColor Green
} elseif ($isKMS) {
    Write-Host " [?] TRANG THAI OFFICE: GIAY PHEP DOANH NGHIEP (KMS CLIENT)" -ForegroundColor Yellow
} elseif ($isLicensed) {
    Write-Host " [+] TRANG THAI OFFICE: DA KICH HOAT (LICENSED)" -ForegroundColor Green
} elseif ($isGrace) {
    Write-Host " [-] TRANG THAI OFFICE: CHUA KICH HOAT (TRIAL / GRACE PERIOD)" -ForegroundColor Red
} else {
    Write-Host " [!] TRANG THAI OFFICE: KHONG XAC DINH HOAC CHUA CAI DAT" -ForegroundColor DarkYellow
}

# 3. QUET HEURISTIC TOAN DIEN (KHONG DUNG -DEPTH DE DIET TẬN GỐC OHOOK)
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Dang quet Heuristic tim dau hieu can thiep cua Tool Crack..." -ForegroundColor White
$crackFound = $false

$sppReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform" -ErrorAction SilentlyContinue
if ($sppReg -and -not [string]::IsNullOrWhiteSpace($sppReg.KeyManagementServiceName)) {
    $crackFound = $true
    Write-Host " -> [PHAT HIEN CRACK] May chu KMS lau: $($sppReg.KeyManagementServiceName)" -ForegroundColor Red
}

$officeInstallPaths = @("$env:ProgramFiles\Microsoft Office", "${env:ProgramFiles(x86)}\Microsoft Office")
foreach ($installPath in $officeInstallPaths) {
    if (Test-Path -LiteralPath $installPath) {
        $fakeDlls = Get-ChildItem -Path $installPath -Filter "sppc.dll" -Recurse -ErrorAction SilentlyContinue
        foreach ($dll in $fakeDlls) {
            $sig = Get-AuthenticodeSignature -LiteralPath $dll.FullName -ErrorAction SilentlyContinue
            if ($sig.Status -ne 'Valid') {
                $crackFound = $true
                Write-Host " -> [PHAT HIEN CRACK] File Ohook gia mao lẩn trốn: $($dll.FullName)" -ForegroundColor Red
            }
        }
    }
}

$kmsTasks = Get-ScheduledTask | Where-Object { $_.TaskName -match "(?i)KMS|AutoKMS|SppExtComObjHook" } -ErrorAction SilentlyContinue
if ($kmsTasks) {
    $crackFound = $true
    Write-Host " -> [PHAT HIEN CRACK] Tac vu tu dong gia han lau:" -ForegroundColor Red
    foreach ($task in $kmsTasks) { Write-Host "    + $($task.TaskName)" -ForegroundColor DarkRed }
}

$ohookReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\sppsvc.exe" -ErrorAction SilentlyContinue
if ($ohookReg) {
    $crackFound = $true
    Write-Host " -> [PHAT HIEN CRACK] Registry bi thay doi (Ohook Bypass)!" -ForegroundColor Red
}

$crackDirs = @("$env:SystemDrive\Windows\KMS", "$env:ProgramData\KMSAutoS", "$env:ProgramData\KMSAuto")
foreach ($dir in $crackDirs) {
    if (Test-Path -LiteralPath $dir) {
        $crackFound = $true
        Write-Host " -> [PHAT HIEN CRACK] Ton tai thu muc rac crack: $dir" -ForegroundColor Red
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
if ($crackFound) {
    Write-Host " [!!!] KET LUAN: OFFICE DANG DUNG HANG CRACK/LAU (BO DOI CUNG BI TOM)!" -ForegroundColor Red
} elseif ($isKMS) {
    Write-Host " [?] KET LUAN: DUNG KENH KMS, CAN XAC MINH LAI VOI CONG TY." -ForegroundColor DarkYellow
} elseif ($isM365 -or $isVNext -or ($isLicensed -and -not $crackFound)) {
    Write-Host " [v] KET LUAN: OFFICE BAN QUYEN XIN, CHUAN THANH BACH!" -ForegroundColor Green
} else {
    Write-Host " [!] KET LUAN: HE THONG SACH SE NHUNG OFFICE CHUA DUOC KICH HOAT." -ForegroundColor DarkYellow
}
Write-Host "==========================================================`n"

Write-Host "Nhan phim bat ky de thoat..." -ForegroundColor White
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')