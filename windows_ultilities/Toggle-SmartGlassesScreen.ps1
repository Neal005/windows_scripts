<#
.SYNOPSIS
    Toggle overlay mau den len man hinh SmartGlasses (RayNeo).

.HOW IT WORKS
    - Nhan dien man hinh qua Screen.AllScreens + EnumDisplaySettings (lay
      tan so quet / Hz), KHONG dung EnumDisplayDevices vi ham do khong on
      dinh tren mot so may.
    - Lan dau: liet ke man hinh de ban chon 1 lan, luu DO PHAN GIAI + Hz.
    - Cac lan sau: tu tim man hinh khop CA do phan giai LAN Hz da luu -> giam
      manh kha nang trung voi man hinh khac (vd man chieu o cong ty).
      Neu van con trung (hiem), uu tien man KHONG PHAI Primary; neu van con
      nhieu hon 1 lua chon thi hoi lai thu cong.
    - Overlay dang chay tu poll lai (2s/lan): neu man hinh khop bien mat
      (rut kinh / doi output) -> tu dong dong; neu doi vi tri -> tu di chuyen theo.
    - Goi lai script (vd gan phim tat) de BAT/TAT qua lai.
#>

Add-Type -AssemblyName System.Windows.Forms

if (-not ("Native.DisplaySettings" -as [type])) {
    Add-Type -Namespace Native -Name DisplaySettings -MemberDefinition @"
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion;
    public short dmDriverVersion;
    public short dmSize;
    public short dmDriverExtra;
    public int   dmFields;
    public int   dmPositionX;
    public int   dmPositionY;
    public int   dmDisplayOrientation;
    public int   dmDisplayFixedOutput;
    public short dmColor;
    public short dmDuplex;
    public short dmYResolution;
    public short dmTTOption;
    public short dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels;
    public int   dmBitsPerPel;
    public int   dmPelsWidth;
    public int   dmPelsHeight;
    public int   dmDisplayFlags;
    public int   dmDisplayFrequency;
    public int   dmICMMethod;
    public int   dmICMIntent;
    public int   dmMediaType;
    public int   dmDitherType;
    public int   dmReserved1;
    public int   dmReserved2;
    public int   dmPanningWidth;
    public int   dmPanningHeight;
}

[DllImport("user32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
"@
}

$logPath    = Join-Path $PSScriptRoot 'smartglasses_log.txt'
$configPath = Join-Path $PSScriptRoot 'smartglasses_screen.json'
$lockPath   = Join-Path $PSScriptRoot 'smartglasses_overlay.lock'

function Write-Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Add-Content -Path $logPath -Encoding UTF8
}

# Phat hien co dang chay o che do tuong tac khong (co cua so console hien
# thi de nguoi dung go phim). Khi chay qua phim tat voi -WindowStyle Hidden,
# cua so bi an -> khong the Read-Host duoc.
if (-not ("Native.ConsoleWin" -as [type])) {
    Add-Type -Namespace Native -Name ConsoleWin -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool IsWindowVisible(IntPtr hWnd);
"@
}
$script:IsInteractive = $false
try {
    $hWnd = [Native.ConsoleWin]::GetConsoleWindow()
    $script:IsInteractive = ($hWnd -ne [IntPtr]::Zero) -and [Native.ConsoleWin]::IsWindowVisible($hWnd)
} catch {
    $script:IsInteractive = $false
}

$ENUM_CURRENT_SETTINGS = -1

function Get-RefreshRate([string]$deviceName) {
    $dm = New-Object -TypeName 'Native.DisplaySettings+DEVMODE'
    $dm.dmSize = [int16][System.Runtime.InteropServices.Marshal]::SizeOf($dm)
    $ok = [Native.DisplaySettings]::EnumDisplaySettings($deviceName, $ENUM_CURRENT_SETTINGS, [ref]$dm)
    if (-not $ok) {
        Write-Log "EnumDisplaySettings that bai cho '$deviceName'."
        return $null
    }
    return $dm.dmDisplayFrequency
}

function Get-ScreenInfoList {
    $screens = [System.Windows.Forms.Screen]::AllScreens
    $list = @()
    foreach ($s in $screens) {
        $hz = Get-RefreshRate $s.DeviceName
        $list += [PSCustomObject]@{
            Screen = $s
            Width  = $s.Bounds.Width
            Height = $s.Bounds.Height
            Hz     = $hz
            Primary = $s.Primary
        }
        Write-Log "AllScreens: DeviceName='$($s.DeviceName)' $($s.Bounds.Width)x$($s.Bounds.Height)@${hz}Hz at ($($s.Bounds.X),$($s.Bounds.Y)) Primary=$($s.Primary)"
    }
    return $list
}

function Get-TargetScreen {
    $infoList = Get-ScreenInfoList

    $HZ_TOLERANCE = 5

    if (Test-Path $configPath) {
        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
        $resMatches = @($infoList | Where-Object { $_.Width -eq $cfg.Width -and $_.Height -eq $cfg.Height })

        if ($resMatches.Count -eq 0) {
            Write-Log "Khong con man hinh nao khop do phan giai $($cfg.Width)x$($cfg.Height) -> co the kinh chua cam. TU CHOI bat overlay."
            Write-Host "Khong tim thay man hinh khop cau hinh da luu (co the kinh chua cam)." -ForegroundColor Red
            return $null
        } elseif ($resMatches.Count -eq 1) {
            $only = $resMatches[0]
            $diff = if ($null -ne $only.Hz -and $null -ne $cfg.Hz) { [Math]::Abs($only.Hz - $cfg.Hz) } else { 9999 }
            if ($diff -le $HZ_TOLERANCE) {
                Write-Log "Khop duy nhat theo do phan giai va Hz gan dung ($($only.Hz)Hz vs $($cfg.Hz)Hz da luu, lech=$diff)."
                return $only.Screen
            } else {
                Write-Log "CANH BAO: chi co 1 man khop do phan giai nhung Hz lech qua xa ($($only.Hz)Hz vs $($cfg.Hz)Hz da luu, lech=$diff) -> co the day la man khac (vd kinh chua cam), TU CHOI bat overlay."
                Write-Host "Khong tim thay dung man SmartGlasses (co the kinh chua cam). Bo qua, khong bat overlay." -ForegroundColor Red
                return $null
            }
        } else {
            # Nhieu man hinh cung do phan giai -> chon Hz GAN NHAT voi Hz da luu
            $withDiff = @($resMatches | ForEach-Object {
                $diff = if ($null -ne $_.Hz -and $null -ne $cfg.Hz) { [Math]::Abs($_.Hz - $cfg.Hz) } else { 9999 }
                [PSCustomObject]@{ Screen = $_.Screen; Primary = $_.Primary; Hz = $_.Hz; Diff = $diff }
            })
            $minDiff = ($withDiff | Measure-Object -Property Diff -Minimum).Minimum

            if ($minDiff -gt $HZ_TOLERANCE) {
                Write-Log "CANH BAO: khong man nao co Hz gan voi $($cfg.Hz)Hz da luu (gan nhat lech=$minDiff) -> TU CHOI bat overlay."
                Write-Host "Khong tim thay dung man SmartGlasses (co the kinh chua cam). Bo qua, khong bat overlay." -ForegroundColor Red
                return $null
            } else {
                $best = @($withDiff | Where-Object { $_.Diff -eq $minDiff })

                if ($best.Count -eq 1) {
                    Write-Log "Trung do phan giai, chon man co Hz gan nhat voi $($cfg.Hz)Hz da luu (lech=$minDiff): $($best[0].Screen.DeviceName) @ $($best[0].Hz)Hz."
                    return $best[0].Screen
                }

                $nonPrimary = @($best | Where-Object { -not $_.Primary })
                if ($nonPrimary.Count -eq 1) {
                    Write-Log "Van trung ca Hz gan nhat, tu dong chon man KHONG PHAI Primary."
                    return $nonPrimary[0].Screen
                }
                Write-Log "Van con $($best.Count) ung vien mo ho -> TU CHOI bat overlay (can chay tay de chon lai)."
                Write-Host "Nhieu man hinh mo ho, khong tu xac dinh duoc. Chay script truc tiep (khong qua phim tat) de chon lai thu cong." -ForegroundColor Red
                return $null
            }
        }
    }

    # Bug 7: neu khong co config va dang chay AN (qua phim tat), Read-Host se
    # mo prompt vo hinh va treo vinh vien. Phat hien va tu choi thay vi treo.
    if (-not $script:IsInteractive) {
        Write-Log "Chua co config va dang chay che do an -> khong the hoi chon tay. TU CHOI."
        Write-Host "Chua cau hinh man hinh. Hay chay script truc tiep (double-click / tu terminal) de chon lan dau." -ForegroundColor Red
        return $null
    }

    Write-Host "=== Chon man hinh SmartGlasses ===" -ForegroundColor Cyan
    for ($i = 0; $i -lt $infoList.Count; $i++) {
        $info = $infoList[$i]
        Write-Host " [$i] $($info.Screen.DeviceName)  $($info.Width)x$($info.Height)@$($info.Hz)Hz  Primary=$($info.Primary)"
    }

    # Bug 6: xac thuc input - chi chap nhan so nguyen trong pham vi hop le.
    $chosen = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $sel = Read-Host "Nhap so thu tu man hinh SmartGlasses (0-$($infoList.Count - 1))"
        $idx = 0
        if ([int]::TryParse(("$sel").Trim(), [ref]$idx) -and $idx -ge 0 -and $idx -lt $infoList.Count) {
            $chosen = $infoList[$idx]
            break
        }
        Write-Host "Lua chon khong hop le. Vui long nhap so tu 0 den $($infoList.Count - 1)." -ForegroundColor Yellow
    }

    if (-not $chosen) {
        Write-Log "Nguoi dung khong nhap duoc lua chon hop le sau 3 lan -> huy."
        Write-Host "Da huy." -ForegroundColor Red
        return $null
    }

    [PSCustomObject]@{
        Width  = $chosen.Width
        Height = $chosen.Height
        Hz     = $chosen.Hz
    } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8

    Write-Log "Da luu lua chon thu cong: $($chosen.Width)x$($chosen.Height)@$($chosen.Hz)Hz"
    return $chosen.Screen
}

# ============================================================
# TOGGLE LOGIC
# ============================================================
Write-Log "===== Script duoc goi ====="

# Doc PID tu lock file mot cach an toan (chi lay dong dau, ep ve int).
function Get-LockedPid {
    if (-not (Test-Path $lockPath)) { return $null }
    $raw = (Get-Content $lockPath -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $raw) { return $null }
    $parsed = 0
    if ([int]::TryParse(("$raw").Trim(), [ref]$parsed)) { return $parsed }
    Write-Log "Lock file chua gia tri khong hop le: '$raw'. Bo qua."
    return $null
}

# Chi loai tru PID trong lock khoi viec don dep NEU no thuc su con song.
# (Neu lock giu PID da chet, phai coi nhu khong co gi duoc bao ve.)
$lockedPid = Get-LockedPid
$trackedPid = $null
if ($lockedPid -and (Get-Process -Id $lockedPid -ErrorAction SilentlyContinue)) {
    $trackedPid = $lockedPid
}

try {
    $strayProcs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*smartglasses_overlay_*' -and $_.ProcessId -ne $trackedPid }
    foreach ($p in $strayProcs) {
        Write-Log "Don tien trinh overlay mo coi PID=$($p.ProcessId)."
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }

    # Don luon cac instance CU cua chinh script nay bi treo - tru tien trinh dang chay.
    $staleMain = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*Toggle-SmartGlassesScreen.ps1*' -and $_.ProcessId -ne $PID }
    foreach ($p in $staleMain) {
        Write-Log "Don tien trinh script chinh cu bi treo PID=$($p.ProcessId)."
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Log "Loi khi quet tien trinh mo coi: $($_.Exception.Message)"
}

# Bug 2: don file tam cu trong %TEMP% (chi xoa file cua chinh minh, cu hon 1 ngay
# hoac khong con tien trinh nao dang dung).
try {
    $liveCmdLines = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object { $_.CommandLine })
    Get-ChildItem -Path $env:TEMP -Filter 'smartglasses_overlay_*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
        $inUse = $false
        foreach ($cl in $liveCmdLines) { if ($cl -like "*$($_.Name)*") { $inUse = $true; break } }
        if (-not $inUse) { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
    }
} catch {
    Write-Log "Loi khi don file tam: $($_.Exception.Message)"
}

$overlayAlive = $false
$procId = Get-LockedPid
if ($procId) {
    if (Get-Process -Id $procId -ErrorAction SilentlyContinue) {
        $overlayAlive = $true
    } else {
        Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
        Write-Log "Overlay truoc do da tu tat (co the do rut kinh). Da don trang thai."
    }
} elseif (Test-Path $lockPath) {
    Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
    Write-Log "Lock file hong/rong -> da xoa."
}

if ($overlayAlive) {
    Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
    Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
    Write-Log "Da BAT lai man hinh SmartGlasses."
    Write-Host "Da BAT lai man hinh SmartGlasses." -ForegroundColor Green
    exit
}

$screen = Get-TargetScreen
if (-not $screen) {
    Write-Log "DUNG: khong xac dinh duoc man hinh, khong bat overlay."
    exit 1
}
$targetWidth  = $screen.Bounds.Width
$targetHeight = $screen.Bounds.Height
$targetHz     = Get-RefreshRate $screen.DeviceName
# Bug 4: neu khong doc duoc Hz, dung 0 lam sentinel (script con se bo qua
# dieu kien Hz thay vi bi loi cu phap do nhung gia tri rong).
if ($null -eq $targetHz) {
    Write-Log "CANH BAO: khong doc duoc Hz cua $($screen.DeviceName), overlay se chi doi chieu theo DeviceName va do phan giai."
    $targetHz = 0
}
Write-Log "Chuan bi bat overlay tren $($screen.DeviceName) ${targetWidth}x${targetHeight}@${targetHz}Hz Bounds=$($screen.Bounds)"

$overlayScript = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ("Native.DisplaySettings" -as [type])) {
    Add-Type -Namespace Native -Name DisplaySettings -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion;
    public short dmDriverVersion;
    public short dmSize;
    public short dmDriverExtra;
    public int   dmFields;
    public int   dmPositionX;
    public int   dmPositionY;
    public int   dmDisplayOrientation;
    public int   dmDisplayFixedOutput;
    public short dmColor;
    public short dmDuplex;
    public short dmYResolution;
    public short dmTTOption;
    public short dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels;
    public int   dmBitsPerPel;
    public int   dmPelsWidth;
    public int   dmPelsHeight;
    public int   dmDisplayFlags;
    public int   dmDisplayFrequency;
    public int   dmICMMethod;
    public int   dmICMIntent;
    public int   dmMediaType;
    public int   dmDitherType;
    public int   dmReserved1;
    public int   dmReserved2;
    public int   dmPanningWidth;
    public int   dmPanningHeight;
}

[DllImport("user32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
'@
}

function Get-RefreshRate2([string]`$deviceName) {
    `$dm = New-Object -TypeName 'Native.DisplaySettings+DEVMODE'
    `$dm.dmSize = [int16][System.Runtime.InteropServices.Marshal]::SizeOf(`$dm)
    `$ok = [Native.DisplaySettings]::EnumDisplaySettings(`$deviceName, -1, [ref]`$dm)
    if (-not `$ok) { return `$null }
    return `$dm.dmDisplayFrequency
}

`$targetWidth      = $targetWidth
`$targetHeight     = $targetHeight
`$targetHz         = $targetHz
`$targetDeviceName = '$($screen.DeviceName)'

`$form = New-Object System.Windows.Forms.Form
`$form.FormBorderStyle = 'None'
`$form.BackColor = [System.Drawing.Color]::Black
`$form.StartPosition = 'Manual'
`$form.Bounds = New-Object System.Drawing.Rectangle($($screen.Bounds.X), $($screen.Bounds.Y), `$targetWidth, `$targetHeight)
`$form.TopMost = `$true
`$form.ShowInTaskbar = `$false
`$form.Cursor = [System.Windows.Forms.Cursors]::None

`$timer = New-Object System.Windows.Forms.Timer
`$timer.Interval = 2000
`$timer.Add_Tick({
    `$all = [System.Windows.Forms.Screen]::AllScreens
    # Uu tien khop dung DeviceName da bat overlay tu dau.
    `$found = `$all | Where-Object { `$_.DeviceName -ieq `$targetDeviceName } | Select-Object -First 1
    if (-not `$found) {
        # Du phong: khop ca do phan giai LAN Hz (khong duoc chi dung do phan
        # giai, vi de nham voi man laptop cung do phan giai nhung khac Hz).
        # Neu `$targetHz = 0 (khong doc duoc luc bat) thi bo qua dieu kien Hz.
        `$found = `$all | Where-Object {
            `$_.Bounds.Width -eq `$targetWidth -and `$_.Bounds.Height -eq `$targetHeight -and
            (`$targetHz -eq 0 -or (Get-RefreshRate2 `$_.DeviceName) -eq `$targetHz)
        } | Select-Object -First 1
    }

    if (-not `$found) {
        # Khong con man nao khop chinh xac -> kinh da bi rut, tu dong dong
        `$timer.Stop()
        `$form.Close()
        [System.Windows.Forms.Application]::Exit()
        return
    }
    if (`$form.Bounds.X -ne `$found.Bounds.X -or `$form.Bounds.Y -ne `$found.Bounds.Y) {
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

# Bug 5: xac minh overlay that su song sot (khong crash ngay do loi cu phap
# trong script con). Neu no chet ngay, KHONG ghi lock file - de lan bam phim
# tat sau khong tuong nham la "dang bat" roi chi tat mot thu khong ton tai.
Start-Sleep -Milliseconds 700
if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) {
    Write-Log "LOI: tien trinh overlay (PID=$($proc.Id)) da thoat ngay sau khi khoi dong -> script con co the bi loi. Khong ghi lock."
    Write-Host "Khong bat duoc overlay (tien trinh con thoat ngay). Xem log de biet them." -ForegroundColor Red
    Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
    exit 1
}

Set-Content -Path $lockPath -Value $proc.Id
Write-Log "Da TAT man hinh SmartGlasses (overlay den), PID=$($proc.Id)."
Write-Host "Da TAT man hinh SmartGlasses (overlay den)." -ForegroundColor Green