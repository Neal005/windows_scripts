<#
.SYNOPSIS
    Script tao Symbolic Link hoac Junction cho thu muc tren Windows.
.DESCRIPTION
    Script nay yeu cau quyen Administrator. 
    Ho tro tuy chon giua Symlink (/D) va Directory Junction (/J).
#>

# 1. Kiểm tra quyền Administrator
# Kiểm tra xem script đã có quyền Admin chưa
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    
    Write-Host "Script đang xin quyen Admin de tiep tuc..." -ForegroundColor Yellow
    
    # Nếu chưa có quyền, tự động gọi lại chính file này nhưng với quyền Admin (Verb RunAs)
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    
    # Thoát tiến trình cũ (không có quyền) để tránh chạy code 2 lần
    Exit
}

Clear-Host
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   CONG CU TAO LIEN KET THU MUC (ADVANCED)   " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# 2. Nhập đường dẫn thư mục GỐC (Nguồn dữ liệu thật)
Write-Host "[1] Nhap duong dan thu muc GOC (Noi dang chua du lieu that):" -ForegroundColor Yellow
$targetPath = Read-Host
$targetPath = $targetPath.Trim('"') # Loại bỏ dấu ngoặc kép

if (-not (Test-Path -Path $targetPath)) {
    Write-Error "Loi: Thu muc goc khong ton tai! Vui long kiem tra lai duong dan."
    Pause
    Exit
}

# 3. Nhập đường dẫn thư mục LINK (Thư mục ảo sẽ được tạo)
Write-Host ""
Write-Host "[2] Nhap duong dan thu muc LINK (Ten file/folder ao muon tao):" -ForegroundColor Yellow
$linkPath = Read-Host
$linkPath = $linkPath.Trim('"')

if (Test-Path -Path $linkPath) {
    Write-Error "Loi: Duong dan Link da ton tai. Vui long xoa no truoc khi tao Link."
    Pause
    Exit
}

# 4. Lựa chọn loại liên kết (Junction hay Symlink)
Write-Host ""
Write-Host "[3] Chon loai lien ket muon tao:" -ForegroundColor Yellow
Write-Host "    [J] Junction (Khuyen dung cho Local Disk, on dinh hon, sua loi Watchman)" -ForegroundColor Gray
Write-Host "    [S] Symlink  (Lien ket mem truyen thong)" -ForegroundColor Gray

$validChoice = $false
$linkType = ""

do {
    $choice = Read-Host "    Nhap lua chon cua ban (J hoac S)"
    $choice = $choice.ToUpper()
    if ($choice -eq "J" -or $choice -eq "S") {
        $validChoice = $true
        $linkType = $choice
    } else {
        Write-Warning "    Lua chon khong hop le. Vui long nhap 'J' hoac 'S'."
    }
} until ($validChoice)

# 5. Thực thi tạo Link
Write-Host ""
Write-Host "Dang tien hanh tao..." -ForegroundColor Green

try {
    if ($linkType -eq "J") {
        # Tạo Junction Point
        New-Item -ItemType Junction -Path $linkPath -Target $targetPath -ErrorAction Stop | Out-Null
        $typeMsg = "Directory Junction (/J)"
    }
    else {
        # Tạo Symbolic Link
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $targetPath -ErrorAction Stop | Out-Null
        $typeMsg = "Symbolic Link (/D)"
    }
    
    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host " THANH CONG! $typeMsg da duoc tao tai:" -ForegroundColor Cyan
    Write-Host " $linkPath"
    Write-Host " -> Tro den: $targetPath"
    Write-Host "------------------------------------------"
}
catch {
    Write-Host ""
    Write-Error "DA CO LOI XAY RA:"
    Write-Error $_.Exception.Message
    if ($linkType -eq "J") {
        Write-Warning "Luu y: Junction chi hoat dong tren cung o dia hoac giua cac o dia Local. Khong dung cho Network Share."
    }
}

Write-Host ""
Pause