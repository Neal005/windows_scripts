# ==============================================================================
# SCRIPT QUET DAU HIEU PHAN MEM KHONG BAN QUYEN (V16.1 - LITERAL PATH FIX)
# ==============================================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Dang yeu cau cap quyen Administrator de kiem tra..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   CONG CU QUET DAU HIEU PHAN MEM KHONG BAN QUYEN (V16.1) " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " -> Phien ban doc quyen: Quet Heuristic sau toan bo he thong." -ForegroundColor DarkGray
Write-Host " -> Chu y: Thoi gian quet se lau do phai phan tich cau truc file.`n" -ForegroundColor DarkGray

$suspiciousExeList = @()
$unsignedExeList = @()

$emulatorConfigs = @("steam_emu.ini", "codex.ini", "skidrow.ini", "ali213.ini", "flt.ini", "3dmgame.ini", "valve.ini", "smartsteamemu.ini", "steam_appid.txt", "*.nfo")
$targetExtensions = @("*.exe", "*.dll")

$validPathsToScan = @()

# ------------------------------------------------------------------------------
Write-Host "CHON CHE DO QUET:" -ForegroundColor White
Write-Host " [1] Quet cac phan mem/game da cai dat (Tu dong tim qua Registry)" -ForegroundColor Yellow
Write-Host " [2] Quet mot thu muc bat ky (Dung cho Game Copy/Portable)" -ForegroundColor Yellow
$choice = Read-Host " -> Vui long nhap lua chon (1 hoac 2)"

if ($choice -eq "2") {
    $customPath = Read-Host " -> Nhap duong dan thu muc can quet (VD: C:\Program Files\Adobe)"
    if (Test-Path -LiteralPath $customPath) {
        $cleanCustomPath = $customPath.Trim().TrimEnd('\')
        $validPathsToScan += [PSCustomObject]@{ Name = "Thu muc Custom"; Path = $cleanCustomPath }
        Write-Host "`n -> Da nhan duong dan. Dang chuan bi quet toan bo thu muc: $cleanCustomPath`n" -ForegroundColor Green
    } else {
        Write-Host "`n[!] Duong dan khong hop le hoac khong ton tai. Chuong trinh se thoat!" -ForegroundColor Red
        Read-Host "Nhan Enter de thoat..."
        exit
    }
} else {
    Write-Host "`n[1] Dang thu thap toan bo duong dan cai dat tu Registry..." -ForegroundColor Yellow
    $registryPaths = @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*")
    $installedApps = Get-ItemProperty $registryPaths -ErrorAction SilentlyContinue | Select-Object DisplayName, InstallLocation | Where-Object { $_.DisplayName -ne $null }

    foreach ($app in $installedApps) {
        if (-not [string]::IsNullOrWhiteSpace($app.InstallLocation)) {
            $cleanPath = $app.InstallLocation.Trim().TrimEnd('\')
            if ((Test-Path -LiteralPath $cleanPath) -and $cleanPath.Length -gt 3 -and $cleanPath -notmatch "(?i)\\Windows\\") {
                $validPathsToScan += [PSCustomObject]@{ Name = $app.DisplayName; Path = $cleanPath }
            }
        }
    }
    
    $validPathsToScan = $validPathsToScan | Sort-Object -Property Path -Unique
    Write-Host " -> Da tim thay $(($validPathsToScan).Count) thu muc doc lap de quet heuristic.`n" -ForegroundColor Green
}

$totalApps = $validPathsToScan.Count
if ($totalApps -eq 0) {
    Write-Host "[!] Khong co gi de quet. Chuong trinh se thoat!" -ForegroundColor DarkYellow
    Read-Host "Nhan Enter de thoat..."
    exit
}

# ------------------------------------------------------------------------------
Write-Host "[2] BAT DAU PHAN TICH CAU TRUC VA DAU HIEU BAT THUONG..." -ForegroundColor Yellow

$counter = 0
foreach ($app in $validPathsToScan) {
    $counter++
    $percent = [math]::Round(($counter / $totalApps) * 100)
    Write-Progress -Activity "Dang phan tich he thong ($counter/$totalApps)" -Status "Dang xu ly: $($app.Name)" -PercentComplete $percent
    
    $targetPath = $app.Path
    if (-not $targetPath.EndsWith("\")) { $targetPath += "\" }
    $targetPath += "*"

    # Fix -LiteralPath cho Get-ChildItem bang cach dung -Path ket hop voi ten thu muc goc
    $emuFiles = Get-ChildItem -Path $targetPath -Include $emulatorConfigs -Recurse -ErrorAction SilentlyContinue
    if ($emuFiles) {
        foreach ($emu in $emuFiles) {
            Write-Host " -> [PHAT HIEN] File moi truong gia lap / rac crack: $($emu.Name)" -ForegroundColor Red
            $suspiciousExeList += "[Rac Crack] $($emu.FullName)"
        }
    }

    $executables = Get-ChildItem -Path $targetPath -Include $targetExtensions -Recurse -ErrorAction SilentlyContinue
    foreach ($exe in $executables) {
        # FIX CHI MANG: Thay -FilePath bang -LiteralPath de chong loi ngoac vuong []
        $sig = Get-AuthenticodeSignature -LiteralPath $exe.FullName -ErrorAction SilentlyContinue
        
        if ($sig.Status -eq 'HashMismatch') {
            Write-Host " -> [PHAT HIEN] File co dau hieu loi / ma doc crack: $($exe.Name)" -ForegroundColor Red
            $suspiciousExeList += "[File Loi/Crack] $($exe.FullName)"
        } elseif ($sig.Status -eq 'NotSigned' -and $exe.Extension -match "(?i)\.exe$") {
            Write-Host " -> [NGHI VAN] File khong ro nguon goc / can kiem tra them: $($exe.Name)" -ForegroundColor DarkYellow
            $unsignedExeList += "[Nghi Van] $($exe.FullName)"
        }
    }
}
Write-Progress -Activity "Dang phan tich he thong" -Completed

# ------------------------------------------------------------------------------
$suspiciousExeList = $suspiciousExeList | Where-Object { $_ -ne $null }
$unsignedExeList = $unsignedExeList | Where-Object { $_ -ne $null }

$finalEmuCount = @($suspiciousExeList | Where-Object { $_ -match "Rac Crack" }).Count
$finalSigCount = @($suspiciousExeList | Where-Object { $_ -match "File Loi/Crack" }).Count
$finalUnsignedCount = $unsignedExeList.Count

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "   BANG TONG KET SO LIEU PHAN TICH                        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

Write-Host " [1] Moi truong gia lap / rac: $finalEmuCount muc phat hien" -ForegroundColor Red
Write-Host " [2] Tap tin loi / ma doc    : $finalSigCount muc phat hien" -ForegroundColor Red
Write-Host " [3] Tap tin chua xac thuc   : $finalUnsignedCount muc nghi van" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------"

if ($suspiciousExeList.Count -gt 0) {
    Write-Host " DANH SACH TAP TIN NGUY HIEM / DAU HIEU CRACK (DO):" -ForegroundColor Red
    foreach ($exePath in $suspiciousExeList) {
        Write-Host "  -> $exePath" -ForegroundColor DarkRed
    }
    Write-Host "----------------------------------------------------------"
}

if ($finalUnsignedCount -gt 0) {
    Write-Host " DANH SACH TAP TIN KHONG RO NGUON GOC (VANG):" -ForegroundColor Yellow
    foreach ($exePath in $unsignedExeList) {
        Write-Host "  -> $exePath" -ForegroundColor DarkYellow
    }
    Write-Host "----------------------------------------------------------"
}

if (($finalSigCount + $finalEmuCount) -gt 0) {
    Write-Host " [!] KET LUAN: HE THONG CO CHUA PHAN MEM / GAME DA BI CAN THIEP!" -ForegroundColor Red
} elseif ($finalUnsignedCount -gt 0) {
    Write-Host " [?] KET LUAN: CO CHUA TAP TIN DANG NGO. CAN RA SOAT THU CONG!" -ForegroundColor DarkYellow
} else {
    Write-Host " [v] KET LUAN: MAY TINH HOAN TOAN SACH SE, CHUAN THANH BACH!" -ForegroundColor Green
}

Write-Host "==========================================================`n"

Read-Host -Prompt "Nhan Enter de thoat chuong trinh..."