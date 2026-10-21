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
    return [pscustomobject]@{ ok = $true; written = $true; problems = @(); lines = $recordLines; message = ("status written for " + $back.orc + ": " + $back.doing); usage = $false }
}
