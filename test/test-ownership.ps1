# DOES EVERY FIELD OF A SESSION HAVE EXACTLY ONE OWNER AND ONE WAY TO BE READ?
#
# Step 0.6's gate. The table is core\ownership.json; the lessons behind each rule are in
# planning/ledger/core-ownership.md.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\Ownership.ps1")

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
# ONE FRESHNESS RULE FOR THE REGISTRY'S PANE, and it is census's. wezfleet has two: 900 seconds of
# lastSeen (lib/Registry.ps1:537, :779) and the instance rule with no age (census through
# Get-WfPaneIndex, :393-394, and the act-on finder, :658-659). Horde shadows census, so it reads by
# census's rule and a comparison against it is predictable.
# The 900 is matched on its own: "900 seconds old" appeared nowhere, so the check could not fail,
# while "the 900-second limit" was in the rule (second review, finding 9). The rule names the limit
# it does not adopt without its number; the number is in ledger L-025.
$paneW1 = @($pane.read | Where-Object { "$($_.store)" -ceq "W1" })[0]
Check ("$($paneW1.when)" -like "*written in this terminal instance*" -and "$($paneW1.when)" -like "*no age limit*" -and "$($paneW1.when)" -notlike "*900*") "the registry's pane is read by census's rule, with no age limit"
Check ("$($pane.provisional)" -like "*no single wezfleet function*") "the order of the pane-sessions file before the status snapshot is marked as a new decision"
# X1 IS GUARDED ON THE STORE, so no read of it can be bare. It was guarded for sessionId and pane
# and read bare for projectCwd, transcriptPath and name (review finding 6). The guard says AT MOST
# one wezterm-gui, because Read-WfPaneSessionFile refuses only more than one (lib/Registry.ps1:247,
# guiCount -gt 1); with none running there is no pane to misattribute. The "only live file naming
# the session" rule is the act-on finder's (:672), not census's, which reads each live pane's file
# on its own (:839-848); the guard adopts the stricter rule and must say whose it is.
$x1Guard = "$($doc.stores.X1.guard)"
Check ($x1Guard -like "*after this terminal instance started*" -and $x1Guard -like "*at most one wezterm-gui*" -and $x1Guard -like "*hijack*") "every read of the pane-sessions file carries one guard"
Check ($x1Guard -like "*finder that picks a pane to act on*" -and $x1Guard -like "*census*") "the pane-sessions guard says whose rule the one-live-file check is"
# W2 LIKEWISE: the claim reader's TTL and cwd checks, and the hook's "only for a session with no
# record", on every read of a claim (review finding 7). The claim carries owner, so owner reads it.
$w2Guard = "$($doc.stores.W2.guard)"
$ownerStores = @((Get-HordeOwnershipField -Doc $doc -Name "owner").read | ForEach-Object { "$($_.store)" })
Check ($w2Guard -like "*10080 minutes*" -and $w2Guard -like "*cwd*" -and $w2Guard -like "*no registry record*") "every read of a spawn claim carries the claim reader's full guard"
# "MATCHES" MEANS WHAT READ-WFPANECLAIM COMPARES: both directories reduced to Claude's path key and
# compared ignoring case (lib/Registry.ps1:1305, ConvertTo-WfClaudePathKey and -ine). An exact
# string match would refuse claims wezfleet accepts.
Check ($w2Guard -like "*by Claude path key, ignoring case*") "a spawn claim's cwd is matched the way the claim reader matches it"
Check ($ownerStores -ccontains "W2") "owner, which a spawn claim carries, reads the claim"
# THE CLAIM'S FLEET ID, right after the registry. The hook takes it from the claim when the
# environment has none (hooks/wf-registry-refresh.ps1:153), and it decides the record's origin
# (lib/Registry.ps1:322), so a table that skipped it would call a fleet session the user's.
$fleetStores = @((Get-HordeOwnershipField -Doc $doc -Name "fleetSessionId").read | ForEach-Object { "$($_.store)" })
Check ($fleetStores.Count -ge 2 -and $fleetStores[0] -ceq "W1" -and $fleetStores[1] -ceq "W2") "the fleet id a spawn claim carries is read right after the registry"
# THE FIELDS THE FIRST DRAFT MISSED (review finding 8), each found in a real store: every one must
# be named in the required list, so the gate holds it to kept-or-dropped.
$missedOnce = @("lastSeen", "runId", "labelCycle", "nameSource", "remoteControl", "retiredAt", "lastTool",
                "title", "dependsOn", "spawnedAt", "procStart", "bridgeSessionId", "formerNames")
$notRequired = @($missedOnce | Where-Object { @($doc.required) -cnotcontains $_ })
foreach ($x in $notRequired) { Write-Host ("  not in the required list: " + $x) -ForegroundColor Red }
Check ($notRequired.Count -eq 0) "every field the old stores hold is kept or dropped"
# EVERY KEY A CLAUDE CONTROL FILE HOLDS IS KEPT OR DROPPED, not only the ones a reader happened to
# want. The census of ~/.claude/sessions on 2026-09-30 found these 20 keys across 10 files - 19 in
# nine of them, bridgeSessionId missing from one, formerNames in one - and eight had no row at all
# (ledger L-048). A key is kept when some field reads it from X2, and dropped when a dropped entry
# names it; a key the agent writes is the agent's, so a kept one is owned by the agent.
# waitingFor is the 21st: Claude Code writes it only while a session waits on the user, so the
# census, which found every session idle, never saw it. On 2026-09-30 it was in 1 of 10 files, the
# one whose status was waiting, as "permission prompt" (ledger L-055).
$controlKeys = @("pid", "sessionId", "cwd", "startedAt", "procStart", "version", "peerProtocol", "peerFeatures", "kind",
                 "entrypoint", "pidDomain", "messagingSocketPath", "name", "nameSource", "nameSince", "updatedAt", "status",
                 "statusUpdatedAt", "bridgeSessionId", "formerNames", "waitingFor")
$x2Reads = @($doc.fields | ForEach-Object { $ownField = $_; @($ownField.read) | Where-Object { "$($_.store)" -ceq "X2" } | ForEach-Object { [pscustomobject]@{ key = "$($_.field)"; owner = "$($ownField.owner)"; name = "$($ownField.name)" } } })
$droppedNames = @($doc.dropped | Where-Object { $null -ne $_ } | ForEach-Object { "$($_.name)" })
$unaccounted = @($controlKeys | Where-Object { @($x2Reads | ForEach-Object { $_.key }) -cnotcontains $_ -and $droppedNames -cnotcontains $_ })
foreach ($x in $unaccounted) { Write-Host ("  control file key with no row: " + $x) -ForegroundColor Red }
Check ($controlKeys.Count -eq 21 -and $x2Reads.Count -ge 10) ("CONTROL: the census key list and the table's control-file reads were both found (" + $x2Reads.Count + " reads)")
Check ($unaccounted.Count -eq 0) "every claude control file key is kept or dropped"
# Two exceptions, and neither is a copy. updatedAt: lastActivity, the engine's derived "newest sign
# of life", takes it as one of its inputs. cwd, read by projectCwd: the launch directory is a fact
# the engine must still hold after the session exits and Claude removes its control file - a
# stopped session's transcript and resume need it - so the engine owns it and reads it from the
# control file while the session runs (ledger L-054). schema/session-record.v1 stores it for that
# reason: "fixed at start and never revised".
$notAgent = @($x2Reads | Where-Object { $_.owner -cne "agent" -and $_.key -cne "updatedAt" -and -not ($_.key -ceq "cwd" -and $_.name -ceq "projectCwd") } | ForEach-Object { $_.name })
Check ($notAgent.Count -eq 0) ("a field kept from the claude control file is owned by the agent (" + ($notAgent -join ", ") + ")")
$resumeStores = @((Get-HordeOwnershipField -Doc $doc -Name "resumeCommand").read | ForEach-Object { "$($_.store)" })
Check ($resumeStores -ccontains "W5") "the stored copy of the resume command is read for comparison"
$cwdW1 = @((Get-HordeOwnershipField -Doc $doc -Name "cwd").read | Where-Object { "$($_.store)" -ceq "W1" })[0]
Check ("$($cwdW1.when)" -like "*lastSeen*" -and "$($cwdW1.when)" -like "*instance started*") "the registry's cwd says what fresh means and what it is measured against"
# ONE DEFINITION OF "WRITTEN IN THIS TERMINAL INSTANCE", word for word in every read that uses it.
# The pane's read required the record to name this instance and the cwd's did not; wezfleet has
# one rule for both (lib/Common.ps1:628): a record that names an instance must name this one, a
# record that names none passes on lastSeen alone.
$inInstance = "written in this terminal instance: the record's instance matches this one when the record names one, and its lastSeen, the time the hook last saw a tool call, is not before the instance started"
Check ("$($cwdW1.when)".Contains($inInstance) -and "$($paneW1.when)".Contains($inInstance)) "the registry's cwd and pane use one definition of written in this instance"
$hostInstance = Get-HordeOwnershipField -Doc $doc -Name "hostInstance"
Check ("$($hostInstance.read[0].store)" -ceq "X6" -and "$($hostInstance.read[0].field)" -ceq "WEZTERM_UNIX_SOCKET") "the terminal instance is read from the socket first, which names it exactly"
Check ("$($hostInstance.derived)" -like "*ambiguous*trusts no pane record*") "an ambiguous terminal instance trusts no pane record"
$windowW3 = @((Get-HordeOwnershipField -Doc $doc -Name "window").read | Where-Object { "$($_.store)" -ceq "W3" })[0]
Check ("$($windowW3.when)" -like "*run-level*") "the run's window is marked as the run's, a fallback for the session"
Check ($pane.owner -eq "host" -and "$($pane.derived)" -like "*never identity*") "pane is owned by the host and is never identity"
Check ((Get-HordeOwnershipField -Doc $doc -Name "transcriptPath").derived -like "*sessionId*") "the transcript path is derived, never trusted as stored"
# THE PROJECT DIRECTORY IS THE LAUNCH DIRECTORY, and while the session runs its own control file
# holds it. The pane-sessions file's cwd is what the hook saw at that moment - the CURRENT
# directory - and was read second: census of 2026-09-30, 163 pane-sessions files, 1 (23.json,
# written at a compaction) whose cwd was not the folder its own transcript_path names, and 265
# transcripts, 210 with a cwd, 21 that changed directory, every one under the folder of its FIRST
# cwd (ledger L-050). So the control file is read first, and the hook's cwd only when the folder
# of the transcript it names in the same file says it is the launch directory.
$projectCwd = Get-HordeOwnershipField -Doc $doc -Name "projectCwd"
Check ("$($projectCwd.owner)" -ceq "engine") "the project directory stays the engine's, because it must outlive the control file"
$pcFirst = @($projectCwd.read)[0]
Check ("$($pcFirst.store)" -ceq "X2" -and "$($pcFirst.field)" -ceq "cwd" -and "$($pcFirst.when)" -like "*running*") "the project directory is read first from the running session's control file"
$pcX1 = @($projectCwd.read | Where-Object { "$($_.store)" -ceq "X1" })
Check (@($pcX1 | Where-Object { "$($_.when)" -notlike "*transcript_path*" }).Count -eq 0) "the hook's cwd is never the project directory unless its transcript folder agrees"
$cwdX2 = @((Get-HordeOwnershipField -Doc $doc -Name "cwd").read | Where-Object { "$($_.store)" -ceq "X2" })[0]
Check ("$($cwdX2.when)" -like "*launch directory*" -and "$($cwdX2.when)" -like "*not the current directory*") "the control file's cwd is labelled as the launch directory"
# A SESSION THAT IS NOT RUNNING HAS NO CONTROL FILE, and the fallback was projectCwd - whose other
# sources can hold the current directory (L-050). The fallback is now the one file named for the
# session id in any project folder, taken only when there is exactly one: on 2026-09-30 one test
# session id had a transcript in 55 folders (ledger L-052).
$tpDerived = "$((Get-HordeOwnershipField -Doc $doc -Name 'transcriptPath').derived)"
Check ($tpDerived -notlike "*from projectCwd*" -and $tpDerived -like "*exactly one*") "a stopped session's transcript is the one file named for its id, never projectCwd's folder"
# THE FOLDER KEY IS MEASURED ONLY ON SHORT PATHS: the longest of 149 project folders is 137
# characters. A tool may shorten a long key and add a hash; that is unverified, so the rule is
# provisional and says why it still fails safe (ledger L-053).
$tpProvisional = "$((Get-HordeOwnershipField -Doc $doc -Name 'transcriptPath').provisional)"
Check ($tpProvisional -like "*137 characters*" -and $tpProvisional -like "*checked to exist*") "the transcript folder key is provisional beyond the longest path measured"
# WHAT THE CONTROL FILE'S ENTRYPOINT SAYS FOR A NESTED SESSION IS UNMEASURED. wezfleet measured
# the environment variable of that name (sdk-cli for a nested claude -p), not this key, which has
# been seen only as cli (ledger L-048).
Check ("$((Get-HordeOwnershipField -Doc $doc -Name 'entrypoint').provisional)" -like "*environment variable*") "the entrypoint's meaning for a nested session is marked unmeasured"
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
# AN OWNER SAYS WHAT IT IS. An empty description passed, so an owner could be listed that nothing
# explains (second review, finding 5).
Check (Says (Mutated { param($d) $d.owners.agent = " " }) "owner 'agent' has no description") "an owner with an empty description is refused"
Check (Says (Mutated { param($d) $d.owners.agent = $true }) "owner 'agent' has no description") "an owner whose description is not text is refused"
Check (Says (Mutated { param($d) $d.fields[0].read = @() }) "has no read rule") "a field with no read rule is refused"
Check (Says (Mutated { param($d) $d.fields[0].read[0].store = "Z9" }) "not in the store list") "a read from a store that does not exist is refused"
Check (Says (Mutated { param($d) $d.fields[0].read[0].field = "" }) "without naming what it reads") "a read that does not say what it reads is refused"
Check (Says (Mutated { param($d) $d.fields += $d.fields[0] }) "listed twice") "a field listed twice is refused"
# FIELD NAMES ARE MATCHED EXACTLY, like owners and stores, and two names differing only in case are
# refused for what they are: one property to PowerShell, two to an exact comparison. The gate had
# found them with a case-insensitive table and called them "listed twice" (second review, finding 9).
$caseTwin = @(Mutated { param($d) $d.fields += [pscustomobject]@{ name = "SessionId"; owner = "agent"; read = $d.fields[0].read } })
Check ((Says $caseTwin "differ only in case") -and -not (Says $caseTwin "listed twice")) "two field names differing only in case are refused for what they are"
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
# A READ ENTRY IS AN OBJECT NAMING ITS FIELD AS TEXT. 5 and true stringify to "5" and "True" and
# passed as field names; a null entry was filtered out before any check saw it; and one store read
# as sessionId and SessionId passed as two reads, though PowerShell reads both as one property
# (second review, finding 5).
Check (Says (Mutated { param($d) $d.fields[0].read[0].field = 5 }) "without naming what it reads") "a read whose field is a number is refused"
Check (Says (Mutated { param($d) $d.fields[0].read[0].field = $true }) "without naming what it reads") "a read whose field is true or false is refused"
Check (Says (Mutated { param($d) $d.fields[0].read = @($d.fields[0].read) + @($null) }) "an empty read entry") "a null inside a read rule is refused, not dropped"
Check (Says (Mutated { param($d) $d.fields[0].read = @($d.fields[0].read) + @([pscustomobject]@{ store = "X2"; field = "SessionId" }) }) "twice") "a store read twice under names differing only in case is refused"
Check (Says (Mutated { param($d) $d.fields[0].owner = "Agent" }) "not one of the listed owners") "an owner named in the wrong case is refused"
Check (Says (Mutated { param($d) $d.fields[0].read[0].store = "x2" }) "not in the store list") "a store named in the wrong case is refused"
$oneOwnerList = @(Mutated { param($d) $d.fields[0].owner = @("agent") })
Check ((Says $oneOwnerList "as a list") -and -not (Says $oneOwnerList "more than one owner")) "an owner given as a one-item list is refused for what it is"
Check (Says (Mutated { param($d) $d.fields[0] | Add-Member -NotePropertyName derived -NotePropertyValue $false -Force }) "but not how or why") "derived given as false is refused"
Check (Says (Mutated { param($d) $d.fields[0] | Add-Member -NotePropertyName derived -NotePropertyValue 0 -Force }) "but not how or why") "derived given as a number is refused"
Check (Says (Mutated { param($d) $d.fields[0] | Add-Member -NotePropertyName provisional -NotePropertyValue $false -Force }) "but not how or why") "provisional given as false is refused"
Check (Says (Mutated { param($d) $d.stores.X1 | Add-Member -NotePropertyName gaurd -NotePropertyValue "x" -Force }) "store 'X1' has an unknown key 'gaurd'") "a misspelled key in a store is refused, so a guard cannot vanish"
Check (Says (Mutated { param($d) $d.stores.X1 | Add-Member -NotePropertyName guard -NotePropertyValue " " -Force }) "store 'X1' has an empty guard") "a store guard that says nothing is refused"
Check (Says (Mutated { param($d) $d.stores.X1 | Add-Member -NotePropertyName guard -NotePropertyValue $true -Force }) "store 'X1' has an empty guard") "a store guard that is not text is refused"
# A STORE SAYS WHICH SYSTEM KEEPS IT, WHAT IT IS AND WHERE IT LIVES. {} passed as a store, so a
# field could read from a store no reader could find (second review, finding 5).
Check (Says (Mutated { param($d) $d.stores.X4 = [pscustomobject]@{} }) "store 'X4' needs system, what and path") "a store that says nothing about itself is refused"
Check (Says (Mutated { param($d) $d.stores.X4.path = 7 }) "store 'X4' needs system, what and path") "a store whose path is not text is refused"
$aDroppedField = { param($d, $reason)
    $d.fields = @($d.fields | Where-Object { $_.name -cne "origin" })
    $d | Add-Member -NotePropertyName dropped -NotePropertyValue (@($d.dropped | Where-Object { $null -ne $_ }) + @([pscustomobject]@{ name = "origin"; reason = $reason })) -Force }
Check (Says (Mutated { param($d) $d.fields = @() }) "is missing") "an empty table is refused"
Check (Says (Mutated { param($d) $d.fields = @($d.fields | Where-Object { $_.name -cne "pane" }) }) "'pane' is missing") "a deleted field is refused"
Check (Says (Mutated { param($d) $d.fields += [pscustomobject]@{ name = "extra"; owner = "engine"; read = @([pscustomobject]@{ store = "W1"; field = "extra" }) } }) "not in the required list") "a field the required list does not name is refused"
Check (Says (Mutated { param($d) $d.PSObject.Properties.Remove("required") }) "needs a required list") "a table with no required list is refused"
# THE TOP LEVEL HAS A FIXED SET OF KEYS. A misspelled "requird" beside a real "required" would be
# ignored, and a misspelled "dropped" would hide every dropped field's reason. And an id is either
# a store or a gap in the numbering, never both (second review, finding 6).
Check (Says (Mutated { param($d) $d | Add-Member -NotePropertyName droped -NotePropertyValue @() }) "unknown top-level key 'droped'") "a misspelled top-level key is refused"
Check (Says (Mutated { param($d) $d.storeIdGaps | Add-Member -NotePropertyName W1 -NotePropertyValue "a gap that is also a store" }) "'W1' is both a store and a gap") "a store id also listed as a gap is refused"
Check (Says (Mutated { param($d) & $aDroppedField $d "" }) "dropped without a reason") "a dropped field with no reason is refused"
Check (Says (Mutated { param($d) & $aDroppedField $d $false }) "dropped without a reason") "a dropped field whose reason is not text is refused"
Check (Says (Mutated { param($d) $d | Add-Member -NotePropertyName dropped -NotePropertyValue @([pscustomobject]@{ name = "pane"; reason = "a reason of several words" }) -Force }) "both kept and dropped") "a field both kept and dropped is refused"
Check (Says (Mutated { param($d) $d | Add-Member -NotePropertyName dropped -NotePropertyValue @([pscustomobject]@{ name = "origin"; reasn = "x" }) -Force }) "unknown key") "a misspelled key in a dropped entry is refused"
$droppedControl = @(Mutated { param($d) & $aDroppedField $d "a reason of several words" })
Check ($droppedControl.Count -eq 0) ("CONTROL: a field dropped with a reason is accounted for (" + $droppedControl.Count + " findings)")
$dupControl = @(try { Find-HordeJsonDuplicateKey -Text $rawText } catch { "THE SCAN THREW: " + $_.Exception.Message })
$storeKeys = ([regex]::Matches($rawText, '"store"')).Count
Check ($dupControl.Count -eq 0 -and $storeKeys -ge 20) ("CONTROL: one key in many objects is not a repeat (" + $storeKeys + " store keys, " + $dupControl.Count + " repeats)")

Complete-HordeSuite -Success "every field has one owner and one way to be read"
