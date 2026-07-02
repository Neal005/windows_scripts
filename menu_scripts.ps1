$rootDir = $PSScriptRoot
$currentLocation = $rootDir

while ($true) {
    Clear-Host
    Write-Host "=== SCRIPTS MENU ===" -ForegroundColor Cyan
    Write-Host "Instructions:" -ForegroundColor White
    Write-Host "- Enter the corresponding [Number] to enter a directory or run a script." -ForegroundColor White
    Write-Host "- Enter [0] to return to the parent directory (if in a subdirectory)." -ForegroundColor White
    Write-Host "- Enter [e] or [exit] to quit the program." -ForegroundColor White
    Write-Host "--------------------"
    Write-Host "Current Location: $($currentLocation.Replace($rootDir, '\'))" -ForegroundColor Yellow
    Write-Host "--------------------"

    # Get the list of directories and ps1 files (excluding this menu file)
    $dirs = Get-ChildItem -Path $currentLocation -Directory
    $files = Get-ChildItem -Path $currentLocation -File -Filter "*.ps1" | Where-Object { $_.Name -ne $MyInvocation.MyCommand.Name }

    $menuMap = @{}
    $index = 1

    # Option 0 logic: Only display when in a subdirectory
    if ($currentLocation -ne $rootDir) {
        Write-Host " 0. [..] Return to Parent Directory" -ForegroundColor DarkGray
        $menuMap["0"] = "BACK"
    }

    # List directories
    foreach ($d in $dirs) {
        Write-Host " $index. [Dir] $($d.Name)" -ForegroundColor Blue
        $menuMap["$index"] = $d
        $index++
    }

    # List files
    foreach ($f in $files) {
        Write-Host " $index. [File] $($f.Name)" -ForegroundColor Green
        $menuMap["$index"] = $f
        $index++
    }

    Write-Host " e. Exit" -ForegroundColor Red
    Write-Host "--------------------"

    $choice = Read-Host "Select an option"

    # Process Logic
    if ($choice -match "^(e|exit)$") { break }

    if ($menuMap.ContainsKey($choice)) {
        $selected = $menuMap[$choice]
        
        if ($selected -eq "BACK") {
            # Go up one level
            $currentLocation = Split-Path $currentLocation -Parent
        } elseif ($selected -is [System.IO.DirectoryInfo]) {
            # Go into subdirectory
            $currentLocation = $selected.FullName
        } elseif ($selected -is [System.IO.FileInfo]) {
            # Run file
            Clear-Host
            Write-Host ">> Running: $($selected.Name)...`n" -ForegroundColor Magenta
            & $selected.FullName
            Read-Host "`n[Done] Press Enter to return to the menu..."
        }
    }
}