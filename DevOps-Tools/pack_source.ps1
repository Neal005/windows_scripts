param(
    [Parameter(Position=0)]
    [string]$TargetFolder
)
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ([string]::IsNullOrWhiteSpace($TargetFolder)) {
    $TargetFolder = Read-Host "Please enter (or drag and drop) the directory path to pack"
}
$TargetFolder = $TargetFolder.Trim('"').Trim("'")
if ($TargetFolder.Length -gt 3) { $TargetFolder = $TargetFolder.TrimEnd('\', '/') }
if (-not (Test-Path -LiteralPath $TargetFolder -PathType Container)) {
    Write-Host "Directory does not exist or is invalid: $TargetFolder" -ForegroundColor Red
    Pause
    exit 1
}

$ProjectDir = (Get-Item -LiteralPath $TargetFolder).FullName.TrimEnd('\')
$ProjectName = (Split-Path $ProjectDir -Leaf)
if ([string]::IsNullOrWhiteSpace($ProjectName) -or $ProjectName -match ':') {
    Write-Host "Khong dong goi duoc goc o dia. Hay chon mot thu muc du an." -ForegroundColor Red
    Pause
    exit 1
}
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ZipFileName = "${ProjectName}_SourceCode_Update_${Timestamp}.zip"

$ParentDir = (Get-Item -LiteralPath $ProjectDir).Parent
if ($ParentDir) {
    $ZipFilePath = Join-Path $ParentDir.FullName $ZipFileName
} else {
    $ZipFilePath = Join-Path $ProjectDir $ZipFileName
}

$TempDir = Join-Path $env:TEMP "${ProjectName}_Pack_${Timestamp}"
Write-Host "Creating temporary directory at: $TempDir" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# Thu muc bi loai o MOI cap (robocopy /XD khop theo ten, khong phan biet hoa thuong, ho tro wildcard).
# Cac ten chung chung nhu "test", "data", "docs", "bin", "obj" CO Y KHONG dua vao day vi la source that
# (src/test, Data/Seeds, bin/*.ps1...). bin/obj cua .NET duoc nhan dien rieng ben duoi.
$ExcludedDirs = @(
    # VCS / IDE
    ".git", ".vscode", ".vs", ".idea",
    # Build output
    "target", "build", "out", "node_modules",
    ".next", ".nuxt", ".angular", ".gradle", ".cache",
    # Python
    "venv", ".venv", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", "mlruns", ".ocr_tmp",
    # Test / verify / coverage output
    "TestResults", "test-results", "test-classes", "playwright-report", "coverage",
    "TestBuild", "_build_verify*", "*build_check*", "*_smoke*", "*-smoke*", "artifacts",
    # Tam / secrets / runtime
    "tmp", "temp", ".aspnet-data-protection-keys", ".rustfs.sys",
    # Rieng du an
    "App_Data", "admin-app"
)
# Chi loai o thu muc GOC cua du an (tranh xoa nham thu muc cung ten o cap sau, vd wwwroot/lib/x/dist).
$RootOnlyCommon = @("dist", "Agent")
$RootOnlyExcludes = @{
    "rustfs"    = @("data")
    "tt02_api"  = @("uploads")
    "local_AI"  = @("uploads")
}
$ExcludedFiles = @(
    "appsettings*.json", ".env", ".env.*", "launchSettings.json", "secrets.json",
    "*.pfx", "*.pem", "*.key",
    "*.zip", "*.7z", "*.rar", "*.tar", "*.gz", "*.tgz",
    "*.log", "*.pyc", "*.pyo", "*.bak", "*.tmp",
    ".last_pack_commit"
)

# Thu muc goc bi loai (tuong doi so voi ProjectDir)
$rootOnlyList = @($RootOnlyCommon)
if ($RootOnlyExcludes.ContainsKey($ProjectName)) { $rootOnlyList += $RootOnlyExcludes[$ProjectName] }

# bin/obj: chi loai khi la output cua .NET (canh file .csproj) hoac Eclipse (canh .classpath).
# Cac thu muc "bin" chua script trien khai (Build_and_Start.ps1, DeployDocker.ps1...) duoc giu lai.
$dynamicRel = @()
$markers = @(Get-ChildItem -LiteralPath $ProjectDir -Recurse -Depth 4 -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in '.csproj', '.fsproj', '.vbproj' -or $_.Name -eq '.classpath' })
foreach ($m in $markers) {
    $dirFull = $m.DirectoryName
    if ($dirFull.Length -lt $ProjectDir.Length) { continue }
    $rel = $dirFull.Substring($ProjectDir.Length).TrimStart('\')
    foreach ($sub in @('bin', 'obj')) {
        if ($m.Name -eq '.classpath' -and $sub -eq 'obj') { continue }
        $dynamicRel += $(if ($rel) { "$rel\$sub" } else { $sub })
    }
}
$dynamicRel = @($dynamicRel | Select-Object -Unique)

$xdList = @($ExcludedDirs)
foreach ($d in $rootOnlyList) { $xdList += (Join-Path $ProjectDir $d) }
foreach ($d in $dynamicRel)   { $xdList += (Join-Path $ProjectDir $d) }

Write-Host "Thu muc bin/obj bi loai (nhan dien tu .csproj/.classpath): $($dynamicRel.Count)" -ForegroundColor Gray

Write-Host "Copying source code (excluding config, build output and junk)..." -ForegroundColor Cyan
$RobocopyLog = Join-Path $env:TEMP "pack_robocopy_${Timestamp}.log"
# /E thay cho /MIR (dich trong, khong can purge); /MT da luong; /XJ bo qua junction/symlink de tranh vong lap
$robocopyArgs = @(
    $ProjectDir, $TempDir,
    "/E", "/XJ", "/MT:16", "/R:1", "/W:1",
    "/NFL", "/NDL", "/NJH", "/NJS", "/NP",
    "/LOG:$RobocopyLog",
    "/XD"
) + $xdList + @("/XF") + $ExcludedFiles
& robocopy @robocopyArgs | Out-Null
$robocopyExit = $LASTEXITCODE
# Robocopy exit codes 0-7 are success/no-error variants; 8+ means real errors occurred
if ($robocopyExit -ge 8) {
    Write-Host "FAILED: robocopy loi (exit code $robocopyExit). Xem log: $RobocopyLog" -ForegroundColor Red
    Write-Host "Co the do file bi khoa (dang chay), thieu quyen, hoac duong dan qua dai. Khong tao ZIP, khong cap nhat moc commit." -ForegroundColor Red
    Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    Pause
    exit 1
}

# Kiem tra 1 duong dan (tuong doi, co the dung '/') co nam trong thu muc bi loai hay khong
function Test-ExcludedPath([string]$relPath) {
    $norm = $relPath -replace '/', '\'
    $segments = $norm -split '\\'
    # chi xet cac segment thu muc (bo segment cuoi = ten file)
    for ($i = 0; $i -lt $segments.Count - 1; $i++) {
        foreach ($pat in $ExcludedDirs) {
            if ($segments[$i] -like $pat) { return $true }
        }
    }
    foreach ($d in ($rootOnlyList + $dynamicRel)) {
        $prefix = ($d -replace '/', '\').TrimEnd('\') + '\'
        if ($norm.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# File co bi loai theo $ExcludedFiles khong (khop theo ten file)
function Test-ExcludedFileName([string]$relPath) {
    $leaf = Split-Path ($relPath -replace '/', '\') -Leaf
    foreach ($pat in $ExcludedFiles) {
        if ($leaf -like $pat) { return $true }
    }
    return $false
}

# Duong dan nhap tay co an toan de dua vao cleanup khong
function Test-SafeRelativePath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    if ([System.IO.Path]::IsPathRooted($p)) { return $false }
    if ($p -match '[\*\?]') { return $false }
    foreach ($seg in ($p -split '[\\/]')) {
        if ($seg -eq '..' -or $seg -eq '.' -or $seg -eq '') { return $false }
    }
    return $true
}

# ==============================================================================
# PHAN MO RONG: TU DONG TIM FILE DA BI XOA VA TAO SCRIPT CLEANUP
# ==============================================================================
$deletedFiles = @()
$StateFilePath = Join-Path $ProjectDir ".last_pack_commit"
$currentCommit = $null

if (Test-Path -LiteralPath (Join-Path $ProjectDir ".git")) {
    Push-Location $ProjectDir
    try {
        $headOut = git rev-parse --verify -q HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $headOut) { $currentCommit = "$headOut".Trim() }

        if (-not $currentCommit) {
            Write-Host "Repo chua co commit nao, bo qua phat hien file xoa." -ForegroundColor Yellow
        } else {
            $lastCommit = $null
            if (Test-Path -LiteralPath $StateFilePath) {
                $lastCommit = "$(Get-Content -LiteralPath $StateFilePath -Raw)".Trim()
            }

            $lastCommitValid = $false
            if ($lastCommit -match '^[0-9a-fA-F]{7,64}$') {
                $objType = git cat-file -t $lastCommit 2>$null
                $lastCommitValid = ($LASTEXITCODE -eq 0 -and "$objType".Trim() -eq 'commit')
            }

            $gitOutput = $null
            if ($lastCommitValid) {
                # quotepath=false: giu nguyen ten file co dau tieng Viet (khong bi escape thanh \303\240...)
                $gitOutput = git -c core.quotepath=false diff --diff-filter=DR --name-status $lastCommit $currentCommit 2>$null
            } else {
                Write-Host "Khong tim thay commit dong goi lan truoc, chi so sanh voi 1 commit gan nhat." -ForegroundColor Yellow
                git rev-parse --verify -q "HEAD~1" 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $gitOutput = git -c core.quotepath=false diff --diff-filter=DR --name-status HEAD~1 HEAD 2>$null
                }
            }

            if ($gitOutput) {
                foreach ($line in ($gitOutput -split "`r?`n" | Where-Object { $_ -match '\S' })) {
                    $parts = $line -split "`t"
                    $status = $parts[0]
                    # D: parts[1] = path da xoa. R: parts[1] = path cu (khong con ton tai), parts[2] = path moi
                    if (($status -like "D*" -or $status -like "R*") -and $parts.Count -ge 2) {
                        $deletedFiles += $parts[1]
                    }
                }
            }

            # Chi giu file thuc su KHONG nam trong goi:
            #  - bo file trong thu muc da exclude (chua tung len server)
            #  - bo file bi loai theo ten (appsettings*, .env...) de khong xoa config rieng cua server
            #  - bo file van con trong goi (vd: doi ten chi khac hoa/thuong, git rm --cached)
            $deletedFiles = @($deletedFiles | Where-Object {
                (-not (Test-ExcludedPath $_)) -and
                (-not (Test-ExcludedFileName $_)) -and
                (-not (Test-Path -LiteralPath (Join-Path $TempDir ($_ -replace '/', '\'))))
            })
        }
    } catch {
        Write-Host "Loi khi doc lich su Git: $_" -ForegroundColor Red
    } finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "Cac file bi xoa/doi ten duoc phat hien tu Git:" -ForegroundColor Yellow
if ($deletedFiles.Count -gt 0) {
    foreach ($df in $deletedFiles) {
        Write-Host "  - $df" -ForegroundColor Yellow
    }
} else {
    Write-Host "  (Khong phat hien file xoa tu dong)" -ForegroundColor Gray
}

$manualFiles = Read-Host "Nhap them file can xoa tren server (duong dan tuong doi, cach nhau boi dau phay, hoac Enter de bo qua)"
if (-not [string]::IsNullOrWhiteSpace($manualFiles)) {
    $manualList = $manualFiles.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    foreach ($mf in $manualList) {
        if (Test-SafeRelativePath $mf) {
            $deletedFiles += $mf
        } else {
            Write-Host "  Bo qua duong dan khong an toan: $mf (chi nhan duong dan tuong doi, khong co .., ., *, ?)" -ForegroundColor Red
        }
    }
}

if ($deletedFiles.Count -gt 0) {
    $deletedFiles = @($deletedFiles | Sort-Object -Unique)

    $txtPath = Join-Path $TempDir "deleted_files.txt"
    $deletedFiles | Out-File -LiteralPath $txtPath -Encoding utf8

    $ps1Path = Join-Path $TempDir "cleanup_old_files.ps1"
    # Chuoi nhay don: '$' trong ten file khong bi PowerShell noi suy; nhan doi moi loai dau nhay don (ke ca nhay cong) de thoat
    $listBody = ($deletedFiles | ForEach-Object { "    '" + ($_ -replace "[‘’‚‛']", '$0$0') + "'" }) -join ",`r`n"
    $ps1Content = @"
# Script tu dong xoa cac file cu khong con dung sau khi giai nen
# Chi xoa FILE (khong xoa de quy) nam ben trong thu muc chua script nay.
`$filesToDelete = @(
$listBody
)
`$root = [System.IO.Path]::GetFullPath(`$PSScriptRoot).TrimEnd('\')
Write-Host "Dang quet va xoa cac file cu tren server..." -ForegroundColor Cyan
foreach (`$relPath in `$filesToDelete) {
    `$fullPath = [System.IO.Path]::GetFullPath((Join-Path `$root `$relPath))
    if (-not `$fullPath.StartsWith(`$root + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "Bo qua (nam ngoai thu muc): `$relPath" -ForegroundColor Red
        continue
    }
    if (Test-Path -LiteralPath `$fullPath -PathType Leaf) {
        Remove-Item -LiteralPath `$fullPath -Force
        Write-Host "Da xoa: `$relPath" -ForegroundColor Yellow
    } else {
        Write-Host "Khong tim thay (co the da xoa truoc do): `$relPath" -ForegroundColor Gray
    }
}
Write-Host "Hoan tat don dep file cu!" -ForegroundColor Green
Pause
"@
    # UTF8 co BOM de Windows PowerShell 5.1 doc dung duong dan co dau tieng Viet
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($ps1Path, $ps1Content, $utf8Bom)
    Write-Host "Da tao cleanup_old_files.ps1 va deleted_files.txt vao goi ZIP!" -ForegroundColor Green
}
# ==============================================================================

Write-Host "Compressing to ZIP..." -ForegroundColor Cyan
$zipOk = $false
$expectedFiles = @(Get-ChildItem -LiteralPath $TempDir -Recurse -File -Force).Count
try {
    # Tu tao ZIP bang ZipArchive: ten entry dung '/' (CreateFromDirectory tren PS 5.1 ghi '\' lam hong tren Linux),
    # ten file UTF-8 (co dau tieng Viet). Chi them FILE, khong them entry thu muc rong.
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $baseLen = $TempDir.TrimEnd('\').Length + 1
    $fs = [System.IO.File]::Open($ZipFilePath, [System.IO.FileMode]::Create)
    $archive = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create, $false, (New-Object System.Text.UTF8Encoding($false)))
    try {
        Get-ChildItem -LiteralPath $TempDir -Recurse -File -Force | ForEach-Object {
            $entryName = $_.FullName.Substring($baseLen).Replace('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $_.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally {
        $archive.Dispose()
        $fs.Dispose()
    }
    $zipOk = Test-Path -LiteralPath $ZipFilePath
} catch {
    Write-Host "Tao ZIP loi: $_" -ForegroundColor Red
    Remove-Item -LiteralPath $ZipFilePath -Force -ErrorAction SilentlyContinue
}

# Doi chieu so entry trong ZIP voi so file da copy, va khong cho phep '\' trong ten entry
if ($zipOk) {
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipFilePath)
        $entryCount = @($zip.Entries | Where-Object { $_.FullName -notmatch '[\\/]$' }).Count
        $badNames = @($zip.Entries | Where-Object { $_.FullName.Contains('\') }).Count
        $zip.Dispose()
        if ($badNames -gt 0) {
            Write-Host "CANH BAO: $badNames entry co dau '\' trong ten." -ForegroundColor Red
            $zipOk = $false
        }
        if ($entryCount -ne $expectedFiles) {
            Write-Host "CANH BAO: ZIP co $entryCount file nhung thu muc tam co $expectedFiles file." -ForegroundColor Red
            $zipOk = $false
        }
    } catch {
        Write-Host "Khong doc lai duoc ZIP de kiem tra: $_" -ForegroundColor Red
        $zipOk = $false
    }
}

Write-Host "Cleaning up temporary directory..." -ForegroundColor Cyan
Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue

if ($zipOk) {
    # Chi ghi moc commit khi dong goi thanh cong va da kiem tra
    if ($currentCommit) {
        [System.IO.File]::WriteAllText($StateFilePath, $currentCommit, [System.Text.Encoding]::ASCII)
    }
    Write-Host "------------------------------------------------" -ForegroundColor Green
    Write-Host "SUCCESS! Source code has been safely packaged." -ForegroundColor Green
    Write-Host "ZIP file location: $ZipFilePath" -ForegroundColor Green
    Write-Host "------------------------------------------------" -ForegroundColor Green
} else {
    Write-Host "FAILED: ZIP khong hop le. Moc commit chua duoc cap nhat." -ForegroundColor Red
    Remove-Item -LiteralPath $ZipFilePath -Force -ErrorAction SilentlyContinue
    exit 1
}
Pause
