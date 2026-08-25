# =============================================================================
# claude-run-review.ps1
# Runs a single headless Claude Code review call, with the working directory
# correctly set BEFORE Claude starts - avoiding the "changes directory before
# running git" approval wall that blocks cd/git -C inside the Bash tool.
#
# Antigravity should call this script (not construct the pipe manually)
# every time it needs to trigger claude-review-plan or claude-review-code.
#
# Usage:
#   .\claude-run-review.ps1 -RepoPath "F:\VScode\MKDC-IoT\ocr_ui" -PromptFile "C:\path\to\prompt.txt"
# =============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,

    [Parameter(Mandatory = $true)]
    [string]$PromptFile
)

$ErrorActionPreference = "Stop"

function Write-Err($msg)  { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }

# -----------------------------------------------------------------------
# 1. Validate inputs before touching anything
# -----------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    Write-Err "RepoPath not found or not a directory: $RepoPath"
    exit 1
}
if (-not (Test-Path -LiteralPath $PromptFile -PathType Leaf)) {
    Write-Err "PromptFile not found: $PromptFile"
    exit 1
}

$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path

# -----------------------------------------------------------------------
# 2. Confirm it is actually a git repo BEFORE launching Claude - fail fast
#    with a clear error instead of letting Claude discover it mid-review.
# -----------------------------------------------------------------------
Push-Location -LiteralPath $RepoPath
try {
    $topLevel = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($topLevel)) {
        Write-Err "Not a git repository (or git not available) at: $RepoPath"
        exit 1
    }
    Write-Ok "Confirmed git repo. Top level: $topLevel"

    # -------------------------------------------------------------------
    # 3. Run claude -p with the working directory ALREADY correct - no
    #    cd/-C needed inside the prompt, so no "changes directory before
    #    running git" approval wall is triggered.
    # -------------------------------------------------------------------
    Get-Content -LiteralPath $PromptFile -Raw -Encoding UTF8 | claude -c -p -
}
finally {
    Pop-Location
}