# core/PaneSessions - Claude Code's pane-sessions files, read as schema/pane-session.v1 describes them.
#
# ~/.claude/pane-sessions/<n>.json is written by Claude Code's SessionStart hook: the hook's input,
# verbatim, in a file named by the number of the host handle the session started in. Horde never
# writes these files (schema/pane-session.v1, "Horde never writes these files").
#
# THIS READER DOES NOT DECIDE WHETHER A FILE IS TRUE. It reads every file, validates it against the
# schema, and records when it was written - the file's last-write time is the only record of that
# (pane-session.v1 x-horde-file.written). Whether a file may answer for a session is the projection's
# question, because it needs the live handle list, the host instance and the other stores
# (core/ownership.json X1 guard). wezfleet had five readers of this file, each applying its own
# subset of the guards (YedPool/wezfleet lib/Registry.ps1:214-218); here there is one reader and one
# place the guard is applied.
#
# A LISTING IS COMPLETE OR IT SAYS WHY NOT: a missing directory, an unlistable one, or a file that
# cannot be read makes the listing unknown, naming what failed. A file that is read but does not
# match the schema is REFUSED and named - it is a known fact about that file, not a gap - because
# wezfleet refused the same files (a malformed session_id, lib/Registry.ps1:244).

# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "Schema.ps1")

function Get-HordePaneSessionsDir { return (Join-Path $env:USERPROFILE ".claude\pane-sessions") }

function Read-HordePaneSessions {
    # Returns { files; refused; complete }:
    #   files     one { handle; path; writtenUtc; sessionId; cwd; transcriptPath; sessionTitle } per
    #             file that is named by a handle number and matches schema/pane-session.v1
    #   refused   { name; reason } for every file that was read and is not one
    #   complete  answer: known $true when every file was listed and read, unknown otherwise
    param([string]$Dir = (Get-HordePaneSessionsDir), $Schema = $null)
    if ($null -eq $Schema) { $Schema = Get-HordeSchema -Name "pane-session.v1" }
    $files = New-Object System.Collections.ArrayList
    $refused = New-Object System.Collections.ArrayList
    $gaps = New-Object System.Collections.ArrayList
    $listed = @()
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        [void]$gaps.Add("there is no pane-sessions directory at " + $Dir)
    } else {
        try { $listed = @(Get-ChildItem -LiteralPath $Dir -File -ErrorAction Stop | Where-Object { $_.Extension -eq ".json" }) }
        catch { [void]$gaps.Add("the pane-sessions directory could not be listed: " + $_.Exception.Message) }
    }
    foreach ($f in $listed) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        # A HANDLE NUMBER NAMES THE FILE, as wezfleet requires (lib/Registry.ps1:230).
        if ($base -notmatch '^[0-9]{1,9}$') { [void]$refused.Add([pscustomobject]@{ name = $f.Name; reason = "not named by a handle number" }); continue }
        $j = $null
        $written = $null
        try {
            $j = ConvertFrom-HordeJson -Text (Read-HordeSharedText -Path $f.FullName)
            $written = [System.IO.File]::GetLastWriteTimeUtc($f.FullName)
        } catch {
            # A file removed between listing and reading is a session that restarted in that
            # handle; the hook rewrites it with cat >, so it can also be caught half-written.
            if (-not (Test-Path -LiteralPath $f.FullName)) { [void]$refused.Add([pscustomobject]@{ name = $f.Name; reason = "removed during the read" }); continue }
            [void]$gaps.Add($f.Name + " could not be read: " + $_.Exception.Message); continue
        }
        $problems = @()
        if ($null -eq $j) { $problems = @("the file is empty") } else { $problems = @(Test-HordeSchema -Value $j -Schema $Schema) }
        if ($problems.Count -gt 0) { [void]$refused.Add([pscustomobject]@{ name = $f.Name; reason = ("does not match pane-session.v1: " + ($problems -join "; ")) }); continue }
        $title = $null
        $tp = $j.PSObject.Properties["session_title"]
        if ($null -ne $tp -and "$($tp.Value)" -ne "") { $title = "$($tp.Value)" }
        [void]$files.Add([pscustomobject]@{
            handle = ("" + [long]$base); path = $f.FullName; writtenUtc = $written
            sessionId = "$($j.session_id)"; cwd = "$($j.cwd)"; transcriptPath = "$($j.transcript_path)"; sessionTitle = $title })
    }
    $complete = New-HordeKnown -Value $true
    if ($gaps.Count -gt 0) { $complete = New-HordeUnknown -Reason (@($gaps) -join "; ") }
    return [pscustomobject]@{ PSTypeName = "Horde.PaneSessionsRead"; files = $files.ToArray(); refused = $refused.ToArray(); complete = $complete }
}
