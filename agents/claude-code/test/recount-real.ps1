# RECOUNT REAL TRANSCRIPTS: does the adapter's token count equal an independent recount on this
# machine's own session and subagent files?
#
#   powershell -File agents\claude-code\test\recount-real.ps1 -Path <a transcript, or a folder of them>
#
# WHY THIS EXISTS (review of PR #50, F1). The suites' fixtures had one usage per response, so the
# adapter's first-line rule passed them all while undercounting real subagent output by 88.9 percent;
# the orchestrator-only reality check matched only because orchestrator lines carry final usage. A
# fixture cannot show what a real file does, so this instrument runs over real files, read-only, as
# part of every metrics gate on a machine that has them. It is not a test-*.ps1 suite because its
# input is the user's own store, which a suite must never depend on (CONTRIBUTING 9).
#
# THE SECOND INSTRUMENT is deliberately different from the adapter: the study's rule (worker-extract.js),
# the LAST line's usage per message id, with no shared code beyond the JSON parser. API-error lines
# ("<synthetic>") are left out by both, and in a session file so are sidechain lines.
#
# Read-only: every file is opened through core/ReadShared.ps1. Nothing is written. Exit 0 only when every
# file agrees on all four token kinds and at least one file was compared; the last line says so.

param([Parameter(Mandatory = $true)][string]$Path)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
foreach ($f in @("Tristate", "ReadShared", "Home", "Transcript", "Price", "Metrics")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "agents\claude-code\Transcript.ps1")

function Get-LastLineRecount {
    param([string]$File)
    $isSession = ([System.IO.Path]::GetFileName($File) -notlike "agent-*")
    $last = @{}
    $null = Read-HordeJsonLines -Path $File -Each {
        param($n, $v)
        if ($v["type"] -ne "assistant" -or $v["message"] -isnot [System.Collections.IDictionary]) { return }
        if ("$($v["message"]["model"])" -eq "<synthetic>" -or $v["isApiErrorMessage"] -eq $true) { return }
        if ($isSession -and $v["isSidechain"] -eq $true) { return }
        $last["$($v["message"]["id"])"] = $v["message"]["usage"]
    }
    $t = @{ input = [long]0; cacheRead = [long]0; cacheWrite = [long]0; output = [long]0 }
    foreach ($u in $last.Values) {
        if ($u -isnot [System.Collections.IDictionary]) { continue }
        $t.input += [long]$u["input_tokens"]; $t.cacheRead += [long]$u["cache_read_input_tokens"]
        $t.cacheWrite += [long]$u["cache_creation_input_tokens"]; $t.output += [long]$u["output_tokens"]
    }
    return [pscustomobject]$t
}

$files = @()
if (Test-Path -LiteralPath $Path -PathType Leaf) { $files = @($Path) }
else { $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File | Where-Object { $_.Extension -ieq ".jsonl" } | ForEach-Object { $_.FullName }) }
$compared = 0; $agree = 0; $bad = 0; $skipped = 0
$sum = @{ adapterOut = [long]0; recountOut = [long]0 }
foreach ($file in $files) {
    if (-not (Test-ClaudeCodeTranscript -Path $file)) { $skipped++; continue }
    $r = Read-ClaudeCodeTranscript -Path $file
    $w = Get-HordeWorkerSummary -Records $r.records -PriceTable (New-HordeAbsent -Note "not priced")
    $x = Get-LastLineRecount -File $file
    $compared++
    if ($w.tokens.state -ne "known") { $bad++; Write-Output ("UNKNOWN " + (Split-Path -Leaf $file) + ": " + $w.tokens.reason); continue }
    $t = $w.tokens.value
    $sum.adapterOut += $t.output; $sum.recountOut += $x.output
    if ($t.input -eq $x.input -and $t.cacheRead -eq $x.cacheRead -and $t.cacheWrite -eq $x.cacheWrite -and $t.output -eq $x.output) { $agree++ }
    else { $bad++; Write-Output ("DIFFER " + (Split-Path -Leaf $file) + ": adapter in/cr/cw/out " + $t.input + "/" + $t.cacheRead + "/" + $t.cacheWrite + "/" + $t.output + ", recount " + $x.input + "/" + $x.cacheRead + "/" + $x.cacheWrite + "/" + $x.output) }
}
Write-Output ("files compared " + $compared + ", agree " + $agree + ", differ or unknown " + $bad + ", not this harness's " + $skipped + "; output tokens adapter " + $sum.adapterOut + ", recount " + $sum.recountOut)
if ($compared -eq 0) { Write-Output "RECOUNT-REAL verdict: NOT RUN - no transcript of this harness under the path"; exit 2 }
if ($bad -gt 0) { Write-Output "RECOUNT-REAL verdict: FAIL"; exit 1 }
Write-Output "RECOUNT-REAL verdict: PASS"
exit 0
