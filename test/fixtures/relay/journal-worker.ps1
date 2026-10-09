# One racer of test/test-relay-journal-race.ps1. Not a suite; run only by that suite, under either
# PowerShell runtime.
#
# It loads relay/Journal.ps1 from -CodeRoot (the repository, or the suite's broken copy of it), trusts the
# one sender whose 65-byte public key is hex in -SenderFile, receives as the machine whose agree key id
# is -RecipientKeyId, and reads -EnvelopesFile: one envelope's
# wire text per line. Every envelope is read (Read-HordeRelayEnvelope) before -ReadyFile is written, so
# process start-up is not part of the race. Then, by -Mode:
#   race                for each envelope i, it waits for the shared tick (the start time in -GoFile,
#                       plus i times -TickMs) and registers envelope i as received. When i is of
#                       -DelayParity (0 even, 1 odd), it waits -DelayMs more: a head start for the
#                       racers of the other runtime, which would otherwise lose every envelope to the
#                       faster one (measured 2026-10-09: PowerShell 7 won 30 of 30).
#   once                it registers envelope -Index at once, with no go file.
#   stall-before-move   it registers envelope -Index, but stops inside the write, after the record is
#   stall-after-move    written and flushed to its temporary file and before (or just after) it takes its
#                       name, by standing in for core/FileAtomic.ps1's Move-HordeFileNewDurable. It
#                       writes -GoFile when it has reached the step, then waits to be killed.
# -LogFile gets one line per envelope, then END:  index|state|fresh|why-or-reason
# A line written means the racer was TOLD that; the suite compares it with what the journal holds.
param(
    [Parameter(Mandatory = $true)][ValidateSet("race", "once", "stall-before-move", "stall-after-move")][string]$Mode,
    [Parameter(Mandatory = $true)][string]$CodeRoot,
    [Parameter(Mandatory = $true)][string]$HordeHome,
    [Parameter(Mandatory = $true)][string]$EnvelopesFile,
    [Parameter(Mandatory = $true)][string]$SenderFile,
    [Parameter(Mandatory = $true)][string]$LogFile,
    [string]$GoFile = "",
    [string]$ReadyFile = "",
    [int]$TickMs = 0,
    [int]$Index = 0,
    [int]$DelayParity = -1,
    [int]$DelayMs = 0,
    [string]$RecipientKeyId = ""
)
$ErrorActionPreference = "Stop"
. (Join-Path $CodeRoot "relay\Journal.ps1")

$pubHex = [System.IO.File]::ReadAllText($SenderFile).Trim()
$pub = ConvertFrom-HordeRelayHex -Text $pubHex
$senders = @{ (Get-HordeRelayKeyId -Public $pub) = (New-HordeRelaySender -Public $pub -Proof "es256") }
$envelopes = New-Object System.Collections.ArrayList
foreach ($line in [System.IO.File]::ReadAllLines($EnvelopesFile)) {
    if ($line.Trim() -eq "") { continue }
    $r = Read-HordeRelayEnvelope -Text $line
    if (-not $r.ok) { throw ("envelope " + $envelopes.Count + " does not read: " + $r.reason) }
    [void]$envelopes.Add($r.value)
}

function Format-Answer {
    param([int]$At, $Answer)
    if ($Answer.state -ceq "known") { return ("" + $At + "|known|" + $Answer.value.fresh + "|" + ("" + $Answer.value.why -replace "[\r\n|]", " ")) }
    return ("" + $At + "|" + $Answer.state + "||" + ("" + $Answer.reason -replace "[\r\n|]", " "))
}

if ($Mode -clike "stall-*") {
    $script:realMove = ${function:Move-HordeFileNewDurable}
    $script:stallMode = $Mode
    $script:stallMark = $GoFile
    function Move-HordeFileNewDurable {
        param($From, $To, $Open = $null, $OsPlatform = [System.Environment]::OSVersion.Platform)
        if ($script:stallMode -ceq "stall-after-move") { $null = & $script:realMove -From $From -To $To -Open $Open }
        [System.IO.File]::WriteAllText($script:stallMark, $script:stallMode)
        # Killed here by the suite. Ten minutes is far past any suite's wait, so a writer that was not
        # killed is seen as still running, not mistaken for one that finished.
        Start-Sleep -Seconds 600
        throw "the stalled writer was not killed"
    }
}

if ($Mode -cne "race") {
    $answer = Register-HordeRelayJournalReceived -Envelope $envelopes[$Index] -Senders $senders -RecipientKeyIds @($RecipientKeyId) -Channel $envelopes[$Index].header.channel -Kind "answer" -HordeHome $HordeHome
    [System.IO.File]::WriteAllLines($LogFile, [string[]]@((Format-Answer -At $Index -Answer $answer), "END"))
    exit 0
}

[System.IO.File]::WriteAllText($ReadyFile, "ready")
$deadline = [datetime]::UtcNow.AddSeconds(120)
while (-not (Test-Path -LiteralPath $GoFile)) {
    if ([datetime]::UtcNow -gt $deadline) { throw "no go file within 120 s" }
    Start-Sleep -Milliseconds 20
}
$startTicks = [long]([System.IO.File]::ReadAllText($GoFile).Trim())
$log = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $envelopes.Count; $i++) {
    # The ticks come from the wall clock every racer reads (test/fixtures/journal/race-worker.ps1): its
    # coarse resolution makes the racers start each envelope together rather than take turns.
    $target = $startTicks + [long]$i * [long]$TickMs * 10000
    if ($DelayParity -ge 0 -and ($i % 2) -eq $DelayParity) { $target += [long]$DelayMs * 10000 }
    while ([datetime]::UtcNow.Ticks -lt $target) { }
    try { $line = Format-Answer -At $i -Answer (Register-HordeRelayJournalReceived -Envelope $envelopes[$i] -Senders $senders -RecipientKeyIds @($RecipientKeyId) -Channel $envelopes[$i].header.channel -Kind "answer" -HordeHome $HordeHome) }
    catch { $line = "" + $i + "|threw||" + ("" + $_.Exception.Message -replace "[\r\n|]", " ") }
    [void]$log.Add($line)
}
[void]$log.Add("END")
[System.IO.File]::WriteAllLines($LogFile, [string[]]$log.ToArray())
exit 0
