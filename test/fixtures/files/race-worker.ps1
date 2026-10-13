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
#   THE ORDER IS STAGED, NOT HOPED FOR, AND NOT BY THE CLOCK. Left to the machine, the racers overlap
#   or do not as its load decides (measured 2026-10-13, with other runs busy on the machine: in one
#   run no racer overlapped another, and a broken key move went unseen). Until the second round of
#   that day's review the order was staged by time - racer 0 waited 50 ms before it made its key,
#   racer 1 for 85, and so on, 35 ms apart - and a machine at 70 percent CPU held racers back
#   longer than that: the control that must see two keys saw them in 0 to 2 of 6 rounds, three
#   runs in a row. A control that fails under load fails in somebody's net.
#   SO THE RACERS TELL EACH OTHER WHERE THEY ARE, by files in the race's own folder, and no clock
#   decides anything. Each racer, having found no key and no record, writes that it has DECIDED to
#   make a key, and waits until every racer of the round has written the same: all of them have
#   then seen "no key". Then they go on one at a time, in the order of their numbers: a racer
#   waits until the one before it has written that its share is DONE. With a move that does not
#   replace, the second is told the name is taken and reads the first one's key; with one that
#   replaces, it reads its own. Load makes this slower and never puts it in another order.
#   The wait is put where the real code asks the store whether it holds a record
#   (Test-HordeFilesStoreHasRecord), whose REAL answer is worked out first and returned
#   unchanged: only the moment is this worker's, never the answer.
#   A WAIT THAT IS NEVER ANSWERED ENDS, after 180 s, and the racer writes that the staging FAILED
#   for that round and goes on; so does a racer whose share never came to that question. The suite
#   counts those files and fails on one: a round that was not staged proves nothing.
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
    [int]$Racers = 1,
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
    # The round whose first asking is staged, or -1: outside a round, and after that first asking,
    # the question is answered at once.
    $script:stageRound = -1
    $script:stageDir = Split-Path -Parent $GoFile
    function Get-StageMark { param([int]$Round, [string]$What, [int]$Of) return (Join-Path $script:stageDir ("stage-" + $Round + "-" + $What + "-" + $Of)) }
    function Wait-StageMarks {
        # Wait until every file of -Marks is there: $true, or $false when -Seconds passed first.
        param([string[]]$Marks, [int]$Seconds = 180)
        $until = [datetime]::UtcNow.AddSeconds($Seconds)
        while (@($Marks | Where-Object { -not [System.IO.File]::Exists($_) }).Count -gt 0) {
            if ([datetime]::UtcNow -gt $until) { return $false }
            Start-Sleep -Milliseconds 5
        }
        return $true
    }
    function Test-HordeFilesStoreHasRecord {
        param([string]$Root)
        $said = & $script:realHasRecord -Root $Root
        if ($script:stageRound -lt 0) { return $said }
        $staged = $script:stageRound
        $script:stageRound = -1
        [System.IO.File]::WriteAllText((Get-StageMark -Round $staged -What "decided" -Of $Racer), "")
        $held = Wait-StageMarks -Marks @(0..($Racers - 1) | ForEach-Object { Get-StageMark -Round $staged -What "decided" -Of $_ })
        if ($held -and $Racer -gt 0) { $held = Wait-StageMarks -Marks @((Get-StageMark -Round $staged -What "done" -Of ($Racer - 1))) }
        if (-not $held) { [System.IO.File]::WriteAllText((Get-StageMark -Round $staged -What "failed" -Of $Racer), "") }
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
    if ($Mode -ceq "first-share") { $shareHome = $HordeHome + "-" + $i; $script:stageRound = $i }
    try {
        $told = Add-HordeFilesShare -Path $Source -Title ("racer " + $Racer + " share " + $i) -HordeHome $shareHome -Asking $asking
        if ($told.outcome -ceq "shared") { $line = "" + $i + "|shared|" + $told.record.fileId + "|" + $told.record.version + "|" + $told.attempts + "|" + $told.record.sha256 + "|" }
        else { $line = "" + $i + "|" + $told.outcome + "||0|0||" + ("$($told.reason)" -replace "[\r\n|]", " ") }
    } catch { $line = "" + $i + "|threw||0|0||" + ("$($_.Exception.Message)" -replace "[\r\n|]", " ") }
    if ($Mode -ceq "first-share") {
        # A share that never asked the staged question was not staged: said, and the others are not
        # left waiting for it. Then DONE, whatever the share was told, so the next racer goes on.
        if ($script:stageRound -ge 0) {
            $script:stageRound = -1
            [System.IO.File]::WriteAllText((Get-StageMark -Round $i -What "failed" -Of $Racer), "")
            [System.IO.File]::WriteAllText((Get-StageMark -Round $i -What "decided" -Of $Racer), "")
        }
        [System.IO.File]::WriteAllText((Get-StageMark -Round $i -What "done" -Of $Racer), "")
    }
    [void]$log.Add($line)
}
[void]$log.Add("END")
[System.IO.File]::WriteAllLines($LogFile, [string[]]$log.ToArray())
exit 0
