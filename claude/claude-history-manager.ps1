# =============================================================================
# claude-history-manager.ps1
# Manage local Claude Code CLI conversation history stored under
# ~/.claude/projects/**/*.jsonl - this includes both top-level session
# files AND nested subagent/workflow logs under
# <project>/<session-id>/subagents/workflows/<workflow-id>/*.jsonl
# (these are the real transcripts of Claude subagents spawned by MCP
# "Workflow" tool calls - e.g. from Antigravity's claude-review-plan /
# claude-review-code workflows).
#
# Usage:
#   Just run the script (double-click or drag onto it) - everything is
#   driven by an interactive numbered menu, no command-line flags needed.
# =============================================================================

$ErrorActionPreference = "Stop"
$claudeProjectsDir = Join-Path $HOME ".claude\projects"

function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Err($msg)  { Write-Host "  [ERROR] $msg" -ForegroundColor Red }
function Write-Warn($msg) { Write-Host "  [WARNING] $msg" -ForegroundColor Yellow }

# -----------------------------------------------------------------------
# Helper: enumerate ALL .jsonl files recursively across all project
# folders, including nested subagent/workflow logs. Tags each entry
# with a Type so the menu can show which kind it is.
# -----------------------------------------------------------------------
function Get-AllSessions {
    if (-not (Test-Path $claudeProjectsDir)) {
        return @()
    }
    $projectFolders = Get-ChildItem -Path $claudeProjectsDir -Directory
    $sessions = foreach ($proj in $projectFolders) {
        Get-ChildItem -Path $proj.FullName -Filter "*.jsonl" -File -Recurse | ForEach-Object {
            $relative = $_.FullName.Substring($proj.FullName.Length).TrimStart('\')
            $type = if ($relative -match 'subagents\\workflows') { "Subagent" } else { "Main" }
            [PSCustomObject]@{
                Project      = $proj.Name
                Type         = $type
                SessionId    = $_.BaseName
                RelativePath = $relative
                Path         = $_.FullName
                SizeKB       = [math]::Round($_.Length / 1KB, 1)
                LastModified = $_.LastWriteTime
            }
        }
    }
    return $sessions | Sort-Object LastModified -Descending
}

# -----------------------------------------------------------------------
# Helper: extract a readable (role, text) sequence from a .jsonl file.
# Shared by view / export / audit so parsing logic lives in one place.
# Best-effort - internal JSONL format is undocumented and may change.
# -----------------------------------------------------------------------
function Get-MessageTexts {
    param([string]$Path)

    $result = @()
    $lines = Get-Content -LiteralPath $Path
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            continue
        }

        $role = $null
        $text = $null

        if ($obj.PSObject.Properties.Name -contains "message") {
            $role = $obj.message.role
            $content = $obj.message.content
            if ($content -is [string]) {
                $text = $content
            } elseif ($content) {
                $textParts = @()
                foreach ($part in $content) {
                    if ($part.type -eq "text" -and $part.text) { $textParts += $part.text }
                    elseif ($part.type -eq "tool_use") { $textParts += "[tool_use: $($part.name)]" }
                    elseif ($part.type -eq "tool_result") { $textParts += "[tool_result]" }
                }
                $text = $textParts -join "`n"
            }
        } elseif ($obj.PSObject.Properties.Name -contains "type") {
            $role = $obj.type
        }

        if ($text) {
            $result += [PSCustomObject]@{ Role = $role; Text = $text }
        }
    }
    return $result
}

# -----------------------------------------------------------------------
# Action: list - show all sessions with size, date, and type
# -----------------------------------------------------------------------
function Invoke-ListSessions {
    $sessions = Get-AllSessions
    if ($sessions.Count -eq 0) {
        Write-Warn "No sessions found under $claudeProjectsDir"
        return
    }
    Write-Host ""
    Write-Host "Total entries: $($sessions.Count)  (Main sessions + Subagent/Workflow logs)" -ForegroundColor Cyan
    Write-Host ""
    $i = 1
    foreach ($s in $sessions) {
        $typeColor = if ($s.Type -eq "Subagent") { "Magenta" } else { "Yellow" }
        Write-Host ("[{0}] " -f $i) -NoNewline
        Write-Host ("{0,-9}" -f $s.Type) -NoNewline -ForegroundColor $typeColor
        Write-Host (" {0}  {1} KB  {2}" -f $s.LastModified.ToString("yyyy-MM-dd HH:mm"), $s.SizeKB, $s.Project)
        if ($s.Type -eq "Subagent") {
            Write-Host ("        -> $($s.RelativePath)") -ForegroundColor DarkGray
        }
        $i++
    }
    Write-Host ""
    return $sessions
}

# -----------------------------------------------------------------------
# Action: view - best-effort readable dump of a session's messages
# -----------------------------------------------------------------------
function Show-SessionContent {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Err "File not found: $Path"
        return
    }

    Write-Host ""
    Write-Host "=== Session content: $Path ===" -ForegroundColor Cyan
    Write-Host "(Best-effort parsing - internal JSONL format is undocumented and may change)" -ForegroundColor DarkGray
    Write-Host ""

    $messages = Get-MessageTexts -Path $Path
    foreach ($m in $messages) {
        $preview = if ($m.Text.Length -gt 500) { $m.Text.Substring(0, 500) + " ...(truncated)" } else { $m.Text }
        Write-Host "--- $($m.Role) ---" -ForegroundColor Magenta
        Write-Host $preview
        Write-Host ""
    }
}

# -----------------------------------------------------------------------
# Action: export - dump a session to a readable .md file
# -----------------------------------------------------------------------
function Export-SessionToMarkdown {
    param([string]$Path, [string]$OutPath)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Err "File not found: $Path"
        return
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Claude Code session export")
    [void]$sb.AppendLine("Source: $Path")
    [void]$sb.AppendLine("")

    $messages = Get-MessageTexts -Path $Path
    foreach ($m in $messages) {
        [void]$sb.AppendLine("## $($m.Role)")
        [void]$sb.AppendLine($m.Text)
        [void]$sb.AppendLine("")
    }

    Set-Content -Path $OutPath -Value $sb.ToString() -Encoding UTF8
    Write-Ok "Exported to: $OutPath"
}

# -----------------------------------------------------------------------
# Action: search - grep a keyword across all session files (raw line match)
# -----------------------------------------------------------------------
function Invoke-SearchSessions {
    param([string]$Keyword)

    if ([string]::IsNullOrWhiteSpace($Keyword)) {
        $Keyword = Read-Host "Enter keyword to search"
    }

    $sessions = Get-AllSessions
    Write-Host ""
    Write-Host "Searching for '$Keyword' across $($sessions.Count) entries..." -ForegroundColor Cyan
    Write-Host ""

    $found = 0
    foreach ($s in $sessions) {
        $matches = Select-String -Path $s.Path -Pattern ([regex]::Escape($Keyword)) -SimpleMatch -ErrorAction SilentlyContinue
        if ($matches) {
            $found++
            Write-Host ("Match ({0}x) - {1} - [{2}] {3}" -f $matches.Count, $s.LastModified.ToString("yyyy-MM-dd"), $s.Type, $s.Path) -ForegroundColor Yellow
        }
    }

    if ($found -eq 0) {
        Write-Warn "No matches found."
    } else {
        Write-Host ""
        Write-Ok "$found entrie(s) contain '$Keyword'"
    }
}

# -----------------------------------------------------------------------
# Action: audit verdicts - scan every Subagent (real Claude review) log,
# extract the actual verdict (APPROVED / REJECTED / NEED_CLARIFICATION /
# MATCH / MISMATCH / PARTIAL_MATCH / "Verdict" section), and print it
# plainly. Use this to cross-check what Claude actually concluded
# against what the orchestrating agent (e.g. Gemini/Antigravity)
# reported back to you in chat.
# -----------------------------------------------------------------------
function Invoke-AuditVerdicts {
    $verdictPattern = '(?is)(APPROVED|REJECTED|NEED_CLARIFICATION|PARTIAL_MATCH|MISMATCH|\bMATCH\b|##\s*Verdict)'

    $sessions = Get-AllSessions | Where-Object { $_.Type -eq "Subagent" }
    if ($sessions.Count -eq 0) {
        Write-Warn "No subagent/workflow logs found - nothing to audit."
        Write-Warn "(These only exist after an MCP Workflow tool call, e.g. from claude-review-plan/claude-review-code.)"
        return
    }

    Write-Host ""
    Write-Host "=== Verdict Audit - real Claude subagent conclusions ===" -ForegroundColor Cyan
    Write-Host "Scanning $($sessions.Count) subagent log(s)..." -ForegroundColor DarkGray
    Write-Host ""

    $anyFound = $false
    foreach ($s in $sessions) {
        $messages = Get-MessageTexts -Path $s.Path
        $assistantMessages = $messages | Where-Object { $_.Role -eq "assistant" }
        foreach ($m in $assistantMessages) {
            if ($m.Text -match $verdictPattern) {
                $anyFound = $true
                # Print from the last occurrence of a verdict keyword onward,
                # since verdicts are usually stated near the end of the message.
                $idx = $m.Text.LastIndexOf($Matches[0])
                $startIdx = [Math]::Max(0, $idx - 50)
                $snippet = $m.Text.Substring($startIdx)
                if ($snippet.Length -gt 700) { $snippet = $snippet.Substring(0, 700) + " ...(truncated)" }

                Write-Host ("Project : {0}" -f $s.Project) -ForegroundColor Cyan
                Write-Host ("Workflow: {0}" -f $s.RelativePath) -ForegroundColor Cyan
                Write-Host ("Date    : {0}" -f $s.LastModified.ToString("yyyy-MM-dd HH:mm"))
                Write-Host "--- verdict excerpt ---" -ForegroundColor DarkGray
                Write-Host $snippet
                Write-Host ""
                Write-Host "----------------------------------------------------------------------"
                Write-Host ""
            }
        }
    }

    if (-not $anyFound) {
        Write-Warn "No explicit verdict keywords found in any subagent log."
    } else {
        Write-Host "Cross-check each verdict above against what the orchestrating agent" -ForegroundColor Yellow
        Write-Host "told you in chat. A mismatch (e.g. real verdict = NEED_CLARIFICATION" -ForegroundColor Yellow
        Write-Host "but chat summary claimed 'fully approved') means the summary you were" -ForegroundColor Yellow
        Write-Host "given misrepresented the actual review." -ForegroundColor Yellow
        Write-Host ""
    }
}

# -----------------------------------------------------------------------
# Action: clean - delete sessions older than N days (with confirmation)
# -----------------------------------------------------------------------
function Invoke-CleanSessions {
    param([int]$OlderThanDays)

    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $sessions = Get-AllSessions | Where-Object { $_.LastModified -lt $cutoff }

    if ($sessions.Count -eq 0) {
        Write-Ok "No entries older than $OlderThanDays days."
        return
    }

    Write-Host ""
    Write-Warn "The following $($sessions.Count) entrie(s) are older than $OlderThanDays days:"
    foreach ($s in $sessions) {
        Write-Host ("  {0}  ({1} KB)  [{2}] {3}" -f $s.LastModified.ToString("yyyy-MM-dd"), $s.SizeKB, $s.Type, $s.Path)
    }
    Write-Host ""
    $confirm = Read-Host "Type YES to permanently delete these files (anything else cancels)"
    if ($confirm -ne "YES") {
        Write-Warn "Cancelled - nothing deleted."
        return
    }

    foreach ($s in $sessions) {
        Remove-Item -LiteralPath $s.Path -Force
    }
    Write-Ok "Deleted $($sessions.Count) file(s)."
}

# -----------------------------------------------------------------------
# Action: stats - overall disk usage summary
# -----------------------------------------------------------------------
function Show-Stats {
    $sessions = Get-AllSessions
    if ($sessions.Count -eq 0) {
        Write-Warn "No sessions found."
        return
    }
    $mainCount = ($sessions | Where-Object { $_.Type -eq "Main" }).Count
    $subCount  = ($sessions | Where-Object { $_.Type -eq "Subagent" }).Count
    $totalKB = ($sessions | Measure-Object -Property SizeKB -Sum).Sum
    $projectCount = ($sessions | Select-Object -ExpandProperty Project -Unique).Count
    $oldest = $sessions | Sort-Object LastModified | Select-Object -First 1
    $newest = $sessions | Sort-Object LastModified -Descending | Select-Object -First 1

    Write-Host ""
    Write-Host "=== History stats ===" -ForegroundColor Cyan
    Write-Host "  Total entries    : $($sessions.Count)  (Main: $mainCount, Subagent/Workflow: $subCount)"
    Write-Host "  Projects         : $projectCount"
    Write-Host "  Total size       : $([math]::Round($totalKB / 1024, 2)) MB"
    Write-Host "  Oldest entry     : $($oldest.LastModified.ToString('yyyy-MM-dd')) ($($oldest.Project))"
    Write-Host "  Newest entry     : $($newest.LastModified.ToString('yyyy-MM-dd')) ($($newest.Project))"
    Write-Host ""
}

# -----------------------------------------------------------------------
# Interactive menu
# -----------------------------------------------------------------------
function Show-Menu {
    while ($true) {
        Write-Host ""
        Write-Host "=== Claude Code History Manager ===" -ForegroundColor Cyan
        Write-Host "  1. List all entries (main sessions + subagent/workflow logs)"
        Write-Host "  2. View an entry (pick from list)"
        Write-Host "  3. Export an entry to markdown"
        Write-Host "  4. Search entries by keyword"
        Write-Host "  5. Clean up old entries"
        Write-Host "  6. Show stats"
        Write-Host "  7. Audit verdicts (find real Claude APPROVED/REJECTED/etc.)"
        Write-Host "  0. Exit"
        Write-Host ""
        $choice = Read-Host "Choose an option"

        switch ($choice) {
            "1" { Invoke-ListSessions | Out-Null }
            "2" {
                $sessions = Invoke-ListSessions
                if ($sessions) {
                    $idx = Read-Host "Enter number to view"
                    if ($idx -match '^\d+$' -and [int]$idx -ge 1 -and [int]$idx -le $sessions.Count) {
                        Show-SessionContent -Path $sessions[[int]$idx - 1].Path
                    }
                }
            }
            "3" {
                $sessions = Invoke-ListSessions
                if ($sessions) {
                    $idx = Read-Host "Enter number to export"
                    if ($idx -match '^\d+$' -and [int]$idx -ge 1 -and [int]$idx -le $sessions.Count) {
                        $s = $sessions[[int]$idx - 1]
                        $outPath = Join-Path (Get-Location) "$($s.SessionId).md"
                        Export-SessionToMarkdown -Path $s.Path -OutPath $outPath
                    }
                }
            }
            "4" { Invoke-SearchSessions -Keyword "" }
            "5" {
                $days = Read-Host "Delete entries older than how many days? (default 30)"
                if ([string]::IsNullOrWhiteSpace($days)) { $days = 30 }
                Invoke-CleanSessions -OlderThanDays ([int]$days)
            }
            "6" { Show-Stats }
            "7" { Invoke-AuditVerdicts }
            "0" { return }
            default { Write-Warn "Invalid choice." }
        }
    }
}

# -----------------------------------------------------------------------
# Entry point - always launch the interactive menu
# -----------------------------------------------------------------------
if (-not (Test-Path $claudeProjectsDir)) {
    Write-Warn "No history folder found yet at: $claudeProjectsDir"
    Write-Warn "This is normal if you have not run any Claude Code session yet."
}

Show-Menu

Write-Host ""
Write-Host "Press Enter to exit..."
Read-Host | Out-Null