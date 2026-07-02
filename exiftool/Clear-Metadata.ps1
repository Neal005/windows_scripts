param (
    [string]$FilePath = ""
)

# Clear the screen for a clean output
Clear-Host

# PRINT HEADER UPON OPENING
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "      METADATA REMOVAL SCRIPT V1.0       " -ForegroundColor Red
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# If no path provided, prompt user to enter/drag-and-drop
if ([string]::IsNullOrWhiteSpace($FilePath)) {
    $FilePath = Read-Host "Please enter (or drag and drop) the file path here"
}

# Automatically remove quotes if drag-and-dropped
$FilePath = $FilePath.Trim('"', "'")

# Check if file exists
if (Test-Path $FilePath) {
    Write-Host ""
    Write-Host " REMOVING ALL METADATA FOR FILE: " -NoNewline -ForegroundColor Cyan
    Write-Host $FilePath -ForegroundColor Yellow
    Write-Host "-----------------------------------------" -ForegroundColor Cyan
    
    # Call exiftool to remove all metadata and overwrite the original file
    exiftool -all= -overwrite_original $FilePath
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Excellent! The file has been completely cleansed." -ForegroundColor Green
    } else {
        Write-Host "An error occurred during the ExifTool process." -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "Error: File not found at path '$FilePath'. Please check again." -ForegroundColor Red
}

Write-Host ""
# Keep window open to view results
Read-Host -Prompt "Press Enter to exit"