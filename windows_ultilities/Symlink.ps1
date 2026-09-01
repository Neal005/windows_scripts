<#
.SYNOPSIS
    Script to create Symbolic Link or Junction for a directory on Windows.
.DESCRIPTION
    This script requires Administrator privileges. 
    Supports choosing between Symlink (/D) and Directory Junction (/J).
#>

# 1. Check for Administrator privileges
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    
    Write-Host "Script is requesting Admin privileges to continue..." -ForegroundColor Yellow
    
    # If no privileges, automatically relaunch this file with Admin rights
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    
    # Exit the old process to prevent running code twice
    Exit
}

Clear-Host
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "       ADVANCED DIRECTORY LINK TOOL          " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# 2. Enter TARGET directory path (Real data location)
Write-Host "[1] Enter TARGET directory path (Where the real data is stored):" -ForegroundColor Yellow
$targetPath = Read-Host
$targetPath = $targetPath.Trim('"') # Remove quotes

if (-not (Test-Path -Path $targetPath)) {
    Write-Error "Error: Target directory does not exist! Please check the path."
    Pause
    Exit
}

# 3. Enter LINK directory path (Virtual folder to be created)
Write-Host ""
Write-Host "[2] Enter LINK directory path (Name of the virtual folder to create):" -ForegroundColor Yellow
$linkPath = Read-Host
$linkPath = $linkPath.Trim('"')

if (Test-Path -Path $linkPath) {
    Write-Error "Error: Link path already exists. Please delete it before creating a Link."
    Pause
    Exit
}

# 4. Select link type (Junction or Symlink)
Write-Host ""
Write-Host "[3] Choose the type of link to create:" -ForegroundColor Yellow
Write-Host "    [J] Junction (Recommended for Local Disk, more stable, fixes Watchman errors)" -ForegroundColor Gray
Write-Host "    [S] Symlink  (Traditional soft link)" -ForegroundColor Gray

$validChoice = $false
$linkType = ""

do {
    $choice = Read-Host "    Enter your choice (J or S)"
    $choice = $choice.ToUpper()
    if ($choice -eq "J" -or $choice -eq "S") {
        $validChoice = $true
        $linkType = $choice
    } else {
        Write-Warning "    Invalid choice. Please enter 'J' or 'S'."
    }
} until ($validChoice)

# 5. Execute Link creation
Write-Host ""
Write-Host "Creating link..." -ForegroundColor Green

try {
    if ($linkType -eq "J") {
        # Create Junction Point
        New-Item -ItemType Junction -Path $linkPath -Target $targetPath -ErrorAction Stop | Out-Null
        $typeMsg = "Directory Junction (/J)"
    }
    else {
        # Create Symbolic Link
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $targetPath -ErrorAction Stop | Out-Null
        $typeMsg = "Symbolic Link (/D)"
    }
    
    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host " SUCCESS! $typeMsg was created at:" -ForegroundColor Cyan
    Write-Host " $linkPath"
    Write-Host " -> Pointing to: $targetPath"
    Write-Host "------------------------------------------"
}
catch {
    Write-Host ""
    Write-Error "AN ERROR OCCURRED:"
    Write-Error $_.Exception.Message
    if ($linkType -eq "J") {
        Write-Warning "Note: Junctions only work on the same drive or between Local drives. Not for Network Shares."
    }
}

Write-Host ""
Pause