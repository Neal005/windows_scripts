# =============================================================================
# claude-review-folder.ps1
# Run this script (double-click or "Run with PowerShell"), then drag and
# drop a folder into the open console window when prompted - Windows will
# auto-type the full path for you. Opens an interactive Claude Code session
# inside that folder with an initial review prompt pre-sent.
#
# Usage:
#   Just run the script - it will ask you to drag/drop the folder.
#   Optional pre-fill: .\claude-review-folder.ps1 -TargetFolder "F:\path"
# =============================================================================

param(
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$TargetFolder = "",

    [Parameter(Mandatory = $false)]
    [string]$Prompt = "",

    [switch]$Headless
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Err($msg)  { Write-Host "  [ERROR] $msg" -ForegroundColor Red }
function Write-Warn($msg) { Write-Host "  [WARNING] $msg" -ForegroundColor Yellow }

Write-Step "=== Claude Code Folder Review ==="
Write-Host ""

# -----------------------------------------------------------------------
# 1. Get the target folder - either from -TargetFolder param, or by
#    prompting the user to drag-and-drop it into this console window
# -----------------------------------------------------------------------
Write-Step "[1/4] Getting target folder..."

if ([string]::IsNullOrWhiteSpace($TargetFolder)) {
    $TargetFolder = Read-Host "Drag and drop the folder to review here (then press Enter)"
}

# Dragging a folder into the console wraps the path in quotes and may add
# a trailing space - strip both before validating
$TargetFolder = $TargetFolder.Trim().Trim('"').Trim("'")

if (-not (Test-Path -LiteralPath $TargetFolder -PathType Container)) {
    Write-Err "Not a valid folder: $TargetFolder"
    Write-Host ""
    Write-Host "Press Enter to exit..."
    Read-Host | Out-Null
    exit 1
}
$TargetFolder = (Resolve-Path -LiteralPath $TargetFolder).Path
Write-Ok "Target: $TargetFolder"

# -----------------------------------------------------------------------
# 2. Check Claude Code CLI is available
# -----------------------------------------------------------------------
Write-Step "[2/4] Checking Claude Code CLI..."
try {
    $claudeVersion = claude --version
    Write-Ok "Claude Code $claudeVersion"
} catch {
    Write-Err "Claude Code CLI not found. Install it first (native installer, see plan doc)."
    Write-Host ""
    Write-Host "Press Enter to close..."
    Read-Host | Out-Null
    exit 1
}

# -----------------------------------------------------------------------
# 3. Report basic folder info (git repo or not - purely informational)
# -----------------------------------------------------------------------
Write-Step "[3/4] Inspecting folder..."
Push-Location -LiteralPath $TargetFolder
try {
    $isGitRepo = $false
    try {
        $null = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0) { $isGitRepo = $true }
    } catch { $isGitRepo = $false }

    if ($isGitRepo) {
        $remote = (git remote -v 2>$null | Select-Object -First 1)
        $branch = (git branch --show-current 2>$null)
        Write-Ok "Git repo detected - branch: $branch"
        if ($remote) { Write-Ok "Remote: $remote" }
    } else {
        Write-Warn "Not a git repo (or git not available) - proceeding anyway, no diff/history context."
    }
} finally {
    Pop-Location
}

# -----------------------------------------------------------------------
# 4. Build the review prompt and launch Claude Code in the target folder
# -----------------------------------------------------------------------
Write-Step "[4/4] Starting Claude Code session..."

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    $Prompt = @"
Hay xem xet tong quan thu muc nay (khong sua/tao/xoa file, chi doc va nhan xet):
1. Cau truc thu muc, cong nghe/framework dang dung.
2. Nhung diem dang chu y: code smell, thieu test, TODO/FIXME con sot, dependency loi thoi hoac co lo hong bao mat da biet, config/secret bi lo trong repo.
3. Danh gia tong quan chat luong code (muc do de bao tri, do nhat quan style).
4. Neu thay dieu gi kho hieu hoac can doc them file cu the de danh gia chinh xac hon, hay tu doc (qua Bash/Read/Grep) truoc khi ket luan, khong doan.

Tra loi ngan gon, co cau truc ro rang theo tung muc tren.
"@
}

Write-Host ""
Write-Host "Folder : $TargetFolder" -ForegroundColor DarkGray
Write-Host "Mode   : $(if ($Headless) { 'Headless (one-shot, non-interactive)' } else { 'Interactive session' })" -ForegroundColor DarkGray
Write-Host ""

Set-Location -LiteralPath $TargetFolder

if ($Headless) {
    # One-shot: prints the review and exits, no follow-up chat
    claude -p $Prompt
} else {
    # Interactive: sends the prompt as the first message, then stays open
    # for follow-up questions
    claude $Prompt
}