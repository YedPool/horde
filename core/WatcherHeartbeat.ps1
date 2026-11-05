# core/WatcherHeartbeat - is the overseer's watcher still running? Checked from OUTSIDE it, by no model (T-0388).
#
# WHY THIS EXISTS. The overseer watcher (a scheduled task, every 10 minutes) was silently dead from 18:49 to
# 19:56Z on 2026-11-04 and nothing said so. A watcher cannot report its own death, so something else must
# look. The watcher writes <wezfleet root>\_home\orcs\overseer\run.json = {"started": ISO, "finished": ISO}
# on every pass; this file reads it and raises ONE alarm per stale episode.
#
# STALE MEANS (any one of):
#   missing    the file is not there                                     (said as "missing")
#   unreadable the file is not {started, finished} with readable ISO times
#   stopped    "finished" is older than watcherStaleMinutes (30)
#   hung       "started" is newer than "finished" for more than watcherHungMinutes (15): a pass began and never ended
# A pass that is running now, begun less than watcherHungMinutes ago, is not stale.
#
# ONE ALARM PER EPISODE, TOLD ONLY WHEN TAKEN (the rule of core/RelayWatch.ps1): the founder's phone gets one
# notice and the warchief one fleet mail; the episode counts as told once either was taken, so a failed tell is
# tried again at the next pass. While it stays stale nothing more is said. When the file is fresh again the
# episode is closed and one "back" notice is tried, so the next stale spell alarms again.
#
# THE TELLERS ARE HANDED IN (Invoke-HordeWatcherHeartbeat -Tools), as in core/RelayWatch.ps1: a suite uses its
# own recorders and never tells anyone. This file reads one file and starts nothing.
#
# THE READER CHECK (Invoke-HordeWatcherReaderCheck). A running watcher is not enough: its alarms go to one session.
# A restart on 2026-11-05 left that session down 11.6 h while the watcher ran clean, and 9 alarm mails sat unread
# with nobody told. So its inbox is read from here too: mail older than watcherReaderMinutes (120) means nobody is
# reading the alarms. A reader that cannot be identified, or a mail folder that cannot be found, is the same alarm:
# a source that cannot be read must not read as all quiet. One notice per episode, kept in a state file of its own
# so neither check closes the other's episode. No "back" notice: the reader reading its mail needs no news.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "FileAtomic.ps1")

$script:HordeWatcherTimeStyles = ([System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)

function ConvertTo-HordeWatcherTime {
    # A time as the watcher or the state file wrote it: $null when it is not one. PowerShell 7 may already hold an
    # ISO time as a date; a string that names no zone is read as UTC.
    param($Value)
    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime() }
    $t = [datetime]::MinValue
    if ($Value -is [string] -and [datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, $script:HordeWatcherTimeStyles, [ref]$t)) { return $t }
    return $null
}

function Read-HordeWatcherRun {
    # run.json at -Path: { state = "missing" | "unreadable" | "ok"; why; started; finished } (times UTC, or $null).
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return [pscustomobject]@{ state = "missing"; why = "the watcher's run file is missing"; started = $null; finished = $null } }
    $bad = { param($why) return [pscustomobject]@{ state = "unreadable"; why = ("the watcher's run file is unreadable: " + $why); started = $null; finished = $null } }
    $doc = $null
    try { $doc = ConvertFrom-HordeJson -Text (Read-HordeSharedText -Path $Path) } catch { return (& $bad "it is not JSON") }
    if ($doc -isnot [System.Management.Automation.PSCustomObject]) { return (& $bad "it is not an object") }
    $times = @{ started = $null; finished = $null }
    foreach ($k in @("started", "finished")) {
        $p = $doc.PSObject.Properties[$k]
        if ($null -eq $p -or $null -eq $p.Value) { continue }
        $times[$k] = ConvertTo-HordeWatcherTime -Value $p.Value
        if ($null -eq $times[$k]) { return (& $bad ("""" + $k + """ is not an ISO time")) }
    }
    if ($null -eq $times["started"] -and $null -eq $times["finished"]) { return (& $bad "it holds neither ""started"" nor ""finished""") }
    return [pscustomobject]@{ state = "ok"; why = ""; started = $times["started"]; finished = $times["finished"] }
}

function Get-HordeWatcherVerdict {
    # PURE. { stale; kind; why } for one reading at -Now. kind: "" | "missing" | "unreadable" | "stopped" | "hung".
    param([Parameter(Mandatory = $true)]$Run, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)]$Policy)
    $utc = $Now.ToUniversalTime()
    if ($Run.state -ceq "missing" -or $Run.state -ceq "unreadable") { return [pscustomobject]@{ stale = $true; kind = $Run.state; why = $Run.why } }
    $staleMin = [int]$Policy.watcherStaleMinutes
    $hungMin = [int]$Policy.watcherHungMinutes
    $started = $Run.started; $finished = $Run.finished
    if ($started -is [datetime] -and ($finished -isnot [datetime] -or $started -gt $finished)) {
        $age = [int][System.Math]::Floor(($utc - $started).TotalMinutes)
        if ($age -gt $hungMin) { return [pscustomobject]@{ stale = $true; kind = "hung"; why = ("a watcher pass began " + $age + " minutes ago and has not finished (more than " + $hungMin + ")") } }
    }
    if ($finished -isnot [datetime]) { return [pscustomobject]@{ stale = $false; kind = ""; why = "" } }
    $fage = [int][System.Math]::Floor(($utc - $finished).TotalMinutes)
    if ($fage -gt $staleMin) { return [pscustomobject]@{ stale = $true; kind = "stopped"; why = ("the watcher's last pass finished " + $fage + " minutes ago (more than " + $staleMin + ")") } }
    return [pscustomobject]@{ stale = $false; kind = ""; why = "" }
}

function Read-HordeWatcherBeatState {
    # { alerted; since } at -Path; a fresh one when there is none or it cannot be read (the worst case is one more alarm).
    param([Parameter(Mandatory = $true)][string]$Path)
    $s = [pscustomobject]@{ alerted = $false; since = $null }
    if (-not [System.IO.File]::Exists($Path)) { return $s }
    try {
        $doc = ConvertFrom-HordeJson -Text (Read-HordeSharedText -Path $Path)
        if ($doc -is [System.Management.Automation.PSCustomObject] -and $doc.alerted -eq $true) { $s.alerted = $true; $s.since = ConvertTo-HordeWatcherTime -Value $doc.since }
    } catch { }
    return $s
}

function Write-HordeWatcherBeatState {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$State)
    $o = [ordered]@{ v = 1; alerted = [bool]$State.alerted; since = $null }
    if ($State.since -is [datetime]) { $o.since = $State.since.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
    $temp = $Path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    [System.IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $o -Compress), (New-Object System.Text.UTF8Encoding($false)))
    try { Move-HordeFileAtomic -From $temp -To $Path } catch { try { [System.IO.File]::Delete($temp) } catch { }; throw }
}

function Send-HordeWatcherWord {
    # Hand one text to the tool -Name: { ok; line }. A tool that is $null tells nobody.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Who)
    if ($null -eq $Tools[$Name]) { return [pscustomobject]@{ ok = $false; line = ("watcher check: would tell " + $Who + ", but telling is off") } }
    $r = $null
    try { $r = @(& $Tools[$Name] $Text) | Select-Object -Last 1 } catch { $r = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
    $ok = ($null -ne $r -and $r.ok -eq $true)
    return [pscustomobject]@{ ok = $ok; line = ("watcher check: " + $(if ($ok) { "told " + $Who } else { "could not tell " + $Who + ": " + $(if ($null -ne $r) { "" + $r.detail } else { "no answer" }) })) }
}

function Invoke-HordeWatcherHeartbeat {
    # One look at -RunPath: { lines }. -Tools: Now; Tell param($Body) and Notify param($Line), each answering
    # { ok; detail } or $null to tell nobody. -Policy holds watcherStaleMinutes and watcherHungMinutes.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Policy, [Parameter(Mandatory = $true)][string]$RunPath, [Parameter(Mandatory = $true)][string]$StatePath)
    $lines = New-Object System.Collections.ArrayList
    $now = ([datetime](@(& $Tools["Now"]) | Select-Object -Last 1)).ToUniversalTime()
    $v = Get-HordeWatcherVerdict -Run (Read-HordeWatcherRun -Path $RunPath) -Now $now -Policy $Policy
    $st = Read-HordeWatcherBeatState -Path $StatePath
    if ($v.stale) {
        if ($st.alerted) { return [pscustomobject]@{ lines = @() } }
        [void]$lines.Add("watcher check: STALE (" + $v.kind + ") - " + $v.why)
        $text = "Overseer watcher is stale (" + $v.kind + "): " + $v.why + ". Check the Task Scheduler task 'Fleet overseer watch'."
        $n = Send-HordeWatcherWord -Tools $Tools -Name "Notify" -Text $text -Who "the founder's phone"
        $w = Send-HordeWatcherWord -Tools $Tools -Name "Tell" -Text ("OVERSEER WATCHER STALE`n" + $text + "`nIts run file is " + $RunPath + ". You are not told again until it has been fresh and goes stale again.") -Who "the warchief"
        [void]$lines.Add($n.line); [void]$lines.Add($w.line)
        # TOLD ONLY WHEN TAKEN: when neither was taken, the next pass tries again.
        if ($n.ok -or $w.ok) { Write-HordeWatcherBeatState -Path $StatePath -State ([pscustomobject]@{ alerted = $true; since = $now }) }
        return [pscustomobject]@{ lines = @($lines.ToArray()) }
    }
    if ($st.alerted) {
        [void]$lines.Add("watcher check: fresh again")
        [void]$lines.Add((Send-HordeWatcherWord -Tools $Tools -Name "Notify" -Text "Overseer watcher is running again." -Who "the founder's phone").line)
        # The episode closes whatever the "back" notice answers: it is a courtesy, the alarm is what matters.
        Write-HordeWatcherBeatState -Path $StatePath -State ([pscustomobject]@{ alerted = $false; since = $null })
    }
    return [pscustomobject]@{ lines = @($lines.ToArray()) }
}

function Get-HordeWatcherReaderVerdict {
    # { stale; kind; why } for the reader named by -SelfPath (first word: its session id) at -Now. kind: "" |
    # "unknown" (no usable id) | "nomail" (no mail folder) | "unread". A message whose time cannot be read counts
    # by its file's time: it is still a message nobody took.
    param([Parameter(Mandatory = $true)][string]$SelfPath, [Parameter(Mandatory = $true)][string]$MailRoot, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)]$Policy)
    $sid = ""
    try { $sid = (("" + (Read-HordeSharedText -Path $SelfPath)).Trim() -split '\s+')[0] } catch { }
    if ($sid -cnotmatch '\A[A-Za-z0-9-]{8,80}\z') { return [pscustomobject]@{ stale = $true; kind = "unknown"; why = "the file naming the alarm reader is missing or unreadable (" + $SelfPath + ")" } }
    if (-not [System.IO.Directory]::Exists($MailRoot)) { return [pscustomobject]@{ stale = $true; kind = "nomail"; why = "the fleet mail folder is missing (" + $MailRoot + ")" } }
    $limit = [int]$Policy.watcherReaderMinutes
    $utc = $Now.ToUniversalTime()
    $inbox = [System.IO.Path]::Combine($MailRoot, $sid, "inbox")
    $files = @(); if ([System.IO.Directory]::Exists($inbox)) { $files = @([System.IO.Directory]::GetFiles($inbox, "*.json")) }
    $oldest = $null
    foreach ($f in $files) {
        $at = $null
        try { $at = ConvertTo-HordeWatcherTime -Value (ConvertFrom-HordeJson -Text (Read-HordeSharedText -Path $f)).createdAt } catch { }
        if ($null -eq $at) { $at = [System.IO.File]::GetLastWriteTimeUtc($f) }
        if ($null -eq $oldest -or $at -lt $oldest) { $oldest = $at }
    }
    if ($null -eq $oldest) { return [pscustomobject]@{ stale = $false; kind = ""; why = "" } }
    $age = [int][System.Math]::Floor(($utc - $oldest).TotalMinutes)
    if ($age -le $limit) { return [pscustomobject]@{ stale = $false; kind = ""; why = "" } }
    return [pscustomobject]@{ stale = $true; kind = "unread"; why = ("" + $files.Count + " unread, the oldest " + $age + " minutes old (more than " + $limit + "): it, or the whole fleet, may be down") }
}

function Invoke-HordeWatcherReaderCheck {
    # One look at the alarm reader's inbox: { lines }. -Tools as Invoke-HordeWatcherHeartbeat. -Policy holds watcherReaderMinutes.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Policy, [Parameter(Mandatory = $true)][string]$SelfPath, [Parameter(Mandatory = $true)][string]$MailRoot, [Parameter(Mandatory = $true)][string]$StatePath)
    $now = ([datetime](@(& $Tools["Now"]) | Select-Object -Last 1)).ToUniversalTime()
    $v = Get-HordeWatcherReaderVerdict -SelfPath $SelfPath -MailRoot $MailRoot -Now $now -Policy $Policy
    $st = Read-HordeWatcherBeatState -Path $StatePath
    if (-not $v.stale) {
        if ($st.alerted) { Write-HordeWatcherBeatState -Path $StatePath -State ([pscustomobject]@{ alerted = $false; since = $null }) }
        return [pscustomobject]@{ lines = @() }
    }
    if ($st.alerted) { return [pscustomobject]@{ lines = @() } }
    $text = "Overseer alarms are not being read (" + $v.kind + "): " + $v.why + "."
    $n = Send-HordeWatcherWord -Tools $Tools -Name "Notify" -Text $text -Who "the founder's phone"
    $w = Send-HordeWatcherWord -Tools $Tools -Name "Tell" -Text ("OVERSEER ALARMS UNREAD`n" + $text + "`nYou are not told again until this has cleared and comes back.") -Who "the warchief"
    # TOLD ONLY WHEN TAKEN: when neither was taken, the next pass tries again.
    if ($n.ok -or $w.ok) { Write-HordeWatcherBeatState -Path $StatePath -State ([pscustomobject]@{ alerted = $true; since = $now }) }
    return [pscustomobject]@{ lines = @(("watcher reader check: STALE (" + $v.kind + ") - " + $v.why), $n.line, $w.line) }
}
