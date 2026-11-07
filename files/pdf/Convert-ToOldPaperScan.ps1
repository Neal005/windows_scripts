Clear-Host
Write-Host "=== SCAN SIMULATOR: OLD PAPER DOCUMENT (IMAGE-ONLY PDF FOR OCR TESTING) ===" -ForegroundColor Cyan
Write-Host "Yellowed paper, stains, fold crease, faded ink, warp, dust. Output: <name>_giaycu.pdf" -ForegroundColor DarkGray

# ----------------------------------------------------------------------------------------------
# Image processing lives in scan_sim.py (same folder as this script).
# Optional: set $env:SCANSIM_PYTHON to a specific python.exe (e.g. a venv) to use that environment.
# Requires: numpy, pillow, scipy, pymupdf  +  Microsoft Word or LibreOffice for DOCX/DOC input.
# ----------------------------------------------------------------------------------------------

function Pause-Exit {
    param([int]$Code = 0)
    Write-Host ""
    Write-Host "Press Enter to exit..." -ForegroundColor Cyan
    Read-Host | Out-Null
    exit $Code
}

# --- Locate script folder (PSScriptRoot can be empty under some launchers / PS 5.1)
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir -and $MyInvocation.MyCommand.Path) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir -and $PSCommandPath) { $ScriptDir = Split-Path -Parent $PSCommandPath }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$ScanSim = $null
foreach ($cand in @((Join-Path $ScriptDir 'scan_sim.py'), (Join-Path (Get-Location).Path 'scan_sim.py'))) {
    if (Test-Path -LiteralPath $cand) { $ScanSim = (Resolve-Path -LiteralPath $cand).Path; break }
}
if (-not $ScanSim) {
    Write-Host "Critical Error: scan_sim.py not found next to this script ($ScriptDir)!" -ForegroundColor Red
    Pause-Exit 1
}

# --- Locate Python 3: $env:SCANSIM_PYTHON -> active venv/conda -> py -3 -> python -> python3
$PyCmd = $null
$candidates = @()
if ($env:SCANSIM_PYTHON) { $candidates += , @($env:SCANSIM_PYTHON) }
foreach ($envRoot in @($env:VIRTUAL_ENV, $env:CONDA_PREFIX)) {
    if ($envRoot) {
        foreach ($rel in @('Scripts\python.exe', 'python.exe', 'bin/python3')) {
            $p = Join-Path $envRoot $rel
            if (Test-Path -LiteralPath $p) { $candidates += , @($p) }
        }
    }
}
$candidates += , @('py', '-3'); $candidates += , @('python'); $candidates += , @('python3')
foreach ($c in $candidates) {
    if (-not (Get-Command $c[0] -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $c[0])) { continue }
    $extra = @($c | Select-Object -Skip 1)
    try {
        $v = & $c[0] @extra -c "import sys; print(sys.version_info[0])" 2>$null
        if ($LASTEXITCODE -eq 0 -and "$v".Trim() -eq '3') { $PyCmd = $c; break }
    } catch { }
}
if (-not $PyCmd) {
    Write-Host "Critical Error: Python 3 not found! (install Python or set `$env:SCANSIM_PYTHON)" -ForegroundColor Red
    Pause-Exit 1
}
$PyExe = $PyCmd[0]; $PyExtra = @($PyCmd | Select-Object -Skip 1)

& $PyExe @PyExtra -c "import numpy, PIL, scipy, pymupdf" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Critical Error: Python environment is missing libraries!" -ForegroundColor Red
    Write-Host "Run: $($PyCmd -join ' ') -m pip install numpy pillow scipy pymupdf" -ForegroundColor Yellow
    Pause-Exit 1
}
Write-Host "Python : $($PyCmd -join ' ')" -ForegroundColor DarkGray
Write-Host "Engine : $ScanSim" -ForegroundColor DarkGray
Write-Host "------------------------------------------------"

# --- Helpers ----------------------------------------------------------------------------------
function Split-DroppedPaths {
    # Handles: "C:\a b\x.docx" 'D:\y.pdf'  |  & 'E:\z.docx'  |  C:\k.doc  |  C:\path with spaces\x.docx
    param([string]$Text)
    $t = "$Text".Trim()
    if (-not $t) { return @() }
    $t = $t -replace '^\s*&\s+', ''
    $whole = $t.Trim().Trim('"').Trim("'")
    if ($whole -and (Test-Path -LiteralPath $whole)) { return , @($whole) }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($t, '"([^"]*)"|''((?:[^'']|'''')*)''|(\S+)')) {
        $v = if ($m.Groups[1].Success) { $m.Groups[1].Value }
             elseif ($m.Groups[2].Success) { $m.Groups[2].Value -replace "''", "'" }
             else { $m.Groups[3].Value }
        if ($v -and $v -ne '&') { $out.Add($v) }
    }
    return , $out.ToArray()
}

function Find-Soffice {
    $cmd = Get-Command soffice -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @("$env:ProgramFiles\LibreOffice\program\soffice.exe", "${env:ProgramFiles(x86)}\LibreOffice\program\soffice.exe")) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

$script:Word = $null
function Convert-DocToPdf {
    param([string]$InFile, [string]$OutPdf)
    if ($IsWindows -ne $false) {
        try {
            if (-not $script:Word) {
                $script:Word = New-Object -ComObject Word.Application
                $script:Word.Visible = $false
                $script:Word.DisplayAlerts = 0
            }
            $doc = $script:Word.Documents.Open($InFile, $false, $true, $false)
            try { $doc.ExportAsFixedFormat($OutPdf, 17) } finally { $doc.Close($false) | Out-Null }
            if (Test-Path -LiteralPath $OutPdf) { return }
        } catch {
            Write-Host "  (Word unavailable, falling back to LibreOffice...)" -ForegroundColor DarkYellow
        }
    }
    $so = Find-Soffice
    if (-not $so) { throw "Microsoft Word or LibreOffice is required to convert DOCX/DOC to PDF." }
    $tmpDir = Split-Path $OutPdf -Parent
    $p = Start-Process -FilePath $so -ArgumentList @('--headless', '--convert-to', 'pdf', '--outdir', "`"$tmpDir`"", "`"$InFile`"") -Wait -PassThru -NoNewWindow
    $produced = Join-Path $tmpDir ([IO.Path]::GetFileNameWithoutExtension($InFile) + '.pdf')
    if (-not (Test-Path -LiteralPath $produced)) { throw "LibreOffice failed to create the PDF (exit code $($p.ExitCode)). Close all LibreOffice windows and try again." }
    if ($produced -ne $OutPdf) { Move-Item -Force -LiteralPath $produced -Destination $OutPdf }
}

function Read-IntChoice {
    param([string]$Prompt, [int]$Default, [int]$Min, [int]$Max)
    while ($true) {
        $s = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($s)) { return $Default }
        $n = 0
        if ([int]::TryParse($s.Trim(), [ref]$n)) {
            if ($n -ge $Min -and $n -le $Max) { return $n }
            Write-Host "Value must be between $Min and $Max!" -ForegroundColor Red
        } else { Write-Host "Please enter a valid integer!" -ForegroundColor Red }
    }
}

# --- 1. Get input -----------------------------------------------------------------------------
$exts = @('.docx', '.doc', '.pdf')
$files = @()
while ($files.Count -eq 0) {
    $line = Read-Host "Step 1: Drag and drop .docx/.doc/.pdf file(s) or a folder here"
    $found = foreach ($raw in (Split-DroppedPaths $line)) {
        $p = "$raw".Trim().Trim('"').Trim("'")
        if (-not (Test-Path -LiteralPath $p)) { Write-Host "Not found: $p" -ForegroundColor Red; continue }
        $item = Get-Item -LiteralPath $p
        if ($item.PSIsContainer) {
            Get-ChildItem -LiteralPath $item.FullName -File |
                Where-Object { $exts -contains $_.Extension.ToLower() -and $_.BaseName -notmatch '_(scan|giaycu)$' -and $_.Name -notlike '~$*' }
        } elseif ($exts -contains $item.Extension.ToLower()) { $item }
        else { Write-Host "Unsupported file type, skipped: $p" -ForegroundColor Red }
    }
    $files = @($found)
    if ($files.Count -eq 0) { Write-Host "No valid file. Please check the path!" -ForegroundColor Red }
}
Write-Host "=> $($files.Count) file(s) selected:" -ForegroundColor Green
foreach ($f in $files) { Write-Host "   - $($f.Name)" -ForegroundColor Green }
Write-Host "------------------------------------------------"

# --- 2. Aging level
Write-Host "Step 2: Select aging / damage level" -ForegroundColor Yellow
Write-Host "[1] Light  (slightly yellowed, few spots)" -ForegroundColor White
Write-Host "[2] Medium (yellowed, stains, fold crease, faded ink - Default)" -ForegroundColor White
Write-Host "[3] Heavy  (strong stains, broken strokes, warped page, more skew + optional faded table borders)" -ForegroundColor White
$level = Read-IntChoice -Prompt "Please select (1, 2 or 3. Press Enter for 2)" -Default 2 -Min 1 -Max 3
Write-Host "-> Selection: Level $level" -ForegroundColor Magenta
Write-Host "------------------------------------------------"

# --- 2b. Table borders (Heavy only)
$table = 'off'
if ($level -eq 3) {
    Write-Host "Step 2b: Fade table borders?" -ForegroundColor Yellow
    Write-Host "[0] No     (keep table lines as they are - Default)" -ForegroundColor White
    Write-Host "[1] Light  (lines ~60% darkness, a few short ~1 mm breaks)" -ForegroundColor White
    Write-Host "[2] Heavy  (lines ~40% darkness, 2-5 mm breaks, some segments almost gone - stress test)" -ForegroundColor White
    $tc = Read-IntChoice -Prompt "Please select (0, 1 or 2. Press Enter for 0)" -Default 0 -Min 0 -Max 2
    $table = @('off', 'light', 'heavy')[$tc]
    Write-Host "-> Selection: Table borders = $table" -ForegroundColor Magenta
    Write-Host "------------------------------------------------"
}

# --- 3. Resolution
$dpi = Read-IntChoice -Prompt "Step 3: Enter scan resolution in DPI (e.g., 200). Press Enter for default [300]" -Default 300 -Min 72 -Max 1200
Write-Host "-> Selection: $dpi DPI" -ForegroundColor Magenta
Write-Host "------------------------------------------------"

# --- 4. Seed
$seed = Read-IntChoice -Prompt "Step 4: Enter a seed to reproduce a previous result (e.g., 42). Press Enter for random" -Default -1 -Min 0 -Max 1000000000
if ($seed -lt 0) { Write-Host "-> Selection: Random (the seed used is printed after each file)" -ForegroundColor Magenta }
else { Write-Host "-> Selection: Seed $seed" -ForegroundColor Magenta }
Write-Host "------------------------------------------------"


# --- Execute ----------------------------------------------------------------------------------
$work = Join-Path ([IO.Path]::GetTempPath()) ("oldscan_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$results = @(); $failed = 0
try {
    $i = 0
    foreach ($f in $files) {
        $i++
        Write-Host ""
        Write-Host "[$i/$($files.Count)] $($f.Name)" -ForegroundColor Yellow
        try {
            $outPdf = Join-Path $f.DirectoryName ($f.BaseName + "_giaycu.pdf")
            if ($f.Extension.ToLower() -eq '.pdf') { $srcPdf = $f.FullName }
            else {
                Write-Host "  Converting to PDF..." -ForegroundColor DarkCyan
                $id = [guid]::NewGuid().ToString('N')
                $tmpDoc = Join-Path $work ($id + $f.Extension)
                Copy-Item -LiteralPath $f.FullName -Destination $tmpDoc      # works even if the file is open in Word
                $srcPdf = Join-Path $work ($id + '.pdf')
                Convert-DocToPdf -InFile $tmpDoc -OutPdf $srcPdf
            }
            Write-Host "  Simulating old paper scan..." -ForegroundColor DarkCyan
            & $PyExe @PyExtra $ScanSim --mode old --level $level --table $table --dpi $dpi --seed $seed --input $srcPdf --output $outPdf
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outPdf)) { throw "scan_sim.py failed (exit code $LASTEXITCODE)." }
            $results += $outPdf
        } catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
            $failed++
        }
    }
} finally {
    if ($script:Word) {
        try { $script:Word.Quit() } catch { }
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($script:Word)
        $script:Word = $null
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($results.Count -gt 0) {
    Write-Host "COMPLETED! $($results.Count) file(s) processed$(if ($failed) { ", $failed failed" })." -ForegroundColor Green
    foreach ($r in $results) {
        $mb = [math]::Round((Get-Item -LiteralPath $r).Length / 1MB, 1)
        Write-Host "Output saved at: $r ($mb MB)" -ForegroundColor Cyan
    }
} else {
    Write-Host "Error: No output file was created. Please check the messages above." -ForegroundColor Red
}
Pause-Exit $(if ($failed) { 1 } else { 0 })
