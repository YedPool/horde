# DOES `horde metrics summarize` STAY FLAT IN MEMORY, HOWEVER LARGE THE TRANSCRIPT?
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
# HEAVY: it writes about 170 MB to TEMP and runs for minutes. It is in the gate so that a change that
# brings back a list of records fails it; run it where there is memory to spare.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-memory-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$overFloorMB = 120

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
        try { $p.Refresh(); if ($p.PeakWorkingSet64 -gt $peak) { $peak = $p.PeakWorkingSet64 }; if ($p.PrivateMemorySize64 -gt $priv) { $priv = $p.PrivateMemorySize64 } } catch { }
        Start-Sleep -Milliseconds 100
    }
    $p.WaitForExit()
    $code = $p.ExitCode; $p.Dispose()
    return [pscustomobject]@{ code = $code; peakMB = [math]::Round($peak / 1MB); privateMB = [math]::Round($priv / 1MB); seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); out = ($outTask.Result + $errTask.Result) }
}

try {
    $rows = @()
    foreach ($size in @(@{ name = "floor"; pairs = 1 }, @{ name = "small"; pairs = 10000 }, @{ name = "large"; pairs = 40000 }, @{ name = "short-few"; pairs = 20000; short = $true }, @{ name = "short-many"; pairs = 120000; short = $true })) {
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
    $f = $rows[0]; $s = $rows[1]; $l = $rows[2]; $sf = $rows[3]; $sm = $rows[4]
    $perPair = [math]::Round((($sm.privateMB - $sf.privateMB) * 1MB) / ($sm.pairs - $sf.pairs))
    Write-Host ("MEMORY per response with short lines: " + $perPair + " bytes of private memory per assistant response and its tool result (" + $sf.privateMB + " MB at " + $sf.pairs + ", " + $sm.privateMB + " MB at " + $sm.pairs + ")")
    Check ($l.MB -ge 120) ("CONTROL: the large file is the size the target names (" + $l.MB + " MB)")
    Check (($l.peakMB - $f.peakMB) -lt $overFloorMB) ("the peak on the large file is within " + $overFloorMB + " MB of the floor (" + $l.peakMB + " MB against " + $f.peakMB + " MB; M1 measured 1,734 MB)")
    Check (($l.peakMB - $s.peakMB) -lt 50) ("the peak does not grow with the file: +" + ($l.peakMB - $s.peakMB) + " MB for " + ($l.MB - $s.MB) + " MB more transcript")
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "summarize's peak on a 133 MB transcript is within 120 MB of the bare command's, and does not grow with the file"
