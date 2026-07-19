<#
.SYNOPSIS
Continuous interactive script to clean up build directories.
Safer version: confirms before deleting, sends items to Recycle Bin,
avoids recursing into already-matched folders, and protects source code (\src\).
#>

Add-Type -AssemblyName Microsoft.VisualBasic

$TargetFolders = @("build", "bin", "obj", "target", "node_modules", "dist")

function Remove-ItemToRecycleBin {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $Path,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $Path,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    }
}

function Get-FolderSize {
    param([string]$Path)
    try {
        $bytes = (Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum
        if (-not $bytes) { return 0 }
        return $bytes
    } catch {
        return 0
    }
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# Recursively find target folders WITHOUT descending into ones already matched
function Find-TargetFolders {
    param([string]$Root)

    $results = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Root)

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()

        $children = $null
        try {
            $children = Get-ChildItem -LiteralPath $current -Directory -Force -ErrorAction Stop
        } catch {
            continue
        }

        foreach ($child in $children) {
            # Skip all directories begin with "."
            if ($child.Name.StartsWith(".")) { continue }

            # SAFEGUARD: Check if the folder is inside a "src" directory
            # [\\/] matches either \ (Windows) or / (Linux/Mac)
            $isInsideSourceCode = $child.FullName -match "[\\/]src[\\/]"

            if (($TargetFolders -contains $child.Name.ToLower()) -and (-not $isInsideSourceCode)) {
                $results.Add($child.FullName)
                # Do NOT push this folder's children to avoid recursing inside it
            } else {
                $stack.Push($child.FullName)
            }
        }
    }
    return $results
}

while ($true) {
    Clear-Host
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "             BUILD DIRECTORY CLEANER             " -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host ""

    $RootPath = Read-Host "Enter the path to scan (or 'e' / 'exit' to quit)"

    # Remove "" auto generate when drag folder in to terminal
    $RootPath = $RootPath.Replace('"', '').Replace("'", "")

    if ($RootPath -match "^(e|exit)$") {
        Write-Host "Exiting program. Have a great day, boss!" -ForegroundColor Yellow
        exit
    }
    if (-not (Test-Path -LiteralPath $RootPath)) {
        Write-Host "Path does not exist! Please check again." -ForegroundColor Red
        Start-Sleep -Seconds 2
        continue
    }
    Write-Host "`nRecursively scanning subdirectories... Please wait!" -ForegroundColor Yellow

    $FoundPaths = Find-TargetFolders -Root $RootPath
    $FoundDirs = @()
    $idx = 0
    foreach ($p in $FoundPaths) {
        $FoundDirs += [PSCustomObject]@{
            Index   = $idx
            Path    = $p
            Cleaned = $false
        }
        $idx++
    }

    if ($FoundDirs.Count -eq 0) {
        Write-Host "This directory is clean, no build folders found." -ForegroundColor Green
        Start-Sleep -Seconds 2
        continue
    }

    while ($true) {
        Clear-Host
        Write-Host "Current path: $RootPath" -ForegroundColor Cyan
        Write-Host "List of found build directories:`n"

        foreach ($Item in $FoundDirs) {
            if ($Item.Cleaned) {
                Write-Host "[$($Item.Index)] $($Item.Path) (Cleaned)" -ForegroundColor DarkGray
            } else {
                Write-Host "[$($Item.Index)] $($Item.Path)" -ForegroundColor Green
            }
        }
        Write-Host "`n-------------------------------------------------"
        Write-Host "Available commands:"
        Write-Host "- Enter numbers (e.g., 0, 1, 2) to delete."
        Write-Host "- Enter 'all' to delete all uncleaned directories."
        Write-Host "- Enter 'b' to go back and choose another root path."
        Write-Host "- Enter 'e' or 'exit' to quit completely."
        $Choice = Read-Host "`nYour choice, boss"
        
        if ($Choice -match "^(e|exit)$") { exit }
        if ($Choice -eq 'b') { break }

        $ToDelete = @()
        if ($Choice -eq 'all') {
            $ToDelete = $FoundDirs | Where-Object { -not $_.Cleaned }
        } else {
            $Indices = $Choice -split ',' | ForEach-Object { $_.Trim() }
            foreach ($Idx in $Indices) {
                if ($Idx -match "^\d+$") {
                    $i = [int]$Idx
                    if ($i -ge 0 -and $i -lt $FoundDirs.Count -and -not $FoundDirs[$i].Cleaned) {
                        $ToDelete += $FoundDirs[$i]
                    }
                }
            }
        }

        if ($ToDelete.Count -eq 0) {
            Write-Host "Invalid choice or directory already cleaned!" -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }

        # --- Confirmation step with size preview ---
        Write-Host "`nCalculating size, please wait..." -ForegroundColor Yellow
        $totalBytes = 0
        foreach ($Item in $ToDelete) {
            $size = Get-FolderSize -Path $Item.Path
            $totalBytes += $size
            Write-Host (" - {0}  [{1}]" -f $Item.Path, (Format-Size $size))
        }
        Write-Host ("`nTotal: {0} folder(s), approx. {1}" -f $ToDelete.Count, (Format-Size $totalBytes)) -ForegroundColor Cyan
        Write-Host "Items will be sent to the Recycle Bin (recoverable)." -ForegroundColor Yellow
        $Confirm = Read-Host "Proceed with deletion? (y/n)"
        if ($Confirm -notmatch "^(y|yes)$") {
            Write-Host "Cancelled." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            continue
        }

        foreach ($Item in $ToDelete) {
            try {
                if (Test-Path -LiteralPath $Item.Path) {
                    Remove-ItemToRecycleBin -Path $Item.Path
                }
                $Item.Cleaned = $true
            } catch {
                Write-Host "Error deleting $($Item.Path): $_" -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    }
}