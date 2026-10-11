# The node side of test/test-hub-dial.ps1: cli/NodeServe.ps1's real dialling loop (remote plan R17c),
# on the in-process memory transport, answering from a fixed session view. Not a suite: the suite runs
# it in a second runspace and is the hub.
#
# THE PREAMBLE AS THE HUB'S FORCED COMMAND WRITES IT. Live, the node dials the hub's listener, and the forced
# command (R17a's cli\attach.ps1) dials the hub pipe and writes one preamble line before relaying the
# node's bytes. Here the transport plays that part: its open dials the memory endpoint and, when
# -Preamble is not empty, writes that line first. The node itself sends nothing before its hello.
#
# -DeviceId is the device the node says it is in its hello; -Preamble is whatever line the "forced
# command" writes, so a suite can bind the link to another device, or write no preamble at all.
# WHAT THE DIALLED LINK IS SERVED, as horde node serve -Dial serves it: -Acts serves acts with a fixture
# act that counts itself in -Counter["acts"] and answers done, recorded in -JournalRoot; -ReadOnly
# serves read verbs only; -MessagingHome builds the node's messaging there, with no messenger named.
# -ActWorldHome serves acts through the REAL act path over test/fixtures/node-serve/act-world.ps1's fakes,
# its policy read from that home; -ActDelayMs holds the FIRST act that long (a node slow to act, so a
# hub can lose the answer); -IntervalMs is the wait between dials.
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$HubEndpoint,
    [Parameter(Mandatory = $true)][string]$DeviceId,
    [Parameter(Mandatory = $true)][string]$ViewPath,
    [AllowEmptyString()][string]$Preamble = "",
    [int]$MaxDials = 1,
    [int]$IdleTimeoutMs = 30000,
    [string]$JournalRoot = "",
    [switch]$Acts,
    [switch]$ReadOnly,
    [string]$MessagingHome = "",
    $Counter = $null,
    [string]$ActWorldHome = "",
    [int]$ActDelayMs = 0,
    [int]$IntervalMs = 100
)
$ErrorActionPreference = "Stop"
foreach ($f in @("Tristate", "Platform", "Namespace", "NodeDeliverTo")) { . (Join-Path $Root ("core\" + $f + ".ps1")) }
. (Join-Path $Root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $Root "remote\NodeServe.ps1")
. (Join-Path $Root "remote\Outbox.ps1")
. (Join-Path $Root "cli\NodeServe.ps1")
. (Join-Path $Root "cli\NodeAct.ps1")
. (Join-Path $Root "messengers\Port.ps1")
foreach ($m in @(Get-HordeMessengerFiles -Root (Join-Path $Root "messengers"))) { . $m }
$node = [pscustomobject]@{ deviceId = $DeviceId; deviceName = "dialling-node" }
$manifest = New-HordeNodeManifest -Root $Root -Node $node -Space "windows"
$ns = New-HordeNamespace -Device $DeviceId -Space "windows"
$viewText = [System.IO.File]::ReadAllText($ViewPath)
$getView = { return ($viewText | ConvertFrom-Json) }
$mem = Get-HordeTransport -Name "memory"
$memOpen = $mem.open
$viaAttach = $mem.PSObject.Copy()
# A plain block, not a closure: it runs below this script's scope, where $memOpen, $mem and $Preamble
# and the port's functions are found.
$viaAttach.open = {
    param($Endpoint, [int]$TimeoutMs)
    $r = & $memOpen $Endpoint $TimeoutMs
    if ($r.ok -and $Preamble -ne "") {
        $first = New-HordeLink -Transport $mem -Role "node" -Endpoint $Endpoint -Channel $r.channel -Peer $r.peer
        $null = Send-HordeLinkFrame -Link $first -Frame $Preamble
    }
    return $r
}
$act = $null
if ($ActWorldHome -ne "") {
    . (Join-Path $Root "test\fixtures\node-serve\act-world.ps1")
    $worldCtx = New-HordeActWorldContext -Root $Root -HordeHome $ActWorldHome -Namespace $ns
    $act = {
        param($a)
        if ($null -ne $Counter) { $Counter["acts"] = 1 + [int]$Counter["acts"] }
        if ($ActDelayMs -gt 0 -and [int]$Counter["acts"] -eq 1) { Start-Sleep -Milliseconds $ActDelayMs }
        return (Invoke-HordeNodeActRequest -Act $a -Context $worldCtx)
    }
} elseif ($Acts) {
    $act = {
        param($a)
        if ($null -ne $Counter) { $Counter["acts"] = 1 + [int]$Counter["acts"] }
        if ($ActDelayMs -gt 0 -and [int]$Counter["acts"] -eq 1) { Start-Sleep -Milliseconds $ActDelayMs }
        $ex = [pscustomobject]@{ ns = [pscustomobject]@{ device = $DeviceId; space = "windows" }; pid = 4242; procStart = "134350994347710308" }
        return [pscustomobject]@{ state = "done"; sessionId = "aaaaaaaa-1111-4222-8333-444444444444"; expect = $ex; reason = "" }
    }
}
$messaging = $null
if ($MessagingHome -ne "") { $messaging = New-HordeNodeMessaging -Root $Root -HordeHome $MessagingHome -GetView $getView }
$lines = New-Object System.Collections.ArrayList
$log = { param($Line) [void]$lines.Add($Line) }
$r = Invoke-HordeNodeDial -Transport $viaAttach -Endpoint $HubEndpoint -Manifest $manifest -Namespace $ns -GetView $getView -JournalRoot $JournalRoot -Act $act -Messaging $messaging -ReadOnly:$ReadOnly -MaxDials $MaxDials -IdleTimeoutMs $IdleTimeoutMs -IntervalMs $IntervalMs -Log $log
$r | Add-Member -NotePropertyName log -NotePropertyValue $lines.ToArray()
return $r
