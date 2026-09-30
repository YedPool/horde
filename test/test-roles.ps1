# DOES HORDE READ WEZFLEET'S ROLES CORRECTLY, WITHOUT EVER WRITING TO WEZFLEET?
#
# Every lesson here is cited in planning/ledger/core-roles.md. Nothing touches the real wezfleet store:
# a throwaway store is built in TEMP and reached through WEZFLEET_ROOT, the same override wezfleet's own
# tests use.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "core\Roles.ps1")

$fails = @()
# A condition must be exactly true or false; anything else fails loudly (see test-isolation.ps1).
function Check { param($Cond, [string]$What)
    if ($Cond -isnot [bool]) { Write-Host "  [FAIL] $What (the check's condition was not true or false)" -ForegroundColor Red; $script:fails += $What; return }
    if ($Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }
# A section's checks run inside try/finally so its throwaway store is always removed. An error that
# stops a statement inside try jumps straight to finally and skips every check after it - found
# 2026-09-29 when a call to a not-yet-written function skipped the rest of the store section and
# the suite still exited 0. So each such section also catches, and a section that stopped early fails.
function SectionStopped { param([string]$Section, $Err)
    Write-Host "  [FAIL] the '$Section' section stopped early: $Err" -ForegroundColor Red
    $script:fails += ("the '" + $Section + "' section stopped early: " + $Err) }
function RoleOf { param($R) if ($R.role.state -eq "known") { return "$($R.role.value)" } return "unknown" }

$table = Get-HordeRoleTable

Write-Host ""
Write-Host "--- the alias table ---" -ForegroundColor Cyan

Check ((RoleOf (Resolve-HordeRole -Raw "master" -Table $table)) -eq "warchief" -and
       (RoleOf (Resolve-HordeRole -Raw "orchestrator" -Table $table)) -eq "orc" -and
       (RoleOf (Resolve-HordeRole -Raw "session" -Table $table)) -eq "goblin") "each wezfleet role reads as its horde role"
Check ((RoleOf (Resolve-HordeRole -Raw "warchief" -Table $table)) -eq "warchief" -and
       (RoleOf (Resolve-HordeRole -Raw "goblin" -Table $table)) -eq "goblin") "a native horde role reads as itself"
Check ((RoleOf (Resolve-HordeRole -Raw "MASTER" -Table $table)) -eq "warchief" -and
       (RoleOf (Resolve-HordeRole -Raw "Orchestrator" -Table $table)) -eq "orc") "role matching ignores case as wezfleet does"
$padded = Resolve-HordeRole -Raw " master" -Table $table
Check ((RoleOf $padded) -eq "unknown" -and $padded.raw -eq " master") "a padded role is not trimmed into a match"
$odd = Resolve-HordeRole -Raw "lane" -Table $table
Check ($odd.role.state -eq "unknown" -and $odd.raw -eq "lane" -and $odd.role.reason -like "*'lane'*") "an unrecognised role reads as unknown and keeps its raw value"
$mapped = Resolve-HordeRole -Raw "Master" -Table $table
Check ($mapped.raw -eq "Master" -and (RoleOf $mapped) -eq "warchief") "the raw role is returned beside the mapped role"
$missing = Read-HordeRecordRole -Record ([pscustomobject]@{ claudeSessionId = "x" }) -Table $table
$empty = Read-HordeRecordRole -Record ([pscustomobject]@{ claudeSessionId = "x"; role = "" }) -Table $table
Check ($missing.role.state -eq "unknown") "a record with no role reads as unknown"
Check ($missing.field -eq "missing" -and $empty.field -eq "empty" -and $missing.role.reason -ne $empty.role.reason) "an absent role and an empty role are reported apart"
# A record built in memory is often a hashtable, not a parsed-JSON object. Its keys are not
# properties, and a lookup written for objects read @{ role = "master" } as having no role.
$fromMap = Read-HordeRecordRole -Record @{ claudeSessionId = "x"; role = "master" } -Table $table
Check ((RoleOf $fromMap) -eq "warchief" -and $fromMap.field -eq "present") "a record held as a hashtable reads its role"
Check ((Read-HordeRecordRole -Record @{ claudeSessionId = "x" } -Table $table).field -eq "missing") "and a hashtable with no role key reads as missing"
$labelled = Read-HordeRecordRole -Record ([pscustomobject]@{ claudeSessionId = "x"; label = "M" }) -Table $table
Check ($labelled.role.state -eq "unknown") "role is never inferred from the label"

# DRIFT: every role wezfleet can store must have an alias, so a fourth wezfleet role cannot arrive
# unmapped. Read from the wezfleet repository's own source, checked out beside this one or named by
# HORDE_WEZFLEET_REPO. With neither, the check FAILS unless HORDE_SKIP_DRIFT=1 asks to skip it.
$hier = $null
foreach ($up in @("..", "..\..", "..\..\..")) {
    $cand = Join-Path $root ($up + "\wezfleet\lib\Hierarchy.ps1")
    if (Test-Path -LiteralPath $cand) { $hier = $cand; break }
}
if ($env:HORDE_WEZFLEET_REPO) { $hier = Join-Path $env:HORDE_WEZFLEET_REPO "lib\Hierarchy.ps1" }
if ($hier -and (Test-Path -LiteralPath $hier)) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($hier, [ref]$tokens, [ref]$errors)
    $assign = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and "$($n.Left.Extent.Text)" -eq '$script:WfRoles' }, $true) | Select-Object -First 1
    $wf = @()
    if ($assign) { $wf = @($assign.Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value }) }
    Check ($wf.Count -ge 3) "CONTROL: wezfleet's role list was found and read"
    $unmapped = @($wf | Where-Object { -not $table.aliases.ContainsKey($_.ToLowerInvariant()) })
    Check ($unmapped.Count -eq 0) ("every role wezfleet can store has an alias (" + ($unmapped -join ", ") + ")")
} elseif ($env:HORDE_SKIP_DRIFT -eq "1") {
    # Skipping is allowed only when asked for by name, and says so on every run.
    Write-Host "  [SKIP] the drift check did not run: HORDE_SKIP_DRIFT=1 and no wezfleet checkout was found" -ForegroundColor Yellow
} else {
    # A check that did not run is not a pass. It used to print "inconclusive" and exit 0, so a
    # machine without wezfleet beside Horde passed a check it never made (review, 2026-09-29).
    Check $false ("the drift check ran: no wezfleet lib\Hierarchy.ps1 was found (set HORDE_WEZFLEET_REPO to a wezfleet checkout, or HORDE_SKIP_DRIFT=1 to skip it on purpose)")
}

Write-Host ""
Write-Host "--- reading a wezfleet store ---" -ForegroundColor Cyan

# A throwaway store, shaped like the real one: records, a writer's temp file, claims, and the other
# stores the no-write check must cover.
$store = Join-Path $env:TEMP ("horde-roles-store-" + [guid]::NewGuid().ToString("N"))
$sess = Join-Path $store "registry\sessions"; $claimsDir = Join-Path $store "registry\claims"
foreach ($d in @($sess, $claimsDir, (Join-Path $store "registry\labels"), (Join-Path $store "mail"), (Join-Path $store "codex-sessions"), (Join-Path $store "locks"))) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
function Put { param([string]$Path, $Obj) Set-Content -LiteralPath $Path -Value ($Obj | ConvertTo-Json -Depth 5) -Encoding UTF8 }
Put (Join-Path $sess "m1.json") @{ claudeSessionId = "m1"; role = "master"; label = "M" }
Put (Join-Path $sess "o1.json") @{ claudeSessionId = "o1"; role = "orchestrator"; label = "A" }
Put (Join-Path $sess "o2.json") @{ claudeSessionId = "o2"; role = "orchestrator"; label = "B"; retired = $true }
Put (Join-Path $sess "s1.json") @{ claudeSessionId = "s1"; role = "session"; label = "A7" }
Put (Join-Path $sess "n1.json") @{ claudeSessionId = "n1"; label = "C" }
Put (Join-Path $sess "n2.json") @{ claudeSessionId = "n2"; label = "D"; retired = $true }
Put (Join-Path $sess "wrong-name.json") @{ claudeSessionId = "someone-else"; role = "master" }
Set-Content -LiteralPath (Join-Path $sess "m1.12345.abcd1234.tmp") -Value '{"claudeSessionId":"m1","role":"master"}'
Put (Join-Path $claimsDir "7.json") @{ role = "master"; claimedAt = "2026-09-29T00:00:00Z" }
Put (Join-Path $claimsDir "8.json") @{ role = "" }
# Pending by wezfleet's rule (lib/Registry.ps1 Read-WfPaneClaim, as lib/Master.ps1:130-137 calls it):
# a spawnedAt no older than the 10080-minute backstop. 7 has no spawnedAt, so it is not pending.
Put (Join-Path $claimsDir "9.json") @{ role = "master"; spawnedAt = (Get-Date).ToUniversalTime().AddHours(-1).ToString("o") }
Put (Join-Path $claimsDir "10.json") @{ role = "orchestrator"; spawnedAt = (Get-Date).ToUniversalTime().AddDays(-8).ToString("o") }
Set-Content -LiteralPath (Join-Path $store "registry\labels\A.claim") -Value "2026-09-29T00:00:00Z"
Put (Join-Path $store "index.json") @{ repos = @() }
Set-Content -LiteralPath (Join-Path $store "delivery.jsonl") -Value "{}"

$keepRoot = $env:WEZFLEET_ROOT
try {
    $env:WEZFLEET_ROOT = $store
    Check ((Get-HordeWezfleetRoot) -eq $store) "the wezfleet store root honours WEZFLEET_ROOT"
    # wezfleet uses WEZFLEET_ROOT whenever it is non-empty (lib/Common.ps1:16), spaces and all. Horde
    # used to trim it and fall back to the default store: a different store from the one wezfleet used.
    $env:WEZFLEET_ROOT = "   "
    $spacesRoot = Get-HordeWezfleetRoot
    $env:WEZFLEET_ROOT = $store
    Check ($spacesRoot -eq "   ") "a WEZFLEET_ROOT of only spaces is used as wezfleet uses it, not replaced by the default"

    # Fingerprint the whole store, then read it with every file held open against writing.
    function Get-StoreFingerprint { param([string]$Dir)
        return @(Get-ChildItem -LiteralPath $Dir -Recurse -Force | Sort-Object FullName | ForEach-Object {
            if ($_.PSIsContainer) { "D " + $_.FullName.Substring($Dir.Length) }
            else { "F " + $_.FullName.Substring($Dir.Length) + " " + $_.Length + " " + $_.LastWriteTimeUtc.Ticks + " " + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        }) -join "`n" }
    $before = Get-StoreFingerprint -Dir $store
    $holds = @(Get-ChildItem -LiteralPath $store -Recurse -File | ForEach-Object { [System.IO.File]::Open($_.FullName, "Open", "Read", "Read") })
    $read = $null; $threw = $null
    try { $read = Read-HordeWezfleetRoles } catch { $threw = $_.Exception.Message }
    $holds | ForEach-Object { $_.Dispose() }
    $after = Get-StoreFingerprint -Dir $store

    Check ($null -eq $threw -and $null -ne $read -and $read.complete.state -eq "known") "horde opens no wezfleet file for writing"
    Check ($before -eq $after) "reading leaves no new file in any wezfleet store"
    # CONTROL: the same comparison catches a reader that writes, so the check above can fail.
    Set-Content -LiteralPath (Join-Path $sess "m1.json.lock") -Value "x"
    Check ((Get-StoreFingerprint -Dir $store) -ne $before) "CONTROL: a reader that leaves a lock file behind is caught by the same comparison"
    Remove-Item -LiteralPath (Join-Path $sess "m1.json.lock") -Force

    $byId = @{}; foreach ($s in $read.sessions) { $byId[$s.id] = $s }
    Check ($byId.Count -eq 6) ("six records are read (" + (@($byId.Keys | Sort-Object) -join ", ") + ")")
    Check (-not $byId.ContainsKey("m1.12345.abcd1234") -and -not $byId.ContainsKey("wrong-name")) "a temp file beside the records is not read as a record"
    Check ((RoleOf $byId["o2"]) -eq "orc" -and $byId["o2"].retired) "a retired record still reads its role"
    # wezfleet skips a record whose claudeSessionId disagrees with its file name (lib/Registry.ps1:122).
    # Horde skips it too, but says so: a silently dropped record is how a master goes missing.
    Check (@($read.mismatched | Where-Object { $_ -like "*wrong-name.json" }).Count -eq 1) "a record whose id does not match its file name is listed, not silently skipped"
    Check ($byId["n1"].role.state -eq "unknown" -and $byId["n1"].field -eq "missing") "and a record with no role reads as unknown, not goblin"
    $c7 = @($read.claims | Where-Object { $_.pane -eq "7" })[0]
    $c8 = @($read.claims | Where-Object { $_.pane -eq "8" })[0]
    Check ((RoleOf $c7) -eq "warchief" -and $c8.field -eq "empty") "a claim role is read through the same alias table"
    # n1 is live and has no role: it may well be the warchief (every roleless record that mattered in
    # wezfleet was a lost master or orchestrator), so no role count over this store is known.
    $wcHole = Get-HordeRoleCount -Read $read -Role "warchief"
    Check ($wcHole.state -eq "unknown" -and $wcHole.reason -like "*n1*") "a live session whose role is unknown makes the role count unknown, naming it"
    Check ((Get-HordeRoleCount -Read $read -Role "goblin").state -eq "unknown") "and that holds for every role, not only warchief"

    # CONTROL: the same store without the live roleless record. n2 - retired and roleless - stays, so
    # the control also shows a retired session's unknown role does not matter to a live count.
    Remove-Item -LiteralPath (Join-Path $sess "n1.json") -Force
    $readClean = Read-HordeWezfleetRoles
    $wc = Get-HordeRoleCount -Read $readClean -Role "warchief"
    Check ($wc.state -eq "known" -and $wc.value -eq 1) "CONTROL: with every record readable, the warchief count is known"
    $oc = Get-HordeRoleCount -Read $readClean -Role "orc"
    Check ($oc.state -eq "known" -and $oc.value -eq 1) "a retired orc is not counted among the live ones"
    # A spawned master that has not yet run a tool has a claim and no record. wezfleet counts it as a
    # master (lib/Master.ps1:130-137); Horde reports it as its own number beside the session count.
    $pendingW = Get-HordeRoleClaimCount -Read $readClean -Role "warchief"
    Check ($pendingW.state -eq "known" -and $pendingW.value -eq 1) "a pending master claim is counted as a pending warchief, separately from sessions"
    $pendingO = Get-HordeRoleClaimCount -Read $readClean -Role "orc"
    Check ($pendingO.state -eq "known" -and $pendingO.value -eq 0) "a claim past wezfleet's seven-day backstop is not pending"
    Set-Content -LiteralPath (Join-Path $claimsDir "11.json") -Value ('{"role":"lane","spawnedAt":"' + (Get-Date).ToUniversalTime().ToString("o") + '"}')
    $readOddClaim = Read-HordeWezfleetRoles
    $pendingOdd = Get-HordeRoleClaimCount -Read $readOddClaim -Role "warchief"
    Check ($pendingOdd.state -eq "unknown" -and $pendingOdd.reason -like "*11*") "a pending claim whose role is unknown makes the pending count unknown"
    Remove-Item -LiteralPath (Join-Path $claimsDir "11.json") -Force

    # Counting "master" - wezfleet's word - matched nothing and answered a known 0 while a master ran.
    $wrongWord = $null
    try { $wrongWord = Get-HordeRoleCount -Read $readClean -Role "master" } catch { $wrongWord = "threw: " + $_.Exception.Message }
    Check ("$wrongWord" -like "threw:*warchief*") "counting a role that is not a native horde role is refused, naming the native ones"

    # One record that cannot be parsed: the counts become unknown instead of silently shrinking.
    Set-Content -LiteralPath (Join-Path $sess "broken.json") -Value "{ not json"
    $read2 = Read-HordeWezfleetRoles
    Check ((Get-HordeRoleCount -Read $read2 -Role "warchief").state -eq "unknown") "an unreadable record makes the role count unknown"
    Remove-Item -LiteralPath (Join-Path $sess "broken.json") -Force
}
catch { SectionStopped "reading a wezfleet store" $_ }
finally {
    $env:WEZFLEET_ROOT = $keepRoot
    if ((Split-Path -Leaf $store) -match '^horde-roles-store-[0-9a-f]{32}$') { Remove-Item -LiteralPath $store -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "--- a store that is not there is not an empty store ---" -ForegroundColor Cyan

# A wrong WEZFLEET_ROOT used to read as a complete, empty fleet: no sessions, known, count known 0.
$nowhere = Join-Path $env:TEMP ("horde-roles-nowhere-" + [guid]::NewGuid().ToString("N"))
$readNowhere = Read-HordeWezfleetRoles -Root $nowhere
Check ($readNowhere.complete.state -eq "unknown" -and $readNowhere.complete.reason -like "*sessions*") "a store with no sessions directory reads as unknown, not as an empty fleet"
Check ((Get-HordeRoleCount -Read $readNowhere -Role "warchief").state -eq "unknown") "and a role count over it is unknown, not zero"

# A sessions directory that exists but cannot be listed: a junction whose target has gone. Measured
# 2026-09-29: Test-Path says it is a container, listing it throws "Could not find a part of the path",
# and the same listing without -ErrorAction Stop quietly gives 0 files. (A deny ACE was tried first
# and did NOT stop the listing in this environment, so it could not serve as the case.)
$locked = Join-Path $env:TEMP ("horde-roles-locked-" + [guid]::NewGuid().ToString("N"))
$lockedSess = Join-Path $locked "registry\sessions"
$lockedTarget = Join-Path $locked "gone"
New-Item -ItemType Directory -Path $lockedTarget -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $locked "registry") -Force | Out-Null
try {
    $null = & cmd /c mklink /J $lockedSess $lockedTarget
    Remove-Item -LiteralPath $lockedTarget -Force
    $listable = $true
    try { $null = Get-ChildItem -LiteralPath $lockedSess -ErrorAction Stop } catch { $listable = $false }
    Check ((Test-Path -LiteralPath $lockedSess -PathType Container) -and $listable -eq $false) "CONTROL: the sessions directory is there but really cannot be listed"
    $readLocked = Read-HordeWezfleetRoles -Root $locked
    Check ($readLocked.complete.state -eq "unknown") "a sessions directory that cannot be listed reads as unknown"
}
catch { SectionStopped "a sessions directory that cannot be listed" $_ }
finally {
    # rmdir removes the junction itself, never what it points at.
    if (Test-Path -LiteralPath $lockedSess) { $null = & cmd /c rmdir $lockedSess }
    if ((Split-Path -Leaf $locked) -match '^horde-roles-locked-[0-9a-f]{32}$') { Remove-Item -LiteralPath $locked -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "--- reading never blocks the writer ---" -ForegroundColor Cyan

# wezfleet swaps a record in with [System.IO.File]::Replace. While Horde holds the file open to read,
# that swap must still succeed - and the control shows it would not with the ordinary read share.
$w = Join-Path $env:TEMP ("horde-share-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $w | Out-Null
try {
    $dest = Join-Path $w "rec.json"; Set-Content -LiteralPath $dest -Value "old"
    $tmp = Join-Path $w "rec.tmp"; Set-Content -LiteralPath $tmp -Value "new"
    $h = Open-HordeSharedStream -Path $dest
    $ok = $true
    try { [System.IO.File]::Replace($tmp, $dest, [NullString]::Value) } catch { $ok = $false }
    $h.Dispose()
    Check $ok "a wezfleet write succeeds while horde holds the file open for reading"
    Set-Content -LiteralPath $tmp -Value "newer"
    $plain = [System.IO.File]::Open($dest, "Open", "Read", "Read")
    $blocked = $false
    try { [System.IO.File]::Replace($tmp, $dest, [NullString]::Value) } catch { $blocked = $true }
    $plain.Dispose()
    Check $blocked "CONTROL: with the ordinary read share the same write fails"
}
catch { SectionStopped "reading never blocks the writer" $_ }
finally {
    if ((Split-Path -Leaf $w) -match '^horde-share-[0-9a-f]{32}$') { Remove-Item -LiteralPath $w -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
if ($fails.Count) {
    Write-Host "==== $($fails.Count) FAILURE(S) ====" -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "==== roles read in both vocabularies, and wezfleet is never written ====" -ForegroundColor Green
exit 0
