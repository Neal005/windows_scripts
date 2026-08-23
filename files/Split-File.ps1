Clear-Host
Write-Host "=== SCRIPT: SPLIT FILE INTO N EQUAL PARTS ===" -ForegroundColor Cyan

# 1. Input file (Drag & Drop)
Write-Host "Step 1: Select the target file" -ForegroundColor Yellow
Write-Host "Hint: Drag and drop the file into this window, then press Enter" -ForegroundColor DarkGray
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

$sourceFile = Get-Item -LiteralPath $filePath
Write-Host "=> File found: $($sourceFile.Name) ($([Math]::Round($sourceFile.Length / 1MB, 2)) MB)" -ForegroundColor Magenta
Write-Host "------------------------------------------------"

# 2. Number of parts
Write-Host "Step 2: Enter the number of equal parts" -ForegroundColor Yellow
$partsInput = Read-Host "How many parts do you want to split this file into"

$totalParts = 0
if (-not [int]::TryParse($partsInput, [ref]$totalParts) -or $totalParts -le 1) {
    Write-Host "Error: Please enter a valid integer greater than 1!" -ForegroundColor Red
    Read-Host
    exit
}

Write-Host "=> Splitting into $totalParts parts..." -ForegroundColor Magenta
Write-Host "------------------------------------------------"

# 3. Calculate chunk sizes with strict remainder handling
$totalSize = $sourceFile.Length
$baseChunkSize = [Math]::Floor($totalSize / $totalParts)
$remainder = $totalSize - ($baseChunkSize * $totalParts)

if ($baseChunkSize -eq 0) {
    Write-Host "Error: File is too small to split into $totalParts parts!" -ForegroundColor Red
    Read-Host
    exit
}

# Padding width based on total number of parts (e.g. 12 -> 2 digits, 120 -> 3 digits)
$padWidth = ([string]$totalParts).Length
$outputDir = $sourceFile.DirectoryName
$baseName = $sourceFile.Name

# 4. Binary split using FileStream (memory-efficient, buffered copy)
$bufferSize = 4MB
$buffer = New-Object byte[] $bufferSize
$outputFiles = @()

$sourceStream = $null
try {
    $sourceStream = New-Object System.IO.FileStream($sourceFile.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)

    for ($i = 1; $i -le $totalParts; $i++) {
        # Last part absorbs the remainder to guarantee zero data loss
        $bytesForThisPart = $baseChunkSize
        if ($i -eq $totalParts) {
            $bytesForThisPart += $remainder
        }

        $suffix = ".part" + $i.ToString().PadLeft($padWidth, '0')
        $outputPath = Join-Path -Path $outputDir -ChildPath ($baseName + $suffix)

        $destStream = $null
        try {
            $destStream = New-Object System.IO.FileStream($outputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)

            $remainingForPart = $bytesForThisPart
            while ($remainingForPart -gt 0) {
                $readSize = [Math]::Min($bufferSize, $remainingForPart)
                $bytesRead = $sourceStream.Read($buffer, 0, $readSize)
                if ($bytesRead -le 0) { break }
                $destStream.Write($buffer, 0, $bytesRead)
                $remainingForPart -= $bytesRead
            }
        }
        finally {
            if ($destStream) { $destStream.Dispose() }
        }

        $outputFiles += $outputPath
        Write-Host "=> Writing part $($i.ToString().PadLeft($padWidth,'0'))/$totalParts... Done ($([Math]::Round($bytesForThisPart / 1MB, 2)) MB)" -ForegroundColor DarkCyan
    }
}
catch {
    Write-Host "An error occurred while splitting the file:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host
    exit
}
finally {
    if ($sourceStream) { $sourceStream.Dispose() }
}

# 5. Verify and report results
Write-Host "------------------------------------------------"
$allExist = $true
foreach ($f in $outputFiles) {
    if (-not (Test-Path -LiteralPath $f)) { $allExist = $false }
}

if ($allExist) {
    Write-Host "SUCCESS! The file has been split into $totalParts parts:" -ForegroundColor Green
    foreach ($f in $outputFiles) {
        Write-Host $f -ForegroundColor Cyan
    }
} else {
    Write-Host "An error occurred! Some output parts were not created successfully." -ForegroundColor Red
}

Write-Host ""
Write-Host "Press Enter to exit..." -ForegroundColor Cyan
Read-Host