# Tự động xin quyền Admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Dang yeu cau quyen Administrator..." -ForegroundColor Yellow
    # Mở lại chính file này với quyền Admin và bỏ qua ExecutionPolicy
    Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

function Show-Menu {
    Clear-Host
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "==      QUAN LY TRANG THAI HYPER-V     ==" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""

    # Kiểm tra trạng thái Hyper-V hiện tại
    $bcdeditOutput = bcdedit
    Write-Host "Trang thai hien tai cua Hyper-V: " -NoNewline
    if ($bcdeditOutput -match "hypervisorlaunchtype\s+Auto") {
        Write-Host "[ DANG BAT (Auto) ]" -ForegroundColor Green
    } else {
        Write-Host "[ DANG TAT (Off) ]" -ForegroundColor Red
    }
    Write-Host ""

    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "1. BAT Hyper-V (De chay Docker/WSL)"
    Write-Host "2. TAT Hyper-V (De choi game gia lap, v.v.)"
    Write-Host "3. Thoat"
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""

    $choice = Read-Host "Moi sep chon thao tac (1-3)"
    return $choice
}

$userChoice = Show-Menu

switch ($userChoice) {
    '1' {
        Write-Host "`nDang BAT Hyper-V..." -ForegroundColor Yellow
        bcdedit /set hypervisorlaunchtype auto | Out-Null
        Write-Host "Da BAT thanh cong!" -ForegroundColor Green
    }
    '2' {
        Write-Host "`nDang TAT Hyper-V..." -ForegroundColor Yellow
        bcdedit /set hypervisorlaunchtype off | Out-Null
        Write-Host "Da TAT thanh cong!" -ForegroundColor Green
    }
    '3' {
        exit
    }
    default {
        Write-Host "Lua chon khong hop le. Dang thoat..." -ForegroundColor Red
        Start-Sleep -Seconds 2
        exit
    }
}

# Hỏi khởi động lại
Write-Host "`n== HOAN TAT THAY DOI! ==" -ForegroundColor Cyan
$restartChoice = Read-Host "Sep co muon khoi dong lai may tinh ngay bay gio khong? (Y/N)"

if ($restartChoice -eq 'Y' -or $restartChoice -eq 'y') {
    Write-Host "Dang khoi dong lai may sau 5 giay..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    Write-Host "OK sep. Nho khoi dong lai may sau de ap dung cac thay doi tren nhe." -ForegroundColor Green
    Write-Host "Bam phim Enter de thoat..."
    Read-Host
}