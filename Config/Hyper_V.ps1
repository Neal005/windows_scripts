# Automatically request Admin privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    # Relaunch this file with Admin rights and bypass ExecutionPolicy
    Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

function Show-Menu {
    Clear-Host
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "==        HYPER-V STATUS MANAGER       ==" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check current Hyper-V status
    $bcdeditOutput = bcdedit
    Write-Host "Current Hyper-V Status: " -NoNewline
    if ($bcdeditOutput -match "hypervisorlaunchtype\s+Auto") {
        Write-Host "[ ON (Auto) ]" -ForegroundColor Green
    } else {
        Write-Host "[ OFF ]" -ForegroundColor Red
    }
    Write-Host ""

    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "1. Turn ON Hyper-V (To run Docker/WSL)"
    Write-Host "2. Turn OFF Hyper-V (For emulators, etc.)"
    Write-Host "3. Exit"
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""

    $choice = Read-Host "Please select an option (1-3)"
    return $choice
}

$userChoice = Show-Menu

switch ($userChoice) {
    '1' {
        Write-Host "`nTurning ON Hyper-V..." -ForegroundColor Yellow
        bcdedit /set hypervisorlaunchtype auto | Out-Null
        Write-Host "Successfully turned ON!" -ForegroundColor Green
    }
    '2' {
        Write-Host "`nTurning OFF Hyper-V..." -ForegroundColor Yellow
        bcdedit /set hypervisorlaunchtype off | Out-Null
        Write-Host "Successfully turned OFF!" -ForegroundColor Green
    }
    '3' {
        exit
    }
    default {
        Write-Host "Invalid choice. Exiting..." -ForegroundColor Red
        Start-Sleep -Seconds 2
        exit
    }
}

# Ask for reboot
Write-Host "`n== CHANGES COMPLETED! ==" -ForegroundColor Cyan
$restartChoice = Read-Host "Do you want to restart your computer now? (Y/N)"

if ($restartChoice -eq 'Y' -or $restartChoice -eq 'y') {
    Write-Host "Restarting computer in 5 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    Write-Host "Acknowledged. Remember to restart later to apply the changes." -ForegroundColor Green
    Write-Host "Press Enter to exit..."
    Read-Host
}