# Get the Desktop path for the current user
$desktopPath = [Environment]::GetFolderPath("Desktop")

Clear-Host
Write-Host "=== WINDOWS LOG EXTRACTOR ===" -ForegroundColor Cyan
Write-Host "1. System Log"
Write-Host "2. Application Log"
Write-Host "=============================" -ForegroundColor Cyan

# Prompt user to select log type
$choice = Read-Host "Select log type to extract (Enter 1 or 2)"

if ($choice -eq "1") {
    $logName = "System"
} elseif ($choice -eq "2") {
    $logName = "Application"
} else {
    Write-Host "Invalid selection! Exiting program..." -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit
}

# Prompt user to select the date to extract logs for
Write-Host ""
$dateInput = Read-Host "Enter the date (Format: dd/MM/yyyy, e.g., 23/04/2026). Press Enter for today"

if ([string]::IsNullOrWhiteSpace($dateInput)) {
    $startDate = (Get-Date).Date
} else {
    try {
        $startDate = [datetime]::ParseExact($dateInput, "dd/MM/yyyy", $null).Date
    } catch {
        Write-Host "Invalid date format! Defaulting to today's date." -ForegroundColor Yellow
        $startDate = (Get-Date).Date
    }
}

$endDate = $startDate.AddDays(1)

# Set file name and export path to Desktop (CSV format)
$dateString = $startDate.ToString("dd-MM-yyyy")
$fileName = "Log_$($logName)_$dateString.csv"
$exportPath = Join-Path -Path $desktopPath -ChildPath $fileName

Write-Host ""
Write-Host "Scanning $logName logs for $($startDate.ToString('dd/MM/yyyy'))..." -ForegroundColor Cyan

try {
    # Scan all logs within the selected time frame
    $events = Get-WinEvent -FilterHashtable @{LogName=$logName; StartTime=$startDate; EndTime=$endDate} -ErrorAction Stop
    
    # Format and export directly to CSV file
    $events | Select-Object TimeCreated, LevelDisplayName, Id, Message | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
    
    Write-Host "Success! The CSV log file has been saved to the Desktop at: $exportPath" -ForegroundColor Green
    
    # Automatically open the CSV file
    Invoke-Item $exportPath
} catch {
    Write-Host "No log data found for this date or the log file is currently locked." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Process completed! Press Enter to close the window..." -ForegroundColor Cyan
Read-Host