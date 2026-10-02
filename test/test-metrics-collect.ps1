# DOES `horde metrics collect` RECORD EXACTLY WHAT IS NEW OR CHANGED, AND ONLY WITH CONSENT?
#
# core/MetricsCollect.ps1, against a fake profile and a fake HORDE_HOME this suite creates and removes
# (CONTRIBUTING 9). Every engine's declared transcript folders are found from agents/<name>/stores.json
# under the fake profile, and filled with copies of the engines' own fixtures; every variable a
# stores.json names is cleared for the run, so no real store is read. Each rule has its control:
# unchanged, changed, new and deleted files; the gate off, refused and before consent; provisional
# records; and the lock.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "ReadShared", "Home", "Transcript", "Price", "Metrics", "MetricsStore", "MetricsReport", "MetricsCollect")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
foreach ($a in (Get-HordeTranscriptAdapterFiles -Root $root)) { . $a }
. (Join-Path $root "test\lib\Cli.ps1")

$work = Join-Path $env:TEMP ("horde-collect-" + [guid]::NewGuid().ToString("N"))
$saved = @{ HORDE_HOME = $env:HORDE_HOME; USERPROFILE = $env:USERPROFILE }
# Every variable a stores.json names can move a real store into view; each is cleared for the run.
Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$storeVars = @()
foreach ($sj in @(Get-ChildItem -LiteralPath (Join-Path $root "agents") -Directory | ForEach-Object { Join-Path $_.FullName "stores.json" } | Where-Object { Test-Path -LiteralPath $_ })) {
    foreach ($r in @($ser.DeserializeObject([System.IO.File]::ReadAllText($sj))["roots"])) { if ($r["env"] -is [string]) { $storeVars += $r["env"] } }
}
foreach ($v in $storeVars) { $saved[$v] = [Environment]::GetEnvironmentVariable($v); [Environment]::SetEnvironmentVariable($v, $null) }

function Set-Gate { param([string]$Text) [void][System.IO.Directory]::CreateDirectory((Get-HordeMetricsDir)); [System.IO.File]::WriteAllText((Join-Path (Get-HordeMetricsDir) "gate.json"), $Text) }
function Get-StoreSnapshot {
    # Every file under the home, with its size, time and hash: what "wrote nothing" is checked against.
    $h = Get-HordeHome
    if (-not (Test-Path -LiteralPath $h)) { return "" }
    return ((@(Get-ChildItem -LiteralPath $h -File -Recurse -Force | Where-Object { $_.Name -ne "collect.lock" } | Sort-Object FullName | ForEach-Object { $_.FullName + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks + "|" + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash })) -join "`n")
}
function Get-Records { $d = Join-Path (Get-HordeMetricsDir) "summaries"; if (-not (Test-Path -LiteralPath $d)) { return @() }; return @(Get-ChildItem -LiteralPath $d -File -Recurse -Filter "*.json" | Where-Object { $_.Extension -ceq ".json" }) }
function Get-Index { $p = Get-HordeCollectIndexPath; if (-not (Test-Path -LiteralPath $p)) { return $null }; return $ser.DeserializeObject([System.IO.File]::ReadAllText($p)) }
function Set-Old { param([string]$Path, [datetime]$At) (Get-Item -LiteralPath $Path).LastWriteTimeUtc = $At }

try {
    $env:USERPROFILE = Join-Path $work "profile"
    $env:HORDE_HOME = Join-Path $work "home"
    $now = [datetime]::UtcNow
    $settledAt = $now.AddHours(-1)
    $stores = Get-HordeAgentStores -Root $root
    Check ($stores.state -eq "known") "the engines' stores are read from their stores.json"
    $filled = 0
    $copies = New-Object System.Collections.ArrayList
    foreach ($s in @($stores.value)) {
        $fx = Join-Path $root ("agents\" + $s.agent + "\test\fixtures\metrics")
        if (@($s.transcripts).Count -eq 0 -or -not (Test-Path -LiteralPath $fx)) { continue }
        $dest = Join-Path @($s.transcripts)[0].dir "fixtures"
        [void][System.IO.Directory]::CreateDirectory($dest)
        Copy-Item -Path (Join-Path $fx "*") -Destination $dest -Recurse
        foreach ($c in @(Get-ChildItem -LiteralPath $dest -File -Recurse)) { Set-Old $c.FullName $settledAt; if ($c.Extension -ieq ".jsonl") { [void]$copies.Add($c.FullName); $filled++ } }
    }
    Check ($filled -ge 4) ("CONTROL: the fake stores hold the engines' fixtures (" + $filled + " transcripts)")
    $planted = @($copies | Where-Object { $_ -like "*planted*" -and $_ -notlike "*subagents*" })[0]
    $noBook = New-HordeAbsent -Note "not priced"

    Write-Host ""
    Write-Host "--- the gate: off, refused, before consent ---" -ForegroundColor Cyan
    $off = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    Check ($off.state -eq "off" -and -not (Test-Path -LiteralPath (Get-HordeHome))) "with no gate file collect is off, and the home is not even created"
    Set-Gate '{ "schemaVersion": 1, "level": "off", "enabledAt": "2026-09-01T00:00:00Z" }'
    $snap = Get-StoreSnapshot
    Check ((Invoke-HordeMetricsCollect -Now $now -RepoRoot $root).state -eq "off" -and (Get-StoreSnapshot) -eq $snap) "a gate that says off: off, and nothing written"
    Set-Gate '{ not json'
    $snap = Get-StoreSnapshot
    $ref = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    Check ($ref.state -eq "refused" -and (Get-StoreSnapshot) -eq $snap -and @(Get-Records).Count -eq 0) "a gate that cannot be read is refused, and nothing is written - no record, no index"
    # Consent after every fixture began: each is read (written to since), and none is recorded.
    Set-Gate ('{ "schemaVersion": 1, "level": "usage", "enabledAt": "' + $now.AddHours(-2).ToString("yyyy-MM-ddTHH:mm:ssZ") + '" }')
    $bc = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    Check ($bc.state -eq "done" -and $bc.recorded -eq 0 -and $bc.beforeConsent -eq $filled -and @(Get-Records).Count -eq 0) ("transcripts that began before consent are not recorded (" + $bc.beforeConsent + " of " + $filled + ")")
    Check ($bc.read -eq $filled) "they were read once, to learn when they began"
    $bcKeys = @((Get-Index)["entries"].Keys)
    Check ($bcKeys.Count -eq $filled -and @($bcKeys | Where-Object { $_ -notlike "hash:*" }).Count -eq 0) "and the index keeps nothing readable about them: each is a hash, no path and no name (review of PR #70, F6)"
    $bc2 = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    Check ($bc2.read -eq 0 -and -not $bc2.wroteIndex) "and are not read again while unchanged"
    [System.IO.File]::AppendAllText($planted, "`n")
    Set-Old $planted $settledAt.AddMinutes(1)
    $bc3 = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    Check ($bc3.read -eq 0 -and $bc3.beforeConsent -eq 1 -and @(Get-Records).Count -eq 0) "nor when one that began before consent has only grown: its first event cannot move later"
    Set-Gate ('{ "schemaVersion": 1, "level": "usage", "enabledAt": "' + $now.AddMinutes(-30).ToString("yyyy-MM-ddTHH:mm:ssZ") + '" }')
    $bm = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    Check ($bm.read -eq 0 -and $bm.beforeConsent -eq $filled) "a transcript last written before consent is not read at all"
    Check (@((Get-Index)["entries"].Keys).Count -eq 0) "nor indexed"

    Write-Host ""
    Write-Host "--- consent before every fixture: new files are recorded ---" -ForegroundColor Cyan
    Remove-Item -LiteralPath (Get-HordeCollectIndexPath) -Force
    Set-Gate '{ "schemaVersion": 1, "level": "usage", "enabledAt": "2026-09-01T00:00:00Z" }'
    $r1 = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    Check ($r1.recorded -eq $filled -and $r1.provisional -eq 0 -and @(Get-Records).Count -eq $filled) ("every transcript is recorded once (" + $r1.recorded + ")")
    $ix = Get-Index
    Check ($null -ne $ix -and @($ix["entries"].Keys).Count -eq $filled) "and the index holds one entry per transcript"
    # The record is summarize's record, plus how it was collected.
    $sum = Measure-HordeTranscriptFile -Path $planted -PriceTable (Read-HordePriceBook)
    $plantedRec = Get-HordeMetricsRecordPath -Adapter $sum.value.read.adapter -Name $sum.value.read.recordKey
    Check (Test-Path -LiteralPath $plantedRec -PathType Leaf) "the record is named by the transcript's own identity, its session id"
    $rec = @{ worker = $null; orc = $null; collection = @{} }; if (Test-Path -LiteralPath $plantedRec) { $rec = $ser.DeserializeObject([System.IO.File]::ReadAllText($plantedRec)) }
    $sumRec = $ser.DeserializeObject((ConvertTo-Json -InputObject $sum.value.record -Depth 30))
    Check ((ConvertTo-Json $rec["worker"] -Depth 30 -Compress) -eq (ConvertTo-Json $sumRec["worker"] -Depth 30 -Compress) -and (ConvertTo-Json $rec["orc"] -Depth 30 -Compress) -eq (ConvertTo-Json $sumRec["orc"] -Depth 30 -Compress)) "a collected record measures what summarize measures"
    Check ($rec["collection"]["provisional"] -eq $false -and $rec["collection"]["sourceBytes"] -eq (Get-Item -LiteralPath $planted).Length) "and says it is final, and how big its transcript was"

    Write-Host ""
    Write-Host "--- unchanged, changed, new, deleted ---" -ForegroundColor Cyan
    $snap = Get-StoreSnapshot
    $r2 = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    Check ($r2.unchanged -eq $filled -and $r2.read -eq 0 -and -not $r2.wroteIndex -and (Get-StoreSnapshot) -eq $snap) "a second run with nothing changed reads nothing and writes nothing, byte for byte"
    $recPath = Get-HordeMetricsRecordPath -Adapter $sum.value.read.adapter -Name ([System.IO.Path]::GetFileNameWithoutExtension($planted))
    # Either half of the key alone tells a change: a size with the old time, a time with the old size.
    $keepTime = (Get-Item -LiteralPath $planted).LastWriteTimeUtc
    [System.IO.File]::AppendAllText($planted, "`n")
    Set-Old $planted $keepTime
    Check ((Invoke-HordeMetricsCollect -Now $now -RepoRoot $root).read -eq 1) "a transcript whose size changed and whose time did not is read again"
    Set-Old $planted $keepTime.AddSeconds(1)
    Check ((Invoke-HordeMetricsCollect -Now $now -RepoRoot $root).read -eq 1) "and so is one whose time changed and whose size did not"
    $before = [System.IO.File]::ReadAllText($recPath)
    [System.IO.File]::AppendAllText($planted, "`n")
    Set-Old $planted $settledAt.AddMinutes(2)
    $r3 = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    Check ($r3.read -eq 1 -and $r3.recorded -eq 1 -and @(Get-Records).Count -eq $filled) "a changed transcript is read again, and replaces its record rather than adding one"
    Check ([System.IO.File]::ReadAllText($recPath) -ne $before) "CONTROL: the record did change (its transcript grew)"
    # A NEW transcript: a session of its own, made from the clean fixture with a new session id.
    $cleanSrc = @($copies | Where-Object { $_ -like "*clean*" -and [System.IO.Path]::GetFileName($_) -match '\A[0-9a-f-]{36}\.jsonl\z' })[0]
    $newId = "99999999-8888-4777-8666-555555555555"
    $newFile = Join-Path (Split-Path -Parent $cleanSrc) ($newId + ".jsonl")
    [System.IO.File]::WriteAllText($newFile, ([System.IO.File]::ReadAllText($cleanSrc) -replace [regex]::Escape([System.IO.Path]::GetFileNameWithoutExtension($cleanSrc)), $newId))
    Set-Old $newFile $settledAt
    $r4 = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    Check ($r4.read -eq 1 -and $r4.recorded -eq 1 -and @(Get-Records).Count -eq ($filled + 1) -and @($r4.rows)[0].record -like ("*/" + $newId)) "a new transcript is recorded, under its own session id"
    # MOVED (review of PR #70, F4): the same session in a renamed folder is the same record.
    $movedDir = Join-Path (Split-Path -Parent (Split-Path -Parent $newFile)) "renamed-project"
    [void][System.IO.Directory]::CreateDirectory($movedDir)
    $movedFile = Join-Path $movedDir (Split-Path -Leaf $newFile)
    Move-Item -LiteralPath $newFile -Destination $movedFile
    $r5 = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    Check ($r5.read -eq 1 -and $r5.removed -eq 1 -and @(Get-Records).Count -eq ($filled + 1) -and @($r5.rows)[0].record -like ("*/" + $newId)) "a moved transcript replaces its own record; it does not get a second one"
    $ix5 = Get-Index
    Check (@($ix5["entries"].Values | Where-Object { $_["record"] -like ("*/" + $newId) }).Count -eq 1 -and @($ix5["entries"].Keys).Count -eq ($filled + 1)) "and the index follows it: one entry, at its new place"
    # A COPY of a session is the same session: one record.
    $copyDir = Join-Path (Split-Path -Parent $planted) "elsewhere"
    [void][System.IO.Directory]::CreateDirectory($copyDir)
    $copyFile = Join-Path $copyDir (Split-Path -Leaf $planted)
    Copy-Item -LiteralPath $planted -Destination $copyFile
    Set-Old $copyFile $settledAt
    $r6 = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    Check ($r6.read -eq 1 -and @(Get-Records).Count -eq ($filled + 1)) "a copy of a session is the same session: it replaces that session's record, never adds one"
    Remove-Item -LiteralPath $copyFile -Force
    Remove-Item -LiteralPath $movedFile -Force
    $r7 = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    $ix7 = Get-Index
    Check ($r7.removed -eq 2 -and @($ix7["entries"].Keys).Count -eq $filled) "a deleted transcript leaves the index"
    Check (@(Get-Records).Count -eq ($filled + 1)) "and its record stays: the work it measured was done"
    $ixText = [System.IO.File]::ReadAllText((Get-HordeCollectIndexPath))
    Check (-not $ixText.Contains($env:USERPROFILE) -and -not $ixText.Contains($work) -and -not $ixText.ToLowerInvariant().Contains(($env:USERPROFILE.Replace('\', '/')).ToLowerInvariant())) "the index holds no path into the home, only each transcript's place in its engine's folder (review of PR #70, F6)"
    # The folders a harness names after a project spell out where the user works (review of #70, verification:
    # a real key held C--Users-<name>-...); a key keeps only a hash of the folder part.
    Check (-not $ixText.Contains("renamed-project") -and -not $ixText.Contains("fixtures") -and -not $ixText.Contains("elsewhere")) "and no folder name below the engine's transcript folder: only a hash of it, and the file's own name"

    Write-Host ""
    Write-Host "--- a transcript still being written is provisional ---" -ForegroundColor Cyan
    [System.IO.File]::AppendAllText($planted, "`n")
    Set-Old $planted $now.AddMinutes(-2)
    $p1 = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root -SettleMinutes 10
    $prec = $ser.DeserializeObject([System.IO.File]::ReadAllText($recPath))
    Check ($p1.provisional -eq 1 -and $prec["collection"]["provisional"] -eq $true -and "$($prec["collection"]["why"])" -like "*within the last 10 minutes*") "one written 2 minutes ago is recorded as provisional, and the record says why"
    $snap = Get-StoreSnapshot
    $p2 = Invoke-HordeMetricsCollect -Now $now.AddMinutes(5) -RepoRoot $root -SettleMinutes 10
    Check ($p2.read -eq 0 -and (Get-StoreSnapshot) -eq $snap) "while it has not settled and has not changed, it is left alone"
    $p3 = Invoke-HordeMetricsCollect -Now $now.AddMinutes(20) -RepoRoot $root -SettleMinutes 10
    $frec = $ser.DeserializeObject([System.IO.File]::ReadAllText($recPath))
    Check ($p3.read -eq 1 -and $p3.provisional -eq 0 -and $frec["collection"]["provisional"] -eq $false) "once it has settled it is collected again, and the record is final"
    $p4 = Invoke-HordeMetricsCollect -Now $now.AddMinutes(30) -RepoRoot $root -SettleMinutes 10
    Check ($p4.read -eq 0 -and -not $p4.wroteIndex) "CONTROL: and then it is unchanged"

    Write-Host ""
    Write-Host "--- one run at a time; never inside an engine's folder ---" -ForegroundColor Cyan
    $held = [System.IO.File]::Open((Join-Path (Get-HordeMetricsDir) "collect.lock"), [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        [System.IO.File]::AppendAllText($planted, "`n"); Set-Old $planted $settledAt.AddMinutes(3)
        $snap = Get-StoreSnapshot
        $busy = Invoke-HordeMetricsCollect -Now $now.AddMinutes(40) -RepoRoot $root
        Check ($busy.state -eq "busy" -and (Get-StoreSnapshot) -eq $snap) "while another run holds the lock, a run does nothing"
    } finally { $held.Dispose() }
    Check ((Invoke-HordeMetricsCollect -Now $now.AddMinutes(40) -RepoRoot $root).read -eq 1) "CONTROL: once it is released, the change is collected"
    $engineRoot = @(@($stores.value | Where-Object { @($_.transcripts).Count -gt 0 })[0].roots)[0]
    $env:HORDE_HOME = Join-Path $engineRoot "horde-home"
    Set-Gate '{ "schemaVersion": 1, "level": "usage", "enabledAt": "2026-09-01T00:00:00Z" }'
    $snapIn = (@(Get-ChildItem -LiteralPath $engineRoot -File -Recurse | ForEach-Object { $_.FullName })) -join "`n"
    $inside = Invoke-HordeMetricsCollect -Now $now -RepoRoot $root
    Check ($inside.state -eq "refused" -and $inside.reason -like "*inside a harness*") "a home inside an engine's folder is refused"
    Check (((@(Get-ChildItem -LiteralPath $engineRoot -File -Recurse | ForEach-Object { $_.FullName })) -join "`n") -eq $snapIn) "and nothing but the gate file was written there"
    $env:HORDE_HOME = Join-Path $work "home"

    Write-Host ""
    Write-Host "--- one bad file never stops a run, and every failure is said (review of PR #70) ---" -ForegroundColor Cyan
    $later = $now.AddMinutes(100)
    # F3: a transcript whose identity cannot name a record.
    $subCopy = @($copies | Where-Object { $_ -like "*subagents*" })[0]
    $badName = Join-Path (Split-Path -Parent $subCopy) "agent-bad name.jsonl"
    Copy-Item -LiteralPath $subCopy -Destination $badName
    Set-Old $badName $settledAt
    $b1 = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root
    Check ($b1.state -eq "done" -and $b1.notRecorded -eq 1 -and $b1.wroteIndex) "a transcript whose identity is not a record name is not recorded, and the run goes on to write its index"
    $b2 = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root
    Check ($b2.state -eq "done" -and $b2.read -eq 0) "and the next run does not stumble on it again"
    Remove-Item -LiteralPath $badName -Force
    # F3: a record that cannot be written fails that file only.
    $id2 = "77777777-6666-4555-8444-333333333333"
    $file2 = Join-Path (Split-Path -Parent $cleanSrc) ($id2 + ".jsonl")
    [System.IO.File]::WriteAllText($file2, ([System.IO.File]::ReadAllText($cleanSrc) -replace [regex]::Escape([System.IO.Path]::GetFileNameWithoutExtension($cleanSrc)), $id2))
    Set-Old $file2 $settledAt
    $cleanAdapter = (Measure-HordeTranscriptFile -Path $cleanSrc -PriceTable $noBook).value.read.adapter
    $blocker = Get-HordeMetricsRecordPath -Adapter $cleanAdapter -Name $id2
    [void][System.IO.Directory]::CreateDirectory($blocker)
    $b3 = $null; try { $b3 = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root } catch { Write-Host ("    the run threw: " + $_.Exception.Message) }
    Check ($null -ne $b3 -and $b3.state -eq "done" -and $b3.failed -eq 1 -and $b3.wroteIndex) "a record that cannot be written fails that one file; the run finishes and writes its index"
    Remove-Item -LiteralPath $blocker -Force
    Set-Old $file2 $settledAt.AddMinutes(5)
    $b4 = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root
    Check ($b4.recorded -eq 1 -and (Test-Path -LiteralPath $blocker -PathType Leaf)) "CONTROL: once it can be written, it is"
    # F7: a transcript that changes while it is read is provisional, whatever its time said.
    $origMeasure = ${function:Measure-HordeTranscriptFile}
    function Measure-HordeTranscriptFile { param($Path, $PriceTable, $From = $null, $To = $null) [System.IO.File]::AppendAllText($Path, "`n"); & $script:origMeasure -Path $Path -PriceTable $PriceTable }
    try {
        Set-Old $file2 $settledAt.AddMinutes(6)
        $b5 = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root
    } finally { Set-Item -Path function:Measure-HordeTranscriptFile -Value $origMeasure }
    $r2rec = $ser.DeserializeObject([System.IO.File]::ReadAllText($blocker))
    Check ($b5.provisional -eq 1 -and $r2rec["collection"]["provisional"] -eq $true -and "$($r2rec["collection"]["why"])" -like "*changed while it was read*") "a transcript that grew while it was read is recorded as provisional, and says why"
    Set-Old $file2 $settledAt.AddMinutes(7)
    $b6 = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root
    Check ($b6.read -eq 1 -and $b6.provisional -eq 0) "CONTROL: read again unchanged, it is final"
    # F9: a provisional record whose transcript disappears is flagged, not left provisional forever.
    Set-Old $file2 $later.AddMinutes(-1)
    [System.IO.File]::AppendAllText($file2, "`n"); Set-Old $file2 $later.AddMinutes(-1)
    $b7 = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root
    Check ($b7.provisional -eq 1) "CONTROL: the transcript is provisional now"
    Remove-Item -LiteralPath $file2 -Force
    $b8 = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root
    $gone = $ser.DeserializeObject([System.IO.File]::ReadAllText($blocker))
    Check ($b8.removed -eq 1 -and $gone["collection"]["sourceGone"] -eq $true -and "$($gone["collection"]["why"])" -like "*can never be made final*") "when its transcript is gone, the provisional record says it can never be made final"
    # F9: a recorded transcript whose time moves to before consent is still read, not skipped.
    Set-Old $planted ([datetime]::Parse("2026-08-01T00:00:00Z").ToUniversalTime())
    $b9 = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root
    Check ($b9.read -eq 1) "a recorded transcript whose time moved to before consent is read again, not dropped as pre-consent"
    Set-Old $planted $settledAt.AddMinutes(8)
    # F8: a lock that cannot be opened is a failure, said so, never a silent "busy".
    Remove-Item -LiteralPath (Join-Path (Get-HordeMetricsDir) "collect.lock") -Force -ErrorAction SilentlyContinue
    [void][System.IO.Directory]::CreateDirectory((Join-Path (Get-HordeMetricsDir) "collect.lock"))
    $lk = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root
    Check ($lk.state -eq "refused" -and $lk.reason -like "*lock could not be opened*") "a lock that cannot be opened (here, a folder in its place) refuses the run and says why"
    Remove-Item -LiteralPath (Join-Path (Get-HordeMetricsDir) "collect.lock") -Force

    Write-Host ""
    Write-Host "--- a large backlog: progress is kept, and a run ends within its budget (review of #70, NEW-1) ---" -ForegroundColor Cyan
    $backlogDir = Join-Path (Split-Path -Parent $cleanSrc) "backlog"
    [void][System.IO.Directory]::CreateDirectory($backlogDir)
    $cleanText = [System.IO.File]::ReadAllText($cleanSrc)
    $cleanId = [System.IO.Path]::GetFileNameWithoutExtension($cleanSrc)
    $backlogIds = @()
    for ($i = 0; $i -lt 30; $i++) {
        $bid = "b0000000-0000-4000-8000-" + $i.ToString("000000000000")
        $backlogIds += $bid
        $bf = Join-Path $backlogDir ($bid + ".jsonl")
        [System.IO.File]::WriteAllText($bf, ($cleanText -replace [regex]::Escape($cleanId), $bid))
        Set-Old $bf $settledAt
    }
    $countBacklog = { $ix = Get-Index; if ($null -eq $ix) { 0 } else { @($ix["entries"].Values | Where-Object { "$($_["record"])" -match '/b0000000-' }).Count } }
    # A run that is killed keeps what it finished: the index is committed after every transcript.
    $envsK = @{ HORDE_HOME = $env:HORDE_HOME; USERPROFILE = $env:USERPROFILE }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $root "horde.ps1") + "`" metrics collect"
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    foreach ($k in $envsK.Keys) { $psi.EnvironmentVariables[$k] = $envsK[$k] }
    $kp = [System.Diagnostics.Process]::Start($psi)
    $null = $kp.StandardOutput.ReadToEndAsync(); $null = $kp.StandardError.ReadToEndAsync()
    $deadline = [datetime]::UtcNow.AddMinutes(5)
    $committed = 0
    while (-not $kp.HasExited -and [datetime]::UtcNow -lt $deadline) {
        try { $committed = & $countBacklog } catch { $committed = 0 }
        if ($committed -ge 3) { break }
        Start-Sleep -Milliseconds 100
    }
    $killedMidway = (-not $kp.HasExited)
    if ($killedMidway) { $kp.Kill(); $kp.WaitForExit() }
    $kp.Dispose()
    $committed = & $countBacklog
    Check ($killedMidway -and $committed -ge 3 -and $committed -lt 30) ("a run killed in the middle of a backlog has already committed what it finished (" + $committed + " of 30)")
    $resume = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root
    $recIds = @(Get-Records | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } | Where-Object { $_ -like "b0000000-*" })
    $resumedBacklog = @($resume.rows | Where-Object { $_.record -match '/b0000000-' }).Count
    Check ($resumedBacklog -eq (30 - $committed) -and $resume.state -eq "done") ("the next run reads only the backlog's transcripts that were not committed (" + $resumedBacklog + " = 30 - " + $committed + ")")
    Check ($recIds.Count -eq 30 -and @($recIds | Sort-Object -Unique).Count -eq 30 -and (& $countBacklog) -eq 30) "and every transcript of the backlog is recorded exactly once"
    # A run ends cleanly within its budget, before a scheduler's time limit would kill it.
    foreach ($bid in $backlogIds[0..4]) { $bf = Join-Path $backlogDir ($bid + ".jsonl"); [System.IO.File]::AppendAllText($bf, "`n"); Set-Old $bf $settledAt.AddMinutes(9) }
    $bud = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root -MaxFiles 2
    Check ($bud.state -eq "done" -and $bud.read -eq 2 -and $bud.stoppedEarly -and $bud.reason -like "*budget*") "a run with a budget of 2 files reads 2, stops cleanly, and says why"
    Check ((& $countBacklog) -eq 30 -and $bud.removed -eq 0) "and forgets nothing it did not reach"
    $bud2 = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root
    Check ($bud2.read -eq 3 -and -not $bud2.stoppedEarly) "the next run picks up the other 3"
    $budS = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root -MaxSeconds 0
    Check ($budS.state -eq "done" -and $budS.read -eq 0) "CONTROL: a time budget is honoured too (0 seconds: nothing read, nothing lost)"
    foreach ($bid in $backlogIds) { Remove-Item -LiteralPath (Join-Path $backlogDir ($bid + ".jsonl")) -Force }
    $null = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root

    Write-Host ""    Write-Host "--- one file too big for a run never starves the rest (review of #70, the budget) ---" -ForegroundColor Cyan
    # A run's budget is checked INSIDE a file too: a giant file is abandoned uncommitted ("deferred"),
    # read last in the next run, and after three deferrals in a row is "tooLarge": skipped, and said.
    $gDir = Join-Path (Split-Path -Parent $cleanSrc) "giant-backlog"
    [void][System.IO.Directory]::CreateDirectory($gDir)
    $giant = Join-Path $gDir "00000000-0000-4000-8000-000000000000.jsonl"
    $gw = New-Object System.IO.StreamWriter($giant, $false, (New-Object System.Text.UTF8Encoding($false)))
    try {
        $gt0 = [datetime]::Parse("2026-09-30T00:00:00Z").ToUniversalTime()
        for ($i = 0; $i -lt 150000; $i++) {
            $gw.WriteLine('{"type":"assistant","sessionId":"00000000-0000-4000-8000-000000000000","timestamp":"' + $gt0.AddSeconds($i * 2).ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + '","message":{"id":"g' + $i + '","model":"model-a","content":[{"type":"tool_use","id":"gt' + $i + '","name":"Bash","input":{}}],"usage":{"input_tokens":3,"cache_read_input_tokens":1000,"cache_creation_input_tokens":10,"output_tokens":50}}}')
            $gw.WriteLine('{"type":"user","sessionId":"00000000-0000-4000-8000-000000000000","timestamp":"' + $gt0.AddSeconds($i * 2 + 1).ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + '","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"gt' + $i + '","content":"ok"}]}}')
        }
    } finally { $gw.Dispose() }
    Set-Old $giant $settledAt
    $smallIds = @()
    for ($i = 0; $i -lt 4; $i++) {
        $sid = "c0000000-0000-4000-8000-" + $i.ToString("000000000000")
        $smallIds += $sid
        $sf = Join-Path $gDir ($sid + ".jsonl")
        [System.IO.File]::WriteAllText($sf, ($cleanText -replace [regex]::Escape($cleanId), $sid))
        Set-Old $sf $settledAt
    }
    $smallsRecorded = { @(Get-Records | Where-Object { $_.Name -like "c0000000-*" }).Count }
    $giantEntry = { $ix = Get-Index; $k = @($ix["entries"].Keys | Where-Object { $_ -like "*/00000000-0000-4000-8000-000000000000.jsonl" }); if ($k.Count -eq 1) { $ix["entries"][$k[0]] } else { $null } }
    $sw1 = [System.Diagnostics.Stopwatch]::StartNew()
    $g1 = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root -MaxSeconds 8
    $sw1.Stop()
    Check ($g1.state -eq "done" -and $g1.stoppedEarly -and $sw1.Elapsed.TotalSeconds -lt 40) ("a run whose budget runs out inside a file stops within its budget, not when the file ends (" + [math]::Round($sw1.Elapsed.TotalSeconds) + " s for an 8 s budget)")
    $ge1 = & $giantEntry
    Check ($null -ne $ge1 -and $ge1["outcome"] -eq "deferred" -and @(Get-Records | Where-Object { $_.Name -like "00000000-*" }).Count -eq 0) "the file it was reading is deferred, not committed: no record, an index entry that says so"
    $g2 = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root -MaxSeconds 8
    Check ((& $smallsRecorded) -eq 4) ("a deferred file is read last: within two runs every other transcript is recorded (" + (& $smallsRecorded) + " of 4)")
    # A deferral counts only when the file was attempted: a run whose budget the others spent first does
    # not count against it. Each run from here reaches it, since the others are recorded.
    $attempts = 0
    for ($k = 0; $k -lt 4; $k++) {
        $ge = & $giantEntry
        if ($null -ne $ge -and $ge["outcome"] -eq "tooLarge") { break }
        $null = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root -MaxSeconds 8
        $attempts++
    }
    $ge3 = & $giantEntry
    Check ($null -ne $ge3 -and $ge3["outcome"] -eq "tooLarge" -and [int]$ge3["deferrals"] -eq 3) ("deferred three times in a row, it is marked too large (" + $attempts + " more runs)")
    $g4 = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root -MaxSeconds 8
    Check ($g4.read -eq 0 -and $g4.tooLarge -eq 1 -and -not $g4.stoppedEarly) "and is then skipped, counted, and the run goes on"
    $sumOut = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "summarize", $cleanSrc) -Env @{ HORDE_HOME = $env:HORDE_HOME; USERPROFILE = $env:USERPROFILE }
    Check ($sumOut.out -like "*too large*00000000-0000-4000-8000-000000000000.jsonl*") "summarize says, loudly, which transcript collect could not read within a run"
    Remove-Item -LiteralPath $gDir -Recurse -Force
    $null = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root

    Write-Host ""
    Write-Host "--- a temp file left by a killed write is cleaned up, and only Horde's own ---" -ForegroundColor Cyan
    $orphan = Join-Path (Get-HordeMetricsDir) (".collect-index.json." + [guid]::NewGuid().ToString("N") + ".tmp")
    $notOurs = Join-Path (Get-HordeMetricsDir) "notes.tmp"
    [System.IO.File]::WriteAllText($orphan, "half"); [System.IO.File]::WriteAllText($notOurs, "mine")
    $null = Invoke-HordeMetricsCollect -Now $later -RepoRoot $root
    Check (-not (Test-Path -LiteralPath $orphan) -and (Test-Path -LiteralPath $notOurs)) "an orphaned temp file of Horde's own pattern is removed at the start of a run; a file that only looks like one is left"
    Remove-Item -LiteralPath $notOurs -Force

    Write-Host ""    Write-Host "--- through the real horde command ---" -ForegroundColor Cyan
    $envs = @{ HORDE_HOME = $env:HORDE_HOME; USERPROFILE = $env:USERPROFILE }
    [System.IO.File]::AppendAllText($planted, "`n"); Set-Old $planted $settledAt.AddMinutes(4)
    $c1 = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "collect") -Env $envs
    Check ($c1.code -eq 0 -and $c1.out -like "*1 recorded (0 provisional)*") "horde metrics collect records the one changed transcript and says so"
    $c2 = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "collect") -Env $envs
    Check ($c2.code -eq 0 -and $c2.out -like "*nothing new or changed, nothing written*") "and run again, says it wrote nothing"
    Set-Gate '{ not json'
    $c3 = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "collect") -Env $envs
    Check ($c3.code -eq 1 -and $c3.out -like "*refused*") "a refused gate fails the command, so a scheduler's log shows it"
} finally {
    foreach ($k in @($saved.Keys)) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "collect records what is new or changed, once, only with consent, and never in an engine's folder"
