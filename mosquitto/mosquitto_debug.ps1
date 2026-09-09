<#
.SYNOPSIS
    MQTT Publish/Subscribe helper for mosquitto_pub / mosquitto_sub (Debug Mode:
    checks network, credentials, and ACL permissions before running).

.DESCRIPTION
    Runs interactively by default (prompts for each value, same as before).
    Any value can instead be supplied directly as a parameter, which skips
    that one prompt only — so a human and an agent can mix-and-match, or an
    agent can supply everything for a fully non-interactive run.

.PARAMETER Action
    'p' (Publish) or 's' (Subscribe).

.PARAMETER HostAddress
    Broker host. Defaults to 'localhost' if passed empty.

.PARAMETER Port
    Broker port. Defaults to '1884' if passed empty.

.PARAMETER Topic
    MQTT topic. Required — cannot be empty.

.PARAMETER UserName
    Broker username. Leave unset for no auth.

.PARAMETER Password
    Broker password, in PLAIN TEXT. See the security note below.

.PARAMETER ClientId
    MQTT client id (-i). If passed empty, an ID is auto-generated silently
    (no prompt) so an agent run never blocks.

.PARAMETER CheckAcl
    'y' or 'n'. If supplied, skips the "check permissions?" prompt and uses
    this value directly.

.PARAMETER Message
    Publish mode only. If supplied, sends this ONE message and exits
    immediately instead of entering the interactive "Enter Message" loop.

.PARAMETER WaitSeconds
    Subscribe mode only. Passed to mosquitto_sub -W — exit automatically
    after this many seconds with no message, instead of listening forever.

.PARAMETER MessageCount
    Subscribe mode only. Passed to mosquitto_sub -C — exit automatically
    after receiving this many messages.

.PARAMETER NonInteractive
    Suppresses every "Press Enter to exit..." pause. Set this for agent runs
    so the script never waits on a keypress that will never come.

.EXAMPLE
    # Original interactive behavior, unchanged
    .\mosquitto_debug.ps1

.EXAMPLE
    # Fully non-interactive: check everything, publish one message, exit
    .\mosquitto_debug.ps1 -Action p -HostAddress "192.168.1.10" -Port 1884 `
        -Topic "my/topic" -UserName "admin" -Password "secret" `
        -ClientId "agent-01" -CheckAcl y -Message "hello world" -NonInteractive

.EXAMPLE
    # Non-interactive subscribe, skip ACL check, auto-exit after 10s
    .\mosquitto_debug.ps1 -Action s -HostAddress "192.168.1.10" -Topic "my/topic" `
        -CheckAcl n -WaitSeconds 10 -NonInteractive

.NOTES
    Passing -Password on the command line leaves it in plain text in your
    shell history / process list. Prefer the interactive secure prompt
    (leave -Password unset) whenever a human runs this directly; only pass
    -Password for trusted, automated/agent contexts.
#>
param(
    [ValidateSet('p','s','pub','sub')]
    [string]$Action,

    [string]$HostAddress,

    [string]$Port,

    [string]$Topic,

    [string]$UserName,

    [string]$Password,

    [string]$ClientId,

    [ValidateSet('y','n')]
    [string]$CheckAcl,

    [string]$Message,

    [int]$WaitSeconds,

    [int]$MessageCount,

    [switch]$NonInteractive
)

# Change encoding to UTF-8 for proper character display
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== MOSQUITTO MQTT MANAGEMENT TOOL (DEBUG MODE) ===" -ForegroundColor Cyan

# 1. Select Pub or Sub
if ($PSBoundParameters.ContainsKey('Action')) {
    $action = $Action
    Write-Host "-> Action (from parameter): $action" -ForegroundColor DarkGray
} else {
    $action = Read-Host "Do you want to Publish (p) or Subscribe (s)?"
    while ($action -notmatch "^(p|s|pub|sub)$") {
        $action = Read-Host "Please enter 'p' (Publish) or 's' (Subscribe)"
    }
}

# 2. Enter Host, Port and main Topic
if ($PSBoundParameters.ContainsKey('HostAddress')) {
    $hostAddress = $HostAddress
    if ([string]::IsNullOrWhiteSpace($hostAddress)) { $hostAddress = "localhost" }
} else {
    $hostAddress = Read-Host "Enter Host (Leave blank for 'localhost')"
    if ([string]::IsNullOrWhiteSpace($hostAddress)) { $hostAddress = "localhost" }
}

if ($PSBoundParameters.ContainsKey('Port')) {
    $port = $Port
    if ([string]::IsNullOrWhiteSpace($port)) { $port = "1884" }
} else {
    $port = Read-Host "Enter Port (Leave blank for default '1884')"
    if ([string]::IsNullOrWhiteSpace($port)) { $port = "1884" }
}

if ($PSBoundParameters.ContainsKey('Topic')) {
    $topic = $Topic
    if ([string]::IsNullOrWhiteSpace($topic)) {
        Write-Host "-> [ERROR] -Topic cannot be empty." -ForegroundColor Red
        exit 1
    }
} else {
    $topic = Read-Host "Enter the main Topic (e.g., my/topic)"
    while ([string]::IsNullOrWhiteSpace($topic)) {
        $topic = Read-Host "Topic cannot be empty, please re-enter"
    }
}

# 3. Enter Username / Password (Hidden Password)
if ($PSBoundParameters.ContainsKey('UserName')) {
    $user = $UserName
} else {
    $user = Read-Host "Enter Username (Leave blank if none)"
}

if ($PSBoundParameters.ContainsKey('Password')) {
    $pass = $Password
} else {
    $securePass = Read-Host "Enter Password (Leave blank if none)" -AsSecureString
    # Decrypt Password securely to pass into command
    $pass = (New-Object System.Net.NetworkCredential("", $securePass)).Password
}

# 3b. Enter Client ID (-i) — required by some brokers/ACL configs
if ($PSBoundParameters.ContainsKey('ClientId')) {
    $clientId = $ClientId
    if ([string]::IsNullOrWhiteSpace($clientId)) {
        $clientId = "psmqtt_" + [System.Guid]::NewGuid().ToString("N").Substring(0,8)
    }
} else {
    $clientId = Read-Host "Enter Client ID (Leave blank to auto-generate)"
    if ([string]::IsNullOrWhiteSpace($clientId)) {
        $clientId = "psmqtt_" + [System.Guid]::NewGuid().ToString("N").Substring(0,8)
        Write-Host "-> No Client ID entered, using auto-generated ID: $clientId" -ForegroundColor DarkGray
    }
}

# 4. Build CONNECTION command structure
$connCmd = "-h $hostAddress -p $port -i `"$clientId`""
if (-not [string]::IsNullOrWhiteSpace($user)) { $connCmd += " -u `"$user`"" }
if (-not [string]::IsNullOrWhiteSpace($pass)) { $connCmd += " -P `"$pass`"" }

$baseCmd = "$connCmd -t `"$topic`""

# ==========================================
# 5. CHECK NETWORK CONNECTION (PING PORT)
# ==========================================
Write-Host "`n[1/3] Checking network connection to ${hostAddress}:${port}..." -ForegroundColor Yellow
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connectTask = $tcpClient.ConnectAsync($hostAddress, $port)
    if ($connectTask.Wait(2000) -and $tcpClient.Connected) {
        Write-Host "-> [OK] Connected to MQTT broker successfully!" -ForegroundColor Green
        $tcpClient.Close()
    } else {
        Write-Host "-> [ERROR] Cannot connect to ${hostAddress}:${port}. MQTT Broker might be down or incorrect address!" -ForegroundColor Red
        if (-not $NonInteractive) { Read-Host "Press Enter to exit..." }
        exit 1
    }
} catch {
    Write-Host "-> [ERROR] Cannot connect to ${hostAddress}:${port}. $_" -ForegroundColor Red
    if (-not $NonInteractive) { Read-Host "Press Enter to exit..." }
    exit 1
}

# ==========================================
# 6. CHECK LOGIN CREDENTIALS (AUTHENTICATION)
# ==========================================
Write-Host "`n[2/3] Verifying login credentials (Username/Password)..." -ForegroundColor Yellow

# Run a test command with -d flag to catch exact errors from Broker
$authCheckCmd = "mosquitto_pub $connCmd -t `"test/auth/dummy`" -m `"`" -d"
$authResult = ""
try {
    $authResult = Invoke-Expression "$authCheckCmd 2>&1" | Out-String

    # If 'not authorised' error is returned, it is 100% due to wrong credentials
    if ($authResult -match "not authorised" -or $authResult -match "CONNACK \(5\)") {
        Write-Host "-> [ERROR] INCORRECT USERNAME OR PASSWORD! (Or account does not exist)" -ForegroundColor Red
        if (-not $NonInteractive) { Read-Host "Press Enter to exit..." }
        exit 1
    } elseif ($authResult -match "Error: Connection refused") {
        Write-Host "-> [ERROR] Broker refused connection. (Broker denying access or blocking IP)" -ForegroundColor Red
        if (-not $NonInteractive) { Read-Host "Press Enter to exit..." }
        exit 1
    } else {
        Write-Host "-> [OK] Login successful! Credentials are valid." -ForegroundColor Green
    }
} catch {
    Write-Host "-> [ERROR] Unknown error during credential check: $_" -ForegroundColor Red
}

# ==========================================
# 7. CHECK PUB/SUB PERMISSIONS (ACL) ON TOPIC
# ==========================================
Write-Host ""
if ($PSBoundParameters.ContainsKey('CheckAcl')) {
    $checkAcl = $CheckAcl
    Write-Host "-> Check ACL permissions (from parameter): $checkAcl" -ForegroundColor DarkGray
} else {
    $checkAcl = Read-Host "Do you want to check Pub/Sub permissions on the topic? (y/n - Leave blank for 'y')"
}

if ($checkAcl -notmatch "^n") {
    Write-Host "`n[3/3] Verifying permissions (ACL) on topic '$topic'..." -ForegroundColor Yellow

    $hasPub = $false
    $hasSub = $false

    # Check Publish permission
    $testPubCmd = "mosquitto_pub $connCmd -t `"$topic`" -m `"ping_auth_check`" -d"
    $pubResult = ""
    try {
        $pubResult = Invoke-Expression "$testPubCmd 2>&1" | Out-String
        # Since Auth passed, a block here means missing write permission
        if ($LASTEXITCODE -eq 0 -and $pubResult -notmatch "Denied|Error|Connection lost") {
            $hasPub = $true
        }
    } catch {}

    # Check Subscribe permission
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

    # Display Permissions Summary Table
    Write-Host "`n+--------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "| ACCOUNT PERMISSION RESULTS ON BROKER             |" -ForegroundColor Cyan
    Write-Host "+--------------------------------------------------+" -ForegroundColor Cyan

    if ($hasPub) {
        Write-Host "| Publish Permission  :  [ V ] Allowed                 |" -ForegroundColor Green
    } else {
        Write-Host "| Publish Permission  :  [ X ] Denied (No permission)  |" -ForegroundColor DarkGray
    }

    if ($hasSub) {
        Write-Host "| Subscribe Permission:  [ V ] Allowed                 |" -ForegroundColor Green
    } else {
        Write-Host "| Subscribe Permission:  [ X ] Denied (No permission)  |" -ForegroundColor DarkGray
    }
    Write-Host "+--------------------------------------------------+`n" -ForegroundColor Cyan

    # Handle block / allow logic
    if ($action -match "^p") {
        if (-not $hasPub) {
            Write-Host "-> [ERROR] Account DOES NOT HAVE Publish permission for topic '$topic'!" -ForegroundColor Red
            if (-not $NonInteractive) { Read-Host "Press Enter to exit..." }
            exit 1
        } else {
            Write-Host "-> [OK] Publish permission valid! Switching to terminal..." -ForegroundColor Green
        }
    } else {
        if (-not $hasSub) {
            Write-Host "-> [ERROR] Account DOES NOT HAVE Subscribe permission for topic '$topic'!" -ForegroundColor Red
            if (-not $NonInteractive) { Read-Host "Press Enter to exit..." }
            exit 1
        } else {
            Write-Host "-> [OK] Subscribe permission valid! Switching to terminal..." -ForegroundColor Green
        }
    }
} else {
    Write-Host "`n-> [3/3] SKIPPING permission check (ACL). Proceeding directly!" -ForegroundColor DarkGray
}

Start-Sleep -Seconds 1

# ==========================================
# 8. MAIN PROCESSING: SEPARATE PUB AND SUB
# ==========================================

if ($action -match "^p") {
    Write-Host "`n=== CONTINUOUS PUBLISH MODE ===" -ForegroundColor Yellow
    Write-Host "Working on Topic: $topic" -ForegroundColor Green

    if ($PSBoundParameters.ContainsKey('Message')) {
        # Single-shot publish (agent/non-interactive mode): send one message, then exit
        Write-Host "--------------------------------------------------`n" -ForegroundColor Cyan
        $safeMessage = $Message -replace '"', '\"'
        $fullCommand = "mosquitto_pub $baseCmd -m '$safeMessage'"

        $pubResult = ""
        try {
            $pubResult = Invoke-Expression "$fullCommand 2>&1" | Out-String
            if ($LASTEXITCODE -ne 0 -or $pubResult -match "Denied|Error") {
                Write-Host "-> [ERROR] Cannot Publish. Please re-verify permissions!" -ForegroundColor Red
                if (-not [string]::IsNullOrWhiteSpace($pubResult)) { Write-Host "Details: $pubResult" -ForegroundColor DarkGray }
                exit 1
            } else {
                Write-Host "-> Sent successfully!" -ForegroundColor Green
            }
        } catch {
            Write-Host "-> [ERROR] An error occurred: $_" -ForegroundColor Red
            exit 1
        }
        exit 0
    }

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
            if ($LASTEXITCODE -ne 0 -or $pubResult -match "Denied|Error") {
                Write-Host "-> [ERROR] Cannot Publish. Please re-verify permissions!" -ForegroundColor Red
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
    if ($PSBoundParameters.ContainsKey('WaitSeconds')) { $fullCommand += " -W $WaitSeconds" }
    if ($PSBoundParameters.ContainsKey('MessageCount')) { $fullCommand += " -C $MessageCount" }

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
    if (-not $NonInteractive) { Read-Host "Press Enter to exit..." }
}
