# STEP 1: Automatically request Administrator privileges
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Requesting Admin privileges..." -ForegroundColor Yellow
    # Call this script again but with RunAs (run as Admin)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $startInfo.Verb = "RunAs"
    [System.Diagnostics.Process]::Start($startInfo) | Out-Null
    Exit # Close the old window without privileges
}

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "           DOCKER DISK COMPACTION SCRIPT                 " -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

# STEP 2: Prompt user to enter path
$vhdxPath = Read-Host "Please enter the absolute path to the .vhdx file (e.g., D:\Docker\docker_data.vhdx)"

# Remove quotes if accidentally copied
$vhdxPath = $vhdxPath -replace '"', ''

# Check if file exists
if (-Not (Test-Path -Path $vhdxPath -PathType Leaf)) {
    Write-Host "[ERROR] File not found at: $vhdxPath! Please check again." -ForegroundColor Red
    Pause
    Exit
}

if ($vhdxPath -notmatch "\.vhdx$") {
    Write-Host "[ERROR] The file must have a .vhdx extension!" -ForegroundColor Red
    Pause
    Exit
}

Write-Host "[1/2] Forcing Docker Desktop and WSL to shut down..." -ForegroundColor Yellow
Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "com.docker.backend" -Force -ErrorAction SilentlyContinue
wsl --shutdown
Start-Sleep -Seconds 2

# STEP 3: Execute compaction
Write-Host "[2/2] Running Diskpart to compact the file: $vhdxPath..." -ForegroundColor Magenta

# Create temporary script for diskpart
$diskpartScriptPath = "$env:TEMP\diskpart_script.txt"
@"
select vdisk file="$vhdxPath"
compact vdisk
exit
"@ | Out-File -FilePath $diskpartScriptPath -Encoding ASCII

# Run diskpart in background
$process = Start-Process -FilePath "diskpart" -ArgumentList "/s `"$diskpartScriptPath`"" -Wait -NoNewWindow -PassThru
Remove-Item -Path $diskpartScriptPath -ErrorAction SilentlyContinue

if ($process.ExitCode -eq 0) {
    Write-Host "`n[OK] Compaction successful! Everything is done.`n" -ForegroundColor Green
} else {
    Write-Host "`n[ERROR] Compaction failed (Error code: $($process.ExitCode))." -ForegroundColor Red
}

Write-Host "`nTask completed! Press any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')