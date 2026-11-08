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
# notice and the warchief one fleet mail; the episode counts as told once the phone's notice was accepted or the
# warchief's own session TOOK his mail (T-0391 slice 8, core/WatchTell.ps1) - the messenger accepting the mail is not
# that. The mail is marked and posted first and kept "posted" in the state; each pass asks whether it was taken,
# and a refused post is tried again at the next pass under the same id. The phone is told only what is known of it. While it stays stale nothing more is said. When the file is fresh again the
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
. (Join-Path $PSScriptRoot "WatchTell.ps1")

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
    # { alerted; since; gen; tell; tellAt } at -Path; a fresh one when there is none or it cannot be read (the worst case is one more alarm).
    # gen is the number of the episode (raised each time one is closed), the generation of the notice ids; tell is "" (the warchief's notice
    # not posted), "posted" (posted and watched, awaiting TAKEN) or "lost" (given up); tellAt when it was posted. A file that cannot be read
    # takes its gen from the clock, so a notice id is never one an earlier episode already used.
    param([Parameter(Mandatory = $true)][string]$Path)
    $s = [pscustomobject]@{ alerted = $false; since = $null; gen = [long]0; tell = ""; tellAt = $null }
    if (-not [System.IO.File]::Exists($Path)) { return $s }
    try {
        $doc = ConvertFrom-HordeJson -Text (Read-HordeSharedText -Path $Path)
        if ($doc -is [System.Management.Automation.PSCustomObject]) {
            if ($doc.alerted -eq $true) { $s.alerted = $true; $s.since = ConvertTo-HordeWatcherTime -Value $doc.since }
            if ($null -ne $doc.PSObject.Properties["gen"]) { $s.gen = [long]$doc.gen }
            $tp = $doc.PSObject.Properties["tell"]
            if ($null -ne $tp -and @("", "posted", "lost") -ccontains ("" + $tp.Value)) { $s.tell = "" + $tp.Value }
            if ($null -ne $doc.PSObject.Properties["tellAt"]) { $s.tellAt = ConvertTo-HordeWatcherTime -Value $doc.tellAt }
        }
    } catch { $s.gen = [long][System.Math]::Floor(([datetime]::UtcNow - ([datetime]"1970-01-01T00:00:00Z").ToUniversalTime()).TotalSeconds) }
    return $s
}

function Write-HordeWatcherBeatState {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$State)
    $o = [ordered]@{ v = 1; alerted = [bool]$State.alerted; since = $null; gen = [long]$State.gen; tell = "" + $State.tell; tellAt = $null }
    if ($State.since -is [datetime]) { $o.since = $State.since.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($State.tellAt -is [datetime]) { $o.tellAt = $State.tellAt.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
    $temp = $Path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    [System.IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $o -Compress), (New-Object System.Text.UTF8Encoding($false)))
    try { Move-HordeFileAtomic -From $temp -To $Path } catch { try { [System.IO.File]::Delete($temp) } catch { }; throw }
}

function Send-HordeWatcherWord {
    # Hand one text to the tool -Name (Notify): { ok; line }. A tool that is $null tells nobody. The warchief's tell is
    # Send-HordeWatchTell (core/WatchTell.ps1): ok there is not "told".
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Who)
    if ($null -eq $Tools[$Name]) { return [pscustomobject]@{ ok = $false; line = ("watcher check: would tell " + $Who + ", but telling is off") } }
    $r = $null
    try { $r = @(& $Tools[$Name] $Text) | Select-Object -Last 1 } catch { $r = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
    $ok = ($null -ne $r -and $r.ok -eq $true)
    return [pscustomobject]@{ ok = $ok; line = ("watcher check: " + $(if ($ok) { "told " + $Who } else { "could not tell " + $Who + ": " + $(if ($null -ne $r) { "" + $r.detail } else { "no answer" }) })) }
}

function Resolve-HordeWatcherTell {
    # THE TAKEN LOOK of a stale episode whose warchief notice is posted or given up (core/WatchTell.ps1): lines. Posted and TAKEN counts the
    # episode as told (alerted); given up leaves it untold and posts nothing more for it; still awaited or unknown changes nothing.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$StatePath, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)][string]$Label)
    if ($State.tell -cne "posted") { return @() }
    $t = Get-HordeWatchTellTaken -Tools $Tools -Key $Key -Gen ([long]$State.gen) -PostedAt $State.tellAt -Now $Now
    if ($t -ceq "taken") {
        Write-HordeWatcherBeatState -Path $StatePath -State ([pscustomobject]@{ alerted = $true; since = $Now; gen = [long]$State.gen; tell = ""; tellAt = $null })
        return @($Label + ": the warchief's session took the notice: he is told")
    }
    if ($t -ceq "lost") {
        Write-HordeWatcherBeatState -Path $StatePath -State ([pscustomobject]@{ alerted = $false; since = $null; gen = [long]$State.gen; tell = "lost"; tellAt = $State.tellAt })
        return @($Label + ": the notice to the warchief was given up unread; he is not told, and none is posted again for this episode")
    }
    return @()
}

function Send-HordeWatcherAlarm {
    # One stale episode's alarm: the warchief's notice is marked and posted FIRST (Send-HordeWatchTell), then the founder's phone is told what
    # is known of it. The episode counts as told when the phone's notice was accepted or, later, the warchief's session TAKES his (the next
    # passes' look). Returns the lines; the state is written here, only when something was posted or told (so a pass that did neither tries again).
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$StatePath, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][string]$PhoneText, [Parameter(Mandatory = $true)][string]$WarchiefBody, [Parameter(Mandatory = $true)][datetime]$Now)
    $w = Send-HordeWatchTell -Tools $Tools -Prefix "watcher check" -Who "the warchief" -Key $Key -Gen ([long]$State.gen) -Text $WarchiefBody
    $n = Send-HordeWatcherWord -Tools $Tools -Name "Notify" -Text ($PhoneText + " " + (Get-HordeWatchTellWords -State $w.state)) -Who "the founder's phone"
    if ($n.ok) { Write-HordeWatcherBeatState -Path $StatePath -State ([pscustomobject]@{ alerted = $true; since = $Now; gen = [long]$State.gen; tell = ""; tellAt = $null }) }
    elseif ($w.state -cne "none") { Write-HordeWatcherBeatState -Path $StatePath -State ([pscustomobject]@{ alerted = $false; since = $null; gen = [long]$State.gen; tell = "posted"; tellAt = $Now }) }
    return @($n.line, $w.line)
}

function Invoke-HordeWatcherHeartbeat {
    # One look at -RunPath: { lines }. -Tools: Now; Tell param($Body, $Key, $Gen) and Taken param($Key, $Gen) (core/WatchTell.ps1); Notify
    # param($Line) answering { ok; detail }; $null for a tool tells nobody. -Policy holds watcherStaleMinutes and watcherHungMinutes.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Policy, [Parameter(Mandatory = $true)][string]$RunPath, [Parameter(Mandatory = $true)][string]$StatePath)
    $lines = New-Object System.Collections.ArrayList
    $now = ([datetime](@(& $Tools["Now"]) | Select-Object -Last 1)).ToUniversalTime()
    $v = Get-HordeWatcherVerdict -Run (Read-HordeWatcherRun -Path $RunPath) -Now $now -Policy $Policy
    $st = Read-HordeWatcherBeatState -Path $StatePath
    if ($v.stale) {
        if ($st.alerted) { return [pscustomobject]@{ lines = @() } }
        # A notice already posted (awaiting TAKEN) or given up is not posted again: only looked at.
        if ($st.tell -cne "") { return [pscustomobject]@{ lines = @(Resolve-HordeWatcherTell -Tools $Tools -State $st -StatePath $StatePath -Key "watcher-stale" -Now $now -Label "watcher check") } }
        [void]$lines.Add("watcher check: STALE (" + $v.kind + ") - " + $v.why)
        $text = "Overseer watcher is stale (" + $v.kind + "): " + $v.why + ". Check the Task Scheduler task 'Fleet overseer watch'."
        foreach ($l in @(Send-HordeWatcherAlarm -Tools $Tools -State $st -StatePath $StatePath -Key "watcher-stale" -PhoneText $text -WarchiefBody ("OVERSEER WATCHER STALE`n" + $text + "`nIts run file is " + $RunPath + ". You are not told again until it has been fresh and goes stale again.") -Now $now)) { [void]$lines.Add($l) }
        return [pscustomobject]@{ lines = @($lines.ToArray()) }
    }
    if ($st.alerted -or $st.tell -cne "") {
        if ($st.alerted) {
            [void]$lines.Add("watcher check: fresh again")
            [void]$lines.Add((Send-HordeWatcherWord -Tools $Tools -Name "Notify" -Text "Overseer watcher is running again." -Who "the founder's phone").line)
        }
        # The episode closes whatever the "back" notice answers: it is a courtesy, the alarm is what matters. The next one has a new number.
        Write-HordeWatcherBeatState -Path $StatePath -State ([pscustomobject]@{ alerted = $false; since = $null; gen = ([long]$st.gen + 1); tell = ""; tellAt = $null })
    }
    return [pscustomobject]@{ lines = @($lines.ToArray()) }
}

function Get-HordeWatcherReaderMessageTime {
    # When the message at -Path was sent, UTC. One whose time cannot be read counts by its file's time: it is still a
    # message nobody took. $null when it is gone: the reader took it after the listing. A missing file's time reads
    # 1601 on .NET, an age of 223 million minutes (review of T-0388), so a reader draining its mail would read as down.
    param([Parameter(Mandatory = $true)][string]$Path)
    $at = $null
    try { $at = ConvertTo-HordeWatcherTime -Value (ConvertFrom-HordeJson -Text (Read-HordeSharedText -Path $Path)).createdAt } catch { }
    if ($null -ne $at) { return $at }
    $t = [System.IO.File]::GetLastWriteTimeUtc($Path)
    if ($t.Year -le 1601) { return $null }
    return $t
}

function Get-HordeWatcherReaderVerdict {
    # { stale; kind; why } for the reader named by -SelfPath (first word: its session id) at -Now. kind: "" |
    # "unknown" (no usable id) | "nomail" (no mail folder) | "unreadable" (its inbox cannot be listed) | "unread".
    param([Parameter(Mandatory = $true)][string]$SelfPath, [Parameter(Mandatory = $true)][string]$MailRoot, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)]$Policy)
    $sid = ""
    try { $sid = (("" + (Read-HordeSharedText -Path $SelfPath)).Trim() -split '\s+')[0] } catch { }
    if ($sid -cnotmatch '\A[A-Za-z0-9-]{8,80}\z') { return [pscustomobject]@{ stale = $true; kind = "unknown"; why = "the file naming the alarm reader is missing or unreadable (" + $SelfPath + ")" } }
    if (-not [System.IO.Directory]::Exists($MailRoot)) { return [pscustomobject]@{ stale = $true; kind = "nomail"; why = "the fleet mail folder is missing (" + $MailRoot + ")" } }
    $limit = [int]$Policy.watcherReaderMinutes
    $utc = $Now.ToUniversalTime()
    $inbox = [System.IO.Path]::Combine($MailRoot, $sid, "inbox")
    $files = @()
    if ([System.IO.Directory]::Exists($inbox)) {
        try { $files = @([System.IO.Directory]::GetFiles($inbox, "*.json")) }
        catch { return [pscustomobject]@{ stale = $true; kind = "unreadable"; why = ("the alarm reader's inbox cannot be listed: " + $_.Exception.Message) } }
    }
    $oldest = $null
    $unread = 0
    foreach ($f in $files) {
        $at = Get-HordeWatcherReaderMessageTime -Path $f
        if ($null -eq $at) { continue }
        $unread++
        if ($null -eq $oldest -or $at -lt $oldest) { $oldest = $at }
    }
    if ($null -eq $oldest) { return [pscustomobject]@{ stale = $false; kind = ""; why = "" } }
    $age = [int][System.Math]::Floor(($utc - $oldest).TotalMinutes)
    if ($age -le $limit) { return [pscustomobject]@{ stale = $false; kind = ""; why = "" } }
    return [pscustomobject]@{ stale = $true; kind = "unread"; why = ("" + $unread + " unread, the oldest " + $age + " minutes old (more than " + $limit + "): it, or the whole fleet, may be down") }
}

function Invoke-HordeWatcherReaderCheck {
    # One look at the alarm reader's inbox: { lines }. -Tools as Invoke-HordeWatcherHeartbeat. -Policy holds watcherReaderMinutes.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Policy, [Parameter(Mandatory = $true)][string]$SelfPath, [Parameter(Mandatory = $true)][string]$MailRoot, [Parameter(Mandatory = $true)][string]$StatePath)
    $now = ([datetime](@(& $Tools["Now"]) | Select-Object -Last 1)).ToUniversalTime()
    $v = Get-HordeWatcherReaderVerdict -SelfPath $SelfPath -MailRoot $MailRoot -Now $now -Policy $Policy
    $st = Read-HordeWatcherBeatState -Path $StatePath
    if ($v.stale -and $st.alerted) { return [pscustomobject]@{ lines = @() } }
    if (-not $v.stale) {
        if ($st.alerted -or $st.tell -cne "") { Write-HordeWatcherBeatState -Path $StatePath -State ([pscustomobject]@{ alerted = $false; since = $null; gen = ([long]$st.gen + 1); tell = ""; tellAt = $null }) }
        return [pscustomobject]@{ lines = @() }
    }
    # A notice already posted (awaiting TAKEN) or given up is not posted again: only looked at.
    if ($st.tell -cne "") { return [pscustomobject]@{ lines = @(Resolve-HordeWatcherTell -Tools $Tools -State $st -StatePath $StatePath -Key "watcher-unread" -Now $now -Label "watcher reader check") } }
    $text = "Overseer alarms are not being read (" + $v.kind + "): " + $v.why + "."
    $sent = @(Send-HordeWatcherAlarm -Tools $Tools -State $st -StatePath $StatePath -Key "watcher-unread" -PhoneText $text -WarchiefBody ("OVERSEER ALARMS UNREAD`n" + $text + "`nYou are not told again until this has cleared and comes back.") -Now $now)
    return [pscustomobject]@{ lines = @(("watcher reader check: STALE (" + $v.kind + ") - " + $v.why), $sent[0], $sent[1]) }
}
