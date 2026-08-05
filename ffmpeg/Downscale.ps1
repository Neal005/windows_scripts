Clear-Host
Write-Host "=== SCRIPT 3: VIDEO DOWNSCALING (REDUCE RESOLUTION & FPS) ===" -ForegroundColor Cyan

# Check FFmpeg
if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue) -or -not (Get-Command "ffprobe" -ErrorAction SilentlyContinue)) {
    Write-Host "Critical Error: FFmpeg or FFprobe not found!" -ForegroundColor Red
    Write-Host "Press Enter to exit..."
    Read-Host
    exit
}

# 1. Get video input
$inputFile = Read-Host "Step 1: Drag and drop the video file to downscale here"
$inputFile = $inputFile.Trim('"').Trim("'")

if (-not (Test-Path $inputFile)) {
    Write-Host "File not found. Please check the path!" -ForegroundColor Red
    Read-Host
    exit
}

Write-Host "Scanning original video properties..." -ForegroundColor DarkCyan

$origHeight = [int](ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "`"$inputFile`"")
$origFpsStr = ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "`"$inputFile`""

$fpsParts = $origFpsStr.Split('/')
$origFps = [math]::Round([double]$fpsParts[0] / [double]$fpsParts[1], 2)

Write-Host "=> Original Video: ${origHeight}p at $origFps FPS" -ForegroundColor Green
Write-Host "------------------------------------------------"

# 2. Enter new resolution
$targetHeight = $origHeight
while ($true) {
    $inputHeight = Read-Host "Step 2: Enter target height (e.g., 720). Press Enter to keep original [$origHeight]"
    if ([string]::IsNullOrWhiteSpace($inputHeight)) {
        Write-Host "-> Selection: Keeping original ${origHeight}p" -ForegroundColor Magenta
        break
    }
    if ([int]::TryParse($inputHeight, [ref]$null)) {
        $h = [int]$inputHeight
        if ($h -gt $origHeight) {
            Write-Host "Warning: Target height exceeds original! Please enter a smaller value." -ForegroundColor Red
        } elseif ($h -le 0) {
            Write-Host "Error: Value must be greater than zero!" -ForegroundColor Red
        } else {
            $targetHeight = $h
            Write-Host "-> Selection: Downscaling to ${targetHeight}p" -ForegroundColor Magenta
            break
        }
    } else {
        Write-Host "Please enter a valid integer!" -ForegroundColor Red
    }
}
Write-Host "------------------------------------------------"

# 3. Enter new FPS
$targetFps = $origFps
while ($true) {
    $inputFps = Read-Host "Step 3: Enter target FPS (e.g., 30). Press Enter to keep original [$origFps]"
    if ([string]::IsNullOrWhiteSpace($inputFps)) {
        Write-Host "-> Selection: Keeping original $origFps FPS" -ForegroundColor Magenta
        break
    }
    if ([double]::TryParse($inputFps, [ref]$null)) {
        $f = [double]$inputFps
        if ($f -gt $origFps) {
            Write-Host "Warning: Target FPS exceeds original! Please enter a smaller or equal value." -ForegroundColor Red
        } elseif ($f -le 0) {
            Write-Host "Error: FPS must be greater than zero!" -ForegroundColor Red
        } else {
            $targetFps = $f
            Write-Host "-> Selection: Downscaling to $targetFps FPS" -ForegroundColor Magenta
            break
        }
    } else {
        Write-Host "Please enter a valid number!" -ForegroundColor Red
    }
}
Write-Host "------------------------------------------------"

# 4. Select Compression Quality
Write-Host "Step 4: Select image quality (bitrate)" -ForegroundColor Yellow
Write-Host "[1] Standard Compression (Smallest file size for this resolution - Default)" -ForegroundColor White
Write-Host "[2] High Quality (Maximum sharpness at ${targetHeight}p)" -ForegroundColor White
$qualityChoice = Read-Host "Please select (1 or 2. Press Enter for 1)"

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

Write-Host "------------------------------------------------"

# Ensure height is an even number to prevent encoder errors
if ($targetHeight % 2 -ne 0) {
    Write-Host "(!) Detected odd height value ($targetHeight). Automatically subtracting 1 pixel for encoder compatibility..." -ForegroundColor Yellow
    $targetHeight -= 1
}

# 5. Execute
$fileInfo = Get-Item $inputFile
$outputFile = Join-Path -Path $fileInfo.DirectoryName -ChildPath ($fileInfo.BaseName + "_lite.mp4")

Write-Host "Downscaling video... Please wait." -ForegroundColor Yellow

$vfParams = "scale=-2:$targetHeight,format=yuv420p"

$ffmpegCmd = "ffmpeg -i `"$inputFile`" -vf `"$vfParams`" -r $targetFps -c:v $encoder $qualityParams -c:a aac -movflags +faststart `"$outputFile`""
Invoke-Expression $ffmpegCmd

if (Test-Path $outputFile) {
    Write-Host ""
    Write-Host "COMPLETED! Video successfully downscaled." -ForegroundColor Green
    Write-Host "Output saved at: $outputFile" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "Error: Output file not found. Please check the rendering process." -ForegroundColor Red
}

Write-Host ""
Write-Host "Press Enter to exit..." -ForegroundColor Cyan
Read-Host