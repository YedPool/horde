# DOES EVERY FIELD OF A SESSION HAVE EXACTLY ONE OWNER AND ONE WAY TO BE READ?
#
# Step 0.6's gate. The table is core\ownership.json; the lessons behind each rule are in
# planning/ledger/core-ownership.md.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "core\Ownership.ps1")

$fails = @()
# A condition must be exactly true or false; anything else fails loudly (see test-isolation.ps1).
function Check { param($Cond, [string]$What)
    if ($Cond -isnot [bool]) { Write-Host "  [FAIL] $What (the check's condition was not true or false)" -ForegroundColor Red; $script:fails += $What; return }
    if ($Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }

$doc = Get-HordeOwnership
$findings = @(Test-HordeOwnership -Doc $doc)
foreach ($x in $findings) { Write-Host ("  finding: " + $x) -ForegroundColor Red }

Write-Host ""
Write-Host "--- the table holds ---" -ForegroundColor Cyan

Check ($findings.Count -eq 0) "every field has exactly one owner and one read rule"
Check (@($doc.fields).Count -ge 20) ("CONTROL: the table really was read (" + @($doc.fields).Count + " fields)")

$pane = Get-HordeOwnershipField -Doc $doc -Name "pane"
$paneStores = @($pane.read | ForEach-Object { "$($_.store)" } | Where-Object { $_ -like "W*" } | Sort-Object -Unique)
Check ($null -ne $pane -and $paneStores.Count -ge 3) "pane, stored three times in wezfleet, has one read order across all of them"
Check ($pane.owner -eq "host" -and "$($pane.derived)" -like "*never identity*") "pane is owned by the host and is never identity"
Check ((Get-HordeOwnershipField -Doc $doc -Name "transcriptPath").derived -like "*sessionId*") "the transcript path is derived, never trusted as stored"
Check ((Get-HordeOwnershipField -Doc $doc -Name "owner").derived -like "*never an edge*") "owner is a derived display name; parent is the edge"
Check ("$((Get-HordeOwnershipField -Doc $doc -Name 'resumeCommand').provisional)" -ne "") "a rule that depends on something unmeasured is marked provisional"
$role = Get-HordeOwnershipField -Doc $doc -Name "role"
Check ($role.owner -eq "engine" -and "$($role.read[0].store)" -eq "W1") "role is owned by horde's engine and read from the registry first"

Write-Host ""
Write-Host "--- the gate refuses every way the table can be wrong ---" -ForegroundColor Cyan

function Mutated { param([scriptblock]$Change)
    $copy = (Get-Content -LiteralPath (Join-Path $root "core\ownership.json") -Raw) | ConvertFrom-Json
    & $Change $copy
    return @(Test-HordeOwnership -Doc $copy) }
function Says { param($Found, [string]$Like) return (@($Found | Where-Object { $_ -like ("*" + $Like + "*") }).Count -gt 0) }

Check (Says (Mutated { param($d) $d.fields[0].owner = @("agent", "engine") }) "more than one owner") "a field with two owners is refused"
Check (Says (Mutated { param($d) $d.fields[0].owner = "" }) "has no owner") "a field with no owner is refused"
Check (Says (Mutated { param($d) $d.fields[0].owner = "someone" }) "not one of the listed owners") "a field owned by something that is not an owner is refused"
Check (Says (Mutated { param($d) $d.fields[0].read = @() }) "has no read rule") "a field with no read rule is refused"
Check (Says (Mutated { param($d) $d.fields[0].read[0].store = "Z9" }) "not in the store list") "a read from a store that does not exist is refused"
Check (Says (Mutated { param($d) $d.fields[0].read[0].field = "" }) "without naming what it reads") "a read that does not say what it reads is refused"
Check (Says (Mutated { param($d) $d.fields += $d.fields[0] }) "listed twice") "a field listed twice is refused"
Check (Says (Mutated { param($d) $d.fields[0] | Add-Member -NotePropertyName owners -NotePropertyValue "x" }) "unknown key") "a misspelled key is refused rather than ignored"
Check (Says (Mutated { param($d) $d.stores | Add-Member -NotePropertyName W99 -NotePropertyValue ([pscustomobject]@{ what = "x" }) }) "no field reads it") "a store no field reads is refused"
Check (Says (Mutated { param($d) $d.fields[0] | Add-Member -NotePropertyName provisional -NotePropertyValue " " -Force }) "but not how or why") "provisional without a reason is refused"

Write-Host ""
if ($fails.Count) {
    Write-Host "==== $($fails.Count) FAILURE(S) ====" -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "==== every field has one owner and one way to be read ====" -ForegroundColor Green
exit 0
