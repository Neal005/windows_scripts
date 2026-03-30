# Chuyen doi ma hoa sang UTF-8 de hien thi ky tu chuan
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== CONG CU QUAN LY MOSQUITTO MQTT (FAST MODE) ===" -ForegroundColor Cyan

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
Write-Host "`n[1/1] Dang kiem tra ket noi mang den ${hostAddress}:${port}..." -ForegroundColor Yellow
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connectTask = $tcpClient.ConnectAsync($hostAddress, $port)
    if ($connectTask.Wait(2000) -and $tcpClient.Connected) {
        Write-Host "-> Ket noi may chu MQTT thanh cong! Vao viec luon..." -ForegroundColor Green
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

Start-Sleep -Seconds 1

# ==========================================
# XU LY CHINH: TACH RIENG PUB VA SUB
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
            if ($LASTEXITCODE -ne 0 -or $pubResult -match "not authorised|Connection Refused|Error") {
                Write-Host "-> [LOI] Khong the Publish. Sai Pass hoac khong co quyen tren topic nay!" -ForegroundColor Red
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