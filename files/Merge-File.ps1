Clear-Host
Write-Host "=== SCRIPT: MERGE FILE PARTS BACK TOGETHER ===" -ForegroundColor Cyan

# 1. Input one of the part files (Drag & Drop)
Write-Host "Step 1: Select ONE of the part files (e.g. file.zip.part01)" -ForegroundColor Yellow
Write-Host "Hint: Drag and drop any .partNN file into this window, then press Enter" -ForegroundColor DarkGray
$inputString = Read-Host "Please drag and drop the file here"

if ([string]::IsNullOrWhiteSpace($inputString)) {
    Write-Host "Error: No file was provided!" -ForegroundColor Red
    Read-Host
    exit
}

# Sanitize drag-and-drop input (strip surrounding quotes/spaces safely)
$regex = '(?:"([^"]+)")|(?:([^\s"]+))'
$match = [regex]::Match($inputString.Trim(), $regex)

$filePath = ""
if ($match.Groups[1].Value) {
    $filePath = $match.Groups[1].Value
} elseif ($match.Groups[2].Value) {
    $filePath = $match.Groups[2].Value
}

if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
    Write-Host "Error: File not found at the given path!" -ForegroundColor Red
    Write-Host $filePath -ForegroundColor DarkGray
    Read-Host
    exit
}

$selectedFile = Get-Item -LiteralPath $filePath

# 2. Detect the base name by stripping the trailing .partNNN suffix
if ($selectedFile.Name -notmatch '^(?<base>.+)\.part(?<num>\d+)$') {
    Write-Host "Error: The selected file does not look like a '.partNN' file!" -ForegroundColor Red
    Write-Host "Expected a name like: myfile.zip.part01" -ForegroundColor DarkGray
    Read-Host
    exit
}

$baseName = $Matches['base']
$outputDir = $selectedFile.DirectoryName

Write-Host "=> Detected base file name: $baseName" -ForegroundColor Magenta
Write-Host "------------------------------------------------"

# 3. Find and sort all matching part files
$partFiles = Get-ChildItem -LiteralPath $outputDir -Filter ($baseName + ".part*") |
    Where-Object { $_.Name -match '^' + [regex]::Escape($baseName) + '\.part\d+$' } |
    Sort-Object { [int]([regex]::Match($_.Name, '\.part(\d+)$').Groups[1].Value) }

if ($partFiles.Count -eq 0) {
    Write-Host "Error: No matching part files were found in the folder!" -ForegroundColor Red
    Read-Host
    exit
}

Write-Host "=> Found $($partFiles.Count) part(s):" -ForegroundColor Yellow
foreach ($p in $partFiles) {
    Write-Host "   $($p.Name) ($([Math]::Round($p.Length / 1MB, 2)) MB)" -ForegroundColor DarkCyan
}
Write-Host "------------------------------------------------"

# 4. Determine output path (avoid overwriting an existing file with the same name)
$outputPath = Join-Path -Path $outputDir -ChildPath $baseName
if (Test-Path -LiteralPath $outputPath) {
    $namePart = [System.IO.Path]::GetFileNameWithoutExtension($baseName)
    $extPart = [System.IO.Path]::GetExtension($baseName)
    $counter = 1
    do {
        $outputPath = Join-Path -Path $outputDir -ChildPath ("$namePart (merged $counter)$extPart")
        $counter++
    } while (Test-Path -LiteralPath $outputPath)
    Write-Host "Note: '$baseName' already exists. Output will be saved as:" -ForegroundColor Yellow
    Write-Host "      $outputPath" -ForegroundColor Yellow
    Write-Host "------------------------------------------------"
}

# 5. Merge using FileStream (memory-efficient, buffered copy)
$bufferSize = 4MB
$buffer = New-Object byte[] $bufferSize
$expectedTotalSize = ($partFiles | Measure-Object -Property Length -Sum).Sum

$destStream = $null
try {
    $destStream = New-Object System.IO.FileStream($outputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)

    $i = 0
    foreach ($part in $partFiles) {
        $i++
        $sourceStream = $null
        try {
            $sourceStream = New-Object System.IO.FileStream($part.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
            while ($true) {
                $bytesRead = $sourceStream.Read($buffer, 0, $bufferSize)
                if ($bytesRead -le 0) { break }
                $destStream.Write($buffer, 0, $bytesRead)
            }
        }
        finally {
            if ($sourceStream) { $sourceStream.Dispose() }
        }
        Write-Host "=> Merging part $i/$($partFiles.Count)... Done ($($part.Name))" -ForegroundColor DarkCyan
    }
}
catch {
    Write-Host "An error occurred while merging the file:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host
    exit
}
finally {
    if ($destStream) { $destStream.Dispose() }
}

# 6. Verify result
Write-Host "------------------------------------------------"
$resultFile = Get-Item -LiteralPath $outputPath
if ($resultFile.Length -eq $expectedTotalSize) {
    Write-Host "SUCCESS! Parts have been merged into:" -ForegroundColor Green
    Write-Host $outputPath -ForegroundColor Cyan
    Write-Host "Total size: $([Math]::Round($resultFile.Length / 1MB, 2)) MB" -ForegroundColor Cyan
} else {
    Write-Host "Warning! Merged file size ($($resultFile.Length) bytes) does not match" -ForegroundColor Red
    Write-Host "the expected total size ($expectedTotalSize bytes). Please check the parts." -ForegroundColor Red
}

Write-Host ""
Write-Host "Press Enter to exit..." -ForegroundColor Cyan
Read-Host