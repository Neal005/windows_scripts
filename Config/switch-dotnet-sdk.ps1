param (
    [string]$Scope = ""
)

$ErrorActionPreference = "Stop"

# Check Admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($Scope -eq "") {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "SELECT SDK APPLICATION SCOPE:" -ForegroundColor Yellow
    Write-Host "  [1] Current Directory ($PWD)"
    Write-Host "  [2] Entire Computer (All Drives)"
    $scopeChoice = Read-Host "Enter scope choice (1 or 2)"
} else {
    $scopeChoice = $Scope
}

if ($scopeChoice -eq "2") {
    if (-not $isAdmin) {
        Write-Host "Administrator privileges are required to write to system drives!" -ForegroundColor Yellow
        Write-Host "Relaunching this window with Admin privileges..." -ForegroundColor Cyan
        
        # Relaunch this file with -Scope 2 parameter so the new window won't ask again
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Scope 2"
        exit
    }
} elseif ($scopeChoice -ne "1") {
    Write-Host "Invalid choice. Operation canceled!" -ForegroundColor Red
    if ($isAdmin) { Read-Host "Press Enter to exit..." }
    exit
}

# Get current SDK version
$currentSdk = (dotnet --version).Trim()

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Currently Active .NET SDK Version: $currentSdk" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "AVAILABLE SDkS FOR SWITCHING:" -ForegroundColor Yellow

$sdks = dotnet --list-sdks
if (-not $sdks) {
    Write-Host "No .NET SDKs found on the system!" -ForegroundColor Red
    if ($isAdmin) { Read-Host "Press Enter to exit..." }
    exit
}

$sdkArray = @()
$i = 1

foreach ($sdk in $sdks) {
    if ($sdk -match "^(\d+\.\d+\.\d+.*?)\s+\[") {
        $version = $matches[1]
        
        if ($version -eq $currentSdk) {
            Write-Host "  [-] $version (Currently In Use)" -ForegroundColor Green
        } else {
            Write-Host "  [$i] $version"
            $sdkArray += @{ Index = $i; Version = $version }
            $i++
        }
    }
}

if ($sdkArray.Count -eq 0) {
    Write-Host "No other SDK versions available to switch to." -ForegroundColor Yellow
    if ($isAdmin) { Read-Host "Press Enter to exit..." }
    exit
}

Write-Host "----------------------------------------" -ForegroundColor Cyan
$choice = Read-Host "Enter the number to select an SDK (Press Enter to exit)"

if ([string]::IsNullOrWhiteSpace($choice)) {
    Write-Host "Operation canceled."
    if ($isAdmin) { Read-Host "Press Enter to exit..." }
    exit
}

$choiceInt = $choice -as [int]
$selectedObj = $sdkArray | Where-Object { $_.Index -eq $choiceInt }

if (-not $selectedObj) {
    Write-Host "Invalid choice!" -ForegroundColor Red
    if ($isAdmin) { Read-Host "Press Enter to exit..." }
    exit
}

$selectedSdk = $selectedObj.Version

Write-Host "----------------------------------------" -ForegroundColor Cyan

if ($scopeChoice -eq "2") {
    Write-Host "Setting SDK $selectedSdk for the ENTIRE COMPUTER..." -ForegroundColor Yellow
    
    $drives = Get-PSDrive -PSProvider FileSystem
    $oldPwd = $PWD
    foreach ($drive in $drives) {
        $rootPath = $drive.Root
        $globalJsonPath = Join-Path -Path $rootPath -ChildPath "global.json"
        
        try {
            Set-Location -Path $rootPath -ErrorAction Stop
            dotnet new globaljson --sdk-version $selectedSdk --force | Out-Null
            Write-Host "Successfully updated $globalJsonPath" -ForegroundColor Green
        } catch {
            Write-Host "Skipped drive $rootPath (Permission denied or locked)" -ForegroundColor DarkGray
        }
    }
    Set-Location -Path $oldPwd
} else {
    Write-Host "Setting SDK $selectedSdk for the CURRENT DIRECTORY..." -ForegroundColor Yellow
    dotnet new globaljson --sdk-version $selectedSdk --force | Out-Null
    Write-Host "Success! global.json has been updated in the current directory." -ForegroundColor Green
}

# Verify current active version again
$newVer = (dotnet --version).Trim()
Write-Host "Current active version is now: $newVer" -ForegroundColor Magenta

# Prevent window from closing immediately when run as Admin
if ($isAdmin) {
    Write-Host "Press Enter to exit..."
    Read-Host
}
