# DOES THE TRANSCRIPT PORT HOLD ITS CONTRACT, WHATEVER THE ADAPTER?
#
# core/Transcript.ps1, with neutral fake adapters ("harness-a", "harness-b") built here: the real
# adapters are tested in their own agents/<name>/test/ folders (CONTRIBUTING 14). Everything this suite
# writes is under one folder in TEMP that it creates and removes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "core\ReadShared.ps1")
. (Join-Path $root "core\Transcript.ps1")

$work = Join-Path $env:TEMP ("horde-transcript-port-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    Write-Host ""
    Write-Host "--- times ---" -ForegroundColor Cyan
    $t = ConvertTo-HordeUtcTime "2026-09-30T14:33:13.872Z"
    Check ($t -is [datetime] -and $t.Kind -eq [System.DateTimeKind]::Utc -and $t.Hour -eq 14) "a Z timestamp reads as that UTC time"
    $o = ConvertTo-HordeUtcTime "2026-09-30T10:33:13-04:00"
    Check ($o -is [datetime] -and $o.Hour -eq 14 -and $o.Kind -eq [System.DateTimeKind]::Utc) "an offset timestamp is converted to UTC"
    Check ($null -eq (ConvertTo-HordeUtcTime "2026-09-30T14:33:13")) "a timestamp with no zone is not guessed to be UTC"
    Check ($null -eq (ConvertTo-HordeUtcTime "yesterday")) "text that is not a time is no time"

    Write-Host ""
    Write-Host "--- records ---" -ForegroundColor Cyan
    Check (Throws { New-HordeTranscriptRecord -Kind "nonsense" -Role "system" -Ts $t -Line 1 } "not a transcript record kind") "a record of a kind the port does not define is refused"
    Check (Throws { New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts (Get-Date "2026-09-30T14:00:00") -Line 1 } "UTC time") "a record whose time is not UTC is refused"
    $ev = New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $t -Line 3
    Check ($ev.kind -eq "event" -and $ev.line -eq 3) "CONTROL: a well-formed record is made"
    Check (Throws { New-HordeUsage -Uncached -1 -CacheRead 0 -CacheWrite 0 -Output 0 -Split (New-HordeAbsent) } "negative") "a negative token count is refused"
    Check (Throws { New-HordeUsage -Uncached 1 -CacheRead 0 -CacheWrite 0 -Output 0 -Split 5 } "not a Horde answer") "a cache-write split that is not an answer is refused"

    Write-Host ""
    Write-Host "--- reading JSONL ---" -ForegroundColor Cyan
    $f = Join-Path $work "lines.jsonl"
    [System.IO.File]::WriteAllText($f, "{""a"":1}`n{not json`n`n{""b"":2}`n{""c"":")
    $r = Read-HordeJsonLines -Path $f
    Check (@($r.lines).Count -eq 2) ("the two good lines are read (" + @($r.lines).Count + ")")
    Check ($r.parseSkipped -eq 1) ("a bad line in the middle is counted as skipped (" + $r.parseSkipped + ")")
    Check ($r.tornTail -eq 1) ("an unfinished last line with no newline is counted as the line being written (" + $r.tornTail + ")")
    Check (@($r.lines)[1].line -eq 4) "each value keeps the line number it came from"
    $g = Join-Path $work "ends.jsonl"
    [System.IO.File]::WriteAllText($g, "{""a"":1}`n{bad`n")
    $r2 = Read-HordeJsonLines -Path $g
    Check ($r2.parseSkipped -eq 1 -and $r2.tornTail -eq 0) "a bad last line that ends with a newline is skipped, not torn"
    $seenLines = New-Object System.Collections.ArrayList
    $streamed = Read-HordeJsonLines -Path $f -Each { param($n, $v) [void]$seenLines.Add($n); "stray output" }
    Check ((@($seenLines) -join ",") -eq "1,4") "with -Each, every good line is handed to the block with its line number"
    Check (@($streamed.lines).Count -eq 0 -and $streamed.parseSkipped -eq 1 -and $streamed.tornTail -eq 1) "and none is kept, while bad and torn lines are still counted"
    # Dynamic scoping: a block that reads a name the reader also uses must still see its author's.
    $out = "the author's"; $ser = "the author's"; $text = "the author's"
    $sawNames = New-Object System.Collections.ArrayList
    $null = Read-HordeJsonLines -Path $f -Each { param($n, $v) [void]$sawNames.Add($out + "|" + $ser + "|" + $text) }
    Check (@($sawNames | Where-Object { $_ -ne "the author's|the author's|the author's" }).Count -eq 0 -and $sawNames.Count -eq 2) 'a block reading names the reader also uses ($out, $ser, $text) sees its author''s, not the reader''s'
    $arr = Join-Path $work "array.jsonl"
    [System.IO.File]::WriteAllText($arr, "[1,2]`n""text""`n")
    Check ((Read-HordeJsonLines -Path $arr).parseSkipped -eq 2) "a line that parses but is not an object is skipped, not read"

    # READ-ONLY AND SHARED: a writer holding the file open for appending, sharing only read and write,
    # is what a harness does while its session runs. The read must succeed, and must not change the file.
    $live = Join-Path $work "live.jsonl"
    [System.IO.File]::WriteAllText($live, "{""a"":1}`n")
    $before = (Get-FileHash -LiteralPath $live -Algorithm SHA256).Hash
    $writer = [System.IO.File]::Open($live, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    try {
        $rl = Read-HordeJsonLines -Path $live
        Check (@($rl.lines).Count -eq 1) "a file a writer holds open for appending is read"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes("{""b"":2}`n")
        $writer.Write($bytes, 0, $bytes.Length)
        $writer.Flush()
        Check $true "CONTROL: the writer can still append after the read"
    } finally { $writer.Dispose() }
    $rl2 = Read-HordeJsonLines -Path $live
    Check (@($rl2.lines).Count -eq 2) "and the line it appended is read next time"
    [System.IO.File]::WriteAllText($f, "{""a"":1}`n")
    $h1 = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
    $null = Read-HordeJsonLines -Path $f
    Check ($h1 -eq (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash) "reading a transcript leaves it byte for byte as it was"

    Write-Host ""
    Write-Host "--- the json path helper ---" -ForegroundColor Cyan
    $parsed = @(Read-HordeJsonLines -Path $live)[0].lines[0].value
    Check ((Get-HordeJsonPath $parsed "a") -eq 1) "a top-level key is read"
    Check ($null -eq (Get-HordeJsonPath $parsed "a.b.c")) "a path through something that is not an object reads as nothing"
    Check ($null -eq (Get-HordeJsonPath $parsed "missing")) "a missing key reads as nothing"

    Write-Host ""
    Write-Host "--- adapters ---" -ForegroundColor Cyan
    $script:HordeTranscriptAdapters.Clear()
    $tsA = $t
    Register-HordeTranscriptAdapter -Name "harness-a" -Claim { param($p) $p -like "*.a.jsonl" } -Read {
        param($p)
        [pscustomobject]@{ sessionId = "s-a"; parseSkipped = 0; tornTail = 0; records = @(
            (New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $tsA -Line 1)
        ) }
    }
    Register-HordeTranscriptAdapter -Name "harness-b" -Claim { param($p) $p -like "*.b.jsonl" -or $p -like "*.both.jsonl" } -Read {
        param($p)
        [pscustomobject]@{ sessionId = "s-b"; parseSkipped = 0; tornTail = 0; records = @([pscustomobject]@{ kind = "call" }) }
    }
    Register-HordeTranscriptAdapter -Name "harness-c" -Claim { param($p) $p -like "*.both.jsonl" } -Read { param($p) $null }
    Check (Throws { Register-HordeTranscriptAdapter -Name "Bad Name" -Claim { $true } -Read { $null } } "lowercase") "an adapter name that is not lowercase letters, digits and hyphens is refused"

    $a = Read-HordeTranscript -Path (Join-Path $work "x.a.jsonl")
    Check ($a.state -eq "known" -and $a.value.adapter -eq "harness-a" -and @($a.value.records).Count -eq 1) "CONTROL: a file one adapter claims is read through it"
    $none = Read-HordeTranscript -Path (Join-Path $work "x.txt")
    Check ($none.state -eq "unknown" -and $none.reason -like "*no adapter*") "a file no adapter claims is unknown, with the reason"
    $two = Resolve-HordeTranscriptAdapter -Path (Join-Path $work "x.both.jsonl")
    Check ($two.state -eq "unknown" -and $two.reason -like "*more than one*") "a file two adapters claim is read by neither"
    $b = Read-HordeTranscript -Path (Join-Path $work "x.b.jsonl")
    Check ($b.state -eq "unknown" -and $b.reason -like "*broke the record contract*") "an adapter whose records were not made by the port is refused"

    Register-HordeTranscriptAdapter -Name "harness-d" -Claim { param($p) $p -like "*.d.jsonl" } -Read {
        param($p)
        [pscustomobject]@{ sessionId = "s-d"; parseSkipped = 0; tornTail = 0; records = @(
            (New-HordeTranscriptRecord -Kind "call" -Role "assistant" -Ts $tsA -Line 2 -Fields @{ id = "c1"; model = "not an answer"; usage = (New-HordeUnknown -Reason "x") })
        ) }
    }
    $d = Read-HordeTranscript -Path (Join-Path $work "x.d.jsonl")
    Check ($d.state -eq "unknown" -and $d.reason -like "*model*not an answer*") "a call whose model is a bare value, not an answer, breaks the contract"
    Register-HordeTranscriptAdapter -Name "harness-e" -Claim { param($p) $p -like "*.e.jsonl" } -Read {
        param($p)
        [pscustomobject]@{ sessionId = "s-e"; parseSkipped = 0; tornTail = 0; records = @(
            (New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $tsA -Line 5),
            (New-HordeTranscriptRecord -Kind "event" -Role "system" -Ts $tsA -Line 2)
        ) }
    }
    $e = Read-HordeTranscript -Path (Join-Path $work "x.e.jsonl")
    Check ($e.state -eq "unknown" -and $e.reason -like "*out of file order*") "records out of file order break the contract"
    Register-HordeTranscriptAdapter -Name "harness-f" -Claim { param($p) $p -like "*.f.jsonl" } -Read { param($p) throw "disk on fire" }
    $ff = Read-HordeTranscript -Path (Join-Path $work "x.f.jsonl")
    Check ($ff.state -eq "unknown" -and $ff.reason -like "*disk on fire*") "an adapter that throws gives unknown carrying its message"

    Write-Host ""
    Write-Host "--- finding adapter files ---" -ForegroundColor Cyan
    $fakeRoot = Join-Path $work "repo"
    New-Item -ItemType Directory -Path (Join-Path $fakeRoot "agents\harness-a") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fakeRoot "agents\harness-b") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeRoot "agents\harness-a\Transcript.ps1") -Value "# a"
    $files = @(Get-HordeTranscriptAdapterFiles -Root $fakeRoot)
    Check ($files.Count -eq 1 -and $files[0] -like "*harness-a*Transcript.ps1") "an agent folder with a Transcript.ps1 is an adapter; one without is not"
    $real = @(Get-HordeTranscriptAdapterFiles)
    Check ($real.Count -ge 1) ("CONTROL: the repository's own agents folder has adapters (" + $real.Count + ")")
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the transcript port reads JSONL read-only, counts what it skips, and refuses adapters that break its contract"
