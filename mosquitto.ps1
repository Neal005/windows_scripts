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
# 6. KIEM TRA XAC THUC USER/PASS (Gui vao test-conection)
# ==========================================
Write-Host "`n[2/2] Dang kiem tra xac thuc User/Pass..." -ForegroundColor Yellow
$testCmd = "mosquitto_pub $connCmd -t 'test-conection' -m 'ping_auth_check'"

$testResult = ""
try {
    $testResult = Invoke-Expression "$testCmd 2>&1" | Out-String
} catch {
    $testResult = $_.Exception.Message
}

if ($LASTEXITCODE -ne 0 -or $testResult -match "Connection Refused|not authorised|Error") {
    Write-Host "-> [LOI] Xac thuc that bai! Sai Username, Password hoac bi Broker tu choi." -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($testResult)) {
        Write-Host "Chi tiet tu server: $testResult" -ForegroundColor DarkGray
    }
    Read-Host "Nhan Enter de thoat..."
    exit
} else {
    Write-Host "-> Xac thuc thanh cong! Da vao duoc Broker." -ForegroundColor Green
}

# ==========================================
# XU LY CHINH: TACH RIENG PUB VA SUB
# ==========================================

if ($action -match "^p") {
    # --- CHE DO PUBLISH LIEN TUC ---
    Write-Host "`n=== CHE DO GUI TIN LIEN TUC ===" -ForegroundColor Yellow
    Write-Host "Dang lam viec tren Topic: $topic" -ForegroundColor Green
    Write-Host "Go 'exit' vao o Message de thoat chuong trinh." -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------`n" -ForegroundColor Cyan
    
    while ($true) {
        $message = Read-Host "Nhap Message"
        
        # Kiem tra thoat
        if ($message -eq "exit") {
            Write-Host "`nDang thoat che do Publish..." -ForegroundColor Yellow
            break
        }
        
        # Bo qua neu message rong
        if ([string]::IsNullOrWhiteSpace($message)) {
            Write-Host "[CANH BAO] Tin nhan trong, thu lai!" -ForegroundColor Red
            continue
        }
        
        # Them dau \ truoc ngoac kep cua JSON de khong bi loi cu phap
        $safeMessage = $message -replace '"', '\"'
        
        # Rap lenh hoan chinh de Pub
        $fullCommand = "mosquitto_pub $baseCmd -m '$safeMessage'"
        
        # Chay lenh
        try {
            Invoke-Expression $fullCommand
            Write-Host "-> Da gui thanh cong!" -ForegroundColor Green
        } catch {
            Write-Host "-> [LOI] Da co loi xay ra: $_" -ForegroundColor Red
        }
        Write-Host "" # Xuong dong cho dep
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