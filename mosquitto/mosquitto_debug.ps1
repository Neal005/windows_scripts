# Chuyen doi ma hoa sang UTF-8 de hien thi ky tu chuan
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== CONG CU QUAN LY MOSQUITTO MQTT (DEBUG MODE) ===" -ForegroundColor Cyan

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

# 4. Tao cau truc lenh KET NOI
$connCmd = "-h $hostAddress -p $port"
if (-not [string]::IsNullOrWhiteSpace($user)) { $connCmd += " -u `"$user`"" }
if (-not [string]::IsNullOrWhiteSpace($pass)) { $connCmd += " -P `"$pass`"" }

$baseCmd = "$connCmd -t `"$topic`""

# ==========================================
# 5. KIEM TRA KET NOI MANG (PING PORT)
# ==========================================
Write-Host "`n[1/3] Dang kiem tra ket noi mang den ${hostAddress}:${port}..." -ForegroundColor Yellow
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connectTask = $tcpClient.ConnectAsync($hostAddress, $port)
    if ($connectTask.Wait(2000) -and $tcpClient.Connected) {
        Write-Host "-> [OK] Ket noi may chu MQTT thanh cong!" -ForegroundColor Green
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
# 6. KIEM TRA TAI KHOAN DANG NHAP (AUTHENTICATION)
# ==========================================
Write-Host "`n[2/3] Dang kiem tra thong tin dang nhap (Username/Password)..." -ForegroundColor Yellow

# Chay thu mot lenh ket noi kem co -d de bat chinh xac loi tu Broker
$authCheckCmd = "mosquitto_pub $connCmd -t `"test/auth/dummy`" -m `"`" -d"
$authResult = ""
try {
    $authResult = Invoke-Expression "$authCheckCmd 2>&1" | Out-String
    
    # Neu tra ve loi 'not authorised' o buoc nay thi 100% la do sai tai khoan hoac mat khau
    if ($authResult -match "not authorised" -or $authResult -match "CONNACK \(5\)") {
        Write-Host "-> [LOI] SAI TAI KHOAN HOAC MAT KHAU! (Hoac tai khoan khong ton tai)" -ForegroundColor Red
        Read-Host "Nhan Enter de thoat..."
        exit
    } elseif ($authResult -match "Error: Connection refused") {
        Write-Host "-> [LOI] Broker tu choi ket noi. (Broker khong cho phep hoac dang chan IP)" -ForegroundColor Red
        Read-Host "Nhan Enter de thoat..."
        exit
    } else {
        Write-Host "-> [OK] Dang nhap thanh cong! Tai khoan hop le." -ForegroundColor Green
    }
} catch {
    Write-Host "-> [LOI] Loi khong xac dinh khi kiem tra tai khoan: $_" -ForegroundColor Red
}

# ==========================================
# 7. KIEM TRA QUYEN PUB/SUB (ACL) TREN TOPIC
# ==========================================
Write-Host ""
$checkAcl = Read-Host "Sep co muon kiem tra phan quyen Pub/Sub tren topic khong? (y/n - Bo trong la 'y')"

if ($checkAcl -notmatch "^n") {
    Write-Host "`n[3/3] Dang kiem tra phan quyen (ACL) tren topic '$topic'..." -ForegroundColor Yellow

    $hasPub = $false
    $hasSub = $false

    # Check quyen Publish
    $testPubCmd = "mosquitto_pub $connCmd -t `"$topic`" -m `"ping_auth_check`" -d"
    $pubResult = ""
    try {
        $pubResult = Invoke-Expression "$testPubCmd 2>&1" | Out-String
        # Vi da qua buoc Auth, neu bi chan o day chac chan la do thieu quyen ghi tren topic
        if ($LASTEXITCODE -eq 0 -and $pubResult -notmatch "Denied|Error|Connection lost") {
            $hasPub = $true
        }
    } catch {}

    # Check quyen Subscribe
    $errFile = "$env:TEMP\sub_err_temp.txt"
    if (Test-Path $errFile) { Remove-Item $errFile -Force -ErrorAction SilentlyContinue }

    try {
        $subProcess = Start-Process -FilePath "mosquitto_sub" -ArgumentList "$connCmd -t `"$topic`"" -WindowStyle Hidden -PassThru -RedirectStandardError $errFile
        $subProcess.WaitForExit(1500) | Out-Null
        
        if (-not $subProcess.HasExited) {
            $hasSub = $true
            $subProcess.Kill()
        } else {
            if (Test-Path $errFile) {
                $errText = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
                if ($errText -match "Denied|Error|Connection lost") {
                    $hasSub = $false
                } else {
                    $hasSub = $true
                }
            } else {
                $hasSub = $true
            }
        }
    } catch {
    } finally {
        if (Test-Path $errFile) { Remove-Item $errFile -Force -ErrorAction SilentlyContinue }
    }

    # Hien thi Bang tong hop quyen han
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

    # Xu ly logic chan / tha
    if ($action -match "^p") {
        if (-not $hasPub) {
            Write-Host "-> [LOI] Tai khoan KHONG CO QUYEN Publish vao topic '$topic'!" -ForegroundColor Red
            Read-Host "Nhan Enter de thoat..."
            exit
        } else {
            Write-Host "-> [OK] Quyen Publish hop le! Dang chuyen vao terminal..." -ForegroundColor Green
        }
    } else {
        if (-not $hasSub) {
            Write-Host "-> [LOI] Tai khoan KHONG CO QUYEN Subscribe vao topic '$topic'!" -ForegroundColor Red
            Read-Host "Nhan Enter de thoat..."
            exit
        } else {
            Write-Host "-> [OK] Quyen Subscribe hop le! Dang chuyen vao terminal..." -ForegroundColor Green
        }
    }
} else {
    Write-Host "`n-> [3/3] BO QUA buoc kiem tra phan quyen (ACL). Vao viec luon!" -ForegroundColor DarkGray
}

Start-Sleep -Seconds 1

# ==========================================
# 8. XU LY CHINH: TACH RIENG PUB VA SUB
# ==========================================

if ($action -match "^p") {
    Write-Host "`n=== CHE DO GUI TIN LIEN TUC ===" -ForegroundColor Yellow
    Write-Host "Dang lam viec tren Topic: $topic" -ForegroundColor Green
    Write-Host "Nhan Ctrl + C de thoat chuong trinh." -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------`n" -ForegroundColor Cyan
    
    while ($true) {
        $message = Read-Host "Nhap Message"
        
        if ([string]::IsNullOrWhiteSpace($message)) {
            Write-Host "[CANH BAO] Tin nhan trong, thu lai!" -ForegroundColor Red
            continue
        }
        
        $safeMessage = $message -replace '"', '\"'
        $fullCommand = "mosquitto_pub $baseCmd -m '$safeMessage'"
        
        $pubResult = ""
        try {
            $pubResult = Invoke-Expression "$fullCommand 2>&1" | Out-String
            if ($LASTEXITCODE -ne 0 -or $pubResult -match "Denied|Error") {
                Write-Host "-> [LOI] Khong the Publish. Vui long kiem tra lai quyen!" -ForegroundColor Red
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
    $fullCommand = "mosquitto_sub $baseCmd -v"
    
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