<#
.SYNOPSIS
    Automatically reboots Windows 11 directly into BIOS/UEFI firmware settings.

.DESCRIPTION
    - Checks whether the script is currently running with Administrator privileges.
    - If not running as Administrator, the script relaunches itself elevated
      (triggering a UAC prompt) and exits the current non-elevated process.
    - Once running as Administrator, it asks for confirmation before rebooting,
      since the machine will restart immediately into firmware setup instead of Windows.

.NOTES
    Requirement: Windows 8/10/11 with UEFI firmware (does not work on pure Legacy BIOS).
    Core command: shutdown.exe /r /fw /t 0
#>

# ============================================================
# STEP 1: Check for Administrator privileges
# ============================================================
function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host "Script is not running as Administrator. Requesting elevation (UAC)..." -ForegroundColor Yellow

    # Get the full path of this script
    $scriptPath = $MyInvocation.MyCommand.Definition

    try {
        # Relaunch PowerShell with admin rights, running this same script again
        Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
            -Verb RunAs

        Write-Host "Elevation request sent. Please confirm the UAC prompt in the new window." -ForegroundColor Cyan
    }
    catch {
        Write-Host "The UAC prompt was cancelled or an error occurred: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Exit the current non-elevated process (nothing more can be done without admin rights)
    exit
}

# ============================================================
# STEP 2: Already running as Administrator -> Confirm before reboot
# ============================================================
Write-Host "Running with Administrator privileges." -ForegroundColor Green
Write-Host ""
Write-Host "WARNING: The computer will RESTART IMMEDIATELY and boot straight into BIOS/UEFI Setup." -ForegroundColor Yellow
Write-Host "Please save and close any unsaved work before continuing." -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Are you sure you want to reboot into BIOS now? (Y/N)"

if ($confirm -match '^[Yy]') {
    Write-Host "Rebooting into BIOS/UEFI..." -ForegroundColor Cyan
    Start-Sleep -Seconds 2
    # Official Windows command to reboot directly into firmware setup (UEFI only)
    shutdown.exe /r /fw /t 0
}
else {
    Write-Host "Operation cancelled. No changes were made." -ForegroundColor Gray
}
