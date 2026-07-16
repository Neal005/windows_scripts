# ==============================================================================
# MICROSOFT OFFICE LICENSE STATUS CHECKER (V15 - VNEXT / WAM-AWARE)
# ==============================================================================
# Main changes from V14:
#   - Completely removed reliance on HKCU\...\Common\Identity (it is merely a login 
#     CACHE, not the actual license source - per Microsoft docs, these are separate: 
#     Part 1 = License/LicensingNext, Part 2 = Identity).
#   - Added vNext detection layer (Microsoft 365 from build 1910+):
#       1) vnextdiag.ps1  -> official native tool replacing ospp.vbs for vNext, 
#          located in the Office install directory (Office16), returning License 
#          Type (User|Subscription), SKU, License State, Email, Tenant Id.
#       2) HKCU\SOFTWARE\Microsoft\Office\16.0\Common\Licensing\LicensingNext
#          -> value "2" = product is using vNext activation mechanism.
#       3) %localappdata%\Microsoft\Office\Licenses\<number>\ -> actual token files, 
#          their existence is physical proof of account-based activation.
#   - License ID starting with "CWW" = Microsoft 365 Family/Personal (consumer),
#     "EWW" = Microsoft 365 for enterprise/business.
#   - Retained ospp.vbs for Office MSI/Volume (2016/2019/2021/LTSC) as it remains 
#     valid for those types.
# ==============================================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges to scan system..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   MICROSOFT OFFICE LICENSE CHECKER (V15 - VNEXT-AWARE)     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------
# HELPER FUNCTION: Determine the exact interactive logged-in user and return:
#   - Registry hive path (HKU\SID) ready to be read
#   - The ACTUAL LocalAppData path of that user (not the $env:LOCALAPPDATA 
#     of the admin process running the script)
# ------------------------------------------------------------------------
function Get-InteractiveUserContext {
    $result = [PSCustomObject]@{
        Success       = $false
        UserName      = $null
        SID           = $null
        HivePath      = $null
        TempLoaded    = $false
        TempHiveKey   = $null
        LocalAppData  = $null
    }

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $loggedUser = $cs.UserName
    } catch { $loggedUser = $null }

    if ([string]::IsNullOrWhiteSpace($loggedUser)) {
        try {
            $explorerProc = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop | Select-Object -First 1
            if ($explorerProc) {
                $owner = Invoke-CimMethod -InputObject $explorerProc -MethodName GetOwner
                if ($owner -and $owner.User) { $loggedUser = "$($owner.Domain)\$($owner.User)" }
            }
        } catch { }
    }

    if ([string]::IsNullOrWhiteSpace($loggedUser)) { return $result }
    $result.UserName = $loggedUser

    try {
        $sid = (New-Object System.Security.Principal.NTAccount($loggedUser)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $result.SID = $sid
    } catch { return $result }

    try {
        $profile = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$sid'" -ErrorAction Stop
        if ($profile) { $result.LocalAppData = Join-Path $profile.LocalPath "AppData\Local" }
    } catch { }

    if (Test-Path "Registry::HKEY_USERS\$sid") {
        $result.HivePath = "Registry::HKEY_USERS\$sid"
        $result.Success  = $true
        return $result
    }

    try {
        $profile = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$sid'" -ErrorAction Stop
        if ($profile) {
            $ntUserDat = Join-Path $profile.LocalPath "NTUSER.DAT"
            if (Test-Path -LiteralPath $ntUserDat) {
                $tempKeyName = "TempHive_$($sid -replace '[^a-zA-Z0-9]','')"
                & reg.exe load "HKU\$tempKeyName" "`"$ntUserDat`"" 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $result.HivePath    = "Registry::HKEY_USERS\$tempKeyName"
                    $result.TempLoaded  = $true
                    $result.TempHiveKey = $tempKeyName
                    $result.Success     = $true
                }
            }
        }
    } catch { }

    return $result
}

function Dismount-TempHive($ctx) {
    if ($ctx -and $ctx.TempLoaded -and $ctx.TempHiveKey) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers()
        & reg.exe unload "HKU\$($ctx.TempHiveKey)" 2>&1 | Out-Null
    }
}

# ==========================================================================
# STEP 1: RESOLVE INTERACTIVE LOGGED-IN USER (used for all subsequent steps)
# ==========================================================================
Write-Host "[1/5] Resolving correct interactive user context..." -ForegroundColor White
$ctx = Get-InteractiveUserContext
if ($ctx.Success) {
    Write-Host "  -> Interactive user resolved: $($ctx.UserName)" -ForegroundColor DarkGray
} else {
    Write-Host "  -> [!] Could not determine the logged-in user. Some checks may be inaccurate." -ForegroundColor Yellow
}

# ==========================================================================
# STEP 2: OSPP.VBS - ONLY USED FOR OFFICE MSI/VOLUME (2016/2019/2021/LTSC)
# NO longer used to conclude status for Microsoft 365 vNext.
# ==========================================================================
Write-Host "[2/5] Checking legacy OSPP engine (for MSI/Volume Office only)..." -ForegroundColor White

$osppPaths = @(
    "$env:ProgramFiles\Microsoft Office\root\Office16\ospp.vbs",
    "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\ospp.vbs",
    "$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs",
    "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs"
)
$ospp = $null
foreach ($p in $osppPaths) { if (Test-Path -LiteralPath $p) { $ospp = $p; break } }

$legacyLicensed = $false
$legacyGrace     = $false
$legacyKMS       = $false

if ($ospp) {
    Write-Host "  -> ospp.vbs found: $ospp" -ForegroundColor DarkGray
    $outputStr = (cscript.exe //nologo "`"$ospp`"" /dstatus 2>&1) -join "`n"
    if ($outputStr -match "---LICENSED---")        { $legacyLicensed = $true }
    if ($outputStr -match "OOB_GRACE|NOTIFICATION") { $legacyGrace    = $true }
    if ($outputStr -match "KMS_CLIENT")             { $legacyKMS      = $true }
} else {
    Write-Host "  -> ospp.vbs not found (normal for Microsoft 365 vNext / stripped-down Click-to-Run)." -ForegroundColor DarkGray
}

# ==========================================================================
# STEP 3: DETECT VNEXT (MICROSOFT 365 - BOTH CONSUMER AND ENTERPRISE)
# This is the true replacement layer for the blind spots of ospp.vbs / Identity cache.
# ==========================================================================
Write-Host "[3/5] Detecting modern vNext (WAM-based) Microsoft 365 licensing..." -ForegroundColor White

$vnextLicensed   = $false
$vnextInfo       = @()   # information lines for display
$vnextEmail      = $null
$vnextLicenseIds = @()

# --- 3a. Priority: run the native vnextdiag.ps1 tool (available from build 2104+) ---
$vnextDiagPaths = @(
    "$env:ProgramFiles\Microsoft Office\root\Office16\vnextdiag.ps1",
    "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\vnextdiag.ps1"
)
$vnextDiag = $null
foreach ($p in $vnextDiagPaths) { if (Test-Path -LiteralPath $p) { $vnextDiag = $p; break } }

if ($vnextDiag) {
    Write-Host "  -> vnextdiag.ps1 found: $vnextDiag" -ForegroundColor DarkGray
    try {
        $diagOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$vnextDiag" -action list 2>&1
        $diagStr = ($diagOutput | Out-String)

        # The exact format of vnextdiag.ps1 may vary between
        # Office builds, so use a "lenient" regex instead of rigid string matching.
        if ($diagStr -match "(?im)\bLicensed\b") { $vnextLicensed = $true }

        $emailMatch = [regex]::Match($diagStr, '[\w\.\-]+@[\w\.\-]+\.\w+')
        if ($emailMatch.Success) { $vnextEmail = $emailMatch.Value }

        $idMatches = [regex]::Matches($diagStr, '\b(EWW|CWW)[A-Za-z0-9_\-]*')
        foreach ($m in $idMatches) { $vnextLicenseIds += $m.Value }

        if ($vnextLicenseIds | Where-Object { $_ -match '^CWW' }) {
            $vnextInfo += "Detected CWW License ID -> Microsoft 365 Family/Personal (consumer)."
        }
        if ($vnextLicenseIds | Where-Object { $_ -match '^EWW' }) {
            $vnextInfo += "Detected EWW License ID -> Microsoft 365 for enterprise/business."
        }
    } catch {
        Write-Host "  -> [!] Cannot run vnextdiag.ps1: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  -> vnextdiag.ps1 not found (Office too old before 2104, or alternative path)." -ForegroundColor DarkGray
}

# --- 3b. Corroborate via LicensingNext Registry (value 2 = using vNext) ---
$licensingNextActive = $false
if ($ctx.Success) {
    $licensingNextPath = Join-Path $ctx.HivePath "SOFTWARE\Microsoft\Office\16.0\Common\Licensing\LicensingNext"
    if (Test-Path -LiteralPath $licensingNextPath) {
        $props = Get-ItemProperty -Path $licensingNextPath -ErrorAction SilentlyContinue
        if ($props) {
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -notmatch '^PS') {
                    if ($p.Value -eq 2) { $licensingNextActive = $true }
                }
            }
        }
    }
}
if ($licensingNextActive) {
    Write-Host "  -> LicensingNext Registry confirms at least 1 product is activated via vNext." -ForegroundColor DarkGray
}

# --- 3c. Corroborate via the existence of physical token files in %localappdata% ---
$licenseTokenFilesFound = $false
$localAppDataToCheck = if ($ctx.LocalAppData) { $ctx.LocalAppData } else { $env:LOCALAPPDATA }
$licensesFolder = Join-Path $localAppDataToCheck "Microsoft\Office\Licenses"
if (Test-Path -LiteralPath $licensesFolder) {
    $tokenFiles = Get-ChildItem -Path $licensesFolder -Recurse -File -ErrorAction SilentlyContinue
    if ($tokenFiles -and $tokenFiles.Count -gt 0) {
        $licenseTokenFilesFound = $true
        Write-Host "  -> Found $($tokenFiles.Count) vNext token files at: $licensesFolder" -ForegroundColor DarkGray
    }
}

if ($vnextEmail) {
    Write-Host "  -> Activating account (via vnextdiag.ps1): $vnextEmail" -ForegroundColor DarkGray
}

# Temporary vNext conclusion: prioritize actual results from vnextdiag.ps1 (Licensed).
# If the script cannot be run, use the 2 corroborating signals (registry + token file)
# as indirect evidence, but with lower confidence, treated only as "signs of activation".
$vnextStateConfirmed = $vnextLicensed
$vnextStateInferred   = (-not $vnextDiag) -and $licensingNextActive -and $licenseTokenFilesFound

# ==========================================================================
# STEP 4: SYNTHESIS -> DETERMINE VALID ACTIVATED STATE (A)
# ==========================================================================
$legacyActivated = ($legacyLicensed -and -not $legacyGrace)
$stateA = $legacyActivated -or $vnextStateConfirmed -or $vnextStateInferred

$activationMethodNote = if ($legacyActivated) {
    "Confirmed via ospp.vbs (Office MSI/Volume: Valid Key/KMS)."
} elseif ($vnextStateConfirmed) {
    "Confirmed via vnextdiag.ps1 (Microsoft 365 vNext - Licensed state)."
} elseif ($vnextStateInferred) {
    "Inferred via LicensingNext Registry + physical token files (vnextdiag.ps1 could not run for direct confirmation)."
} else { $null }

# ==========================================================================
# STEP 5: HEURISTIC SCAN - ONLY TO DISTINGUISH (B) vs (C), MUST NOT
# OVERRIDE CONCLUSION (A).
# ==========================================================================
Write-Host "[4/5] Running heuristic scan (illicit KMS / crack tools)..." -ForegroundColor DarkYellow

$crackFound = $false

$sppReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform" -ErrorAction SilentlyContinue
if ($sppReg -and -not [string]::IsNullOrWhiteSpace($sppReg.KeyManagementServiceName)) {
    $crackFound = $true
    Write-Host "  -> [!] Fake KMS Server found: $($sppReg.KeyManagementServiceName)" -ForegroundColor Red
}
if (Get-Process | Where-Object { $_.Name -match "(?i)vlmcsd|KMSAuto|KMSpico|SECOH-QAD" } -ErrorAction SilentlyContinue) {
    $crackFound = $true
    Write-Host "  -> [!] Malicious KMS emulator running in memory!" -ForegroundColor Red
}
if (Get-ScheduledTask | Where-Object { $_.TaskName -match "(?i)KMS|AutoKMS|SppExtComObjHook|KMSAuto|KMS-VL-ALL" } -ErrorAction SilentlyContinue) {
    $crackFound = $true
    Write-Host "  -> [!] Unauthorized automatic renewal task found." -ForegroundColor Red
}
$crackDirs = @("$env:SystemDrive\Windows\KMS", "$env:ProgramData\KMSAutoS", "$env:ProgramData\KMSAuto", "$env:ProgramFiles\KMSpico")
foreach ($dir in $crackDirs) {
    if (Test-Path -LiteralPath $dir) {
        $crackFound = $true
        Write-Host "  -> [!] Crack folder exists: $dir" -ForegroundColor Red
    }
}
if (-not $crackFound) {
    Write-Host "  -> No signs of illicit KMS / crack tools detected." -ForegroundColor DarkGray
}

Dismount-TempHive $ctx

# ==========================================================================
# STEP 6: FINAL CONCLUSION
# ==========================================================================
Write-Host "[5/5] Finalizing conclusion..." -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "                 FINAL SYSTEM CONCLUSION                  " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if ($stateA) {
    Write-Host " [v] (A) VALIDLY ACTIVATED" -ForegroundColor Green
    Write-Host "     -> $activationMethodNote" -ForegroundColor Gray
    if ($vnextEmail) { Write-Host "     -> Account: $vnextEmail" -ForegroundColor Gray }
    foreach ($note in $vnextInfo) { Write-Host "     -> $note" -ForegroundColor Gray }
    if ($legacyKMS) {
        Write-Host "     -> Note: using KMS Client (normal if this is an organizational/enterprise machine)." -ForegroundColor Gray
    }
    if ($crackFound) {
        Write-Host "     -> [Note] Trace amounts of KMS/crack tools were still detected," -ForegroundColor DarkYellow
        Write-Host "        but they do not affect the valid activation conclusion confirmed above." -ForegroundColor DarkYellow
    }
} elseif (-not $ospp -and -not $vnextDiag -and -not $licenseTokenFilesFound) {
    Write-Host " [?] No Microsoft Office installation detected on this machine (or Office has never been launched)." -ForegroundColor DarkGray
} elseif ($crackFound) {
    Write-Host " [!!!] (C) SYSTEM COMPROMISED: Illicit KMS / unauthorized crack tools detected!" -ForegroundColor Red
} else {
    Write-Host " [!] (B) UNACTIVATED / EXPIRED (Clean machine, no valid license)" -ForegroundColor Yellow
    if ($vnextDiag -and -not $vnextLicensed) {
        Write-Host "     -> vnextdiag.ps1 executed successfully but did not report a Licensed state." -ForegroundColor Gray
        Write-Host "     -> Please open an Office application and sign in with a licensed Microsoft 365 account." -ForegroundColor Gray
    } else {
        Write-Host "     -> Please sign in with a valid Microsoft account or enter a Product Key." -ForegroundColor Gray
    }
}

Write-Host "==========================================================`n"
Write-Host "Press any key to exit..." -ForegroundColor White
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')