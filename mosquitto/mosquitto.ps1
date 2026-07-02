# Change encoding to UTF-8 for proper character display
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== MOSQUITTO MQTT MANAGEMENT TOOL (FAST MODE) ===" -ForegroundColor Cyan

# 1. Select Pub or Sub
$action = Read-Host "Do you want to Publish (p) or Subscribe (s)?"
while ($action -notmatch "^(p|s|pub|sub)$") {
    $action = Read-Host "Please enter 'p' (Publish) or 's' (Subscribe)"
}

# 2. Enter Host, Port and main Topic
$hostAddress = Read-Host "Enter Host (Leave blank for 'localhost')"
if ([string]::IsNullOrWhiteSpace($hostAddress)) { $hostAddress = "localhost" }

$port = Read-Host "Enter Port (Leave blank for default '1884')"
if ([string]::IsNullOrWhiteSpace($port)) { $port = "1884" }

$topic = Read-Host "Enter the main Topic (e.g., my/topic)"
while ([string]::IsNullOrWhiteSpace($topic)) {
    $topic = Read-Host "Topic cannot be empty, please re-enter"
}

# 3. Enter Username / Password (Hidden Password)
$user = Read-Host "Enter Username (Leave blank if none)"

$securePass = Read-Host "Enter Password (Leave blank if none)" -AsSecureString
# Decrypt Password securely to pass into command
$pass = (New-Object System.Net.NetworkCredential("", $securePass)).Password

# 4. Build CONNECTION command structure
$connCmd = "-h $hostAddress -p $port"
if (-not [string]::IsNullOrWhiteSpace($user)) { $connCmd += " -u `"$user`"" }
if (-not [string]::IsNullOrWhiteSpace($pass)) { $connCmd += " -P `"$pass`"" }

$baseCmd = "$connCmd -t `"$topic`""

# ==========================================
# 5. CHECK NETWORK CONNECTION (PING PORT)
# ==========================================
Write-Host "`n[1/1] Checking network connection to ${hostAddress}:${port}..." -ForegroundColor Yellow
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connectTask = $tcpClient.ConnectAsync($hostAddress, $port)
    if ($connectTask.Wait(2000) -and $tcpClient.Connected) {
        Write-Host "-> Connected to MQTT broker successfully! Proceeding..." -ForegroundColor Green
        $tcpClient.Close()
    } else {
        Write-Host "-> [ERROR] Cannot connect to ${hostAddress}:${port}. MQTT Broker might be down or incorrect address!" -ForegroundColor Red
        Read-Host "Press Enter to exit..."
        exit
    }
} catch {
    Write-Host "-> [ERROR] Cannot connect to ${hostAddress}:${port}. $_" -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    exit
}

Start-Sleep -Seconds 1

# ==========================================
# MAIN PROCESSING: SEPARATE PUB AND SUB
# ==========================================

if ($action -match "^p") {
    Write-Host "`n=== CONTINUOUS PUBLISH MODE ===" -ForegroundColor Yellow
    Write-Host "Working on Topic: $topic" -ForegroundColor Green
    Write-Host "Press Ctrl + C to exit." -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------`n" -ForegroundColor Cyan
    
    while ($true) {
        $message = Read-Host "Enter Message"
        
        if ([string]::IsNullOrWhiteSpace($message)) {
            Write-Host "[WARNING] Empty message, try again!" -ForegroundColor Red
            continue
        }
        
        $safeMessage = $message -replace '"', '\"'
        $fullCommand = "mosquitto_pub $baseCmd -m '$safeMessage'"
        
        $pubResult = ""
        try {
            $pubResult = Invoke-Expression "$fullCommand 2>&1" | Out-String
            if ($LASTEXITCODE -ne 0 -or $pubResult -match "not authorised|Connection Refused|Error") {
                Write-Host "-> [ERROR] Cannot Publish. Incorrect Password or missing permissions on this topic!" -ForegroundColor Red
                if (-not [string]::IsNullOrWhiteSpace($pubResult)) { Write-Host "Details: $pubResult" -ForegroundColor DarkGray }
            } else {
                Write-Host "-> Sent successfully!" -ForegroundColor Green
            }
        } catch {
            Write-Host "-> [ERROR] An error occurred: $_" -ForegroundColor Red
        }
        Write-Host ""
    }

} else {
    $fullCommand = "mosquitto_sub $baseCmd -v"
    
    $displayCommand = $fullCommand
    if (-not [string]::IsNullOrWhiteSpace($pass)) {
        $displayCommand = $displayCommand.Replace("-P `"$pass`"", "-P `"***`"")
    }
    
    Write-Host "`nListening for data on Topic: $topic ... (Press Ctrl + C to exit)" -ForegroundColor Yellow
    Write-Host $displayCommand -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------`n" -ForegroundColor Cyan
    
    try {
        Invoke-Expression $fullCommand
    } catch {
        Write-Host "`n[ERROR] An error occurred: $_" -ForegroundColor Red
    }
    
    Write-Host "`n"
    Read-Host "Press Enter to exit..."
}