# transports/ssh/test/MeshNode.ps1 - the node half of test-mesh-act-local.ps1, run as its own process with
# HORDE_HOME set to the node's home. Not a suite.
#
# What `horde node serve -Dial` runs - cli/NodeServe.ps1's Invoke-HordeNodeDial over this transport,
# with the node's link key and pinned hub host key from its home, answering the hub's frames through
# the real serve loop, request journal and act path - with one thing swapped: the node's hosts and
# harnesses are test/fixtures/node-serve/act-world.ps1's fakes, so a spawn the policy allows starts no
# terminal and no harness. Its policy is <home>\node\policy.json, read at every spawn. The session view
# is a fixed fixture. It dials until stopped (the suite ends it through its job).
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Endpoint,
    [int]$IntervalMs = 1000
)
$ErrorActionPreference = "Stop"
foreach ($f in @("Tristate", "Home", "Device", "Platform", "Namespace", "NodeDeliverTo")) { . (Join-Path $Root ("core\" + $f + ".ps1")) }
. (Join-Path $Root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $Root "remote\NodeServe.ps1")
. (Join-Path $Root "remote\Outbox.ps1")
. (Join-Path $Root "cli\NodeServe.ps1")
. (Join-Path $Root "cli\NodeAct.ps1")
. (Join-Path $Root "test\fixtures\node-serve\act-world.ps1")
$node = Get-HordeNode
$hordeHome = Get-HordeHome
$manifest = New-HordeNodeManifest -Root $Root -Node $node -Space "windows"
$ns = New-HordeNamespace -Device $node.deviceId -Space "windows"
$viewText = [System.IO.File]::ReadAllText((Join-Path $Root "test\fixtures\node-serve\view.json"))
$getView = { return ($viewText | ConvertFrom-Json) }
$journal = Initialize-HordeJournal -Root (Join-Path $hordeHome "node\requests") -Kind "request"
$ctx = New-HordeActWorldContext -Root $Root -HordeHome $hordeHome -Namespace $ns
$act = { param($a) Invoke-HordeNodeActRequest -Act $a -Context $ctx }
$tr = Resolve-HordeLinkTransport -Name "ssh"
if ($tr.state -cne "known") { throw ("this node cannot dial: " + $tr.reason) }
Write-Host ("mesh node " + $node.deviceId + " dialling " + $Endpoint)
$log = { param($Line) Write-Host $Line }
$null = Invoke-HordeNodeDial -Transport $tr.value -Endpoint $Endpoint -Manifest $manifest -Namespace $ns -GetView $getView -JournalRoot $journal -Act $act -MaxDials 0 -IdleTimeoutMs 60000 -IntervalMs $IntervalMs -BackoffMaxMs 4000 -Log $log
