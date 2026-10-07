# DOES THE NODE ACT ON session.spawn AND session.close EXACTLY ONCE PER REQUEST ID, AND SAY SO?
#
# Remote plan R19, the act path's A3 (2026-10-05). remote/NodeServe.ps1 decides, frame by frame, and
# starts nothing: for an act verb it records the request in the journal (remote/Journal.ps1) and hands
# the act to its caller (NeedAct), which acts through the host and agent layers (cli/NodeAct.ps1) and
# hands back the outcome; the node records it and answers with the journal entry. Proven here:
#   - one act per request id: a resend of the same request replays the recorded entry and acts nothing,
#     and the same id with other arguments is refused;
#   - a node with no journal, or that serves no acts, acts on nothing;
#   - a spawn's prompt is text or a handoff reference, not both and not neither; handoff references are
#     not served yet and are refused;
#   - every frame the node sends passes the contract, and request.status reports the outcome.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Platform", "Namespace")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "remote\NodeServe.ps1")

$device = "0f8fad5b-d9cb-469f-a165-70867728950e"
$ns = New-HordeNamespace -Device $device -Space "windows"
$manifest = [pscustomobject]@{ deviceId = $device }
$contract = Get-HordeLinkContract
function State { return (New-HordeNodeServeState -NodeId $device -NodeName "fixture-node" -HordeVersion "0.1.0" -Contract $contract) }
function Data { param([string]$Journal = "", [bool]$Acts = $true, $Outcome = $null) return [pscustomobject]@{ manifest = $manifest; view = $null; viewError = ""; journalRoot = $Journal; namespace = $ns; acts = $Acts; actOutcome = $Outcome } }
function Hello {
    $t = Get-HordeLinkTime
    return [pscustomobject][ordered]@{ v = 1; kind = "hello"; id = (New-HordeLinkFrameId); seq = 1; ts = $t; hello = [pscustomobject][ordered]@{ role = "hub"; id = "7c9e6679-7425-40de-944b-e07fc1f90ae7"; name = "fixture-hub"; protocols = @(1); verbsVersions = @(1); hordeVersion = "0.1.0"; t1 = $t } }
}
function Req {
    param([string]$Verb, $ArgsObject, [string]$RequestId = (New-HordeLinkFrameId), [string]$IssuedAt = (Get-HordeLinkTime))
    return [pscustomobject][ordered]@{ v = 1; kind = "req"; id = (New-HordeLinkFrameId); seq = 2; ts = (Get-HordeLinkTime); verb = $Verb; requestId = $RequestId; issuedAt = $IssuedAt; args = $ArgsObject }
}
function Line { param($Frame) $b = ConvertTo-HordeFrameBytes -Frame $Frame -Contract $contract; if ($b.ok) { return [System.Text.Encoding]::ASCII.GetString($b.bytes, 0, $b.bytes.Length - 1) }; return (ConvertTo-HordeWireText $Frame) }
function Sendable { param($Frame) $b = ConvertTo-HordeFrameBytes -Frame $Frame -Contract $contract; if (-not $b.ok) { Write-Host ("         not sendable: " + $b.reason) -ForegroundColor DarkYellow }; return [bool]$b.ok }
function Linked { $st = State; $null = Invoke-HordeNodeFrame -State $st -Line (Line (Hello)) -Data (Data); return $st }
function Spawn {
    param([hashtable]$Extra = @{})
    $a = [ordered]@{ label = "E"; role = "orc"; runId = "20261005-120000-act"; profile = "alpha"; repoId = "github.com/example/app"; prompt = [pscustomobject]@{ text = "read the plan" }; closeOn = "proof"; title = "client search orc"; permission = "bypass" }
    foreach ($k in $Extra.Keys) { $a[$k] = $Extra[$k] }
    return [pscustomobject]$a
}
$sid = "aaaaaaaa-1111-4222-8333-444444444444"
$expect = [pscustomobject][ordered]@{ ns = [pscustomobject][ordered]@{ device = $device; space = "windows" }; pid = 4242; procStart = "134350994347710308" }
$jr = Join-Path $env:TEMP ("horde-serve-act-" + [guid]::NewGuid().ToString("N"))
Initialize-HordeJournal -Root $jr -Kind "request" | Out-Null

try {
Write-Host ""
Write-Host "--- a spawn is acted on once: recorded, handed over, its outcome recorded and answered ---" -ForegroundColor Cyan
$st = Linked
$q = Req "session.spawn" (Spawn)
Check ((ConvertTo-HordeFrameBytes -Frame $q -Contract $contract).ok -eq $true) "CONTROL: the spawn request is well formed"
$r1 = Invoke-HordeNodeFrame -State $st -Line (Line $q) -Data (Data -Journal $jr)
Check ($r1.needAct -eq $true -and $null -eq $r1.reply -and "$($r1.act.hubId)" -ceq "7c9e6679-7425-40de-944b-e07fc1f90ae7" -and "$($r1.act.verb)" -ceq "session.spawn" -and "$($r1.act.requestId)" -ceq $q.requestId -and "$($r1.act.args.label)" -ceq "E") "the first sight of a spawn is recorded and handed to the caller to act, with the hub that asked, and nothing sent yet"
$e = Get-HordeJournalEntry -Root $jr -Id $q.requestId
Check ($e.state -eq "known" -and "$($e.value.state)" -ceq "accepted") "the journal holds it as accepted before anything acts"
$out = [pscustomobject]@{ state = "done"; sessionId = $sid; expect = $expect; reason = "" }
$r2 = Invoke-HordeNodeFrame -State $st -Line (Line $q) -Data (Data -Journal $jr -Outcome $out)
Check ($r2.needAct -eq $false -and "$($r2.reply.result.state)" -ceq "known" -and "$($r2.reply.result.value.state)" -ceq "done" -and "$($r2.reply.result.value.sessionId)" -ceq $sid -and (Sendable $r2.reply)) "the outcome is answered as the journal entry: done, with the session id"
Check ($r2.reply.result.value.expect.pid -eq 4242 -and "$($r2.reply.result.value.expect.procStart)" -ceq "134350994347710308" -and "$($r2.reply.result.value.expect.ns.device)" -ceq $device) "and with the started process, placed by its device and space, as a later close will carry it back"
$e = Get-HordeJournalEntry -Root $jr -Id $q.requestId
Check ($e.state -eq "known" -and "$($e.value.state)" -ceq "done") "the journal records the outcome"
$r3 = Invoke-HordeNodeFrame -State (Linked) -Line (Line $q) -Data (Data -Journal $jr)
Check ($r3.needAct -eq $false -and "$($r3.reply.result.value.state)" -ceq "done" -and "$($r3.reply.result.value.sessionId)" -ceq $sid -and (Sendable $r3.reply)) "a resend of the same request replays the recorded entry and acts nothing"
$s = Invoke-HordeNodeFrame -State (Linked) -Line (Line (Req "request.status" ([pscustomobject]@{ requestId = $q.requestId }))) -Data (Data -Journal $jr)
Check ("$($s.reply.result.value.state)" -ceq "done" -and "$($s.reply.result.value.sessionId)" -ceq $sid -and $s.reply.result.value.expect.pid -eq 4242 -and (Sendable $s.reply)) "request.status reports the outcome with its session and process"
$other = Req "session.spawn" (Spawn @{ label = "F" }) -RequestId $q.requestId -IssuedAt $q.issuedAt
$r4 = Invoke-HordeNodeFrame -State (Linked) -Line (Line $other) -Data (Data -Journal $jr)
Check ($r4.needAct -eq $false -and "$($r4.reply.error.code)" -ceq "refused" -and "$($r4.reply.error.reason)" -like "*reused*" -and (Sendable $r4.reply)) "the same request id with other arguments is refused and acts nothing"

Write-Host ""
Write-Host "--- a refused or failed outcome is answered as such, with its reason ---" -ForegroundColor Cyan
$q2 = Req "session.spawn" (Spawn)
$st = Linked
$null = Invoke-HordeNodeFrame -State $st -Line (Line $q2) -Data (Data -Journal $jr)
$r = Invoke-HordeNodeFrame -State $st -Line (Line $q2) -Data (Data -Journal $jr -Outcome ([pscustomobject]@{ state = "refused"; sessionId = ""; expect = $null; reason = "the permission level bypass is above this node's ceiling, edits" }))
Check ("$($r.reply.result.value.state)" -ceq "refused" -and "$($r.reply.result.value.reason)" -like "*above this node's ceiling*" -and $null -eq $r.reply.result.value.PSObject.Properties["expect"] -and (Sendable $r.reply)) "a refused spawn is answered refused, with the node's reason and no process"
$q3 = Req "session.spawn" (Spawn)
$st = Linked
$null = Invoke-HordeNodeFrame -State $st -Line (Line $q3) -Data (Data -Journal $jr)
$r = Invoke-HordeNodeFrame -State $st -Line (Line $q3) -Data (Data -Journal $jr -Outcome ([pscustomobject]@{ state = "failed"; sessionId = $sid; expect = $null; reason = ("x" * 3000) }))
Check ("$($r.reply.result.value.state)" -ceq "failed" -and (Sendable $r.reply)) "a failed spawn is answered failed, its long reason cut to the cap"
# A failure here is a failed check, never only a thrown error: a mutant that lets a second outcome
# through throws inside the journal, and that must read as caught (round 1 of the gate).
$r = $null; $err = ""
try { $r = Invoke-HordeNodeFrame -State (Linked) -Line (Line $q3) -Data (Data -Journal $jr -Outcome ([pscustomobject]@{ state = "weird"; sessionId = ""; expect = $null; reason = "" })) } catch { $err = "$($_.Exception.Message)" }
Check ($err -eq "" -and $null -ne $r -and "$($r.reply.result.value.state)" -ceq "failed") ("CONTROL: a resend after the outcome is recorded replays it, whatever outcome the caller offers" + $(if ($err) { " (threw: " + $err + ")" } else { "" }))

Write-Host ""
Write-Host "--- what is never acted on ---" -ForegroundColor Cyan
$r = $null; $err = ""
try { $r = Invoke-HordeNodeFrame -State (Linked) -Line (Line (Req "session.spawn" (Spawn))) -Data (Data -Journal "") } catch { $err = "$($_.Exception.Message)" }
Check ($err -eq "" -and $null -ne $r -and $r.needAct -eq $false -and "$($r.reply.error.code)" -ceq "refused" -and "$($r.reply.error.reason)" -like "*no request journal*" -and (Sendable $r.reply)) ("a node with no request journal acts on nothing" + $(if ($err) { " (threw: " + $err + ")" } else { "" }))
$r = Invoke-HordeNodeFrame -State (Linked) -Line (Line (Req "session.spawn" (Spawn))) -Data (Data -Journal $jr -Acts $false)
Check ($r.needAct -eq $false -and "$($r.reply.error.code)" -ceq "unsupported-verb") "a node that serves no acts refuses an act verb as unsupported"
$r = Invoke-HordeNodeFrame -State (Linked) -Line (Line (Req "session.spawn" (Spawn @{ prompt = [pscustomobject]@{ text = "a"; handoffRef = (New-HordeLinkFrameId) } }))) -Data (Data -Journal $jr)
Check ($r.needAct -eq $false -and "$($r.reply.error.code)" -ceq "refused" -and "$($r.reply.error.reason)" -like "*text or a handoff reference, not both*") "a prompt with both text and a handoff reference is refused"
$r = Invoke-HordeNodeFrame -State (Linked) -Line (Line (Req "session.spawn" (Spawn @{ prompt = [pscustomobject]@{} }))) -Data (Data -Journal $jr)
Check ($r.needAct -eq $false -and "$($r.reply.error.code)" -ceq "refused") "a prompt with neither is refused"
$r = Invoke-HordeNodeFrame -State (Linked) -Line (Line (Req "session.spawn" (Spawn @{ prompt = [pscustomobject]@{ handoffRef = (New-HordeLinkFrameId) } }))) -Data (Data -Journal $jr)
Check ($r.needAct -eq $false -and "$($r.reply.error.reason)" -like "*handoff reference*not served*") "a handoff reference is not served yet, and is refused rather than ignored"
$r = Invoke-HordeNodeFrame -State (Linked) -Line (Line (Req "session.resume" ([pscustomobject][ordered]@{ sessionId = $sid }))) -Data (Data -Journal $jr)
Check ($r.needAct -eq $false -and "$($r.reply.error.code)" -ceq "unsupported-verb") "session.resume is still refused: this step acts only on spawn and close (session.deliver is messaging, R21 slice 4, and is tested there)"

Write-Host ""
Write-Host "--- a close is acted on the same way ---" -ForegroundColor Cyan
$c = Req "session.close" ([pscustomobject][ordered]@{ sessionId = $sid; expect = $expect; reason = "the founder asked" })
$st = Linked
$r1 = Invoke-HordeNodeFrame -State $st -Line (Line $c) -Data (Data -Journal $jr)
Check ($r1.needAct -eq $true -and "$($r1.act.verb)" -ceq "session.close" -and "$($r1.act.args.sessionId)" -ceq $sid) "a close is recorded and handed to the caller"
$r2 = Invoke-HordeNodeFrame -State $st -Line (Line $c) -Data (Data -Journal $jr -Outcome ([pscustomobject]@{ state = "done"; sessionId = $sid; expect = $null; reason = "" }))
Check ("$($r2.reply.result.value.state)" -ceq "done" -and "$($r2.reply.result.value.verb)" -ceq "session.close" -and (Sendable $r2.reply)) "and its outcome answered"
$r3 = Invoke-HordeNodeFrame -State (Linked) -Line (Line $c) -Data (Data -Journal $jr)
Check ($r3.needAct -eq $false -and "$($r3.reply.result.value.state)" -ceq "done") "a resent close acts nothing"
} finally {
    if ((Split-Path -Leaf $jr) -match '^horde-serve-act-[0-9a-f]{32}$') { Remove-Item -LiteralPath $jr -Recurse -Force -ErrorAction SilentlyContinue }
}


Write-Host ""
Write-Host "--- the loop: cli/NodeServe.ps1 acts once per request over a real link (memory transport) ---" -ForegroundColor Cyan
. (Join-Path $root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $root "cli\NodeServe.ps1")
$fxs = Join-Path $root "test\fixtures\node-serve"
function Start-ActNode {
    param([string]$Outcome = "", [switch]$Throws, [string]$Journal)
    $ready = New-Object System.Threading.ManualResetEventSlim($false)
    $counter = [hashtable]::Synchronized(@{ views = 0; acts = 0 })
    $ps = [PowerShell]::Create()
    [void]$ps.AddCommand((Join-Path $fxs "serve-peer.ps1")).AddParameter("Root", $root).AddParameter("Endpoint", $device).AddParameter("ViewPath", (Join-Path $fxs "view.json")).AddParameter("JournalRoot", $Journal).AddParameter("MaxLinks", 1).AddParameter("Counter", $counter).AddParameter("Ready", $ready)
    if ($Outcome -ne "") { [void]$ps.AddParameter("ActOutcome", $Outcome) }
    if ($Throws) { [void]$ps.AddParameter("ActThrows", $true) }
    $h = $ps.BeginInvoke()
    $up = $ready.Wait(30000)
    return [pscustomobject]@{ ps = $ps; h = $h; counter = $counter; up = $up }
}
function Stop-ActNode { param($Node) if ($Node.h.AsyncWaitHandle.WaitOne(40000)) { try { $null = $Node.ps.EndInvoke($Node.h) } catch { } } else { try { $Node.ps.Stop() } catch { } }; $Node.ps.Dispose() }
function Talk {
    param($Link, $Frame)
    $null = Send-HordeLinkFrame -Link $Link -Frame (Line $Frame)
    $got = Receive-HordeLinkFrame -Link $Link -TimeoutMs 30000
    if ("$($got.state)" -cne "known") { return $null }
    $d = ConvertFrom-HordeFrameBytes -Bytes ([System.Text.Encoding]::ASCII.GetBytes("$($got.value)")) -Contract $contract
    if (-not $d.ok) { Write-Host ("         refused: " + $d.reason) -ForegroundColor DarkYellow; return $null }
    return $d.frame
}
$jr2 = Join-Path $env:TEMP ("horde-serve-act-" + [guid]::NewGuid().ToString("N"))
Initialize-HordeJournal -Root $jr2 -Kind "request" | Out-Null
try {
    $node = Start-ActNode -Outcome "done" -Journal $jr2
    $link = $null
    try {
        Check ($node.up -eq $true) "the node is listening, serving acts"
        $open = Open-HordeTransportLink -Transport (Get-HordeTransport -Name "memory") -Endpoint $device -Role "hub"
        $link = $open.value
        $null = Talk $link (Hello)
        $q = Req "session.spawn" (Spawn)
        $a1 = Talk $link $q
        Check ($null -ne $a1 -and "$($a1.result.value.state)" -ceq "done" -and "$($a1.result.value.sessionId)" -ceq $sid -and $a1.result.value.expect.pid -eq 4242) "a spawn over the link is acted on and answered done, with its session and process"
        $a2 = Talk $link $q
        Check ($null -ne $a2 -and "$($a2.result.value.state)" -ceq "done" -and [int]$node.counter["acts"] -eq 1) ("the same request sent again is answered from the journal: the act ran once (" + $node.counter["acts"] + ")")
        $null = Send-HordeLinkFrame -Link $link -Frame (Line (New-HordeLinkBye -Code "shutdown" -Reason "done" -Seq 9))
    } finally { if ($null -ne $link) { Close-HordeLink -Link $link } }
    Stop-ActNode $node
    $node = Start-ActNode -Throws -Journal $jr2
    $link = $null
    try {
        $open = Open-HordeTransportLink -Transport (Get-HordeTransport -Name "memory") -Endpoint $device -Role "hub"
        $link = $open.value
        $null = Talk $link (Hello)
        $q = Req "session.spawn" (Spawn)
        $a = Talk $link $q
        Check ($null -ne $a -and "$($a.result.value.state)" -ceq "failed" -and "$($a.result.value.reason)" -like "*failed while acting*") "an act that throws is answered failed, and the journal gets that outcome"
        $e = Get-HordeJournalEntry -Root $jr2 -Id $q.requestId
        Check ($e.state -eq "known" -and "$($e.value.state)" -ceq "failed") "so the request is never left accepted with no outcome"
        $null = Send-HordeLinkFrame -Link $link -Frame (Line (New-HordeLinkBye -Code "shutdown" -Reason "done" -Seq 9))
    } finally { if ($null -ne $link) { Close-HordeLink -Link $link } }
    Stop-ActNode $node
} finally {
    if ((Split-Path -Leaf $jr2) -match '^horde-serve-act-[0-9a-f]{32}$') { Remove-Item -LiteralPath $jr2 -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "the node acts on spawn and close once per request id, records each outcome, and answers it in frames the contract accepts"
