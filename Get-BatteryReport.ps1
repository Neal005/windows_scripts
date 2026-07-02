# Get the Desktop path of the current user
$desktopPath = [Environment]::GetFolderPath("Desktop")

# Define the full path and report file name
$reportPath = Join-Path -Path $desktopPath -ChildPath "battery_report.html"

# Processing notification
Write-Host "Generating battery report..." -ForegroundColor Cyan

# Run powercfg command to output the report directly to the Desktop
powercfg /batteryreport /output $reportPath

# Check if the file was successfully created
if (Test-Path $reportPath) {
    Write-Host "Success! The report has been saved to: $reportPath" -ForegroundColor Green
    
    # Automatically open the report file using the default browser
    Invoke-Item $reportPath
} else {
    Write-Host "An error occurred. Unable to generate the battery report." -ForegroundColor Red
}