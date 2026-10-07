# fleet/StatusPanel.ps1 - what each Orc says it is doing, read from the small file each one keeps.
#
# THE ONE JOB of this file is to read status records and hand them on as plain data. It knows nothing
# of questions, windows or pages: a page part that shows the data (fleet/line/) is given it by whoever
# opened the page, and the same data could be printed or sent across a link unchanged.
#
# THE STATUS RECORD, version 1 (approved 2026-10-06). One file per Orc, status.txt, in that Orc's own
# folder, replaced whole each time: exactly six lines of ASCII,
#
#   horde-orc-status 1
#   orc: <one capital letter>
#   lane: <its lane in plain words>
#   doing: <what it is doing now>          at most 120 characters, plain words
#   finished: <the last thing it finished>  at most 120 characters, plain words
#   blocked: <no, or one sentence saying what stops all its work>
#
# The file's own modified time is the "as of": an Orc never writes a time, and a stale record is
# visible because its age is shown.
#
# A RECORD IS READ WHOLE OR NOT AT ALL. A file that is missing, or that breaks any rule below, is
# shown as "no status written" with what was wrong - NEVER as its half-read fields, and never as a
# guess. The rules are the record's own checker's, ported: a byte-order mark; a byte that is not
# ASCII; a line count that is not six; a first line that is not the header; a line that is not its
# "key: value" with something after the colon; doing or finished over 120 characters; doing or
# finished holding a bare pull-request or issue number or a file path (the record is read cold by a
# person: "the fix for garbled mail", not "PR 68"). Two rules are this reader's own. It has no table
# of who sits where, so the orc line is ONE capital letter, and two folders that both claim one letter
# are both "no status written", since which is that Orc cannot be told. And a record holds no control
# character but the ends of its lines: the checker lets one through, and this reader hands a record
# on to be drawn.
#
# WHAT THIS DOES NOT SAY, and the panel must not pretend to: working or idle, sessions open, waiting
# on a person. Those come from the fleet's activity and the list of questions, not from this file.
#
# WHERE THE FILES ARE, AND HOW MANY FOLDERS ARE READ, ARE THE MODULE'S SETTINGS (core/ModuleSettings.ps1,
# module "fleet", a person's file <HordeHome>\settings\fleet.json):
#   statusFolder        an absolute folder, each direct subfolder of which is one Orc's. Left out, the
#                       answer is "not configured", which is not an error: a machine with no fleet has
#                       none. (It replaces <HordeHome>\fleet\status-source.json, the one settings file
#                       written before there was a place for a module's settings; that file is no
#                       longer read.)
#   statusFoldersRead   the most folders read, 64 unless the file says otherwise. THE REST ARE COUNTED
#                       AND SAID, never read: the caller is a window's own thread, asking again every
#                       few seconds, and a folder of ten thousand subfolders held it for 8 s each time
#                       (measured 2026-10-06 by the review of this reader; with the 64, the same ten
#                       thousand are listed, 64 read and 9,936 counted in 67 to 93 ms, measured
#                       2026-10-07 on a machine slowed on purpose). Which are read is the first
#                       so many by name, compared by code point with letter case set aside, so the same
#                       ones every time.
# A fault in the person's file is said by name in the answer's findings, and the default is used.
#
# NOTHING HERE WRITES. Not the configuration, not a status file, not a folder.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ModuleSettings.ps1")

$script:HordeFleetStatusHeader = "horde-orc-status 1"
$script:HordeFleetStatusKeys = @("orc", "lane", "doing", "finished", "blocked")
$script:HordeFleetStatusFile = "status.txt"
# The longest doing and finished may be, in characters (the record's rule 2).
$script:HordeFleetStatusMostChars = 120
# A record is six short lines. A file far past that is not one, and is not read into memory to find out.
$script:HordeFleetStatusMostBytes = 8192
# How many of the folders that claim one letter are named in each one's problem; the rest are counted.
# Measured 2026-10-06 with every one named: 1,000 folders claiming one letter made 11 MB of answer,
# 3,000 made 100 MB, and 10,000 ended in an out-of-memory error. More than 26 records must repeat one.
$script:HordeFleetStatusMostNamed = 5
# THE SETTINGS OF THE MODULE "fleet" (header). The four numbers above are not among them: they are the
# record's own format and this reader's bound on its own answer, which no person's file should move.
$script:HordeFleetSettings = New-HordeModuleSettings -Module "fleet" -Settings @(
    @{ name = "statusFolder"; kind = "folder"; default = ""; what = "The folder whose direct subfolders each hold one Orc's status record. Left out, no fleet is configured on this machine." }
    @{ name = "statusFoldersRead"; kind = "whole"; default = 64; min = 1; max = 1000; what = "The most status folders read at one time; the rest are counted and said, not read." }
)
# A bare pull-request or issue reference, or a Windows path: the record checker's own expression.
$script:HordeFleetStatusBareReference = '(?i)\b(pr|pull request|issue)\s*#?\d+|#\d+|[A-Za-z]:\\'

function Get-HordeFleetSettingsDeclaration { return $script:HordeFleetSettings }

function Get-HordeFleetSettings {
    # The module's settings as they are now: { values; findings; path } (core/ModuleSettings.ps1).
    # Reads the one file and writes nothing. -HordeHome is for a caller that already knows the home.
    param([string]$HordeHome = "")
    return (Get-HordeModuleSettings -Declaration $script:HordeFleetSettings -HordeHome $HordeHome)
}

function Get-HordeFleetStatusSource {
    # The folder of status records, as { state; folder; reason }: state is configured, not-configured
    # (the setting names none) or unreadable (it names a folder that is not there). -Settings is the
    # answer of Get-HordeFleetSettings; without it the file is read here.
    param($Settings = $null, [string]$HordeHome = "")
    if ($null -eq $Settings) { $Settings = Get-HordeFleetSettings -HordeHome $HordeHome }
    $folder = "$($Settings.values.statusFolder)"
    if ($folder -eq "") { return [pscustomobject]@{ state = "not-configured"; folder = ""; reason = "no folder of status records is configured on this machine" } }
    $bad = { param([string]$Why) return [pscustomobject]@{ state = "unreadable"; folder = ""; reason = ("the setting of where status records are (statusFolder) " + $Why) } }
    # A FOLDER WINDOWS CANNOT EVEN BE ASKED ABOUT IS UNREADABLE TOO, NEVER A THROW: the caller is a
    # window's tick, and it is promised an answer. Measured 2026-10-06 by the review of this reader: a
    # folder on a machine that does not answer threw "The network path was not found" out of the test
    # for the folder, and a name holding characters no path may threw "Illegal characters in path".
    # Both are caught here and said in words.
    try {
        if (-not (Test-Path -LiteralPath $folder -PathType Container -ErrorAction Stop)) { return (& $bad ("names a folder that does not exist: " + $folder)) }
        return [pscustomobject]@{ state = "configured"; folder = [System.IO.Path]::GetFullPath($folder); reason = "" }
    } catch { return (& $bad ("names a folder that could not be looked for: " + $_.Exception.Message)) }
}

function ConvertFrom-HordeFleetStatusBytes {
    # One status record from the bytes of its file, as { problems; fields }: fields is the five values
    # by key, and is $null whenever problems is not empty (header, A RECORD IS READ WHOLE OR NOT AT
    # ALL). A PURE FUNCTION of the bytes.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)
    $problems = New-Object System.Collections.ArrayList
    $body = $Bytes
    if ($body.Length -ge 3 -and $body[0] -eq 0xEF -and $body[1] -eq 0xBB -and $body[2] -eq 0xBF) {
        [void]$problems.Add("starts with a byte-order mark")
        $rest = New-Object byte[] ($body.Length - 3)
        [System.Array]::Copy($body, 3, $rest, 0, $rest.Length)
        $body = $rest
    }
    if (@($body | Where-Object { $_ -gt 127 }).Count -gt 0) { [void]$problems.Add("holds bytes that are not ASCII") }
    # Latin-1 maps each byte to one character, so nothing is lost or merged before the lines are split.
    $text = [System.Text.Encoding]::GetEncoding(28591).GetString($body)
    # A CONTROL CHARACTER IS NO PART OF A RECORD: the only bytes below a space it may hold are the ends
    # of its six lines. An escape, a NUL or a backspace in a field was handed on as "written" (measured
    # 2026-10-06 by the review of this reader), to be shown by whatever draws the record.
    if ($text.Replace("`r`n", "`n") -cmatch '[\x00-\x09\x0B-\x1F\x7F]') { [void]$problems.Add("holds a control character") }
    $lines = New-Object System.Collections.ArrayList
    foreach ($l in ($text.Replace("`r`n", "`n") -split "`n")) { [void]$lines.Add($l) }
    while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq "") { $lines.RemoveAt($lines.Count - 1) }
    if ($lines.Count -ne 6) { [void]$problems.Add("has " + $lines.Count + " lines, and a record is 6") }
    if ($lines.Count -eq 0 -or $lines[0] -cne $script:HordeFleetStatusHeader) { [void]$problems.Add("does not begin with the line '" + $script:HordeFleetStatusHeader + "'") }
    $fields = [ordered]@{}
    for ($i = 0; $i -lt $script:HordeFleetStatusKeys.Count; $i++) {
        $key = $script:HordeFleetStatusKeys[$i]
        $at = $i + 1
        if ($at -ge $lines.Count -or -not $lines[$at].StartsWith($key + ": ", [System.StringComparison]::Ordinal) -or $lines[$at].Substring($key.Length + 2).Trim() -eq "") {
            [void]$problems.Add("line " + ($at + 1) + " is not '" + $key + ": ...'")
            continue
        }
        $value = $lines[$at].Substring($key.Length + 2)
        if ($key -ceq "orc" -and $value -cnotmatch '\A[A-Z]\z') { [void]$problems.Add("its orc is not one capital letter") }
        if ($key -ceq "doing" -or $key -ceq "finished") {
            if ($value.Length -gt $script:HordeFleetStatusMostChars) { [void]$problems.Add($key + " is " + $value.Length + " characters, and the most is " + $script:HordeFleetStatusMostChars) }
            if ($value -match $script:HordeFleetStatusBareReference) { [void]$problems.Add($key + " holds a bare reference or a path, where plain words are wanted") }
        }
        $fields[$key] = $value
    }
    if ($problems.Count -gt 0) { return [pscustomobject]@{ problems = @($problems); fields = $null } }
    return [pscustomobject]@{ problems = @(); fields = $fields }
}

function Read-HordeFleetStatusFolder {
    # One Orc's folder, as the plain record the panel shows: { folder; written; problems; orc; lane;
    # doing; finished; blocked; blockedBy; ageSeconds }. When written is false every field of the
    # record is empty: nothing of a file that broke a rule is passed on.
    param([Parameter(Mandatory = $true)][string]$Path, [datetime]$Now = [datetime]::UtcNow)
    $out = [ordered]@{ folder = (Split-Path -Leaf $Path); written = $false; problems = @(); orc = ""; lane = ""; doing = ""; finished = ""; blocked = $false; blockedBy = ""; ageSeconds = -1 }
    $file = Join-Path $Path $script:HordeFleetStatusFile
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { $out.problems = @("there is no " + $script:HordeFleetStatusFile); return [pscustomobject]$out }
    $bytes = $null; $wroteAt = $null
    try {
        $info = New-Object System.IO.FileInfo($file)
        if ($info.Length -gt $script:HordeFleetStatusMostBytes) { $out.problems = @("is " + $info.Length + " bytes, far more than six lines, and was not read"); return [pscustomobject]$out }
        $wroteAt = $info.LastWriteTimeUtc
        # Shared for reading, writing and deleting: an Orc replaces the file whole, and a reader must
        # never be why that fails.
        $stream = [System.IO.File]::Open($file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        try { $bytes = New-Object byte[] $stream.Length; $got = 0; while ($got -lt $bytes.Length) { $n = $stream.Read($bytes, $got, $bytes.Length - $got); if ($n -le 0) { break }; $got += $n } }
        finally { $stream.Dispose() }
    } catch { $out.problems = @("could not be read: " + $_.Exception.Message); return [pscustomobject]$out }
    $out.ageSeconds = [int][Math]::Max(0, [Math]::Floor(($Now.ToUniversalTime() - $wroteAt).TotalSeconds))
    $record = ConvertFrom-HordeFleetStatusBytes -Bytes $bytes
    if ($null -eq $record.fields) { $out.problems = @($record.problems); return [pscustomobject]$out }
    $out.written = $true
    $out.orc = $record.fields["orc"]; $out.lane = $record.fields["lane"]; $out.doing = $record.fields["doing"]; $out.finished = $record.fields["finished"]
    # THE WORD no, IN ANY LETTER CASE, is not blocked; anything else is the sentence saying what stops
    # it. The record's rule 4 writes "no", and an Orc that wrote "No" was shown as blocked, at the
    # highest state, for the reason "No" (measured 2026-10-06 by the review of this reader). Compared
    # by code point with case set aside, so no machine's language reads the word differently.
    if (-not [string]::Equals($record.fields["blocked"].Trim(), "no", [System.StringComparison]::OrdinalIgnoreCase)) { $out.blocked = $true; $out.blockedBy = $record.fields["blocked"].Trim() }
    return [pscustomobject]$out
}

function Get-HordeFleetStatus {
    # Every Orc's record under the folder of status records, as plain data a page shows:
    #   { schemaVersion; state; reason; orcs; notRead; findings }
    # state is read, not-configured or unreadable; orcs is one record per direct subfolder that was
    # read, in the order of their letters and then of their folder names; notRead is how many
    # subfolders were past the most that are read (header) and were only counted; findings is what
    # was wrong in the person's settings file, in sentences. -Folder names the folder for a caller
    # that made it; -Settings is the answer of Get-HordeFleetSettings, read here when it is not given.
    param([string]$Folder = "", [string]$HordeHome = "", $Settings = $null, [datetime]$Now = [datetime]::UtcNow)
    if ($null -eq $Settings) { $Settings = Get-HordeFleetSettings -HordeHome $HordeHome }
    $findings = @($Settings.findings | ForEach-Object { "" + $_ })
    $none = { param([string]$State, [string]$Why) return [pscustomobject]@{ schemaVersion = 1; state = $State; reason = $Why; orcs = @(); notRead = 0; findings = $findings } }
    if ($Folder -eq "") {
        $source = Get-HordeFleetStatusSource -Settings $Settings
        if ($source.state -cne "configured") { return (& $none $source.state $source.reason) }
        $Folder = $source.folder
    }
    $paths = $null
    try { $paths = [string[]]@([System.IO.Directory]::GetDirectories($Folder)) }
    catch { return (& $none "unreadable" ("the folder of status records could not be listed: " + $_.Exception.Message)) }
    # THE SAME FOLDERS EVERY TIME (header): by name, by code point, letter case set aside.
    [System.Array]::Sort($paths, [System.StringComparer]::OrdinalIgnoreCase)
    $most = [int]$Settings.values.statusFoldersRead
    $notRead = [Math]::Max(0, $paths.Length - $most)
    $orcs = @($paths | Select-Object -First $most | ForEach-Object { Read-HordeFleetStatusFolder -Path $_ -Now $Now })
    # TWO FOLDERS, ONE LETTER: neither is shown as that Orc (header).
    foreach ($group in @($orcs | Where-Object { $_.written } | Group-Object -Property orc -CaseSensitive | Where-Object { $_.Count -gt 1 })) {
        # A FEW ARE NAMED AND THE REST COUNTED ($script:HordeFleetStatusMostNamed): every claimant's
        # problem naming every other grew with the square of the folders.
        $claimants = @($group.Group | ForEach-Object { $_.folder })
        $names = @($claimants | Select-Object -First $script:HordeFleetStatusMostNamed) -join ", "
        if ($claimants.Count -gt $script:HordeFleetStatusMostNamed) { $names += " and " + ($claimants.Count - $script:HordeFleetStatusMostNamed) + " more" }
        foreach ($o in $group.Group) {
            $o.written = $false; $o.problems = @("says it is Orc " + $group.Name + ", and so does another folder (" + $names + "), so which is that Orc cannot be told")
            $o.orc = ""; $o.lane = ""; $o.doing = ""; $o.finished = ""; $o.blocked = $false; $o.blockedBy = ""
        }
    }
    $sorted = @($orcs | Sort-Object -Property @{ Expression = { if ($_.written) { 0 } else { 1 } } }, @{ Expression = { $_.orc } }, @{ Expression = { $_.folder } })
    return [pscustomobject]@{ schemaVersion = 1; state = "read"; reason = ""; orcs = $sorted; notRead = $notRead; findings = $findings }
}
