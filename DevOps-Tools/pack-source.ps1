param(
    [Parameter(Position=0)]
    [string]$TargetFolder
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($TargetFolder)) {
    $TargetFolder = Read-Host "Please enter (or drag and drop) the directory path to pack"
}

# Remove quotes if they exist due to terminal drag and drop
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

# Output ZIP file to the same level as the packed folder
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

& robocopy $robocopyArgs | Out-Null

Write-Host "Compressing to ZIP..." -ForegroundColor Cyan
Compress-Archive -Path "$TempDir\*" -DestinationPath $ZipFilePath -Force

Write-Host "Cleaning up temporary directory..." -ForegroundColor Cyan
Remove-Item -Path $TempDir -Recurse -Force

Write-Host "------------------------------------------------" -ForegroundColor Green
Write-Host "SUCCESS! Source code has been safely packaged." -ForegroundColor Green
Write-Host "ZIP file location: $ZipFilePath" -ForegroundColor Green
Write-Host "------------------------------------------------" -ForegroundColor Green

Pause
