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
# ONE ALARM PER EPISODE, TOLD ONLY WHEN TAKEN (the rule of core/RelayWatch.ps1, T-0391 slice 8, core/WatchTell.ps1): the warchief's fleet
# mail is marked and posted first, and the episode counts as told only when his own session TOOK it - the messenger accepting it is not that.
# The founder's phone gets one notice that says what is known of the mail (posted and watched, may have been posted, not posted), and one more
# if the mail is later held (not delivered) or given up (not taken in time); a phone that refuses is tried again on every later pass, even
# after TAKEN. The phone accepting does NOT end the watch on the warchief's mail: it is looked at on every pass until it is taken, held or
# given up, and a mail whose result was unknown is posted again under the same id. Only when no mail of his is in play (none posted,
# telling off) does the phone's acceptance alone count the episode as told. While it stays stale nothing more is said. When the file is fresh
# again the episode is closed and one "back" notice is tried, so the next stale spell alarms again with a new notice id. A state file that
# cannot be read is said, never overwritten and never taken for a fresh one.
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

function New-HordeWatcherBeatState {
    # A state with nothing in it. gen is the episode number; tell is "" (the warchief's notice not posted), "posted" (posted and watched,
    # awaiting TAKEN), "maybe" (a post whose result was unknown: it may have landed, is watched, and is posted again under the same id),
    # "held" (the messenger holds it for good: not delivered), "lost" (not taken in time, no longer watched) or "taken"; tellAt when it was FIRST
    # posted (the 7-day give-up counts from then). alerted: the episode counts as told - the warchief's session took his mail, or no mail of his is
    # in play and the phone took the notice, or his mail is held or given up and the phone was told so. phoneAbout: what the phone was last told
    # of the warchief's mail (a Get-HordeWatchTellWords state, or "" for nothing yet; "legacy" for a file made before this field): the phone is
    # told once, and again when the mail is held or given up. seeded and unreadable are the reader's, not stored.
    param([long]$Gen = 0)
    return [pscustomobject]@{ alerted = $false; since = $null; gen = $Gen; tell = ""; tellAt = $null; phoneAbout = ""; seeded = $false; unreadable = $false }
}

function Read-HordeWatcherBeatState {
    # The state at -Path (New-HordeWatcherBeatState). A FRESH state (no file) takes its gen from the clock (-Now, seconds since 1970) and says
    # seeded: a file that was removed must never start again at a number whose notice ids the messenger already holds (it would answer
    # "already posted" for a new episode); the caller writes a seeded state at once, so every retry has the same id. A file that cannot be read
    # says unreadable and is NEVER taken for a fresh one: a live episode in it would be forgotten (the caller says so, and leaves the file).
    param([Parameter(Mandatory = $true)][string]$Path, [datetime]$Now = [datetime]::UtcNow)
    $clock = [long][System.Math]::Floor(($Now.ToUniversalTime() - ([datetime]"1970-01-01T00:00:00Z").ToUniversalTime()).TotalSeconds)
    $s = New-HordeWatcherBeatState -Gen $clock
    if (-not [System.IO.File]::Exists($Path)) { $s.seeded = $true; return $s }
    try {
        $doc = ConvertFrom-HordeJson -Text (Read-HordeSharedText -Path $Path)
        if ($doc -isnot [System.Management.Automation.PSCustomObject]) { throw "it is not an object" }
        $s.gen = [long]0
        if ($doc.alerted -eq $true) { $s.alerted = $true; $s.since = ConvertTo-HordeWatcherTime -Value $doc.since }
        if ($null -ne $doc.PSObject.Properties["gen"]) { $s.gen = [long]$doc.gen }
        $tp = $doc.PSObject.Properties["tell"]
        if ($null -ne $tp) { if (@("", "posted", "maybe", "held", "lost", "taken") -ccontains ("" + $tp.Value)) { $s.tell = "" + $tp.Value } else { throw "tell is not a known value" } }
        if ($null -ne $doc.PSObject.Properties["tellAt"]) { $s.tellAt = ConvertTo-HordeWatcherTime -Value $doc.tellAt }
        $pp = $doc.PSObject.Properties["phoneAbout"]
        if ($null -ne $pp) { if (@("", "posted", "maybe", "copy", "none", "off", "held", "lost", "taken", "legacy") -ccontains ("" + $pp.Value)) { $s.phoneAbout = "" + $pp.Value } else { throw "phoneAbout is not a known value" } }
        elseif ($s.alerted) { $s.phoneAbout = "legacy" }
    } catch { $s = New-HordeWatcherBeatState -Gen 0; $s.unreadable = $true }
    return $s
}

function Write-HordeWatcherBeatState {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$State)
    $o = [ordered]@{ v = 1; alerted = [bool]$State.alerted; since = $null; gen = [long]$State.gen; tell = "" + $State.tell; tellAt = $null; phoneAbout = "" + $State.phoneAbout }
    if ($State.since -is [datetime]) { $o.since = $State.since.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($State.tellAt -is [datetime]) { $o.tellAt = $State.tellAt.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
    $temp = $Path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    [System.IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $o -Compress), (New-Object System.Text.UTF8Encoding($false)))
    try { Move-HordeFileAtomic -From $temp -To $Path } catch { try { [System.IO.File]::Delete($temp) } catch { }; throw }
}

function Get-HordeWatcherBeatStateSeeded {
    # The state at -Path as Read-HordeWatcherBeatState gives it, and a fresh one is written at once (its clock-made gen kept), so the next pass
    # reads the same gen and a retried notice has the same id. An unreadable file is returned as it is and not written over.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][datetime]$Now)
    $st = Read-HordeWatcherBeatState -Path $Path -Now $Now
    if ($st.seeded) { Write-HordeWatcherBeatState -Path $Path -State $st; $st.seeded = $false }
    return $st
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

function Get-HordeWatcherPhoneWords {
    # PURE. What the founder's phone is told of the warchief's mail, in what is known: -State is a Send-HordeWatchTell state, or held, lost, taken.
    param([Parameter(Mandatory = $true)][string]$State)
    if ($State -ceq "held" -or $State -ceq "lost") { return (Get-HordeWatchLostWords -Why $State) }
    if ($State -ceq "taken") { return "A notice to the warchief was taken by his session." }
    return (Get-HordeWatchTellWords -State $State)
}

function Resolve-HordeWatcherTell {
    # THE TAKEN LOOK of a stale episode whose warchief notice is posted (or may be): lines. It changes -State in place and writes nothing (the
    # caller does). TAKEN counts the episode as told (alerted); a notice the messenger holds, or that was given up unread, is left and not posted
    # again; still awaited or unknown changes nothing. The look is made whether or not the phone took the episode.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)][string]$Label)
    if ($State.tell -cne "posted" -and $State.tell -cne "maybe") { return @() }
    $t = Get-HordeWatchTellTaken -Tools $Tools -Key $Key -Gen ([long]$State.gen) -PostedAt $State.tellAt -Now $Now
    if ($t -ceq "taken") {
        $State.alerted = $true; $State.since = $Now; $State.tell = "taken"
        return @($Label + ": the warchief's session took the notice: he is told")
    }
    if ($t -ceq "held" -or $t -ceq "lost") {
        $State.tell = $t
        return @($Label + ": the notice to the warchief " + (Get-HordeWatchLostText -Why $t) + "; he is not told, and none is posted again for this episode")
    }
    return @()
}

function Invoke-HordeWatcherEpisode {
    # What both checks do about one STALE verdict, with the state -St read from -StatePath: the lines; the state is written once, at the end, when it
    # changed. In order:
    #   1. the warchief's notice, if posted (or maybe): is it TAKEN, held, or given up? (Resolve-HordeWatcherTell) - this look is made on every pass
    #      until the episode closes, whatever the phone did;
    #   2. a notice not posted, or one whose result was unknown, is posted (again, same id); a posted one is not;
    #   3. the founder's phone is told what is known of the warchief's mail - once, and once more when that mail is held or given up - and a phone
    #      that refused is tried again on every later pass until it takes it, even after TAKEN;
    #   4. the episode counts as told (alerted) only when the warchief's session TOOK his mail, or when telling is off (there is no Tell tool: no
    #      mail of his is ever in play) and the phone took the notice, or when his mail was held or given up and the phone was told so. A mail
    #      that was REFUSED (a short absence of his seat, say) is posted again, under the same id, on every later pass until it is taken, held or given up.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$St, [Parameter(Mandatory = $true)][string]$StatePath, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][string]$PhoneText, [Parameter(Mandatory = $true)][string]$WarchiefBody, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)][string]$Label)
    $lines = New-Object System.Collections.ArrayList
    $before = ("" + $St.alerted + "|" + $St.tell + "|" + $St.tellAt + "|" + $St.phoneAbout)
    foreach ($l in @(Resolve-HordeWatcherTell -Tools $Tools -State $St -Key $Key -Now $Now -Label $Label)) { [void]$lines.Add($l) }
    $postLine = $null
    $words = "" + $St.tell
    if (-not $St.alerted -and ($St.tell -ceq "" -or $St.tell -ceq "maybe")) {
        $w = Send-HordeWatchTell -Tools $Tools -Prefix "watcher check" -Who "the warchief" -Key $Key -Gen ([long]$St.gen) -Text $WarchiefBody
        $postLine = $w.line
        $words = $w.state
        if ($w.state -ceq "posted" -or $w.state -ceq "maybe") { $St.tell = $w.state; if ($null -eq $St.tellAt) { $St.tellAt = $Now } }
        elseif ($St.tell -ceq "maybe") { $words = "maybe" }
    }
    if ($words -ceq "") { $words = "none" }
    $lost = ($St.tell -ceq "held" -or $St.tell -ceq "lost")
    $needPhone = ($St.phoneAbout -ceq "" -or ($lost -and $St.phoneAbout -cne "held" -and $St.phoneAbout -cne "lost"))
    $phoneLine = $null
    if ($needPhone) {
        $n = Send-HordeWatcherWord -Tools $Tools -Name "Notify" -Text ($PhoneText + " " + (Get-HordeWatcherPhoneWords -State $words)) -Who "the founder's phone"
        $phoneLine = $n.line
        if ($n.ok) { $St.phoneAbout = $words }
    }
    if (-not $St.alerted) {
        $phoneKnows = ($St.phoneAbout -cne "")
        # Only TELLING OFF (no Tell tool) ends it on the phone's accept: a refused mail (none, copy) is posted again, same id, on every later pass.
        $over = (($St.tell -ceq "" -and $phoneKnows -and $words -ceq "off") -or ($lost -and ($St.phoneAbout -ceq "held" -or $St.phoneAbout -ceq "lost")))
        if ($over) { $St.alerted = $true; $St.since = $Now }
    }
    if ($null -ne $phoneLine) { [void]$lines.Add($phoneLine) }
    if ($null -ne $postLine) { [void]$lines.Add($postLine) }
    if ($before -cne ("" + $St.alerted + "|" + $St.tell + "|" + $St.tellAt + "|" + $St.phoneAbout)) { Write-HordeWatcherBeatState -Path $StatePath -State $St }
    return @($lines.ToArray())
}

function Send-HordeWatcherUnreadable {
    # The check's own state file cannot be read: it is NOT overwritten (a live episode in it would be forgotten) and it is NOT silent. A person is
    # told, at most once a day, on the TAKEN rules (core/WatchTell.ps1, Send-HordeWatchDailyTell, its mark beside the state file in <state>.told: mark
    # first, the same id on a retry, a post whose result was unknown posted again, the 7-day give-up from the first post): the warchief's mail, and
    # the founder's phone (<state>.phone holds the day; a phone that refuses is tried again on every pass). The log says it once a day too.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$StatePath, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)][string]$Prefix, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][string]$Subject)
    $lines = New-Object System.Collections.ArrayList
    $text = $Subject + " cannot read its state file, so it is not alarming about the overseer watcher until the file is mended or removed. It is " + $StatePath + "."
    $r = Send-HordeWatchDailyTell -Tools $Tools -MarkPath ($StatePath + ".told") -Prefix $Prefix -Key $Key -Noun "UNREADABLE-STATE notice" -Now $Now -Text ("WATCHER CHECK BLIND`n" + $text)
    if ($r.fresh) { [void]$lines.Add($Prefix + ": its state file cannot be read, so nothing is checked until it is mended or removed (" + $StatePath + ")") }
    foreach ($l in @($r.lines)) { [void]$lines.Add($l) }
    $pm = $StatePath + ".phone"
    $due = (-not [System.IO.File]::Exists($pm)) -or ($Now -ge [System.IO.File]::GetLastWriteTimeUtc($pm).AddHours(24))
    if ($due -and $null -ne $Tools["Notify"]) {
        $words = $(if ($r.state -cne "") { " " + (Get-HordeWatcherPhoneWords -State $r.state) } else { "" })
        $n = Send-HordeWatcherWord -Tools $Tools -Name "Notify" -Text ($text + $words) -Who "the founder's phone"
        [void]$lines.Add($n.line)
        if ($n.ok) { try { [System.IO.File]::WriteAllText($pm, "told"); [System.IO.File]::SetLastWriteTimeUtc($pm, $Now) } catch { } }
    }
    return @($lines.ToArray())
}

function Invoke-HordeWatcherHeartbeat {
    # One look at -RunPath: { lines }. -Tools: Now; Tell param($Body, $Key, $Gen) and Taken param($Key, $Gen) (core/WatchTell.ps1); Notify
    # param($Line) answering { ok; detail }; $null for a tool tells nobody. -Policy holds watcherStaleMinutes and watcherHungMinutes.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Policy, [Parameter(Mandatory = $true)][string]$RunPath, [Parameter(Mandatory = $true)][string]$StatePath)
    $lines = New-Object System.Collections.ArrayList
    $now = ([datetime](@(& $Tools["Now"]) | Select-Object -Last 1)).ToUniversalTime()
    $v = Get-HordeWatcherVerdict -Run (Read-HordeWatcherRun -Path $RunPath) -Now $now -Policy $Policy
    $st = Get-HordeWatcherBeatStateSeeded -Path $StatePath -Now $now
    if ($st.unreadable) { return [pscustomobject]@{ lines = @(Send-HordeWatcherUnreadable -Tools $Tools -StatePath $StatePath -Now $now -Prefix "watcher check" -Key "watcher-unreadable" -Subject "The overseer watcher check") } }
    if ($v.stale) {
        # Done once the episode counts as told AND the phone was told; until then the warchief's mail is looked at and the phone is tried again.
        if ($st.alerted -and $st.phoneAbout -cne "") { return [pscustomobject]@{ lines = @() } }
        if ($st.tell -ceq "" -and -not $st.alerted) { [void]$lines.Add("watcher check: STALE (" + $v.kind + ") - " + $v.why) }
        $text = "Overseer watcher is stale (" + $v.kind + "): " + $v.why + ". Check the Task Scheduler task 'Fleet overseer watch'."
        foreach ($l in @(Invoke-HordeWatcherEpisode -Tools $Tools -St $st -StatePath $StatePath -Key "watcher-stale" -PhoneText $text -WarchiefBody ("OVERSEER WATCHER STALE`n" + $text + "`nIts run file is " + $RunPath + ". You are not told again until it has been fresh and goes stale again.") -Now $now -Label "watcher check")) { [void]$lines.Add($l) }
        return [pscustomobject]@{ lines = @($lines.ToArray()) }
    }
    if ($st.alerted -or $st.tell -cne "" -or $st.phoneAbout -cne "") {
        if ($st.alerted -or $st.phoneAbout -cne "") {
            [void]$lines.Add("watcher check: fresh again")
            [void]$lines.Add((Send-HordeWatcherWord -Tools $Tools -Name "Notify" -Text "Overseer watcher is running again." -Who "the founder's phone").line)
        }
        # The episode closes whatever the "back" notice answers: it is a courtesy, the alarm is what matters. The next one has a new number.
        Write-HordeWatcherBeatState -Path $StatePath -State (New-HordeWatcherBeatState -Gen ([long]$st.gen + 1))
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
    $st = Get-HordeWatcherBeatStateSeeded -Path $StatePath -Now $now
    if ($st.unreadable) { return [pscustomobject]@{ lines = @(Send-HordeWatcherUnreadable -Tools $Tools -StatePath $StatePath -Now $now -Prefix "watcher reader check" -Key "watcher-reader-unreadable" -Subject "The overseer alarm-reader check") } }
    if ($v.stale -and $st.alerted -and $st.phoneAbout -cne "") { return [pscustomobject]@{ lines = @() } }
    if (-not $v.stale) {
        if ($st.alerted -or $st.tell -cne "" -or $st.phoneAbout -cne "") { Write-HordeWatcherBeatState -Path $StatePath -State (New-HordeWatcherBeatState -Gen ([long]$st.gen + 1)) }
        return [pscustomobject]@{ lines = @() }
    }
    $text = "Overseer alarms are not being read (" + $v.kind + "): " + $v.why + "."
    $firstLook = ($st.tell -ceq "" -and -not $st.alerted)
    $sent = @(Invoke-HordeWatcherEpisode -Tools $Tools -St $st -StatePath $StatePath -Key "watcher-unread" -PhoneText $text -WarchiefBody ("OVERSEER ALARMS UNREAD`n" + $text + "`nYou are not told again until this has cleared and comes back.") -Now $now -Label "watcher reader check")
    return [pscustomobject]@{ lines = @($(if ($firstLook) { @("watcher reader check: STALE (" + $v.kind + ") - " + $v.why) } else { @() })) + $sent }
}
