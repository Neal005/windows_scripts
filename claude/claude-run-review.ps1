# =============================================================================
# claude-run-review.ps1
# Runs a single headless Claude Code review call, with the working directory
# correctly set BEFORE Claude starts - avoiding the "changes directory before
# running git" approval wall that blocks cd/git -C inside the Bash tool.
#
# Antigravity should call this script (not construct the pipe manually)
# every time it needs to trigger claude-review-plan or claude-review-code.
#
# What this version adds:
#   - Per-repo Python: auto-detects the repo's venv (.venv / venv / env) and
#     puts it first on PATH, so the plain "python -m ..." allow rules in
#     settings.json run the RIGHT interpreter in every repo. Override with
#     -PythonEnv when the venv lives elsewhere.
#   - Tool caches (pycache, pytest, mypy, ruff) are redirected to %TEMP%, so
#     the review does not leave untracked files in the repo.
#   - Side-effect guard: compares `git status` before/after the review and
#     prints REVIEW_SIDE_EFFECT_DETECTED if the working tree changed.
#   - Per-task session: -SessionId (+ -NewSession on the first call) instead
#     of `-c`. Without -SessionId it falls back to `-c` (old behaviour).
#   - Model pinned via -Model (default "opus"), so a review never silently
#     runs on whatever model the settings or a resumed session had before.
#   - Reviewer permissions loaded from -ReviewerSettings (default
#     reviewer-settings.json next to this script) via --settings, so the
#     user-level settings.json can grant Claude PC write/commit rights.
#   - All environment changes are restored on exit, so the caller's
#     PowerShell session is not polluted.
#
# Usage:
#   First call of a task:
#     claude-run-review -RepoPath "F:\VScode\MKDC-IoT\ocr_ui" -PromptFile "C:\...\prompt.txt" -SessionId "<uuid>" -NewSession
#   Later calls of the same task:
#     claude-run-review -RepoPath "F:\VScode\MKDC-IoT\ocr_ui" -PromptFile "C:\...\prompt.txt" -SessionId "<uuid>"
#   Venv not in repo root / top level:
#     ... -PythonEnv "F:\VScode\MKDC-IoT\ocr_be\services\ocr\.venv"
#
# Exit codes: Claude's own exit code, or 3 if Claude succeeded but the
# working tree changed during the review.
# =============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,

    [Parameter(Mandatory = $true)]
    [string]$PromptFile,

    # UUID identifying the review session of ONE task.
    [string]$SessionId,

    # Create the session (first call of a task). Otherwise the session is resumed.
    [switch]$NewSession,

    # Optional: venv folder, its Scripts folder, or a python.exe path.
    [string]$PythonEnv,

    # Model for the review (alias or full ID). Passed as --model on every call,
    # so resumed sessions switch to it too.
    [string]$Model = "opus",

    # Reviewer permission set, passed as --settings. Its deny rules win over
    # any allow in the user-level settings.json (which belongs to Claude PC).
    [string]$ReviewerSettings = (Join-Path $PSScriptRoot 'reviewer-settings.json')
)

$ErrorActionPreference = "Stop"

function Write-Err($msg)  { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }

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
if (-not (Test-Path -LiteralPath $ReviewerSettings -PathType Leaf)) {
    Write-Err "ReviewerSettings not found: $ReviewerSettings"
    exit 1
}

$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
# Absolute, because Push-Location below changes the working directory
$ReviewerSettings = (Resolve-Path -LiteralPath $ReviewerSettings).Path

# Session arguments
if ($SessionId) {
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($SessionId, [ref]$parsed)) {
        Write-Err "SessionId must be a UUID, got: $SessionId"
        exit 1
    }
    if ($NewSession) {
        $sessionArgs = @('--session-id', $SessionId)
        Write-Info "Starting NEW review session $SessionId"
    } else {
        $sessionArgs = @('--resume', $SessionId)
        Write-Info "Resuming review session $SessionId"
    }
} else {
    if ($NewSession) {
        Write-Err "-NewSession requires -SessionId"
        exit 1
    }
    $sessionArgs = @('-c')
    Write-Warn "No -SessionId given: falling back to -c (continues the most recent session in this repo)."
}

# -----------------------------------------------------------------------
# 2. Locate the Python environment for this repo
#    Returns the folder that contains python.exe (e.g. <venv>\Scripts), or $null.
# -----------------------------------------------------------------------
function Resolve-PythonBin {
    param([string]$Explicit, [string[]]$SearchRoots)

    $candidates = @()
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit)) {
            throw "PythonEnv not found: $Explicit"
        }
        $item = Get-Item -LiteralPath $Explicit
        if (-not $item.PSIsContainer) {
            # A python.exe path was given
            return $item.Directory.FullName
        }
        $candidates += $item.FullName
    } else {
        foreach ($root in $SearchRoots) {
            foreach ($name in '.venv', 'venv', 'env') {
                $candidates += (Join-Path $root $name)
            }
        }
    }

    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $c 'python.exe') -PathType Leaf) {
            return $c                                   # already a Scripts folder
        }
        $scripts = Join-Path $c 'Scripts'
        if (Test-Path -LiteralPath (Join-Path $scripts 'python.exe') -PathType Leaf) {
            return $scripts
        }
    }

    if ($Explicit) {
        throw "No python.exe found under PythonEnv: $Explicit"
    }
    return $null
}

# -----------------------------------------------------------------------
# 3. Save environment so everything can be restored in `finally`
# -----------------------------------------------------------------------
$envKeys = @(
    'PATH', 'VIRTUAL_ENV', 'PYTHONHOME',
    'PYTHONPYCACHEPREFIX', 'PYTEST_ADDOPTS', 'MYPY_CACHE_DIR', 'RUFF_CACHE_DIR',
    'PYTHONUTF8', 'PYTHONIOENCODING'
)
$savedEnv = @{}
foreach ($k in $envKeys) {
    $savedEnv[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
}

# -----------------------------------------------------------------------
# UTF-8 for the pipe into claude and for reading its output.
# Windows PowerShell 5.1 defaults $OutputEncoding to ASCII, which turns
# Vietnamese characters into '?' when piping text to a native exe.
# Harmless on PowerShell 7 (already UTF-8). Restored in `finally`.
# -----------------------------------------------------------------------
$savedOutputEncoding  = $OutputEncoding
$savedConsoleEncoding = [Console]::OutputEncoding
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$OutputEncoding = $utf8NoBom
try { [Console]::OutputEncoding = $utf8NoBom } catch { Write-Warn "Could not set console output encoding: $($_.Exception.Message)" }

$exitCode = 0
Push-Location -LiteralPath $RepoPath
try {
    # -------------------------------------------------------------------
    # 4. Confirm it is actually a git repo BEFORE launching Claude
    # -------------------------------------------------------------------
    $topLevel = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($topLevel)) {
        throw "Not a git repository (or git not available) at: $RepoPath"
    }
    $topLevelWin = (Resolve-Path -LiteralPath $topLevel.Trim()).Path
    Write-Ok "Confirmed git repo. Top level: $topLevelWin"

    # -------------------------------------------------------------------
    # 5. Python: put this repo's venv first on PATH
    # -------------------------------------------------------------------
    $searchRoots = @($RepoPath, $topLevelWin) | Select-Object -Unique
    $pythonBin = Resolve-PythonBin -Explicit $PythonEnv -SearchRoots $searchRoots

    if ($pythonBin) {
        $env:VIRTUAL_ENV = Split-Path -Parent $pythonBin
        $env:PATH = "$pythonBin;$($savedEnv['PATH'])"
        Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
        Write-Ok "Python env: $pythonBin"
    } else {
        Write-Info "No venv found in $($searchRoots -join ', ') - using system python on PATH."
    }

    # Readable Vietnamese output from Python on Windows consoles
    $env:PYTHONUTF8 = '1'
    $env:PYTHONIOENCODING = 'utf-8'

    # -------------------------------------------------------------------
    # 6. Redirect tool caches out of the repo (keeps git status clean)
    # -------------------------------------------------------------------
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $hashBytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($topLevelWin.ToLowerInvariant()))
    $hash = -join ($hashBytes[0..5] | ForEach-Object { $_.ToString('x2') })
    $cacheRoot = Join-Path $env:TEMP ("claude-review-cache\{0}-{1}" -f (Split-Path $topLevelWin -Leaf), $hash)
    New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null

    $env:PYTHONPYCACHEPREFIX = Join-Path $cacheRoot 'pycache'
    $env:MYPY_CACHE_DIR      = Join-Path $cacheRoot 'mypy'
    $env:RUFF_CACHE_DIR      = Join-Path $cacheRoot 'ruff'
    $env:PYTEST_ADDOPTS      = ("{0} -p no:cacheprovider" -f $savedEnv['PYTEST_ADDOPTS']).Trim()
    Write-Info "Tool caches redirected to: $cacheRoot"

    # -------------------------------------------------------------------
    # 7. Snapshot working tree, run Claude, compare
    # -------------------------------------------------------------------
    Write-Info "Review model: $Model"
    Write-Info "Reviewer settings: $ReviewerSettings"
    $before = (git status --porcelain=v1 --untracked-files=all) -join "`n"

    Get-Content -LiteralPath $PromptFile -Raw -Encoding UTF8 | claude @sessionArgs --model $Model --settings $ReviewerSettings -p -
    $exitCode = $LASTEXITCODE

    $after = (git status --porcelain=v1 --untracked-files=all) -join "`n"
    if ($before -ne $after) {
        Write-Warn "REVIEW_SIDE_EFFECT_DETECTED: the working tree changed during the review."
        Write-Warn "The reviewer is supposed to be read-only. Changes (<= before / => after):"
        Compare-Object ($before -split "`n") ($after -split "`n") |
            ForEach-Object { Write-Host ("  {0} {1}" -f $_.SideIndicator, $_.InputObject) }
        if ($exitCode -eq 0) { $exitCode = 3 }
    }
}
catch {
    Write-Err $_.Exception.Message
    $exitCode = 1
}
finally {
    $OutputEncoding = $savedOutputEncoding
    try { [Console]::OutputEncoding = $savedConsoleEncoding } catch { }
    foreach ($k in $envKeys) {
        [Environment]::SetEnvironmentVariable($k, $savedEnv[$k], 'Process')
    }
    Pop-Location
}

exit $exitCode