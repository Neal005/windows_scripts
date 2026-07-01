Clear-Host
Write-Host "=== SCRIPT 4: DAO THUAT CAT KHOANG LANG (CHUA 2S + TUY CHON EP CAN) ===" -ForegroundColor Cyan

# Kiem tra vu khi
if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) {
    Write-Host "Loi to roi sep oi: Khong tim thay ffmpeg!" -ForegroundColor Red
    Write-Host "Nhan Enter de thoat..."
    Read-Host
    exit
}

# 1. Nhan file video tu sep
$inputFile = Read-Host "Buoc 1: Keo tha file video can 'giet thoi gian chet' vao day"
$inputFile = $inputFile.Trim('"').Trim("'")

if (-not (Test-Path $inputFile)) {
    Write-Host "Khong tim thay file. Sep kiem tra lai duong dan nhe!" -ForegroundColor Red
    Read-Host
    exit
}

Write-Host "------------------------------------------------"
Write-Host "Dang tha robot vao do min (Tim khoang lang > 30s)..." -ForegroundColor Yellow
Write-Host "CPU dang duoc giai phong, toc do quet se rat nhanh!" -ForegroundColor DarkGray

# 2. Chay FFmpeg de do tim (Dung -vn de bo qua hinh anh)
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
    Write-Host "=> Tuyet voi! Video khong co khoang lang nao qua 30s." -ForegroundColor Green
    Write-Host "Nhan Enter de thoat..."
    Read-Host
    exit
}

Write-Host "=> Phat hien $($silences.Count) doan im lang. Bat dau tinh toan chua dung 2s..." -ForegroundColor Magenta

# 3. Chuan bi ban ve thi cong
$fileInfo = Get-Item $inputFile
$workDir = $fileInfo.DirectoryName
$listFile = Join-Path -Path $workDir -ChildPath "danhsach_cat_tam.txt"
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

# Luu file tam bang UTF-8 khong BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines($listFile, $listContent, $utf8NoBom)

# 4. Menu Lua chon Ep can (IQ 200)
Write-Host "------------------------------------------------"
Write-Host "Buoc 2: Chot don chat luong hinh anh" -ForegroundColor Yellow
Write-Host "[1] Ep can thanh bach (Dung luong sieu nho, chat luong du xem - Mac dinh)" -ForegroundColor White
Write-Host "[2] Giu net bo doi (Dung luong lon hon, net cang nhu goc)" -ForegroundColor White
$qualityChoice = Read-Host "Moi sep chon (1 hoac 2. Bam Enter de chon 1)"

# Nhan dien dong co tu Tram Chi Huy
$encoder = if ($env:FFMPEG_GPU_ENCODER) { $env:FFMPEG_GPU_ENCODER } else { "libx264" }
$qualityParams = ""

if ($qualityChoice -eq '2') {
    Write-Host "=> Da chot: Giu net bo doi! Dang nap dan xuyen giap cho dong co $encoder..." -ForegroundColor Magenta
    # Kiem tra xem Tram Chi Huy dang phan cong dong co nao de bam tham so tuong ung
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
    Write-Host "=> Da chot: Ep can giam mo! De FFmpeg tu dong bop bitrate..." -ForegroundColor Magenta
}

# 5. Day vao lo render GPU
$outputFile = Join-Path -Path $workDir -ChildPath ($fileInfo.BaseName + "_NoSilence.mp4")

Write-Host "------------------------------------------------"
Write-Host "Dang tien hanh phep thuat cat ghep va render ra MP4!" -ForegroundColor DarkCyan
Write-Host "Dong co: $encoder | Tham so phu: $qualityParams" -ForegroundColor DarkGray

# Chay FFmpeg voi tham so dong
$ffmpegCmd = "ffmpeg -f concat -safe 0 -i `"$listFile`" -c:v $encoder $qualityParams -c:a aac -movflags +faststart `"$outputFile`""
Invoke-Expression $ffmpegCmd

# 6. Don dep hau truong
if (Test-Path $listFile) { 
    Remove-Item $listFile 
}

Write-Host "------------------------------------------------"
if (Test-Path $outputFile) {
    Write-Host "HOAN TAT! Video da duoc cat gon gang, giam tai thoi gian chet." -ForegroundColor Green
    Write-Host "Thanh pham o day: $outputFile" -ForegroundColor Cyan
} else {
    Write-Host "Co loi khi render. Sep kiem tra lai xem video goc co van de gi khong." -ForegroundColor Red
}

Write-Host ""
Write-Host "Nhan Enter de thoat va tiep tuc su nghiep..." -ForegroundColor Cyan
Read-Host