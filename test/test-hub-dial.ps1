# DOES THE HUB TAKE A LINK A NODE DIALLED, BOUND TO THE DEVICE ITS PREAMBLE NAMES, AND DOES THE NODE DIAL?
#
# Remote plan R17c, slices 1 and 2. A node behind NAT dials the hub's listener over ssh; the hub's forced
# command (R17a's cli\attach.ps1) dials the hub pipe and writes one preamble line, "horde-attach 1
# <device id>", the device the node's key is enrolled as. The hub reads it, binds the link to that device,
# refuses a hello claiming another, and runs the same pull it runs on a link it opened
# (cli/HubServe.ps1). The node dials, answers on its own link as it answers an accepted one, and dials
# again with a growing wait while the hub cannot be reached (cli/NodeServe.ps1, Invoke-HordeNodeDial).
#
# Without ssh or a pipe: both ends on the in-process memory transport, the node in a second runspace
# (test/fixtures/node-serve/dial-peer.ps1), whose transport writes the preamble as attach will. The live
# ssh dial is R17c-3 (test-transport-conformance's ssh case against R16's child sshd).
#
# R17a OWNS THE PREAMBLE CONTRACT (remote/LinkBinding.ps1, not yet merged): the preamble cases here are
# that contract's wire form, and keep holding when cli/HubServe.ps1's stand-ins become calls to it.

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
    param([string]$HubEndpoint, [string]$As = $device, [AllowEmptyString()][string]$Preamble, [int]$MaxDials = 1)
    $ps = [PowerShell]::Create()
    [void]$ps.AddCommand((Join-Path $fx "dial-peer.ps1")).AddParameter("Root", $root).AddParameter("HubEndpoint", $HubEndpoint).AddParameter("DeviceId", $As).AddParameter("ViewPath", $viewPath).AddParameter("Preamble", $Preamble).AddParameter("MaxDials", $MaxDials).AddParameter("IdleTimeoutMs", 20000)
    return [pscustomobject]@{ ps = $ps; h = $ps.BeginInvoke() }
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
    $ok = Get-HordeHubPreambleDevice -Text ("horde-attach 1 " + $device)
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
        $r = Get-HordeHubPreambleDevice -Text $bad[$k]
        Check ($r.state -ceq "unknown" -and "$($r.reason)" -clike "*not an attach preamble*") ("a first line of " + $k + " binds nothing, and says so")
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
    Write-Host "--- a hello that claims another device than the preamble is refused ---" -ForegroundColor Cyan
    $mr = Join-Path $work "mirror-b"
    $listener = New-HubListener -Name $ep
    try {
        $node = Start-Dialler -HubEndpoint $ep -As $device -Preamble ("horde-attach 1 " + $other)
        $rounds = @(Invoke-HordeHubServe -Nodes @() -Root $mr -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 8000 -TimeoutMs 20000 -Listener $listener)
        $nd = Stop-Dialler $node
    } finally { Stop-HordeTransportListener -Listener $listener }
    $outs = @($rounds[0].outcomes)
    Check (@($outs | Where-Object { $_ -clike ("*(" + $other + "): unreachable: *answered as device " + $device + "*bound to " + $other + "*") }).Count -eq 1) ("the hub refuses the hello, naming both devices (" + ($outs -join " | ") + ")")
    Check (-not (Test-Path -LiteralPath (Get-HordeHubMirrorPath -Root $mr -DeviceId $device))) "and writes nothing under the device the hello claimed"
    $bm = Mirror-Of -Root $mr -Id $other
    Check ($bm.state -ceq "known" -and "$(Get-HordeLinkProp (Get-HordeLinkProp $bm.value 'lost') 'reason')" -clike "*bound to*" -and $null -eq (Get-HordeLinkProp $bm.value "inventory")) "the bound device's mirror records the failed round, never an inventory from the other"
    Check ($null -ne $nd -and $nd.served -eq 1 -and "$(@($nd.endings)[0])" -clike "*closed by the protocol*") ("the node got the hub's bye (" + "$(@($nd.endings) -join ' | ')" + ")")

    Write-Host ""
    Write-Host "--- no preamble, or a wrong one, binds nothing and ends the link ---" -ForegroundColor Cyan
    foreach ($case in @(@{ name = "a wrong version"; pre = ("horde-attach 2 " + $device); want = "*not an attach preamble*" }, @{ name = "no preamble"; pre = ""; want = "*no preamble came*" })) {
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
