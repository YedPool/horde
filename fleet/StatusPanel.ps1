# fleet/StatusPanel.ps1 - what each Orc says it is doing, read from the small file each one keeps.
#
# THE ONE JOB of this file is to read status records and hand them on as plain data. It knows nothing
# of questions, windows or pages: a panel that shows the data (fleet/panel/) is given it by whoever
# opened the window, and the same data could be printed or sent across a link unchanged.
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
# person: "the fix for garbled mail", not "PR 68"). One rule is this reader's own, because it has no
# table of who sits where: the orc line is ONE capital letter, and two folders that both claim one
# letter are both "no status written", since which is that Orc cannot be told.
#
# WHAT THIS DOES NOT SAY, and the panel must not pretend to: working or idle, sessions open, waiting
# on a person. Those come from the fleet's activity and the list of questions, not from this file.
#
# WHERE THE FILES ARE IS CONFIGURATION, a path and nothing else: <HordeHome>\fleet\status-source.json,
# { "schemaVersion": 1, "folder": "<absolute path>" }, each direct subfolder of which is one Orc's. With
# no such file the answer is "not configured", which is not an error: a machine with no fleet has none.
#
# NOTHING HERE WRITES. Not the configuration, not a status file, not a folder.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")

$script:HordeFleetStatusHeader = "horde-orc-status 1"
$script:HordeFleetStatusKeys = @("orc", "lane", "doing", "finished", "blocked")
$script:HordeFleetStatusFile = "status.txt"
# The longest doing and finished may be, in characters (the record's rule 2).
$script:HordeFleetStatusMostChars = 120
# A record is six short lines. A file far past that is not one, and is not read into memory to find out.
$script:HordeFleetStatusMostBytes = 8192
# A bare pull-request or issue reference, or a Windows path: the record checker's own expression.
$script:HordeFleetStatusBareReference = '(?i)\b(pr|pull request|issue)\s*#?\d+|#\d+|[A-Za-z]:\\'

function Get-HordeFleetStatusSourcePath {
    # Where the configuration is. Worked out, never created.
    param([string]$HordeHome = "")
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    return (Join-Path (Join-Path $HordeHome "fleet") "status-source.json")
}

function Get-HordeFleetStatusSource {
    # The configured folder, as { state; folder; reason }: state is configured, not-configured (there
    # is no configuration file) or unreadable (there is one and it does not name a folder that exists).
    param([string]$HordeHome = "")
    $path = Get-HordeFleetStatusSourcePath -HordeHome $HordeHome
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [pscustomobject]@{ state = "not-configured"; folder = ""; reason = "no folder of status records is configured on this machine" } }
    $config = $null
    try { $config = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $config = $null }
    $bad = { param([string]$Why) return [pscustomobject]@{ state = "unreadable"; folder = ""; reason = ("the configuration of where status records are (" + $path + ") " + $Why) } }
    if ($null -eq $config -or $config -isnot [System.Management.Automation.PSCustomObject]) { return (& $bad "is not a JSON object") }
    $version = $config.PSObject.Properties["schemaVersion"]
    $folder = $config.PSObject.Properties["folder"]
    if ($null -eq $version -or $version.Value -ne 1) { return (& $bad "is not schemaVersion 1") }
    # A FOLDER WINDOWS CANNOT EVEN BE ASKED ABOUT IS UNREADABLE TOO, NEVER A THROW: the caller is a
    # window's tick, and it is promised an answer. Measured 2026-10-06 by the review of this reader: a
    # folder on a machine that does not answer threw "The network path was not found" out of the test
    # for the folder, and a name holding characters no path may threw "Illegal characters in path" out
    # of the test for an absolute one. Both are caught here and said in words.
    try {
        if ($null -eq $folder -or $folder.Value -isnot [string] -or -not [System.IO.Path]::IsPathRooted($folder.Value)) { return (& $bad "does not give an absolute folder") }
        if (-not (Test-Path -LiteralPath $folder.Value -PathType Container -ErrorAction Stop)) { return (& $bad ("names a folder that does not exist: " + $folder.Value)) }
        return [pscustomobject]@{ state = "configured"; folder = [System.IO.Path]::GetFullPath($folder.Value); reason = "" }
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
    # "no", exactly as the record's rule 4 writes it; anything else is the sentence saying what stops it.
    if ($record.fields["blocked"].Trim() -cne "no") { $out.blocked = $true; $out.blockedBy = $record.fields["blocked"].Trim() }
    return [pscustomobject]$out
}

function Get-HordeFleetStatus {
    # Every Orc's record under the configured folder, as plain data a panel shows:
    #   { schemaVersion; state; reason; orcs }
    # state is read, not-configured or unreadable; orcs is one record per direct subfolder, in the order
    # of their letters and then of their folder names. -Folder names the folder for a caller that made it.
    param([string]$Folder = "", [string]$HordeHome = "", [datetime]$Now = [datetime]::UtcNow)
    if ($Folder -eq "") {
        $source = Get-HordeFleetStatusSource -HordeHome $HordeHome
        if ($source.state -cne "configured") { return [pscustomobject]@{ schemaVersion = 1; state = $source.state; reason = $source.reason; orcs = @() } }
        $Folder = $source.folder
    }
    $dirs = $null
    try { $dirs = @(Get-ChildItem -LiteralPath $Folder -Directory -ErrorAction Stop | Sort-Object Name) }
    catch { return [pscustomobject]@{ schemaVersion = 1; state = "unreadable"; reason = ("the folder of status records could not be listed: " + $_.Exception.Message); orcs = @() } }
    $orcs = @($dirs | ForEach-Object { Read-HordeFleetStatusFolder -Path $_.FullName -Now $Now })
    # TWO FOLDERS, ONE LETTER: neither is shown as that Orc (header).
    foreach ($group in @($orcs | Where-Object { $_.written } | Group-Object -Property orc -CaseSensitive | Where-Object { $_.Count -gt 1 })) {
        $names = @($group.Group | ForEach-Object { $_.folder }) -join ", "
        foreach ($o in $group.Group) {
            $o.written = $false; $o.problems = @("says it is Orc " + $group.Name + ", and so does another folder (" + $names + "), so which is that Orc cannot be told")
            $o.orc = ""; $o.lane = ""; $o.doing = ""; $o.finished = ""; $o.blocked = $false; $o.blockedBy = ""
        }
    }
    $sorted = @($orcs | Sort-Object -Property @{ Expression = { if ($_.written) { 0 } else { 1 } } }, @{ Expression = { $_.orc } }, @{ Expression = { $_.folder } })
    return [pscustomobject]@{ schemaVersion = 1; state = "read"; reason = ""; orcs = $sorted }
}
