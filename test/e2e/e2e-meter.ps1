# END TO END: `horde meter collect`, `watch-limits -DryRun` and `status`, driven at the real command line.
#
# The user of the fleet meter is the scheduled task that runs it every few minutes and the person who
# asks "is it collecting?". This scenario is both: it builds a small synthetic transcripts folder and
# session registry (no real transcript is read), points the shipped horde.ps1 at a Horde home of its
# own, and reads back what a user sees: the summary line of a first collect, the same collect run again
# finding nothing new, the status report with its row counts, the limit watch's dry run naming the
# stopped session, a flag refused for the wrong verb, and a machine without Node failing in one
# sentence and not hanging. No pane, no terminal and no session is touched, and the watch is only ever
# run with -DryRun, so nobody is told anything. The real Horde home is checked before and after: it must
# not have gained a metrics folder (CONTRIBUTING 9).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] no node here: the fleet meter cannot run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}

$script:work = Join-Path $env:TEMP ("horde-meter-e2e-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$projects = Join-Path $script:work "projects"
$registry = Join-Path $script:work "registry"
$realMetrics = Join-Path (Join-Path "$env:USERPROFILE" ".horde") "metrics"
$realBefore = Test-Path -LiteralPath $realMetrics
$cliEnv = @{ HORDE_HOME = $hordeHome }
function Invoke-Meter { param([string[]]$MeterArgs, [hashtable]$Env = $cliEnv) return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("meter") + $MeterArgs) -Env $Env) }

try {

# The synthetic fleet, from the reader's own fixture builder (found by its place, not by a harness name).
$builder = @(Get-ChildItem -Path (Join-Path $root "agents") -Filter "make-projects.mjs" -Recurse -File | Select-Object -First 1)
Check ($builder.Count -eq 1) "CONTROL: the fixture builder for a reader is found"
$made = Start-Process -FilePath $node.Source -ArgumentList @(('"' + $builder[0].FullName + '"'), ('"' + $projects + '"'), ('"' + $registry + '"')) -Wait -PassThru -NoNewWindow
Check ($made.ExitCode -eq 0 -and (Test-Path -LiteralPath $projects)) "CONTROL: the synthetic transcripts and registry are made"

Write-Host ""
Write-Host "=== status before anything is collected ===" -ForegroundColor Cyan
$s0 = Invoke-Meter @("status")
Check ($s0.code -eq 0) ("status exits 0 on an empty home (" + $s0.code + ")")
Check ($s0.out -like "*database: *fleet.sqlite*" -and $s0.out -like "*tokens_requests: 0 rows*" -and $s0.out -like "*data age: no data yet*") "it names the database and says there is no data yet"
Check (Test-Path -LiteralPath (Join-Path $hordeHome "metrics\fleet.sqlite") -PathType Leaf) "and the database is under the home the command was given"

Write-Host ""
Write-Host "=== collect, and collect again ===" -ForegroundColor Cyan
$c1 = Invoke-Meter @("collect", "-Projects", $projects, "-Registry", $registry)
Check ($c1.code -eq 0) ("collect exits 0 (" + $c1.code + ": " + $c1.out.Trim() + ")")
Check ($c1.out -cmatch 'collect: files=3 new_bytes=[1-9]\d* rows: tokens_requests=4 tokens_turns=3 tokens_agents=2 tokens_limits=1 ms=\d+') ("one summary line: 3 files (two sessions and a subagent), 4 requests (a repeated one counted once), 3 turns, 1 subagent call written twice - by the parent's call and by its sidecar, 1 limit hit (" + $c1.out.Trim() + ")")
$c2 = Invoke-Meter @("collect", "-Projects", $projects, "-Registry", $registry)
Check ($c2.code -eq 0 -and $c2.out -cmatch 'collect: files=3 new_bytes=0 rows: tokens_requests=0 tokens_turns=0 tokens_agents=0 tokens_limits=0') ("the same collect again finds nothing new (" + $c2.out.Trim() + ")")

Write-Host ""
Write-Host "=== status after ===" -ForegroundColor Cyan
$s1 = Invoke-Meter @("status")
Check ($s1.code -eq 0 -and $s1.out -like "*tokens_requests: 4 rows*" -and $s1.out -like "*tokens_turns: 3 rows*" -and $s1.out -like "*tokens_agents: 1 rows*" -and $s1.out -like "*tokens_limits: 1 rows*") ("status counts the rows per table (" + ($s1.out.Trim() -replace "\r?\n", " / ") + ")")
Check ($s1.out -cmatch 'data age: \S+ \S+ since the newest row') "and says how old the newest row is"

Write-Host ""
Write-Host "=== the limit watch, dry run ===" -ForegroundColor Cyan
$w = Invoke-Meter @("watch-limits", "-DryRun", "-Projects", $projects, "-Registry", $registry)
Check ($w.code -eq 0) ("watch-limits -DryRun exits 0 (" + $w.code + ")")
Check ($w.out -cmatch 'would send: Fleet meter: Q \(session 22222222\) has been stopped by its 5-hour usage limit since ') ("it names the Orc and the session that stopped (" + (($w.out.Trim() -split "\r?\n")[0]) + ")")
Check ($w.out -cmatch 'watch-limits: scanned=\d+ would_send=1 ') "and says one message would be sent, none was"
$s2 = Invoke-Meter @("status")
Check ($s2.out -like "*tokens_limits: 1 rows*") "the dry run changed no row"

Write-Host ""
Write-Host "=== refusals ===" -ForegroundColor Cyan
$bad = Invoke-Meter @("status", "-DryRun")
Check ($bad.code -ne 0 -and $bad.out -like "*-DryRun does not apply to meter status*") ("a flag for another verb is refused (" + $bad.code + ")")
$noNode = Invoke-Meter @("status") @{ HORDE_HOME = $hordeHome; PATH = ($env:SystemRoot + "\System32;" + $env:SystemRoot + "\System32\WindowsPowerShell\v1.0") }
Check ($noNode.code -ne 0 -and $noNode.out -like "*needs Node.js 24 or later*") ("with no Node on the PATH it fails at once in one sentence (" + $noNode.code + ")")

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-meter-e2e-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check ((Test-Path -LiteralPath $realMetrics) -eq $realBefore) "the real Horde home under the user profile has gained no metrics folder"

Complete-HordeSuite -Success "collect is incremental and idempotent, status reports it, the dry-run watch names the stopped session, and nothing real is touched"
