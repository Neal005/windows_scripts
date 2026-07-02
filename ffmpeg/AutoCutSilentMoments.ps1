Clear-Host
Write-Host "=== SCRIPT 4: AUTO CUT SILENT MOMENTS (PRESERVES 2S + ENCODING OPTIONS) ===" -ForegroundColor Cyan

# Check for FFmpeg
if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) {
    Write-Host "Critical Error: FFmpeg not found!" -ForegroundColor Red
    Write-Host "Press Enter to exit..."
    Read-Host
    exit
}

# 1. Get video file input
$inputFile = Read-Host "Step 1: Drag and drop the video file to remove dead time here"
$inputFile = $inputFile.Trim('"').Trim("'")

if (-not (Test-Path $inputFile)) {
    Write-Host "File not found. Please check the path!" -ForegroundColor Red
    Read-Host
    exit
}

Write-Host "------------------------------------------------"
Write-Host "Scanning for silent gaps (> 30s)..." -ForegroundColor Yellow
Write-Host "CPU is processing audio only, scanning will be very fast!" -ForegroundColor DarkGray

# 2. Run FFmpeg for detection (-vn ignores video)
$detectLog = ffmpeg -v info -i "$inputFile" -vn -af "silencedetect=noise=-40dB:d=30" -f null - 2>&1

$silences = @()
$currentStart = -1

foreach ($line in $detectLog) {
    if ($line -match "silence_start:\s+([\d\.]+)") {
        $currentStart = [double]$matches[1]
    }
    if ($line -match "silence_end:\s+([\d\.]+)") {
        $currentEnd = [double]$matches[1]
        if ($currentStart -ge 0) {
            $silences += [PSCustomObject]@{ Start = $currentStart; End = $currentEnd }
            $currentStart = -1
        }
    }
}

if ($silences.Count -eq 0) {
    Write-Host "=> Excellent! No silent gaps exceeding 30s were found." -ForegroundColor Green
    Write-Host "Press Enter to exit..."
    Read-Host
    exit
}

Write-Host "=> Detected $($silences.Count) silent intervals. Calculating 2s preservation cuts..." -ForegroundColor Magenta

# 3. Prepare the cut list
$fileInfo = Get-Item $inputFile
$workDir = $fileInfo.DirectoryName
$listFile = Join-Path -Path $workDir -ChildPath "temp_cut_list.txt"
$safePath = $inputFile -replace "'", "'\''"

$listContent = @()
$lastOut = 0.0

foreach ($s in $silences) {
    $cutStart = [math]::Round($s.Start, 3)
    $cutEnd = [math]::Round($s.End - 2.0, 3) 
    
    $listContent += "file '$safePath'"
    $listContent += "inpoint $lastOut"
    $listContent += "outpoint $cutStart"
    
    $lastOut = $cutEnd
}

$listContent += "file '$safePath'"
$listContent += "inpoint $lastOut"

# Save temp file using UTF-8 without BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines($listFile, $listContent, $utf8NoBom)

# 4. Encoding Quality Selection
Write-Host "------------------------------------------------"
Write-Host "Step 2: Select output video quality" -ForegroundColor Yellow
Write-Host "[1] Standard Compression (Smallest file size, decent quality - Default)" -ForegroundColor White
Write-Host "[2] High Quality (Larger file size, retains original sharpness)" -ForegroundColor White
$qualityChoice = Read-Host "Please select (1 or 2. Press Enter for 1)"

# Detect encoder
$encoder = if ($env:FFMPEG_GPU_ENCODER) { $env:FFMPEG_GPU_ENCODER } else { "libx264" }
$qualityParams = ""

if ($qualityChoice -eq '2') {
    Write-Host "=> Selected: High Quality! Preparing encoder parameters for $encoder..." -ForegroundColor Magenta
    if ($encoder -match "nvenc") {
        $qualityParams = "-rc vbr -cq 22 -preset p6"
    } elseif ($encoder -match "amf") {
        $qualityParams = "-rc cqp -qp_p 22 -qp_i 22"
    } elseif ($encoder -match "qsv") {
        $qualityParams = "-global_quality 22"
    } else {
        $qualityParams = "-crf 22"
    }
} else {
    Write-Host "=> Selected: Standard Compression! Allowing FFmpeg to auto-adjust bitrate..." -ForegroundColor Magenta
}

# 5. Execute Encoding
$outputFile = Join-Path -Path $workDir -ChildPath ($fileInfo.BaseName + "_NoSilence.mp4")

Write-Host "------------------------------------------------"
Write-Host "Starting video cutting and rendering to MP4!" -ForegroundColor DarkCyan
Write-Host "Encoder: $encoder | Extra Parameters: $qualityParams" -ForegroundColor DarkGray

# Run FFmpeg with dynamic parameters
$ffmpegCmd = "ffmpeg -f concat -safe 0 -i `"$listFile`" -c:v $encoder $qualityParams -c:a aac -movflags +faststart `"$outputFile`""
Invoke-Expression $ffmpegCmd

# 6. Cleanup
if (Test-Path $listFile) { 
    Remove-Item $listFile 
}

Write-Host "------------------------------------------------"
if (Test-Path $outputFile) {
    Write-Host "COMPLETED! Video successfully trimmed." -ForegroundColor Green
    Write-Host "Output saved at: $outputFile" -ForegroundColor Cyan
} else {
    Write-Host "Rendering error. Please check if the source video has any issues." -ForegroundColor Red
}

Write-Host ""
Write-Host "Press Enter to exit..." -ForegroundColor Cyan
Read-Host