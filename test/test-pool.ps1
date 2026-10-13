# DOES THE POOL KEEP EVERY CLOSED ORC ONCE, SHOW IT BY WINDOW, AND HOLD NOTHING IT MUST NOT?
#
# pool/Port.ps1, pool/Store.ps1 and pool/Settings.ps1, in this process (planning/idle-session-reaper.md
# section 13, slice PA). The suite attacks the rules:
#   - an entry is written once and never rewritten: the same close added again is the same entry, and a
#     different closure record for that close is refused with the file left as it was;
#   - the pool keeps Orcs only: a Warg or a founder session writes nothing, an unknown role is kept;
#   - an entry holds no transcript text: a source with any field not on the list is refused, naming it;
#   - a harness or session id that could leave the store's folder is refused before any path is made;
#   - the windows are cumulative and counted from the close, never the start, and nothing older than the
#     retention is listed even before a sweep;
#   - the sweep removes only old entries, never a closure record or anything else, and the retention can
#     be raised and never lowered below 92 days;
#   - listing never opens a transcript.
# The real `horde pool` command is test/test-pool-cli.ps1.
#
# Every home here is a fresh folder under %TEMP% that this suite made and removes (CONTRIBUTING 9), and
# the home every call is given is that folder: the real home is never read.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "pool\Port.ps1")

$script:work = Join-Path $env:TEMP ("horde-pool-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
[System.IO.Directory]::SetCurrentDirectory($script:work)
Set-Location -LiteralPath $script:work
# Whatever a function here is not handed, it must not find the real home.
$env:HORDE_HOME = Join-Path $script:work "home-nobody-uses"
$script:n = 0
$invariant = [System.Globalization.CultureInfo]::InvariantCulture
# A fixed "now", so every window and the sweep are measured against one known moment.
$now = New-Object DateTime 2026, 10, 13, 12, 0, 0, ([DateTimeKind]::Utc)

function New-TestHome {
    $script:n++
    return (Join-Path $script:work ("home-" + $script:n))
}
function Get-PoolFolder { param([string]$TestHome) return (Join-Path $TestHome "store\pool") }
function Get-EntriesFolder { param([string]$TestHome) return (Join-Path $TestHome "store\pool\entries") }
function Get-PoolFiles {
    # Every file under the home's pool folder, as full paths, sorted; empty when there is none.
    param([string]$TestHome)
    $folder = Get-PoolFolder $TestHome
    if (-not (Test-Path -LiteralPath $folder)) { return @() }
    return @(Get-ChildItem -LiteralPath $folder -Recurse -File -Force | Sort-Object FullName | ForEach-Object { $_.FullName })
}
function Get-Iso { param([datetime]$At) return $At.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", $invariant) }
function New-Source {
    # A source for one close, closed -DaysAgo days before $now and started -StartedDaysBefore days
    # before that. -Set overrides or adds fields; -Drop removes them.
    param([double]$DaysAgo = 1, [string]$SessionId = "s-0001", [string]$Label = "F3", [double]$StartedDaysBefore = 20, [hashtable]$Set = @{}, [string[]]$Drop = @())
    $closed = $now.AddDays(-$DaysAgo)
    $s = @{
        machine = @{ id = "machine-1"; name = "box-one" }
        harness = "agent-a"
        sessionId = $SessionId
        label = $Label
        name = "pool builder"
        role = "orc"
        owner = "F"
        parent = $null
        taskIds = @("T-0001", "T-0002")
        cwd = (Join-Path $script:work "repo")
        startedAt = (Get-Iso $closed.AddDays(-$StartedDaysBefore))
        lastActiveAt = (Get-Iso $closed.AddMinutes(-30))
        closedAt = (Get-Iso $closed)
        closedBy = @{ kind = "reaper" }
        closureRecord = $null
        resume = @{ argv = @("agent-a", "--resume", $SessionId); transcriptPath = (Join-Path $script:work "no-such-transcript.jsonl"); fileId = "0x00010000000a1b2c"; length = 4096; tailHash = ("ab" * 32) }
        remote = $null
        memoryMB = 512
    }
    foreach ($k in @($Set.Keys)) { $s[$k] = $Set[$k] }
    foreach ($k in $Drop) { $s.Remove($k) }
    return $s
}
function Get-Labels {
    param($Listing)
    return (@($Listing.entries | ForEach-Object { $_.label }) -join ",")
}

Write-Host ""
Write-Host "--- an entry is written once, where it belongs ---" -ForegroundColor Cyan
$h = New-TestHome
$closure = Join-Path $script:work "closure-1.json"
$first = Add-HordePoolEntry -Source (New-Source -DaysAgo 1 -Set @{ closureRecord = $closure }) -HordeHome $h
Check ($first.added -eq $true -and $first.outcome -ceq "created") ("a new close is added (" + $first.outcome + ": " + $first.reason + ")")
Check ("" + $first.entry.entryId -cmatch '\A[0-9a-f]{32}\z') "its entry id is 32 lower-case hex digits"
$closedFirst = $now.AddDays(-1)
$expected = Join-Path (Get-EntriesFolder $h) ($closedFirst.ToString("yyyy-MM", $invariant) + "\" + $closedFirst.ToString("yyyyMMdd'T'HHmmssfff'Z'", $invariant) + "-agent-a-s-0001.json")
Check ([System.IO.File]::Exists($expected)) ("the entry is at entries\<yyyy-MM>\<closed>-<harness>-<session>.json (" + $expected + ")")
Check (@(Get-PoolFiles $h).Count -eq 1) "and nothing else is under the pool folder"
$onDisk = [System.IO.File]::ReadAllText($expected) | ConvertFrom-Json
Check ($onDisk.schemaVersion -eq 1 -and $onDisk.entryId -ceq $first.entry.entryId -and $onDisk.closureRecord -ceq $closure) "the file holds schema version 1, the entry id it was given, and the closure record"
$schemaFindings = @(Test-HordeSchema -Value $onDisk -Schema (Get-HordeSchema -Name "pool-entry.v1"))
Check ($schemaFindings.Count -eq 0) ("the file fits schema/pool-entry.v1 (" + ($schemaFindings -join "; ") + ")")
$bytesBefore = [System.IO.File]::ReadAllBytes($expected)
$writtenBefore = [System.IO.File]::GetLastWriteTimeUtc($expected)

$again = Add-HordePoolEntry -Source (New-Source -DaysAgo 1 -Set @{ closureRecord = $closure }) -HordeHome $h
Check ($again.outcome -ceq "exists" -and $again.added -eq $false -and $again.entry.entryId -ceq $first.entry.entryId -and @(Get-PoolFiles $h).Count -eq 1) ("the same close added twice is one entry (" + $again.outcome + ")")
$other = Add-HordePoolEntry -Source (New-Source -DaysAgo 1 -Set @{ closureRecord = (Join-Path $script:work "closure-other.json") }) -HordeHome $h
Check ($other.outcome -ceq "refused" -and $other.added -eq $false -and "$($other.reason)" -like "*closure record*" -and @(Get-PoolFiles $h).Count -eq 1) ("a different closure record for the same close is refused (" + $other.outcome + ": " + $other.reason + ")")
$noClosure = Add-HordePoolEntry -Source (New-Source -DaysAgo 1) -HordeHome $h
Check ($noClosure.outcome -ceq "refused") "and so is the same close with no closure record where the first had one"
$bytesAfter = [System.IO.File]::ReadAllBytes($expected)
Check ((@(Compare-Object $bytesBefore $bytesAfter -SyncWindow 0).Count -eq 0) -and [System.IO.File]::GetLastWriteTimeUtc($expected) -eq $writtenBefore) "an entry is written once and never rewritten"

$h2 = New-TestHome
$a1 = Add-HordePoolEntry -Source (New-Source -DaysAgo 3) -HordeHome $h2
$a2 = Add-HordePoolEntry -Source (New-Source -DaysAgo 1) -HordeHome $h2
Check ($a1.outcome -ceq "created" -and $a2.outcome -ceq "created" -and $a1.entry.entryId -cne $a2.entry.entryId -and @(Get-PoolFiles $h2).Count -eq 2) "a session closed twice gets two entries"
$sameSecond = Add-HordePoolEntry -Source (New-Source -DaysAgo 1 -Set @{ closedAt = (Get-Iso $now.AddDays(-1).AddMilliseconds(5)) }) -HordeHome $h2
Check ($sameSecond.outcome -ceq "created" -and @(Get-PoolFiles $h2).Count -eq 3) "two closes 5 ms apart are two closes, not one"

Write-Host ""
Write-Host "--- the pool keeps Orcs only ---" -ForegroundColor Cyan
$hw = New-TestHome
$warg = Add-HordePoolEntry -Source (New-Source -Set @{ role = "warg" }) -HordeHome $hw
Check ($warg.added -eq $false -and $warg.outcome -ceq "not-an-orc" -and "$($warg.reason)" -like "*warg*" -and -not (Test-Path -LiteralPath (Get-PoolFolder $hw))) ("a closed Warg makes no pool entry (" + $warg.outcome + ": " + $warg.reason + ")")
$founder = Add-HordePoolEntry -Source (New-Source -Set @{ role = "founder" }) -HordeHome $hw
Check ($founder.added -eq $false -and $founder.outcome -ceq "not-an-orc" -and -not (Test-Path -LiteralPath (Get-PoolFolder $hw))) "a founder session that is not an Orc makes no pool entry"
$unknownRole = Add-HordePoolEntry -Source (New-Source -Set @{ role = "unknown" }) -HordeHome $hw
Check ($unknownRole.added -eq $true -and $unknownRole.entry.role -ceq "unknown" -and @(Get-PoolFiles $hw).Count -eq 1) "an unknown role is kept as an Orc"
$noRole = Add-HordePoolEntry -Source (New-Source -SessionId "s-norole" -Drop @("role")) -HordeHome $hw
Check ($noRole.outcome -ceq "refused" -and "$($noRole.reason)" -like "*role*" -and @(Get-PoolFiles $hw).Count -eq 1) ("a source with no role is refused, naming it (" + $noRole.reason + ")")
$badRole = Add-HordePoolEntry -Source (New-Source -SessionId "s-badrole" -Set @{ role = "worker" }) -HordeHome $hw
Check ($badRole.outcome -ceq "refused" -and "$($badRole.reason)" -like "*role*" -and @(Get-PoolFiles $hw).Count -eq 1) "a role that is not orc, warg, founder or unknown is refused"

Write-Host ""
Write-Host "--- an entry holds no transcript text, and nothing it was not told to ---" -ForegroundColor Cyan
$hx = New-TestHome
$prompt = Add-HordePoolEntry -Source (New-Source -Set @{ lastPrompt = "please refactor the store" }) -HordeHome $hx
Check ($prompt.outcome -ceq "refused" -and "$($prompt.reason)" -like "*lastPrompt*" -and -not (Test-Path -LiteralPath (Get-PoolFolder $hx))) ("an entry holds no transcript text (" + $prompt.reason + ")")
$nested = Add-HordePoolEntry -Source (New-Source -Set @{ resume = @{ argv = @("agent-a"); transcriptPath = "x"; fileId = "1"; length = 1; tailHash = ("ab" * 32); lastLine = "hello" } }) -HordeHome $hx
Check ($nested.outcome -ceq "refused" -and "$($nested.reason)" -like "*lastLine*" -and -not (Test-Path -LiteralPath (Get-PoolFolder $hx))) "a field hidden inside resume is refused too, naming it"
$givenId = Add-HordePoolEntry -Source (New-Source -Set @{ entryId = ("0" * 32) }) -HordeHome $hx
Check ($givenId.outcome -ceq "refused" -and "$($givenId.reason)" -like "*entryId*") "a source may not choose its entry id"
foreach ($field in @("machine", "harness", "sessionId", "label", "closedAt", "closedBy", "resume", "cwd")) {
    $missing = Add-HordePoolEntry -Source (New-Source -Drop @($field)) -HordeHome $hx
    Check ($missing.outcome -ceq "refused" -and "$($missing.reason)" -like ("*" + $field + "*")) ("a source with no " + $field + " is refused, naming it")
}
$long = Add-HordePoolEntry -Source (New-Source -Label ("L" * 201)) -HordeHome $hx
Check ($long.outcome -ceq "refused" -and "$($long.reason)" -like "*label*") "a label of 201 characters is refused"
$longName = Add-HordePoolEntry -Source (New-Source -Set @{ name = ("n" * 201) }) -HordeHome $hx
Check ($longName.outcome -ceq "refused" -and "$($longName.reason)" -like "*name*") "a name of 201 characters is refused"
$lineBreak = Add-HordePoolEntry -Source (New-Source -Label "F3`nrm -rf") -HordeHome $hx
Check ($lineBreak.outcome -ceq "refused") "a label with a line break is refused"
Check (-not (Test-Path -LiteralPath (Get-PoolFolder $hx))) "CONTROL: none of those refusals wrote anything"
$atCap = Add-HordePoolEntry -Source (New-Source -Label ("L" * 200)) -HordeHome $hx
Check ($atCap.outcome -ceq "created") "CONTROL: a label of 200 characters is kept"
$offerNoPart = Add-HordePoolEntry -Source (New-Source -SessionId "s-offer" -Set @{ closedBy = @{ kind = "offer" } }) -HordeHome $hx
Check ($offerNoPart.outcome -ceq "refused" -and "$($offerNoPart.reason)" -like "*decision*") "a close by offer with no decision is refused"
$reaperWithPart = Add-HordePoolEntry -Source (New-Source -SessionId "s-offer" -Set @{ closedBy = @{ kind = "reaper"; decision = 12; part = "b" } }) -HordeHome $hx
Check ($reaperWithPart.outcome -ceq "refused") "a close by the reaper that names a decision is refused"
$offer = Add-HordePoolEntry -Source (New-Source -SessionId "s-offer" -Set @{ closedBy = @{ kind = "offer"; decision = 12; part = "b" } }) -HordeHome $hx
Check ($offer.outcome -ceq "created" -and $offer.entry.closedBy.decision -eq 12 -and $offer.entry.closedBy.part -ceq "b") "CONTROL: a close by offer with its decision and part is kept"
$badKind = Add-HordePoolEntry -Source (New-Source -SessionId "s-kind" -Set @{ closedBy = @{ kind = "crash" } }) -HordeHome $hx
Check ($badKind.outcome -ceq "refused") "a closedBy kind not on the list is refused"
$fromJson = Add-HordePoolEntry -Source ((New-Source -SessionId "s-json" | ConvertTo-Json -Depth 10) | ConvertFrom-Json) -HordeHome $hx
Check ($fromJson.outcome -ceq "created") "a source read from JSON, an object and not a hashtable, is taken the same way"

Write-Host ""
Write-Host "--- a harness or session id cannot leave the folder ---" -ForegroundColor Cyan
$hp = New-TestHome
foreach ($bad in @("a\b", "a/b", "..", "..\..\x", "a:b", "s.1", "", " s")) {
    $r = Add-HordePoolEntry -Source (New-Source -SessionId $bad) -HordeHome $hp
    Check ($r.outcome -ceq "refused" -and "$($r.reason)" -like "*sessionId*") ("a session id with a path separator is refused: '" + $bad + "'")
}
foreach ($bad in @("..", "a\b", "a/b", "c:", "Agent-A")) {
    $r = Add-HordePoolEntry -Source (New-Source -Set @{ harness = $bad }) -HordeHome $hp
    Check ($r.outcome -ceq "refused" -and "$($r.reason)" -like "*harness*") ("a harness that could leave the folder is refused: '" + $bad + "'")
}
Check (-not (Test-Path -LiteralPath $hp)) "and none of them made so much as the home folder"
Check (@(Get-ChildItem -LiteralPath $script:work -Recurse -Filter "*.json" -Force | Where-Object { $_.FullName -notlike ($script:work + "\home-*") }).Count -eq 0) "and no entry landed anywhere else in the suite's folder"
$badTime = Add-HordePoolEntry -Source (New-Source -Set @{ closedAt = "2026-10-13 12:00:00" }) -HordeHome $hp
Check ($badTime.outcome -ceq "refused" -and "$($badTime.reason)" -like "*closedAt*") "a closedAt that is not UTC ISO 8601 is refused"

Write-Host ""
Write-Host "--- windows count from the close ---" -ForegroundColor Cyan
$hwin = New-TestHome
# Each started 20 days before it closed, so a window counted from the start would see none of them in 7d.
$null = Add-HordePoolEntry -Source (New-Source -DaysAgo 6 -SessionId "s-6" -Label "six") -HordeHome $hwin
$null = Add-HordePoolEntry -Source (New-Source -DaysAgo 8 -SessionId "s-8" -Label "eight") -HordeHome $hwin
$null = Add-HordePoolEntry -Source (New-Source -DaysAgo 7.5 -SessionId "s-75" -Label "sevenhalf") -HordeHome $hwin
$null = Add-HordePoolEntry -Source (New-Source -DaysAgo 20 -SessionId "s-20" -Label "twenty") -HordeHome $hwin
$null = Add-HordePoolEntry -Source (New-Source -DaysAgo 60 -SessionId "s-60" -Label "sixty") -HordeHome $hwin
$null = Add-HordePoolEntry -Source (New-Source -DaysAgo 0.5 -SessionId "s-05" -Label "half" -StartedDaysBefore 0.1) -HordeHome $hwin
$w7 = Get-HordePoolEntries -Window "7d" -Now $now -HordeHome $hwin
Check ((Get-Labels $w7) -ceq "half,six") ("the 7-day window holds an entry closed 6 days ago and not one closed 8 days ago (" + (Get-Labels $w7) + ")")
$w30 = Get-HordePoolEntries -Window "30d" -Now $now -HordeHome $hwin
$w3m = Get-HordePoolEntries -Window "3m" -Now $now -HordeHome $hwin
Check ((Get-Labels $w30) -ceq "half,six,sevenhalf,eight,twenty" -and (Get-Labels $w3m) -ceq "half,six,sevenhalf,eight,twenty,sixty") ("the 30-day and 3-month windows are cumulative (" + (Get-Labels $w30) + " | " + (Get-Labels $w3m) + ")")
Check ($w7.state -ceq "ok" -and $w7.windowDays -eq 7 -and $w30.windowDays -eq 30 -and $w3m.windowDays -eq 92) "each window says how many days it covers"
$default = Get-HordePoolEntries -Now $now -HordeHome $hwin
Check ((Get-Labels $default) -ceq (Get-Labels $w3m)) "with no window the list is the whole 3 months"
Check (Throws { Get-HordePoolEntries -Window "1y" -Now $now -HordeHome $hwin } "1y") "a window not on the list is refused, naming it"
$empty = Get-HordePoolEntries -Window "7d" -Now $now -HordeHome (New-TestHome)
Check ($empty.state -ceq "absent" -and @($empty.entries).Count -eq 0) "a pool nothing was ever added to lists nothing, and says so"

Write-Host ""
Write-Host "--- the retention: never listed past it, swept past it ---" -ForegroundColor Cyan
$hr = New-TestHome
$closureDir = Join-Path $hr "store\closures"
New-Item -ItemType Directory -Path $closureDir | Out-Null
$closureFile = Join-Path $closureDir "close-old.json"
[System.IO.File]::WriteAllText($closureFile, '{"state":"closed"}')
$null = Add-HordePoolEntry -Source (New-Source -DaysAgo 100 -SessionId "s-100" -Label "hundred" -Set @{ closureRecord = $closureFile }) -HordeHome $hr
$null = Add-HordePoolEntry -Source (New-Source -DaysAgo 93 -SessionId "s-93" -Label "ninetythree") -HordeHome $hr
$null = Add-HordePoolEntry -Source (New-Source -DaysAgo 91 -SessionId "s-91" -Label "ninetyone") -HordeHome $hr
$null = Add-HordePoolEntry -Source (New-Source -DaysAgo 2 -SessionId "s-2" -Label "two") -HordeHome $hr
Check (@(Get-PoolFiles $hr).Count -eq 4) "CONTROL: four entries are on disk, two older than the retention"
$before = Get-HordePoolEntries -Window "3m" -Now $now -HordeHome $hr
Check ((Get-Labels $before) -ceq "two,ninetyone") ("an entry older than the retention is not listed before a sweep (" + (Get-Labels $before) + ")")
$monthOf100 = Join-Path (Get-EntriesFolder $hr) $now.AddDays(-100).ToString("yyyy-MM", $invariant)
$stray = Join-Path (Get-EntriesFolder $hr) ($now.AddDays(-91).ToString("yyyy-MM", $invariant) + "\notes.txt")
[System.IO.File]::WriteAllText($stray, "not an entry")
$sweep = Invoke-HordePoolSweep -Now $now -HordeHome $hr
Check ($sweep.removed -eq 2 -and @(Get-PoolFiles $hr | Where-Object { $_ -like "*.json" }).Count -eq 2) ("the sweep removes the two entries older than the retention (" + $sweep.removed + ")")
Check ([System.IO.File]::Exists($closureFile) -and [System.IO.File]::ReadAllText($closureFile) -ceq '{"state":"closed"}' -and $sweep.removed -eq 2) "an entry older than the retention is swept, its closure record is not"
Check ([System.IO.File]::Exists($stray)) "a file in the pool that is not an entry is left alone"
Check (-not (Test-Path -LiteralPath $monthOf100) -and $sweep.removedFolders -ge 1) "a month folder the sweep left empty is removed"
$after = Get-HordePoolEntries -Window "3m" -Now $now -HordeHome $hr
Check ((Get-Labels $after) -ceq "two,ninetyone") "after the sweep the list is the same"
$again2 = Invoke-HordePoolSweep -Now $now -HordeHome $hr
Check ($again2.removed -eq 0) "a second sweep removes nothing"
$sweepNone = Invoke-HordePoolSweep -Now $now -HordeHome (New-TestHome)
Check ($sweepNone.removed -eq 0) "a sweep of a pool that was never made removes nothing and makes nothing"

Write-Host ""
Write-Host "--- the retention can be raised and never lowered ---" -ForegroundColor Cyan
Check ((Get-HordePoolSettings -HordeHome (New-TestHome)).retentionDays -eq 92) "the retention is 92 days by default"
$hs = New-TestHome
$null = Add-HordePoolEntry -Source (New-Source -DaysAgo 100 -SessionId "s-100" -Label "hundred") -HordeHome $hs
New-Item -ItemType Directory -Path (Join-Path $hs "settings") | Out-Null
$settingsFile = Join-Path $hs "settings\pool.json"
[System.IO.File]::WriteAllText($settingsFile, '{ "schemaVersion": 1, "settings": { "retentionDays": 91 } }')
Check ((Throws { Get-HordePoolEntries -Window "3m" -Now $now -HordeHome $hs } "retentionDays") -and (Throws { Invoke-HordePoolSweep -Now $now -HordeHome $hs } "retentionDays") -and @(Get-PoolFiles $hs).Count -eq 1) "the retention cannot be lowered below 92"
[System.IO.File]::WriteAllText($settingsFile, '{ "schemaVersion": 1, "settings": { "retentionDays": 120 } }')
$raised = Get-HordePoolEntries -Window "3m" -Now $now -HordeHome $hs
$raisedSweep = Invoke-HordePoolSweep -Now $now -HordeHome $hs
Check ((Get-Labels $raised) -ceq "hundred" -and $raised.windowDays -eq 120 -and $raisedSweep.removed -eq 0 -and @(Get-PoolFiles $hs).Count -eq 1) "a retention raised to 120 days lists and keeps an entry 100 days old"

Write-Host ""
Write-Host "--- list and show read no transcript ---" -ForegroundColor Cyan
$ht = New-TestHome
$null = Add-HordePoolEntry -Source (New-Source -DaysAgo 1 -SessionId "s-missing" -Label "missing") -HordeHome $ht
$held = Join-Path $script:work "held-transcript.jsonl"
[System.IO.File]::WriteAllText($held, '{"text":"never read"}')
$heldAdd = Add-HordePoolEntry -Source (New-Source -DaysAgo 2 -SessionId "s-held" -Label "held" -Set @{ resume = @{ argv = @("agent-a"); transcriptPath = $held; fileId = "0x1"; length = 22; tailHash = ("cd" * 32) } }) -HordeHome $ht
# Held with no sharing at all: anything that opens it to read, or even to look, now throws.
$lock = New-Object System.IO.FileStream($held, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
try {
    $tripped = $false
    try { $null = [System.IO.File]::ReadAllText($held) } catch { $tripped = $true }
    Check $tripped "CONTROL: the held transcript cannot be opened while the suite holds it"
    $listed = Get-HordePoolEntries -Window "7d" -Now $now -HordeHome $ht
    Check ((Get-Labels $listed) -ceq "missing,held" -and @($listed.unreadable).Count -eq 0) ("list reads no transcript (" + (Get-Labels $listed) + ")")
    $shown = Get-HordePoolEntry -EntryId $heldAdd.entry.entryId -HordeHome $ht
    Check ($shown.found -eq $true -and $shown.entry.label -ceq "held") "show reads no transcript either"
} finally { $lock.Dispose() }

Write-Host ""
Write-Host "--- show ---" -ForegroundColor Cyan
$unknownId = [guid]::NewGuid().ToString("N")
$miss = Get-HordePoolEntry -EntryId $unknownId -HordeHome $ht
Check ($miss.found -eq $false -and "$($miss.reason)" -like ("*" + $unknownId + "*")) "show of an unknown entry fails naming it"
$malformed = Get-HordePoolEntry -EntryId "..\x" -HordeHome $ht
Check ($malformed.found -eq $false -and "$($malformed.reason)" -like "*32*") "show of an id that is not 32 hex digits is refused, saying what an id is"
$noPool = Get-HordePoolEntry -EntryId $unknownId -HordeHome (New-TestHome)
Check ($noPool.found -eq $false -and "$($noPool.reason)" -like ("*" + $unknownId + "*")) "show in a pool that was never made fails naming the id"

Write-Host ""
Write-Host "--- a damaged entry is reported, never listed as a session ---" -ForegroundColor Cyan
$hd = New-TestHome
$good = Add-HordePoolEntry -Source (New-Source -DaysAgo 1 -SessionId "s-good" -Label "good") -HordeHome $hd
$monthDir = Join-Path (Get-EntriesFolder $hd) $now.AddDays(-1).ToString("yyyy-MM", $invariant)
$tornName = $now.AddDays(-2).ToString("yyyyMMdd'T'HHmmssfff'Z'", $invariant) + "-agent-a-s-torn.json"
[System.IO.File]::WriteAllText((Join-Path $monthDir $tornName), '{"schemaVersion": 1, "label": ')
$damaged = Get-HordePoolEntries -Window "7d" -Now $now -HordeHome $hd
Check ((Get-Labels $damaged) -ceq "good" -and @($damaged.unreadable).Count -eq 1 -and $damaged.unreadable[0].file -ceq $tornName) "a torn entry is listed as unreadable, by its file, and the rest is listed"
$extra = Join-Path $monthDir ($now.AddDays(-3).ToString("yyyyMMdd'T'HHmmssfff'Z'", $invariant) + "-agent-a-s-extra.json")
$tampered = [System.IO.File]::ReadAllText((Join-Path $monthDir ([System.IO.Path]::GetFileName((Get-PoolFiles $hd | Where-Object { $_ -like "*s-good.json" }))))) | ConvertFrom-Json
$tampered | Add-Member -NotePropertyName lastPrompt -NotePropertyValue "secret words"
[System.IO.File]::WriteAllText($extra, ($tampered | ConvertTo-Json -Depth 10))
$withExtra = Get-HordePoolEntries -Window "7d" -Now $now -HordeHome $hd
Check ((Get-Labels $withExtra) -ceq "good" -and @($withExtra.unreadable | Where-Object { "$($_.reason)" -like "*lastPrompt*" }).Count -eq 1) "an entry file holding a field not on the list is reported unreadable, never shown"
Check ((Get-HordePoolEntry -EntryId $good.entry.entryId -HordeHome $hd).found -eq $true) "CONTROL: show still finds the good entry beside them"

if ((Split-Path -Leaf $script:work) -match '\Ahorde-pool-test-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
    Set-Location -LiteralPath $env:TEMP
    [System.IO.Directory]::SetCurrentDirectory($env:TEMP)
    Remove-Item -LiteralPath $script:work -Recurse -Force
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"

Complete-HordeSuite -Success "the pool keeps each closed Orc once, holds no transcript text, lists by cumulative windows from the close, and sweeps only old entries"
