# fleet/StatusWrite.ps1 - the ONE way an Orc's status card is written: `horde status set`.
#
# WHY (task T-0246, 2026-10-20). The phone's Orc cards read each lane's status.txt through
# fleet/StatusPanel.ps1. Orcs wrote the file by hand and sometimes broke a rule (a bare "PR 68", a
# path, 121 characters, a byte-order mark), and the card then said "no status written". One writer
# builds the whole record from three required statements, asks THE READER'S OWN FUNCTION whether it
# would be read (ConvertFrom-HordeFleetStatusBytes: no rule is copied here, so the two cannot drift),
# and writes nothing when it would not.
#
# WHAT IT WRITES. Exactly the bytes of record version 1: ASCII, LF line ends, a trailing LF, the
# header, then orc, lane, doing, finished, blocked and - only when given - waiting on. The text is
# encoded as UTF-8, so a character outside ASCII becomes bytes above 127 and the reader refuses it
# by its own words, rather than this file guessing at a transliteration.
#
# THE LAST GOOD COPY. After a clean write the same bytes go to .status.last-good.txt beside it. The
# guard hook (hooks/horde-status-guard.mjs) puts that copy back when a status.txt written any other
# way breaks a rule. Both files are written whole: a temp file beside the target, then
# Move-HordeFileAtomic, so a kill leaves the old file or the new one, never half of either.
#
# No Set-StrictMode here: this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\FileAtomic.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
. (Join-Path $PSScriptRoot "StatusPanel.ps1")

# The copy the guard hook restores from. One name, here and in the hook's checker.
$script:HordeStatusLastGoodFile = ".status.last-good.txt"

function ConvertTo-HordeStatusRecordBytes {
    # The bytes of one record from its values. -WaitingOn $null means "no seventh line" (an empty
    # string is a value, and the reader refuses it).
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Orc,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Lane,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Doing,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Finished,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Blocked,
        [AllowNull()]$WaitingOn = $null
    )
    $lines = @($script:HordeFleetStatusHeader, ("orc: " + $Orc), ("lane: " + $Lane), ("doing: " + $Doing), ("finished: " + $Finished), ("blocked: " + $Blocked))
    if ($null -ne $WaitingOn) { $lines += ($script:HordeFleetStatusWaitingKey + ": " + $WaitingOn) }
    $text = ($lines -join "`n") + "`n"
    return (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)
}

function Write-HordeStatusFileAtomic {
    # Bytes to a file, whole: a temp file beside it, then one rename. The temp file is removed in finally unless the process is killed between its creation and the rename, which leaves one ".tmp-" file beside the target; the target itself is never half-written.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][byte[]]$Bytes, $Mtime = $null)
    $temp = $Path + ".tmp-" + [guid]::NewGuid().ToString("N")
    try {
        [System.IO.File]::WriteAllBytes($temp, $Bytes)
        # An undo gives the old card back its own modified time (the panel's "as of"), not now.
        if ($null -ne $Mtime) { [System.IO.File]::SetLastWriteTimeUtc($temp, $Mtime) }
        Move-HordeFileAtomic -From $temp -To $Path
    } finally {
        if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) }
    }
}

function Invoke-HordeStatusSet {
    # Build, check and (unless -DryRun) write one card. Returns { ok; written; problems; lines; message }:
    # ok is false whenever nothing was written because of what was asked; an error in the disk itself
    # is thrown. -Orc and -Lane left empty are taken from the folder's current card when it reads clean.
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Doing,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Finished,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Blocked,
        [AllowNull()]$WaitingOn = $null,
        [string]$Lane = "",
        [string]$Orc = "",
        [switch]$DryRun
    )
    if (-not [System.IO.Directory]::Exists($Folder)) {
        return [pscustomobject]@{ ok = $false; written = $false; problems = @("the folder '" + $Folder + "' does not exist"); lines = @(); message = ""; usage = $false }
    }
    $current = Read-HordeFleetStatusFolder -Path $Folder
    $missing = @()
    if ($Orc -eq "") { if ($current.written) { $Orc = $current.orc } else { $missing += "-Orc" } }
    if ($Lane -eq "") { if ($current.written) { $Lane = $current.lane } else { $missing += "-Lane" } }
    if ($missing.Count -gt 0) {
        $why = "the folder holds no status.txt that reads clean, so " + ($missing -join " and ") + " must be given (" + (@($current.problems) -join "; ") + ")"
        return [pscustomobject]@{ ok = $false; written = $false; problems = @($why); lines = @(); message = ""; usage = $true }
    }
    # One line each: a line break inside a value would move the lines under their keys. The reader would
    # catch most of that by count, but not name it.
    $problems = @()
    foreach ($pair in @(@("Orc", $Orc), @("Lane", $Lane), @("Doing", $Doing), @("Finished", $Finished), @("Blocked", $Blocked), @("WaitingOn", $WaitingOn))) {
        if ($null -ne $pair[1] -and ("" + $pair[1]) -match "[\r\n]") { $problems += ("-" + $pair[0] + " holds a line break, and a value is one line") }
    }
    $bytes = ConvertTo-HordeStatusRecordBytes -Orc $Orc -Lane $Lane -Doing $Doing -Finished $Finished -Blocked $Blocked -WaitingOn $WaitingOn
    # THE READER'S OWN FUNCTION decides. Every problem it finds is listed, in its words.
    $verdict = ConvertFrom-HordeFleetStatusBytes -Bytes $bytes
    $problems += @($verdict.problems)
    # THE READER'S SIZE CAP is in Read-HordeFleetStatusFolder, not in the bytes function: a card past it
    # passes every rule above and is then NOT READ. Held here in the reader's own words (review, 2026-10-20:
    # a 9000 character -Lane passed a dry run and wrote a card the panel could not read).
    if ($bytes.Length -gt $script:HordeFleetStatusMostBytes) { $problems += ("is " + $bytes.Length + " bytes, far more than a record's seven lines, and was not read") }
    # TWO FOLDERS, ONE LETTER (the panel's own rule, in its words): a sibling lane whose card reads clean and
    # says the same letter would make both cards "no status written".
    $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Folder).TrimEnd("\", "/"))
    if ($Orc -cmatch '\A[A-Z]\z' -and $parent) {
        $rivals = @()
        foreach ($sib in @([System.IO.Directory]::GetDirectories($parent) | Sort-Object)) {
            if ([string]::Equals($sib.TrimEnd("\", "/"), [System.IO.Path]::GetFullPath($Folder).TrimEnd("\", "/"), [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $theirs = Read-HordeFleetStatusFolder -Path $sib
            if ($theirs.written -and $theirs.orc -ceq $Orc) { $rivals += (Split-Path -Leaf $sib) }
        }
        if ($rivals.Count -gt 0) {
            $names = (@($rivals | Select-Object -First $script:HordeFleetStatusMostNamed) -join ", ")
            if ($rivals.Count -gt $script:HordeFleetStatusMostNamed) { $names += " and " + ($rivals.Count - $script:HordeFleetStatusMostNamed) + " more" }
            $problems += ("says it is Orc " + $Orc + ", and so does another folder (" + $names + "), so which is that Orc cannot be told")
        }
    }
    $text = (New-Object System.Text.UTF8Encoding($false)).GetString($bytes).TrimEnd("`n")
    $recordLines = @($text -split "`n")
    if ($problems.Count -gt 0) {
        return [pscustomobject]@{ ok = $false; written = $false; problems = @($problems); lines = $recordLines; message = ""; usage = $false }
    }
    if ($DryRun) {
        return [pscustomobject]@{ ok = $true; written = $false; problems = @(); lines = $recordLines; message = "dry run: the record reads clean and was not written"; usage = $false }
    }
    $target = Join-Path $Folder $script:HordeFleetStatusFile
    # The previous bytes, kept so a card that does not read back can be taken away again.
    $previous = $null; $previousTime = $null
    if ([System.IO.File]::Exists($target)) { $previous = [System.IO.File]::ReadAllBytes($target); $previousTime = [System.IO.File]::GetLastWriteTimeUtc($target) }
    Write-HordeStatusFileAtomic -Path $target -Bytes $bytes
    $back = Read-HordeFleetStatusFolder -Path $Folder
    if (-not $back.written) {
        $undone = "the new file was taken away again (there was no previous card)"
        if ($null -ne $previous) { Write-HordeStatusFileAtomic -Path $target -Bytes $previous -Mtime $previousTime; $undone = "the previous card was put back" }
        elseif ([System.IO.File]::Exists($target)) { [System.IO.File]::Delete($target) }
        return [pscustomobject]@{ ok = $false; written = $false; undone = $true; problems = @("read back after the write, the card does not read clean: " + (@($back.problems) -join "; ") + "; " + $undone); lines = $recordLines; message = ""; usage = $false }
    }
    Write-HordeStatusFileAtomic -Path (Join-Path $Folder $script:HordeStatusLastGoodFile) -Bytes $bytes
    return [pscustomobject]@{ ok = $true; written = $true; problems = @(); lines = $recordLines; message = ("status written for " + $back.orc + ": " + $back.doing); usage = $false; orc = $back.orc; lane = $back.lane }
}

function Invoke-HordeStatusOrcRow {
    # After a card is written: make sure fleet.db has an orc row for it (T-0299: a new Orc had none until a hand
    # `horde db import`, and `horde decisions publish` refused with "no row for Orc X"). The rule is the importer's
    # own, one function in fleet-db/orc-row.mjs, reached through fleet-db/orc-cli.mjs.
    # FAIL-OPEN, because the card is what matters and it is already written: no home, no node (or one older than
    # 24), no fleet.db, a busy or newer database all come back as { state = "skipped"; reason }, never as a throw.
    # state is "added" (a row was made), "kept" (it was there) or "skipped". Only a folder named "thrall" is the Thrall's.
    # T-0389: the card just written is passed too (--card), so the same transaction appends its orc_status row (live,
    # backfill 0); statusRow says what became of that row: "status row added", "status row kept", "no status row: <why>"
    # (the card's doing or blocked is past what the table holds; the orc row is still made), or "" when skipped.
    param([Parameter(Mandatory = $true)][string]$Folder, [Parameter(Mandatory = $true)][string]$Orc, [AllowEmptyString()][string]$Lane = "")
    try {
        $resolved = Resolve-HordeHome
        if ($resolved.source -eq "default") { return [pscustomobject]@{ state = "skipped"; reason = "no Horde home (set HORDE_HOME, or horde home set -Path <folder>)"; statusRow = "" } }
        $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $node) { return [pscustomobject]@{ state = "skipped"; reason = "node is not installed (fleet.db needs Node.js 24 or later)"; statusRow = "" } }
        # No separate `node --version` probe: it would run outside the 20 s net below. A node too old for fleet.db
        # fails orc-cli.mjs on its first import, and that comes back here as a skip like any other refusal.
        $leaf = Split-Path -Leaf ([System.IO.Path]::GetFullPath($Folder).TrimEnd("\", "/"))
        # The lane text goes in a quoted argument: a double quote or a backslash in it would end the argument early under
        # Windows PowerShell 5.1's quoting, so each becomes an apostrophe (the row's name is a label, not the card).
        $laneText = ($Lane -replace '["\\]', "'")
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $node.Source
        $psi.Arguments = '"' + (Join-Path (Split-Path -Parent $PSScriptRoot) "fleet-db\orc-cli.mjs") + '" ensure --folder "' + $leaf + '" --letter "' + $Orc + '" --lane "' + $laneText + '"'
        if ($leaf -ceq "thrall") { $psi.Arguments += " --thrall" }
        $psi.Arguments += ' --card "' + (Join-Path ([System.IO.Path]::GetFullPath($Folder)) $script:HordeFleetStatusFile) + '"'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.EnvironmentVariables["HORDE_HOME"] = $resolved.path
        $p = [System.Diagnostics.Process]::Start($psi)
        try {
            $errTask = $p.StandardError.ReadToEndAsync()
            $outTask = $p.StandardOutput.ReadToEndAsync()
            # The database waits at most a few seconds for its lock; this is the net under that, killing only the process started here.
            if (-not $p.WaitForExit(20000)) { try { $p.Kill() } catch { }; return [pscustomobject]@{ state = "skipped"; reason = "fleet.db did not answer in 20 seconds"; statusRow = "" } }
            $p.WaitForExit()
            $said = ("" + $outTask.Result).Trim()
            if ($p.ExitCode -eq 0 -and $said -cmatch '\A(added|kept)(; (status row added|status row kept|no status row: [\x20-\x7E]+))?\z') {
                $statusRow = ""
                if ($Matches[3]) { $statusRow = $Matches[3] }
                return [pscustomobject]@{ state = $Matches[1]; reason = ""; statusRow = $statusRow }
            }
            # orc-cli.mjs says its reason on a line of its own ("fleet.db..." or "refused..."); a node crash or warning
            # printed around it is not the reason, so only such a line is taken.
            $why = (("" + $errTask.Result) -split "\r?\n" | Where-Object { $_ -match '^(fleet\.db|refused)' } | Select-Object -Last 1)
            if (-not $why) { $why = "the row command stopped with exit code " + $p.ExitCode + " (fleet.db needs Node.js 24 or later)" }
            return [pscustomobject]@{ state = "skipped"; reason = ("" + $why).Trim(); statusRow = "" }
        } finally { $p.Dispose() }
    } catch {
        return [pscustomobject]@{ state = "skipped"; reason = $_.Exception.Message; statusRow = "" }
    }
}
