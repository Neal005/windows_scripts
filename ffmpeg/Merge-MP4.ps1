Clear-Host
Write-Host "=== SCRIPT 2: BATCH VIDEO MERGE TO MP4 ===" -ForegroundColor Cyan

# 1. Input video files
Write-Host "Step 1: Gather media files" -ForegroundColor Yellow
Write-Host "Hint: You can highlight multiple files and drag them here, then press Enter" -ForegroundColor DarkGray
$inputString = Read-Host "Please drag and drop files here"

if ([string]::IsNullOrWhiteSpace($inputString)) {
    Write-Host "Error: No files were provided!" -ForegroundColor Red
    Read-Host
    exit
}

# Parse drag-and-drop string 
$regex = '(?:"([^"]+)")|(?:([^\s"]+))'
$matches = [regex]::Matches($inputString, $regex)

$videoFiles = @()
foreach ($m in $matches) {
    $path = ""
    if ($m.Groups[1].Value) {
        $path = $m.Groups[1].Value
    } elseif ($m.Groups[2].Value) {
        $path = $m.Groups[2].Value
    }
    
    if (Test-Path $path) {
        $videoFiles += Get-Item $path
    }
}

if ($videoFiles.Count -eq 0) {
    Write-Host "No valid video files identified from the input!" -ForegroundColor Red
    Read-Host
    exit
}

Write-Host "=> Found $($videoFiles.Count) video files. Creating work order..." -ForegroundColor Magenta
Write-Host "------------------------------------------------"

# Get directory of the first file
$workDir = $videoFiles[0].DirectoryName
Set-Location -Path $workDir

# 2. Create temporary list file
$listFile = Join-Path -Path $workDir -ChildPath "temp_list.txt"
$listContent = $videoFiles | ForEach-Object { 
    $safePath = $_.FullName -replace "'", "'\''"
    "file '$safePath'" 
}

# Use UTF-8 No BOM for accurate FFmpeg character recognition
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines($listFile, $listContent, $utf8NoBom)

$outputMp4 = Join-Path -Path $workDir -ChildPath "Final_Merged_Video.mp4"

# 3. Check pixel format 
$pixFmt = ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 $videoFiles[0].FullName

$vfParams = ""
if ($pixFmt -like "*422*") {
    $vfParams = "-vf `"format=yuv420p`""
}

# 4. Encoding Quality Selection
Write-Host "Step 2: Select output video quality" -ForegroundColor Yellow
Write-Host "[1] Standard Compression (Smallest file size, decent quality - Default)" -ForegroundColor White
Write-Host "[2] High Quality (Larger file size, retains original sharpness)" -ForegroundColor White
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
Write-Host "Concatenating files and encoding to MP4 format..." -ForegroundColor DarkCyan

# 5. Build and execute command
$ffmpegCmd = "ffmpeg -f concat -safe 0 -i `"$listFile`" $vfParams -c:v $encoder $qualityParams -c:a aac -movflags +faststart `"$outputMp4`""
Invoke-Expression $ffmpegCmd

# 6. Cleanup
if (Test-Path $listFile) { 
    Remove-Item $listFile 
}

Write-Host "------------------------------------------------"
if (Test-Path $outputMp4) {
    Write-Host "SUCCESS! The consolidated MP4 file has been generated at the requested location:" -ForegroundColor Green
    Write-Host $outputMp4 -ForegroundColor Cyan
} else {
    Write-Host "An error occurred! Please check if any source files are corrupted." -ForegroundColor Red
}

Write-Host ""
Write-Host "Press Enter to clean up the tool and exit..." -ForegroundColor Cyan
Read-Host