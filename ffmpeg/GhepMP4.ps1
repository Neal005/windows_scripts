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

# Parse chuoi keo tha 
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

# Lay thu muc cua file dau tien
$workDir = $videoFiles[0].DirectoryName
Set-Location -Path $workDir

# 2. Tao file danh sach tam thoi
$listFile = "danhsach_tam.txt"
$listContent = $videoFiles | ForEach-Object { 
    $safePath = $_.FullName -replace "'", "'\''"
    "file '$safePath'" 
}

# Chuyen sang UTF-8 No BOM de FFmpeg nhan dien chuan xac tieng Viet
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines($listFile, $listContent, $utf8NoBom)

$outputMp4 = Join-Path -Path $workDir -ChildPath "Video_Final_ThanhBach.mp4"

# 3. Kiem tra dinh dang pixel 
$pixFmt = ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 $videoFiles[0].FullName

$vfParams = ""
if ($pixFmt -like "*422*") {
    $vfParams = "-vf `"format=yuv420p`""
}

# 4. Menu Lua chon Ep can (IQ 200)
Write-Host "Buoc 2: Chot don chat luong hinh anh" -ForegroundColor Yellow
Write-Host "[1] Ep can thanh bach (Dung luong sieu nho, chat luong du xem - Mac dinh)" -ForegroundColor White
Write-Host "[2] Giu net bo doi (Dung luong lon hon, net cang nhu goc)" -ForegroundColor White
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
Write-Host "Dang noi cac file lai voi nhau va ep sang chuan MP4..." -ForegroundColor DarkCyan

# 5. Ghep lenh va thuc thi 
$ffmpegCmd = "ffmpeg -f concat -safe 0 -i $listFile $vfParams -c:v $encoder $qualityParams -c:a aac -movflags +faststart `"$outputMp4`""
Invoke-Expression $ffmpegCmd

# 6. Don dep hau truong
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