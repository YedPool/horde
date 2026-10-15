# DOES THE DECISIONS READ CACHE EVER SERVE A RECORD THAT CHANGED OR LEFT THE STORE, OR LET ONE CALLER
# CHANGE WHAT THE NEXT IS GIVEN?
#
# T-0166 (2026-10-15): every operation read and checked every record, so on the live store of 264
# records a list took about 10 s, an inbox or a show about 7 s, and a phone's answer reached the phone
# 22 to 58 s later. decisions/Store.ps1 now keeps, per process and per store folder, the text of every
# record it read whole, keyed by name, size and write time; decisions/Rules.ps1 keeps each such
# record's checks under the same stamp and the very definitions object they were made with (both
# headers: THE READ CACHE, THE CHECKS OF A RECORD ARE KEPT). This suite attacks what a cache can get
# wrong:
#   1. a cached read is the same as a fresh one: records, and the list, inbox and show built on them;
#   2. it IS a cache: a record held open by another process is still served, from what was read;
#   3. a new record appears; a record whose bytes change is read again (cut, it is torn; mended, ok);
#      a record only touched is read again and is the same; a removed record is a gap, and is gone
#      from both caches;
#   4. a record that fails its checks fails them again from the cache, and a record a caller changed
#      in one answer is unchanged in the next;
#   5. other definitions are checked afresh; another version of Store.ps1 empties the cache; a store
#      folder that is gone empties it for that folder.
# Under Windows PowerShell 5.1 and PowerShell 7 alike. Every store is a fresh folder under %TEMP% that
# this suite made and removes (CONTRIBUTING 9); the real store is listed before and after and must be
# untouched.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "decisions\Operations.ps1")
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$defs = Get-HordeDecisionDefinitions
$script:work = Join-Path $env:TEMP ("horde-decisions-cache-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-RealStoreListing {
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing

function Add-Question {
    param([string]$Store, [string]$Title)
    return (Invoke-HordeDecision -Operation "add" -Root $Store -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = $Title; kind = "yes-no"; whatItIs = "A question for the cache suite."; group = "cache"; askedBy = "c13" } })
}
function Get-Key { param([string]$Store) return [System.IO.Path]::GetFullPath($Store).TrimEnd("\").ToLowerInvariant() }
function Get-Cached { param([string]$Store) $k = $script:HordeDecisionStoreCache[(Get-Key $Store)]; if ($null -eq $k) { return @() }; return @($k.Keys | Sort-Object) }
function Show-Records {
    # The records as text, for comparison: everything a caller is handed but the stamp.
    param($Got)
    return (@($Got.records | ForEach-Object { [ordered]@{ sequence = $_.sequence; span = $_.span; file = $_.file; kind = $_.kind; reason = $_.reason; data = $_.data } }) | ConvertTo-Json -Depth 30 -Compress)
}
function Show-Answer { param($A) return ((ConvertTo-Json -InputObject $A.value -Depth 30 -Compress) -replace '"observedAt":"[^"]*"', '') }
function Reset-Caches { $script:HordeDecisionStoreCache = @{}; $script:HordeDecisionCheckCache = @{} }
function File-Of { param([string]$Store, [long]$Seq) return (Join-Path $Store (Get-HordeDecisionRecordName -Sequence $Seq)) }

try {
    $store = Join-Path $script:work "store-1"
    $made = @(1..3 | ForEach-Object { Add-Question -Store $store -Title ("Cache question " + $_ + ": keep it?") })
    Check (@($made | Where-Object { $_.state -ceq "known" -and $_.value.outcome -ceq "done" }).Count -eq 3) "CONTROL: three questions are in a store of the suite's own"
    $n = @(Get-ChildItem -LiteralPath $store -Filter "*.json").Count
    Check ($n -ge 3) ("CONTROL: the store holds their records (" + $n + ")")

    Write-Host ""
    Write-Host "--- 1. a cached read is a fresh read ---" -ForegroundColor Cyan
    Reset-Caches
    $fresh = Get-HordeDecisionRecords -Root $store
    Check (@(Get-Cached $store).Count -eq $n) ("the first read keeps every record read whole (" + @(Get-Cached $store).Count + " of " + $n + ")")
    $cached = Get-HordeDecisionRecords -Root $store
    Check ((Show-Records $fresh) -ceq (Show-Records $cached)) "the second read hands back exactly the records the first did"
    Check (@($cached.records | Where-Object { $_.kind -ceq "ok" -and "$($_.stamp)" -clike ((Get-Key $store) + "|*|*|*") }).Count -eq $n) "and each record read whole carries its stamp: folder, name, size, write time"
    Reset-Caches
    $ops = @(@{ o = "list"; r = @{ state = "open"; messages = $true } }, @{ o = "inbox"; r = @{ actor = "warchief" } }, @{ o = "show"; r = @{ number = 2 } })
    $cold = @($ops | ForEach-Object { Show-Answer (Invoke-HordeDecision -Operation $_.o -Request $_.r -Root $store) })
    $warm = @($ops | ForEach-Object { Show-Answer (Invoke-HordeDecision -Operation $_.o -Request $_.r -Root $store) })
    Reset-Caches
    $again = @($ops | ForEach-Object { Show-Answer (Invoke-HordeDecision -Operation $_.o -Request $_.r -Root $store) })
    foreach ($i in 0..2) { Check ($cold[$i] -ceq $warm[$i] -and $warm[$i] -ceq $again[$i] -and $cold[$i].Length -gt 50) ("the " + $ops[$i].o + " built on the cache is the " + $ops[$i].o + " built on a fresh read") }
    Check (@($script:HordeDecisionCheckCache.Keys).Count -eq $n) ("the checks of every record read whole are kept (" + @($script:HordeDecisionCheckCache.Keys).Count + ")")

    Write-Host ""
    Write-Host "--- 2. it is a cache: a record held open elsewhere is still served ---" -ForegroundColor Cyan
    $f1 = File-Of $store 1
    $hold = New-Object System.IO.FileStream($f1, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
    try { $held = Get-HordeDecisionRecords -Root $store } finally { $hold.Dispose() }
    Check (@($held.records)[0].kind -ceq "ok" -and (Show-Records $held) -ceq (Show-Records $fresh)) ("a record no one else may open now, but unchanged, is served from what was read (" + @($held.records)[0].kind + ")")

    Write-Host ""
    Write-Host "--- 3. new, changed, touched and removed records ---" -ForegroundColor Cyan
    $null = Add-Question -Store $store -Title "Cache question 4: a new one?"
    $grown = Get-HordeDecisionRecords -Root $store
    Check (@($grown.records).Count -eq ($n + 1) -and @(Get-Cached $store).Count -eq ($n + 1)) ("a new record appears, and is kept (" + @($grown.records).Count + ")")
    $f2 = File-Of $store 2
    $orig = [System.IO.File]::ReadAllText($f2, $utf8)
    [System.IO.File]::WriteAllText($f2, $orig.Substring(0, [int]($orig.Length / 2)), $utf8)
    $cut = Get-HordeDecisionRecords -Root $store
    $r2 = @($cut.records | Where-Object { $_.sequence -eq 2 })[0]
    Check ($r2.kind -ceq "torn" -and @(Get-Cached $store) -notcontains (Split-Path -Leaf $f2)) ("a record whose bytes changed is read again: cut, it is torn, and not kept (" + $r2.kind + ")")
    # Its size changed and its write time put back as it was: the size alone must be enough.
    [System.IO.File]::WriteAllText($f2, ($orig + " "), $utf8)
    $same = [System.IO.File]::GetLastWriteTimeUtc($f2)
    $longer = Get-HordeDecisionRecords -Root $store
    [System.IO.File]::WriteAllText($f2, $orig.Substring(0, [int]($orig.Length / 2)), $utf8)
    [System.IO.File]::SetLastWriteTimeUtc($f2, $same)
    $sizeOnly = Get-HordeDecisionRecords -Root $store
    Check (@($longer.records | Where-Object { $_.sequence -eq 2 })[0].kind -ceq "ok" -and @($sizeOnly.records | Where-Object { $_.sequence -eq 2 })[0].kind -ceq "torn") "a record whose size changed while its write time stayed the same is read again"
    [System.IO.File]::WriteAllText($f2, $orig, $utf8)
    $mended = Get-HordeDecisionRecords -Root $store
    Check (@($mended.records | Where-Object { $_.sequence -eq 2 })[0].kind -ceq "ok" -and (Show-Records $mended) -ceq (Show-Records $grown)) "mended, it is read again and is the record it was"
    $before = "$(@($mended.records | Where-Object { $_.sequence -eq 3 })[0].stamp)"
    [System.IO.File]::SetLastWriteTimeUtc((File-Of $store 3), [datetime]::UtcNow.AddMinutes(1))
    $touched = Get-HordeDecisionRecords -Root $store
    $after = "$(@($touched.records | Where-Object { $_.sequence -eq 3 })[0].stamp)"
    Check ($after -cne $before -and (Show-Records $touched) -ceq (Show-Records $grown)) "a record only touched has a new stamp, is read again, and is the same"
    $null = ConvertTo-HordeDecisionState -Records $touched.records -Definitions $defs
    Remove-Item -LiteralPath $f2
    $gone = Get-HordeDecisionRecords -Root $store
    $g2 = @($gone.records | Where-Object { $_.sequence -eq 2 })[0]
    Check ($g2.kind -ceq "missing" -and @(Get-Cached $store) -notcontains (Split-Path -Leaf $f2)) ("a removed record is a gap in the order, never served from the cache (" + $g2.kind + ")")
    $state = ConvertTo-HordeDecisionState -Records $gone.records -Definitions $defs
    Check (@($script:HordeDecisionCheckCache.Keys | Where-Object { $_ -clike ("*|" + (Split-Path -Leaf $f2) + "|*") }).Count -eq 0 -and @($script:HordeDecisionCheckCache.Keys).Count -ge 3) "and its checks are let go at the next fold, the others kept"

    Write-Host ""
    Write-Host "--- 4. a record that fails its checks fails them again; a caller's change does not leak ---" -ForegroundColor Cyan
    $bad = Join-Path $script:work "store-2"
    $null = Add-Question -Store $bad -Title "Cache question: a good one"
    # A record whose envelope is whole and whose event is not: a good record's envelope, its place moved
    # to 2, a new id, and data its kind's schema refuses - so the second check, made only once the
    # first passes, is the one that is kept.
    $good = [System.IO.File]::ReadAllText((File-Of $bad 1), $utf8) | ConvertFrom-Json
    $good.sequence = 2; $good.id = [guid]::NewGuid().ToString("N"); $good.data = [pscustomobject]@{ nonsense = $true }
    $wrong = ConvertTo-Json -InputObject $good -Depth 30 -Compress
    [System.IO.File]::WriteAllText((File-Of $bad 2), $wrong, $utf8)
    Reset-Caches
    $null = ConvertTo-HordeDecisionState -Records (Get-HordeDecisionRecords -Root $store).records -Definitions $defs
    $mine = @($script:HordeDecisionCheckCache.Keys | Where-Object { $_ -clike ((Get-Key $store) + "|*") }).Count
    $s1 = ConvertTo-HordeDecisionState -Records (Get-HordeDecisionRecords -Root $bad).records -Definitions $defs
    Check ($mine -ge 3 -and @($script:HordeDecisionCheckCache.Keys | Where-Object { $_ -clike ((Get-Key $store) + "|*") }).Count -eq $mine) ("folding one store lets go of nothing kept for another (" + $mine + ")")
    $s2 = ConvertTo-HordeDecisionState -Records (Get-HordeDecisionRecords -Root $bad).records -Definitions $defs
    $u1 = @($s1.unreadable | ForEach-Object { "" + $_.sequence + ":" + $_.reason }) -join ";"
    $u2 = @($s2.unreadable | ForEach-Object { "" + $_.sequence + ":" + $_.reason }) -join ";"
    Check ($u1 -cmatch '\A2:' -and $u1 -cnotmatch 'decision-event.v1 record' -and $u1 -ceq $u2) ("a record whose event breaks its kind's schema is unreadable again from the cache, for the same reason (" + $u1.Substring(0, [Math]::Min(80, $u1.Length)) + ")")
    $one = Get-HordeDecisionRecords -Root $store
    @($one.records)[0].data | Add-Member -NotePropertyName injected -NotePropertyValue "CHANGED BY A CALLER"
    $two = Get-HordeDecisionRecords -Root $store
    Check ($null -eq @($two.records)[0].data.PSObject.Properties["injected"] -and (Show-Records $two) -ceq (Show-Records $gone)) "a record a caller changed in one answer is unchanged in the next"

    Write-Host ""
    Write-Host "--- 5. other definitions, another version, a store that is gone ---" -ForegroundColor Cyan
    $recs = (Get-HordeDecisionRecords -Root $store).records
    $null = ConvertTo-HordeDecisionState -Records $recs -Definitions $defs
    $other = $defs.PSObject.Copy()
    $null = ConvertTo-HordeDecisionState -Records $recs -Definitions $other
    $held = @($script:HordeDecisionCheckCache.Keys | Where-Object { $_ -clike ((Get-Key $store) + "|*") } | ForEach-Object { $script:HordeDecisionCheckCache[$_] })
    Check ($held.Count -ge 1 -and @($held | Where-Object { -not [object]::ReferenceEquals($_.definitions, $other) }).Count -eq 0) "checks made with other definitions are made afresh, never reused across them"
    Check (@(Get-Cached $store).Count -ge 1) "CONTROL: before the next load, the cache holds this store's records"
    $script:HordeDecisionStoreCacheStamp = "another version of Store.ps1"
    . (Join-Path $root "decisions\Store.ps1")
    Check (@(Get-Cached $store).Count -eq 0 -and $script:HordeDecisionStoreCacheStamp -ceq $script:HordeDecisionStoreCodeStamp) "a cache another version of Store.ps1 made is emptied when this one loads"
    $null = Get-HordeDecisionRecords -Root $store
    . (Join-Path $root "decisions\Store.ps1")
    Check (@(Get-Cached $store).Count -ge 1) "and the same version loaded again keeps it"
    Remove-Item -LiteralPath $store -Recurse -Force
    $none = Get-HordeDecisionRecords -Root $store
    Check ($none.state -ceq "absent" -and $null -eq $script:HordeDecisionStoreCache[(Get-Key $store)] -and @($script:HordeDecisionCheckCache.Keys | Where-Object { $_ -clike ((Get-Key $store) + "|*") }).Count -eq 0) "a store folder that is gone is absent, and its texts and its checks are let go"
} finally {
    if ((Split-Path -Leaf $script:work) -match '^horde-decisions-cache-test-[0-9a-f]{32}$') { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store was not touched"
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's own folder is gone"

Complete-HordeSuite -Success "the decisions read cache serves only records unchanged since they were read, hands every caller its own copy, keeps the checks only for the same bytes and definitions, and lets go of what left the store"
