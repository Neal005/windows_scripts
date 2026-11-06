param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Path,
    [ValidateSet("mono", "accent")]
    [string]$Theme,
    [switch]$NoClobber
)
# Gen-Erd.ps1 - launcher: dan duong dan file ERD meta (vd erd_mau_02.meta.json) -> ra file .gen.drawio
# (vi tri bang va duong noi tu dong). Dau ra nam canh file meta, ten bo duoi ".meta" va them ".gen.drawio",
# VD erd_mau_02.meta.json -> erd_mau_02.gen.drawio (khong de len ban ve tay erd_mau_02.drawio).
# Chay khong tham so: dan duong dan file .meta.json (hoac thu muc chua cac *.meta.json), Enter; lap lai cho den khi de trong.
# Cong cu that nam o lib\Convert-ToDrawio.ps1 (goi python -B -m diagram_tool --kind erd).
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
    if ($NoClobber) { $extra["NoClobber"] = $true }
    & $converter -Path $Items -Kind erd -NoPause @extra
}

if ($Path -and $Path.Count -gt 0) {
    Invoke-Convert $Path
    $code = $LASTEXITCODE
    Pause
    exit $code
}

Write-Host "Gen draw.io - ERD (meta.json). Dan duong dan file .meta.json hoac thu muc roi Enter (de trong de thoat)." -ForegroundColor Cyan
while ($true) {
    $line = Read-Host "META JSON"
    if ([string]::IsNullOrWhiteSpace($line)) { break }
    Invoke-Convert @($line)
    Write-Host ""
}
