<#
.SYNOPSIS
    Toggle overlay mau den len dung man hinh SmartGlasses (RayNeo).

.HOW IT WORKS
    - KHONG con dua vao do phan giai (de tranh trung voi man laptop). Thay vao
      do, script lay Instance ID cua thiet bi "Generic Monitor (SmartGlasses)"
      qua Get-PnpDevice, roi doi chieu voi tung \\.\DISPLAYn bang Windows API
      EnumDisplayDevices de xac dinh CHINH XAC adapter nao la kinh.
    - Tu nhan dien moi lan chay, khong can chon tay, khong con file config.
    - Overlay dang chay se tu poll lai (2s/lan): neu rut kinh -> tu dong dong;
      neu cam lai o vi tri khac -> tu di chuyen theo.
    - Goi lai script (vd gan phim tat) de BAT/TAT qua lai.
#>

Add-Type -AssemblyName System.Windows.Forms

if (-not ("Native.Display" -as [type])) {
    Add-Type -Namespace Native -Name Display -MemberDefinition @"
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct DISPLAY_DEVICE {
    public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]  public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
    public int StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
}

[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
"@
}

function Find-SmartGlassesAdapterDeviceName {
    # Tim thiet bi monitor co FriendlyName chua "SmartGlasses" trong Device Manager
    $monitorPnp = Get-PnpDevice -Class Monitor -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'SmartGlasses' } |
        Select-Object -First 1

    if (-not $monitorPnp) { return $null }

    # Instance ID dang: MONITOR\<HardwareID>\4&xxxx&0&UIDxxx
    $targetHwId = ($monitorPnp.InstanceId -split '\\')[1]
    if (-not $targetHwId) { return $null }

    $adapterIndex = 0
    while ($true) {
        $adapter = New-Object -TypeName 'Native.Display+DISPLAY_DEVICE'
        $adapter.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($adapter)
        $ok = [Native.Display]::EnumDisplayDevices($null, $adapterIndex, [ref]$adapter, 0)
        if (-not $ok) { break }

        $attached = ($adapter.StateFlags -band 0x1) -ne 0   # DISPLAY_DEVICE_ATTACHED_TO_DESKTOP
        if ($attached) {
            $monitorIndex = 0
            while ($true) {
                $monitor = New-Object -TypeName 'Native.Display+DISPLAY_DEVICE'
                $monitor.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($monitor)
                $mOk = [Native.Display]::EnumDisplayDevices($adapter.DeviceName, $monitorIndex, [ref]$monitor, 0)
                if (-not $mOk) { break }

                if ($monitor.DeviceID) {
                    $hwId = ($monitor.DeviceID -split '\\')[1]
                    if ($hwId -eq $targetHwId) {
                        return $adapter.DeviceName
                    }
                }
                $monitorIndex++
            }
        }
        $adapterIndex++
    }
    return $null
}

function Get-TargetScreen {
    $adapterName = Find-SmartGlassesAdapterDeviceName
    if (-not $adapterName) {
        Write-Host "Khong tim thay man hinh SmartGlasses dang cam. Kiem tra lai ket noi kinh." -ForegroundColor Red
        return $null
    }
    $screen = [System.Windows.Forms.Screen]::AllScreens | Where-Object { $_.DeviceName -ieq $adapterName } | Select-Object -First 1
    if (-not $screen) {
        Write-Host "Tim thay thiet bi ($adapterName) nhung Windows chua nhan no la man hinh active." -ForegroundColor Red
        return $null
    }
    return $screen
}

# ============================================================
# TOGGLE LOGIC
# ============================================================
$lockPath = Join-Path $PSScriptRoot 'smartglasses_overlay.lock'

$overlayAlive = $false
if (Test-Path $lockPath) {
    $procId = Get-Content $lockPath
    if ($procId -and (Get-Process -Id $procId -ErrorAction SilentlyContinue)) {
        $overlayAlive = $true
    } else {
        Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
        Write-Host "Overlay truoc do da tu tat (co the do rut kinh). Da don trang thai." -ForegroundColor DarkYellow
    }
}

if ($overlayAlive) {
    Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
    Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
    Write-Host "Da BAT lai man hinh SmartGlasses." -ForegroundColor Green
    exit
}

$screen = Get-TargetScreen
if (-not $screen) { exit 1 }

$overlayScript = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ("Native.Display" -as [type])) {
    Add-Type -Namespace Native -Name Display -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct DISPLAY_DEVICE {
    public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]  public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
    public int StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
}

[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
'@
}

function Find-SmartGlassesAdapterDeviceName {
    `$monitorPnp = Get-PnpDevice -Class Monitor -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { `$_.FriendlyName -match 'SmartGlasses' } |
        Select-Object -First 1
    if (-not `$monitorPnp) { return `$null }
    `$targetHwId = (`$monitorPnp.InstanceId -split '\\')[1]
    if (-not `$targetHwId) { return `$null }

    `$adapterIndex = 0
    while (`$true) {
        `$adapter = New-Object -TypeName 'Native.Display+DISPLAY_DEVICE'
        `$adapter.cb = [System.Runtime.InteropServices.Marshal]::SizeOf(`$adapter)
        `$ok = [Native.Display]::EnumDisplayDevices(`$null, `$adapterIndex, [ref]`$adapter, 0)
        if (-not `$ok) { break }
        `$attached = (`$adapter.StateFlags -band 0x1) -ne 0
        if (`$attached) {
            `$monitorIndex = 0
            while (`$true) {
                `$monitor = New-Object -TypeName 'Native.Display+DISPLAY_DEVICE'
                `$monitor.cb = [System.Runtime.InteropServices.Marshal]::SizeOf(`$monitor)
                `$mOk = [Native.Display]::EnumDisplayDevices(`$adapter.DeviceName, `$monitorIndex, [ref]`$monitor, 0)
                if (-not `$mOk) { break }
                if (`$monitor.DeviceID) {
                    `$hwId = (`$monitor.DeviceID -split '\\')[1]
                    if (`$hwId -eq `$targetHwId) { return `$adapter.DeviceName }
                }
                `$monitorIndex++
            }
        }
        `$adapterIndex++
    }
    return `$null
}

`$form = New-Object System.Windows.Forms.Form
`$form.FormBorderStyle = 'None'
`$form.BackColor = [System.Drawing.Color]::Black
`$form.StartPosition = 'Manual'
`$form.Bounds = New-Object System.Drawing.Rectangle($($screen.Bounds.X), $($screen.Bounds.Y), $($screen.Bounds.Width), $($screen.Bounds.Height))
`$form.TopMost = `$true
`$form.ShowInTaskbar = `$false
`$form.Cursor = [System.Windows.Forms.Cursors]::None

`$timer = New-Object System.Windows.Forms.Timer
`$timer.Interval = 2000
`$timer.Add_Tick({
    `$adapterName = Find-SmartGlassesAdapterDeviceName
    if (-not `$adapterName) {
        # Kinh bi rut -> tu dong dong, khong de lai overlay mo coi
        `$timer.Stop()
        `$form.Close()
        [System.Windows.Forms.Application]::Exit()
        return
    }
    `$found = [System.Windows.Forms.Screen]::AllScreens | Where-Object { `$_.DeviceName -ieq `$adapterName } | Select-Object -First 1
    if (`$found -and (`$form.Bounds.X -ne `$found.Bounds.X -or `$form.Bounds.Y -ne `$found.Bounds.Y -or `$form.Bounds.Width -ne `$found.Bounds.Width -or `$form.Bounds.Height -ne `$found.Bounds.Height)) {
        `$form.Bounds = `$found.Bounds
    }
})
`$timer.Start()

[System.Windows.Forms.Application]::Run(`$form)
"@

$tempScript = Join-Path $env:TEMP "smartglasses_overlay_$([guid]::NewGuid().ToString('N')).ps1"
Set-Content -Path $tempScript -Value $overlayScript -Encoding UTF8

$proc = Start-Process powershell.exe `
    -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tempScript`"" `
    -WindowStyle Hidden -PassThru

Set-Content -Path $lockPath -Value $proc.Id
Write-Host "Da TAT man hinh SmartGlasses (overlay den)." -ForegroundColor Green
