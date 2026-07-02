param (
    # Removed Mandatory to allow script to proceed to prompt
    [string]$FilePath = ""
)

# Clear the screen for a clean output
Clear-Host

# PRINT HEADER UPON OPENING
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "       METADATA READER (EXIFTOOL)        " -ForegroundColor Green
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
    Write-Host " READING METADATA FOR FILE: " -NoNewline -ForegroundColor Cyan
    Write-Host $FilePath -ForegroundColor Yellow
    Write-Host "-----------------------------------------" -ForegroundColor Cyan
    
    # Call exiftool to read metadata
    exiftool $FilePath
    
    Write-Host "-----------------------------------------" -ForegroundColor Cyan
    Write-Host " Reading process completed." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Error: File not found at path '$FilePath'. Please check again." -ForegroundColor Red
}

Write-Host ""
# Keep window open to read information
Read-Host -Prompt "Press Enter to exit"