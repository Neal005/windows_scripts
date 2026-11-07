Clear-Host
Write-Host "=== SCRIPT: SPLIT VIDEO INTO EQUAL-LENGTH PARTS ===" -ForegroundColor Cyan

# Check FFmpeg
if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue) -or -not (Get-Command "ffprobe" -ErrorAction SilentlyContinue)) {
    Write-Host "Critical Error: FFmpeg or FFprobe not found!" -ForegroundColor Red
    Write-Host "Press Enter to exit..."
    Read-Host
    exit
}

# 1. Get video input
$inputFile = Read-Host "Step 1: Drag and drop the video file to split here"
$inputFile = $inputFile.Trim().Trim('"').Trim("'")

if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) {
    Write-Host "File not found. Please check the path!" -ForegroundColor Red
    Read-Host
    exit
}

$fileInfo = Get-Item -LiteralPath $inputFile

# Read duration
$durStr = ffprobe -v error -show_entries format=duration -of csv=p=0 $fileInfo.FullName
$duration = [double]::Parse(($durStr | Select-Object -First 1).Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
Write-Host "=> Video duration: $([math]::Round($duration, 2)) seconds" -ForegroundColor Green
Write-Host "------------------------------------------------"

# 2. Enter segment length
$defaultSeconds = 3540
$segSeconds = $defaultSeconds
while ($true) {
    $inputSec = Read-Host "Step 2: Enter length of each part in seconds. Press Enter for default [$defaultSeconds]"
    if ([string]::IsNullOrWhiteSpace($inputSec)) {
        break
    }
    $parsed = 0
    if ([int]::TryParse($inputSec.Trim(), [ref]$parsed) -and $parsed -gt 0) {
        $segSeconds = $parsed
        break
    }
    Write-Host "Please enter a positive integer!" -ForegroundColor Red
}

$partCount = [math]::Ceiling($duration / $segSeconds)
Write-Host "-> Selection: $segSeconds seconds per part (about $partCount parts)" -ForegroundColor Magenta
Write-Host "------------------------------------------------"

# 3. Prepare output folder
$outDir = Join-Path -Path $fileInfo.DirectoryName -ChildPath ($fileInfo.BaseName + "_split")
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}
$outPattern = Join-Path -Path $outDir -ChildPath ($fileInfo.BaseName + "_part%03d.mp4")

# 4. Execute (re-encode so every part is cut exactly at the requested length)
$encoder = if ($env:FFMPEG_GPU_ENCODER) { $env:FFMPEG_GPU_ENCODER } else { "libx264" }
Write-Host "Splitting video with $encoder... Please wait." -ForegroundColor Yellow

$ffArgs = @(
    "-y", "-i", $fileInfo.FullName,
    "-map", "0:v:0", "-map", "0:a?",
    "-c:v", $encoder,
    "-force_key_frames", "expr:gte(t,n_forced*$segSeconds)",
    "-pix_fmt", "yuv420p",
    "-c:a", "aac",
    "-f", "segment", "-segment_time", "$segSeconds",
    "-reset_timestamps", "1",
    "-segment_format_options", "movflags=+faststart",
    $outPattern
)
& ffmpeg @ffArgs

$created = @(Get-ChildItem -LiteralPath $outDir -Filter "*_part*.mp4" -ErrorAction SilentlyContinue)
Write-Host "------------------------------------------------"
if ($created.Count -gt 0) {
    Write-Host "COMPLETED! Created $($created.Count) parts." -ForegroundColor Green
    Write-Host "Output folder: $outDir" -ForegroundColor Cyan
} else {
    Write-Host "Error: No output files found. Please check the rendering process." -ForegroundColor Red
}

Write-Host ""
Write-Host "Press Enter to exit..." -ForegroundColor Cyan
Read-Host
