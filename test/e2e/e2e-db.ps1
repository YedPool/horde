# END TO END: `horde db init`, `status` and `check`, driven at the real command line.
#
# The user of these verbs is whoever sets up fleet.db on a PC and later asks whether it is sound: they run
# init once (and again, by habit), read status to see the tables fill, and run check before trusting it.
# This scenario is that, with the shipped horde.ps1 run as its own process (test/lib/Cli.ps1) against a
# Horde home of its own:
#   - with HORDE_HOME unset, every verb is refused in one sentence about the home and nothing is made,
#     not even in the default home under the user profile (fleet.db is never made in a default folder);
#   - status and check before init say to run init, and create nothing;
#   - init creates fleet.db at the current schema, and init again keeps it;
#   - status names the file and counts the rows of every table, the decisions lists among them;
#   - check says ok on a sound file, and on a file holding a decisions list that is missing a line it
#     names the list and fails, so a script or a scheduler sees it;
#   - import reads small fixture files of the old formats (ledger, PR cache, changelog, status cards, a
#     session record with a byte order mark) into a fleet.db of its own: it names the rows added per table
#     and the lines it could not link, a second import adds nothing, a dry run writes nothing, a flag
#     meant for import is refused on another verb, and a file that is not there is refused;
#   - import -Lots reads a hibernations folder (lane K's one-file-per-table lots): the lot, members, wake and
#     the sessions fleet.db never saw come in, a legacy record is named and left, a second import adds nothing,
#     a member that woke since is moved forward, -Lots on another verb is refused, a file of the wrong table is
#     reported;
#   - a mistyped verb is refused, and a machine without Node fails at once in one sentence.
#   - work start, list and end (an agent and a warg through the real horde.ps1): the repeat of each says already
#     started / already ended and exits 0, a different outcome for an ended unit is refused, check stays ok;
# NOTHING REAL IS READ OR WRITTEN: the home and the user profile every child sees are folders this
# scenario made and removes. The real homes (HORDE_HOME if set, and the profile's .horde) are checked
# before and after: neither may have gained a fleet.db (CONTRIBUTING 9).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] no node here: fleet.db cannot run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}

$script:work = Join-Path $env:TEMP ("horde-db-e2e-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$fakeProfile = Join-Path $script:work "profile"
New-Item -ItemType Directory -Path $fakeProfile | Out-Null
$realHomes = @((Join-Path (Join-Path "$env:USERPROFILE" ".horde") "fleet.db"))
if ("$env:HORDE_HOME".Trim() -ne "") { $realHomes += (Join-Path $env:HORDE_HOME "fleet.db") }
$realBefore = @($realHomes | ForEach-Object { Test-Path -LiteralPath $_ })
$cliEnv = @{ HORDE_HOME = $hordeHome; USERPROFILE = $fakeProfile }
function Invoke-Db { param([string[]]$DbArgs, [hashtable]$Env = $cliEnv) return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("db") + $DbArgs) -Env $Env) }
$dbFile = Join-Path $hordeHome "fleet.db"

try {

Write-Host ""
Write-Host "=== no home ===" -ForegroundColor Cyan
foreach ($verb in @("init", "status", "check")) {
    $r = Invoke-Db @($verb) @{ HORDE_HOME = ""; USERPROFILE = $fakeProfile }
    Check ($r.code -ne 0 -and $r.out -like "*horde db needs HORDE_HOME set*") ("db " + $verb + " with HORDE_HOME unset is refused, naming the home (" + $r.code + ")")
}
Check (-not (Test-Path -LiteralPath (Join-Path $fakeProfile ".horde\fleet.db"))) "and no fleet.db was made in the default home under the profile"

Write-Host ""
Write-Host "=== before init ===" -ForegroundColor Cyan
$s0 = Invoke-Db @("status")
Check ($s0.code -ne 0 -and $s0.out -like "*does not exist yet*run horde db init*") ("status before init says to run init (" + $s0.code + ")")
$c0 = Invoke-Db @("check")
Check ($c0.code -ne 0 -and $c0.out -like "*run horde db init*") "check before init says the same"
Check (-not (Test-Path -LiteralPath $dbFile)) "neither made the file"

Write-Host ""
Write-Host "=== init, twice ===" -ForegroundColor Cyan
$i1 = Invoke-Db @("init")
Check ($i1.code -eq 0 -and $i1.out -cmatch 'fleet\.db: .+fleet\.db \(schema 9, created\)') ("init creates the file at schema 9 (" + $i1.out.Trim() + ")")
Check (Test-Path -LiteralPath $dbFile -PathType Leaf) "under the home it was given"
$i2 = Invoke-Db @("init")
Check ($i2.code -eq 0 -and $i2.out -like "*already there, now current*") "init again keeps it"

Write-Host ""
Write-Host "=== status ===" -ForegroundColor Cyan
$s1 = Invoke-Db @("status")
Check ($s1.code -eq 0 -and $s1.out -cmatch 'database: .+fleet\.db \(schema 9, \d+ bytes\)') "status names the file, its schema and its size"
Check ($s1.out -cmatch '(?m)^decisions_snapshot: 0 rows\r?$' -and $s1.out -cmatch '(?m)^task_event: 0 rows\r?$' -and $s1.out -cmatch '(?m)^orc: 0 rows\r?$') "and counts the rows of every table"

Write-Host ""
Write-Host "=== check ===" -ForegroundColor Cyan
$k1 = Invoke-Db @("check")
Check ($k1.code -eq 0 -and $k1.out -cmatch '(?m)^check: ok\r?$') ("check says ok on a sound file (" + $k1.code + ")")
# A decisions list that says two lines and holds one: written through the store, the one write path.
$seed = Join-Path $script:work "seed.mjs"
$storeUrl = ([System.Uri](Join-Path $root "fleet-db\store.mjs")).AbsoluteUri
$seedText = "import { openStore } from '" + $storeUrl + "';`n" +
    "const db = openStore(process.argv[2]);`n" +
    "db.prepare(""INSERT INTO node (id, name, is_authority, created_at) VALUES ('01J0000000000000000000000N', 'pc', 1, 1)"").run();`n" +
    "db.prepare(""INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES ('01J0000000000000000000000F', 'F', 'f', 'F', 'orc', 1)"").run();`n" +
    "db.prepare(""INSERT INTO decisions_snapshot (id, orc_id, published_at, item_count, sha256) VALUES ('01J0000000000000000000000S', '01J0000000000000000000000F', 1, 2, '" + ("a" * 64) + "')"").run();`n" +
    "db.prepare(""INSERT INTO decisions_snapshot_item (snapshot_id, position, text) VALUES ('01J0000000000000000000000S', 1, 'one line')"").run();`n" +
    "db.close();`n"
[System.IO.File]::WriteAllText($seed, $seedText, (New-Object System.Text.UTF8Encoding($false)))
$made = Start-Process -FilePath $node.Source -ArgumentList @(('"' + $seed + '"'), ('"' + $dbFile + '"')) -Wait -PassThru -NoNewWindow
Check ($made.ExitCode -eq 0) "CONTROL: a decisions list missing a line is written"
$k2 = Invoke-Db @("check")
Check ($k2.code -ne 0 -and $k2.out -like "*problem: decisions list 01J0000000000000000000000S says 2 lines and holds 1*") ("check names the list and fails (" + $k2.code + ")")
Check ($k2.out -like "*problem: decisions list 01J0000000000000000000000S does not hash to its sha256*") "and that its lines do not hash to the list's sha256"
Check ($k2.out -cmatch '(?m)^check: 2 problems\r?$') "and counts two problems"
Check ($k2.out -like "*horde db check stopped with exit code 1*") "and the command says it stopped with that exit code"

Write-Host ""
Write-Host "=== import ===" -ForegroundColor Cyan
# A Horde home of its own: the check section above filled the first one with rows of its own.
$impHome = Join-Path $script:work "home-import"
$impEnv = @{ HORDE_HOME = $impHome; USERPROFILE = $fakeProfile }
$src = Join-Path $script:work "sources"
New-Item -ItemType Directory -Path (Join-Path $src "orcs\form-fill"), (Join-Path $src "thrall"), (Join-Path $src "sessions") -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$utf8bom = New-Object System.Text.UTF8Encoding($true)
function Save-Text { param([string]$Path, [string]$Text, $Enc = $utf8) [System.IO.File]::WriteAllText($Path, $Text, $Enc) }
$ledgerFile = Join-Path $src "tasks.jsonl"
Save-Text $ledgerFile ((@(
    '{"ts":"2026-10-05T17:00:00+00:00","task":"T-0001","event":"opened","title":"Root","source":"founder","lane":"form-fill","prio":2,"parent":null,"by":"analyst-backfill"}',
    '{"ts":"2026-10-05T18:00:00Z","task":"T-0001","event":"started","by":"C13"}',
    '{"ts":"2026-10-05T19:00:00+00:00","task":"T-0001","event":"done","by":"C","pr":"OrahVision/horde#5"}'
) -join "`r`n") + "`r`n")
$prFile = Join-Path $src "pr-cache.json"
Save-Text $prFile '{"OrahVision/horde#5":{"checked":"2026-10-15T19:49:05+00:00","mergedAt":"2026-10-14T10:00:00Z","state":"MERGED"}}'
$logFile = Join-Path $src "changelog.jsonl"
Save-Text $logFile '{"v":1,"id":"20261011T035700Z-01","ts":"2026-10-11T03:57:00Z","kind":"progress","area":"Lane C","title":"first","text":"Happened: a","lane":"C,F","task":"T-0001 (root)"}'
$cardText = "horde-orc-status 1`norc: C`nlane: Form fill`ndoing: filling forms`nfinished: one form`nblocked: no`n"
Save-Text (Join-Path $src "orcs\form-fill\status.txt") $cardText
Save-Text (Join-Path $src "thrall\status.txt") ($cardText.Replace("orc: C", "orc: M").Replace("Form fill", "Thrall"))
$sessionFile = Join-Path $src "sessions\00000000-0000-4000-8000-000000000001.json"
Save-Text $sessionFile ('{"owner":"C","label":"C3","firstSeen":"10/17/2026 01:49:32","lastSeen":"2026-10-18T10:00:00.0000000Z","parent":"00000000-0000-4000-8000-000000000099"}') $utf8bom
$impArgs = @("import", "-Ledger", $ledgerFile, "-PrCache", $prFile, "-Changelog", $logFile, "-Cards", (Join-Path $src "orcs"), "-ThrallCard", (Join-Path $src "thrall\status.txt"), "-Registry", (Join-Path $src "sessions"))

$noDb = Invoke-Db $impArgs $impEnv
Check ($noDb.code -ne 0 -and $noDb.out -like "*run horde db init*") ("import before init says to run init (" + $noDb.code + ")")
Check (-not (Test-Path -LiteralPath (Join-Path $impHome "fleet.db"))) "and made no file"
$null = Invoke-Db @("init") $impEnv
$dry = Invoke-Db ($impArgs + "-DryRun") $impEnv
Check ($dry.code -eq 0 -and $dry.out -cmatch '(?m)^import: dry run, nothing was written\r?$' -and $dry.out -cmatch '(?m)^task_event: 3 added, 0 already there\r?$') ("a dry run says what it would add (" + $dry.code + ")")
Check ((Invoke-Db @("status") $impEnv).out -cmatch '(?m)^task_event: 0 rows\r?$') "and wrote nothing"
$i1 = Invoke-Db $impArgs $impEnv
Check ($i1.code -eq 0 -and $i1.out -cmatch '(?m)^import: done\r?$') ("import ends 0 (" + $i1.code + ")")
Check ($i1.out -cmatch '(?m)^orc: 2 added, 0 already there\r?$' -and $i1.out -cmatch '(?m)^task: 1 added, 0 already there\r?$' -and $i1.out -cmatch '(?m)^task_event: 3 added, 0 already there\r?$' -and $i1.out -cmatch '(?m)^pr: 1 added, 0 already there\r?$' -and $i1.out -cmatch '(?m)^session: 2 added, 0 already there\r?$' -and $i1.out -cmatch '(?m)^changelog_entry: 1 added, 0 already there\r?$' -and $i1.out -cmatch '(?m)^orc_status: 2 added, 0 already there\r?$') "it names the rows added in every table (a session and its missing parent's stub among them)"
Check ($i1.out -like "*ledger: by analyst-backfill names no Orc row (kept as by_text): 1*" -and $i1.out -like "*registry: parent is not in the registry (stub row made): 1*") "and the lines it could not link, with their counts"
Check ((Invoke-Db @("status") $impEnv).out -cmatch '(?m)^task_event: 3 rows\r?$') "status counts the imported events"
$i2 = Invoke-Db $impArgs $impEnv
Check ($i2.code -eq 0 -and $i2.out -cmatch '(?m)^task_event: 0 added, 3 already there\r?$' -and $i2.out -cmatch '(?m)^session: 0 added, 1 already there\r?$' -and $i2.out -cmatch '(?m)^orc_status: 0 added, 2 already there\r?$' -and $i2.out -cmatch '(?m)^changelog_entry: 0 added, 1 already there\r?$') "a second import adds nothing in any table"
Check ((Invoke-Db @("check") $impEnv).code -eq 0) "and check says the imported file is sound"
$flagOnOther = Invoke-Db @("status", "-Ledger", $ledgerFile) $impEnv
Check ($flagOnOther.code -ne 0 -and $flagOnOther.out -like "*-Ledger belongs to db import, not db status*") ("a flag meant for import is refused on another verb (" + $flagOnOther.code + ")")
$missing = Invoke-Db @("import", "-Ledger", (Join-Path $src "nope.jsonl")) $impEnv
Check ($missing.code -ne 0 -and $missing.out -like "*ENOENT*") ("a source file that is not there is refused (" + $missing.code + ")")
$none = Invoke-Db @("import") $impEnv
Check ($none.code -ne 0 -and $none.out -like "*at least one source*") "import with no source is refused"

Write-Host ""
Write-Host "=== import: the decisions store, then a publish naming its question ===" -ForegroundColor Cyan
# The fixture records are hashed by the store's own function (decisions/Rules.ps1), so a requestHash the
# importer calls different would mean the importer's recomputation is not the store's.
. (Join-Path $root "decisions\Rules.ps1")
$decDir = Join-Path $src "store\decisions"
New-Item -ItemType Directory -Path $decDir -Force | Out-Null
function Save-DecisionRecord {
    param([int]$Sequence, [string]$Kind, [string]$Operation, [string]$Actor, [int]$Number, $Body, $Data, [string]$At)
    $hash = Get-HordeDecisionHash -Value ([ordered]@{ operation = $Operation; actor = $Actor; number = $Number; body = $Body })
    $record = [ordered]@{ schemaVersion = 1; sequence = $Sequence; id = ("{0:x32}" -f $Sequence); kind = $Kind; at = $At; actor = $Actor; requestHash = $hash; data = $Data }
    Save-Text (Join-Path $decDir ("{0:d10}.json" -f $Sequence)) (ConvertTo-Json -InputObject $record -Compress -Depth 12)
}
$question31 = [ordered]@{ title = "Does the fixture question import?"; kind = "yes-no"; options = @(); parts = @(); whatItIs = "A question made for this scenario."; yesMeans = "It imported."; recommendation = "yes."; group = "Fixture"; groupNote = ""; askedBy = "Orc C"; waiting = @(); files = @(); references = @(); needsSecret = $false }
Save-DecisionRecord -Sequence 1 -Kind "question-added" -Operation "add" -Actor "warchief" -Number 0 -Body ([ordered]@{ question = $question31 }) -Data ([ordered]@{ number = 31; question = $question31 }) -At "2026-10-07T16:26:16.9667002Z"
$said = [ordered]@{ speaker = "founder"; route = "window"; text = "yes"; wordingVersion = 1 }
Save-DecisionRecord -Sequence 2 -Kind "message-said" -Operation "say" -Actor "founder" -Number 31 -Body $said -Data ([ordered]@{ number = 31; speaker = "founder"; route = "window"; text = "yes"; wordingVersion = 1 }) -At "2026-10-07T16:27:00.1000000Z"
$decArgs = @("import", "-Decisions", $decDir)
$decDry = Invoke-Db ($decArgs + "-DryRun") $impEnv
Check ($decDry.code -eq 0 -and $decDry.out -cmatch '(?m)^question: 1 added, 0 already there\r?$' -and $decDry.out -cmatch '(?m)^answer: 1 added, 0 already there\r?$') ("a dry run says what the store would add (" + $decDry.code + ")")
Check ((Invoke-Db @("status") $impEnv).out -cmatch '(?m)^question: 0 rows\r?$') "and wrote nothing"
$dec1 = Invoke-Db $decArgs $impEnv
Check ($dec1.code -eq 0 -and $dec1.out -cmatch '(?m)^question: 1 added, 0 already there\r?$' -and $dec1.out -cmatch '(?m)^answer: 1 added, 0 already there\r?$' -and $dec1.out -cmatch '(?m)^answer_extra: 1 added, 0 already there\r?$') ("the store imports: a question and its answer (" + $dec1.code + ")")
Check ($dec1.out -notlike "*requestHash*") "and no record's requestHash differs from the one the importer recomputes (the store's own hash made them)"
Check ($dec1.out -like "*decisions: question names no task*: 1*") "and the question that names no task is reported"
$dec2 = Invoke-Db $decArgs $impEnv
Check ($dec2.code -eq 0 -and $dec2.out -cmatch '(?m)^question: 0 added, 1 already there\r?$' -and $dec2.out -cmatch '(?m)^answer: 0 added, 1 already there\r?$') "a second import adds nothing"
Check ((Invoke-Db @("check") $impEnv).code -eq 0) "and check says the file is still sound"
$decWrongVerb = Invoke-Db @("check", "-Decisions", $decDir) $impEnv
Check ($decWrongVerb.code -ne 0 -and $decWrongVerb.out -like "*-Decisions belongs to db import, not db check*") "-Decisions on another verb is refused"
# A gap in the sequence refuses the store, whole.
$gapDir = Join-Path $src "store-gap"
New-Item -ItemType Directory -Path $gapDir | Out-Null
Copy-Item -LiteralPath (Join-Path $decDir "0000000002.json") -Destination (Join-Path $gapDir "0000000002.json")
$gap = Invoke-Db @("import", "-Decisions", $gapDir) $impEnv
Check ($gap.code -eq 0 -and $gap.out -like "*decisions: source refused, nothing imported from it: a gap in the sequence: record 1 is not there*") "a store with a hole in its sequence is refused, whole, in words"
# Publish: the node side of `horde decisions publish`, as the command calls it (the command itself proves the
# calling session from the fleet's records, which this scenario has not got). The list names question 31.
function Invoke-NodeCli {
    param([string[]]$NodeArgs, [string]$HomeDir)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = ($NodeArgs | ForEach-Object { '"' + $_ + '"' }) -join " "
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_HOME"] = $HomeDir
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $errTask = $p.StandardError.ReadToEndAsync()
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        return [pscustomobject]@{ code = $p.ExitCode; out = ($out + "`n" + $errTask.Result) }
    } finally { $p.Dispose() }
}
$decCli = Join-Path $root "fleet-db\decisions-cli.mjs"
$pubOk = Join-Path $script:work "publish-31.json"
Save-Text $pubOk '{"who":{"letter":"C"},"sessionId":"none","items":[{"questionNumber":31,"text":"Does the fixture question import?","recommendation":"yes"}]}'
$pubBad = Join-Path $script:work "publish-99.json"
Save-Text $pubBad '{"who":{"letter":"C"},"sessionId":"none","items":[{"questionNumber":99,"text":"A question that was never imported"}]}'
$pBad = Invoke-NodeCli @($decCli, "publish", $pubBad) $impHome
Check ($pBad.code -ne 0 -and $pBad.out -like "*item 1 names question 99, which is not in the decisions store*") ("CONTROL: a list naming a question that was never imported is refused (" + $pBad.code + ")")
$pOk = Invoke-NodeCli @($decCli, "publish", $pubOk) $impHome
Check ($pOk.code -eq 0 -and $pOk.out -cmatch 'published 1 item \(snapshot ') ("a list naming the imported question 31 is published (" + $pOk.code + ": " + $pOk.out.Trim() + ")")
$listed = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "published") -Env $impEnv
Check ($listed.code -eq 0 -and $listed.out -like "*Does the fixture question import?*" -and $listed.out -like "*question 31*") ("and horde decisions published shows the line with its question number (" + $listed.code + ")")
Check ((Invoke-Db @("check") $impEnv).code -eq 0) "and check says the file is sound with the list in it"
# The same list again records a confirm (T-0299): unchanged, no new snapshot, and a later confirmed time.
$pj1 = Invoke-NodeCli @($decCli, "published", "--json") $impHome
Start-Sleep -Milliseconds 1100
$pAgain = Invoke-NodeCli @($decCli, "publish", $pubOk) $impHome
Check ($pAgain.code -eq 0 -and $pAgain.out -cmatch 'unchanged, confirmed \d{4}-\d\d-\d\dT[\d:.]+Z \(snapshot ') ("the same list published twice says unchanged and names the confirm time (" + $pAgain.code + ": " + $pAgain.out.Trim() + ")")
$pj2 = Invoke-NodeCli @($decCli, "published", "--json") $impHome
$l1 = (($pj1.out.Trim() -split "`n")[0] | ConvertFrom-Json).lists[0]
$l2 = (($pj2.out.Trim() -split "`n")[0] | ConvertFrom-Json).lists[0]
Check ($l1.snapshot -eq $l2.snapshot -and $l1.publishedAt -eq $l2.publishedAt) "and the list is the same snapshot, published at the same time"
Check ([datetime]$l2.confirmedAt -gt [datetime]$l1.confirmedAt -and [datetime]$l1.confirmedAt -ge [datetime]$l1.publishedAt) ("and published --json shows a later confirmedAt (" + $l1.confirmedAt + " then " + $l2.confirmedAt + ")")
$listed2 = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "published") -Env $impEnv
$c2 = [regex]::Match($pj2.out, 'confirmedAt\W+([0-9TZ:.-]+)').Groups[1].Value
Check ($listed2.code -eq 0 -and $c2 -ne "" -and $listed2.out -like ("*confirmed " + $c2 + "*")) "and horde decisions published prints the confirm time"

Write-Host ""
Write-Host "=== import: the parking lots (lane K's one-file-per-table form) ===" -ForegroundColor Cyan
$lotsDir = Join-Path $src "hibernations"
$lotId = "01K8T0N2E0S6V7W8X9Y0Z1A2B3"
$wakeId = "01K8T1Q2E0S6V7W8X9Y0Z1A2B3"
$lotSession1 = "33333333-0000-4000-8000-000000000001"
$lotSession2 = "33333333-0000-4000-8000-000000000002"
$lotDir = Join-Path $lotsDir "20261019-202000"
New-Item -ItemType Directory -Path (Join-Path $lotDir ("wakes\" + $wakeId)), (Join-Path $lotsDir "20260101-000000") -Force | Out-Null
Save-Text (Join-Path $lotsDir "20260101-000000\record.json") '{"id":"20260101-000000"}'
function Save-LotMembers { param([string]$State)
    Save-Text (Join-Path $lotDir "parking_lot_member.json") ('{"v":1,"table":"parking_lot_member","rows":[{"lot_id":"' + $lotId + '","session_id":"' + $lotSession1 + '","orc_id":"C","tier":2,"state":"' + $State + '"},{"lot_id":"' + $lotId + '","session_id":"' + $lotSession2 + '","state":"parked","note":"lanes/c/PARKED-C1.md"}]}')
}
Save-LotMembers "parked"
Save-Text (Join-Path $lotDir "parking_lot.json") ('{"v":1,"table":"parking_lot","rows":[{"id":"' + $lotId + '","created_at":"2026-10-19T20:20:00Z","created_by_orc_id":"C","reason":"free memory","selection_kind":"orcs","keep_visible":1}]}')
Save-Text (Join-Path $lotDir ("wakes\" + $wakeId + "\wake_member.json")) ('{"v":1,"table":"wake_member","rows":[{"wake_id":"' + $wakeId + '","session_id":"' + $lotSession1 + '","outcome":"woken"}]}')
Save-Text (Join-Path $lotDir ("wakes\" + $wakeId + "\wake.json")) ('{"v":1,"table":"wake","rows":[{"id":"' + $wakeId + '","lot_id":"' + $lotId + '","requested_at":"2026-10-19T21:00:00Z"}]}')
$lotArgs = @("import", "-Lots", $lotsDir)
$lotDry = Invoke-Db ($lotArgs + "-DryRun") $impEnv
Check ($lotDry.code -eq 0 -and $lotDry.out -cmatch '(?m)^parking_lot: 1 added, 0 already there\r?$' -and $lotDry.out -cmatch '(?m)^parking_lot_member: 2 added, 0 already there, 0 moved forward\r?$') ("a dry run says what the lots would add (" + $lotDry.code + ")")
Check ((Invoke-Db @("status") $impEnv).out -cmatch '(?m)^parking_lot: 0 rows\r?$') "and wrote nothing"
$lot1 = Invoke-Db $lotArgs $impEnv
Check ($lot1.code -eq 0 -and $lot1.out -cmatch '(?m)^parking_lot: 1 added, 0 already there\r?$' -and $lot1.out -cmatch '(?m)^parking_lot_member: 2 added, 0 already there, 0 moved forward\r?$' -and $lot1.out -cmatch '(?m)^wake: 1 added, 0 already there\r?$' -and $lot1.out -cmatch '(?m)^wake_member: 1 added, 0 already there\r?$' -and $lot1.out -cmatch '(?m)^session: 2 added, 0 already there\r?$') ("the lot, its members, its wake and the two sessions fleet.db had never seen come in (" + $lot1.code + ")")
Check ($lot1.out -like "*lots: legacy record, run K's lot backfill first (not imported): 1 (e.g. 20260101-000000)*") "and the legacy record is named, not imported"
$lot2 = Invoke-Db $lotArgs $impEnv
Check ($lot2.code -eq 0 -and $lot2.out -cmatch '(?m)^parking_lot: 0 added, 1 already there\r?$' -and $lot2.out -cmatch '(?m)^parking_lot_member: 0 added, 2 already there, 0 moved forward\r?$' -and $lot2.out -cmatch '(?m)^wake: 0 added, 1 already there\r?$' -and $lot2.out -cmatch '(?m)^wake_member: 0 added, 1 already there\r?$') "a second import adds nothing"
Save-LotMembers "woken"
$lot3 = Invoke-Db $lotArgs $impEnv
Check ($lot3.code -eq 0 -and $lot3.out -cmatch '(?m)^parking_lot_member: 0 added, 2 already there, 1 moved forward\r?$') "a member that woke since is moved forward, not added again"
Check ((Invoke-Db @("check") $impEnv).code -eq 0) "and check says the file is still sound"
$lotWrongVerb = Invoke-Db @("status", "-Lots", $lotsDir) $impEnv
Check ($lotWrongVerb.code -ne 0 -and $lotWrongVerb.out -like "*-Lots belongs to db import, not db status*") "-Lots on another verb is refused"
Save-Text (Join-Path $lotDir "parking_lot_member.json") '{"v":1,"table":"wake","rows":[]}'
$lotBad = Invoke-Db $lotArgs $impEnv
Check ($lotBad.code -eq 0 -and $lotBad.out -like "*lots: a file is missing or is not version 1 of its table (nothing imported from this lot): 1*") "a member file of the wrong table is reported, in words"

Write-Host ""
Write-Host "=== work units: an agent and a warg through horde work ===" -ForegroundColor Cyan
$workHome = Join-Path $script:work "home-work"
$workEnv = @{ HORDE_HOME = $workHome; USERPROFILE = $fakeProfile }
function Invoke-Work { param([string[]]$WorkArgs, [hashtable]$Env = $workEnv) return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("work") + $WorkArgs) -Env $Env) }
$parentId = "00000000-0000-4000-8000-0000000000a1"
$wargId = "00000000-0000-4000-8000-0000000000b2"
$agentName = "a3f9c01b7d2e4f5a6"
$wn = Invoke-Work @("list") @{ HORDE_HOME = ""; USERPROFILE = $fakeProfile }
Check ($wn.code -ne 0 -and $wn.out -like "*horde work needs HORDE_HOME set*") "work with HORDE_HOME unset is refused, naming the home"
$w1 = Invoke-Work @("start", "-Kind", "agent", "-ParentSession", $parentId, "-AgentId", $agentName, "-AgentType", "general-purpose", "-WorkType", "research", "-Task", "T-0299", "-Domain", "fleet-db")
Check ($w1.code -eq 0 -and $w1.out -cmatch '(?m)^started agent [0-9A-Z]{26}\r?$' -and $w1.out -like "*warning: task T-0299 is not in fleet.db yet*") ("an agent starts; a task the ledger lacks is a warning, not a refusal (" + $w1.code + ")")
$w2 = Invoke-Work @("start", "-Kind", "agent", "-ParentSession", $parentId, "-AgentId", $agentName, "-WorkType", "research")
Check ($w2.code -eq 0 -and $w2.out -cmatch '(?m)^already started agent [0-9A-Z]{26}\r?$') "the same start again says already started and exits 0"
# The flip unsets HORDE_HOME: a hook then finds the home by the pointer alone, in a profile of its own.
$pointerProfile = Join-Path $script:work "profile-pointer"
New-Item -ItemType Directory -Force -Path $pointerProfile | Out-Null
[System.IO.File]::WriteAllText((Join-Path $pointerProfile ".horde-home.json"), ('{"v":1,"hordeHome":' + (ConvertTo-Json $workHome) + '}'))
$wp = Invoke-Work @("list") @{ HORDE_HOME = ""; USERPROFILE = $pointerProfile }
Check ($wp.code -eq 0 -and $wp.out -like "*$agentName*") ("with HORDE_HOME unset, work finds the home by the pointer (" + $wp.code + ")")
$w3 = Invoke-Work @("start", "-Kind", "warg", "-ParentSession", $parentId, "-Session", $wargId, "-WorkType", "build")
Check ($w3.code -eq 0 -and $w3.out -cmatch '(?m)^started warg [0-9A-Z]{26}\r?$') "a warg starts by its own session"
$wl = Invoke-Work @("list", "-Running")
Check ($wl.code -eq 0 -and $wl.out -like ("* agent running - no_task research " + $agentName + " *") -and $wl.out -like ("* warg running - no_task build " + $wargId + " *")) "list shows both running, the agent id exactly as given"
$wj = Invoke-Work @("list", "-Json")
Check ($wj.code -eq 0 -and $wj.out -like ('*"agent_id":"' + $agentName + '"*') -and $wj.out -like '*"domain":"fleet-db"*') "list -Json is one line of data"
$we = Invoke-Work @("end", "-ParentSession", $parentId, "-AgentId", $agentName, "-Outcome", "done")
Check ($we.code -eq 0 -and $we.out -cmatch '(?m)^ended [0-9A-Z]{26} as done\r?$') "the agent ends"
$we2 = Invoke-Work @("end", "-ParentSession", $parentId, "-AgentId", $agentName, "-Outcome", "done")
Check ($we2.code -eq 0 -and $we2.out -cmatch '(?m)^already ended ') "ending again says already ended and exits 0"
$we3 = Invoke-Work @("end", "-ParentSession", $parentId, "-AgentId", $agentName, "-Outcome", "failed")
Check ($we3.code -ne 0 -and $we3.out -like "*refused: already ended as done*") ("a different outcome for an ended unit is refused (" + $we3.code + ")")
$we4 = Invoke-Work @("end", "-Session", $wargId, "-Outcome", "stopped")
Check ($we4.code -eq 0) "the warg ends by its session"
$wl2 = Invoke-Work @("list", "-Running")
Check ($wl2.code -eq 0 -and $wl2.out -like "*no work units*") "nothing is running after both ended"
$wbad = Invoke-Work @("list", "-Kind", "agent")
Check ($wbad.code -ne 0 -and $wbad.out -like "*-Kind does not belong to work list*") "a flag of another verb is refused"
$wck = Invoke-HordeCliProcess -Root $root -HordeArgs @("db", "check") -Env $workEnv
Check ($wck.code -eq 0 -and $wck.out -cmatch '(?m)^check: ok\r?$') "horde db check says ok on the file the work verbs made"

Write-Host ""
Write-Host "=== the task list through horde task ===" -ForegroundColor Cyan
function Invoke-TaskList { param([string[]]$TaskArgs, [hashtable]$Env = $workEnv) return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("task") + $TaskArgs) -Env $Env) }
$tn = Invoke-TaskList @("list") @{ HORDE_HOME = ""; USERPROFILE = $fakeProfile }
Check ($tn.code -ne 0 -and $tn.out -like "*horde task needs HORDE_HOME set*") "task with HORDE_HOME unset is refused, naming the home"
$tl = Invoke-TaskList @("list")
Check ($tl.code -eq 0 -and $tl.out -cmatch '(?m)^0 open, and 0 done, not yet verified, not listed\r?$') ("an empty list says so in its counts (" + $tl.code + ")")
$tj = Invoke-TaskList @("list", "-Json")
Check ($tj.code -eq 0 -and $tj.out -like '*{"tasks":`[`],"done_not_verified":0}*') "task list -Json reaches the verb"
$to = Invoke-TaskList @("list", "-Orc", "nobody")
Check ($to.code -ne 0 -and $to.out -like "*refused: no Orc is called nobody*") ("-Orc reaches the verb, and a name it does not know is refused (" + $to.code + ")")
$tp = Invoke-TaskList @("list") @{ HORDE_HOME = ""; USERPROFILE = $pointerProfile }
Check ($tp.code -eq 0 -and $tp.out -like "*0 open*") ("with HORDE_HOME unset, task list finds the home by the pointer (" + $tp.code + ")")
$tv = Invoke-TaskList @("add")
Check ($tv.code -ne 0) ("a verb that is not list is refused (" + $tv.code + ")")
$tx = Invoke-TaskList @("list") @{ HORDE_HOME = (Join-Path $script:work "home-no-db"); USERPROFILE = $fakeProfile }
Check ($tx.code -ne 0 -and $tx.out -like "*fleet.db does not exist yet*" -and -not (Test-Path (Join-Path $script:work "home-no-db\fleet.db"))) ("a home with no fleet.db is told so, and none is made (" + $tx.code + ")")

Write-Host ""
Write-Host "=== refusals ===" -ForegroundColor Cyan
$bad = Invoke-Db @("drop")
Check ($bad.code -ne 0 -and $bad.out -like "*drop*") ("a verb that is not init, status or check is refused (" + $bad.code + ")")
$noNode = Invoke-Db @("status") @{ HORDE_HOME = $hordeHome; USERPROFILE = $fakeProfile; PATH = ($env:SystemRoot + "\System32;" + $env:SystemRoot + "\System32\WindowsPowerShell\v1.0") }
Check ($noNode.code -ne 0 -and $noNode.out -like "*needs Node.js 24 or later*") ("with no Node on the PATH it fails at once in one sentence (" + $noNode.code + ")")

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-db-e2e-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue }
}
$realAfter = @($realHomes | ForEach-Object { Test-Path -LiteralPath $_ })
Check (($realAfter -join ",") -eq ($realBefore -join ",")) "no real Horde home gained or lost a fleet.db"

Complete-HordeSuite -Success "init is safe to repeat, status counts every table, check names a broken list, import adds each row once, and nothing real is touched"
