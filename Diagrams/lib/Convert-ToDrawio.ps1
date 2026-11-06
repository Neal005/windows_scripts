param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Path,
    [string]$OutputPath,
    [ValidateSet("mono", "accent")]
    [string]$Theme,
    [ValidateSet("raw", "erd")]
    [string]$Kind,
    [switch]$NoClobber,
    [switch]$NoPause
)
# Convert-ToDrawio.ps1 - ENGINE dung chung cua Gen-Erd.ps1 / Gen-Raw.ps1 (o thu muc cha), co the chay rieng.
# JSON -> .drawio qua `python -B -m diagram_tool` (thu vien chuan, khong can pip).
# Dung: .\Convert-ToDrawio.ps1 file.json            -> file.drawio canh file.json (erd: ten.gen.drawio)
#       .\Convert-ToDrawio.ps1 thu_muc              -> moi *.json trong thu muc (khong de quy, bo *.meta.json; dung -Kind erd cho *.meta.json)
#       .\Convert-ToDrawio.ps1 a.json -OutputPath D:\ra\a.drawio
#       .\Convert-ToDrawio.ps1 thu_muc -OutputPath D:\ra   (OutputPath la THU MUC khi dau vao la thu muc)
#       Keo tha file/thu muc vao script cung duoc. -Theme mono|accent ghi de chu de; -NoClobber khong ghi de.
#       -Kind raw|erd: bat buoc dung loai dau vao (erd = file *.meta.json cua du an; thu muc chi lay *.meta.json).
# Ten file dau ra do CLI quyet dinh (script khong tu tinh); CLI in "wrote: <duong dan>" hoac "skipped: <duong dan>".
# Bien moi truong DIAGRAM_PYTHON (duong dan python.exe) duoc uu tien neu co.
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Pause-Exit([int]$Code) {
    if (-not $NoPause) { Pause }
    exit $Code
}

function Test-PythonCandidate([string]$Exe, [string[]]$Prefix) {
    # Tra ve $true neu la Python >= 3.8
    try {
        $out = & $Exe @Prefix -c "import sys; print(sys.version_info[0]*100+sys.version_info[1])" 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        return ([int]($out | Select-Object -First 1) -ge 308)
    } catch { return $false }
}

function Find-Python {
    # Thu tu: DIAGRAM_PYTHON -> venv/conda dang bat -> py -3 -> python -> python3
    $list = @()
    if ($env:DIAGRAM_PYTHON) { $list += , @($env:DIAGRAM_PYTHON, @()) }
    if ($env:VIRTUAL_ENV) { $list += , @((Join-Path $env:VIRTUAL_ENV "Scripts\python.exe"), @()) }
    if ($env:CONDA_PREFIX) { $list += , @((Join-Path $env:CONDA_PREFIX "python.exe"), @()) }
    $list += , @("py", @("-3"))
    $list += , @("python", @())
    $list += , @("python3", @())
    foreach ($c in $list) {
        $exe = $c[0]; $prefix = [string[]]$c[1]
        if (($exe -match '[\\/]') -and -not (Test-Path -LiteralPath $exe)) { continue }
        if (Test-PythonCandidate $exe $prefix) { return , @($exe, $prefix) }
    }
    return $null
}

# ---- dau vao ----
if (-not $Path -or $Path.Count -eq 0) {
    $answer = Read-Host "Nhap (hoac keo tha) duong dan file .json hoac thu muc"
    $Path = @($answer)
}
$inputs = @()
foreach ($p in $Path) {
    $q = $p.Trim().Trim('"').Trim("'")
    if ($q.Length -gt 3) { $q = $q.TrimEnd('\', '/') }
    if ([string]::IsNullOrWhiteSpace($q)) { continue }
    if (-not (Test-Path -LiteralPath $q)) {
        Write-Host "Khong tim thay: $q" -ForegroundColor Red
        Pause-Exit 1
    }
    $inputs += (Get-Item -LiteralPath $q).FullName
}
if ($inputs.Count -eq 0) {
    Write-Host "Khong co dau vao." -ForegroundColor Red
    Pause-Exit 1
}

# ---- gom danh sach file ----
$files = @()
foreach ($item in $inputs) {
    if (Test-Path -LiteralPath $item -PathType Container) {
        $found = @(Get-ChildItem -LiteralPath $item -Filter "*.json" -File | Sort-Object Name)
        if ($Kind -eq "erd") {
            $found = @($found | Where-Object { $_.Name -like "*.meta.json" })
        } else {
            # -Kind raw hoac khong chi dinh: bo *.meta.json (la file ERD, can -Kind erd)
            $found = @($found | Where-Object { $_.Name -notlike "*.meta.json" })
        }
        if ($found.Count -eq 0) { Write-Host "Thu muc khong co file phu hop: $item" -ForegroundColor Yellow }
        $files += @($found | ForEach-Object { $_.FullName })
    } else {
        $files += (Get-Item -LiteralPath $item).FullName
    }
}
if ($files.Count -eq 0) { Pause-Exit 1 }

# ---- -OutputPath: tuyet doi hoa truoc khi doi thu muc lam viec; tao thu muc khi can ----
$outArg = $null
if ($OutputPath) {
    $o = $OutputPath.Trim().Trim('"').Trim("'")
    if (-not [System.IO.Path]::IsPathRooted($o)) { $o = Join-Path (Get-Location).Path $o }
    $outArg = [System.IO.Path]::GetFullPath($o)
    $multi = ($files.Count -gt 1) -or ($inputs | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
    if ($multi -and -not (Test-Path -LiteralPath $outArg)) {
        New-Item -ItemType Directory -Path $outArg -Force | Out-Null
    }
    if ($multi -and -not (Test-Path -LiteralPath $outArg -PathType Container)) {
        Write-Host "-OutputPath phai la thu muc khi co nhieu file: $outArg" -ForegroundColor Red
        Pause-Exit 1
    }
}

# ---- Python ----
$py = Find-Python
if (-not $py) {
    Write-Host "Khong tim thay Python >= 3.8 (thu DIAGRAM_PYTHON, venv, conda, py -3, python, python3)." -ForegroundColor Red
    Pause-Exit 1
}
Write-Host ("Python: " + $py[0] + " " + ($py[1] -join " ")) -ForegroundColor DarkGray

$env:PYTHONDONTWRITEBYTECODE = "1"
$env:PYTHONIOENCODING = "utf-8"
$ok = 0; $fail = 0
Push-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)    # thu muc Diagrams (chua diagram_tool)
try {
    foreach ($in in $files) {
        $pyArgs = @($py[1]) + @("-B", "-m", "diagram_tool", $in)
        if ($outArg) { $pyArgs += @("-o", $outArg) }
        if ($Theme) { $pyArgs += @("--theme", $Theme) }
        if ($Kind) { $pyArgs += @("--kind", $Kind) }
        if ($NoClobber) { $pyArgs += "--no-clobber" }
        Write-Host "Chuyen: $in" -ForegroundColor Cyan
        & $py[0] @pyArgs
        if ($LASTEXITCODE -eq 0) {
            $ok++
        } else {
            Write-Host "  That bai (ma thoat $LASTEXITCODE): $in" -ForegroundColor Red
            $fail++
        }
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Xong: $ok thanh cong, $fail that bai." -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Yellow" })
Pause-Exit $(if ($fail -eq 0) { 0 } else { 1 })
