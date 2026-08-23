# =============================================================================
# claude-qa-start.ps1
# Starts Claude Code in MCP server mode, acting as the QA/Reviewer role
# that Antigravity connects to via MCP. The reviewer role is READ-ONLY -
# it must never edit files - so this script locks down Write/Edit
# permissions before starting the server.
#
# Usage:
#   .\claude-qa-start.ps1
#   .\claude-qa-start.ps1 -WorkspaceRoot "D:\Projects"
# =============================================================================

param(
    [string]$WorkspaceRoot = "F:\VScode"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Err($msg)  { Write-Host "  [ERROR] $msg" -ForegroundColor Red }
function Write-Warn($msg) { Write-Host "  [WARNING] $msg" -ForegroundColor Yellow }

Write-Step "=== Claude Code QA/Reviewer Launcher ==="
Write-Host ""

# -----------------------------------------------------------------------
# 1. Check Claude Code CLI (native installer - no Node.js dependency)
# -----------------------------------------------------------------------
Write-Step "[1/4] Checking Claude Code CLI..."
try {
    $claudeVersion = claude --version
    Write-Ok "Claude Code $claudeVersion"
} catch {
    Write-Err "Claude Code CLI not found."
    Write-Host "  Install the native version (no Node.js needed) with:"
    Write-Host "    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser"
    Write-Host "    irm https://claude.ai/install.ps1 | iex"
    exit 1
}

# -----------------------------------------------------------------------
# 2. Check that the workspace root exists
# -----------------------------------------------------------------------
Write-Step "[2/4] Checking workspace directory..."
if (-not (Test-Path $WorkspaceRoot)) {
    Write-Err "Directory not found: $WorkspaceRoot"
    Write-Host "  Pass the correct path via -WorkspaceRoot, for example:"
    Write-Host "    .\claude-qa-start.ps1 -WorkspaceRoot ""D:\Projects"""
    exit 1
}
Write-Ok "Workspace root: $WorkspaceRoot"

# -----------------------------------------------------------------------
# 4. Check/write permissions.deny into the global settings.json
#    CONFIRMED: "claude mcp serve" does NOT accept a --disallowedTools
#    flag (tested - CLI rejects it with "unknown option"). This
#    settings.json permissions.deny block is therefore the ONLY
#    enforcement layer for blocking Write/Edit/NotebookEdit - not a
#    backup layer.
# -----------------------------------------------------------------------
Write-Step "[3/4] Checking settings.json (~/.claude/settings.json)..."

$claudeDir = Join-Path $HOME ".claude"
$settingsPath = Join-Path $claudeDir "settings.json"

if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

$denyTools = @("Write", "Edit", "NotebookEdit")

if (Test-Path $settingsPath) {
    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    } catch {
        Write-Warn "The current settings.json has a JSON syntax error - it will NOT be auto-fixed."
        Write-Warn "Please check the file manually: $settingsPath"
        $settings = $null
    }

    if ($settings) {
        if (-not ($settings.PSObject.Properties.Name -contains "permissions")) {
            $settings | Add-Member -MemberType NoteProperty -Name "permissions" -Value ([PSCustomObject]@{ deny = @() })
        }
        if (-not ($settings.permissions.PSObject.Properties.Name -contains "deny")) {
            $settings.permissions | Add-Member -MemberType NoteProperty -Name "deny" -Value @()
        }
        $currentDeny = @($settings.permissions.deny)
        $missing = $denyTools | Where-Object { $_ -notin $currentDeny }
        if ($missing.Count -gt 0) {
            $settings.permissions.deny = @($currentDeny + $missing)
            $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
            Write-Ok "Added $($missing -join ', ') to permissions.deny in settings.json"
        } else {
            Write-Ok "permissions.deny already includes Write/Edit/NotebookEdit"
        }
    }
} else {
    $newSettings = [PSCustomObject]@{
        permissions = [PSCustomObject]@{
            deny = $denyTools
        }
    }
    $newSettings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
    Write-Ok "Created new settings.json with permissions.deny = Write, Edit, NotebookEdit"
}

Write-Warn "The reviewer role will NOT be able to create/edit/delete files (read-only + can run commands)."
Write-Warn "If you need to temporarily allow file edits (e.g. to let it self-fix a review issue), edit this file manually:"
Write-Host "    $settingsPath"

# -----------------------------------------------------------------------
# 5. Move into the workspace root and start the MCP server
# -----------------------------------------------------------------------
Write-Step "[4/4] Starting Claude Code MCP server..."
Set-Location $WorkspaceRoot
Write-Ok "Changed directory to: $WorkspaceRoot"
Write-Host ""
Write-Host "IMPORTANT NOTE:" -ForegroundColor Magenta
Write-Host "  This server sits at the workspace root ($WorkspaceRoot), NOT inside"
Write-Host "  any specific project/repo. Every time Antigravity calls in for a"
Write-Host "  review, it MUST include the absolute path to the exact repo to work"
Write-Host "  on (see STEP -1 in plan_antigravity_claude_reviewer.md) - this"
Write-Host "  server cannot guess which repo in the workspace you're working on."
Write-Host ""
Write-Host "Press Ctrl+C to stop the server at any time." -ForegroundColor DarkGray
Write-Host ""
Write-Host "NOTE: --disallowedTools is not a valid flag for the 'mcp serve' subcommand" -ForegroundColor DarkGray
Write-Host "(confirmed by testing - the CLI rejects it with 'unknown option'). Write" -ForegroundColor DarkGray
Write-Host "protection is enforced solely via permissions.deny in settings.json, set" -ForegroundColor DarkGray
Write-Host "in step [3/4] above." -ForegroundColor DarkGray
Write-Host ""

claude mcp serve