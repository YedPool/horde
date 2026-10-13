# One racer for test/test-files-race.ps1. Not a suite: it is started as its own process, several at
# once, all aimed at ONE files store (the home at -HordeHome), and it shares in one of these ways.
#
# -Mode same-path: -Count times, on each shared tick, it shares the file at -Source. Every racer is
#   given the SAME file and the same session, so all of them try for the same next version at once.
#   This is the race that shows whether two shares can both take one version, or one be lost.
#
# -Mode first-share: as same-path, but share number i goes to a home of its own, <HordeHome>-<i>,
#   which nothing has used: every racer's share of a round is the FIRST share of that home, so all of
#   them find no key there. This is the race that shows whether two first shares can end with two keys.
#   THE ORDER IS STAGED, NOT HOPED FOR. Left to the machine, the racers overlap or do not as its load
#   decides (measured 2026-10-13, with other runs busy on the machine: in one run no racer overlapped
#   another, and a broken key move went unseen). So each racer, having found no key and no record at
#   the tick, WAITS before it makes its key: racer 0 for 50 ms, racer 1 for 85, and so on, 35 ms
#   apart. Every racer has then decided to make a key, and they make them one after another: with a
#   move that does not replace, the second is told the name is taken and reads the first one's key;
#   with one that replaces, it reads its own. The wait is put where the real code asks the store
#   whether it holds a record (Test-HordeFilesStoreHasRecord), whose REAL answer is worked out
#   first and returned unchanged: only the moment is this worker's, never the answer.
#
# -Mode same-bytes: -Count times it first writes "round <i>" into its OWN file at -Source and then, on
#   the tick, shares it. Every racer writes the same words, so all of them put the same bytes in the
#   store at once. This is the race that shows whether bytes kept once can be seen half-written.
#
# -Mode stall: it makes ONE share of -Source and stops inside it until the suite kills it: at the
#   move number -StallMove (in a new home 1 is the key taking its name, 2 the bytes, 3 the record), before the move
#   when -StallWhen is "before" and just after it when "after". It writes -GoFile when it has reached
#   the step, and writes -LogFile only if the share RETURNS - which it never does, so a log means the
#   writer was told something. The step is reached by standing in for the store's one move
#   (core/FileAtomic.ps1's Move-HordeFileNewDurable) with a function that waits.
#
# What it is TOLD goes to -LogFile, one line a share, fields separated by |:
#   index|outcome or threw|file id|version|attempts|sha256|reason
# The suite compares what every racer was told with what the store holds afterwards.
#
# The ticks come from the wall clock every racer reads (test/fixtures/decisions/race-worker.ps1 says
# why that makes the racers start together rather than take turns).
param(
    [Parameter(Mandatory = $true)][ValidateSet("same-path", "first-share", "same-bytes", "stall")][string]$Mode,
    [Parameter(Mandatory = $true)][string]$CodePath,
    [Parameter(Mandatory = $true)][string]$HordeHome,
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$GoFile,
    [Parameter(Mandatory = $true)][string]$ReadyFile,
    [Parameter(Mandatory = $true)][string]$LogFile,
    [Parameter(Mandatory = $true)][int]$Racer,
    [Parameter(Mandatory = $true)][int]$Count,
    [Parameter(Mandatory = $true)][int]$TickMs,
    [int]$StallMove = 0,
    [ValidateSet("before", "after")][string]$StallWhen = "before"
)
$ErrorActionPreference = "Stop"
. $CodePath
# Every racer is the same session: the same path is then the same file to all of them.
$asking = New-HordeKnown -Value "race-session"
# Everything slow is done before the clock starts, so start-up is not part of the race.
$null = Get-HordeFilesSettings -HordeHome $HordeHome
if ($Mode -cne "stall") {
    # A WHOLE SHARE, ONCE, INTO A HOME NOBODY ELSE USES: the first share of a process compiles what it
    # asks Windows with and loads the cryptography, about half a second, and a racer still doing that
    # on the first tick is not in the race (measured 2026-10-13: of six staged rounds, the first was
    # the one in which no racer met another).
    $warmFile = $LogFile + ".warm.md"
    [System.IO.File]::WriteAllText($warmFile, "warm")
    $null = Add-HordeFilesShare -Path $warmFile -Title "warm" -HordeHome ($HordeHome + "-warm-" + $Racer) -Asking $asking
}
[System.IO.File]::WriteAllText($ReadyFile, "ready")

if ($Mode -ceq "stall") {
    $script:realMove = ${function:Move-HordeFileNewDurable}
    $script:moves = 0
    function Move-HordeFileNewDurable {
        param([string]$From, [string]$To, $Open = $null, $OsPlatform = $null)
        $script:moves++
        if ($script:moves -ne $StallMove) { return (& $script:realMove -From $From -To $To -Open $Open) }
        if ($StallWhen -ceq "after") { $null = & $script:realMove -From $From -To $To -Open $Open }
        [System.IO.File]::WriteAllText($GoFile, ("move " + $script:moves + " " + $StallWhen))
        # Never returns: the suite kills this process here. Bounded all the same, so a suite that
        # forgot it leaves no process.
        Start-Sleep -Seconds 600
        exit 3
    }
    $told = Add-HordeFilesShare -Path $Source -Title "A share stopped part-way" -HordeHome $HordeHome -Asking $asking
    [System.IO.File]::WriteAllLines($LogFile, [string[]]@(("0|" + $told.outcome), "END"))
    exit 0
}

if ($Mode -ceq "first-share") {
    $script:realHasRecord = ${function:Test-HordeFilesStoreHasRecord}
    $script:stageAt = [long]0
    function Test-HordeFilesStoreHasRecord {
        param([string]$Root)
        $said = & $script:realHasRecord -Root $Root
        while ([datetime]::UtcNow.Ticks -lt $script:stageAt) { }
        return $said
    }
}

$deadline = [datetime]::UtcNow.AddSeconds(300)
while (-not (Test-Path -LiteralPath $GoFile)) {
    if ([datetime]::UtcNow -gt $deadline) { throw "no go file within 300 s" }
    Start-Sleep -Milliseconds 20
}
$startTicks = [long]([System.IO.File]::ReadAllText($GoFile).Trim())

$log = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $Count; $i++) {
    if ($Mode -ceq "same-bytes") { [System.IO.File]::WriteAllText($Source, ("round " + $i)) }
    $target = $startTicks + [long]$i * [long]$TickMs * 10000
    while ([datetime]::UtcNow.Ticks -lt $target) { }
    $line = ""
    $shareHome = $HordeHome
    if ($Mode -ceq "first-share") { $shareHome = $HordeHome + "-" + $i; $script:stageAt = $target + [long](50 + 35 * $Racer) * 10000 }
    try {
        $told = Add-HordeFilesShare -Path $Source -Title ("racer " + $Racer + " share " + $i) -HordeHome $shareHome -Asking $asking
        if ($told.outcome -ceq "shared") { $line = "" + $i + "|shared|" + $told.record.fileId + "|" + $told.record.version + "|" + $told.attempts + "|" + $told.record.sha256 + "|" }
        else { $line = "" + $i + "|" + $told.outcome + "||0|0||" + ("$($told.reason)" -replace "[\r\n|]", " ") }
    } catch { $line = "" + $i + "|threw||0|0||" + ("$($_.Exception.Message)" -replace "[\r\n|]", " ") }
    [void]$log.Add($line)
}
[void]$log.Add("END")
[System.IO.File]::WriteAllLines($LogFile, [string[]]$log.ToArray())
exit 0
