# DOES THE REQUEST JOURNAL MAKE "ACT TWICE" IMPOSSIBLE, AND SAY "UNKNOWN" WHEN IT CANNOT KNOW?
#
# Remote plan step R3 (planning/execution-plan-remote.md, PR 32): every act request carries an id, and
# the node records that id before it acts. A resend with the same id and the same arguments gets the
# recorded result and acts nothing; the same id with other arguments is refused; an entry whose
# process stopped between "recorded" and "acted" is UNKNOWN and is never re-executed.
#
# This suite is the single-process half. Racing writers in separate processes, with a control that
# proves the race can catch a double execution, are test/test-journal-race.ps1.
#
# Every journal root here is a fresh folder under %TEMP%, created and removed by this suite (CONTRIBUTING
# 9): nothing reads or writes a real journal.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "remote\Journal.ps1")

$script:tempRoots = New-Object System.Collections.ArrayList
function New-TestRoot {
    # A new, empty folder for one journal, inside a folder of its own: an id that climbs out of the
    # journal ("..\x") then lands in this suite's folder, never loose in %TEMP%, even under a mutant
    # that stops refusing it. -Init makes it a journal; without it, it is just a folder.
    param([switch]$Init)
    $outer = Join-Path $env:TEMP ("horde-journal-test-" + [guid]::NewGuid().ToString("N"))
    $p = Join-Path $outer "j"
    New-Item -ItemType Directory -Path $p | Out-Null
    [void]$script:tempRoots.Add($outer)
    if ($Init) { Initialize-HordeJournal -Root $p -Kind "request" | Out-Null }
    return $p
}
function New-Id { return [guid]::NewGuid().ToString() }
function Names { param([string]$Dir) return @(Get-ChildItem -LiteralPath $Dir -Force | ForEach-Object { $_.Name } | Sort-Object) }
function Bytes { param([string]$Path) return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path)) }
$utcNow = [datetime]::UtcNow
$spawnArgs = @{ label = "g-7"; role = "goblin"; prompt = @{ text = "hello" } }

try {

Write-Host ""
Write-Host "--- argsHash: the same request hashes the same, and any change hashes differently ---" -ForegroundColor Cyan

$t0 = [datetime]::SpecifyKind([datetime]"2026-09-30T12:00:00", [System.DateTimeKind]::Utc)
$h1 = Get-HordeJournalArgsHash -Verb "session.spawn" -Arguments @{ a = 1; b = "x"; c = @(1, 2) } -IssuedAt $t0
$ordered = [ordered]@{}; $ordered["c"] = @(1, 2); $ordered["b"] = "x"; $ordered["a"] = 1
$h2 = Get-HordeJournalArgsHash -Verb "session.spawn" -Arguments $ordered -IssuedAt $t0
$fromJson = '{"c":[1,2],"a":1,"b":"x"}' | ConvertFrom-Json
$h3 = Get-HordeJournalArgsHash -Verb "session.spawn" -Arguments $fromJson -IssuedAt $t0
Check ($h1 -cmatch '^[0-9a-f]{64}$') "the hash is 64 lowercase hex digits (SHA-256)"
Check ($h1 -ceq $h2) "key order does not change the hash (ordered dictionary, keys reversed)"
Check ($h1 -ceq $h3) "a decoded JSON object hashes the same as the hashtable it came from"
Check ($h1 -cne (Get-HordeJournalArgsHash -Verb "session.spawn" -Arguments @{ a = 2; b = "x"; c = @(1, 2) } -IssuedAt $t0)) "a changed value changes the hash"
Check ($h1 -cne (Get-HordeJournalArgsHash -Verb "session.spawn" -Arguments @{ a = 1; b = "x"; c = @(2, 1) } -IssuedAt $t0)) "a reordered list changes the hash: list order is data"
Check ($h1 -cne (Get-HordeJournalArgsHash -Verb "session.resume" -Arguments @{ a = 1; b = "x"; c = @(1, 2) } -IssuedAt $t0)) "another verb changes the hash"
Check ($h1 -cne (Get-HordeJournalArgsHash -Verb "session.spawn" -Arguments @{ a = 1; b = "x"; c = @(1, 2) } -IssuedAt $t0.AddSeconds(1))) "another issue time changes the hash"
Check ((Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ n = 1 } -IssuedAt $t0) -ceq (Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ n = [double]1.0 } -IssuedAt $t0)) "1 and 1.0 hash the same: a number re-encoded on a resend must not look like new arguments"
Check ((Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ n = 1.5 } -IssuedAt $t0) -ceq (Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ n = [decimal]1.5 } -IssuedAt $t0)) "1.5 as a double and as a decimal hash the same"
Check ((ConvertTo-HordeJournalCanonical -Value ([double]1e15)) -ceq "1000000000000000") "a whole double is written as an integer, not as 1E+15"
Check ((Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ n = [long]1000000000000000 } -IssuedAt $t0) -ceq (Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ n = [double]1e15 } -IssuedAt $t0)) "so 10^15 as a long and as a double hash the same"
Check ((Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ n = 1 } -IssuedAt $t0) -ceq (Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ n = [decimal]"1.0" } -IssuedAt $t0)) "1 and a decimal 1.0 (which keeps its scale when printed) hash the same"
# A DECIMAL'S SCALE IS NOT ITS VALUE. [decimal]"1.10" prints as 1.10 and [decimal]"1.1" as 1.1; both are
# the number 1.1, and so is the double 1.1. Hashed by their printed text they differed (review of PR #39).
$h110 = Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ n = [decimal]"1.10" } -IssuedAt $t0
Check ($h110 -ceq (Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ n = [decimal]"1.1" } -IssuedAt $t0)) "a decimal 1.10 and a decimal 1.1 hash the same"
Check ($h110 -ceq (Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ n = [double]1.1 } -IssuedAt $t0)) "and the same as the double 1.1"
Check ((ConvertTo-HordeJournalCanonical -Value ([decimal]"-2.500")) -ceq "-2.5") "a negative decimal loses its trailing zeros too"
Check ((ConvertTo-HordeJournalCanonical -Value ([decimal]"10.0")) -ceq "10") "and a whole one is an integer"
$uEsc = '\' + 'u00e9'
Check ((ConvertTo-HordeJournalCanonical -Value ([string][char]0xE9)) -ceq ('"' + $uEsc + '"')) "a non-ASCII character is written as a backslash-u escape, so the hashed text is ASCII"
Check ((ConvertTo-HordeJournalCanonical -Value $uEsc) -ceq ('"\' + $uEsc + '"')) "the six ASCII characters of that escape are escaped differently from the character they spell"
Check ((Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ s = [string][char]0xE9 } -IssuedAt $t0) -cne (Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ s = $uEsc } -IssuedAt $t0)) "so the two hash differently"
Check ((ConvertTo-HordeJournalCanonical -Value @{ b = 1; a = $null; c = $true }) -ceq '{"a":null,"b":1,"c":true}') "the canonical form sorts keys and writes null and true as JSON"
Check (Throws { Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ when = (Get-Date) } -IssuedAt $t0 } "cannot be hashed") "a value that is not JSON data (a date) is refused, not stringified"
Check (Throws { Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{ n = [double]::NaN } -IssuedAt $t0 } "cannot be hashed") "NaN is refused: JSON has no NaN"
Check (Throws { Get-HordeJournalArgsHash -Verb "v.x" -Arguments @{} -IssuedAt ([datetime]"2026-09-30T12:00:00") } "zone") "an issue time with no zone is refused: it cannot be placed"

Write-Host ""
Write-Host "--- a folder that is not a journal is unknown, never an empty journal ---" -ForegroundColor Cyan

$bare = New-TestRoot
$id = New-Id
$o = Open-HordeJournalEntry -Root $bare -Id $id -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow
Check ($o.decision -ceq "unknown") "Open on a folder with no journal marker does not act (a mistyped or unmounted root must not read as 'never seen')"
Check (@(Names $bare).Count -eq 0) "and it writes nothing there"
$missing = Join-Path $bare "not-there"
$o = Open-HordeJournalEntry -Root $missing -Id $id -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow
Check ($o.decision -ceq "unknown") "Open on a root that does not exist does not act"
Check (-not (Test-Path -LiteralPath $missing)) "and does not create it"
$g = Get-HordeJournalEntry -Root $bare -Id $id
Check ($g.state -ceq "unknown") "request.status on a folder with no marker is unknown, not absent"
Initialize-HordeJournal -Root $bare -Kind "request" | Out-Null
$o = Open-HordeJournalEntry -Root $bare -Id $id -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow
Check ($o.decision -ceq "act") "control: once the folder is initialised, the same request acts"
Check (Throws { Initialize-HordeJournal -Root (New-TestRoot) -Kind "request" -RetentionDays 7 -AdmitDays 7 } "retention") "a journal whose admission window reaches its retention is refused at creation"
Check (Throws { Initialize-HordeJournal -Root (New-TestRoot) -Kind "request" -RetentionDays 8 -AdmitDays 7 -MaxFutureMinutes 1440 } "retention") "the future allowance counts against retention too"
Check (-not (Throws { Initialize-HordeJournal -Root $bare -Kind "request" })) "initialising an existing journal with the same settings is allowed"
Check (Throws { Initialize-HordeJournal -Root $bare -Kind "request" -RetentionDays 60 } "settings") "re-initialising with other settings is refused: the windows are fixed at creation"
Check (Throws { Initialize-HordeJournal -Root $bare -Kind "message" } "settings") "and so is another kind"

Write-Host ""
Write-Host "--- the first request acts; a resend replays the recorded result and acts nothing ---" -ForegroundColor Cyan

$j = New-TestRoot -Init
$id = New-Id
$first = Open-HordeJournalEntry -Root $j -Id $id -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow
Check ($first.decision -ceq "act") "a new id acts"
Check (Test-Path -LiteralPath (Join-Path $j ($id + ".json"))) "and its record is on disk before the caller acts"
$half = Open-HordeJournalEntry -Root $j -Id $id -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow
Check ($half.decision -ceq "unknown") "a resend while the first attempt has recorded no outcome is unknown, not act"
Check ("$($half.reason)" -like "*not repeated*") "and says the act is not repeated"
Check ($null -ne $half.result -and $half.result.state -ceq "unknown") "its result is a tristate unknown, so it can go on the wire as one"
Complete-HordeJournalEntry -Root $j -Id $id -State "done" -Result (New-HordeKnown -Value @{ sessionId = "s-1" }) | Out-Null
$before = Names $j
$again = Open-HordeJournalEntry -Root $j -Id $id -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow
Check ($again.decision -ceq "replay") "a resend after the outcome is recorded replays"
Check ($again.state -ceq "done") "with the recorded state"
Check ($again.result.state -ceq "known" -and "$((Get-HordeValue $again.result).sessionId)" -ceq "s-1") "and the recorded result, as a tristate answer"
Check ((@(Names $j) -join ",") -ceq (@($before) -join ",")) "and writes no file"
Check (@(Names $j).Count -eq 3) "the journal holds the marker, the record and the outcome, nothing else"
$replay2 = Open-HordeJournalEntry -Root $j -Id $id -Verb "session.spawn" -Arguments ('{"role":"goblin","prompt":{"text":"hello"},"label":"g-7"}' | ConvertFrom-Json) -IssuedAt $utcNow
Check ($replay2.decision -ceq "replay") "the same arguments decoded from JSON in another key order replay too"

Write-Host ""
Write-Host "--- the same id with other arguments is refused, and changes nothing ---" -ForegroundColor Cyan

$recPath = Join-Path $j ($id + ".json")
$recBytes = Bytes $recPath
$reuse = Open-HordeJournalEntry -Root $j -Id $id -Verb "session.spawn" -Arguments @{ label = "g-8"; role = "goblin"; prompt = @{ text = "hello" } } -IssuedAt $utcNow
Check ($reuse.decision -ceq "refuse") "the same id with another argument is refused"
Check ("$($reuse.reason)" -like "*reused*") "as a reused id"
Check ((Bytes $recPath) -ceq $recBytes) "and the record is unchanged"
$reuseVerb = Open-HordeJournalEntry -Root $j -Id $id -Verb "session.resume" -Arguments $spawnArgs -IssuedAt $utcNow
Check ($reuseVerb.decision -ceq "refuse") "the same id with another verb is refused"
$reuseTime = Open-HordeJournalEntry -Root $j -Id $id -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow.AddMinutes(-1)
Check ($reuseTime.decision -ceq "refuse") "the same id with another issue time is refused: a resend carries the time it was first issued"
$hid = New-Id
$null = Open-HordeJournalEntry -Root $j -Id $hid -Verb "session.close" -Arguments @{ sessionId = "s-2" } -IssuedAt $utcNow
$reuseHalf = Open-HordeJournalEntry -Root $j -Id $hid -Verb "session.close" -Arguments @{ sessionId = "s-3" } -IssuedAt $utcNow
Check ($reuseHalf.decision -ceq "refuse") "reuse is refused even while the first attempt has no outcome yet"

Write-Host ""
Write-Host "--- every recorded state replays as itself ---" -ForegroundColor Cyan

foreach ($st in @("failed", "refused")) {
    $sid = New-Id
    $null = Open-HordeJournalEntry -Root $j -Id $sid -Verb "worktree.create" -Arguments @{ name = $st } -IssuedAt $utcNow
    Complete-HordeJournalEntry -Root $j -Id $sid -State $st -Result (New-HordeUnknown -Reason ("fixture " + $st)) | Out-Null
    $r = Open-HordeJournalEntry -Root $j -Id $sid -Verb "worktree.create" -Arguments @{ name = $st } -IssuedAt $utcNow
    Check ($r.decision -ceq "replay" -and $r.state -ceq $st) "a '$st' outcome replays as '$st'"
    Check ($r.result.state -ceq "unknown" -and "$($r.result.reason)" -like "*fixture $st*") "with its recorded result and reason"
}
$aid = New-Id
$null = Open-HordeJournalEntry -Root $j -Id $aid -Verb "session.park" -Arguments @{ n = 1 } -IssuedAt $utcNow
Complete-HordeJournalEntry -Root $j -Id $aid -State "done" -Result (New-HordeAbsent -Note "nothing to park") | Out-Null
$ra = Open-HordeJournalEntry -Root $j -Id $aid -Verb "session.park" -Arguments @{ n = 1 } -IssuedAt $utcNow
Check ($ra.result.state -ceq "absent") "an absent result replays as absent"
Check (Throws { Complete-HordeJournalEntry -Root $j -Id $aid -State "done" -Result (New-HordeKnown -Value 1) } "already") "a second outcome for one id is refused: the first one stands"
Check (Throws { Complete-HordeJournalEntry -Root $j -Id (New-Id) -State "done" -Result (New-HordeKnown -Value 1) } "no record") "an outcome for an id never recorded is refused"
$nid = New-Id
$null = Open-HordeJournalEntry -Root $j -Id $nid -Verb "session.park" -Arguments @{ n = 2 } -IssuedAt $utcNow
Check (Throws { Complete-HordeJournalEntry -Root $j -Id $nid -State "done" -Result 5 } "answer") "a result that is not a tristate answer is refused, so no bare value is replayed"
Check (Throws { Complete-HordeJournalEntry -Root $j -Id $nid -State "accepted" -Result (New-HordeKnown -Value 1) } "state") "'accepted' is not an outcome"
Check (-not (Test-Path -LiteralPath (Join-Path $j ($nid + ".outcome.json")))) "and a refused completion writes no outcome file"

Write-Host ""
Write-Host "--- a torn or busy entry is unknown, never re-executed and never overwritten ---" -ForegroundColor Cyan

foreach ($case in @(@{ n = "empty"; text = "" }, @{ n = "cut"; text = '{"v":1,"id":"' })) {
    $tid = New-Id
    $tp = Join-Path $j ($tid + ".json")
    [System.IO.File]::WriteAllText($tp, $case.text)
    $tb = Bytes $tp
    $r = Open-HordeJournalEntry -Root $j -Id $tid -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow
    Check ($r.decision -ceq "unknown") "a record left $($case.n) by a stopped writer is unknown, not act"
    Check ("$($r.reason)" -like "*torn*") "and is called torn"
    Check ((Bytes $tp) -ceq $tb) "and is not overwritten"
    Check ((Get-HordeJournalEntry -Root $j -Id $tid).state -ceq "unknown") "request.status on it is unknown"
}
$oid = New-Id
$null = Open-HordeJournalEntry -Root $j -Id $oid -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow
[System.IO.File]::WriteAllText((Join-Path $j ($oid + ".outcome.json")), '{"v":1,"st')
$r = Open-HordeJournalEntry -Root $j -Id $oid -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow
Check ($r.decision -ceq "unknown" -and "$($r.reason)" -like "*torn*") "a torn outcome is unknown: the act happened and its result was not kept"
$bid = New-Id
$bp = Join-Path $j ($bid + ".json")
$hold = New-Object System.IO.FileStream($bp, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
try {
    $r = Open-HordeJournalEntry -Root $j -Id $bid -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow
    Check ($r.decision -ceq "unknown") "a record another attempt is writing right now is unknown, not act"
    Check ("$($r.reason)" -like "*being recorded*") "and says it is being recorded"
    Check ((Get-HordeJournalEntry -Root $j -Id $bid).state -ceq "unknown") "request.status on it is unknown"
} finally { $hold.Dispose() }

Write-Host ""
Write-Host "--- an id is one lowercase UUID, so it cannot name a path ---" -ForegroundColor Cyan

$before = Names $j
$parentBefore = Names (Split-Path -Parent $j)
foreach ($bad in @("..\x", ((New-Id).ToUpperInvariant()), "", "journal", ((New-Id) + ".outcome"))) {
    $r = Open-HordeJournalEntry -Root $j -Id $bad -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow
    Check ($r.decision -ceq "refuse") "the id '$bad' is refused"
}
Check ((@(Names $j) -join ",") -ceq (@($before) -join ",")) "and no file was written in the journal"
Check ((@(Names (Split-Path -Parent $j)) -join ",") -ceq (@($parentBefore) -join ",")) "nor beside it"
$r = Open-HordeJournalEntry -Root $j -Id (New-Id) -Verb "Session Spawn" -Arguments $spawnArgs -IssuedAt $utcNow
Check ($r.decision -ceq "refuse") "a verb that is not a dotted lowercase name is refused"
Check ((Get-HordeJournalEntry -Root $j -Id "..\x").state -ceq "unknown") "request.status on a malformed id is unknown"
# A TRAILING LF IS NOT PART OF A NAME. In .NET regular expressions $ also matches before a final LF,
# so '^...$' accepted "session.spawn`n" and an id with an LF after it, and the verb was acted on
# (review of PR #39, 2026-09-30). The patterns end in \z.
$before = Names $j
$lfId = Open-HordeJournalEntry -Root $j -Id ((New-Id) + [char]10) -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow
Check ($lfId.decision -ceq "refuse") "an id followed by an LF is refused"
$lfVerb = Open-HordeJournalEntry -Root $j -Id (New-Id) -Verb ("session.spawn" + [char]10) -Arguments $spawnArgs -IssuedAt $utcNow
Check ($lfVerb.decision -ceq "refuse") "a verb followed by an LF is refused, not acted on"
Check ((@(Names $j) -join ",") -ceq (@($before) -join ",")) "and neither wrote a file"
Check ((Get-HordeJournalEntry -Root $j -Id ((New-Id) + [char]10)).state -ceq "unknown") "request.status on an id followed by an LF is unknown"
# ARGUMENTS THAT ARE NOT JSON DATA ARE REFUSED, NOT THROWN. A frame from the far end is input: a
# request whose arguments cannot be hashed is answered "refuse" with the reason, like any other bad
# request, rather than raising an error in the node (review of PR #39).
$before = Names $j
$nj = $null
try { $nj = Open-HordeJournalEntry -Root $j -Id (New-Id) -Verb "session.spawn" -Arguments @{ when = (Get-Date) } -IssuedAt $utcNow } catch { $nj = "threw: " + $_.Exception.Message }
Check ($nj -isnot [string] -and $nj.decision -ceq "refuse" -and "$($nj.reason)" -like "*cannot be hashed*") "arguments holding a date are refused with the reason, not thrown"
$nz = $null
try { $nz = Open-HordeJournalEntry -Root $j -Id (New-Id) -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt ([datetime]"2026-09-30T12:00:00") } catch { $nz = "threw: " + $_.Exception.Message }
Check ($nz -isnot [string] -and $nz.decision -ceq "refuse" -and "$($nz.reason)" -like "*zone*") "an issue time with no zone is refused with the reason, not thrown"
Check ((@(Names $j) -join ",") -ceq (@($before) -join ",")) "and neither wrote a file"

Write-Host ""
Write-Host "--- the admission window: an id too old to be checked is refused, not acted ---" -ForegroundColor Cyan

$w = New-TestRoot -Init
$now = [datetime]::UtcNow
$old = Open-HordeJournalEntry -Root $w -Id (New-Id) -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $now.AddDays(-8) -Now $now
Check ($old.decision -ceq "refuse" -and "$($old.reason)" -like "*window*") "a new id issued 8 days ago (window 7) is refused"
$fresh = Open-HordeJournalEntry -Root $w -Id (New-Id) -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $now.AddDays(-6) -Now $now
Check ($fresh.decision -ceq "act") "control: one issued 6 days ago acts"
$future = Open-HordeJournalEntry -Root $w -Id (New-Id) -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $now.AddMinutes(120) -Now $now
Check ($future.decision -ceq "refuse" -and "$($future.reason)" -like "*future*") "a new id issued 2 hours in the future (allowance 60 minutes) is refused"
$near = Open-HordeJournalEntry -Root $w -Id (New-Id) -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $now.AddMinutes(30) -Now $now
Check ($near.decision -ceq "act") "control: one issued 30 minutes ahead acts"
$kid = New-Id
$null = Open-HordeJournalEntry -Root $w -Id $kid -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $now.AddDays(-6) -Now $now
Complete-HordeJournalEntry -Root $w -Id $kid -State "done" -Result (New-HordeKnown -Value "ok") -Now $now | Out-Null
$late = Open-HordeJournalEntry -Root $w -Id $kid -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $now.AddDays(-6) -Now $now.AddDays(10)
Check ($late.decision -ceq "replay") "an id past the window that IS recorded still replays: what is known is answered"
Check (@(Names $w).Count -eq 5) "the marker, three records and one outcome: the two refused ids wrote nothing"

Write-Host ""
Write-Host "--- request.status ---" -ForegroundColor Cyan

$s = New-TestRoot -Init
Check ((Get-HordeJournalEntry -Root $s -Id (New-Id)).state -ceq "absent") "an id never recorded is absent: it never arrived, so it is safe to resend"
$sid = New-Id
$null = Open-HordeJournalEntry -Root $s -Id $sid -Verb "session.spawn" -Arguments $spawnArgs -IssuedAt $utcNow
$st = Get-HordeJournalEntry -Root $s -Id $sid
Check ($st.state -ceq "known" -and "$((Get-HordeValue $st).state)" -ceq "accepted") "a recorded id with no outcome is known 'accepted'"
Complete-HordeJournalEntry -Root $s -Id $sid -State "done" -Result (New-HordeKnown -Value 3) | Out-Null
$st = Get-HordeJournalEntry -Root $s -Id $sid
$sv = Get-HordeValue $st
Check ("$($sv.state)" -ceq "done" -and "$($sv.verb)" -ceq "session.spawn") "a completed id is known 'done', with its verb"
Check ($sv.result.state -ceq "known" -and (Get-HordeValue $sv.result) -eq 3) "and its result"

Write-Host ""
Write-Host "--- retention and pruning ---" -ForegroundColor Cyan

$p = New-TestRoot -Init
$now = [datetime]::UtcNow
function Add-Entry { param([string]$Root, [datetime]$At, [string]$State)
    $eid = New-Id
    $null = Open-HordeJournalEntry -Root $Root -Id $eid -Verb "session.spawn" -Arguments @{ x = $eid } -IssuedAt $At -Now $At
    if ($State) { Complete-HordeJournalEntry -Root $Root -Id $eid -State $State -Result (New-HordeKnown -Value 1) -Now $At | Out-Null }
    return $eid }
$gone = Add-Entry $p $now.AddDays(-31) "done"
$gone2 = Add-Entry $p $now.AddDays(-45) "failed"
$keep = Add-Entry $p $now.AddDays(-29) "done"
$halfOld = Add-Entry $p $now.AddDays(-400) ""
$tornId = New-Id; [System.IO.File]::WriteAllText((Join-Path $p ($tornId + ".json")), "{")
$orphan = New-Id
[System.IO.File]::WriteAllText((Join-Path $p ($orphan + ".outcome.json")), ('{"v":1,"id":"' + $orphan + '","state":"done","result":{"state":"known","value":1,"reason":"","observedAt":null},"doneAt":"' + $now.AddDays(-40).ToString("o") + '"}'))
$repA = Remove-HordeJournalExpired -Root $p -Now $now
Check ($repA.state -ceq "known") "pruning a journal gives a known report"
$rep = Get-HordeValue $repA
Check (-not (Test-Path -LiteralPath (Join-Path $p ($gone + ".json"))) -and -not (Test-Path -LiteralPath (Join-Path $p ($gone + ".outcome.json")))) "a done entry past 30 days is removed, record and outcome"
Check (-not (Test-Path -LiteralPath (Join-Path $p ($gone2 + ".json")))) "and so is a failed one"
Check ((Get-HordeJournalEntry -Root $p -Id $keep).state -ceq "known") "a done entry inside 30 days is kept"
Check ((Get-HordeJournalEntry -Root $p -Id $halfOld).state -ceq "known") "an entry with no outcome is never pruned, however old: forgetting it would let a resend act again"
Check (@($rep.kept | Where-Object { $_.id -ceq $halfOld -and "$($_.reason)" -like "*no outcome*" }).Count -eq 1) "and the report names it, with the reason"
Check (Test-Path -LiteralPath (Join-Path $p ($tornId + ".json"))) "a torn entry is never pruned"
Check (@($rep.kept | Where-Object { $_.id -ceq $tornId }).Count -eq 1) "and the report names it"
Check (-not (Test-Path -LiteralPath (Join-Path $p ($orphan + ".outcome.json")))) "an old outcome whose record is gone (a prune cut short) is removed"
Check (@($rep.removed) -contains $gone -and @($rep.removed) -contains $gone2) "the report lists what was removed"
Check (Test-Path -LiteralPath (Join-Path $p "journal.json")) "the marker survives pruning"
$resend = Open-HordeJournalEntry -Root $p -Id $gone -Verb "session.spawn" -Arguments @{ x = $gone } -IssuedAt $now.AddDays(-31) -Now $now
Check ($resend.decision -ceq "refuse") "a resend of a pruned id is refused by the window, never acted again"

# A record that cannot be deleted (held open without delete sharing) must leave its outcome in place.
# Deleting the outcome first would turn a done entry into one with no outcome - unknown for ever.
$q = New-TestRoot -Init
$held = Add-Entry $q $now.AddDays(-60) "done"
$hs = New-Object System.IO.FileStream((Join-Path $q ($held + ".json")), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
try { $rep2 = Get-HordeValue (Remove-HordeJournalExpired -Root $q -Now $now) } finally { $hs.Dispose() }
$hv = Get-HordeJournalEntry -Root $q -Id $held
Check ($hv.state -ceq "known" -and "$((Get-HordeValue $hv).state)" -ceq "done") "a prune that cannot delete a record leaves the entry whole and done, not outcome-less"
Check (@($rep2.kept | Where-Object { $_.id -ceq $held }).Count -eq 1) "and reports it kept"
$rep3 = Get-HordeValue (Remove-HordeJournalExpired -Root $q -Now $now)
Check (@($rep3.removed) -contains $held) "control: once the record is free, the next prune removes it"

$np = Remove-HordeJournalExpired -Root (New-TestRoot) -Now $now
Check ($np.state -ceq "unknown") "pruning a folder that is not a journal deletes nothing and says unknown"

} finally {
    foreach ($t in $script:tempRoots) { if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Recurse -Force } }
}
$left = @($script:tempRoots | Where-Object { Test-Path -LiteralPath $_ })
Check ($left.Count -eq 0) "every temp journal this suite made is removed"

Complete-HordeSuite -Success "the journal acts once per id, replays, refuses reuse, and keeps what it cannot resolve"
