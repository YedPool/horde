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

$rawText = Get-Content -LiteralPath (Join-Path $root "core\ownership.json") -Raw
$doc = Get-HordeOwnership
# The raw text as well as the parsed table: a repeated key is visible only in the text, because
# ConvertFrom-Json keeps one of the two values and says nothing.
$findings = @(try { Test-HordeOwnership -Doc $doc -Text $rawText } catch { "THE GATE THREW: " + $_.Exception.Message })
foreach ($x in $findings) { Write-Host ("  finding: " + $x) -ForegroundColor Red }

Write-Host ""
Write-Host "--- the table holds ---" -ForegroundColor Cyan

Check ($findings.Count -eq 0) "every field has exactly one owner and one read rule"
Check (@($doc.fields).Count -ge 20) ("CONTROL: the table really was read (" + @($doc.fields).Count + " fields)")

$pane = Get-HordeOwnershipField -Doc $doc -Name "pane"
# THE ORDER, not only the membership. wezfleet reads roster, then status, then registry, each
# overriding the last (lib/Protocol.ps1:522-537), so the registry comes first and the roster, a
# spawn-time snapshot that made moved sessions unreachable, comes last. A count alone passed the
# roster-first order that was the regression.
$paneOrder = @($pane.read | ForEach-Object { "$($_.store)" })
$w1 = [array]::IndexOf($paneOrder, "W1"); $w5 = [array]::IndexOf($paneOrder, "W5"); $w4 = [array]::IndexOf($paneOrder, "W4")
Write-Host ("  pane is read from: " + ($paneOrder -join ", ")) -ForegroundColor DarkGray
Check ($null -ne $pane -and $w1 -ge 0 -and $w1 -lt $w5 -and $w5 -lt $w4) "pane, stored three times in wezfleet, has one read order across all of them"
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
# A mutation of the RAW TEXT, for what the parsed table cannot show. A replacement that matched
# nothing would test the unchanged file, so it comes back as a finding of its own that no Says
# matches. A gate that throws is reported the same way, never skipped.
function MutatedText { param([string]$Find, [string]$Replace)
    $i = $rawText.IndexOf($Find, [System.StringComparison]::Ordinal)
    if ($i -lt 0) { return @("THE MUTATION DID NOT APPLY: " + $Find) }
    $t = $rawText.Substring(0, $i) + $Replace + $rawText.Substring($i + $Find.Length)
    try { return @(Test-HordeOwnership -Text $t) } catch { return @("THE GATE THREW: " + $_.Exception.Message) } }

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
Check (Says (MutatedText '"owner": "agent",' '"owner": "agent", "owner": "engine",') "appears more than once") "a field with a repeated owner key is refused"
Check (Says (MutatedText '{ "store": "X2", "field": "sessionId" }' '{ "store": "X2", "store": "W1", "field": "sessionId" }') "appears more than once") "a read entry with a repeated key is refused"
Check (Says (MutatedText '"owner": "agent",' '"owner": "agent", "Owner": "engine",') "appears more than once") "a key repeated in another case is refused, not thrown"
Check (Says (Mutated { param($d) $d.fields[0].read[0] | Add-Member -NotePropertyName wehn -NotePropertyValue "x" }) "unknown key 'wehn'") "a misspelled key in a read entry is refused"
Check (Says (Mutated { param($d) $d.fields[0].read[0] | Add-Member -NotePropertyName when -NotePropertyValue " " -Force }) "an empty condition") "a read with an empty condition is refused"
Check (Says (Mutated { param($d) $d.fields[0].read[0] | Add-Member -NotePropertyName when -NotePropertyValue $false -Force }) "an empty condition") "a read whose condition is not text is refused"
Check (Says (Mutated { param($d) $d.fields[0].read = @($d.fields[0].read) + @($d.fields[0].read[0]) }) "twice") "a read of one store and field twice in one rule is refused"
Check (Says (Mutated { param($d) $d.fields[0].owner = "Agent" }) "not one of the listed owners") "an owner named in the wrong case is refused"
Check (Says (Mutated { param($d) $d.fields[0].read[0].store = "x2" }) "not in the store list") "a store named in the wrong case is refused"
$oneOwnerList = @(Mutated { param($d) $d.fields[0].owner = @("agent") })
Check ((Says $oneOwnerList "as a list") -and -not (Says $oneOwnerList "more than one owner")) "an owner given as a one-item list is refused for what it is"
Check (Says (Mutated { param($d) $d.fields[0] | Add-Member -NotePropertyName derived -NotePropertyValue $false -Force }) "but not how or why") "derived given as false is refused"
Check (Says (Mutated { param($d) $d.fields[0] | Add-Member -NotePropertyName derived -NotePropertyValue 0 -Force }) "but not how or why") "derived given as a number is refused"
Check (Says (Mutated { param($d) $d.fields[0] | Add-Member -NotePropertyName provisional -NotePropertyValue $false -Force }) "but not how or why") "provisional given as false is refused"
$aDroppedField = { param($d, $reason)
    $d.fields = @($d.fields | Where-Object { $_.name -cne "origin" })
    $d | Add-Member -NotePropertyName dropped -NotePropertyValue @([pscustomobject]@{ name = "origin"; reason = $reason }) -Force }
Check (Says (Mutated { param($d) $d.fields = @() }) "is missing") "an empty table is refused"
Check (Says (Mutated { param($d) $d.fields = @($d.fields | Where-Object { $_.name -cne "pane" }) }) "'pane' is missing") "a deleted field is refused"
Check (Says (Mutated { param($d) $d.fields += [pscustomobject]@{ name = "extra"; owner = "engine"; read = @([pscustomobject]@{ store = "W1"; field = "extra" }) } }) "not in the required list") "a field the required list does not name is refused"
Check (Says (Mutated { param($d) $d.PSObject.Properties.Remove("required") }) "needs a required list") "a table with no required list is refused"
Check (Says (Mutated { param($d) & $aDroppedField $d "" }) "dropped without a reason") "a dropped field with no reason is refused"
Check (Says (Mutated { param($d) & $aDroppedField $d $false }) "dropped without a reason") "a dropped field whose reason is not text is refused"
Check (Says (Mutated { param($d) $d | Add-Member -NotePropertyName dropped -NotePropertyValue @([pscustomobject]@{ name = "pane"; reason = "a reason of several words" }) -Force }) "both kept and dropped") "a field both kept and dropped is refused"
Check (Says (Mutated { param($d) $d | Add-Member -NotePropertyName dropped -NotePropertyValue @([pscustomobject]@{ name = "origin"; reasn = "x" }) -Force }) "unknown key") "a misspelled key in a dropped entry is refused"
$droppedControl = @(Mutated { param($d) & $aDroppedField $d "a reason of several words" })
Check ($droppedControl.Count -eq 0) ("CONTROL: a field dropped with a reason is accounted for (" + $droppedControl.Count + " findings)")
$dupControl = @(try { Find-HordeJsonDuplicateKey -Text $rawText } catch { "THE SCAN THREW: " + $_.Exception.Message })
$storeKeys = ([regex]::Matches($rawText, '"store"')).Count
Check ($dupControl.Count -eq 0 -and $storeKeys -ge 20) ("CONTROL: one key in many objects is not a repeat (" + $storeKeys + " store keys, " + $dupControl.Count + " repeats)")

Write-Host ""
if ($fails.Count) {
    Write-Host "==== $($fails.Count) FAILURE(S) ====" -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "==== every field has one owner and one way to be read ====" -ForegroundColor Green
exit 0
