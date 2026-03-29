# Chuyen doi ma hoa sang UTF-8 de hien thi ky tu chuan
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== CONG CU QUAN LY MOSQUITTO MQTT (BAN HOAN THIEN) ===" -ForegroundColor Cyan

# 1. Chon Pub hoac Sub
$action = Read-Host "Sep muon Publish (p) hay Subscribe (s)?"
while ($action -notmatch "^(p|s|pub|sub)$") {
    $action = Read-Host "Vui long chi nhap 'p' (Publish) hoac 's' (Subscribe)"
}

# 2. Nhap Host, Port va Topic chinh
$hostAddress = Read-Host "Nhap Host (Bo trong de dung 'localhost')"
if ([string]::IsNullOrWhiteSpace($hostAddress)) { $hostAddress = "localhost" }

$port = Read-Host "Nhap Port (Bo trong de dung mac dinh '1884')"
if ([string]::IsNullOrWhiteSpace($port)) { $port = "1884" }

$topic = Read-Host "Nhap Topic chinh de lam viec (VD: my/topic)"
while ([string]::IsNullOrWhiteSpace($topic)) {
    $topic = Read-Host "Topic khong duoc de trong, sep nhap lai nhe"
}

# 3. Nhap Username / Password (Giau Password)
$user = Read-Host "Nhap Username (Bo trong neu khong co)"

$securePass = Read-Host "Nhap Password (Bo trong neu khong co)" -AsSecureString
# Giai ma Password bang cach an toan de truyen vao lenh
$pass = (New-Object System.Net.NetworkCredential("", $securePass)).Password

# 4. Tao cau truc lenh KET NOI (Host, Port, User, Pass - Chua bao gom Topic)
$connCmd = "-h $hostAddress -p $port"
if (-not [string]::IsNullOrWhiteSpace($user)) { $connCmd += " -u `"$user`"" }
if (-not [string]::IsNullOrWhiteSpace($pass)) { $connCmd += " -P `"$pass`"" }

# Lenh co ban dung cho Pub/Sub chinh thuc sau nay
$baseCmd = "$connCmd -t `"$topic`""

# ==========================================
# 5. KIEM TRA KET NOI MANG (PING PORT)
# ==========================================
Write-Host "`n[1/2] Dang kiem tra ket noi mang den ${hostAddress}:${port}..." -ForegroundColor Yellow
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connectTask = $tcpClient.ConnectAsync($hostAddress, $port)
    if ($connectTask.Wait(2000) -and $tcpClient.Connected) {
        Write-Host "-> Ket noi may chu MQTT thanh cong!" -ForegroundColor Green
        $tcpClient.Close()
    } else {
        Write-Host "-> [LOI] Khong the ket noi den ${hostAddress}:${port}. MQTT Broker co the dang tat hoac sai dia chi!" -ForegroundColor Red
        Read-Host "Nhan Enter de thoat..."
        exit
    }
} catch {
    Write-Host "-> [LOI] Khong the ket noi den ${hostAddress}:${port}. $_" -ForegroundColor Red
    Read-Host "Nhan Enter de thoat..."
    exit
}

# ==========================================
# 6. KIEM TRA TOAN DIEN QUYEN PUB VA SUB (DASHBOARD)
# ==========================================
Write-Host "`n[2/2] Dang kiem tra phan quyen (ACL) tren topic '$topic'..." -ForegroundColor Yellow

$hasPub = $false
$hasSub = $false

# 6.1 Check quyen Publish (Pub xong la tu thoat nen khong so bi ket)
$testPubCmd = "mosquitto_pub $connCmd -t `"$topic`" -m `"ping_auth_check`""
$pubResult = ""
try {
    $pubResult = Invoke-Expression "$testPubCmd 2>&1" | Out-String
    if ($LASTEXITCODE -eq 0 -and $pubResult -notmatch "not authorised|Connection Refused|Error|Denied") {
        $hasPub = $true
    }
} catch {}

# 6.2 Check quyen Subscribe (Chay ngam, doi 1.5s roi giet tien trinh de tranh bi treo)
$errFile = "$env:TEMP\sub_err_temp.txt"
if (Test-Path $errFile) { Remove-Item $errFile -Force -ErrorAction SilentlyContinue }

try {
    # Chay mosquitto_sub an vao nen
    $subProcess = Start-Process -FilePath "mosquitto_sub" -ArgumentList "$connCmd -t `"$topic`"" -WindowStyle Hidden -PassThru -RedirectStandardError $errFile
    
    # Cho tien trinh tra loi toi da 1.5 giay
    $subProcess.WaitForExit(1500) | Out-Null
    
    if (-not $subProcess.HasExited) {
        # Tien trinh van con song (tuc la Sub thanh cong va dang doi tin) -> CO QUYEN!
        $hasSub = $true
        $subProcess.Kill() # Giet luon de thoat nhanh, khong bi ket script
    } else {
        # Tien trinh bi vang ra ngay lap tuc -> Doc file loi xem phai do ACL khong
        if (Test-Path $errFile) {
            $errText = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
            if ($errText -match "not authorised|Connection Refused|Error|Denied") {
                $hasSub = $false
            } else {
                $hasSub = $true
            }
        } else {
            $hasSub = $true
        }
    }
} catch {
    # Bo qua neu loi he thong
} finally {
    # Don dep file rac
    if (Test-Path $errFile) { Remove-Item $errFile -Force -ErrorAction SilentlyContinue }
}

# 6.3 Hien thi Bang tong hop quyen han
Write-Host "`n+--------------------------------------------------+" -ForegroundColor Cyan
Write-Host "| KET QUA PHAN QUYEN TAI KHOAN TREN BROKER         |" -ForegroundColor Cyan
Write-Host "+--------------------------------------------------+" -ForegroundColor Cyan

if ($hasPub) {
    Write-Host "| Quyen Publish   :  [ V ] Cho phep                |" -ForegroundColor Green
} else {
    Write-Host "| Quyen Publish   :  [ X ] Tu choi (No permission) |" -ForegroundColor DarkGray
}

if ($hasSub) {
    Write-Host "| Quyen Subscribe :  [ V ] Cho phep                |" -ForegroundColor Green
} else {
    Write-Host "| Quyen Subscribe :  [ X ] Tu choi (No permission) |" -ForegroundColor DarkGray
}
Write-Host "+--------------------------------------------------+`n" -ForegroundColor Cyan

# 6.4 Xu ly logic chan / tha dua tren lua chon cong viec cua sep
if ($action -match "^p") {
    if (-not $hasPub) {
        Write-Host "-> [LOI] Sep dang chon che do Publish nhung tai khoan lai KHONG CO QUYEN ghi vao topic nay!" -ForegroundColor Red
        Read-Host "Nhan Enter de thoat..."
        exit
    } else {
        Write-Host "-> [OK] Quyen Publish hop le! Dang chuyen vao terminal lam viec..." -ForegroundColor Green
    }
} else {
    if (-not $hasSub) {
        Write-Host "-> [LOI] Sep dang chon che do Subscribe nhung tai khoan lai KHONG CO QUYEN doc tu topic nay!" -ForegroundColor Red
        Read-Host "Nhan Enter de thoat..."
        exit
    } else {
        Write-Host "-> [OK] Quyen Subscribe hop le! Dang chuyen vao terminal lam viec..." -ForegroundColor Green
    }
}

Start-Sleep -Seconds 1

# ==========================================
# XU LY CHINH: TACH RIENG PUB VA SUB
# ==========================================

if ($action -match "^p") {
    # --- CHE DO PUBLISH LIEN TUC ---
    Write-Host "`n=== CHE DO GUI TIN LIEN TUC ===" -ForegroundColor Yellow
    Write-Host "Dang lam viec tren Topic: $topic" -ForegroundColor Green
    Write-Host "Nhan Ctrl + C de thoat chuong trinh." -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------`n" -ForegroundColor Cyan
    
    while ($true) {
        $message = Read-Host "Nhap Message"
        
        # Bo qua neu message rong
        if ([string]::IsNullOrWhiteSpace($message)) {
            Write-Host "[CANH BAO] Tin nhan trong, thu lai!" -ForegroundColor Red
            continue
        }
        
        # Them dau \ truoc ngoac kep cua JSON de khong bi loi cu phap
        $safeMessage = $message -replace '"', '\"'
        $fullCommand = "mosquitto_pub $baseCmd -m '$safeMessage'"
        
        # Chay lenh va bat output de kiem tra loi ACL/Auth
        $pubResult = ""
        try {
            $pubResult = Invoke-Expression "$fullCommand 2>&1" | Out-String
            if ($LASTEXITCODE -ne 0 -or $pubResult -match "not authorised|Connection Refused|Error") {
                Write-Host "-> [LOI] Khong the Publish. Sai Pass hoac khong co quyen (ACL) tren topic nay!" -ForegroundColor Red
                if (-not [string]::IsNullOrWhiteSpace($pubResult)) { Write-Host "Chi tiet: $pubResult" -ForegroundColor DarkGray }
            } else {
                Write-Host "-> Da gui thanh cong!" -ForegroundColor Green
            }
        } catch {
            Write-Host "-> [LOI] Da co loi xay ra: $_" -ForegroundColor Red
        }
        Write-Host ""
    }

} else {
    # --- CHE DO SUBSCRIBE (Lang nghe) ---
    $fullCommand = "mosquitto_sub $baseCmd -v"
    
    # Tao ban sao cua lenh de hien thi, thay the Password bang ***
    $displayCommand = $fullCommand
    if (-not [string]::IsNullOrWhiteSpace($pass)) {
        $displayCommand = $displayCommand.Replace("-P `"$pass`"", "-P `"***`"")
    }
    
    Write-Host "`nDang lang nghe du lieu tren Topic: $topic ... (Nhan Ctrl + C de thoat)" -ForegroundColor Yellow
    Write-Host $displayCommand -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------`n" -ForegroundColor Cyan
    
    try {
        Invoke-Expression $fullCommand
    } catch {
        Write-Host "`n[LOI] Da co loi xay ra: $_" -ForegroundColor Red
    }
    
    Write-Host "`n"
    Read-Host "Nhan Enter de thoat..."
}