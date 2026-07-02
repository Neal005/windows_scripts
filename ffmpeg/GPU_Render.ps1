Clear-Host
Write-Host "=== FFMPEG COMMAND CENTER (MASTER HUB) ===" -ForegroundColor Cyan

# 1. Scan system hardware for encoders
Write-Host "Scanning system for hardware acceleration..." -ForegroundColor DarkCyan
$gpus = Get-CimInstance Win32_VideoController
$gpuNames = $gpus.Name

$encoder = "libx264"
$techName = "CPU (Slowest)"

if ($gpuNames -match "NVIDIA") {
    $encoder = "h264_nvenc"
    $techName = "NVIDIA NVENC"
} elseif ($gpuNames -match "AMD" -or $gpuNames -match "Radeon") {
    $encoder = "h264_amf"
    $techName = "AMD AMF"
} elseif ($gpuNames -match "Intel") {
    $encoder = "h264_qsv"
    $techName = "Intel QuickSync"
}

# Export encoder variable to environment for child scripts
[Environment]::SetEnvironmentVariable("FFMPEG_GPU_ENCODER", $encoder, "Process")

Write-Host "-> Engine detected: $techName" -ForegroundColor Magenta
Write-Host "------------------------------------------------"

# 2. Central Loop (Dock Station)
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Item -Path ".\").FullName }

while ($true) {
    Write-Host ""
    Write-Host ">>> COMMAND CENTER AWAITING ORDERS <<<" -ForegroundColor Yellow
    Write-Host "- Enter the corresponding [Number] to run a script." -ForegroundColor White
    Write-Host "- Enter [e] or [exit] to quit." -ForegroundColor White
    Write-Host "------------------------------------------------"

    # Get the list of ps1 files (excluding this menu file)
    $files = Get-ChildItem -Path $scriptDir -File -Filter "*.ps1" | Where-Object { $_.Name -ne $MyInvocation.MyCommand.Name }

    $menuMap = @{}
    $index = 1

    # List files
    foreach ($f in $files) {
        Write-Host " $index. [Script] $($f.Name)" -ForegroundColor Green
        $menuMap["$index"] = $f
        $index++
    }

    Write-Host " e. Exit" -ForegroundColor Red
    Write-Host "------------------------------------------------"

    $choice = Read-Host "Select an option"
    
    if ($choice -match "^(e|exit)$") {
        Write-Host "Shutting down engines. Have a productive day!" -ForegroundColor DarkGray
        break
    }

    if ($menuMap.ContainsKey($choice)) {
        $selected = $menuMap[$choice]
        
        Write-Host "------------------------------------------------"
        Write-Host "Activating workflow: $($selected.Name)" -ForegroundColor Green
        Start-Sleep -Seconds 1
        
        # Execute child script
        & $selected.FullName
        
        # Restart Hub after child script finishes
        Clear-Host
        Write-Host "=== FFMPEG COMMAND CENTER (MASTER HUB) ===" -ForegroundColor Cyan
        Write-Host "-> Current Engine: $techName" -ForegroundColor Magenta
        Write-Host "=> Previous workflow ($($selected.Name)) completed successfully!" -ForegroundColor Green
        Write-Host "------------------------------------------------"
    } else {
        Write-Host "Invalid selection. Please try again." -ForegroundColor Red
    }
}