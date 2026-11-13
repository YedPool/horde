# DOES WHAT COLLECT COMMITTED SURVIVE BEING KILLED AT ANY POINT?
#
# Review of PR #70: 40 random kills of `horde metrics collect` over a 1,000-transcript backlog, with the
# index read under the collect lock before and after each; kill 5 took the committed count from 35 to 0.
# The replace was not atomic: a kill inside it left no index, and the next run's temp cleanup deleted the
# temp that held the new one. This is that probe, kept as a suite: random kills, each read under the
# lock, and the committed count must never go down, the index must never be missing or unreadable once
# it has existed, and a final run must finish the backlog with each transcript recorded once and no temp
# file left.
#
# Fake profile and fake HORDE_HOME, made and removed here (CONTRIBUTING 9). The backlog is one engine's
# clean fixture copied under new session ids, found by folder, never named (CONTRIBUTING 14).
#
# HEAVY: about five minutes. It kills only the processes it started.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "ReadShared", "Home", "Transcript", "MetricsStore")) { . (Join-Path $root ("core\" + $f + ".ps1")) }

$work = Join-Path $env:TEMP ("horde-kills-" + [guid]::NewGuid().ToString("N"))
$saved = @{ HORDE_HOME = $env:HORDE_HOME; USERPROFILE = $env:USERPROFILE }
$storeVars = @()
foreach ($sj in @(Get-ChildItem -LiteralPath (Join-Path $root "agents") -Directory | ForEach-Object { Join-Path $_.FullName "stores.json" } | Where-Object { Test-Path -LiteralPath $_ })) {
    foreach ($r in @((ConvertFrom-HordeJsonObject -Text ([System.IO.File]::ReadAllText($sj)))["roots"])) { if ($r["env"] -is [string]) { $storeVars += $r["env"] } }
}
foreach ($v in $storeVars) { $saved[$v] = [Environment]::GetEnvironmentVariable($v); [Environment]::SetEnvironmentVariable($v, $null) }

function Read-IndexLocked {
    # Hold the collect lock, so no collect is mid-write, and read the index: { status; committed }.
    $m = Get-HordeMetricsDir
    $lk = $null
    for ($i = 0; $i -lt 200 -and $null -eq $lk; $i++) { try { $lk = [System.IO.File]::Open((Join-Path $m "collect.lock"), "OpenOrCreate", "ReadWrite", "None") } catch { Start-Sleep -Milliseconds 50 } }
    if ($null -eq $lk) { return [pscustomobject]@{ status = "lock not taken"; committed = -1 } }
    try {
        $p = Join-Path $m "collect-index.json"
        if (-not (Test-Path -LiteralPath $p)) { return [pscustomobject]@{ status = "missing"; committed = 0 } }
        $d = $null
        try { $d = ConvertFrom-HordeJsonObject -Text ([System.IO.File]::ReadAllText($p)) } catch { return [pscustomobject]@{ status = "unreadable"; committed = -1 } }
        return [pscustomobject]@{ status = "ok"; committed = @($d["entries"].Values | Where-Object { "$($_["record"])" -ne "" }).Count }
    } finally { $lk.Dispose() }
}

try {
    $env:USERPROFILE = New-HordeTestProfile (Join-Path $work "profile")
    $env:HORDE_HOME = Join-Path $work "home"
    $stores = Get-HordeAgentStores -Root $root
    # A fixture whose own file name is its identity inside it, so new names make new sessions.
    $src = $null; $dest = $null
    foreach ($s in @($stores.value)) {
        if (@($s.transcripts).Count -eq 0) { continue }
        $fx = Join-Path $root ("agents\" + $s.agent + "\test\fixtures\metrics\clean")
        foreach ($c in @(Get-ChildItem -LiteralPath $fx -File -ErrorAction SilentlyContinue)) {
            if ([System.IO.File]::ReadAllText($c.FullName).Contains($c.BaseName)) { $src = $c; $dest = Join-Path @($s.transcripts)[0].dir "kills"; break }
        }
        if ($null -ne $src) { break }
    }
    Check ($null -ne $src) "CONTROL: a fixture whose name is its identity is found"
    [void][System.IO.Directory]::CreateDirectory($dest)
    $text = [System.IO.File]::ReadAllText($src.FullName)
    $n = 800
    for ($i = 0; $i -lt $n; $i++) {
        $id = "cdcdcdcd-3333-4444-8555-" + $i.ToString("000000000000")
        $f = Join-Path $dest ($id + $src.Extension)
        [System.IO.File]::WriteAllText($f, $text.Replace($src.BaseName, $id))
        (Get-Item -LiteralPath $f).LastWriteTimeUtc = [datetime]::UtcNow.AddHours(-1)
    }
    [void][System.IO.Directory]::CreateDirectory((Get-HordeMetricsDir))
    [System.IO.File]::WriteAllText((Join-Path (Get-HordeMetricsDir) "gate.json"), '{ "schemaVersion": 1, "level": "usage", "enabledAt": "2026-09-01T00:00:00Z" }')

    $rnd = New-Object System.Random 703
    $drops = 0; $invalid = 0; $killed = 0; $seen = $false; $log = @()
    for ($k = 0; $k -lt 40; $k++) {
        $before = Read-IndexLocked
        $psi = New-Object System.Diagnostics.ProcessStartInfo "powershell.exe", ("-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $root "horde.ps1") + "`" metrics collect -SettleMinutes 0")
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $null = $p.StandardOutput.ReadToEndAsync(); $null = $p.StandardError.ReadToEndAsync()
        Start-Sleep -Milliseconds ($rnd.Next(1500, 6000))
        $running = -not $p.HasExited
        if ($running) { $p.Kill(); $killed++ }
        $p.WaitForExit(); $p.Dispose()
        $after = Read-IndexLocked
        if ($after.status -eq "ok") { $seen = $true }
        if ($after.status -ne "ok" -and $seen) { $invalid++ }
        if ($after.committed -lt $before.committed) { $drops++ }
        $log += ("" + $before.committed + ">" + $after.committed + $(if ($after.status -ne "ok") { "(" + $after.status + ")" } else { "" }) + $(if ($running) { "" } else { "x" }))
        if ($after.committed -ge $n) { break }
    }
    Write-Host ("KILLS: " + $log.Count + " runs, " + $killed + " killed while running; before>after: " + ($log -join " "))
    Check ($killed -ge 20) ("CONTROL: most runs were killed while running (" + $killed + " of " + $log.Count + ")")
    Check ($drops -eq 0) ("the committed count never went down across " + $log.Count + " kills (" + $drops + " drops)")
    Check ($invalid -eq 0) ("once it existed, the index was never missing or unreadable after a kill (" + $invalid + " times)")
    $psi = New-Object System.Diagnostics.ProcessStartInfo "powershell.exe", ("-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $root "horde.ps1") + "`" metrics collect -SettleMinutes 0")
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi); $out = $p.StandardOutput.ReadToEnd(); $null = $p.StandardError.ReadToEnd(); $p.WaitForExit(); $code = $p.ExitCode; $p.Dispose()
    $fin = Read-IndexLocked
    $records = @(Get-ChildItem -LiteralPath (Join-Path (Get-HordeMetricsDir) "summaries") -File -Recurse -Filter "cdcdcdcd-*").Count
    $temps = @(Get-ChildItem -LiteralPath (Get-HordeMetricsDir) -File -Recurse -Force | Where-Object { $_.Name -like "*.tmp" }).Count
    Write-Host ("FINAL: exit " + $code + ", committed " + $fin.committed + ", records " + $records + ", temps " + $temps + "; " + ($out -replace "\s+", " "))
    Check ($code -eq 0 -and $fin.committed -eq $n -and $records -eq $n) ("a final run finishes the backlog: every transcript committed and recorded once (" + $fin.committed + ", " + $records + " of " + $n + ")")
    # A temp NEWER than its file is a write that a kill stopped before its rename: never committed, and
    # kept until a later commit makes it older (core/MetricsCollect.ps1, Restore-HordeMetricsTemps).
    $ixAt = (Get-Item -LiteralPath (Join-Path (Get-HordeMetricsDir) "collect-index.json")).LastWriteTimeUtc
    $olderTemps = @(Get-ChildItem -LiteralPath (Get-HordeMetricsDir) -File -Force | Where-Object { $_.Name -like ".collect-index.json.*.tmp" -and $_.LastWriteTimeUtc -lt $ixAt }).Count
    Check ($olderTemps -eq 0) ("no temp older than the index is left (" + $olderTemps + " of " + $temps + " temps)")
    $one = @(Get-ChildItem -LiteralPath $dest -File)[0].FullName
    [System.IO.File]::AppendAllText($one, "`n")
    $p = [System.Diagnostics.Process]::Start($psi); $null = $p.StandardOutput.ReadToEnd(); $null = $p.StandardError.ReadToEnd(); $p.WaitForExit(); $p.Dispose()
    $temps2 = @(Get-ChildItem -LiteralPath (Get-HordeMetricsDir) -File -Recurse -Force | Where-Object { $_.Name -like "*.tmp" }).Count
    Check ($temps2 -eq 0) ("and once a run commits again, no temp file is left at all (" + $temps2 + ")")
} finally {
    foreach ($k in @($saved.Keys)) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "what collect committed survives a kill at any point, and a final run finishes the backlog with nothing left over"
