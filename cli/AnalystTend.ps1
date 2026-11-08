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
# A KEY COUNTS AS TOLD ONLY WHILE ITS NOTICE IS WATCHED UNTIL THE WARCHIEF'S OWN SESSION TAKES IT (T-0391 slice 7; the chat's own rule,
# channels/chat/Taken.ps1, and the services', the doorbell's and the routed answers': decisions/NoticeTaken.ps1, used as it is). The
# messenger ACCEPTING the post was counted as the warchief being told, the key went into the state's told list, and a notice the session
# never took was never said again. Now:
#   - MARK FIRST, THEN POST (Send-HordeAnalystWarchiefTaken). A list that cannot be read or written means no post, the reason said, and the
#     key is NOT put in the told list, so the next pass tries again. A post the messenger REFUSES (a known answer) takes its mark off; an
#     UNKNOWN result keeps it, for a post that may have landed must stay watched.
#   - WHAT THE TOLD LIST MEANS NOW: "posted and watched". A key goes in it when the post is accepted AND marked, and stays until its condition
#     is over (Clear-HordeAnalystTold) - so a key is never posted twice for one event and never lost: DELIVERED is the awaiting list's
#     business (Invoke-HordeAnalystTellTakenTick says TAKEN when the session's own hook took it), and a notice not taken raises ONE ALARM
#     at takenAlarmSeconds, is asked about every takenAfterAlarmSeconds after it, and is given up with a second ALARM when 7 days old.
#   - ONE ID PER EVENT, A NEW ID FOR A NEW EVENT. The notice id is made from the key and the key's GENERATION, a number in the state
#     (tellGen) that Clear-HordeAnalystTold raises each time a condition is declared over. The same event after a restart has the same
#     generation (the state is written whole, after the clear and the post), so wezfleet keeps one message (lib/MailPost.ps1
#     already-posted) and the mark keeps its clock and its alarm; the same key told on a LATER event has a higher generation, a new id, and
#     wakes someone. A pass killed between the clear and the state write repeats the clear, and reaches the same generation again.
#   - A repost the messenger answers already-posted for a mark this pass has just written is not a fresh post: the first copy's stage says
#     nothing of this one, so the mark is taken off and the line says so (else a false TAKEN would follow). The key is then told.
#   - THE LINES (a TAKEN, an ALARM, a full list given up) are the pass's own lines, which `horde analyst run` writes to the supervisor's log.
#   - THE RETRY (round 2 of PR 455). A key told in the one pass that finds its cause - started-gone and started-over-cap and spawn-failed (the
#     pass that starts a session), no-answer (the pass that finds a late round, which it marks alerted first) - is decided by no later pass. A
#     tell of these the messenger refuses, or leaves unknown, is kept in the state (tellRetry: the key and, for no-answer, its round) and told
#     again by the NEXT pass under the same id (the generation has not moved), until it is posted and watched or its condition is declared over
#     (Clear-HordeAnalystTold takes the row with the key). The other keys are decided by the session decision on every pass and need no row.
# The founder's notice (Notify) goes to the notices store (notices/Decide.ps1), not through a messenger, and is left as it was. The relay
# watch's and the watcher check's tells are marked and counted the same way (T-0391 slice 8): they tell through Send-HordeAnalystWatchTell
# and ask Get-HordeAnalystWatchTaken (core/WatchTell.ps1), and count a notice as told only when the warchief's session took it.
#
# THE PORT IS LOADED ONCE, BY THE COMMAND (cli/commands/analyst.ps1), at its own scope, for every tool that needs it - the teller and the look
# at the awaiting list share that one load, so there is no second load to throw "already registered" (PR 430's round 1). A suite cuts the real
# blocks out of the command file and runs them in one process, in both orders (test/test-analyst-tell-taken.ps1).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "decisions\NoticeTaken.ps1")

# The awaiting list of these notices: one file under the home, the words its lines use (decisions/NoticeTaken.ps1).
$script:HordeAnalystTellTakenKind = New-HordeDecisionNoticeKind -Path @("analyst", "tell-taken.json") -TempPrefix "analyst-tell-taken" -Ledger "the analyst supervisor's awaiting ledger" -List "the awaiting list of analyst supervisor notices" -Label "analyst" -Notice "analyst supervisor notice" -Owner "the warchief's" -Detail { param($Entry) return "from the analyst supervisor" }
$script:HordeAnalystTellTakenAskedFile = "tell-taken-asked.txt"

$script:HordeAnalystTellRole = "warchief"
$script:HordeAnalystFromSession = "horde-analyst"
$script:HordeAnalystTtlSeconds = 604800
$script:HordeAnalystTellNeeds = @("body.untyped", "idempotent.post", "receipt.receiver")
$script:HordeAnalystTakenStages = @("accepted", "handed-over", "seen")
# The engine's memory keys that are kept between passes besides the last-asked times: alarmed-<32 hex> and delivered-<uuid>.
$script:HordeAnalystTellMemoryKeyPattern = 'alarmed-[0-9a-f]{32}|delivered-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
# The keys a new session and a fresh start declare over (Clear-HordeAnalystTold): the pass also skips the retry of these (Invoke-HordeAnalystTellRetries).
$script:HordeAnalystClearOnAdopt = @("no-analyst", "start-silent", "no-spawn-gone", "no-spawn-over-cap", "spawn-failed", "start-too-soon-gone", "start-too-soon-over-cap", "no-answer", "no-answer-founder")
$script:HordeAnalystClearOnStart = @("started-gone", "started-over-cap", "spawn-failed", "start-silent")
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
        # What became of the notices already posted (Invoke-HordeAnalystTellTakenTick): lines for the pass. $null: nothing is asked.
        TellTaken = $null
        # Is the notice of (key, generation) still on the awaiting list: "listed", "gone" or "unread" (Get-HordeAnalystNoticeWatch). $null: not asked.
        Watching = $null
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

function Get-HordeAnalystTellNoticeId {
    # The id of one notice to the warchief: made from the key and its generation, the same for the teller that posts it and the look that asks
    # whether it is still watched (ONE ID PER EVENT).
    param([Parameter(Mandatory = $true)][string]$Key, [long]$Gen = 0)
    return (ConvertTo-HordeAnalystMessageId -Seed ("tell:" + $Key + ":" + $Gen))
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
    # Tell the warchief one thing once: the key goes into the state's told list when the teller POSTED it and marked it for watching (header:
    # not when the session took it - the awaiting list says that), and a key already there is not told again. Returns the journal line,
    # with the teller's own lines (a full list given up, an already-posted copy) after it.
    # -Retry is for a key told in the one pass that finds its cause (a start, a late round), which no later pass decides again: a tell that
    # is refused or has no known result is kept in the state with its -Round (tellRetry) and told again by the next pass (THE RETRY, header).
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Values, [string]$Round = "", [switch]$Retry)
    if (@($State.told) -ccontains $Key) { Remove-HordeAnalystTellRetry -State $State -Key $Key; return "" }
    if ($null -eq $Tools["Tell"] -or $Values.tellWarchief -ne $true) { Remove-HordeAnalystTellRetry -State $State -Key $Key; return ("would tell the warchief (" + $Key + "), but telling is off") }
    $body = "FLEET ANALYST SUPERVISOR`n" + $(if ($script:HordeAnalystTellSentences.Contains($Key)) { $script:HordeAnalystTellSentences[$Key] } else { "The fleet analyst needs a person. The status of the analyst supervisor says more." }) + $(if ($Round -ne "") { "`nRound: " + $Round } else { "" })
    $r = $null
    $gen = Get-HordeAnalystTellGen -State $State -Key $Key
    try { $r = Invoke-HordeAnalystTool -Tools $Tools -Name "Tell" -With @($Key, $body, $Values, $gen) } catch { $r = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
    $more = @()
    if ($null -ne $r -and $null -ne $r.PSObject.Properties["lines"]) { $more = @(@($r.lines) | ForEach-Object { "" + $_ } | Where-Object { $_ -ne "" }) }
    $tail = $(if ($more.Count -gt 0) { " | " + ($more -join " | ") } else { "" })
    if ($null -ne $r -and $r.ok -eq $true) { $State.told = [string[]]@(@($State.told) + $Key); Remove-HordeAnalystTellRetry -State $State -Key $Key; return ("posted to the warchief: " + $Key + " (delivered only when the warchief's own session takes it)" + $tail) }
    if ($Retry) { Set-HordeAnalystTellRetry -State $State -Key $Key -Round $Round }
    return ("could not tell the warchief (" + $Key + "): " + $(if ($null -ne $r) { "" + $r.detail } else { "the teller did not answer" }) + $tail)
}

function Get-HordeAnalystNoticeWatch {
    # Is the notice of (-Key, -Gen) on the awaiting list now: "listed", "gone" (the list is read and it is not there: taken, given up, or never
    # marked) or "unread" (the list cannot be read - no guess either way).
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$Key, [long]$Gen = 0)
    $r = Read-HordeDecisionNoticeTaken -Kind $script:HordeAnalystTellTakenKind -HordeHome $HordeHome
    if ($r.state -cne "known") { return "unread" }
    $id = (Get-HordeAnalystTellNoticeId -Key $Key -Gen $Gen).Replace("-", "")
    foreach ($mark in @($r.value.awaiting)) { $e = ConvertFrom-HordeChatTakenMark -Mark $mark; if ($null -ne $e -and $e.messageId -ceq $id) { return "listed" } }
    return "gone"
}

function Get-HordeAnalystWarchiefWords {
    # What the founder's phone is told of the warchief's notice: what is KNOWN, in the words of the state it is in (T-0391 round 3):
    #   told, on the list                   posted and being watched.
    #   told, off the list                  posted, and NOT watched now (taken, or the messenger already held it): "being watched" would be false.
    #   told, list unreadable / not asked   posted; the watch is not known.
    #   not told, on the list               the result was UNKNOWN: it MAY have landed and its mark is kept; "was not posted" would be false.
    #   not told, off the list              a known refusal: not posted.
    #   telling off, no teller              not posted.
    #   not told, list unreadable           not confirmed as posted.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Values, [Parameter(Mandatory = $true)][string]$Key)
    $watch = "unread"
    if ($null -ne $Tools["Watching"]) {
        $w = $null
        try { $w = Invoke-HordeAnalystTool -Tools $Tools -Name "Watching" -With @($Key, (Get-HordeAnalystTellGen -State $State -Key $Key)) } catch { $w = $null }
        if (@("listed", "gone") -ccontains ("" + $w)) { $watch = "" + $w }
    }
    if (@($State.told) -ccontains $Key) {
        if ($watch -ceq "listed") { return "a notice to the warchief was posted and is being watched for its taking." }
        if ($watch -ceq "gone") { return "a notice to the warchief was posted and is not being watched now; it may already have been taken." }
        return "a notice to the warchief was posted; whether it is still being watched is not known."
    }
    if ($null -eq $Tools["Tell"] -or $Values.tellWarchief -ne $true) { return "a notice to the warchief was not posted." }
    if ($watch -ceq "listed") { return "a notice to the warchief may have been posted; the supervisor cannot tell." }
    if ($watch -ceq "gone") { return "a notice to the warchief was not posted." }
    return "a notice to the warchief was not confirmed as posted."
}

function Set-HordeAnalystTellRetry {
    # Keep a tell to be told again: one row per key ("<key>=<round>"), the newest round winning.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$Key, [string]$Round = "")
    Remove-HordeAnalystTellRetry -State $State -Key $Key
    $State.tellRetry = [string[]]@(@($State.tellRetry) + ($Key + "=" + $Round))
}

function Remove-HordeAnalystTellRetry {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$Key)
    $State.tellRetry = [string[]]@(@($State.tellRetry) | Where-Object { -not ("" + $_).StartsWith($Key + "=", [System.StringComparison]::Ordinal) })
}

function Invoke-HordeAnalystTellRetries {
    # THE RETRY (header): tell again each key whose tell was refused or unknown in an earlier pass, with the round it was kept with, under the
    # same id (the key's generation has not moved). -Skip names the keys this pass declares over (a start, an adoption): their rows go with
    # Clear-HordeAnalystTold, and a row is never told for an event that is over. Returns the journal lines.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Values, [string[]]$Skip = @())
    $out = New-Object System.Collections.ArrayList
    foreach ($row in @($State.tellRetry)) {
        if ("" + $row -cnotmatch '\A([a-z0-9-]{1,40})=([0-9A-Za-z-]{0,40})\z') { continue }
        $key = $Matches[1]; $round = $Matches[2]
        if ($Skip -ccontains $key) { continue }
        [void]$out.Add((Send-HordeAnalystTell -State $State -Key $key -Tools $Tools -Values $Values -Round $round -Retry))
    }
    return @($out.ToArray())
}

function Get-HordeAnalystTellGen {
    # The generation of a key: how many times its condition has been declared over. 0 for a key never cleared.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$Key)
    foreach ($row in @($State.tellGen)) { if ("" + $row -cmatch '\A([a-z0-9-]{1,40})=([0-9]{1,9})\z' -and $Matches[1] -ceq $Key) { return [long]$Matches[2] } }
    return [long]0
}

function Clear-HordeAnalystTold {
    # Forget the told keys whose condition is over, so it is told again if it comes back. Each key named is a new EVENT the next time it
    # is told: its generation goes up, and with it the notice id (header, ONE ID PER EVENT), so a second event is not taken by the
    # messenger for a repeat of the first and left unheard. Raised for every key named, told or not: a post whose result was unknown may
    # have landed, and its event is over too.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string[]]$Keys)
    $State.told = [string[]]@(@($State.told) | Where-Object { $Keys -cnotcontains $_ })
    # A key whose condition is over is not told again for it: its pending tell goes too.
    foreach ($k in $Keys) { Remove-HordeAnalystTellRetry -State $State -Key $k }
    $rows = New-Object System.Collections.ArrayList
    foreach ($k in $Keys) { [void]$rows.Add($k + "=" + ((Get-HordeAnalystTellGen -State $State -Key $k) + 1)) }
    foreach ($row in @($State.tellGen)) { if ("" + $row -cmatch '\A([a-z0-9-]{1,40})=([0-9]{1,9})\z' -and $Keys -cnotcontains $Matches[1]) { [void]$rows.Add("" + $row) } }
    $State.tellGen = [string[]]@($rows.ToArray())
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
    # WHAT BECAME OF THE NOTICES ALREADY POSTED (T-0391 slice 7, header): the warchief's own session took them (TAKEN), or an ALARM says it
    # did not. Every pass, whatever else it does, even one that cannot read its state: a notice must never go unwatched for an unrelated
    # file. The lines are the pass's own, so `horde analyst run` writes them to the supervisor's log. Its failure is its own.
    if ($null -ne $Tools["TellTaken"]) {
        try { foreach ($l in @(& $Tools["TellTaken"] $Policy.values)) { & $say ("" + $l) } }
        catch { & $say ("the awaiting notices could not be asked: " + $_.Exception.Message) }
    }
    $read = Read-HordeAnalystState -Path $sp.state
    if ($read.state -cne "known") {
        # A state that cannot be read is never taken for no state: that would start a second analyst.
        return [pscustomobject]@{ lines = @($lines.ToArray()) + @("the supervisor's state cannot be read: " + $read.reason); problem = ("the supervisor's state cannot be read, so nothing was done: " + $read.reason); state = $null }
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
    $d = Get-HordeAnalystSessionDecision -State $s -Alive $alive -Handover $handover -Context $context -Now $now -Policy $v -RoundDue $due -CanStart $canStart
    # THE ACKS ARE READ BEFORE THE RETRIES (T-0391 round 3): an ack ends a run of late rounds, and a retry row kept for a "no-answer" the ack
    # just ended must go with it (Clear-HordeAnalystTold) - not be told, a pass later, as "has not acked" for a round that was acked. This
    # is the only thing of step 4 that moved; the late rounds are still found and told after the session's action, as before. Acks that cannot
    # be read end nothing: no guess.
    $acks = Read-HordeAnalystAcks -Path $paths.acks
    $ackedIds = [string[]]@()
    if ($acks.state -ceq "known") {
        $ackedIds = [string[]]$acks.value
        $newestAcked = @($s.rounds | Where-Object { $ackedIds -ccontains $_.id } | Sort-Object at | Select-Object -Last 1)
        if ($newestAcked.Count -eq 1 -and $newestAcked[0].id -cne $s.lastAckId) { $s.lastAckId = $newestAcked[0].id; Clear-HordeAnalystTold -State $s -Keys @("no-answer", "no-answer-founder") }
    }
    # THE RETRY, before the action: a tell the messenger refused or left unknown in an earlier pass is told again now, except the keys this very
    # pass declares over.
    $skipRetry = $(switch -CaseSensitive ($d.action) { "adopt" { $script:HordeAnalystClearOnAdopt } "start" { $script:HordeAnalystClearOnStart } default { @() } })
    foreach ($l in @(Invoke-HordeAnalystTellRetries -State $s -Tools $Tools -Values $v -Skip $skipRetry)) { & $say $l }
    switch -CaseSensitive ($d.action) {
        "adopt" {
            & $say ("adopted session " + $d.sessionId + ": " + $d.why)
            $s.sessionId = $d.sessionId; $s.phase = "running"; $s.contextTokens = [long]-1; $s.transcriptLength = [long]-1; $s.contextAt = $null
            # A NEW SESSION STARTS A NEW RUN (review of PR 306): the last one's untold-until-ack "no-answer"
            # would silence a fresh session that writes its handover and never acks. Its old rounds stay
            # marked alerted, so clearing here tells nothing about them again.
            Clear-HordeAnalystTold -State $s -Keys $script:HordeAnalystClearOnAdopt
            # It was awake when it wrote the handover: a session that has just said who it is is not
            # sent a heartbeat for having been silent before the supervisor knew it.
            if ($null -eq $s.lastWakeAt -or $handover.value.writtenAt -gt $s.lastWakeAt) { $s.lastWakeAt = $handover.value.writtenAt }
            $round = Get-HordeAnalystRoundDecision -Now $now -LastRoundAt $s.lastRoundAt -LastWakeAt $s.lastWakeAt -Findings $findings -Mail $mailItems -Policy $v
            $due = ($round.action -cne "none")
        }
        "start" {
            # STARTING IS WRITTEN BEFORE THE SPAWN RUNS (review of PR 306): a pass killed while the spawn
            # script runs - a service restarted for an update, up to $script:HordeAnalystSpawnSeconds -
            # leaves the script going, and the next pass must find "starting", not "running and gone".
            $s.previousSessionId = $s.sessionId; $s.sessionId = ""; $s.phase = "starting"; $s.startedAt = $now; $s.startReason = $d.reason
            $s.contextTokens = [long]-1; $s.transcriptLength = [long]-1; $s.contextAt = $null
            Clear-HordeAnalystTold -State $s -Keys $script:HordeAnalystClearOnStart
            Write-HordeAnalystState -Path $sp.state -State $s
            $r = $null
            try { $r = Invoke-HordeAnalystTool -Tools $Tools -Name "Spawn" -With @(("" + $v.spawnScript), $sp.handover, $d.reason, $v) } catch { $r = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
            if ($null -ne $r -and $r.ok -eq $true) {
                & $say ("started a fresh analyst session: " + $d.why)
                & $say (Send-HordeAnalystTell -State $s -Key ("started-" + $d.reason) -Tools $Tools -Values $v -Retry)
            } else {
                # A SPAWN THAT FAILED OR TIMED OUT MAY STILL HAVE STARTED ONE: its child can go on after the
                # timeout, and a non-zero exit can follow a tab that opened. So it stays "starting" and
                # waits for a handover (startWaitMinutes, then the warchief is told) - it is never taken
                # for "nothing happened", which would start a second session later.
                & $say ("the spawn script did not report success: " + $(if ($null -ne $r) { "" + $r.detail } else { "it did not answer" }) + "; waiting for a handover all the same")
                & $say (Send-HordeAnalystTell -State $s -Key "spawn-failed" -Tools $Tools -Values $v -Retry)
            }
        }
        default { if ($d.action -cne "keep") { & $say ($d.action + ": " + $d.why) } }
    }
    if ($d.tell -ne "") { & $say (Send-HordeAnalystTell -State $s -Key $d.tell -Tools $Tools -Values $v) }

    # 4. Rounds with no ack: told ONCE for a run of them (review of PR 306: a wedged session that is still
    #    alive gets a round every half hour, and telling each one was up to 48 alerts a day). The run ends,
    #    and the next one may be told, only when an ack arrives: a round newer than the last ack seen.
    if ($acks.state -ceq "known") {
        $late = @(Get-HordeAnalystAckAlerts -Now $now -Rounds @($s.rounds) -Acked $ackedIds -Policy $v)
        foreach ($id in $late) {
            $one = @($s.rounds | Where-Object { $_.id -ceq $id })[0]
            $one.alerted = $true
            & $say ("round " + $id + " has no ack after " + $v.ackMinutes + " minutes")
            # The round is marked alerted just above, so no later pass finds it late again: a refused tell is kept (tellRetry) with this round and
            # told by the next pass.
            if (-not (@($s.told) -ccontains "no-answer")) { & $say (Send-HordeAnalystTell -State $s -Key "no-answer" -Tools $Tools -Values $v -Round $id -Retry) }
            # THE FOUNDER'S NOTICE HAS ITS OWN TOLD KEY (review of PR 306): tied to the warchief's tell, telling
            # switched off or fleet mail failing left "no-answer" untold, so every late round notified the
            # founder again - up to 48 a day - each saying the warchief was told when he was not (and now it says what is known: a notice posted and watched, or not posted).
            if ((@($s.told) -ccontains "no-answer-founder") -or $null -eq $Tools["Notify"] -or $v.notifyFounder -ne $true) { continue }
            # WHAT IS KNOWN, NOT MORE (Get-HordeAnalystWarchiefWords): this goes to a phone.
            $warchief = Get-HordeAnalystWarchiefWords -State $s -Tools $Tools -Values $v -Key "no-answer"
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

function Start-HordeAnalystSession {
    # THE REAL SPAWN (header): run the person's spawn script with the warchief's seat, the handover file
    # and why; { ok; detail }. The script is given at most $script:HordeAnalystSpawnSeconds to return.
    param([Parameter(Mandatory = $true)][string]$Script, [Parameter(Mandatory = $true)][string]$Handover, [Parameter(Mandatory = $true)][string]$Reason)
    if (-not [System.IO.File]::Exists($Script)) { return [pscustomobject]@{ ok = $false; detail = "the spawn script is not there" } }
    $seat = Get-HordeRoleSeat -Role $script:HordeAnalystTellRole
    if ($seat.state -cne "known") { return [pscustomobject]@{ ok = $false; detail = ("the warchief's window cannot be found: " + $(if ($seat.state -ceq "absent") { $seat.note } else { $seat.reason })) } }
    $line = $null
    try { $line = Get-HordeAnalystSpawnArguments -Script $Script -Seat $seat.value -Handover $Handover -Reason $Reason } catch { return [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = $line
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        if (-not $p.WaitForExit($script:HordeAnalystSpawnSeconds * 1000)) { return [pscustomobject]@{ ok = $false; detail = ("the spawn script did not return in " + $script:HordeAnalystSpawnSeconds + " s") } }
        if ($p.ExitCode -ne 0) { return [pscustomobject]@{ ok = $false; detail = ("the spawn script exited " + $p.ExitCode) } }
        return [pscustomobject]@{ ok = $true; detail = "" }
    } finally { $p.Dispose() }
}

function Send-HordeAnalystPost {
    # Post -Body to -SessionId through the one messenger that keeps a body out of any input box and
    # takes a repost as one message: { ok; woken; detail }.
    param([Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)][string]$MessageId, [Parameter(Mandatory = $true)][string]$Body, [Parameter(Mandatory = $true)]$Values, [string]$HordeHome = "")
    # known: whether the answer is a KNOWN one (nothing was posted, or the messenger said what it did) - an unknown result may have landed.
    $found = Find-HordeMessenger -Require $script:HordeAnalystTellNeeds
    if ($found.state -cne "known") { return [pscustomobject]@{ ok = $false; woken = $false; known = $true; detail = ("no messenger can deliver to a session: " + $(if ($found.state -ceq "absent") { $found.note } else { $found.reason })) } }
    $deviceId = ""
    try { $deviceId = Get-HordeDeviceId -HomeRoot $HordeHome } catch { return [pscustomobject]@{ ok = $false; woken = $false; known = $true; detail = ("this machine's device id could not be had: " + $_.Exception.Message) } }
    $message = [pscustomobject]@{
        messageId = $MessageId; sessionId = $SessionId
        from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeAnalystFromSession; label = "" + $Values.fromLabel }
        body = $Body; ttlSeconds = $script:HordeAnalystTtlSeconds
    }
    $posted = Send-HordeMessengerMessage -Messenger $found.value -Message $message
    if ($posted.state -ceq "known" -and $script:HordeAnalystTakenStages -ccontains "$($posted.value.stage)") {
        $woken = $posted.value.PSObject.Properties["woken"]
        $reason = $posted.value.PSObject.Properties["reason"]
        return [pscustomobject]@{ ok = $true; woken = ($null -ne $woken -and $woken.Value -eq $true); known = $true; detail = $(if ($null -ne $reason) { "" + $reason.Value } else { "" }) }
    }
    return [pscustomobject]@{ ok = $false; woken = $false; known = ($posted.state -ceq "known"); detail = $(if ($posted.state -ceq "known") { "the messenger answered " + $posted.value.stage } else { "the messenger did not take it: " + $posted.reason }) }
}

function Send-HordeAnalystMessage {
    # A round to the analyst's session (THE REAL TOOLS, header).
    param([Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)][string]$MessageId, [Parameter(Mandatory = $true)][string]$Body, [Parameter(Mandatory = $true)]$Values, [string]$HordeHome = "")
    if (Test-HordeAnalystHomeIsATests -HordeHome $HordeHome) { return [pscustomobject]@{ ok = $false; woken = $false; detail = "this Horde home is a test's: nothing is posted" } }
    return (Send-HordeAnalystPost -SessionId $SessionId -MessageId $MessageId -Body $Body -Values $Values -HordeHome $HordeHome)
}

function Test-HordeAnalystNoticeListed {
    # Is the notice on the awaiting list now? $false too when the list cannot be read (Add then fails and nothing is posted).
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$NoticeId)
    $r = Read-HordeDecisionNoticeTaken -Kind $script:HordeAnalystTellTakenKind -HordeHome $HordeHome
    if ($r.state -cne "known") { return $false }
    $id = $NoticeId.Replace("-", "")
    foreach ($mark in @($r.value.awaiting)) { $e = ConvertFrom-HordeChatTakenMark -Mark $mark; if ($null -ne $e -and $e.messageId -ceq $id) { return $true } }
    return $false
}

function Send-HordeAnalystWarchiefTaken {
    # THE TELL TOOL (header): one fixed notice to the warchief's session, marked on the awaiting list BEFORE it is posted, under the id of
    # (-Key, -Gen): { ok; detail; lines }. ok is $true when the post was accepted and is watched - NOT when the session took it. -Seat and
    # -TempRoot are for a suite.
    param([Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][string]$Body, [Parameter(Mandatory = $true)]$Values, [long]$Gen = 0, [string]$HordeHome = "", $Now = $null, [scriptblock]$Seat = $null, [string]$TempRoot = "")
    $lines = New-Object System.Collections.ArrayList
    $done = { param([bool]$Ok, [string]$Detail) return [pscustomobject]@{ ok = $Ok; detail = $Detail; lines = [string[]]@($lines.ToArray()) } }
    if (Test-HordeAnalystHomeIsATests -HordeHome $HordeHome -TempRoot $TempRoot) { return (& $done $false "this Horde home is a test's: nobody is told") }
    $where = $(if ($null -ne $Seat) { & $Seat } else { Get-HordeRoleSeat -Role $script:HordeAnalystTellRole })
    if ($where.state -cne "known") { return (& $done $false ("the warchief's session cannot be told: " + $(if ($where.state -ceq "absent") { $where.note } else { $where.reason }))) }
    $id = Get-HordeAnalystTellNoticeId -Key $Key -Gen $Gen
    $at = $(if ($Now -is [datetime]) { $Now.ToUniversalTime() } else { [datetime]::UtcNow })
    # THE MARK IS WRITTEN BEFORE THE POST. A crash between the mark and the post only costs an alarm at takenAlarmSeconds: the next pass
    # posts the same id, which the messenger keeps as one.
    $wasListed = Test-HordeAnalystNoticeListed -HordeHome $HordeHome -NoticeId $id
    $awaited = Add-HordeDecisionNoticeTaken -Kind $script:HordeAnalystTellTakenKind -HordeHome $HordeHome -NoticeId $id -Answer $Gen -SessionId ("" + $where.value.sessionId) -Now $at
    foreach ($l in @($awaited.lines)) { [void]$lines.Add($l) }
    if (-not $awaited.ok) { return (& $done $false ("the notice cannot be awaited (" + $awaited.reason + "); nothing is posted until it can be")) }
    $r = Send-HordeAnalystPost -SessionId ("" + $where.value.sessionId) -MessageId $id -Body $Body -Values $Values -HordeHome $HordeHome
    if ($r.ok) {
        # ALREADY POSTED, AND THIS PASS WROTE A BRAND-NEW MARK: the messenger answered with the first copy's stage and woke nobody, so that
        # stage says nothing of THIS post. The mark is taken off (or the next look would log a TAKEN for a notice never sent again) and the
        # line says so. The key is still told: the first copy was posted, whatever it became.
        if ($r.detail -clike "already-posted*" -and -not $wasListed) {
            $removedAgain = Remove-HordeDecisionNoticeTaken -Kind $script:HordeAnalystTellTakenKind -HordeHome $HordeHome -NoticeId $id
            [void]$lines.Add("analyst: the notice " + $id + " (" + $Key + ") was NOT sent again: the messenger already held a copy of it from an earlier post and woke nobody; this call counts nothing as delivered (an earlier look says if the first copy was taken)" + $(if (-not $removedAgain.ok) { "; its awaiting mark could not be removed (" + $removedAgain.reason + ")" } else { "" }))
        }
        return (& $done $true "")
    }
    # A REFUSED POST LEAVES NO MARK (the notice is in no mailbox, so a mark would alarm "not taken" for something never sent). ONLY A KNOWN
    # ANSWER removes it: an UNKNOWN result may have landed, and a notice that landed must stay watched. AND ONLY A MARK THIS CALL WROTE: one
    # that was already listed (-WasListed, read before the mark was added) belongs to an earlier post that may have landed - a restart before
    # the state was written, an unknown result - so this call's refusal says nothing of it and it stays (round 2 of PR 455: with it gone the
    # next pass, finding no messenger, took the key as unposted and the notice nobody took never alarmed).
    $detail = "" + $r.detail
    if ($r.known -eq $true -and -not $wasListed) {
        $removed = Remove-HordeDecisionNoticeTaken -Kind $script:HordeAnalystTellTakenKind -HordeHome $HordeHome -NoticeId $id
        if (-not $removed.ok) { $detail = $detail + "; its awaiting mark could not be removed (" + $removed.reason + ")" }
    }
    return (& $done $false $detail)
}

function Send-HordeAnalystWatchTell {
    # THE TELL TOOL OF THE RELAY WATCH AND THE WATCHER CHECK (T-0391 slice 8; core/WatchTell.ps1): the marked teller (Send-HordeAnalystWarchiefTaken,
    # under the id of -Key and -Gen) with one more fact: listed, whether the notice's mark is on the awaiting list after the call. A not-ok
    # answer with listed set is an UNKNOWN result that may have landed, and the watch says "may have been posted", never "not posted".
    # { ok; detail; lines; listed }. -Seat, -TempRoot and -Now are for a suite.
    param([Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][string]$Body, [Parameter(Mandatory = $true)]$Values, [long]$Gen = 0, [string]$HordeHome = "", $Now = $null, [scriptblock]$Seat = $null, [string]$TempRoot = "")
    $r = Send-HordeAnalystWarchiefTaken -Key $Key -Body $Body -Values $Values -Gen $Gen -HordeHome $HordeHome -Now $Now -Seat $Seat -TempRoot $TempRoot
    $listed = $false
    if (-not (Test-HordeAnalystHomeIsATests -HordeHome $HordeHome -TempRoot $TempRoot)) { $listed = (Test-HordeAnalystNoticeListed -HordeHome $HordeHome -NoticeId (Get-HordeAnalystTellNoticeId -Key $Key -Gen $Gen)) }
    return [pscustomobject]@{ ok = $r.ok; detail = $r.detail; lines = $r.lines; listed = $listed }
}

function Get-HordeAnalystWatchTaken {
    # THE TAKEN TOOL OF THE RELAY WATCH AND THE WATCHER CHECK (core/WatchTell.ps1): did the warchief's own session take the notice of (-Key,
    # -Gen)? Asked of the messenger by the id it was posted under: "taken" (handed-over or seen), "held" (the messenger holds it for good: not
    # delivered), "lost" (the messenger gave it up unread; it may still be in his mailbox), "pending" (not taken, and still on the awaiting list, so the pass keeps asking and one ALARM is said), or "unknown" (no
    # messenger, no answer, or off the list with no word: nothing is guessed). -Messenger is for a suite; the command has loaded the port.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$Key, [long]$Gen = 0, $Messenger = $null)
    $id = Get-HordeAnalystTellNoticeId -Key $Key -Gen $Gen
    try {
        if ($null -eq $Messenger) { $found = Find-HordeMessenger -Require $script:HordeAnalystTellNeeds; if ($found.state -ceq "known") { $Messenger = $found.value } }
        if ($null -ne $Messenger) {
            $status = Get-HordeMessengerStatus -Messenger $Messenger -MessageId $id
            if ($status.state -ceq "known") {
                $stage = "" + $status.value.stage
                if ($stage -ceq "handed-over" -or $stage -ceq "seen") { return "taken" }
                if ($stage -ceq "held") { return "held" }
                if ($stage -ceq "expired") { return "lost" }
            }
        }
    } catch { }
    if (Test-HordeAnalystNoticeListed -HordeHome $HordeHome -NoticeId $id) { return "pending" }
    return "unknown"
}

function Test-HordeAnalystTellAwaiting {
    # Is there a mark to ask about? A quiet pass - nearly every pass - has none, and then asks no messenger. The file stays after the last
    # mark is taken off ({"awaiting":[]}), so its being there says nothing; a list that cannot be read counts as awaiting, so the look is
    # made and says why it cannot be (a notice must never go unwatched for an unreadable file).
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $path = Get-HordeDecisionNoticeTakenPath -Kind $script:HordeAnalystTellTakenKind -HordeHome $HordeHome
    if (-not [System.IO.File]::Exists($path)) { return $false }
    $r = Read-HordeDecisionNoticeTaken -Kind $script:HordeAnalystTellTakenKind -HordeHome $HordeHome
    if ($r.state -cne "known") { return $true }
    return (@($r.value.awaiting).Count -gt 0)
}

function Read-HordeAnalystTellAsked {
    # What the supervisor keeps about the marks between passes: when each was last asked about, by message id (UTC ms), AND what the engine
    # remembers (decisions/NoticeTaken.ps1, -Memory): that an alarm was said ("alarmed-<id>") and that a taken was said ("delivered-<uuid>").
    # The tend may be a new process each time, so the cadence after an alarm needs the first kept, and a list that cannot be written
    # (read-only, locked) needs the others: the engine keeps them only in the table, and a table lost between passes made every look say the
    # same ALARM and the same TAKEN again (round 2 of PR 455: five ALARMs for one notice in 340 s). A missing or unreadable file is an
    # empty table (every mark is then simply asked).
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $table = @{}
    $path = [System.IO.Path]::Combine($HordeHome, "analyst", $script:HordeAnalystTellTakenAskedFile)
    try {
        if (-not [System.IO.File]::Exists($path)) { return $table }
        foreach ($line in @([System.IO.File]::ReadAllLines($path))) {
            if ($line -cmatch '\A([0-9a-f]{32}) ([0-9]{1,15})\z') { $table[$Matches[1]] = [long]$Matches[2] }
            elseif ($line -cmatch ('\A(' + $script:HordeAnalystTellMemoryKeyPattern + ') 1\z')) { $table[$Matches[1]] = $true }
        }
    } catch { return @{} }
    return $table
}

function Write-HordeAnalystTellAsked {
    # The table (Read-HordeAnalystTellAsked), for the marks still awaiting only, replaced whole in one rename. $true when written; never throws.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][hashtable]$Table)
    $path = [System.IO.Path]::Combine($HordeHome, "analyst", $script:HordeAnalystTellTakenAskedFile)
    $tmp = $path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    try {
        $r = Read-HordeDecisionNoticeTaken -Kind $script:HordeAnalystTellTakenKind -HordeHome $HordeHome
        if ($r.state -cne "known") { return $false }
        $live = @{}
        foreach ($mark in @($r.value.awaiting)) { $e = ConvertFrom-HordeChatTakenMark -Mark $mark; if ($null -ne $e) { $live[$e.messageId] = $true } }
        $rows = @(foreach ($k in @($Table.Keys | Sort-Object)) {
            $id = ("" + $k).Replace("alarmed-", "").Replace("delivered-", "").Replace("-", "")
            if (-not $live.ContainsKey($id)) { continue }
            if (("" + $k) -cmatch '\A[0-9a-f]{32}\z' -and $Table[$k] -is [long]) { $k + " " + $Table[$k] }
            elseif (("" + $k) -cmatch ('\A(' + $script:HordeAnalystTellMemoryKeyPattern + ')\z') -and $Table[$k] -eq $true) { $k + " 1" }
        })
        if ($rows.Count -eq 0) { if ([System.IO.File]::Exists($path)) { [System.IO.File]::Delete($path) }; return $true }
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
        [System.IO.File]::WriteAllBytes($tmp, [System.Text.Encoding]::ASCII.GetBytes(($rows -join "`n") + "`n"))
        Move-HordeFileAtomic -From $tmp -To $path
        return $true
    } catch { try { [System.IO.File]::Delete($tmp) } catch { }; return $false }
}

function Invoke-HordeAnalystTellTakenTick {
    # Ask about the notices awaiting the warchief's own TAKEN and say what became of them (NoticeTaken.ps1): the lines, for the pass's
    # output. The messenger is found as the notice was posted; when none can be had now the clock alone speaks. Never throws. The command
    # has loaded the messenger port (header); call it only when Test-HordeAnalystTellAwaiting.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][datetime]$Now, [double]$AlarmSeconds = 90, [double]$AfterAlarmSeconds = 300)
    $messenger = $null
    try { $found = Find-HordeMessenger -Require $script:HordeAnalystTellNeeds; if ($found.state -ceq "known") { $messenger = $found.value } } catch { $messenger = $null }
    try {
        $memory = Read-HordeAnalystTellAsked -HordeHome $HordeHome
        # A TAKEN said by an earlier look is not said again by one that finds the mark still there (the list could not be written).
        $saidTaken = @{}
        foreach ($k in @($memory.Keys)) { if (("" + $k).StartsWith("delivered-", [System.StringComparison]::Ordinal)) { $saidTaken[("" + $k)] = $true } }
        $tick = Invoke-HordeDecisionNoticeTakenTick -Kind $script:HordeAnalystTellTakenKind -HordeHome $HordeHome -Messenger $messenger -Now $Now.ToUniversalTime() -AlarmSeconds $AlarmSeconds -AfterAlarmSeconds $AfterAlarmSeconds -TtlSeconds $script:HordeAnalystTtlSeconds -Memory $memory
        [void](Write-HordeAnalystTellAsked -HordeHome $HordeHome -Table $memory)
        return @(@($tick.lines) | Where-Object { -not (("" + $_) -cmatch '\ATAKEN: analyst supervisor notice ([0-9a-f-]{36}) ' -and $saidTaken.ContainsKey("delivered-" + $Matches[1])) })
    } catch { return @("analyst: the awaiting list of analyst supervisor notices could not be asked: " + $_.Exception.Message) }
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
    if (@($s.told).Count -gt 0) { [void]$out.Add("posted to the warchief, and not over yet: " + (@($s.told) -join ", ")) }
    [void]$out.Add("settings: rounds every " + $v.roundMinutes + " min, heartbeat after " + $v.heartbeatHours + " h, wake at once on " + ($Policy.markers -join ", ") + ", ack within " + $v.ackMinutes + " min, spawn script " + $(if ("" + $v.spawnScript -ne "") { $v.spawnScript } else { "none (the warchief starts it)" }))
    return @($out.ToArray())
}
