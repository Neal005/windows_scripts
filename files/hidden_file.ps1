# Prompt user for file paths (supports drag and drop into the console)
$imagePath = (Read-Host "Enter the path to the image file (File 1)").Trim('"').Trim("'")
$zipPath = (Read-Host "Enter the path to the zip file (File 2)").Trim('"').Trim("'")

# Verify file existence
if (!(Test-Path $imagePath -PathType Leaf)) {
    Write-Host "Error: The image file was not found at the specified path!" -ForegroundColor Red
    Pause
    exit
}

if (!(Test-Path $zipPath -PathType Leaf)) {
    Write-Host "Error: The zip file was not found at the specified path!" -ForegroundColor Red
    Pause
    exit
}

# Get the Desktop path
$desktopPath = [Environment]::GetFolderPath("Desktop")

# Extract original image filename details to create the new filename
$imageFile = Get-Item $imagePath
$outputFileName = $imageFile.BaseName + "_hidden" + $imageFile.Extension
$outputPath = Join-Path -Path $desktopPath -ChildPath $outputFileName

Write-Host "Merging files, please wait..." -ForegroundColor Cyan

# Execute copy /b command via cmd
cmd.exe /c copy /y /b `"$imagePath`" + `"$zipPath`" `"$outputPath`" > $null

# Check result and notify
if (Test-Path $outputPath) {
    Write-Host "`nSuccess! The file has been exported to the Desktop:" -ForegroundColor Green
    Write-Host "--> $outputPath" -ForegroundColor Yellow
} else {
    Write-Host "`nAn error occurred during the file merging process." -ForegroundColor Red
}

Write-Host "`n"
Pause