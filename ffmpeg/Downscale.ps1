Clear-Host
Write-Host "=== SCRIPT 3: EP XUNG VIDEO (GIAM DO PHAN GIAI & FPS) ===" -ForegroundColor Cyan

# Kiem tra FFmpeg
if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue) -or -not (Get-Command "ffprobe" -ErrorAction SilentlyContinue)) {
    Write-Host "Loi to roi sep oi: Khong tim thay ffmpeg hoac ffprobe!" -ForegroundColor Red
    Write-Host "Nhan Enter de thoat..."
    Read-Host
    exit
}

# 1. Nhan file video
$inputFile = Read-Host "Buoc 1: Keo tha file video can giam dung luong vao day"
$inputFile = $inputFile.Trim('"').Trim("'")

if (-not (Test-Path $inputFile)) {
    Write-Host "Khong tim thay file. Vui long kiem tra lai duong dan!" -ForegroundColor Red
    Read-Host
    exit
}

Write-Host "Dang quet thong so video goc..." -ForegroundColor DarkCyan

$origHeight = [int](ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "`"$inputFile`"")
$origFpsStr = ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "`"$inputFile`""

$fpsParts = $origFpsStr.Split('/')
$origFps = [math]::Round([double]$fpsParts[0] / [double]$fpsParts[1], 2)

Write-Host "=> Phat hien video goc: ${origHeight}p voi $origFps FPS" -ForegroundColor Green
Write-Host "------------------------------------------------"

# 2. Nhap do phan giai moi
$targetHeight = $origHeight
while ($true) {
    $inputHeight = Read-Host "Buoc 2: Nhap chieu cao video muon giam (VD: 720). Nhan Enter de giu nguyen [$origHeight]"
    if ([string]::IsNullOrWhiteSpace($inputHeight)) {
        Write-Host "-> Chot don: Giu nguyen ${origHeight}p" -ForegroundColor Magenta
        break
    }
    if ([int]::TryParse($inputHeight, [ref]$null)) {
        $h = [int]$inputHeight
        if ($h -gt $origHeight) {
            Write-Host "Canh bao: Sep dang buff chieu cao vuot muc goc! Nhap lai nhe." -ForegroundColor Red
        } elseif ($h -le 0) {
            Write-Host "Loi: So am hoac bang 0 lam sao chay duoc ha sep!" -ForegroundColor Red
        } else {
            $targetHeight = $h
            Write-Host "-> Chot don: Ep xuong ${targetHeight}p" -ForegroundColor Magenta
            break
        }
    } else {
        Write-Host "Vui long nhap so nguyen!" -ForegroundColor Red
    }
}
Write-Host "------------------------------------------------"

# 3. Nhap FPS moi
$targetFps = $origFps
while ($true) {
    $inputFps = Read-Host "Buoc 3: Nhap FPS muon giam (VD: 30). Nhan Enter de giu nguyen [$origFps]"
    if ([string]::IsNullOrWhiteSpace($inputFps)) {
        Write-Host "-> Chot don: Giu nguyen $origFps FPS" -ForegroundColor Magenta
        break
    }
    if ([double]::TryParse($inputFps, [ref]$null)) {
        $f = [double]$inputFps
        if ($f -gt $origFps) {
            Write-Host "Canh bao: FPS moi vuot tran FPS goc! Nhap nho hon hoac bang." -ForegroundColor Red
        } elseif ($f -le 0) {
            Write-Host "Khung hinh be hon 0 la di lui do sep! Nhap lai nhe." -ForegroundColor Red
        } else {
            $targetFps = $f
            Write-Host "-> Chot don: Ep xuong $targetFps FPS" -ForegroundColor Magenta
            break
        }
    } else {
        Write-Host "Vui long nhap so thoi sep oi!" -ForegroundColor Red
    }
}
Write-Host "------------------------------------------------"

# 4. Menu Lua chon Ep can (IQ 200)
Write-Host "Buoc 4: Chot don chat luong hinh anh (bitrate)" -ForegroundColor Yellow
Write-Host "[1] Ep can thanh bach (Dung luong nho nhat cho do phan giai nay - Mac dinh)" -ForegroundColor White
Write-Host "[2] Giu net bo doi (Net cang tung pixel ở muc ${targetHeight}p)" -ForegroundColor White
$qualityChoice = Read-Host "Moi sep chon (1 hoac 2. Bam Enter de chon 1)"

$encoder = if ($env:FFMPEG_GPU_ENCODER) { $env:FFMPEG_GPU_ENCODER } else { "libx264" }
$qualityParams = ""

if ($qualityChoice -eq '2') {
    Write-Host "=> Da chot: Giu net bo doi! Dang nap dan xuyen giap cho dong co $encoder..." -ForegroundColor Magenta
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

Write-Host "------------------------------------------------"

# FIX IQ 200: Dam bao chieu cao luon la so chan de dong co khong bi nghen
if ($targetHeight % 2 -ne 0) {
    Write-Host "(!) Phat hien chieu cao la so le ($targetHeight). He thong tu dong tru di 1 pixel de vua mam dong co GPU..." -ForegroundColor Yellow
    $targetHeight -= 1
}

# 5. Thuc thi
$fileInfo = Get-Item $inputFile
$outputFile = Join-Path -Path $fileInfo.DirectoryName -ChildPath ($fileInfo.BaseName + "_lite.mp4")

Write-Host "Dang tien hanh ep xung video! Vui long doi..." -ForegroundColor Yellow

$vfParams = "scale=-2:$targetHeight,format=yuv420p"

$ffmpegCmd = "ffmpeg -i `"$inputFile`" -vf `"$vfParams`" -r $targetFps -c:v $encoder $qualityParams -c:a aac -movflags +faststart `"$outputFile`""
Invoke-Expression $ffmpegCmd

if (Test-Path $outputFile) {
    Write-Host ""
    Write-Host "HOAN TAT! Video da duoc ep mo thanh cong." -ForegroundColor Green
    Write-Host "File nam chinh inh o day: $outputFile" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "Loi roi! Khong thay file dau ra. Sep kiem tra lai qua trinh render nhe." -ForegroundColor Red
}

Write-Host ""
Write-Host "Nhan Enter de thoat va tiep tuc su nghiep..." -ForegroundColor Cyan
Read-Host