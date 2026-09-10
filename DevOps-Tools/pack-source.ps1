param(
    [Parameter(Position=0)]
    [string]$TargetFolder
)
$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($TargetFolder)) {
    $TargetFolder = Read-Host "Please enter (or drag and drop) the directory path to pack"
}
$TargetFolder = $TargetFolder.Trim('"').Trim("'")
if (-not (Test-Path $TargetFolder -PathType Container)) {
    Write-Host "Directory does not exist or is invalid: $TargetFolder" -ForegroundColor Red
    Pause
    exit
}

$ProjectDir = (Get-Item $TargetFolder).FullName
$ProjectName = (Split-Path $ProjectDir -Leaf)
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ZipFileName = "${ProjectName}_SourceCode_Update_${Timestamp}.zip"

$ParentDir = (Get-Item $ProjectDir).Parent
if ($ParentDir) {
    $ZipFilePath = Join-Path $ParentDir.FullName $ZipFileName
} else {
    $ZipFilePath = Join-Path $ProjectDir $ZipFileName
}

$TempDir = Join-Path $env:TEMP "${ProjectName}_Pack_${Timestamp}"
Write-Host "Creating temporary directory at: $TempDir" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

$ExcludedDirs = @(
    "bin", "obj", "node_modules", ".git", ".vscode", ".vs", "Agent", "App_Data", "dist", "admin-app"
)
$ExcludedFiles = @(
    "appsettings*.json", ".env", ".env.*", "launchSettings.json", "*.zip"
)

Write-Host "Copying source code (automatically excluding Config and junk files)..." -ForegroundColor Cyan
$robocopyArgs = @(
    $ProjectDir,
    $TempDir,
    "/MIR",
    "/R:0",
    "/W:0",
    "/NFL",
    "/NDL",
    "/NJH",
    "/NJS",
    "/XD"
) + $ExcludedDirs + @("/XF") + $ExcludedFiles
& robocopy @robocopyArgs | Out-Null
# Robocopy exit codes 0-7 are success/no-error variants; 8+ means real errors occurred
if ($LASTEXITCODE -ge 8) {
    Write-Host "WARNING: robocopy reported errors (exit code $LASTEXITCODE). Check permissions or path length." -ForegroundColor Red
    Pause
}

# ==============================================================================
# PHAN MO RONG: TU DONG TIM FILE DA BI XOA VA TAO SCRIPT CLEANUP
# ==============================================================================
$deletedFiles = @()
$StateFilePath = Join-Path $ProjectDir ".last_pack_commit"

if (Test-Path (Join-Path $ProjectDir ".git")) {
    Push-Location $ProjectDir
    try {
        $currentCommit = git rev-parse HEAD 2>$null

        if (Test-Path $StateFilePath) {
            $lastCommit = (Get-Content $StateFilePath -Raw).Trim()
        } else {
            $lastCommit = $null
        }

        if ($lastCommit -and (git cat-file -e "$lastCommit^{commit}" 2>$null; $LASTEXITCODE -eq 0)) {
            # So sanh tu lan dong goi truoc den commit hien tai (bat het moi commit da trôi qua,
            # khong chi 1 commit gan nhat). Bao gom ca Deleted va Renamed (old path can duoc xoa tren server).
            $gitOutput = git diff --diff-filter=DR --name-status "$lastCommit" "$currentCommit" 2>$null
        } else {
            Write-Host "Khong tim thay commit dong goi lan truoc, chi so sanh voi 1 commit gan nhat." -ForegroundColor Yellow
            $gitOutput = git diff --diff-filter=DR --name-status HEAD~1 HEAD 2>$null
        }

        if ($gitOutput) {
            foreach ($line in ($gitOutput -split "`r?`n" | Where-Object { $_ -match '\S' })) {
                $parts = $line -split "`t"
                $status = $parts[0]
                if ($status -like "D*") {
                    $deletedFiles += $parts[1]
                } elseif ($status -like "R*") {
                    # Renamed: parts[1] = old path (no longer exists), parts[2] = new path
                    $deletedFiles += $parts[1]
                }
            }
        }

        # Loc bo cac file nam trong thu muc da bi exclude (chua tung duoc dong goi len server)
        $excludedPattern = ($ExcludedDirs | ForEach-Object { [regex]::Escape($_) }) -join "|"
        if ($excludedPattern) {
            $deletedFiles = $deletedFiles | Where-Object { $_ -notmatch "(^|[\\/])($excludedPattern)([\\/]|$)" }
        }

        git rev-parse HEAD 2>$null | Out-File -FilePath $StateFilePath -Encoding ascii -NoNewline
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

$manualFiles = Read-Host "Nhap them file can xoa tren server (cach nhau boi dau phay, hoac Enter de bo qua)"
if (-not [string]::IsNullOrWhiteSpace($manualFiles)) {
    $manualList = $manualFiles.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    $deletedFiles += $manualList
}

if ($deletedFiles.Count -gt 0) {
    $deletedFiles = $deletedFiles | Select-Object -Unique

    $txtPath = Join-Path $TempDir "deleted_files.txt"
    $deletedFiles | Out-File -FilePath $txtPath -Encoding utf8

    $ps1Path = Join-Path $TempDir "cleanup_old_files.ps1"
    $ps1Content = @"
# Script tu dong xoa cac file cu khong con dung sau khi giai nen
`$filesToDelete = @(
$( ($deletedFiles | ForEach-Object { "    `"$_`"" }) -join ",`r`n" )
)
`$currentDir = `$PSScriptRoot
Write-Host "Dang quet va xoa cac file cu tren server..." -ForegroundColor Cyan
foreach (`$relPath in `$filesToDelete) {
    `$fullPath = Join-Path `$currentDir `$relPath
    if (Test-Path `$fullPath) {
        Remove-Item -Path `$fullPath -Force -Recurse
        Write-Host "Da xoa: `$relPath" -ForegroundColor Yellow
    } else {
        Write-Host "Khong tim thay (co the da xoa truoc do): `$relPath" -ForegroundColor Gray
    }
}
Write-Host "Hoan tat don dep file cu!" -ForegroundColor Green
Pause
"@
    # UTF8 (no BOM) de giu dung duong dan co dau tieng Viet, thay vi ASCII
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ps1Path, $ps1Content, $utf8NoBom)
    Write-Host "Da tao cleanup_old_files.ps1 va deleted_files.txt vao goi ZIP!" -ForegroundColor Green
}
# ==============================================================================

Write-Host "Compressing to ZIP..." -ForegroundColor Cyan
Compress-Archive -Path "$TempDir\*" -DestinationPath $ZipFilePath -Force

Write-Host "Cleaning up temporary directory..." -ForegroundColor Cyan
Remove-Item -Path $TempDir -Recurse -Force

Write-Host "------------------------------------------------" -ForegroundColor Green
Write-Host "SUCCESS! Source code has been safely packaged." -ForegroundColor Green
Write-Host "ZIP file location: $ZipFilePath" -ForegroundColor Green
Write-Host "------------------------------------------------" -ForegroundColor Green
Pause