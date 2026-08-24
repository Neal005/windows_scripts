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

# -----------------------------------------------------------------------
# Auth helpers - detect an expired/missing Claude Code login before
# doing any real work, so failures show up here instead of mid-task.
# -----------------------------------------------------------------------
function Test-ClaudeAuth {
    try {
        $statusOutput = claude auth status 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) { return $false }
        if ($statusOutput -match "not logged in|not authenticated|no credentials|please run /login|expired") {
            return $false
        }
        return $true
    } catch {
        return $false
    }
}

function Assert-ClaudeAuth {
    if (Test-ClaudeAuth) { return }

    Write-Err "Bạn chưa đăng nhập! Đăng nhập hoặc thoát"
    $choice = Read-Host "Nhấn 'L' để đăng nhập (claude auth login), hoặc phím bất kỳ khác để thoát"
    if ($choice -notmatch '^[Ll]') {
        exit 1
    }

    claude auth login

    if (-not (Test-ClaudeAuth)) {
        Write-Err "Đăng nhập không thành công. Thoát script."
        exit 1
    }
    Write-Ok "Đăng nhập thành công."
}

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

Assert-ClaudeAuth

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
# 4. Launch Claude Code in the target folder (no auto-prompt by default -
#    you decide what to ask once the session opens)
# -----------------------------------------------------------------------
Write-Step "[4/4] Starting Claude Code session..."

Write-Host ""
Write-Host "Folder : $TargetFolder" -ForegroundColor DarkGray
Write-Host "Mode   : $(if ($Headless) { 'Headless (one-shot, non-interactive)' } else { 'Interactive session' })" -ForegroundColor DarkGray
if (-not [string]::IsNullOrWhiteSpace($Prompt)) {
    Write-Host "Prompt : (custom prompt provided, will be sent as first message)" -ForegroundColor DarkGray
}
Write-Host ""

Set-Location -LiteralPath $TargetFolder

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    # No prompt given - just open cd'd into the folder, blank session,
    # you type the first message yourself
    claude
} elseif ($Headless) {
    # One-shot: prints the response and exits, no follow-up chat
    claude -p $Prompt
} else {
    # Interactive: sends the given prompt as the first message, then
    # stays open for follow-up questions
    claude $Prompt
}