# One racer for test/test-journal-race.ps1. Not a suite: it is started as its own process, several
# at once, and each races the others for the same request ids.
#
# For each id in -IdsFile, in order, it waits for that id's shared start tick, then asks the journal
# whether to act. Only when the journal says "act" does it perform the act: it creates one effect
# file, named for the id and this racer, in -EffectsDir. That file is what the suite counts - two
# effect files for one id is a double execution, whatever the journal claims. Then it records the
# outcome, as a node would.
#
# The ticks come from the wall clock every racer reads. Its resolution (about 15.6 ms on Windows by
# default) is coarse, which is what we want here: every racer waiting on the same tick sees it change
# at the same moment, so they call the journal together rather than one after another.
param(
    [Parameter(Mandatory = $true)][string]$JournalPath,
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$IdsFile,
    [Parameter(Mandatory = $true)][string]$EffectsDir,
    [Parameter(Mandatory = $true)][string]$GoFile,
    [Parameter(Mandatory = $true)][string]$ReadyFile,
    [Parameter(Mandatory = $true)][string]$LogFile,
    [Parameter(Mandatory = $true)][int]$Racer,
    [Parameter(Mandatory = $true)][int]$TickMs
)
$ErrorActionPreference = "Stop"
. $JournalPath

$ids = @([System.IO.File]::ReadAllLines($IdsFile) | Where-Object { $_ })
[System.IO.File]::WriteAllText($ReadyFile, "ready")

# Wait for the go file, which holds the shared start time in UTC ticks.
$deadline = [datetime]::UtcNow.AddSeconds(120)
while (-not (Test-Path -LiteralPath $GoFile)) {
    if ([datetime]::UtcNow -gt $deadline) { throw "no go file within 120 s" }
    Start-Sleep -Milliseconds 20
}
$startTicks = [long]([System.IO.File]::ReadAllText($GoFile).Trim())
$issuedAt = New-Object datetime($startTicks, [System.DateTimeKind]::Utc)

$log = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $ids.Count; $i++) {
    $target = $startTicks + [long]$i * [long]$TickMs * 10000
    while ([datetime]::UtcNow.Ticks -lt $target) { }
    $id = $ids[$i]
    $o = Open-HordeJournalEntry -Root $Root -Id $id -Verb "session.spawn" -Arguments @{ n = $i } -IssuedAt $issuedAt
    if ($o.decision -ceq "act") {
        $eff = Join-Path $EffectsDir ($id + "." + $Racer)
        $fs = New-Object System.IO.FileStream($eff, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $fs.Dispose()
        # An act takes time - a spawn takes seconds. 20 ms here, so a racer arriving while it runs
        # finds the record with no outcome yet, as it would in use.
        Start-Sleep -Milliseconds 20
        # A broken journal (the suite's control) can make completing fail - another racer holds the
        # outcome file. The act has already happened and been counted, so that is logged, not fatal.
        try { Complete-HordeJournalEntry -Root $Root -Id $id -State "done" -Result (New-HordeKnown -Value $Racer) | Out-Null }
        catch { [void]$log.Add(($i.ToString() + " complete-failed " + ("$($_.Exception.Message)" -replace "[\r\n]", " "))) }
    }
    [void]$log.Add(($i.ToString() + " " + $o.decision + " " + ("$($o.reason)" -replace "[\r\n]", " ")))
}
[System.IO.File]::WriteAllLines($LogFile, [string[]]$log.ToArray())
exit 0
