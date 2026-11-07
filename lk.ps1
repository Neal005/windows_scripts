# 1. Tắt bộ đếm màn hình khóa (đặt về 0) và khóa máy ngay
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK 0
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK 0
powercfg /SETACTIVE SCHEME_CURRENT
rundll32.exe user32.dll,LockWorkStation

# 2. Đợi màn hình khóa bật lên và canh đến khi sếp mở khóa
Start-Sleep -Seconds 3
try {
    while (Get-Process -Name "LogonUI" -ErrorAction SilentlyContinue) {
        Start-Sleep -Seconds 5
    }
} finally {
    # 3. Trả lại đúng con số zin 30 giây (0x1e) của máy ASUS ngay khi mở khóa
    powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK 30
    powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK 30
    powercfg /SETACTIVE SCHEME_CURRENT
}