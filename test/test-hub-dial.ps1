# DOES THE HUB TAKE A LINK A NODE DIALLED, BOUND TO THE DEVICE ITS PREAMBLE NAMES, AND DOES THE NODE DIAL?
#
# Remote plan R17c, slices 1 and 2. A node behind NAT dials the hub's listener over its link transport; the hub's forced
# command (R17a's cli\attach.ps1) dials the hub pipe and writes one preamble line, "horde-attach 1
# <device id>", the device the node's key is enrolled as. The hub reads it, binds the link to that device,
# refuses a hello claiming another, and runs the same pull it runs on a link it opened
# (cli/HubServe.ps1). The node dials, answers on its own link as it answers an accepted one, and dials
# again with a growing wait while the hub cannot be reached (cli/NodeServe.ps1, Invoke-HordeNodeDial).
#
# Without a server or a pipe: both ends on the in-process memory transport, the node in a second runspace
# (test/fixtures/node-serve/dial-peer.ps1), whose transport writes the preamble as attach will. The live
# dial is R17c-3 (test-transport-conformance's live far end).
#
# R17a OWNS THE PREAMBLE CONTRACT (remote/LinkBinding.ps1, tested on its own by test/test-link-binding.ps1).
# cli/HubServe.ps1 calls it and restates none of it (issue #144, item 7): the preamble cases here run
# through the hub's own reader.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Platform", "Namespace", "ReadShared", "FileAtomic")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $root "remote\NodeServe.ps1")
. (Join-Path $root "remote\Mirror.ps1")
. (Join-Path $root "cli\NodeServe.ps1")
. (Join-Path $root "cli\HubServe.ps1")
. (Join-Path $root "remote\Journal.ps1")

$fx = Join-Path $root "test\fixtures\node-serve"
$viewPath = Join-Path $fx "view.json"
$device = "0f8fad5b-d9cb-469f-a165-70867728950e"
$other = "9b2e4c1a-3f5d-4e6a-8b7c-0d1e2f3a4b5c"
$hubId = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
$hub = [pscustomobject]@{ id = $hubId; name = "fixture-hub"; hordeVersion = "0.1.0" }
$contract = Get-HordeLinkContract
$mem = Get-HordeTransport -Name "memory"
$work = Join-Path $env:TEMP ("horde-hub-dial-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null

function Start-Dialler {
    # The node's dialling loop in a second runspace; it dials at once.
    param([string]$HubEndpoint, [string]$As = $device, [AllowEmptyString()][string]$Preamble, [int]$MaxDials = 1, [string]$JournalRoot = "", [switch]$Acts, [switch]$ReadOnly, [string]$MessagingHome = "", $Counter = $null)
    $ps = [PowerShell]::Create()
    [void]$ps.AddCommand((Join-Path $fx "dial-peer.ps1")).AddParameter("Root", $root).AddParameter("HubEndpoint", $HubEndpoint).AddParameter("DeviceId", $As).AddParameter("ViewPath", $viewPath).AddParameter("Preamble", $Preamble).AddParameter("MaxDials", $MaxDials).AddParameter("IdleTimeoutMs", 20000).AddParameter("JournalRoot", $JournalRoot).AddParameter("MessagingHome", $MessagingHome).AddParameter("Counter", $Counter)
    if ($Acts) { [void]$ps.AddParameter("Acts", $true) }
    if ($ReadOnly) { [void]$ps.AddParameter("ReadOnly", $true) }
    return [pscustomobject]@{ ps = $ps; h = $ps.BeginInvoke() }
}
# A fake hub's side of one dialled link, frame by frame (test/test-node-serve-act.ps1's helpers).
function Hello {
    $t = Get-HordeLinkTime
    return [pscustomobject][ordered]@{ v = 1; kind = "hello"; id = (New-HordeLinkFrameId); seq = 1; ts = $t; hello = [pscustomobject][ordered]@{ role = "hub"; id = $hubId; name = "fixture-hub"; protocols = @(1); verbsVersions = @(1); hordeVersion = "0.1.0"; t1 = $t } }
}
function Req {
    param([string]$Verb, $ArgsObject)
    return [pscustomobject][ordered]@{ v = 1; kind = "req"; id = (New-HordeLinkFrameId); seq = 2; ts = (Get-HordeLinkTime); verb = $Verb; requestId = (New-HordeLinkFrameId); issuedAt = (Get-HordeLinkTime); args = $ArgsObject }
}
function Spawn { return [pscustomobject][ordered]@{ label = "E"; role = "orc"; runId = "20261007-120000-dial"; profile = "alpha"; repoId = "github.com/example/app"; prompt = [pscustomobject]@{ text = "read the plan" }; closeOn = "proof"; title = "dialled orc"; permission = "bypass" } }
function Deliver { return [pscustomobject][ordered]@{ messageId = (New-HordeLinkFrameId); sessionId = "aaaaaaaa-1111-4222-8333-444444444444"; label = "A12"; from = [pscustomobject][ordered]@{ deviceId = $hubId; sessionId = "bbbbbbbb-0000-4000-8000-000000000009"; label = "M" }; body = "hello over a dialled link"; ttlSeconds = 3600 } }
function Line { param($Frame) $b = ConvertTo-HordeFrameBytes -Frame $Frame -Contract $contract; if (-not $b.ok) { throw ("not sendable: " + $b.reason) }; return [System.Text.Encoding]::ASCII.GetString($b.bytes, 0, $b.bytes.Length - 1) }
function Talk {
    param($Link, $Frame)
    $null = Send-HordeLinkFrame -Link $Link -Frame (Line $Frame)
    $got = Receive-HordeLinkFrame -Link $Link -TimeoutMs 30000
    if ("$($got.state)" -cne "known") { return $null }
    $d = ConvertFrom-HordeFrameBytes -Bytes ([System.Text.Encoding]::ASCII.GetBytes("$($got.value)")) -Contract $contract
    if (-not $d.ok) { return $null }
    return $d.frame
}
function Ask-Dialled {
    # Start a dialling node with -Opts, accept its link as a fake hub, say hello, send -Frame, and return
    # { answer; node }.
    param([hashtable]$Opts, $Frame)
    $ep = "hub-ask-" + [guid]::NewGuid().ToString("N").Substring(0, 12)
    $listener = New-HubListener -Name $ep
    $answer = $null
    $nd = $null
    try {
        $node = Start-Dialler -HubEndpoint $ep -Preamble "" @Opts
        $acc = Receive-HordeTransportLink -Listener $listener -TimeoutMs 20000
        if ($acc.state -ceq "known") {
            $link = $acc.value
            try {
                $null = Talk $link (Hello)
                $answer = Talk $link $Frame
                $null = Send-HordeLinkFrame -Link $link -Frame (Line (New-HordeLinkBye -Code "shutdown" -Reason "done" -Seq 9 -Contract $contract))
            } finally { Close-HordeLink -Link $link }
        }
        $nd = Stop-Dialler $node
    } finally { Stop-HordeTransportListener -Listener $listener }
    return [pscustomobject]@{ answer = $answer; node = $nd }
}
function Stop-Dialler {
    param($Node)
    $out = $null
    if ($Node.h.AsyncWaitHandle.WaitOne(40000)) { try { $out = @($Node.ps.EndInvoke($Node.h)) } catch { Write-Host ("         node side: " + $_.Exception.Message) -ForegroundColor Red } } else { try { $Node.ps.Stop() } catch { } }
    $Node.ps.Dispose()
    return (@($out | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties["dials"] }) | Select-Object -First 1)
}
function New-HubListener {
    param([string]$Name)
    $l = Start-HordeTransportListener -Transport $mem -Endpoint $Name
    if ($l.state -cne "known") { throw ("the test hub could not listen: " + $l.reason) }
    return $l.value
}
function Mirror-Of {
    param([string]$Root, [string]$Id)
    return (Read-HordeHubMirror -Path (Get-HordeHubMirrorPath -Root $Root -DeviceId $Id) -DeviceId $Id -Contract $contract)
}

try {
    Write-Host ""
    Write-Host "--- the preamble: one exact line, or nothing is bound ---" -ForegroundColor Cyan
    $ok = Read-HordeAttachPreamble -Line ("horde-attach 1 " + $device)
    Check ($ok.state -ceq "known" -and $ok.value -ceq $device) "CONTROL: 'horde-attach 1 <device id>' binds that device"
    $bad = [ordered]@{
        "another version" = ("horde-attach 2 " + $device)
        "an uppercase id" = ("horde-attach 1 " + $device.ToUpperInvariant())
        "a leading space" = (" horde-attach 1 " + $device)
        "a trailing word" = ("horde-attach 1 " + $device + " x")
        "a JSON frame" = ('{"preamble":{"deviceId":"' + $device + '"}}')
        "a hello" = '{"v":1,"kind":"hello"}'
        "nothing" = ""
    }
    foreach ($k in $bad.Keys) {
        $r = Read-HordeAttachPreamble -Line $bad[$k]
        Check ($r.state -ceq "unknown" -and "$($r.reason)" -clike "*preamble*") ("a first line of " + $k + " binds nothing, and says so (" + $r.reason + ")")
    }

    Write-Host ""
    Write-Host "--- a node dials, and the hub pulls it over the node's own link ---" -ForegroundColor Cyan
    $mr = Join-Path $work "mirror-a"
    $ep = "hub-" + $hubId
    $listener = New-HubListener -Name $ep
    try {
        $node = Start-Dialler -HubEndpoint $ep -Preamble ("horde-attach 1 " + $device)
        $rounds = @(Invoke-HordeHubServe -Nodes @() -Root $mr -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 8000 -TimeoutMs 20000 -Listener $listener)
        $nd = Stop-Dialler $node
    } finally { Stop-HordeTransportListener -Listener $listener }
    $outs = @($rounds[0].outcomes)
    Check (@($outs | Where-Object { $_ -clike ("*(" + $device + "): heard, 2 session(s)*") }).Count -eq 1) ("the hub hears the dialled node in the round it dialled into (" + ($outs -join " | ") + ")")
    $m = Mirror-Of -Root $mr -Id $device
    Check ($m.state -ceq "known" -and @($m.value.inventory.list.sessions).Count -eq 2 -and "$($m.value.deviceName)" -ceq "dialling-node") ("and keeps its mirror under the bound device, named as its hello says (" + $m.state + " " + $m.reason + ")")
    Check ($null -ne $nd -and $nd.dials -eq 1 -and $nd.served -eq 1 -and "$(@($nd.endings)[0])" -ceq "closed by the protocol") ("the node served the link it dialled until the hub's bye (" + "$(@($nd.endings) -join ' | ')" + "$(@($nd.failures) -join ' | ')" + ")")

    Write-Host ""
    Write-Host "--- a round whose pulls ran past its interval still listens (issue #144, item 2) ---" -ForegroundColor Cyan
    Check ((Get-HordeHubDialWindowMs -IntervalMs 20000 -ElapsedMs 3000 -MinMs 5000) -eq 17000) "CONTROL: a quick round listens for the rest of its interval"
    Check ((Get-HordeHubDialWindowMs -IntervalMs 20000 -ElapsedMs 60000 -MinMs 5000) -eq 5000) "a round whose pulls took 60 s of a 20 s interval still listens for the guaranteed 5 s"
    Check ((Get-HordeHubDialWindowMs -IntervalMs 20000 -ElapsedMs 60000 -MinMs -5) -eq 0) "and a floor below 0 is 0, never a negative wait"
    Check ($script:HordeHubDialWindowMinMs -ge 1000) ("the default floor is a real window (" + $script:HordeHubDialWindowMinMs + " ms)")
    # The interval is 1 ms, so every round has run past it before it listens: before the floor, the
    # window was 0 and this node was never taken.
    $mr = Join-Path $work "mirror-late"
    $listener = New-HubListener -Name $ep
    try {
        $node = Start-Dialler -HubEndpoint $ep -Preamble ("horde-attach 1 " + $device)
        $rounds = @(Invoke-HordeHubServe -Nodes @() -Root $mr -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 1 -DialWindowMinMs 8000 -TimeoutMs 20000 -Listener $listener)
        $nd = Stop-Dialler $node
    } finally { Stop-HordeTransportListener -Listener $listener }
    $outs = @($rounds[0].outcomes)
    Check (@($outs | Where-Object { $_ -clike ("*(" + $device + "): heard, 2 session(s)*") }).Count -eq 1) ("a round with no time left of its interval still takes the dialled node (" + ($outs -join " | ") + ")")

    Write-Host ""
    Write-Host "--- a hello that claims another device than the preamble is refused ---" -ForegroundColor Cyan
    $mr = Join-Path $work "mirror-b"
    $listener = New-HubListener -Name $ep
    try {
        $node = Start-Dialler -HubEndpoint $ep -As $device -Preamble ("horde-attach 1 " + $other)
        $rounds = @(Invoke-HordeHubServe -Nodes @() -Root $mr -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 8000 -TimeoutMs 20000 -Listener $listener)
        $nd = Stop-Dialler $node
    } finally { Stop-HordeTransportListener -Listener $listener }
    $outs = @($rounds[0].outcomes)
    Check (@($outs | Where-Object { $_ -clike ("*(" + $other + "): unreachable: *claims device '" + $device + "'*enrolled for device " + $other + "*") }).Count -eq 1) ("the hub refuses the hello, naming both devices (" + ($outs -join " | ") + ")")
    Check (-not (Test-Path -LiteralPath (Get-HordeHubMirrorPath -Root $mr -DeviceId $device))) "and writes nothing under the device the hello claimed"
    $bm = Mirror-Of -Root $mr -Id $other
    Check ($bm.state -ceq "known" -and "$(Get-HordeLinkProp (Get-HordeLinkProp $bm.value 'lost') 'reason')" -clike "*enrolled for device*" -and $null -eq (Get-HordeLinkProp $bm.value "inventory")) "the bound device's mirror records the failed round, never an inventory from the other"
    Check ($null -ne $nd -and $nd.served -eq 1 -and "$(@($nd.endings)[0])" -clike "*closed by the protocol*") ("the node got the hub's bye (" + "$(@($nd.endings) -join ' | ')" + ")")

    Write-Host ""
    Write-Host "--- no preamble, or a wrong one, binds nothing and ends the link ---" -ForegroundColor Cyan
    foreach ($case in @(@{ name = "a wrong version"; pre = ("horde-attach 2 " + $device); want = "*preamble is version '2'*" }, @{ name = "no preamble"; pre = ""; want = "*no preamble came*" })) {
        $mr = Join-Path $work ("mirror-" + [guid]::NewGuid().ToString("N").Substring(0, 6))
        $listener = New-HubListener -Name $ep
        try {
            $node = Start-Dialler -HubEndpoint $ep -Preamble $case.pre
            $rounds = @(Invoke-HordeHubServe -Nodes @() -Root $mr -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 6000 -TimeoutMs 3000 -Listener $listener)
            $nd = Stop-Dialler $node
        } finally { Stop-HordeTransportListener -Listener $listener }
        $outs = @($rounds[0].outcomes)
        Check (@($outs | Where-Object { $_ -clike ("a dialled link was refused: " + $case.want) }).Count -eq 1) ("with " + $case.name + " the link is refused, saying why (" + ($outs -join " | ") + ")")
        Check (@(Get-ChildItem -LiteralPath $mr -File -ErrorAction SilentlyContinue).Count -eq 0) ("and no mirror is written for anyone (" + $case.name + ")")
        Check ($null -ne $nd -and "$(@($nd.endings)[0])" -clike "the link ended: *") ("and the node's link ends, closed by the hub (" + "$(@($nd.endings) -join ' | ')" + ")")
    }
    # The refusing path closes the hub's end itself; seen from the hub's side of one link.
    $listener = New-HubListener -Name $ep
    try {
        $o = Open-HordeTransportLink -Transport $mem -Endpoint $ep -Role "node" -TimeoutMs 2000
        $null = Send-HordeLinkFrame -Link $o.value -Frame "not a preamble"
        $acc = Receive-HordeTransportLink -Listener $listener -TimeoutMs 2000
        $said = Invoke-HordeHubDialled -Link $acc.value -Root (Join-Path $work "mirror-c") -Hub $hub -Contract $contract -TimeoutMs 2000
        Check ($said -clike "a dialled link was refused:*" -and $acc.value.closed) ("a refused dialled link is closed at the hub's end (" + $said + ")")
        Close-HordeLink -Link $o.value
    } finally { Stop-HordeTransportListener -Listener $listener }

    Write-Host ""
    Write-Host "--- a dialled link is served as an accepted one is: acts, read-only, messaging ---" -ForegroundColor Cyan
    # Dial is the always-on box's production path: a node started -ReadOnly that dials in must not act
    # (coordinator, 2026-10-07). A fake hub accepts the dialled link and asks for a spawn.
    $jA = Join-Path $work "journal-acts"
    Initialize-HordeJournal -Root $jA -Kind "request" | Out-Null
    $count = [hashtable]::Synchronized(@{ acts = 0 })
    $q = Req "session.spawn" (Spawn)
    $r = Ask-Dialled -Opts @{ JournalRoot = $jA; Acts = $true; Counter = $count } -Frame $q
    Check ($null -ne $r.answer -and "$($r.answer.result.value.state)" -ceq "done" -and [int]$count["acts"] -eq 1) ("CONTROL: a dialling node that serves acts acts on a spawn over its own link, once (" + $count["acts"] + " act(s); " + "$($r.answer.result.value.state)$($r.answer.error.code)" + ")")
    Check ((Get-HordeJournalEntry -Root $jA -Id $q.requestId).state -ceq "known") "and records it in its journal"
    $jR = Join-Path $work "journal-readonly"
    Initialize-HordeJournal -Root $jR -Kind "request" | Out-Null
    $count = [hashtable]::Synchronized(@{ acts = 0 })
    $q = Req "session.spawn" (Spawn)
    $r = Ask-Dialled -Opts @{ JournalRoot = $jR; Acts = $true; ReadOnly = $true; Counter = $count } -Frame $q
    Check ($null -ne $r.answer -and "$($r.answer.error.code)" -ceq "refused" -and "$($r.answer.error.reason)" -clike "*read verbs only*") ("a dialling node started -ReadOnly refuses a spawn over its own link as read-only (" + "$($r.answer.error.code): $($r.answer.error.reason)" + ")")
    Check ([int]$count["acts"] -eq 0) ("and acts on nothing (" + $count["acts"] + " act(s))")
    Check ((Get-HordeJournalEntry -Root $jR -Id $q.requestId).state -cne "known") "and journals nothing"
    # Messaging reaches a dialled link: with messaging built and no messenger named, a deliver is
    # refused for that reason, which only the messaging object gives.
    $mh = Join-Path $work "messaging-home"
    [void][System.IO.Directory]::CreateDirectory($mh)
    $r = Ask-Dialled -Opts @{ MessagingHome = $mh } -Frame (Req "session.deliver" (Deliver))
    Check ($null -ne $r.answer -and "$($r.answer.error.code)" -ceq "refused" -and "$($r.answer.error.reason)" -clike "*no messenger was named*") ("a dialling node's messaging answers a deliver over its own link (" + "$($r.answer.error.code): $($r.answer.error.reason)" + ")")
    $r = Ask-Dialled -Opts @{} -Frame (Req "session.deliver" (Deliver))
    Check ($null -ne $r.answer -and "$($r.answer.error.reason)" -cnotlike "*no messenger was named*") ("CONTROL: with no messaging built the answer is another, so the check above sees the messaging object (" + "$($r.answer.error.code): $($r.answer.error.reason)" + ")")
    # horde node serve -Dial hands the dial loop what it hands the listening loop.
    $nodeCmd = [System.IO.File]::ReadAllText((Join-Path $root "cli\commands\node.ps1"))
    Check ($nodeCmd -match 'Invoke-HordeNodeDial [^\r\n]*-Act \$act -Messaging \$messaging -ReadOnly:\$ReadOnly') "horde node serve -Dial passes the node's acts, messaging and -ReadOnly to the dial loop"

    Write-Host ""
    Write-Host "--- a hub that cannot be reached: the node dials again, waiting longer each time ---" -ForegroundColor Cyan
    $node = [pscustomobject]@{ deviceId = $device; deviceName = "dialling-node" }
    $manifest = New-HordeNodeManifest -Root $root -Node $node -Space "windows"
    $ns = New-HordeNamespace -Device $device -Space "windows"
    $dialLog = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-HordeNodeDial -Transport $mem -Endpoint "hub-nobody-listens" -Manifest $manifest -Namespace $ns -GetView { $null } -MaxDials 3 -OpenTimeoutMs 500 -IntervalMs 100 -BackoffMaxMs 2000 -Log { param($l) [void]$dialLog.Add($l) }
    $sw.Stop()
    Check ($r.dials -eq 3 -and $r.served -eq 0 -and @($r.failures).Count -eq 3) ("three dials to nobody are three failures, none served (" + (@($r.failures) -join " | ") + ")")
    Check (@($dialLog | Where-Object { $_ -clike "*(1 in a row; next try in 1000 ms)*" }).Count -eq 1 -and @($dialLog | Where-Object { $_ -clike "*(2 in a row; next try in 2000 ms)*" }).Count -eq 1) ("the wait doubles after each failure (" + ($dialLog -join " | ") + ")")
    Check (@($dialLog | Where-Object { $_ -clike "*(3 in a row; next try in 2000 ms)*" }).Count -eq 1) "and stops at -BackoffMaxMs"
    Check ($sw.Elapsed.TotalSeconds -ge 2.9 -and $sw.Elapsed.TotalSeconds -lt 8) ("and the node really waited between dials, not after the last (" + [math]::Round($sw.Elapsed.TotalSeconds, 1) + " s)")
} finally {
    if ((Split-Path -Leaf $work) -match '^horde-hub-dial-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "the hub takes a dialled link only bound to its preamble's device, pulls it as it pulls any node, and the node dials, answers and dials again"
