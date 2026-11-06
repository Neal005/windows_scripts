param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Path,
    [ValidateSet("mono", "accent")]
    [string]$Theme
)
# Gen-Raw.ps1 - launcher: dan duong dan JSON (kind "raw": khoi, bang, canh tu dat toa do) -> ra file .drawio.
# Chay khong tham so: dan duong dan file .json (hoac thu muc), Enter; lap lai cho den khi de trong.
# Co the keo tha file/thu muc vao script. Ket qua nam canh file JSON (cung ten, duoi .drawio).
# Cong cu that nam o lib\Convert-ToDrawio.ps1 (goi python -B -m diagram_tool --kind raw).
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$converter = Join-Path $PSScriptRoot "lib\Convert-ToDrawio.ps1"
if (-not (Test-Path -LiteralPath $converter)) {
    Write-Host "Khong thay $converter" -ForegroundColor Red
    Pause
    exit 1
}

function Invoke-Convert([string[]]$Items) {
    $extra = @{}
    if ($Theme) { $extra["Theme"] = $Theme }
    & $converter -Path $Items -Kind raw -NoPause @extra
}

if ($Path -and $Path.Count -gt 0) {
    Invoke-Convert $Path
    $code = $LASTEXITCODE
    Pause
    exit $code
}

Write-Host "Gen draw.io - kind raw. Dan duong dan file .json hoac thu muc roi Enter (de trong de thoat)." -ForegroundColor Cyan
while ($true) {
    $line = Read-Host "JSON"
    if ([string]::IsNullOrWhiteSpace($line)) { break }
    Invoke-Convert @($line)
    Write-Host ""
}
