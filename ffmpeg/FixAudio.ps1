Clear-Host
Write-Host "=== SCRIPT 1: AUDIO SYNCHRONIZATION (FIX AUDIO DELAY) ===" -ForegroundColor Cyan

# 1. Get file path from user
$inputFile = Read-Host "Step 1: Drag and drop the AVI file to fix here (then press Enter)"
$inputFile = $inputFile.Trim('"').Trim("'")

if (-not (Test-Path $inputFile)) {
    Write-Host "Critical Error: File not found. Please check the path!" -ForegroundColor Red
    Write-Host "Press Enter to exit..."
    Read-Host
    exit
}

Write-Host "------------------------------------------------"
# 2. Get adjustment ratio
Write-Host "Step 2: Enter the audio adjustment ratio." -ForegroundColor Yellow
Write-Host "- You can enter a decimal (e.g., 0.916)" -ForegroundColor DarkGray
Write-Host "- Or a fraction for precision (e.g., 55/60 or 60/55)" -ForegroundColor DarkGray
Write-Host "- Leave blank and press Enter to use default: 5.500/5.570" -ForegroundColor Green

$ratioInput = Read-Host "Please enter the ratio"

# Apply default if left blank
if ([string]::IsNullOrWhiteSpace($ratioInput)) {
    $ratioInput = "5.500/5.570"
    Write-Host "=> Applied default ratio: $ratioInput" -ForegroundColor DarkCyan
}

$tempo = 1.0

# Advanced Parsing: Handles both fractions and decimals
try {
    # Replace comma with dot to prevent formatting errors
    $ratioInput = $ratioInput.Replace(",", ".") 
    
    if ($ratioInput -match "/") {
        $parts = $ratioInput.Split("/")
        $numerator = [double]::Parse($parts[0].Trim())
        $denominator = [double]::Parse($parts[1].Trim())
        $tempo = $numerator / $denominator
    } else {
        $tempo = [double]::Parse($ratioInput.Trim())
    }
} catch {
    Write-Host "Error: Invalid format! Please enter a number or fraction." -ForegroundColor Red
    Read-Host
    exit
}

# FFmpeg atempo filter only accepts values between 0.5 and 100
if ($tempo -lt 0.5 -or $tempo -gt 100.0) {
    Write-Host "Error: FFmpeg only allows audio scaling between 0.5 (half speed) and 100 (100x speed)!" -ForegroundColor Red
    Read-Host
    exit
}

# Convert to standard decimal string to prevent FFmpeg parsing errors
$tempoStr = [math]::Round($tempo, 6).ToString([cultureinfo]::InvariantCulture)

Write-Host "=> Selection: Calculated atempo ratio is $tempoStr" -ForegroundColor Magenta
Write-Host "------------------------------------------------"

# 3. Handle output filename
$fileInfo = Get-Item $inputFile
$outputFile = Join-Path -Path $fileInfo.DirectoryName -ChildPath ($fileInfo.BaseName + "_synced" + $fileInfo.Extension)

Write-Host "Starting FFmpeg Engine! Commencing audio processing..." -ForegroundColor DarkCyan
Write-Host "Command: ffmpeg -i original_file -filter:a `"atempo=$tempoStr`" -c:v copy output_file" -ForegroundColor DarkGray
Write-Host "Please wait a moment..." -ForegroundColor Yellow

# Execute FFmpeg (render audio only, copy video stream)
ffmpeg -i $inputFile -filter:a "atempo=$tempoStr" -c:v copy $outputFile

if (Test-Path $outputFile) {
    Write-Host ""
    Write-Host "SUCCESS! The audio has been synchronized successfully." -ForegroundColor Green
    Write-Host "Output saved at: $outputFile" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "Rendering error. Please check if the original file is locked by another program!" -ForegroundColor Red
}

Write-Host ""
Write-Host "Task completed! Press Enter to exit and move to another file..." -ForegroundColor Cyan
Read-Host