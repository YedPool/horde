# DOES THE NODE ANSWER THE HUB'S READ VERBS, AND NOTHING ELSE, IN FRAMES THE CONTRACT ACCEPTS?
#
# Remote plan step R12a. remote/NodeServe.ps1 decides each answer from one received line;
# cli/NodeServe.ps1 runs the loop. This suite holds both, without a pipe:
#   - frame by frame: hello and its refusal, a ping, node.info, sessions.list, session.get and
#     request.status, every other verb refused, a request before hello refused, a line that is not a
#     frame ended with a bye - and every frame the node sends passes the contract (remote/Contract.ps1)
#     and the caps (remote/Protocol.ps1), because it is encoded by the same writer the link uses;
#   - what crosses: a fixed summary per session, unknowns carried with their reasons, pid, procStart and
#     project directory placed by device and space (R11), and no transcript path or resume command;
#   - complete: known true only when every store was readable, otherwise known false naming the stores;
#     and a session missing from an incomplete list is unknown, never absent;
#   - the loop itself, cli/NodeServe.ps1, over the in-process memory transport with a fake session
#     view: a hub client on this thread, the node in a second runspace.
# The same loop over the real local pipe, started through the real horde CLI, is
# test/test-node-serve-local.ps1, which needs this machine's interactive logon.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Platform", "Namespace")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $root "remote\NodeServe.ps1")
. (Join-Path $root "cli\NodeServe.ps1")

$fx = Join-Path $root "test\fixtures\node-serve"
$viewPath = Join-Path $fx "view.json"
$device = "0f8fad5b-d9cb-469f-a165-70867728950e"
$ns = New-HordeNamespace -Device $device -Space "windows"
$manifest = New-HordeNodeManifest -Root $root -Node ([pscustomobject]@{ deviceId = $device; deviceName = "fixture-node" }) -Space "windows"
function View { return ([System.IO.File]::ReadAllText($viewPath) | ConvertFrom-Json) }
function Data { param($View = $null, [string]$Journal = "", [string]$ViewError = "") return [pscustomobject]@{ manifest = $manifest; view = $View; viewError = $ViewError; journalRoot = $Journal; namespace = $ns } }
function State { return (New-HordeNodeServeState -NodeId $device -NodeName "fixture-node" -HordeVersion "0.1.0") }
function Hello {
    param([int[]]$Protocols = @(1))
    $t = Get-HordeLinkTime
    return [pscustomobject][ordered]@{ v = 1; kind = "hello"; id = (New-HordeLinkFrameId); seq = 1; ts = $t; hello = [pscustomobject][ordered]@{ role = "hub"; id = "7c9e6679-7425-40de-944b-e07fc1f90ae7"; name = "fixture-hub"; protocols = $Protocols; verbsVersions = @(1); hordeVersion = "0.1.0"; t1 = $t } }
}
function Req {
    param([string]$Verb, $ArgsObject = $null)
    if ($null -eq $ArgsObject) { $ArgsObject = [pscustomobject]@{} }
    return [pscustomobject][ordered]@{ v = 1; kind = "req"; id = (New-HordeLinkFrameId); seq = 2; ts = (Get-HordeLinkTime); verb = $Verb; requestId = (New-HordeLinkFrameId); issuedAt = (Get-HordeLinkTime); args = $ArgsObject }
}
function Line {
    # A frame as the wire carries it, encoded by the link's own writer. A frame the writer refuses is
    # returned as its raw JSON so a test can still send it.
    param($Frame)
    $b = ConvertTo-HordeFrameBytes -Frame $Frame
    if ($b.ok) { return [System.Text.Encoding]::ASCII.GetString($b.bytes, 0, $b.bytes.Length - 1) }
    return (ConvertTo-HordeWireText $Frame)
}
function Sendable { param($Frame) $b = ConvertTo-HordeFrameBytes -Frame $Frame; if (-not $b.ok) { Write-Host ("         not sendable: " + $b.reason) -ForegroundColor DarkYellow }; return [bool]$b.ok }
function Ask {
    # One request answered by a node whose hello is done.
    param([string]$Verb, $ArgsObject = $null, $View = $null, [string]$Journal = "", [string]$ViewError = "")
    $st = State
    $null = Invoke-HordeNodeFrame -State $st -Line (Line (Hello)) -Data (Data)
    return (Invoke-HordeNodeFrame -State $st -Line (Line (Req $Verb $ArgsObject)) -Data (Data -View $View -Journal $Journal -ViewError $ViewError))
}

Write-Host ""
Write-Host "--- the node file starts nothing ---" -ForegroundColor Cyan
. (Join-Path $root "tools\ExecScan.ps1")
$scan = @(Get-HordeExecFindings -Path (Join-Path $root "remote\NodeServe.ps1") -Known (Get-HordeExecFunctionNames -Roots @(Join-Path $root "remote")))
Check ($scan.Count -eq 0) ("remote/NodeServe.ps1 passes the exec scan (" + ($scan -join "; ") + ")")
Check ((Test-HordeContractDocument -Value (($manifest | ConvertTo-Json -Depth 10) | ConvertFrom-Json) -SchemaName "node-manifest.v1").Count -eq 0) "the node's manifest is a valid node-manifest.v1"

Write-Host ""
Write-Host "--- hello first ---" -ForegroundColor Cyan
$st = State
$r = Invoke-HordeNodeFrame -State $st -Line (Line (Req "node.info")) -Data (Data)
Check ($null -ne $r.reply -and "$($r.reply.kind)" -ceq "res" -and "$($r.reply.error.code)" -ceq "refused" -and (Sendable $r.reply)) "a request before the hello is refused, in a frame the contract accepts"
$st = State
$r = Invoke-HordeNodeFrame -State $st -Line (Line (Hello)) -Data (Data)
Check ("$($r.reply.kind)" -ceq "hello" -and "$($r.reply.hello.role)" -ceq "node" -and "$($r.reply.hello.id)" -ceq $device -and $r.close -eq $false -and (Sendable $r.reply)) "a hello is answered with the node's own, naming this device"
Check ($st.helloDone -eq $true -and $st.protocol -eq 1) "the link speaks protocol 1 after the hello"
$st = State
$r = Invoke-HordeNodeFrame -State $st -Line (Line (Hello -Protocols @(9))) -Data (Data)
Check ("$($r.reply.kind)" -ceq "bye" -and "$($r.reply.bye.code)" -ceq "no-common-protocol" -and $r.close -eq $true) "a hello with no common protocol ends the link with a bye"
$st = State
$r = Invoke-HordeNodeFrame -State $st -Line "this is not a frame" -Data (Data)
Check ("$($r.reply.kind)" -ceq "bye" -and "$($r.reply.bye.code)" -ceq "bad-frame" -and $r.close -eq $true) "a line that is not a frame ends the link with a bye saying why"
$st = State
$null = Invoke-HordeNodeFrame -State $st -Line (Line (Hello)) -Data (Data)
$pingAt = Get-HordeLinkTime
$ping = [pscustomobject][ordered]@{ v = 1; kind = "ping"; id = (New-HordeLinkFrameId); seq = 2; ts = $pingAt; ping = [pscustomobject]@{ t1 = $pingAt } }
$r = Invoke-HordeNodeFrame -State $st -Line (Line $ping) -Data (Data)
Check ("$($r.reply.kind)" -ceq "pong" -and "$($r.reply.re)" -ceq "$($ping.id)" -and "$($r.reply.pong.t1)" -ceq $pingAt -and (Sendable $r.reply)) "a ping is answered with a pong echoing t1 and giving the node's t2 and t3 (R6)"
$bye = New-HordeLinkBye -Code "shutdown" -Reason "the hub is finished" -Seq 3
$r = Invoke-HordeNodeFrame -State $st -Line (Line $bye) -Data (Data)
Check ($null -eq $r.reply -and $r.close -eq $true) "the hub's bye ends the link"
$st = State
$asNode = Hello
$asNode.hello.role = "node"
$r = Invoke-HordeNodeFrame -State $st -Line (Line $asNode) -Data (Data)
Check ("$($r.reply.kind)" -ceq "bye" -and "$($r.reply.bye.code)" -ceq "refused" -and $r.close -eq $true -and $st.helloDone -eq $false) "a hello that says it is a node, not a hub, ends the link"
$st = State
$null = Invoke-HordeNodeFrame -State $st -Line (Line (Hello)) -Data (Data)
$r = Invoke-HordeNodeFrame -State $st -Line (Line (Hello)) -Data (Data)
Check ("$($r.reply.kind)" -ceq "bye" -and $r.close -eq $true) "a second hello on one link ends it: the protocol is chosen once"
$st = State
$r = Invoke-HordeNodeFrame -State $st -Line (Line $ping) -Data (Data)
Check ("$($r.reply.kind)" -ceq "bye" -and $r.close -eq $true) "a ping before the hello ends the link"
$st = State
$h1 = Invoke-HordeNodeFrame -State $st -Line (Line (Hello)) -Data (Data)
$q = Req "node.info"
$a1 = Invoke-HordeNodeFrame -State $st -Line (Line $q) -Data (Data)
$a2 = Invoke-HordeNodeFrame -State $st -Line (Line (Req "node.info")) -Data (Data)
Check ("$($a1.reply.re)" -ceq "$($q.id)" -and "$($a1.reply.requestId)" -ceq "$($q.requestId)" -and "$($a1.reply.verb)" -ceq "node.info") "an answer names the frame it answers (re), its request id and its verb"
Check ($h1.reply.seq -eq 1 -and $a1.reply.seq -eq 2 -and $a2.reply.seq -eq 3) "the node's frames on one link are numbered 1, 2, 3 in order"

Write-Host ""
Write-Host "--- only the read verbs of R12a are answered ---" -ForegroundColor Cyan
$deliverArgs = [pscustomobject][ordered]@{ messageId = (New-HordeLinkFrameId); sessionId = "aaaaaaaa-0000-4000-8000-000000000001"; from = [pscustomobject][ordered]@{ deviceId = "7c9e6679-7425-40de-944b-e07fc1f90ae7"; sessionId = "aaaaaaaa-0000-4000-8000-000000000002" }; body = "hello"; ttlSeconds = 60 }
$deliverReq = Req "session.deliver" $deliverArgs
Check ((ConvertTo-HordeFrameBytes -Frame $deliverReq).ok -eq $true) "CONTROL: the session.deliver request is well formed, so only the verb gate can refuse it"
$r = Ask "session.deliver" $deliverArgs
Check ("$($r.reply.kind)" -ceq "res" -and "$($r.reply.error.code)" -ceq "unsupported-verb" -and (Sendable $r.reply)) "session.deliver, a drive verb, is refused as unsupported: nothing is typed into any session"
$closeArgs = [pscustomobject][ordered]@{ sessionId = "s-1"; expect = [pscustomobject][ordered]@{ ns = [pscustomobject][ordered]@{ device = $device; space = "windows" }; pid = 4242; procStart = "133420000000000000" }; reason = "done" }
$r = Ask "session.close" $closeArgs
Check ("$($r.reply.error.code)" -ceq "unsupported-verb" -and "$($r.reply.error.reason)" -clike "*node.info, sessions.list, session.get, request.status*" -and (Sendable $r.reply)) "a well-formed session.close is refused as unsupported, naming what this node answers"
$r = Ask "handoff.get" ([pscustomobject][ordered]@{ sessionId = "s-1"; handoffId = (New-HordeLinkFrameId) })
Check ("$($r.reply.error.code)" -ceq "unsupported-verb") "a read verb of a later step (handoff.get, R14) is refused too"

Write-Host ""
Write-Host "--- node.info ---" -ForegroundColor Cyan
$r = Ask "node.info"
Check ("$($r.reply.result.state)" -ceq "known" -and "$($r.reply.result.value.deviceId)" -ceq $device -and (Sendable $r.reply)) "node.info answers this node's manifest, in a frame the contract accepts"

Write-Host ""
Write-Host "--- sessions.list ---" -ForegroundColor Cyan
$r = Ask "sessions.list"
Check ($r.needView -eq $true -and $null -eq $r.reply) "sessions.list asks for the projection first, and sends nothing until it has it"
$r = Ask "sessions.list" -View (View)
$v = $r.reply.result.value
Check ("$($r.reply.result.state)" -ceq "known" -and @($v.sessions).Count -eq 2 -and (Sendable $r.reply)) "sessions.list answers every session of the view, in a frame the contract accepts"
Check ($v.complete.value -eq $false -and "$($v.complete.reason)" -clike "*X4*no host adapter*") "with one store unreadable, complete is known false and names the store and why"
$one = @($v.sessions)[0]
$two = @($v.sessions)[1]
$keys = @($one.PSObject.Properties | ForEach-Object { $_.Name }) -join ","
Check ($keys -ceq "sessionId,agent,fleetSessionId,role,label,parent,liveStatus,workState,startedAt,lastActivity,retired,pid,procStart,projectCwd") "a session crosses as the fixed summary only: no transcript path, no resume command"
Check ("$($one.agent.value)" -ceq "harness-a" -and "$($one.fleetSessionId.value)" -ceq "fix-login-form" -and "$($one.startedAt.value)" -ceq "2026-10-02T09:00:00Z" -and $one.retired.value -eq $false) "the agent, fleet session id, start and retirement cross: the hub's mirror keys and ages by them"
Check ("$($two.fleetSessionId.state)" -ceq "unknown" -and "$($two.fleetSessionId.reason)" -clike "*has no field fleetSessionId*") "a field the view does not have crosses as unknown, saying so"
Check ("$($one.pid.value)" -ceq "4242" -and "$($one.pid.ns.device)" -ceq $device -and "$($one.pid.ns.space)" -ceq "windows") "the pid crosses with its namespace (R11)"
Check ("$($one.procStart.ns.device)" -ceq $device -and "$($one.projectCwd.ns.device)" -ceq $device -and "$($one.projectCwd.value)" -ceq "C:\work\app") "the procStart and the project directory cross placed too"
Check ("$($two.label.state)" -ceq "unknown" -and "$($two.label.reason)" -ceq "no label recorded" -and "$($two.parent.state)" -ceq "absent") "an unknown crosses with its reason, and an absent as absent"
$text = Line $r.reply
Check ($text -cnotlike "*transcript.jsonl*" -and $text -cnotlike "*never crosses*") "CONTROL: the view's transcript path and resume command are in the fixture and not on the wire"
$full = View
foreach ($p in @($full.complete.PSObject.Properties)) { $p.Value.state = "known"; $p.Value | Add-Member -NotePropertyName value -NotePropertyValue $true -Force; $p.Value | Add-Member -NotePropertyName observedAt -NotePropertyValue "2026-10-02T12:00:00.000Z" -Force }
$r = Ask "sessions.list" -View $full
Check ($r.reply.result.value.complete.value -eq $true) "with every store readable, complete is known true"
$empty = View
$empty.complete = [pscustomobject]@{}
$r = Ask "sessions.list" -View $empty
Check ($r.reply.result.value.complete.value -eq $false) "a view naming no store is not complete"

Write-Host ""
Write-Host "--- values the link cannot carry become unknowns, never cut or reshaped ---" -ForegroundColor Cyan
$odd = View
$f1 = @($odd.sessions)[0].fields
$f1.pid.value = -1
$f1.projectCwd.value = ("C:\work\" + [char]7 + "bell")
$f1.role.value = "not a token!"
$f1.retired.value = "no"
$r = Ask "sessions.list" -View $odd
$o = @($r.reply.result.value.sessions)[0]
Check ("$($o.pid.state)" -ceq "unknown" -and "$($o.pid.reason)" -clike "*pid*" -and "$($o.pid.ns.device)" -ceq $device) "a pid below 1 is unknown with the reason, and still placed"
Check ("$($o.projectCwd.state)" -ceq "unknown" -and "$($o.role.state)" -ceq "unknown") "a directory with a control character, and a role that is not a token, are unknown"
Check ("$($o.retired.state)" -ceq "unknown" -and "$($o.retired.reason)" -clike "*retired*bool*") "a retired flag that is text, not true or false, is unknown with the reason, never read as a flag"
Check (Sendable $r.reply) "and the frame still passes the contract"

Write-Host ""
Write-Host "--- every answer fits the wire, whatever the view holds ---" -ForegroundColor Cyan
$big = View
@($big.sessions)[0].fields.label = [pscustomobject]@{ state = "unknown"; reason = ("x" * 1500) }
$r = Ask "sessions.list" -View $big
Check ((Sendable $r.reply) -and "$(@($r.reply.result.value.sessions)[0].label.reason)".Length -le 1024) "a 1500-character reason is cut to the cap, and the list still goes"
$badId = View
@($badId.sessions)[1].sessionId = "a..b"
$r = Ask "sessions.list" -View $badId
Check ((Sendable $r.reply) -and @($r.reply.result.value.sessions).Count -eq 1 -and "$($r.reply.result.value.complete.reason)" -clike "*1 session(s) left out*ids*") "a session whose id the link cannot carry is left out, the rest go, and complete says so"
$many = View
$proto = @($many.sessions)[0]
$rows = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt 260; $i++) { $c = ($proto | ConvertTo-Json -Depth 10) | ConvertFrom-Json; $c.sessionId = ("bbbbbbbb-0000-4000-8000-" + $i.ToString("000000000000")); [void]$rows.Add($c) }
$many.sessions = $rows.ToArray()
$r = Ask "sessions.list" -View $many
# Whether the capped list fits one frame is test\test-node-serve-capacity.ps1, which encodes it: about
# 2 s since fix/link-writer-speed (200 s before), still a cost every mutant of the node would pay again.
Check (@($r.reply.result.value.sessions).Count -eq 256 -and "$($r.reply.result.value.complete.reason)" -clike "*4 session(s) left out past the list cap*") "past 256 sessions the list is cut at the cap, and complete says how many were left out"
$longPath = View
@($longPath.sessions)[0].fields.projectCwd.value = ("C:" + ("\abcdefg" * 31))
$r = Ask "sessions.list" -View $longPath
Check ((Sendable $r.reply) -and "$(@($r.reply.result.value.sessions)[0].projectCwd.state)" -ceq "unknown") "a path within 255 characters but past 256 bytes on the wire, once escaped, is unknown, not unsendable"
$noTime = View
$noTime.PSObject.Properties.Remove("observedAt")
# $r is cleared first: a node that throws here must not leave the last answer to be checked instead.
$r = $null
$r = Ask "sessions.list" -View $noTime
Check ($null -ne $r -and (Sendable $r.reply) -and "$($r.reply.result.value.observedAt)" -cmatch '^[0-9]{4}-') "a view with no observation time is answered with the node's own time, not dropped"
$r = Ask "sessions.list" -View (View) -ViewError "the store is locked"
Check ("$($r.reply.error.code)" -ceq "internal" -and "$($r.reply.error.reason)" -clike "*the store is locked*" -and (Sendable $r.reply)) "a view that could not be built is an internal error to that request, never silence"

Write-Host ""
Write-Host "--- session.get ---" -ForegroundColor Cyan
$r = Ask "session.get" ([pscustomobject]@{ sessionId = "aaaaaaaa-0000-4000-8000-000000000001" }) -View (View)
Check ("$($r.reply.result.state)" -ceq "known" -and "$($r.reply.result.value.sessionId)" -ceq "aaaaaaaa-0000-4000-8000-000000000001" -and (Sendable $r.reply)) "session.get answers one session's summary"
$r = Ask "session.get" ([pscustomobject]@{ sessionId = "bbbbbbbb-0000-4000-8000-000000000009" }) -View (View)
Check ("$($r.reply.result.state)" -ceq "unknown" -and "$($r.reply.result.reason)" -clike "*not every store*" -and (Sendable $r.reply)) "a session missing from an incomplete projection is unknown, never absent"
$r = Ask "session.get" ([pscustomobject]@{ sessionId = "bbbbbbbb-0000-4000-8000-000000000009" }) -View $full
Check ("$($r.reply.result.state)" -ceq "absent" -and (Sendable $r.reply)) "a session missing from a complete projection is absent"
$r = Ask "session.get" ([pscustomobject]@{ sessionId = "AAAAAAAA-0000-4000-8000-000000000001" }) -View $full
Check ("$($r.reply.result.state)" -ceq "absent") "a session id is matched exactly"
$twin = View
$t2 = (@($twin.sessions)[0] | ConvertTo-Json -Depth 10) | ConvertFrom-Json
$t2.fields.agent.value = "harness-b"
$twin.sessions = @(@($twin.sessions) + @($t2))
$r = Ask "session.get" ([pscustomobject]@{ sessionId = "aaaaaaaa-0000-4000-8000-000000000001" }) -View $twin
Check ("$($r.reply.result.state)" -ceq "unknown" -and "$($r.reply.result.reason)" -clike "*2 sessions*name the agent*") "an id two harnesses hold is unknown until the agent is named, never the first one found"
$r = Ask "session.get" ([pscustomobject][ordered]@{ sessionId = "aaaaaaaa-0000-4000-8000-000000000001"; agent = "harness-b" }) -View $twin
Check ("$($r.reply.result.state)" -ceq "known" -and "$($r.reply.result.value.agent.value)" -ceq "harness-b" -and (Sendable $r.reply)) "naming the agent chooses that harness's session"
$manyMissing = View
foreach ($n in @("W1", "W2", "W3", "W4", "W5", "W6", "W8", "X1", "X2", "X3", "X5", "X6")) { $manyMissing.complete.$n = [pscustomobject]@{ state = "unknown"; reason = ("store " + $n + " could not be read because " + ("of a long story " * 6)) } }
$r = Ask "session.get" ([pscustomobject]@{ sessionId = "bbbbbbbb-0000-4000-8000-000000000009" }) -View $manyMissing
Check ("$($r.reply.result.state)" -ceq "unknown" -and (Sendable $r.reply)) "a missing session beside many unreadable stores is still answered within the reason cap"

Write-Host ""
Write-Host "--- request.status ---" -ForegroundColor Cyan
$rid = New-HordeLinkFrameId
$r = Ask "request.status" ([pscustomobject]@{ requestId = $rid })
Check ("$($r.reply.result.state)" -ceq "unknown" -and "$($r.reply.result.reason)" -clike "*no request journal*" -and (Sendable $r.reply)) "a node with no journal answers unknown, never absent"
$jr = Join-Path $env:TEMP ("horde-node-serve-" + [guid]::NewGuid().ToString("N"))
try {
    Initialize-HordeJournal -Root $jr -Kind "request" | Out-Null
    $issued = [datetime]::UtcNow
    $null = Open-HordeJournalEntry -Root $jr -Id $rid -Verb "session.spawn" -Arguments @{ n = 1 } -IssuedAt $issued
    $r = Ask "request.status" ([pscustomobject]@{ requestId = $rid }) -Journal $jr
    Check ("$($r.reply.result.state)" -ceq "known" -and "$($r.reply.result.value.requestId)" -ceq $rid -and "$($r.reply.result.value.state)" -ceq "accepted" -and (Sendable $r.reply)) "a journaled request is answered with its entry, in the closed request-entry shape"
    Check ("$($r.reply.result.value.argsHash)" -cmatch '^[0-9a-f]{64}$' -and "$($r.reply.result.value.verb)" -ceq "session.spawn") "the entry carries its arguments' hash and its verb"
    $r = Ask "request.status" ([pscustomobject]@{ requestId = (New-HordeLinkFrameId) }) -Journal $jr
    Check ("$($r.reply.result.state)" -ceq "absent" -and (Sendable $r.reply)) "a request the journal never saw is absent"
} finally {
    if ((Split-Path -Leaf $jr) -match '^horde-node-serve-[0-9a-f]{32}$') { Remove-Item -LiteralPath $jr -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "--- the contract is read once per link, never per frame or per session ---" -ForegroundColor Cyan
# Measured 2026-10-02: Get-HordeLinkContract parses both link schemas on every call, about 1.4 s, and
# the node read it once per session to check the id; sessions.list over the 31 sessions of the
# projection fixture took 44 s and the real-pipe suite's hub gave up at 60 s. The state now carries
# the contract, read when the link begins; every read after that is a failure here.
$once = State
$lines = @((Line (Hello)), (Line (Req "node.info")), (Line (Req "sessions.list")), (Line (Req "session.get" ([pscustomobject]@{ sessionId = "aaaaaaaa-0000-4000-8000-000000000001" }))), (Line (Req "session.close" $closeArgs)), "not a frame")
$onceView = View
$script:contractReads = 0
$onceReplies = New-Object System.Collections.ArrayList
$onceError = ""
function Get-HordeLinkContract { $script:contractReads++; throw "the contract was read again" }
try {
    foreach ($l in $lines) {
        $r = Invoke-HordeNodeFrame -State $once -Line $l -Data (Data -View $onceView)
        [void]$onceReplies.Add($r.reply)
    }
} catch { $onceError = "$($_.Exception.Message)" }
. (Join-Path $root "remote\Contract.ps1")
Check ($script:contractReads -eq 0 -and $onceError -eq "") ("hello, node.info, sessions.list, session.get, a refusal and a bad line, all answered with the contract read once, when the link began (reads after: " + $script:contractReads + "; " + $onceError + ")")
Check ($onceReplies.Count -eq 6 -and "$($onceReplies[4].error.code)" -ceq "unsupported-verb" -and "$($onceReplies[2].result.state)" -ceq "known" -and "$($onceReplies[3].result.state)" -ceq "known" -and "$($onceReplies[5].kind)" -ceq "bye") "CONTROL: and each was answered, not skipped"
$probe = Get-HordeLinkContract
Check ($null -ne $probe.verbs -and "$((Get-Command Get-HordeLinkContract).ScriptBlock)" -cnotlike "*read again*") "CONTROL: the contract reader is the real one again for the rest of the suite"

Write-Host ""
Write-Host "--- the loop, over the in-process transport, with a fake view ---" -ForegroundColor Cyan
function Start-Node {
    # cli/NodeServe.ps1's real loop in a second runspace, on the memory transport; returns its handles.
    param([int]$IdleTimeoutMs = 30000, [switch]$ThrowOnView)
    $ready = New-Object System.Threading.ManualResetEventSlim($false)
    $counter = [hashtable]::Synchronized(@{ views = 0 })
    $ps = [PowerShell]::Create()
    [void]$ps.AddCommand((Join-Path $fx "serve-peer.ps1")).AddParameter("Root", $root).AddParameter("Endpoint", $device).AddParameter("ViewPath", $viewPath).AddParameter("MaxLinks", 1).AddParameter("IdleTimeoutMs", $IdleTimeoutMs).AddParameter("Counter", $counter).AddParameter("Ready", $ready)
    if ($ThrowOnView) { [void]$ps.AddParameter("ThrowOnView", $true) }
    $h = $ps.BeginInvoke()
    $up = $ready.Wait(30000)
    return [pscustomobject]@{ ps = $ps; h = $h; counter = $counter; up = $up }
}
function Stop-Node {
    # Waits for the node to finish its one link and returns what Invoke-HordeNodeServe returned.
    param($Node)
    $out = $null
    if ($Node.h.AsyncWaitHandle.WaitOne(40000)) { try { $out = @($Node.ps.EndInvoke($Node.h)) } catch { Write-Host ("         node side: " + $_.Exception.Message) -ForegroundColor Red } } else { try { $Node.ps.Stop() } catch { } }
    $Node.ps.Dispose()
    return (@($out | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties["served"] }) | Select-Object -First 1)
}
function Talk {
    param($Link, $Frame)
    $null = Send-HordeLinkFrame -Link $Link -Frame (Line $Frame)
    $got = Receive-HordeLinkFrame -Link $Link -TimeoutMs 30000
    if ("$($got.state)" -cne "known") { return $null }
    $d = ConvertFrom-HordeFrameBytes -Bytes ([System.Text.Encoding]::ASCII.GetBytes("$($got.value)"))
    if (-not $d.ok) { Write-Host ("         refused: " + $d.reason) -ForegroundColor DarkYellow; return $null }
    return $d.frame
}
function Dial {
    $open = Open-HordeTransportLink -Transport (Get-HordeTransport -Name "memory") -Endpoint $device -Role "hub"
    if ("$($open.state)" -cne "known") { Write-Host ("         no link: " + $open.reason) -ForegroundColor DarkYellow; return $null }
    return $open.value
}

$node = Start-Node
$link = $null
try {
    Check ($node.up -eq $true) "the node is listening"
    $link = Dial
    Check ($null -ne $link) "the hub opens a link to the node"
    $hi = Talk $link (Hello)
    Check ($null -ne $hi -and "$($hi.kind)" -ceq "hello" -and "$($hi.hello.id)" -ceq $device) "over the link, the node's hello arrives and passes the hub's decoder"
    $info = Talk $link (Req "node.info")
    Check ($null -ne $info -and "$($info.result.value.deviceName)" -ceq "fixture-node") "node.info arrives over the link"
    $list = Talk $link (Req "sessions.list")
    Check ($null -ne $list -and @($list.result.value.sessions).Count -eq 2 -and $list.result.value.complete.value -eq $false) "sessions.list arrives over the link, built from the view the node was given"
    $again = Talk $link (Req "sessions.list")
    Check ($null -ne $again -and [int]$node.counter["views"] -eq 2) ("the view is built afresh for each request that needs it (" + $node.counter["views"] + " builds for 2 lists)")
    $null = Send-HordeLinkFrame -Link $link -Frame (Line (New-HordeLinkBye -Code "shutdown" -Reason "the hub is finished" -Seq 9))
} finally { if ($null -ne $link) { Close-HordeLink -Link $link } }
$served = Stop-Node $node
Check ($null -ne $served -and $served.served -eq 1 -and "$(@($served.endings)[0])" -clike "*closed by the protocol*") "the node served one link and ended it on the hub's bye"

$node = Start-Node -ThrowOnView
$link = $null
try {
    $link = Dial
    $null = Talk $link (Hello)
    $broken = Talk $link (Req "sessions.list")
    Check ($null -ne $broken -and "$($broken.error.code)" -ceq "internal" -and "$($broken.error.reason)" -clike "*could not build its view*broken on purpose*") "a projection that throws is an internal error to that request, saying the view could not be built"
    $after = Talk $link (Req "node.info")
    Check ($null -ne $after -and "$($after.result.state)" -ceq "known") "and the link and the node go on: the next request is answered"
    $null = Send-HordeLinkFrame -Link $link -Frame (Line (New-HordeLinkBye -Code "shutdown" -Reason "the hub is finished" -Seq 9))
} finally { if ($null -ne $link) { Close-HordeLink -Link $link } }
$served = Stop-Node $node
Check ($null -ne $served -and $served.served -eq 1) "the node that met a broken projection still served its link to the end"

$node = Start-Node -IdleTimeoutMs 1500
$link = $null
try {
    $link = Dial
    $null = Talk $link (Hello)
    Start-Sleep -Milliseconds 4000
    $late = Talk $link (Req "node.info")
    Check ($null -eq $late) "a hub silent past the idle limit finds the link ended"
} finally { if ($null -ne $link) { Close-HordeLink -Link $link } }
$served = Stop-Node $node
Check ($null -ne $served -and "$(@($served.endings)[0])" -clike "*the link ended*") ("the node ended the idle link itself (" + "$(@($served.endings)[0])" + ")")

Complete-HordeSuite -Success "the node answers hello, node.info, sessions.list, session.get and request.status, refuses the rest, and every frame it sends is one the contract accepts"
