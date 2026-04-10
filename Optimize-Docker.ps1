# BUOC 1: Tu dong xin quyen Administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Dang xin quyen Admin..." -ForegroundColor Yellow
    # Goi lai chinh script nay nhung voi co RunAs (chay duoi quyen Admin)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $startInfo.Verb = "RunAs"
    [System.Diagnostics.Process]::Start($startInfo) | Out-Null
    Exit # Tat cua so cu khong co quyen
}

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "           SCRIPT EP DUNG LUONG DOCKER TU DONG           " -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

# BUOC 2: Yeu cau nguoi dung nhap duong dan
$vhdxPath = Read-Host "Sep vui long nhap duong dan tuyet doi den file .vhdx (vd: D:\Docker\docker_data.vhdx)"

# Xoa dau ngoac kep neu sep lo copy thua
$vhdxPath = $vhdxPath -replace '"', ''

# Kiem tra sao huyet co ton tai khong
if (-Not (Test-Path -Path $vhdxPath -PathType Leaf)) {
    Write-Host "[LOI] Khong tim thay file tai duong dan: $vhdxPath! Sep check lai nhe." -ForegroundColor Red
    Pause
    Exit
}

if ($vhdxPath -notmatch "\.vhdx$") {
    Write-Host "[LOI] File phai co duoi .vhdx sep nhe!" -ForegroundColor Red
    Pause
    Exit
}

Write-Host "[1/2] Dang ep tat Docker Desktop va WSL..." -ForegroundColor Yellow
Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "com.docker.backend" -Force -ErrorAction SilentlyContinue
wsl --shutdown
Start-Sleep -Seconds 2

# BUOC 3: Bum! Moi thu hoan tat
Write-Host "[2/2] Dang chay Diskpart de ep dung luong cho file: $vhdxPath..." -ForegroundColor Magenta

# Tao file kich ban tam cho diskpart
$diskpartScriptPath = "$env:TEMP\diskpart_script.txt"
@"
select vdisk file="$vhdxPath"
compact vdisk
exit
"@ | Out-File -FilePath $diskpartScriptPath -Encoding ASCII

# Chay ngam diskpart
$process = Start-Process -FilePath "diskpart" -ArgumentList "/s `"$diskpartScriptPath`"" -Wait -NoNewWindow -PassThru
Remove-Item -Path $diskpartScriptPath -ErrorAction SilentlyContinue

if ($process.ExitCode -eq 0) {
    Write-Host "`n[OK] Ep dung luong thanh cong! Moi thu da hoan tat.`n" -ForegroundColor Green
} else {
    Write-Host "`n[LOI] Qua trinh ep that bai (Ma loi: $($process.ExitCode))." -ForegroundColor Red
}

Write-Host "`nDa xong nhiem vu! Nhan phim bat ky de thoat..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')