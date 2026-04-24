Clear-Host
Write-Host "=== SCRIPT 2: DAY CHUYEN DONG GOI GHEP VIDEO SANG MP4 ===" -ForegroundColor Cyan

# 1. Nhap cac file video
Write-Host "Buoc 1: Thu thap nguyen lieu" -ForegroundColor Yellow
Write-Host "Goi y: Sep co boi den nhieu file cung luc va keo tha vao day roi nhan Enter" -ForegroundColor DarkGray
$inputString = Read-Host "Moi sep keo tha cac file vao day"

if ([string]::IsNullOrWhiteSpace($inputString)) {
    Write-Host "Loi: Chua co file nao duoc dua vao!" -ForegroundColor Red
    Read-Host
    exit
}

# Parse chuoi keo tha (ho tro ca duong dan co ngoac kep va khong co ngoac kep)
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
    Write-Host "Khong nhan dien duoc file video nao hop le tu chuoi vua nhap!" -ForegroundColor Red
    Read-Host
    exit
}

Write-Host "=> Da tim thay $($videoFiles.Count) file video. Dang tao don hang..." -ForegroundColor Magenta
Write-Host "------------------------------------------------"

# Lay thu muc cua file dau tien de lam noi luu tru file tam va file xuat ra
$workDir = $videoFiles[0].DirectoryName
Set-Location -Path $workDir

# 2. Tao file danh sach tam thoi
$listFile = "danhsach_tam.txt"
$listContent = $videoFiles | ForEach-Object { 
    $safePath = $_.FullName -replace "'", "'\''"
    "file '$safePath'" 
}
# FIX 1: Dung encoding ASCII de FFmpeg khong bi boi roi boi loi BOM cua UTF-8
Set-Content -Path $listFile -Value $listContent -Encoding ASCII

# File xuat ra se nam ngay trong thu muc do
$outputMp4 = Join-Path -Path $workDir -ChildPath "Video_Final_ThanhBach.mp4"

# 3. Chay FFmpeg voi kha nang tu thich nghi dinh dang (Auto-detect)
$encoder = if ($env:FFMPEG_GPU_ENCODER) { $env:FFMPEG_GPU_ENCODER } else { "libx264" }

# Kiem tra dinh dang pixel cua file dau tien
Write-Host "Dang kiem tra thong so ky thuat cua nguyen lieu..." -ForegroundColor Gray
$pixFmt = ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 $videoFiles[0].FullName

$vfParams = ""
# FIX 2: Tu dong them filter yuv420p neu phat hien video goc la 4:2:2 (Dung cho the loai mjpeg, camera cu...)
if ($pixFmt -like "*422*") {
    Write-Host "(!) Phat hien dinh dang 4:2:2, dang kich hoat che do tuong thich cho GPU..." -ForegroundColor Magenta
    $vfParams = "-vf `"format=yuv420p`""
}

Write-Host "Dang noi cac file lai voi nhau va ep sang chuan MP4..." -ForegroundColor DarkCyan
Write-Host "FFmpeg dang chay, sep pha ly cafe roi quay lai nhe!" -ForegroundColor Yellow

# Ghep lenh va thuc thi (Them faststart de toi uu video tren web)
$ffmpegCmd = "ffmpeg -f concat -safe 0 -i $listFile $vfParams -c:v $encoder -c:a aac -movflags +faststart `"$outputMp4`""
Invoke-Expression $ffmpegCmd

# 4. Don dep hau truong cho thanh bach
if (Test-Path $listFile) { 
    Remove-Item $listFile 
}

Write-Host "------------------------------------------------"
if (Test-Path $outputMp4) {
    Write-Host "NGON LANH! File MP4 tong hop da duoc tao ra ngay tai vi tri yeu cau:" -ForegroundColor Green
    Write-Host $outputMp4 -ForegroundColor Cyan
} else {
    Write-Host "Co loi xay ra! Sep kiem tra lai xem co file nao dang bi loi khong nhe." -ForegroundColor Red
}

Write-Host ""
Write-Host "Nhan Enter de thu don tool va thoat..." -ForegroundColor Cyan
Read-Host