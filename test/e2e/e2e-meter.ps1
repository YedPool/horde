# END TO END: `horde meter collect`, `live`, `latency`, `watch-limits -DryRun` and `status`, driven at the real command line.
#
# The user of the fleet meter is the scheduled task that runs it every few minutes and the person who
# asks "is it collecting?". This scenario is both: it builds a small synthetic transcripts folder and
# session registry (no real transcript is read), points the shipped horde.ps1 at a Horde home of its
# own, and reads back what a user sees: the summary line of a first collect, the same collect run again
# finding nothing new, the status report with its row counts, the limit watch's dry run naming the
# stopped session, a flag refused for the wrong verb, and a machine without Node failing in one
# sentence and not hanging. No pane, no terminal and no session is touched, and the watch is only ever
# run with -DryRun, so nobody is told anything. The real Horde home (as horde resolves it) is checked before
# and after: its database must not be created or gain a synthetic row (CONTRIBUTING 9). The relay journal is a synthetic one under the test home:
# its hops are read, a damaged header is counted, and its files are checked unchanged afterwards.

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
# The REAL home is the one horde itself would use (HORDE_HOME, else the pointer file, else <profile>\.horde),
# read before anything runs. Until 2026-10-21 this watched <profile>\.horde\metrics only; the one-home move
# (PR 366) put the real home elsewhere, and that old folder already existed, so the check proved nothing.
. (Join-Path $root "core\Home.ps1")
$realHome = $null
try { $realHome = Get-HordeHome } catch { Write-Host ("  the real home does not resolve: " + $_.Exception.Message) }
Check ($null -ne $realHome) "CONTROL: the real Horde home resolves, so it can be checked untouched"
$realDb = $(if ($null -ne $realHome) { Join-Path $realHome "metrics\fleet.sqlite" } else { "" })
# The synthetic sessions, read from the fixture builder so the ids live in one place. A row for one of them in
# the real database is this suite's own write. Rows are counted, not file times compared: the live meter
# writes the real database on its own while this runs.
$fixtureIds = @()
$builderFile = @(Get-ChildItem -Path (Join-Path $root "agents") -Filter "make-projects.mjs" -Recurse -File | Select-Object -First 1)
if ($builderFile.Count -eq 1) {
    $fixtureIds = @([regex]::Matches([System.IO.File]::ReadAllText($builderFile[0].FullName), "export const SID_\w+ = '([0-9a-f-]{36})'") | ForEach-Object { $_.Groups[1].Value })
}
Check ($fixtureIds.Count -ge 2) ("CONTROL: the synthetic session ids are read from the fixture builder (" + $fixtureIds.Count + ")")
function Get-FixtureRows {
    # -1 when -Db is not there, -2 when it cannot be read; else its tokens_requests rows for the synthetic
    # sessions, opened read-only. --no-warnings and no stderr redirect: node:sqlite warns on stderr, and under
    # 5.1 with $ErrorActionPreference Stop a redirected native stderr line is a terminating error.
    param([string]$Db)
    if ($Db -eq "" -or -not (Test-Path -LiteralPath $Db -PathType Leaf)) { return -1 }
    $js = "const {DatabaseSync}=require('node:sqlite');const d=new DatabaseSync(process.argv[1],{readOnly:true});const ids=process.argv.slice(2);console.log(d.prepare('SELECT count(*) AS n FROM tokens_requests WHERE session_id IN ('+ids.map(()=>'?').join(',')+')').get(...ids).n)"
    $said = & $node.Source --no-warnings -e $js $Db @($fixtureIds)
    if ($LASTEXITCODE -ne 0 -or "$said".Trim() -notmatch '\A\d+\z') { return -2 }
    return [int]("$said".Trim())
}
$realBefore = Get-FixtureRows $realDb
Check ($realBefore -ne -2) ("CONTROL: the real database, if any, can be read (" + $realDb + ")")
$cliEnv = @{ HORDE_HOME = $hordeHome }
function Invoke-Meter { param([string[]]$MeterArgs, [hashtable]$Env = $cliEnv) return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("meter") + $MeterArgs) -Env $Env) }

try {

# The synthetic fleet, from the reader's own fixture builder (found by its place, not by a harness name).
$builder = @(Get-ChildItem -Path (Join-Path $root "agents") -Filter "make-projects.mjs" -Recurse -File | Select-Object -First 1)
Check ($builder.Count -eq 1) "CONTROL: the fixture builder for a reader is found"
$made = Start-Process -FilePath $node.Source -ArgumentList @(('"' + $builder[0].FullName + '"'), ('"' + $projects + '"'), ('"' + $registry + '"')) -Wait -PassThru -NoNewWindow
Check ($made.ExitCode -eq 0 -and (Test-Path -LiteralPath $projects)) "CONTROL: the synthetic transcripts and registry are made"

# A synthetic relay journal under the test home: two good records of one stream and one damaged header.
$fromId = "af37" + ("0" * 28)
$streamDir = Join-Path $hordeHome ("relay\journal\in\s-" + $fromId + "\c-chat")
New-Item -ItemType Directory -Path $streamDir -Force | Out-Null
function Write-Rec { param([long]$Seq, [long]$Ts, [long]$Rec)
    $nonce = "a" * 24
    $head = '{"v":1,"direction":"in","key":"' + $fromId + '/chat/' + $Seq + '/' + $nonce + '","from":"' + $fromId + '","channel":"chat","kind":"text","seq":' + $Seq + ',"nonce":"' + $nonce + '","ts":' + $Ts + ',"recordedAt":' + $Rec + ',"envelopeChars":1}'
    [System.IO.File]::WriteAllText((Join-Path $streamDir ($Seq.ToString("D16") + ".rec")), ($head + "`nE"))
}
$stampBase = [DateTimeOffset]::UtcNow.AddHours(-1).ToUnixTimeMilliseconds()  # a believable stamp: mail.mjs refuses any outside 2020..now+1 day
Write-Rec -Seq 1 -Ts $stampBase -Rec ($stampBase + 400)
Write-Rec -Seq 2 -Ts ($stampBase + 1000000) -Rec ($stampBase + 1000600)
[System.IO.File]::WriteAllText((Join-Path $streamDir "0000000000000003.rec"), "not a header`nE")
$journalBefore = @(Get-ChildItem -LiteralPath $streamDir -File | ForEach-Object { $_.Name + ":" + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ","

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
Check ($c1.out -cmatch 'collect: files=3 skipped_old=0 new_bytes=[1-9]\d* rows: tokens_requests=4 tokens_turns=3 tokens_agents=2 tokens_limits=1 tokens_usage=3 ms=\d+') ("one summary line: 3 files (two sessions and a subagent), 4 requests (a repeated one counted once), 3 turns, 1 subagent call written twice - by the parent's call and by its sidecar, 1 limit hit, live rows for the two sessions and the subagent (3 distinct rows, whichever of the subagent and its parent is read first) (" + $c1.out.Trim() + ")")
Check ($c1.out -cmatch 'mail: journal_records=3 hops_added=4 skipped_headers=1') "and a mail line: 2 journal records give 4 hops, the damaged header is skipped and counted"
$ownRows = Get-FixtureRows (Join-Path $hordeHome "metrics\fleet.sqlite")
Check ($ownRows -gt 0) ("CONTROL: the row count used on the real home finds the synthetic rows in the test home (" + $ownRows + ")")
$c2 = Invoke-Meter @("collect", "-Projects", $projects, "-Registry", $registry)
Check ($c2.code -eq 0 -and $c2.out -cmatch 'collect: files=3 skipped_old=0 new_bytes=0 rows: tokens_requests=0 tokens_turns=0 tokens_agents=0 tokens_limits=0 tokens_usage=0' -and $c2.out -cmatch 'hops_added=0') ("the same collect again finds nothing new (" + $c2.out.Trim() + ")")

Write-Host ""
Write-Host "=== status after ===" -ForegroundColor Cyan
$s1 = Invoke-Meter @("status")
Check ($s1.code -eq 0 -and $s1.out -like "*tokens_requests: 4 rows*" -and $s1.out -like "*tokens_turns: 3 rows*" -and $s1.out -like "*tokens_agents: 1 rows*" -and $s1.out -like "*tokens_limits: 1 rows*" -and $s1.out -like "*tokens_usage: 3 rows*" -and $s1.out -like "*mail_hops: 4 rows*") ("status counts the rows per table (" + ($s1.out.Trim() -replace "\r?\n", " / ") + ")")
Check ($s1.out -cmatch 'data age: \S+ \S+ since the newest row') "and says how old the newest row is"

Write-Host ""
Write-Host "=== live, and latency ===" -ForegroundColor Cyan
$orcSession = "11111111-aaaa-4aaa-8aaa-000000000001"
$l1 = Invoke-Meter @("live", "-Session", $orcSession, "-Projects", $projects, "-Registry", $registry)
Check ($l1.code -eq 0) ("live -Session exits 0 (" + $l1.code + ": " + $l1.out.Trim() + ")")
Check ($l1.out -cmatch 'session 11111111 \[-\] (running|done) [^ ]*sonnet-4-5 context 16000/200000') "it shows the session with its last request's context against the model window"
Check ($l1.out -cmatch '  agent a0b1c2d3 of 11111111 \[-\] done [^ ]*haiku-4-5') "and the subagent, done because its call returned to the parent"
Check ($l1.out -cmatch 'live: sessions=1 files=2 new_bytes=0 usage_rows=0 ms=\d+ errors=0') "it read nothing: collect had already taken every byte"
$l2 = Invoke-Meter @("live", "-Projects", $projects, "-Registry", $registry)
Check ($l2.code -eq 0 -and $l2.out -cmatch 'live: sessions=\d+ files=\d+ new_bytes=0 ') ("live with no session also works (" + $l2.code + ")")
$lat = Invoke-Meter @("latency")
Check ($lat.code -eq 0 -and $lat.out -cmatch 'phone_sent -> pc_journal: n=2 p50=400 ms p95=600 ms lacking_a_hop=0 CROSSES CLOCKS \(phone vs pc\)') ("latency gives p50 and p95 for the one pair and flags that it crosses two clocks (" + $lat.out.Trim() + ")")
$journalAfter = @(Get-ChildItem -LiteralPath $streamDir -File | ForEach-Object { $_.Name + ":" + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ","
Check ($journalAfter -ceq $journalBefore) "the relay journal is byte for byte as it was: the meter only reads it"

Write-Host ""
Write-Host "=== the limit watch, dry run ===" -ForegroundColor Cyan
$w = Invoke-Meter @("watch-limits", "-DryRun", "-Projects", $projects, "-Registry", $registry)
Check ($w.code -eq 0) ("watch-limits -DryRun exits 0 (" + $w.code + ")")
Check ($w.out -cmatch 'would send: Fleet meter: Q \(session 22222222\) has been stopped by its 5-hour usage limit since ') ("it names the Orc and the session that stopped (" + (($w.out.Trim() -split "\r?\n")[0]) + ")")
Check ($w.out -cmatch 'watch-limits: scanned=\d+ would_send=1 ') "and says one message would be sent, none was"
$s2 = Invoke-Meter @("status")
Check ($s2.out -like "*tokens_limits: 1 rows*") "the dry run changed no row"

# A real run in a home under the temp folder: the send is refused there by design (a test's home tells
# nobody), so this shows the refusal reaches the user in words and that nothing is marked as told.
$w2 = Invoke-Meter @("watch-limits", "-Projects", $projects, "-Registry", $registry)
Check ($w2.code -eq 1 -and $w2.out -cmatch 'watch-limits: scanned=[0-9]+ alerts=0 messages=0 silent=0 resumed=0 failed=1 ') "a real run in a test home sends nothing and says one alert failed, with exit 1 so a scheduler shows it"
Check ($w2.out -like "*could not tell the master session*test's*") "and says why, in words"

Write-Host ""
Write-Host "=== refusals ===" -ForegroundColor Cyan
$bad = Invoke-Meter @("status", "-DryRun")
Check ($bad.code -ne 0 -and $bad.out -like "*-DryRun does not apply to meter status*") ("a flag for another verb is refused (" + $bad.code + ")")
$badLive = Invoke-Meter @("live", "-DryRun")
Check ($badLive.code -ne 0 -and $badLive.out -like "*-DryRun does not apply to meter live*") "-DryRun is refused for live"
$badSession = Invoke-Meter @("status", "-Session", "x")
Check ($badSession.code -ne 0 -and $badSession.out -like "*-Session does not apply to meter status*") "-Session is refused for status"
$noNode = Invoke-Meter @("status") @{ HORDE_HOME = $hordeHome; PATH = ($env:SystemRoot + "\System32;" + $env:SystemRoot + "\System32\WindowsPowerShell\v1.0") }
Check ($noNode.code -ne 0 -and $noNode.out -like "*needs Node.js 24 or later*") ("with no Node on the PATH it fails at once in one sentence (" + $noNode.code + ")")

# Checked inside the try, before the test home is removed, so a run whose "real" home were the test home
# would be caught by its own synthetic rows.
$realAfter = Get-FixtureRows $realDb
Check ($realAfter -eq $realBefore) ("the real Horde home's database gained no synthetic row and was not created (" + $realBefore + " -> " + $realAfter + "; -1 = no database)")

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-meter-e2e-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "collect is incremental and idempotent, status reports it, the dry-run watch names the stopped session, and nothing real is touched"
