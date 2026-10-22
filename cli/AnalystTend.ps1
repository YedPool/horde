# cli/AnalystTend - `horde analyst tend`: one pass of the analyst's supervisor - look, decide, act,
# keep the state - and what `horde analyst run` and `horde analyst status` are made of.
#
# THE PASS SPENDS NO TOKENS. It reads files and the process table, and it posts a message only when a
# round is due (core/AnalystRounds.ps1). In order:
#   1. the state, the handover file and (only when a session is known) whether that session is running
#      and how large its context is (core/AnalystSession.ps1);
#   2. what to do about the session: keep it, adopt a fresh one that has written its handover, START a
#      fresh one (gone, or over the cap with a round due), or tell the warchief;
#   3. the acks: a round with no ack after ackMinutes is told to the warchief AND the founder, once;
#   4. the round: the findings since the last place, the warchief's mail, the heartbeat clock.
# The state is written at the end of every pass, and after a start or a post, so a pass that is killed
# loses at most what it was doing.
#
# THE TOOLS ARE HANDED IN (New-HordeAnalystTools), as the supervisor of services takes them
# (cli/ServicesTend.ps1): everything a pass does outside the analyst folder goes through a table of
# script blocks, so a suite runs every path with a clock it moves, a process table it wrote and a
# messenger, a spawner and a notifier that only record - and no suite can wake, start or tell anyone
# by forgetting to stub one. The real table is made only by the command. Each block takes what it
# needs as arguments, never from a closure.
#
# A START IS THE NORMAL SPAWN PATH, NEVER A RESTORE (the warchief's decision 4, 2026-10-14). Horde names
# no terminal and no fleet tool here (CONTRIBUTING 14): the start runs the person's own spawn script,
# the setting spawnScript - an absolute path to a .ps1 the warchief keeps - with fixed arguments: the
# warchief's session id and terminal (core/SessionSeat.ps1), so the new session opens as a tab in the
# warchief's window; the handover file it starts from; and why. With no script set, nothing is ever
# started: the warchief is told, once. Whatever was started, the warchief is told that it was.
#
# A TELL CARRIES NO COMMAND, AND NEVER RIDES A COMMAND LINE (the fleet's interim rule of 2026-10-14, after
# part of a message's text reached a command line and ran). Every tell and round goes through the
# messenger port, whose fleet messenger hands the body over only as a file (-MessageFile; its
# capability body.untyped, messengers/wezfleet/capabilities.json); and the fixed sentences below name
# no runnable command - they say in words where to look.
#
# A TEST'S HOME TELLS NOBODY AND STARTS NOTHING. The real tools refuse a Horde home under the temp
# folder before they look for a messenger, a seat or a script (cli/ServicesTell.ps1, the same guard).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeAnalystTellRole = "warchief"
$script:HordeAnalystFromSession = "horde-analyst"
$script:HordeAnalystTtlSeconds = 604800
$script:HordeAnalystTellNeeds = @("body.untyped", "idempotent.post", "receipt.receiver")
$script:HordeAnalystTakenStages = @("accepted", "handed-over", "seen")
# How long the spawn script may take: the fleet tool waits for the new tab to open, about 30 s for a
# launch on this fleet; three minutes leaves room for a slow, throttled machine.
$script:HordeAnalystSpawnSeconds = 180
# The machine-wide lock every pass holds (Invoke-HordeAnalystLockedPass).
$script:HordeAnalystLockName = "Global\HordeAnalystTend"
# The longest mail to the analyst: a long message belongs in a file the mail names.
$script:HordeAnalystMailMostChars = 20000
# One fixed sentence for each thing the warchief is told (FIXED WORDS, core/AnalystRounds.ps1).
$script:HordeAnalystTellSentences = [ordered]@{
    "no-analyst"             = "No fleet analyst session is known to the supervisor: none has written its handover file. Ask the analyst to write it once; from then on it is supervised."
    "no-spawn-gone"          = "The fleet analyst's session has ended, and no spawn script is set, so nothing was started. Start a fresh analyst; it starts from its handover file."
    "no-spawn-over-cap"      = "The fleet analyst's context is over its cap, and no spawn script is set, so no fresh session was started. Start one; it starts from its handover file."
    "started-gone"           = "The supervisor started a fresh fleet analyst in your window, because the last one's session had ended. It starts from its handover file."
    "started-over-cap"       = "The supervisor started a fresh fleet analyst in your window, because the last one's context was over its cap. The old session gets no more rounds; close it when you choose."
    "spawn-failed"           = "The supervisor's spawn script did not report that a fresh fleet analyst started. It waits for a handover all the same; nothing more is started until one is written or you start one. The status of the analyst supervisor says more."
    "start-silent"           = "A fresh fleet analyst was started and has not written its handover file in the time allowed. Look at its tab; nothing more is started until it does or you start one."
    "start-retry"            = "A fresh fleet analyst was started and no session appeared in the time allowed, so the supervisor started another. After a few tries it stops and tells you. The status of the analyst supervisor says more."
    "start-no-log"           = "A fresh fleet analyst was started, but its spawn script wrote nothing to its spawn log, so it did not run to its start. The next start waits for the bound. The status of the analyst supervisor says more."
    "start-wait-unbounded"   = "A fresh fleet analyst has not appeared in the time allowed, but the supervisor cannot tell whether a session of the analyst is already running, so it starts none and WAITS WITH NO BOUND. Look at the analyst's tabs and start or close one by hand. The status of the analyst supervisor says more."
    "start-late-session"     = "A fresh fleet analyst has not written its handover in the time allowed, but a session started since that is the analyst (by its folder or by its name) is running, so the supervisor starts no other. The session is named below. Look at its tab; it is not stopped."
    "second-analyst"         = "A second fleet analyst session wrote a handover and was not adopted: the supervisor keeps following the session it has, so the second gets no rounds. It is not stopped; close one of the two when you choose."
    "start-too-soon-gone"    = "The fleet analyst's session has ended again within minutes of the last start; no new one is started yet. The status of the analyst supervisor says more."
    "start-too-soon-over-cap" = "The fleet analyst went over its context cap within minutes of the last start; no new one is started yet. The status of the analyst supervisor says more."
    "no-answer"              = "The fleet analyst has not acked a round in the time allowed. The status of the analyst supervisor says more."
    "refused"                = "The analyst's supervisor cannot read one of its own files, so it acts on nothing until a person mends it. The status of the analyst supervisor says more."
}

function New-HordeAnalystTools {
    # The real tools (header). The command fills Post, Tell, Notify and Spawn; $null means "nobody is
    # told, nothing is started", which is what a pass without them does.
    return @{
        Now      = { return [datetime]::UtcNow }
        Identity = { return (Get-HordeIdentity) }
        Length   = { param($Path) try { return [long](New-Object System.IO.FileInfo($Path)).Length } catch { return [long]-1 } }
        Context  = { param($Path) return (Get-HordeAnalystContextTokens -Path $Path) }
        Post     = $null
        Tell     = $null
        Notify   = $null
        Spawn    = $null
        # When the spawn script last wrote spawn.log (beside the handover file): a time, or $null for none.
        SpawnLog = { param($Handover) return (Get-HordeAnalystSpawnLogNewest -Handover $Handover) }
    }
}

function Invoke-HordeAnalystTool {
    # Call one tool and take its LAST output, so a block that leaks a value cannot change the answer.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Name, [object[]]$With = @())
    return (@(& $Tools[$Name] @With) | Select-Object -Last 1)
}

function ConvertTo-HordeAnalystMessageId {
    # A round's message id: a lower-case uuid made from the round id, so a round posted again after a
    # pass that could not record it is the same message, and an idempotent messenger keeps one.
    param([Parameter(Mandatory = $true)][string]$Seed)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try { $h = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("horde-analyst:" + $Seed)) } finally { $md5.Dispose() }
    $h[6] = ($h[6] -band 0x0f) -bor 0x30; $h[8] = ($h[8] -band 0x3f) -bor 0x80
    $x = -join ($h | ForEach-Object { $_.ToString("x2") })
    return ($x.Substring(0, 8) + "-" + $x.Substring(8, 4) + "-" + $x.Substring(12, 4) + "-" + $x.Substring(16, 4) + "-" + $x.Substring(20, 12))
}

function Get-HordeAnalystPolicy {
    # The settings' values with the markers made a list: { ok; reason; values; markers }.
    param([string]$HordeHome = "")
    $s = Get-HordeAnalystSettings -HordeHome $HordeHome
    if ($s.state -ceq "refused") { return [pscustomobject]@{ ok = $false; reason = (@($s.findings) -join " "); values = $null; markers = @() } }
    $mk = Get-HordeAnalystMarkers -Text $s.values.wakeNowMarkers
    if ($mk.state -cne "known") { return [pscustomobject]@{ ok = $false; reason = $mk.reason; values = $null; markers = @() } }
    return [pscustomobject]@{ ok = $true; reason = ""; values = $s.values; markers = [string[]]$mk.value }
}

function Send-HordeAnalystTell {
    # Tell the warchief one thing once: the key goes into the state's told list when the teller took it,
    # and a key already there is not told again. Returns the journal line.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Values, [string]$Extra = "")
    if (@($State.told) -ccontains $Key) { return "" }
    if ($null -eq $Tools["Tell"] -or $Values.tellWarchief -ne $true) { return ("would tell the warchief (" + $Key + "), but telling is off") }
    # A key that names a session (second-analyst-<8 hex>) wears its family's sentence; the session id is in -Extra.
    $sentenceKey = $(if ($Key -cmatch '\Asecond-analyst-') { "second-analyst" } else { $Key })
    $body = "FLEET ANALYST SUPERVISOR`n" + $(if ($script:HordeAnalystTellSentences.Contains($sentenceKey)) { $script:HordeAnalystTellSentences[$sentenceKey] } else { "The fleet analyst needs a person. The status of the analyst supervisor says more." }) + $Extra
    $r = $null
    try { $r = Invoke-HordeAnalystTool -Tools $Tools -Name "Tell" -With @($Key, $body, $Values) } catch { $r = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
    if ($null -ne $r -and $r.ok -eq $true) { $State.told = [string[]]@(@($State.told) + $Key); return ("told the warchief: " + $Key) }
    return ("could not tell the warchief (" + $Key + "): " + $(if ($null -ne $r) { "" + $r.detail } else { "the teller did not answer" }))
}

function Clear-HordeAnalystTold {
    # Forget the told keys whose condition is over, so it is told again if it comes back.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string[]]$Keys)
    $State.told = [string[]]@(@($State.told) | Where-Object { $Keys -cnotcontains $_ })
}

function Invoke-HordeAnalystPass {
    # One pass (header): { lines; problem; state }. lines is the journal of what was done or found;
    # problem is "" or why the pass could not act at all. -Folder is the analyst folder.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Policy, [Parameter(Mandatory = $true)][string]$Folder)
    $lines = New-Object System.Collections.ArrayList
    $say = { param([string]$Line) if ($Line -ne "") { [void]$lines.Add($Line) } }
    $v = $Policy.values
    $paths = Get-HordeAnalystPaths -Folder $Folder
    $sp = Get-HordeAnalystSessionPaths -Folder $Folder
    $now = ([datetime](Invoke-HordeAnalystTool -Tools $Tools -Name "Now")).ToUniversalTime()
    $read = Read-HordeAnalystState -Path $sp.state
    if ($read.state -cne "known") {
        # A state that cannot be read is never taken for no state: that would start a second analyst.
        return [pscustomobject]@{ lines = @("the supervisor's state cannot be read: " + $read.reason); problem = ("the supervisor's state cannot be read, so nothing was done: " + $read.reason); state = $null }
    }
    $s = $read.value
    $handover = Read-HordeAnalystHandover -Path $sp.handover
    if ($handover.state -ceq "unknown") { & $say ("the handover file: " + $handover.reason) }

    # 1. Is the session running, and how large is its context?
    $alive = $null; $context = $null
    if ($s.phase -ceq "running" -and $s.sessionId -ne "") {
        $ident = $null
        try { $ident = Invoke-HordeAnalystTool -Tools $Tools -Name "Identity" } catch { $ident = $null }
        if ($null -eq $ident) { $alive = New-HordeUnknown -Reason "the running sessions could not be read" }
        else {
            $live = Get-HordeAnalystLiveness -SessionId $s.sessionId -Identity $ident
            $alive = $live.alive
            if ($alive.state -ceq "known" -and $alive.value -eq $true -and $live.transcript.state -ceq "known") {
                # Read again only when the transcript has grown: a quiet session costs one file length.
                $len = [long](Invoke-HordeAnalystTool -Tools $Tools -Name "Length" -With @("" + $live.transcript.value))
                if ($len -ge 0 -and $len -ne $s.transcriptLength) {
                    $c = $null
                    try { $c = Invoke-HordeAnalystTool -Tools $Tools -Name "Context" -With @("" + $live.transcript.value) } catch { $c = New-HordeUnknown -Reason "the transcript could not be read" -ErrorRecord $_ }
                    if ($null -ne $c -and $c.state -ceq "known") { $s.contextTokens = [long]$c.value.tokens; $s.contextAt = $c.value.at; $s.transcriptLength = $len }
                    elseif ($null -ne $c -and $c.state -ceq "unknown") { & $say ("its context could not be read: " + $c.reason) }
                }
            }
        }
        if ($s.contextTokens -ge 0) { $context = New-HordeKnown -Value ([pscustomobject]@{ tokens = $s.contextTokens }) }
    }
    # A turn the transcript shows is a wake too, whoever caused it: the heartbeat counts from the newest.
    if ($s.contextAt -is [datetime] -and ($null -eq $s.lastWakeAt -or $s.contextAt -gt $s.lastWakeAt)) { $s.lastWakeAt = $s.contextAt }

    # 2. What is waiting, and is a round due? Read before the session decision: a fresh session is
    #    started only when there is something to hand it (the cap) or nothing is running (gone).
    $f = Read-HordeAnalystFindings -Path $paths.findings -Offset $s.findingsOffset
    $mail = Read-HordeAnalystMail -Folder $paths.mail -Markers $Policy.markers
    $findings = @(); $mailItems = @()
    if ($f.state -ceq "known") { $findings = @($f.value.items); if ($f.value.restarted) { & $say "the findings file was replaced: read from its start" } } else { & $say ("the findings: " + $f.reason) }
    if ($mail.state -ceq "known") { $mailItems = @($mail.value) } else { & $say ("the warchief's mail: " + $mail.reason) }
    $round = Get-HordeAnalystRoundDecision -Now $now -LastRoundAt $s.lastRoundAt -LastWakeAt $s.lastWakeAt -Findings $findings -Mail $mailItems -Policy $v
    $due = ($round.action -cne "none")

    # 3. The session.
    $canStart = ("" + $v.spawnScript -ne "" -and $null -ne $Tools["Spawn"])
    # Did the spawn script log anything for the start in progress? $null when nobody asked (no tool, or no
    # start in progress), so a suite or a home without the tool is never failed for a log it cannot read.
    $spawnLogged = $null
    if ($s.phase -ceq "starting" -and $s.startedAt -is [datetime] -and $null -ne $Tools["SpawnLog"]) {
        $logAt = $null; $asked = $true
        try { $logAt = Invoke-HordeAnalystTool -Tools $Tools -Name "SpawnLog" -With @($sp.handover) } catch { $asked = $false }
        if ($asked -and $null -eq $logAt) { $spawnLogged = $false } elseif ($asked -and $logAt -is [datetime]) { $spawnLogged = ($logAt.ToUniversalTime() -ge $s.startedAt.AddMinutes(-1)) }
    }
    # Is the session this start replaced running again (resumed by hand under its old id), and is there a
    # session started since this start that may be its own? Both are asked of ONE reading of who is running;
    # an unreadable one is unknown for both, and an unknown is never a start. $null when no start is in progress.
    $previousAlive = $null; $late = $null
    if ($s.phase -ceq "starting") {
        $identStart = $null
        try { $identStart = Invoke-HordeAnalystTool -Tools $Tools -Name "Identity" } catch { $identStart = $null }
        if ("" + $s.previousSessionId -ne "") {
            if ($null -eq $identStart) { $previousAlive = New-HordeUnknown -Reason "the running sessions could not be read" }
            else { $previousAlive = (Get-HordeAnalystLiveness -SessionId ("" + $s.previousSessionId) -Identity $identStart).alive }
        }
        $lateSince = $(if ($s.startedAt -is [datetime]) { [datetime]$s.startedAt } else { $now.AddYears(-1) })
        $late = Get-HordeAnalystLateSessions -Identity $identStart -Since $lateSince -Exclude @("" + $s.previousSessionId) -Folder $Folder
    }
    $d = Get-HordeAnalystSessionDecision -State $s -Alive $alive -Handover $handover -Context $context -Now $now -Policy $v -RoundDue $due -CanStart $canStart -SpawnLogged $spawnLogged -PreviousAlive $previousAlive -Late $late
    switch -CaseSensitive ($d.action) {
        "adopt" {
            & $say ("adopted session " + $d.sessionId + ": " + $d.why)
            $s.sessionId = $d.sessionId; $s.phase = "running"; $s.contextTokens = [long]-1; $s.transcriptLength = [long]-1; $s.contextAt = $null; $s.startAttempts = [long]0
            # A NEW SESSION STARTS A NEW RUN (review of PR 306): the last one's untold-until-ack "no-answer"
            # would silence a fresh session that writes its handover and never acks. Its old rounds stay
            # marked alerted, so clearing here tells nothing about them again.
            Clear-HordeAnalystTold -State $s -Keys @("no-analyst", "start-silent", "no-spawn-gone", "no-spawn-over-cap", "spawn-failed", "start-too-soon-gone", "start-too-soon-over-cap", "start-retry", "start-no-log", "start-wait-unbounded", "start-late-session", "no-answer", "no-answer-founder")
            # It was awake when it wrote the handover: a session that has just said who it is is not
            # sent a heartbeat for having been silent before the supervisor knew it.
            # (A replaced session found running again may have no handover to read.)
            if ($handover.state -ceq "known" -and $handover.value.sessionId -ceq $d.sessionId -and ($null -eq $s.lastWakeAt -or $handover.value.writtenAt -gt $s.lastWakeAt)) { $s.lastWakeAt = $handover.value.writtenAt }
            $round = Get-HordeAnalystRoundDecision -Now $now -LastRoundAt $s.lastRoundAt -LastWakeAt $s.lastWakeAt -Findings $findings -Mail $mailItems -Policy $v
            $due = ($round.action -cne "none")
        }
        "start" {
            # STARTING IS WRITTEN BEFORE THE SPAWN RUNS (review of PR 306): a pass killed while the spawn
            # script runs - a service restarted for an update, up to $script:HordeAnalystSpawnSeconds -
            # leaves the script going, and the next pass must find "starting", not "running and gone".
            # A RETRY (T-0341) keeps the session it replaced: the sessionId is already empty, and overwriting
            # previousSessionId with it would let the old session's handover be taken for the new one's.
            if ($d.retry -ne $true) { $s.previousSessionId = $s.sessionId }
            $s.startAttempts = $(if ($d.retry -eq $true) { [Math]::Max([long]1, [long]$s.startAttempts) + 1 } else { [long]1 })
            $s.sessionId = ""; $s.phase = "starting"; $s.startedAt = $now; $s.startReason = $d.reason
            $s.contextTokens = [long]-1; $s.transcriptLength = [long]-1; $s.contextAt = $null
            Clear-HordeAnalystTold -State $s -Keys @("started-gone", "started-over-cap", "spawn-failed", "start-silent", "start-retry", "start-no-log", "start-wait-unbounded", "start-late-session")
            if ($d.retry -eq $true) { & $say ("the last start failed: " + $d.why) }
            Write-HordeAnalystState -Path $sp.state -State $s
            $r = $null
            try { $r = Invoke-HordeAnalystTool -Tools $Tools -Name "Spawn" -With @(("" + $v.spawnScript), $sp.handover, $d.reason, $v) } catch { $r = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
            if ($null -ne $r -and $r.ok -eq $true) {
                & $say ("started a fresh analyst session: " + $d.why)
                # A retry is told as a retry (d.tell), not also as a start.
                if ($d.retry -ne $true) { & $say (Send-HordeAnalystTell -State $s -Key ("started-" + $d.reason) -Tools $Tools -Values $v) }
            } else {
                # A SPAWN THAT FAILED OR TIMED OUT MAY STILL HAVE STARTED ONE: its child can go on after the
                # timeout, and a non-zero exit can follow a tab that opened. So it stays "starting" and
                # waits for a handover (startWaitMinutes, then the warchief is told) - it is never taken
                # for "nothing happened", which would start a second session later.
                & $say ("the spawn script did not report success: " + $(if ($null -ne $r) { "" + $r.detail } else { "it did not answer" }) + "; waiting for a handover all the same")
                & $say (Send-HordeAnalystTell -State $s -Key "spawn-failed" -Tools $Tools -Values $v)
            }
        }
        default { if ($d.action -cne "keep") { & $say ($d.action + ": " + $d.why) } }
    }
    # A SECOND ANALYST THAT WROTE A HANDOVER IS NEVER SILENTLY IGNORED (T-0341): once the session in hand is
    # running, a handover written since the last start by another session (not the one it replaced) is a second
    # analyst - a slow first spawn that came up after the replaced session was adopted. It is not stopped, and
    # the warchief is told once, naming it.
    if ($s.phase -ceq "running" -and $d.action -ceq "keep" -and $handover.state -ceq "known" -and $s.startedAt -is [datetime] -and
        $handover.value.sessionId -cne $s.sessionId -and $handover.value.sessionId -cne ("" + $s.previousSessionId) -and $handover.value.writtenAt -ge $s.startedAt.AddMinutes(-1)) {
        & $say ("session " + $handover.value.sessionId + " wrote a handover but is not the analyst this supervisor follows (" + $s.sessionId + "); it is not stopped")
        & $say (Send-HordeAnalystTell -State $s -Key ("second-analyst-" + $handover.value.sessionId.Substring(0, 8)) -Tools $Tools -Values $v -Extra ("`nSession: " + $handover.value.sessionId))
    }
    if ($d.tell -ne "") { & $say (Send-HordeAnalystTell -State $s -Key $d.tell -Tools $Tools -Values $v -Extra ("" + $d.extra)) }

    # 4. Rounds with no ack: told ONCE for a run of them (review of PR 306: a wedged session that is still
    #    alive gets a round every half hour, and telling each one was up to 48 alerts a day). The run ends,
    #    and the next one may be told, only when an ack arrives: a round newer than the last ack seen.
    $acks = Read-HordeAnalystAcks -Path $paths.acks
    if ($acks.state -ceq "known") {
        $ackedIds = [string[]]$acks.value
        $newestAcked = @($s.rounds | Where-Object { $ackedIds -ccontains $_.id } | Sort-Object at | Select-Object -Last 1)
        if ($newestAcked.Count -eq 1 -and $newestAcked[0].id -cne $s.lastAckId) { $s.lastAckId = $newestAcked[0].id; Clear-HordeAnalystTold -State $s -Keys @("no-answer", "no-answer-founder") }
        $late = @(Get-HordeAnalystAckAlerts -Now $now -Rounds @($s.rounds) -Acked $ackedIds -Policy $v)
        foreach ($id in $late) {
            $one = @($s.rounds | Where-Object { $_.id -ceq $id })[0]
            $one.alerted = $true
            & $say ("round " + $id + " has no ack after " + $v.ackMinutes + " minutes")
            if (-not (@($s.told) -ccontains "no-answer")) { & $say (Send-HordeAnalystTell -State $s -Key "no-answer" -Tools $Tools -Values $v -Extra ("`nRound: " + $id)) }
            # THE FOUNDER'S NOTICE HAS ITS OWN TOLD KEY (review of PR 306): tied to the warchief's tell, telling
            # switched off or fleet mail failing left "no-answer" untold, so every late round notified the
            # founder again - up to 48 a day - each saying the warchief was told when he was not.
            if ((@($s.told) -ccontains "no-answer-founder") -or $null -eq $Tools["Notify"] -or $v.notifyFounder -ne $true) { continue }
            $warchief = $(if (@($s.told) -ccontains "no-answer") { "the warchief was told." } else { "the warchief was not told." })
            $n = $null
            try { $n = Invoke-HordeAnalystTool -Tools $Tools -Name "Notify" -With @(("The fleet analyst has not answered round " + $id + " for " + $v.ackMinutes + " minutes; " + $warchief)) } catch { $n = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
            if ($null -ne $n -and $n.ok -eq $true) { $s.told = [string[]]@(@($s.told) + "no-answer-founder"); & $say ("told the founder: no answer to round " + $id + "; " + $warchief) }
            else { & $say ("could not tell the founder: " + $(if ($null -ne $n) { "" + $n.detail } else { "the notifier did not answer" })) }
        }
    } else { & $say ("the acks: " + $acks.reason) }

    # 5. The round, to a session that is running and was not just replaced.
    $target = $(if ($s.phase -ceq "running" -and $d.action -ceq "keep" -or $d.action -ceq "adopt") { $s.sessionId } else { "" })
    $over = ($null -ne $context -and [long]$context.value.tokens -gt [long]$v.contextCapTokens -and $d.action -ceq "keep")
    # An unreadable findings file holds back nothing else (review of PR 306): the mail and the heartbeat
    # still go, and the findings' place is kept until the file can be read.
    if ($due -and $target -ne "" -and -not $over) {
        $id = New-HordeAnalystRoundId -Now $now -Kind $round.action
        $carried = @($mailItems | Where-Object { @($round.mail) -ccontains $_.id })
        $moved = New-Object System.Collections.ArrayList
        $moveProblem = ""
        foreach ($m in $carried) {
            try { [void][System.IO.Directory]::CreateDirectory($paths.delivered); [System.IO.File]::Move($m.path, [System.IO.Path]::Combine($paths.delivered, [System.IO.Path]::GetFileName($m.path))); [void]$moved.Add($m) }
            catch { $moveProblem = $_.Exception.Message; break }
        }
        $unreadable = @($findings | Where-Object { "" + $_.bad -ne "" -and @($round.findings) -ccontains $_.id }).Count
        $body = Format-HordeAnalystRoundBody -Id $id -Kind $round.action -Findings @($round.findings).Count -Unreadable $unreadable -MailIds ([string[]]@($moved | ForEach-Object { $_.id })) -Markers ([string[]]@($moved | Where-Object { $_.marker -ne "" } | ForEach-Object { $_.marker })) -Paths $paths -Handover $sp.handover -FromOffset $s.findingsOffset
        $r = $null
        if ($moveProblem -eq "") {
            if ($null -eq $Tools["Post"]) { $r = [pscustomobject]@{ ok = $false; woken = $false; detail = "posting is off" } }
            else { try { $r = Invoke-HordeAnalystTool -Tools $Tools -Name "Post" -With @($target, (ConvertTo-HordeAnalystMessageId -Seed $id), $body, $v) } catch { $r = [pscustomobject]@{ ok = $false; woken = $false; detail = $_.Exception.Message } } }
        }
        if ($null -ne $r -and $r.ok -eq $true) {
            $s.rounds = @(@($s.rounds) + [pscustomobject]@{ id = $id; kind = $round.action; at = $now; sessionId = $target; alerted = $false; woken = $(if ($r.woken -eq $true) { "yes" } else { "no" }) })
            $s.lastRoundAt = $now; $s.lastWakeAt = $now
            if ($f.state -ceq "known") { $s.findingsOffset = [long]$f.value.offset }
            & $say ("sent round " + $id + " (" + $round.action + "): " + $round.why + $(if ($r.woken -eq $true) { "" } else { "; posted, not woken: " + $r.detail }))
        } else {
            # Put the mail back, so the next pass carries it again.
            foreach ($m in $moved) { try { [System.IO.File]::Move([System.IO.Path]::Combine($paths.delivered, [System.IO.Path]::GetFileName($m.path)), $m.path) } catch { } }
            & $say ("round not sent: " + $(if ($moveProblem -ne "") { "a mail could not be moved: " + $moveProblem } elseif ($null -ne $r) { "" + $r.detail } else { "the poster did not answer" }))
        }
    } elseif ($due -and $over) { & $say ("a round is due and the analyst is over its context cap: it waits for the fresh session") }
    elseif ($due -and $target -eq "") { & $say ("a round is due and no running analyst can take it: it waits") }
    Write-HordeAnalystState -Path $sp.state -State $s
    return [pscustomobject]@{ lines = @($lines.ToArray()); problem = ""; state = $s }
}

function Invoke-HordeAnalystLockedPass {
    # ONE PASS AT A TIME ON THIS MACHINE (review of PR 306): a hand `horde analyst tend` while `run` is
    # passing would read the same "running and gone" and both would run the spawn script - two analysts.
    # So every pass, the loop's and a hand one, holds the machine-wide named mutex -LockName for its whole
    # length. A pass that cannot have it within -WaitSeconds does nothing and says so; a spawn holds it up
    # to $script:HordeAnalystSpawnSeconds, so a hand tend then is told to try again. An abandoned mutex (a
    # pass killed while holding it) is taken: the state that pass wrote is what this one reads.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Policy, [Parameter(Mandatory = $true)][string]$Folder,
          [string]$LockName = $script:HordeAnalystLockName, [int]$WaitSeconds = 30)
    $mutex = New-Object System.Threading.Mutex($false, $LockName)
    $held = $false
    try {
        try { $held = $mutex.WaitOne([System.TimeSpan]::FromSeconds($WaitSeconds)) } catch [System.Threading.AbandonedMutexException] { $held = $true }
        if (-not $held) { return [pscustomobject]@{ lines = @("another pass of the analyst's supervisor is running on this machine; this one did nothing"); problem = ""; state = $null; skipped = $true } }
        $done = Invoke-HordeAnalystPass -Tools $Tools -Policy $Policy -Folder $Folder
        return [pscustomobject]@{ lines = $done.lines; problem = $done.problem; state = $done.state; skipped = $false }
    } finally {
        if ($held) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Test-HordeAnalystHomeIsATests {
    # Is -HordeHome under the temp folder? A home that cannot be resolved is taken as a test's.
    param([string]$HordeHome, [string]$TempRoot = "")
    if ($TempRoot -eq "") { $TempRoot = [System.IO.Path]::GetTempPath() }
    try {
        $rootFull = [System.IO.Path]::GetFullPath($TempRoot).TrimEnd('\', '/') + '\'
        $full = [System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\', '/') + '\'
        return [bool]$full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
    } catch { return $true }
}

function Get-HordeAnalystSpawnArguments {
    # PURE. The command line the spawn script is run with: fixed parameter names, and values that are
    # each a session id, a pane or terminal word, an absolute path or one of two reasons - checked here,
    # so nothing that could be read as another parameter, or a second command, reaches the line.
    param([Parameter(Mandatory = $true)][string]$Script, [Parameter(Mandatory = $true)]$Seat, [Parameter(Mandatory = $true)][string]$Handover, [Parameter(Mandatory = $true)][ValidateSet("gone", "over-cap")][string]$Reason)
    if (-not [System.IO.Path]::IsPathRooted($Script) -or $Script -notmatch '\.ps1\z' -or $Script -match '["\r\n]') { throw "the spawn script is an absolute path to a .ps1" }
    if (-not [System.IO.Path]::IsPathRooted($Handover) -or $Handover -match '["\r\n]') { throw "the handover file is an absolute path" }
    if ("" + $Seat.sessionId -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') { throw "the warchief's session id is not a session id" }
    foreach ($w in @(("" + $Seat.pane), ("" + $Seat.instance))) { if ($w -cnotmatch '\A[A-Za-z0-9._-]{1,64}\z') { throw "the warchief's pane or terminal is not a plain word" } }
    return ("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + $Script + "`" -ParentSessionId " + $Seat.sessionId + " -ParentPane " + $Seat.pane + " -ParentInstance " + $Seat.instance + " -Handover `"" + $Handover + "`" -Reason " + $Reason)
}

function Get-HordeAnalystSpawnLogNewest {
    # When the spawn script last wrote spawn.log, the file beside the handover file (the spawn script
    # appends "<yyyyMMddTHHmmssZ> <what>" to it, one line per step): a UTC time; $null for no file or no
    # line (a start with no entry); the string "unreadable" for a file whose last line does not open with a stamp, or that cannot be read (not asked, never a failure). Only the end of the file is read.
    param([Parameter(Mandatory = $true)][string]$Handover)
    $log = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Handover), "spawn.log")
    $stream = $null
    try {
        $stream = New-Object System.IO.FileStream($log, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $take = [int][Math]::Min([long]4096, $stream.Length)
        [void]$stream.Seek(-$take, [System.IO.SeekOrigin]::End)
        $buf = New-Object byte[] $take
        $got = $stream.Read($buf, 0, $take)
        $last = @([System.Text.Encoding]::ASCII.GetString($buf, 0, $got).Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } | Select-Object -Last 1)
        if ($last.Count -eq 0) { return $null }
        $m = [regex]::Match($last[0], '\A([0-9]{8}T[0-9]{6}Z) ')
        if (-not $m.Success) { return "unreadable" }
        return [datetime]::ParseExact($m.Groups[1].Value, "yyyyMMdd'T'HHmmss'Z'", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
    } catch { $cause = $_.Exception.GetBaseException(); if ($cause -is [System.IO.FileNotFoundException] -or $cause -is [System.IO.DirectoryNotFoundException]) { return $null }; return "unreadable" } finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Resolve-HordeAnalystTerminal {
    # THE TERMINAL A SPAWN TARGETS, as an answer: known { instance; replaced } or unknown with why.
    # -Recorded is the terminal the warchief's record names; a record outlives its terminal (2026-10-19 the
    # last launch went to a terminal that was gone by 2026-10-20), so it is never used as it stands. Each
    # terminal adapter's Own block (core/HostAct.ps1) names the one terminal of this user that is running,
    # or says why it cannot; its socket's file name is the instance the spawn script is given. The recorded
    # one is kept only when it is that terminal; a different live one replaces it; none (or several, which the
    # adapter refuses to choose between) is a failure with the adapter's own reason. -Actors are
    # Get-HordeHostActors' rows; a suite hands in its own.
    param([AllowEmptyString()][string]$Recorded, [object[]]$Actors = @())
    $why = New-Object System.Collections.ArrayList
    foreach ($actor in @($Actors)) {
        $own = $null
        try { $own = & $actor.own } catch { $own = New-HordeUnknown -Reason $_.Exception.Message }
        if ($null -ne $own -and $own.state -ceq "known" -and "" + $own.value.socket -ne "") {
            $live = Split-Path -Leaf ("" + $own.value.socket)
            return (New-HordeKnown -Value ([pscustomobject]@{ instance = $live; replaced = ($live -cne $Recorded) }))
        }
        [void]$why.Add($(if ($null -ne $own -and $own.state -ceq "unknown") { "" + $own.reason } else { "its terminal could not be named" }))
    }
    if ($why.Count -eq 0) { [void]$why.Add("no terminal adapter is loaded") }
    return (New-HordeUnknown -Reason (($why -join "; ") + " (the recorded terminal '" + $Recorded + "' is not used unchecked)"))
}

function Invoke-HordeAnalystSpawnProcess {
    # THE REAL RUN of the spawn script's command line: { exitCode; timedOut }. At most -Seconds to return.
    param([Parameter(Mandatory = $true)][string]$Line, [Parameter(Mandatory = $true)][int]$Seconds)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = $Line
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        if (-not $p.WaitForExit($Seconds * 1000)) { return [pscustomobject]@{ exitCode = -1; timedOut = $true } }
        return [pscustomobject]@{ exitCode = [int]$p.ExitCode; timedOut = $false }
    } finally { $p.Dispose() }
}

function Start-HordeAnalystSession {
    # THE REAL SPAWN (header): run the person's spawn script with the warchief's seat, the handover file
    # and why; { ok; detail }. The script is given at most $script:HordeAnalystSpawnSeconds to return.
    # T-0341: the terminal in the seat is checked (-ResolveTerminal, Resolve-HordeAnalystTerminal) and the
    # live one is passed, and a script that returns without writing a spawn.log line beside the handover
    # file did not run to its start, whatever its exit code says. -FindSeat and -RunScript are for a suite.
    param([Parameter(Mandatory = $true)][string]$Script, [Parameter(Mandatory = $true)][string]$Handover, [Parameter(Mandatory = $true)][string]$Reason,
          [Parameter(Mandatory = $true)][scriptblock]$ResolveTerminal, [scriptblock]$FindSeat = $null, [scriptblock]$RunScript = $null)
    if (-not [System.IO.File]::Exists($Script)) { return [pscustomobject]@{ ok = $false; detail = "the spawn script is not there" } }
    $seat = $null
    if ($null -ne $FindSeat) { $seat = & $FindSeat } else { $seat = Get-HordeRoleSeat -Role $script:HordeAnalystTellRole }
    if ($seat.state -cne "known") { return [pscustomobject]@{ ok = $false; detail = ("the warchief's window cannot be found: " + $(if ($seat.state -ceq "absent") { $seat.note } else { $seat.reason })) } }
    $terminal = & $ResolveTerminal ("" + $seat.value.instance)
    if ($terminal.state -cne "known") { return [pscustomobject]@{ ok = $false; detail = ("no live terminal to start it in: " + $terminal.reason) } }
    $target = [pscustomobject]@{ sessionId = $seat.value.sessionId; pane = $seat.value.pane; instance = $terminal.value.instance }
    $line = $null
    try { $line = Get-HordeAnalystSpawnArguments -Script $Script -Seat $target -Handover $Handover -Reason $Reason } catch { return [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
    $logPath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Handover), "spawn.log")
    $before = [long]0
    try { if ([System.IO.File]::Exists($logPath)) { $before = (New-Object System.IO.FileInfo($logPath)).Length } } catch { $before = [long]0 }
    $ran = $null
    if ($null -ne $RunScript) { $ran = & $RunScript $line $script:HordeAnalystSpawnSeconds } else { $ran = Invoke-HordeAnalystSpawnProcess -Line $line -Seconds $script:HordeAnalystSpawnSeconds }
    $after = [long]0
    try { if ([System.IO.File]::Exists($logPath)) { $after = (New-Object System.IO.FileInfo($logPath)).Length } } catch { $after = [long]0 }
    $how = $(if ($ran.timedOut -eq $true) { "it did not return in " + $script:HordeAnalystSpawnSeconds + " s" } elseif ($ran.exitCode -ne 0) { "it exited " + $ran.exitCode } else { "it exited 0" })
    if ($after -le $before) { return [pscustomobject]@{ ok = $false; detail = ("the spawn script wrote no entry to spawn.log (" + $logPath + "), so it did not run to its start (" + $how + ")") } }
    if ($ran.timedOut -eq $true) { return [pscustomobject]@{ ok = $false; detail = ("the spawn script did not return in " + $script:HordeAnalystSpawnSeconds + " s") } }
    if ($ran.exitCode -ne 0) { return [pscustomobject]@{ ok = $false; detail = ("the spawn script exited " + $ran.exitCode) } }
    return [pscustomobject]@{ ok = $true; detail = "" }
}

function New-HordeAnalystSpawnTool {
    # The Spawn tool of the real command: a block that runs Start-HordeAnalystSession with the terminal found
    # by asking the loaded terminal adapters (Get-HordeHostActors, core/HostAct.ps1). It is a function so a suite
    # can make the very block the command uses and call it from another scope: the adapters' functions are found
    # by the CALLER's scope chain, not where the block was written (T-0341 review). -FindSeat and -RunScript
    # are a suite's doubles; the command passes neither.
    param([scriptblock]$FindSeat = $null, [scriptblock]$RunScript = $null)
    return {
        param($Script, $Handover, $Reason, $Values)
        $resolve = { param($Recorded) return (Resolve-HordeAnalystTerminal -Recorded $Recorded -Actors @(Get-HordeHostActors)) }
        return (Start-HordeAnalystSession -Script $Script -Handover $Handover -Reason $Reason -ResolveTerminal $resolve -FindSeat $FindSeat -RunScript $RunScript)
    }.GetNewClosure()
}

function Send-HordeAnalystPost {
    # Post -Body to -SessionId through the one messenger that keeps a body out of any input box and
    # takes a repost as one message: { ok; woken; detail }.
    param([Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)][string]$MessageId, [Parameter(Mandatory = $true)][string]$Body, [Parameter(Mandatory = $true)]$Values, [string]$HordeHome = "")
    $found = Find-HordeMessenger -Require $script:HordeAnalystTellNeeds
    if ($found.state -cne "known") { return [pscustomobject]@{ ok = $false; woken = $false; detail = ("no messenger can deliver to a session: " + $(if ($found.state -ceq "absent") { $found.note } else { $found.reason })) } }
    $deviceId = ""
    try { $deviceId = Get-HordeDeviceId -HomeRoot $HordeHome } catch { return [pscustomobject]@{ ok = $false; woken = $false; detail = ("this machine's device id could not be had: " + $_.Exception.Message) } }
    $message = [pscustomobject]@{
        messageId = $MessageId; sessionId = $SessionId
        from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeAnalystFromSession; label = "" + $Values.fromLabel }
        body = $Body; ttlSeconds = $script:HordeAnalystTtlSeconds
    }
    $posted = Send-HordeMessengerMessage -Messenger $found.value -Message $message
    if ($posted.state -ceq "known" -and $script:HordeAnalystTakenStages -ccontains "$($posted.value.stage)") {
        $woken = $posted.value.PSObject.Properties["woken"]
        $reason = $posted.value.PSObject.Properties["reason"]
        return [pscustomobject]@{ ok = $true; woken = ($null -ne $woken -and $woken.Value -eq $true); detail = $(if ($null -ne $reason) { "" + $reason.Value } else { "" }) }
    }
    return [pscustomobject]@{ ok = $false; woken = $false; detail = $(if ($posted.state -ceq "known") { "the messenger answered " + $posted.value.stage } else { "the messenger did not take it: " + $posted.reason }) }
}

function Send-HordeAnalystMessage {
    # A round to the analyst's session (THE REAL TOOLS, header).
    param([Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)][string]$MessageId, [Parameter(Mandatory = $true)][string]$Body, [Parameter(Mandatory = $true)]$Values, [string]$HordeHome = "")
    if (Test-HordeAnalystHomeIsATests -HordeHome $HordeHome) { return [pscustomobject]@{ ok = $false; woken = $false; detail = "this Horde home is a test's: nothing is posted" } }
    return (Send-HordeAnalystPost -SessionId $SessionId -MessageId $MessageId -Body $Body -Values $Values -HordeHome $HordeHome)
}

function Send-HordeAnalystWarchief {
    # One fixed notice to the warchief's session; the message id is new each time it is told.
    param([Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][string]$Body, [Parameter(Mandatory = $true)]$Values, [string]$HordeHome = "")
    if (Test-HordeAnalystHomeIsATests -HordeHome $HordeHome) { return [pscustomobject]@{ ok = $false; detail = "this Horde home is a test's: nobody is told" } }
    $seat = Get-HordeRoleSeat -Role $script:HordeAnalystTellRole
    if ($seat.state -cne "known") { return [pscustomobject]@{ ok = $false; detail = ("the warchief's session cannot be told: " + $(if ($seat.state -ceq "absent") { $seat.note } else { $seat.reason })) } }
    $r = Send-HordeAnalystPost -SessionId $seat.value.sessionId -MessageId ([guid]::NewGuid().ToString()) -Body $Body -Values $Values -HordeHome $HordeHome
    return [pscustomobject]@{ ok = $r.ok; detail = $r.detail }
}

function Send-HordeAnalystFounderNotice {
    # One line to the founder's phone (notices/Decide.ps1). The supervisor is no session, so it is its
    # own sender, by a fixed id and name no session wears; the hourly cap counts it like any sender.
    param([Parameter(Mandatory = $true)][string]$Text, [string]$HordeHome = "")
    if (Test-HordeAnalystHomeIsATests -HordeHome $HordeHome) { return [pscustomobject]@{ ok = $false; detail = "this Horde home is a test's: no notice is sent" } }
    $r = Submit-HordeNotify -Sender ([pscustomobject]@{ ok = $true; sessionId = $script:HordeAnalystFromSession; label = "Analyst supervisor" }) -Text $Text -HordeHome $HordeHome
    return [pscustomobject]@{ ok = (@("sent", "sent-refused") -ccontains $r.outcome); detail = ("" + $r.reason) }
}

function Write-HordeAnalystMail {
    # `horde analyst mail`: leave -Text for the analyst in <folder>\mail, written beside its final name
    # and renamed into place, so the supervisor never reads half of one. Returns one line for the person.
    param([Parameter(Mandatory = $true)][string]$Folder, [Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Markers, $Now = $null)
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    if ($Text.Length -gt $script:HordeAnalystMailMostChars) { throw ("a mail to the analyst is at most " + $script:HordeAnalystMailMostChars + " characters; put the rest in a file and name it") }
    $mailDir = (Get-HordeAnalystPaths -Folder $Folder).mail
    [void][System.IO.Directory]::CreateDirectory($mailDir)
    $name = ([datetime]$Now).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ", [System.Globalization.CultureInfo]::InvariantCulture) + "-" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".txt"
    $final = [System.IO.Path]::Combine($mailDir, $name)
    $temp = [System.IO.Path]::Combine($mailDir, "." + $name + ".tmp")
    [System.IO.File]::WriteAllText($temp, $Text, (New-Object System.Text.UTF8Encoding($false)))
    try { Move-HordeFileAtomic -From $temp -To $final } catch { try { [System.IO.File]::Delete($temp) } catch { }; throw }
    $marker = Get-HordeAnalystMailMarker -Text $Text -Markers $Markers
    if ($marker -ne "") { return ("left for the analyst as " + $name + ", marked " + $marker + ": it wakes the analyst at the next pass") }
    return ("left for the analyst as " + $name + ": it goes in the next round")
}

function Format-HordeAnalystStatus {
    # `horde analyst status`: lines for a person. Reads only; never asks a transcript or a process.
    param([Parameter(Mandatory = $true)][string]$Folder, [Parameter(Mandatory = $true)]$Policy, [Parameter(Mandatory = $true)][string]$Heartbeat)
    $v = $Policy.values
    $paths = Get-HordeAnalystPaths -Folder $Folder
    $sp = Get-HordeAnalystSessionPaths -Folder $Folder
    $out = New-Object System.Collections.ArrayList
    [void]$out.Add("analyst folder: " + $Folder)
    $beat = Read-HordeHeartbeat -Path $Heartbeat
    if ($beat.state -ceq "known") {
        $age = [int][System.Math]::Max(0, ([datetime]::UtcNow - $beat.value.at).TotalSeconds)
        [void]$out.Add("supervisor: last pass " + $age + " s ago" + $(if ($age -gt (Get-HordeHeartbeatStaleSeconds -TickSeconds ([int]$beat.value.tickSeconds))) { ", STALE: horde analyst run is not running" } else { "" }) + $(if ("" + $beat.value.condition -ne "") { "; it cannot act: " + $beat.value.why } else { "" }))
    } else { [void]$out.Add("supervisor: no heartbeat (horde analyst run is not running here)") }
    $st = Read-HordeAnalystState -Path $sp.state
    if ($st.state -cne "known") { [void]$out.Add("state: " + $st.reason); return @($out.ToArray()) }
    $s = $st.value
    [void]$out.Add("session: " + $(if ($s.sessionId -ne "") { $s.sessionId } else { "none" }) + ", " + $s.phase + $(if ($s.phase -ceq "starting") { " since " + (ConvertTo-HordeAnalystTimeText $s.startedAt) + " (" + $s.startReason + ")" } else { "" }))
    [void]$out.Add("context: " + $(if ($s.contextTokens -ge 0) { "" + $s.contextTokens + " tokens of a cap of " + $v.contextCapTokens + " (last call " + (ConvertTo-HordeAnalystTimeText $s.contextAt) + ")" } else { "not read yet" }))
    [void]$out.Add("last round: " + $(if ($null -ne $s.lastRoundAt) { ConvertTo-HordeAnalystTimeText $s.lastRoundAt } else { "never" }) + "; last wake: " + $(if ($null -ne $s.lastWakeAt) { ConvertTo-HordeAnalystTimeText $s.lastWakeAt } else { "never" }))
    $acks = Read-HordeAnalystAcks -Path $paths.acks
    $acked = $(if ($acks.state -ceq "known") { [string[]]$acks.value } else { [string[]]@() })
    $open = @($s.rounds | Where-Object { $acked -cnotcontains $_.id })
    [void]$out.Add("rounds kept: " + @($s.rounds).Count + ", without an ack: " + $open.Count + $(if ($open.Count -gt 0) { " (" + ((@($open | Select-Object -Last 5) | ForEach-Object { $_.id + $(if ($_.woken -ceq "no") { " not woken" } else { "" }) }) -join ", ") + ")" } else { "" }))
    $f = Read-HordeAnalystFindings -Path $paths.findings -Offset $s.findingsOffset
    $m = Read-HordeAnalystMail -Folder $paths.mail -Markers $Policy.markers
    [void]$out.Add("waiting: " + $(if ($f.state -ceq "known") { "" + @($f.value.items | Where-Object { $_.wake -cne "never" }).Count + " finding(s)" } else { "findings unreadable" }) + ", " + $(if ($m.state -ceq "known") { "" + @($m.value).Count + " mail(s)" } else { "mail unreadable" }))
    if (@($s.told).Count -gt 0) { [void]$out.Add("told the warchief, and not over yet: " + (@($s.told) -join ", ")) }
    [void]$out.Add("settings: rounds every " + $v.roundMinutes + " min, heartbeat after " + $v.heartbeatHours + " h, wake at once on " + ($Policy.markers -join ", ") + ", ack within " + $v.ackMinutes + " min, spawn script " + $(if ("" + $v.spawnScript -ne "") { $v.spawnScript } else { "none (the warchief starts it)" }))
    return @($out.ToArray())
}
