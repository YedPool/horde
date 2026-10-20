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
#   - a mistyped verb is refused, and a machine without Node fails at once in one sentence.
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
Check ($i1.code -eq 0 -and $i1.out -cmatch 'fleet\.db: .+fleet\.db \(schema 3, created\)') ("init creates the file at schema 3 (" + $i1.out.Trim() + ")")
Check (Test-Path -LiteralPath $dbFile -PathType Leaf) "under the home it was given"
$i2 = Invoke-Db @("init")
Check ($i2.code -eq 0 -and $i2.out -like "*already there, now current*") "init again keeps it"

Write-Host ""
Write-Host "=== status ===" -ForegroundColor Cyan
$s1 = Invoke-Db @("status")
Check ($s1.code -eq 0 -and $s1.out -cmatch 'database: .+fleet\.db \(schema 3, \d+ bytes\)') "status names the file, its schema and its size"
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

Complete-HordeSuite -Success "init is safe to repeat, status counts every table, check names a broken list, and nothing real is touched"
