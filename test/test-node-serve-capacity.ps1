# DOES A FULL sessions.list - THE LIST CAP OF SESSIONS - FIT ONE FRAME THE LINK WILL SEND?
#
# Remote plan step R12a. sessions.list stops at listItems (256) sessions and says how many it left out
# (test\test-node-serve.ps1). This suite checks the other half: that the answer at the cap is a frame the
# link's own writer accepts, within the frame cap. It is its own suite because encoding that frame is the
# slowest thing the node does: 200 s before fix/link-writer-speed (measured 2026-10-02), 1.4 to 2.3 s after
# on the always-on box (2026-10-03), a cost test-node-serve.ps1's every mutant would pay again.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Platform", "Namespace")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $root "remote\NodeServe.ps1")

$device = "0f8fad5b-d9cb-469f-a165-70867728950e"
$ns = New-HordeNamespace -Device $device -Space "windows"
$contract = Get-HordeLinkContract
$cap = $contract.limits["listItems"]
$frameCap = $contract.limits["frameBytes"]

Write-Host ""
Write-Host "--- a list at the cap, every field at its widest the fixture allows ---" -ForegroundColor Cyan
$view = [System.IO.File]::ReadAllText((Join-Path $root "test\fixtures\node-serve\view.json")) | ConvertFrom-Json
$proto = @($view.sessions)[0]
# The widest summary: every token-like field long, a reason at its cap, a long project directory.
$proto.fields.label = [pscustomobject]@{ state = "unknown"; reason = ("r" * 2000) }
$proto.fields.projectCwd.value = ("C:" + ("\abcdefghij" * 20))
$rows = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt ($cap + 4); $i++) {
    $c = ($proto | ConvertTo-Json -Depth 10) | ConvertFrom-Json
    $c.sessionId = ("bbbbbbbb-0000-4000-8000-" + $i.ToString("000000000000"))
    [void]$rows.Add($c)
}
$view.sessions = $rows.ToArray()
Check (@($view.sessions).Count -eq ($cap + 4)) ("CONTROL: the view holds " + ($cap + 4) + " sessions, past the cap of " + $cap)

$st = New-HordeNodeServeState -NodeId $device -NodeName "fixture-node" -HordeVersion "0.1.0" -Contract $contract
$t = Get-HordeLinkTime
$hello = [pscustomobject][ordered]@{ v = 1; kind = "hello"; id = (New-HordeLinkFrameId); seq = 1; ts = $t; hello = [pscustomobject][ordered]@{ role = "hub"; id = "7c9e6679-7425-40de-944b-e07fc1f90ae7"; name = "fixture-hub"; protocols = @(1); verbsVersions = @(1); hordeVersion = "0.1.0"; t1 = $t } }
$req = [pscustomobject][ordered]@{ v = 1; kind = "req"; id = (New-HordeLinkFrameId); seq = 2; ts = (Get-HordeLinkTime); verb = "sessions.list"; requestId = (New-HordeLinkFrameId); issuedAt = (Get-HordeLinkTime); args = [pscustomobject]@{} }
$data = [pscustomobject]@{ manifest = $null; view = $view; viewError = ""; journalRoot = ""; namespace = $ns }
function Line { param($Frame) $b = ConvertTo-HordeFrameBytes -Frame $Frame -Contract $contract; return [System.Text.Encoding]::ASCII.GetString($b.bytes, 0, $b.bytes.Length - 1) }
$null = Invoke-HordeNodeFrame -State $st -Line (Line $hello) -Data $data
$r = Invoke-HordeNodeFrame -State $st -Line (Line $req) -Data $data
$v = $r.reply.result.value
Check (@($v.sessions).Count -eq $cap -and $v.complete.value -eq $false) ("the answer holds the cap of " + $cap + " sessions and is not complete")

Write-Host ""
Write-Host "--- and the link's writer sends it ---" -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$b = ConvertTo-HordeFrameBytes -Frame $r.reply -Contract $contract
$secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
Write-Host ("         encoded in " + $secs + " s") -ForegroundColor DarkGray
Check ($b.ok) ("the full list is a frame the writer accepts (" + $b.reason + ")")
Check ($b.ok -and $b.bytes.Length -le $frameCap) ("within the frame cap: " + $(if ($b.ok) { $b.bytes.Length } else { "none" }) + " of " + $frameCap + " bytes")
$text = ""
if ($b.ok) { $text = [System.Text.Encoding]::ASCII.GetString($b.bytes) }
Check ($text -clike "*bbbbbbbb-0000-4000-8000-000000000255*" -and $text -cnotlike "*bbbbbbbb-0000-4000-8000-000000000256*") "CONTROL: the last session sent is the 256th, and the 257th is not on the wire"

Complete-HordeSuite -Success "a sessions.list at the list cap, its summaries at their widest, is one frame the link sends"
