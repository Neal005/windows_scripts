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

# Lay thong so do phan giai (chieu cao) va FPS tu file goc
$origHeight = [int](ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "`"$inputFile`"")
$origFpsStr = ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "`"$inputFile`""

# Xu ly toan hoc cho FPS (FFmpeg thuong tra ve dang phan so)
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
            Write-Host "Canh bao: Sep dang buff chieu cao ($h) vuot muc goc ($origHeight)! Nhap lai nhe." -ForegroundColor Red
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
            Write-Host "Canh bao: FPS moi ($f) vuot tran FPS goc ($origFps)! Phai nhap nho hon hoac bang thoi." -ForegroundColor Red
        } elseif ($f -le 0) {
            Write-Host "Khung hinh ma be hon 0 la video di lui do sep! Nhap lai nhe." -ForegroundColor Red
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

# 4. Xu ly ten va vi tri file dau ra (xuat luon cung thu muc)
$fileInfo = Get-Item $inputFile
$outputFile = Join-Path -Path $fileInfo.DirectoryName -ChildPath ($fileInfo.BaseName + "_lite" + $fileInfo.Extension)

Write-Host "Dang tien hanh ep xung video! Vui long doi..." -ForegroundColor Yellow

$encoder = if ($env:FFMPEG_GPU_ENCODER) { $env:FFMPEG_GPU_ENCODER } else { "libx264" }
Write-Host "Lenh thuc thi: ffmpeg -i video_goc -vf scale=-2:$targetHeight -r $targetFps -c:v $encoder output_video" -ForegroundColor DarkGray

# Thuc thi FFmpeg
ffmpeg -i $inputFile -vf scale=-2:$targetHeight -r $targetFps -c:v $encoder $outputFile

if (Test-Path $outputFile) {
    Write-Host ""
    Write-Host "HOAN TAT! Video da duoc ép mo thanh cong." -ForegroundColor Green
    Write-Host "File nam chình ình o day: $outputFile" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "Loi roi! Khong thay file dau ra. Sep kiem tra lai qua trinh render nhe." -ForegroundColor Red
}

Write-Host ""
Write-Host "Nhan Enter de thoat va tiep tuc su nghiep..." -ForegroundColor Cyan
Read-Host