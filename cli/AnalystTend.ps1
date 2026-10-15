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
$script:HordeAnalystTellNeeds = @("body.untyped", "idempotent.post")
$script:HordeAnalystTakenStages = @("accepted", "handed-over", "seen")
# How long the spawn script may take: the fleet tool waits for the new tab to open, about 30 s for a
# launch on this fleet; three minutes leaves room for a slow, throttled machine.
$script:HordeAnalystSpawnSeconds = 180
# The longest mail to the analyst: a long message belongs in a file the mail names.
$script:HordeAnalystMailMostChars = 20000
# One fixed sentence for each thing the warchief is told (FIXED WORDS, core/AnalystRounds.ps1).
$script:HordeAnalystTellSentences = [ordered]@{
    "no-analyst"             = "No fleet analyst session is known to the supervisor: none has written its handover file. Ask the analyst to write it once; from then on it is supervised."
    "no-spawn-gone"          = "The fleet analyst's session has ended, and no spawn script is set, so nothing was started. Start a fresh analyst; it starts from its handover file."
    "no-spawn-over-cap"      = "The fleet analyst's context is over its cap, and no spawn script is set, so no fresh session was started. Start one; it starts from its handover file."
    "started-gone"           = "The supervisor started a fresh fleet analyst in your window, because the last one's session had ended. It starts from its handover file."
    "started-over-cap"       = "The supervisor started a fresh fleet analyst in your window, because the last one's context was over its cap. The old session gets no more rounds; close it when you choose."
    "spawn-failed"           = "The supervisor could not start a fresh fleet analyst: its spawn script failed. The status of the analyst supervisor says more."
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
    $body = "FLEET ANALYST SUPERVISOR`n" + $(if ($script:HordeAnalystTellSentences.Contains($Key)) { $script:HordeAnalystTellSentences[$Key] } else { "The fleet analyst needs a person. The status of the analyst supervisor says more." }) + $Extra
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
    $d = Get-HordeAnalystSessionDecision -State $s -Alive $alive -Handover $handover -Context $context -Now $now -Policy $v -RoundDue $due -CanStart $canStart
    switch -CaseSensitive ($d.action) {
        "adopt" {
            & $say ("adopted session " + $d.sessionId + ": " + $d.why)
            $s.sessionId = $d.sessionId; $s.phase = "running"; $s.contextTokens = [long]-1; $s.transcriptLength = [long]-1; $s.contextAt = $null
            Clear-HordeAnalystTold -State $s -Keys @("no-analyst", "start-silent", "no-spawn-gone", "no-spawn-over-cap", "spawn-failed", "start-too-soon-gone", "start-too-soon-over-cap")
            # It was awake when it wrote the handover: a session that has just said who it is is not
            # sent a heartbeat for having been silent before the supervisor knew it.
            if ($null -eq $s.lastWakeAt -or $handover.value.writtenAt -gt $s.lastWakeAt) { $s.lastWakeAt = $handover.value.writtenAt }
            $round = Get-HordeAnalystRoundDecision -Now $now -LastRoundAt $s.lastRoundAt -LastWakeAt $s.lastWakeAt -Findings $findings -Mail $mailItems -Policy $v
            $due = ($round.action -cne "none")
        }
        "start" {
            $r = $null
            try { $r = Invoke-HordeAnalystTool -Tools $Tools -Name "Spawn" -With @(("" + $v.spawnScript), $sp.handover, $d.reason, $v) } catch { $r = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
            if ($null -ne $r -and $r.ok -eq $true) {
                & $say ("started a fresh analyst session: " + $d.why)
                $s.previousSessionId = $s.sessionId; $s.sessionId = ""; $s.phase = "starting"; $s.startedAt = $now; $s.startReason = $d.reason
                $s.contextTokens = [long]-1; $s.transcriptLength = [long]-1; $s.contextAt = $null
                Clear-HordeAnalystTold -State $s -Keys @("started-gone", "started-over-cap", "spawn-failed", "start-silent")
                & $say (Send-HordeAnalystTell -State $s -Key ("started-" + $d.reason) -Tools $Tools -Values $v)
            } else {
                & $say ("the spawn script failed: " + $(if ($null -ne $r) { "" + $r.detail } else { "it did not answer" }))
                # A failed start counts as a start for the wait between starts: no spawn every minute.
                $s.startedAt = $now
                & $say (Send-HordeAnalystTell -State $s -Key "spawn-failed" -Tools $Tools -Values $v)
            }
        }
        default { if ($d.action -cne "keep") { & $say ($d.action + ": " + $d.why) } }
    }
    if ($d.tell -ne "") { & $say (Send-HordeAnalystTell -State $s -Key $d.tell -Tools $Tools -Values $v) }

    # 4. Rounds with no ack: told once to the warchief and the founder.
    $acks = Read-HordeAnalystAcks -Path $paths.acks
    if ($acks.state -ceq "known") {
        $late = @(Get-HordeAnalystAckAlerts -Now $now -Rounds @($s.rounds) -Acked ([string[]]$acks.value) -Policy $v)
        foreach ($id in $late) {
            $one = @($s.rounds | Where-Object { $_.id -ceq $id })[0]
            $one.alerted = $true
            & $say ("round " + $id + " has no ack after " + $v.ackMinutes + " minutes")
            Clear-HordeAnalystTold -State $s -Keys @("no-answer")
            & $say (Send-HordeAnalystTell -State $s -Key "no-answer" -Tools $Tools -Values $v -Extra ("`nRound: " + $id))
            if ($null -ne $Tools["Notify"] -and $v.notifyFounder -eq $true) {
                $n = $null
                try { $n = Invoke-HordeAnalystTool -Tools $Tools -Name "Notify" -With @(("The fleet analyst has not answered round " + $id + " for " + $v.ackMinutes + " minutes; the warchief was told.")) } catch { $n = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
                & $say $(if ($null -ne $n -and $n.ok -eq $true) { "told the founder: no answer to round " + $id } else { "could not tell the founder: " + $(if ($null -ne $n) { "" + $n.detail } else { "the notifier did not answer" }) })
            }
        }
    } else { & $say ("the acks: " + $acks.reason) }

    # 5. The round, to a session that is running and was not just replaced.
    $target = $(if ($s.phase -ceq "running" -and $d.action -ceq "keep" -or $d.action -ceq "adopt") { $s.sessionId } else { "" })
    $over = ($null -ne $context -and [long]$context.value.tokens -gt [long]$v.contextCapTokens -and $d.action -ceq "keep")
    if ($due -and $target -ne "" -and -not $over -and ($f.state -ceq "known" -or $round.action -ceq "heartbeat")) {
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
