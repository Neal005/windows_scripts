# =============================================================================
# claude-history-manager.ps1
# Manage local Claude Code CLI conversation history stored under
# ~/.claude/projects/*.jsonl (one file per session, one folder per project
# working directory).
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
# Helper: enumerate all session files across all project folders
# -----------------------------------------------------------------------
function Get-AllSessions {
    if (-not (Test-Path $claudeProjectsDir)) {
        return @()
    }
    $projectFolders = Get-ChildItem -Path $claudeProjectsDir -Directory
    $sessions = foreach ($proj in $projectFolders) {
        Get-ChildItem -Path $proj.FullName -Filter "*.jsonl" -File | ForEach-Object {
            [PSCustomObject]@{
                Project      = $proj.Name
                SessionId    = $_.BaseName
                Path         = $_.FullName
                SizeKB       = [math]::Round($_.Length / 1KB, 1)
                LastModified = $_.LastWriteTime
            }
        }
    }
    return $sessions | Sort-Object LastModified -Descending
}

# -----------------------------------------------------------------------
# Action: list - show all sessions with size and date
# -----------------------------------------------------------------------
function Invoke-ListSessions {
    $sessions = Get-AllSessions
    if ($sessions.Count -eq 0) {
        Write-Warn "No sessions found under $claudeProjectsDir"
        return
    }
    Write-Host ""
    Write-Host "Total sessions: $($sessions.Count)" -ForegroundColor Cyan
    Write-Host ""
    $i = 1
    foreach ($s in $sessions) {
        Write-Host ("[{0}] {1}" -f $i, $s.LastModified.ToString("yyyy-MM-dd HH:mm")) -NoNewline -ForegroundColor Yellow
        Write-Host ("  {0}  ({1} KB)  Project: {2}" -f $s.SessionId.Substring(0, [Math]::Min(8, $s.SessionId.Length)), $s.SizeKB, $s.Project)
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
            $preview = if ($text.Length -gt 500) { $text.Substring(0, 500) + " ...(truncated)" } else { $text }
            Write-Host "--- $role ---" -ForegroundColor Magenta
            Write-Host $preview
            Write-Host ""
        }
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
        }

        if ($text) {
            [void]$sb.AppendLine("## $role")
            [void]$sb.AppendLine($text)
            [void]$sb.AppendLine("")
        }
    }

    Set-Content -Path $OutPath -Value $sb.ToString() -Encoding UTF8
    Write-Ok "Exported to: $OutPath"
}

# -----------------------------------------------------------------------
# Action: search - grep a keyword across all session files
# -----------------------------------------------------------------------
function Invoke-SearchSessions {
    param([string]$Keyword)

    if ([string]::IsNullOrWhiteSpace($Keyword)) {
        $Keyword = Read-Host "Enter keyword to search"
    }

    $sessions = Get-AllSessions
    Write-Host ""
    Write-Host "Searching for '$Keyword' across $($sessions.Count) sessions..." -ForegroundColor Cyan
    Write-Host ""

    $found = 0
    foreach ($s in $sessions) {
        $matches = Select-String -Path $s.Path -Pattern ([regex]::Escape($Keyword)) -SimpleMatch -ErrorAction SilentlyContinue
        if ($matches) {
            $found++
            Write-Host ("Match ({0}x) - {1} - {2}" -f $matches.Count, $s.LastModified.ToString("yyyy-MM-dd"), $s.Path) -ForegroundColor Yellow
        }
    }

    if ($found -eq 0) {
        Write-Warn "No matches found."
    } else {
        Write-Host ""
        Write-Ok "$found session(s) contain '$Keyword'"
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
        Write-Ok "No sessions older than $OlderThanDays days."
        return
    }

    Write-Host ""
    Write-Warn "The following $($sessions.Count) session(s) are older than $OlderThanDays days:"
    foreach ($s in $sessions) {
        Write-Host ("  {0}  ({1} KB)  {2}" -f $s.LastModified.ToString("yyyy-MM-dd"), $s.SizeKB, $s.Path)
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
    Write-Ok "Deleted $($sessions.Count) session file(s)."
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
    $totalKB = ($sessions | Measure-Object -Property SizeKB -Sum).Sum
    $projectCount = ($sessions | Select-Object -ExpandProperty Project -Unique).Count
    $oldest = $sessions | Sort-Object LastModified | Select-Object -First 1
    $newest = $sessions | Sort-Object LastModified -Descending | Select-Object -First 1

    Write-Host ""
    Write-Host "=== History stats ===" -ForegroundColor Cyan
    Write-Host "  Total sessions : $($sessions.Count)"
    Write-Host "  Projects       : $projectCount"
    Write-Host "  Total size     : $([math]::Round($totalKB / 1024, 2)) MB"
    Write-Host "  Oldest session : $($oldest.LastModified.ToString('yyyy-MM-dd')) ($($oldest.Project))"
    Write-Host "  Newest session : $($newest.LastModified.ToString('yyyy-MM-dd')) ($($newest.Project))"
    Write-Host ""
}

# -----------------------------------------------------------------------
# Interactive menu
# -----------------------------------------------------------------------
function Show-Menu {
    while ($true) {
        Write-Host ""
        Write-Host "=== Claude Code History Manager ===" -ForegroundColor Cyan
        Write-Host "  1. List all sessions"
        Write-Host "  2. View a session (pick from list)"
        Write-Host "  3. Export a session to markdown"
        Write-Host "  4. Search sessions by keyword"
        Write-Host "  5. Clean up old sessions"
        Write-Host "  6. Show stats"
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
                $days = Read-Host "Delete sessions older than how many days? (default 30)"
                if ([string]::IsNullOrWhiteSpace($days)) { $days = 30 }
                Invoke-CleanSessions -OlderThanDays ([int]$days)
            }
            "6" { Show-Stats }
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