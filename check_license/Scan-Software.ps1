# ==============================================================================
# UNAUTHORIZED SOFTWARE DETECTION TOOL (V16.1 - LITERAL PATH FIX)
# ==============================================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges to perform the check..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "       UNAUTHORIZED SOFTWARE DETECTION TOOL (V16.1)       " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " -> Exclusive feature: Deep Heuristic scan across the entire system." -ForegroundColor DarkGray
Write-Host " -> Note: The scan may take a while due to structural analysis of files.`n" -ForegroundColor DarkGray

$suspiciousExeList = @()
$unsignedExeList = @()

$emulatorConfigs = @("steam_emu.ini", "codex.ini", "skidrow.ini", "ali213.ini", "flt.ini", "3dmgame.ini", "valve.ini", "smartsteamemu.ini", "steam_appid.txt", "*.nfo")
$targetExtensions = @("*.exe", "*.dll")

$validPathsToScan = @()

# ------------------------------------------------------------------------------
Write-Host "SELECT SCAN MODE:" -ForegroundColor White
Write-Host " [1] Scan installed software/games (Automatically found via Registry)" -ForegroundColor Yellow
Write-Host " [2] Scan a specific custom directory (For Portable/Copied Games)" -ForegroundColor Yellow
$choice = Read-Host " -> Please enter your choice (1 or 2)"

if ($choice -eq "2") {
    $customPath = Read-Host " -> Enter the directory path to scan (e.g., C:\Program Files\Adobe)"
    if (Test-Path -LiteralPath $customPath) {
        $cleanCustomPath = $customPath.Trim().TrimEnd('\')
        $validPathsToScan += [PSCustomObject]@{ Name = "Custom Directory"; Path = $cleanCustomPath }
        Write-Host "`n -> Path accepted. Preparing to scan the entire directory: $cleanCustomPath`n" -ForegroundColor Green
    } else {
        Write-Host "`n[!] Invalid or non-existent path. The program will now exit!" -ForegroundColor Red
        Read-Host "Press Enter to exit..."
        exit
    }
} else {
    Write-Host "`n[1] Collecting all installation paths from the Registry..." -ForegroundColor Yellow
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
    Write-Host " -> Found $(($validPathsToScan).Count) independent directories for heuristic scanning.`n" -ForegroundColor Green
}

$totalApps = $validPathsToScan.Count
if ($totalApps -eq 0) {
    Write-Host "[!] Nothing to scan. The program will now exit!" -ForegroundColor DarkYellow
    Read-Host "Press Enter to exit..."
    exit
}

# ------------------------------------------------------------------------------
Write-Host "[2] STARTING STRUCTURAL ANALYSIS AND ANOMALY DETECTION..." -ForegroundColor Yellow

$counter = 0
foreach ($app in $validPathsToScan) {
    $counter++
    $percent = [math]::Round(($counter / $totalApps) * 100)
    Write-Progress -Activity "Analyzing system ($counter/$totalApps)" -Status "Processing: $($app.Name)" -PercentComplete $percent
    
    $targetPath = $app.Path
    if (-not $targetPath.EndsWith("\")) { $targetPath += "\" }
    $targetPath += "*"

    # Use LiteralPath fix for Get-ChildItem with base folder name
    $emuFiles = Get-ChildItem -Path $targetPath -Include $emulatorConfigs -Recurse -ErrorAction SilentlyContinue
    if ($emuFiles) {
        foreach ($emu in $emuFiles) {
            Write-Host " -> [DETECTED] Emulator environment / crack artifact: $($emu.Name)" -ForegroundColor Red
            $suspiciousExeList += "[Crack Artifact] $($emu.FullName)"
        }
    }

    $executables = Get-ChildItem -Path $targetPath -Include $targetExtensions -Recurse -ErrorAction SilentlyContinue
    foreach ($exe in $executables) {
        # FATAL FIX: Replace -FilePath with -LiteralPath to prevent square bracket [] errors
        $sig = Get-AuthenticodeSignature -LiteralPath $exe.FullName -ErrorAction SilentlyContinue
        
        if ($sig.Status -eq 'HashMismatch') {
            Write-Host " -> [DETECTED] File with error or crack malware signature: $($exe.Name)" -ForegroundColor Red
            $suspiciousExeList += "[Corrupted/Crack File] $($exe.FullName)"
        } elseif ($sig.Status -eq 'NotSigned' -and $exe.Extension -match "(?i)\.exe$") {
            Write-Host " -> [SUSPICIOUS] Unverified origin / requires further checking: $($exe.Name)" -ForegroundColor DarkYellow
            $unsignedExeList += "[Suspicious] $($exe.FullName)"
        }
    }
}
Write-Progress -Activity "Analyzing system" -Completed

# ------------------------------------------------------------------------------
$suspiciousExeList = $suspiciousExeList | Where-Object { $_ -ne $null }
$unsignedExeList = $unsignedExeList | Where-Object { $_ -ne $null }

$finalEmuCount = @($suspiciousExeList | Where-Object { $_ -match "Crack Artifact" }).Count
$finalSigCount = @($suspiciousExeList | Where-Object { $_ -match "Corrupted/Crack File" }).Count
$finalUnsignedCount = $unsignedExeList.Count

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "          ANALYSIS SUMMARY AND METRICS                    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

Write-Host " [1] Emulator environment / Junk : $finalEmuCount detected items" -ForegroundColor Red
Write-Host " [2] Corrupted / Malware files   : $finalSigCount detected items" -ForegroundColor Red
Write-Host " [3] Unauthenticated files       : $finalUnsignedCount suspicious items" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------"

if ($suspiciousExeList.Count -gt 0) {
    Write-Host " LIST OF DANGEROUS / CRACK DETECTED FILES (RED):" -ForegroundColor Red
    foreach ($exePath in $suspiciousExeList) {
        Write-Host "  -> $exePath" -ForegroundColor DarkRed
    }
    Write-Host "----------------------------------------------------------"
}

if ($finalUnsignedCount -gt 0) {
    Write-Host " LIST OF UNVERIFIED FILES (YELLOW):" -ForegroundColor Yellow
    foreach ($exePath in $unsignedExeList) {
        Write-Host "  -> $exePath" -ForegroundColor DarkYellow
    }
    Write-Host "----------------------------------------------------------"
}

if (($finalSigCount + $finalEmuCount) -gt 0) {
    Write-Host " [!] CONCLUSION: THE SYSTEM CONTAINS TAMPERED SOFTWARE/GAMES!" -ForegroundColor Red
} elseif ($finalUnsignedCount -gt 0) {
    Write-Host " [?] CONCLUSION: SUSPICIOUS FILES FOUND. MANUAL REVIEW REQUIRED!" -ForegroundColor DarkYellow
} else {
    Write-Host " [v] CONCLUSION: THE SYSTEM IS COMPLETELY CLEAN AND GENUINE!" -ForegroundColor Green
}

Write-Host "==========================================================`n"

Read-Host -Prompt "Press Enter to exit the program..."