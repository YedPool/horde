# The node side of test/test-node-serve.ps1's in-process link: cli/NodeServe.ps1's real loop, on the
# in-process memory transport, answering from a fixed session view. Not a suite: the suite runs it in a
# second runspace and is the hub. It serves -MaxLinks links and returns what Invoke-HordeNodeServe
# returned, so the suite sees how each link ended.
#
# -Counter (a synchronized hashtable) counts the views built, so the suite can see one is built per
# request that needs it. -ThrowOnView makes every view build throw, as a broken projection would.
# -ViewDelayMs makes every view build take that long, as a slow projection would (issue #87, F10).
# -ViewThrowsWhenRead hands back a view that builds without error but throws when the answer is built
# from it, so the throw comes from answering, past the view's own try. -ManifestTooLarge gives node.info
# a manifest the link's writer refuses (over the caps), so its result cannot be sent.
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Endpoint,
    [Parameter(Mandatory = $true)][string]$ViewPath,
    [string]$JournalRoot = "",
    [int]$MaxLinks = 1,
    [int]$IdleTimeoutMs = 30000,
    [switch]$ThrowOnView,
    [int]$ViewDelayMs = 0,
    [switch]$ViewThrowsWhenRead,
    [switch]$ManifestTooLarge,
    $Counter = $null,
    $Ready = $null
)
$ErrorActionPreference = "Stop"
foreach ($f in @("Tristate", "Platform", "Namespace")) { . (Join-Path $Root ("core\" + $f + ".ps1")) }
. (Join-Path $Root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $Root "remote\NodeServe.ps1")
. (Join-Path $Root "cli\NodeServe.ps1")
$deviceId = $Endpoint
$node = [pscustomobject]@{ deviceId = $deviceId; deviceName = "fixture-node" }
$manifest = New-HordeNodeManifest -Root $Root -Node $node -Space "windows"
if ($ManifestTooLarge) { $manifest["hosts"] = @(1..300 | ForEach-Object { "host-" + $_ }) }
if ($ViewThrowsWhenRead) {
    # A dictionary whose every lookup throws: the view is built (it is not $null), and the first read of
    # it, inside remote/NodeServe.ps1, throws.
    Add-Type -TypeDefinition 'public class HordeTestThrowingView : System.Collections.Hashtable { public override bool Contains(object key) { throw new System.InvalidOperationException("the fixture view breaks when read"); } }'
}
$ns = New-HordeNamespace -Device $deviceId -Space "windows"
$viewText = [System.IO.File]::ReadAllText($ViewPath)
$getView = {
    if ($null -ne $Counter) { $Counter["views"] = 1 + [int]$Counter["views"] }
    if ($ThrowOnView) { throw "the fixture projection is broken on purpose" }
    if ($ViewDelayMs -gt 0) { Start-Sleep -Milliseconds $ViewDelayMs }
    if ($ViewThrowsWhenRead) { return (New-Object HordeTestThrowingView) }
    return ($viewText | ConvertFrom-Json)
}
$signal = { if ($null -ne $Ready) { $Ready.Set() } }
$transport = Get-HordeTransport -Name "memory"
return (Invoke-HordeNodeServe -Transport $transport -Endpoint $deviceId -Manifest $manifest -Namespace $ns -GetView $getView -JournalRoot $JournalRoot -MaxLinks $MaxLinks -AcceptTimeoutMs 30000 -IdleTimeoutMs $IdleTimeoutMs -OnListening $signal)
