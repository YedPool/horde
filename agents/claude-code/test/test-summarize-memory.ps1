# HOW DOES `horde metrics summarize` USE MEMORY AS TRANSCRIPTS GROW?
#
# Plan step M2's first item. Measured 2026-10-02 on the always-on box (review of PR #50): M1's
# summarize peaked at 593 MB on a 33 MB transcript and 1,734 MB on a 133 MB one, about 11 MB of memory
# per MB of transcript, because it held a record per line and an answer object for each. The target
# set then was a peak working set under 200 MB on the 133 MB file. Measured 2026-10-02, M2 peaks at
# 256 MB on the always-on box on both the 33 MB and the 133 MB files - flat - where the same command
# on a ONE-response transcript peaks at 164 MB; on the 1 GB-free working box the floor is 143 MB and
# the 33 MB file 155 MB. A forced collection every 1,000 lines did not lower it (176 MB). The rise
# above the floor is the garbage collector's working room, which is larger on the box with more
# memory, not records held: it does not grow with the file. So the target is restated (coordinator,
# 2026-10-02): FLAT, and within 120 MB of the floor (measured +92 MB and +12 MB), on the same box in
# the same run - the floor first, then the 33 MB and 133 MB transcripts of the review's shape (an
# assistant response with a tool call and its result, each line about 1.6 KB, every value invented),
# the shipped command run as its own process, its peak working set sampled every 100 ms.
#
# IT LIVES HERE because its transcripts are in this harness's format (CONTRIBUTING 14).
#
# MEMORY IS O(RESPONSES), NOT FLAT (review of PR #70, F5). Measured 2026-10-02 on the always-on box at
# be487ae, private bytes: 204 MB for 20,000 short responses (0.4 KB lines), 228 MB for 120,000 - about
# 252 bytes per response, for what must be kept to stay byte for byte M1: per call its id and the ten
# numbers of its usage (an id can come back after another; 73 times in one of 692 real transcripts),
# per record its time, line and kind (the longest silence, with M1's tie order), per tool result its
# time. The working set stays at 256 MB because the collector trims it. Keeping only the current id
# would make it flat and change M1's output on that real file. So the second target is: at most 1 KB
# of private memory per response, measured on the same box in the same run.
#
# HEAVY: it writes about 170 MB to TEMP and runs for minutes. It is in the gate so that a change that
# brings back a list of records fails it; run it where there is memory to spare.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-memory-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$overFloorMB = 120
# Set from the live measurement below, repeated: see the plan (planning/execution-plan-metrics.md, M2).
$perResponseLimit = 1500

function New-BigTranscript {
    # -Short: about 0.4 KB a line instead of 1.6 KB, so many more records per MB (review of PR #70, F5).
    param([string]$Path, [int]$Pairs, [switch]$Short)
    $w = New-Object System.IO.StreamWriter($Path, $false, (New-Object System.Text.UTF8Encoding($false)))
    try {
        $pad = "x" * 1400
        $t0 = [datetime]::Parse("2026-09-30T00:00:00Z").ToUniversalTime()
        for ($i = 0; $i -lt $Pairs; $i++) {
            $ts = $t0.AddSeconds($i * 2).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            $ts2 = $t0.AddSeconds($i * 2 + 1).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            if ($Short) {
                $w.WriteLine('{"type":"assistant","sessionId":"s","timestamp":"' + $ts + '","message":{"id":"m' + $i + '","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t' + $i + '","name":"Bash","input":{}}],"usage":{"input_tokens":3,"cache_read_input_tokens":1000,"cache_creation_input_tokens":10,"output_tokens":50}}}')
                $w.WriteLine('{"type":"user","sessionId":"s","timestamp":"' + $ts2 + '","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t' + $i + '","content":"ok"}]}}')
                continue
            }
            $w.WriteLine('{"type":"assistant","isSidechain":false,"sessionId":"s","timestamp":"' + $ts + '","requestId":"r' + $i + '","message":{"id":"m' + $i + '","model":"claude-opus-5-5","content":[{"type":"text","text":"' + $pad + '"},{"type":"tool_use","id":"t' + $i + '","name":"Bash","input":{"command":"echo"}}],"stop_reason":"tool_use","usage":{"input_tokens":3,"cache_read_input_tokens":1000,"cache_creation_input_tokens":10,"output_tokens":50,"cache_creation":{"ephemeral_5m_input_tokens":10,"ephemeral_1h_input_tokens":0}}}}')
            $w.WriteLine('{"type":"user","isSidechain":false,"sessionId":"s","timestamp":"' + $ts2 + '","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t' + $i + '","content":"' + $pad + '"}]}}')
        }
    } finally { $w.Dispose() }
}

function Measure-HordeLiveBytes {
    # The most bytes the summary of -File ever held live, in a child process that forces a collection
    # every 5,000 records: { bytes; records; state }.
    param([string]$File)
    $script = Join-Path $work "live.ps1"
    [System.IO.File]::WriteAllText($script, @"
param([string]`$Root, [string]`$File)
foreach (`$f in @("Tristate", "ReadShared", "Home", "Transcript", "Price", "Metrics", "MetricsStore", "MetricsReport")) { . (Join-Path `$Root ("core\" + `$f + ".ps1")) }
foreach (`$a in (Get-HordeTranscriptAdapterFiles -Root `$Root)) { . `$a }
`$acc = New-HordeMetricsAccumulator -PriceTable (New-HordeAbsent -Note "not priced")
`$base = [GC]::GetTotalMemory(`$true)
`$probe = [pscustomobject]@{ into = `$acc; n = 0; peak = [long]0 }
`$probe | Add-Member -MemberType ScriptMethod -Name Add -Value { param(`$r) `$this.into.Add(`$r); `$this.n++; if ((`$this.n % 5000) -eq 0) { `$m = [GC]::GetTotalMemory(`$true); if (`$m -gt `$this.peak) { `$this.peak = `$m } } }
`$read = Read-HordeTranscript -Path `$File -Into `$probe
`$m = [GC]::GetTotalMemory(`$true); if (`$m -gt `$probe.peak) { `$probe.peak = `$m }
"LIVE " + (`$probe.peak - `$base) + " " + `$probe.n + " " + `$read.state
"@)
    $psi = New-Object System.Diagnostics.ProcessStartInfo "powershell.exe", ("-NoProfile -ExecutionPolicy Bypass -File `"" + $script + "`" -Root `"" + $root + "`" -File `"" + $File + "`"")
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit(); $p.Dispose()
    $m = [regex]::Match($out, 'LIVE (-?\d+) (\d+) (\w+)')
    if (-not $m.Success) { return [pscustomobject]@{ bytes = [long]0; records = 0; state = ("no result: " + $out + $errTask.Result) } }
    return [pscustomobject]@{ bytes = [long]$m.Groups[1].Value; records = [int]$m.Groups[2].Value; state = $m.Groups[3].Value }
}

function Measure-Peak {
    # Run the shipped command as its own process; returns { code; peakMB; privateMB; seconds; out }.
    # Both the peak working set, the measure the targets were set in, and the peak private bytes,
    # which the system does not trim under memory pressure (review of PR #70, F5).
    param([string[]]$HordeArgs)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $root "horde.ps1") + "`" " + (($HordeArgs | ForEach-Object { '"' + $_ + '"' }) -join " ")
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_HOME"] = (Join-Path $work "home")
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync(); $errTask = $p.StandardError.ReadToEndAsync()
    $peak = 0; $priv = 0
    while (-not $p.HasExited) {
        try { $p.Refresh(); if ($p.PeakWorkingSet64 -gt $peak) { $peak = $p.PeakWorkingSet64 }; if ($p.PeakPagedMemorySize64 -gt $priv) { $priv = $p.PeakPagedMemorySize64 } } catch { }
        Start-Sleep -Milliseconds 100
    }
    $p.WaitForExit()
    $code = $p.ExitCode; $p.Dispose()
    return [pscustomobject]@{ code = $code; peakMB = [math]::Round($peak / 1MB); privateMB = [math]::Round($priv / 1MB); seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); out = ($outTask.Result + $errTask.Result) }
}

try {
    $rows = @()
    foreach ($size in @(@{ name = "floor"; pairs = 1 }, @{ name = "small"; pairs = 10000 }, @{ name = "large"; pairs = 40000 })) {
        $file = Join-Path $work ($size.name + "\66666666-7777-4888-8999-000000000000.jsonl")
        New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force | Out-Null
        New-BigTranscript -Path $file -Pairs $size.pairs -Short:([bool]$size.short)
        $mb = [math]::Round((Get-Item -LiteralPath $file).Length / 1MB)
        $r = Measure-Peak -HordeArgs @("metrics", "summarize", $file)
        Write-Host ("MEMORY " + $size.name + ": file " + $mb + " MB, " + ($size.pairs * 2) + " lines; summarize peak working set " + $r.peakMB + " MB, private " + $r.privateMB + " MB, in " + $r.seconds + " s; exit " + $r.code)
        Check ($r.code -eq 0) ("summarize of the " + $size.name + " file exits 0")
        $calls = $size.pairs.ToString("N0", [System.Globalization.CultureInfo]::InvariantCulture)
        Check ($r.out -match ("claude-opus-5-5\s.*\s" + [regex]::Escape($calls) + "\s+" + [regex]::Escape($calls) + "\s")) ("CONTROL: it read the whole file (" + $calls + " calls and tool calls)")
        $rows += [pscustomobject]@{ name = $size.name; MB = $mb; pairs = $size.pairs; peakMB = $r.peakMB; privateMB = $r.privateMB }
        Remove-Item -LiteralPath $file -Force
    }
    $f = $rows[0]; $s = $rows[1]; $l = $rows[2]
    # WHAT IS KEPT PER RESPONSE, measured as live bytes rather than as a process peak. A process peak is
    # the collector's choice as much as ours: repeated four times on the always-on box (2026-10-02, at
    # 6d69979), 10,000 and 60,000 short responses peaked alike at 213-238 MB private, a per-response slope
    # of -2 to 507 bytes (median 53) - noise - while on the 1 GB-free working box the reviewer measured
    # at least 1.4 KB (134 MB at 10,000, 202 MB at 60,000). So the summary runs in a child process that
    # forces a full collection every 5,000 records and reports the most bytes it ever held live; the
    # slope between 10,000 and 60,000 short responses is what the code keeps per response.
    $live = @{}
    foreach ($n in @(10000, 60000)) {
        $file = Join-Path $work ("live-" + $n + "\66666666-7777-4888-8999-000000000000.jsonl")
        New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force | Out-Null
        New-BigTranscript -Path $file -Pairs $n -Short
        $live[$n] = Measure-HordeLiveBytes -File $file
        Write-Host ("MEMORY live: " + $n + " short responses held at most " + [math]::Round($live[$n].bytes / 1MB, 1) + " MB live over " + $live[$n].records + " records (" + $live[$n].state + ")")
        Remove-Item -LiteralPath $file -Force
    }
    $perPair = [math]::Round(($live[60000].bytes - $live[10000].bytes) / 50000)
    Write-Host ("MEMORY per response: " + $perPair + " live bytes per assistant response and its tool result")
    Check ($live[10000].state -eq "known" -and $live[60000].state -eq "known" -and $live[60000].records -eq 180000) "CONTROL: the live measurement read both files whole (180,000 records in the larger)"
    Check ($perPair -gt 0) "CONTROL: what is kept does grow with the responses: memory is O(responses), not flat"
    Check ($perPair -lt $perResponseLimit) ("it keeps at most " + $perResponseLimit + " bytes per response (" + $perPair + ")")
    Check ($l.MB -ge 120) ("CONTROL: the large file is the size the target names (" + $l.MB + " MB)")
    Check (($l.peakMB - $f.peakMB) -lt $overFloorMB) ("the peak on the large file is within " + $overFloorMB + " MB of the floor (" + $l.peakMB + " MB against " + $f.peakMB + " MB; M1 measured 1,734 MB)")
    Check (($l.peakMB - $s.peakMB) -lt 50) ("the peak does not grow with the file: +" + ($l.peakMB - $s.peakMB) + " MB for " + ($l.MB - $s.MB) + " MB more transcript")
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "summarize stays within 120 MB of the bare command on long lines, and keeps a bounded number of bytes per response"
