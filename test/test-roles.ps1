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
$labelled = Read-HordeRecordRole -Record ([pscustomobject]@{ claudeSessionId = "x"; label = "M" }) -Table $table
Check ($labelled.role.state -eq "unknown") "role is never inferred from the label"

# DRIFT: every role wezfleet can store must have an alias, so a fourth wezfleet role cannot arrive
# unmapped. Read from the wezfleet repository's own source when it is checked out beside this one.
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
} else {
    Write-Host "  (inconclusive: no wezfleet checkout found beside this repository - the drift check did not run)" -ForegroundColor Yellow
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
Put (Join-Path $sess "wrong-name.json") @{ claudeSessionId = "someone-else"; role = "master" }
Set-Content -LiteralPath (Join-Path $sess "m1.12345.abcd1234.tmp") -Value '{"claudeSessionId":"m1","role":"master"}'
Put (Join-Path $claimsDir "7.json") @{ role = "master"; claimedAt = "2026-09-29T00:00:00Z" }
Put (Join-Path $claimsDir "8.json") @{ role = "" }
Set-Content -LiteralPath (Join-Path $store "registry\labels\A.claim") -Value "2026-09-29T00:00:00Z"
Put (Join-Path $store "index.json") @{ repos = @() }
Set-Content -LiteralPath (Join-Path $store "delivery.jsonl") -Value "{}"

$keepRoot = $env:WEZFLEET_ROOT
try {
    $env:WEZFLEET_ROOT = $store
    Check ((Get-HordeWezfleetRoot) -eq $store) "the wezfleet store root honours WEZFLEET_ROOT"

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
    Check ($byId.Count -eq 5) ("five records are read (" + (@($byId.Keys | Sort-Object) -join ", ") + ")")
    Check (-not $byId.ContainsKey("m1.12345.abcd1234") -and -not $byId.ContainsKey("wrong-name")) "a temp file beside the records is not read as a record"
    Check ((RoleOf $byId["o2"]) -eq "orc" -and $byId["o2"].retired) "a retired record still reads its role"
    Check ($byId["n1"].role.state -eq "unknown" -and $byId["n1"].field -eq "missing") "and a record with no role reads as unknown, not goblin"
    $c7 = @($read.claims | Where-Object { $_.pane -eq "7" })[0]
    $c8 = @($read.claims | Where-Object { $_.pane -eq "8" })[0]
    Check ((RoleOf $c7) -eq "warchief" -and $c8.field -eq "empty") "a claim role is read through the same alias table"
    $wc = Get-HordeRoleCount -Read $read -Role "warchief"
    Check ($wc.state -eq "known" -and $wc.value -eq 1) "CONTROL: with every record readable, the warchief count is known"
    $oc = Get-HordeRoleCount -Read $read -Role "orc"
    Check ($oc.value -eq 1) "a retired orc is not counted among the live ones"

    # One record that cannot be parsed: the counts become unknown instead of silently shrinking.
    Set-Content -LiteralPath (Join-Path $sess "broken.json") -Value "{ not json"
    $read2 = Read-HordeWezfleetRoles
    Check ((Get-HordeRoleCount -Read $read2 -Role "warchief").state -eq "unknown") "an unreadable record makes the role count unknown"
    Remove-Item -LiteralPath (Join-Path $sess "broken.json") -Force
}
finally {
    $env:WEZFLEET_ROOT = $keepRoot
    if ((Split-Path -Leaf $store) -match '^horde-roles-store-[0-9a-f]{32}$') { Remove-Item -LiteralPath $store -Recurse -Force -ErrorAction SilentlyContinue }
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
