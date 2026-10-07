# One racer for test/test-decisions-store-race.ps1 and test/test-decisions-threads-race.ps1. Not a
# suite: it is started as its own process, several at once, all aimed at ONE decisions store, and it
# races the others in one of these ways.
#
# -Mode store: for each sequence number from 1 to -Count, in order, it waits for that number's shared
#   start tick and then asks the store itself (decisions/Store.ps1 at -CodePath) to create that record.
#   Every racer asks for the SAME number on the SAME tick, so the creates collide head on. This is the
#   race that shows whether two writers can both take one sequence number.
#
# -Mode operations: for each of -Count questions it waits for the tick and then asks the decisions
#   operations (decisions/Operations.ps1 at -CodePath) to add a question of its own, under an id of its
#   own. This is the race that shows whether a whole write - read the list, check, take the next
#   number, try again on losing - loses a record.
#
# -Mode loop: it writes records 1, 2, 3, ... through the store as fast as it can, with no tick and no
#   log, until it is killed. This is the writer the suite kills mid-write, to see what a kill leaves.
#
# -Mode stall-before-move, stall-after-move: it makes ONE write and stops inside it, at a named step,
#   until the suite kills it: before the record's temporary file is given the record's name, or just
#   after. With decisions/Store.ps1 at -CodePath the write is record 1; with decisions/Operations.ps1
#   it is an add of one question under a fixed id - or, with -RequestFile, the one operation and
#   request that file holds, so that any write can be stopped the same way. It writes -GoFile when it has reached the step (the
#   suite waits for that), and writes -LogFile only if the write RETURNS - which it never does, so a
#   log means the writer was told something. The step is reached by standing in for the store's one
#   move (core/FileAtomic.ps1's Move-HordeFileNewDurable) with a function that waits.
#
# -Mode requests: -RequestFile holds a list of { offsetMs; operation; request }. For each, in order, it
#   waits for that entry's shared tick, moved by the entry's own offset, and asks the decisions
#   operations for it. Two racers given two lists act on the same ticks: a close and a say of one
#   question, say. This is the race that shows what two DIFFERENT writes do to each other.
#
# -Mode inbox: with decisions/Console.ps1 at -CodePath, -Count times, on each tick: it does what
#   `horde decisions inbox -Json` does, in its two halves - the reading and printing half, then, after
#   -PauseMs, the marking half - and writes down which messages the first half printed. The pause is
#   where another racer's new message lands. This is the race that shows whether a message can be
#   marked read without having been printed.
#
# What it is TOLD goes to -LogFile, one line an attempt, fields separated by |:
#   store:       index|created or exists or threw|reason
#   operations:  index|state|outcome|number|sequence|attempts|reason
#   requests:    index|state|outcome|sequence|attempts|flag|reason     (flag: after-closing, or empty)
#   inbox:       index|the printed messages' sequence numbers, comma-separated|why the marking failed, or empty
# The suite compares what every racer was told with what the store holds afterwards.
#
# The ticks come from the wall clock every racer reads, as in test/fixtures/journal/race-worker.ps1:
# its coarse resolution (about 15.6 ms on Windows by default) makes the racers start together rather
# than take turns.
param(
    [Parameter(Mandatory = $true)][ValidateSet("store", "operations", "loop", "stall-before-move", "stall-after-move", "requests", "inbox")][string]$Mode,
    [Parameter(Mandatory = $true)][string]$CodePath,
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$GoFile,
    [Parameter(Mandatory = $true)][string]$ReadyFile,
    [Parameter(Mandatory = $true)][string]$LogFile,
    [Parameter(Mandatory = $true)][int]$Racer,
    [Parameter(Mandatory = $true)][int]$Count,
    [Parameter(Mandatory = $true)][int]$TickMs,
    [string]$RequestFile = "",
    [int]$PauseMs = 0
)
$ErrorActionPreference = "Stop"
. $CodePath
# Everything slow is done before the clock starts, so start-up is not part of the race.
if ($Mode -ceq "operations" -or $Mode -ceq "requests" -or $Mode -ceq "inbox") { $null = Get-HordeDecisionDefinitions }
# A request file is JSON in UTF-8, read as what it is: the words in it may be in any alphabet.
$given = $null
if ($RequestFile -ne "") { $given = ([System.IO.File]::ReadAllText($RequestFile, (New-Object System.Text.UTF8Encoding($false, $true))) | ConvertFrom-Json) }
# A list of one request is read back as that one request: made a list again here.
$requests = @($given)
[System.IO.File]::WriteAllText($ReadyFile, "ready")

if ($Mode -ceq "loop") {
    # Nothing but writes, one record after another, until the suite kills this process: so that a kill
    # at any moment is likely to land while a record is being written. It never ends by itself in the
    # time a suite waits; -Count bounds it all the same, so a suite that forgot it leaves no process.
    $text = '{"racer":' + $Racer + ',"body":"' + ("word " * 120) + '"}'
    for ($seq = [long]1; $seq -le $Count; $seq++) { $null = Add-HordeDecisionRecord -Root $Root -Sequence $seq -Text $text }
    exit 0
}

if ($Mode -clike "stall-*") {
    $script:realMove = ${function:Move-HordeFileNewDurable}
    $script:stallMode = $Mode
    $script:stallMark = $GoFile
    function Move-HordeFileNewDurable {
        param([string]$From, [string]$To, $Open = $null, $OsPlatform = $null)
        if ($script:stallMode -ceq "stall-after-move") { $null = & $script:realMove -From $From -To $To -Open $Open }
        [System.IO.File]::WriteAllText($script:stallMark, $script:stallMode)
        # Never returns: the suite kills this process here. Bounded all the same, so a suite that
        # forgot it leaves no process.
        Start-Sleep -Seconds 600
        exit 3
    }
    $told = ""
    if ($null -ne $given) {
        $answer = Invoke-HordeDecision -Operation "$($given.operation)" -Request $given.request -Root $Root
        $told = "request|" + $answer.state
    }
    elseif ($null -ne (Get-Command -Name "Invoke-HordeDecision" -ErrorAction SilentlyContinue)) {
        # The same request the suite sends again afterwards: its id and its question are fixed.
        $question = @{ title = "Is a question whose writer was killed either whole or absent?"; kind = "yes-no"; whatItIs = "A writer is stopped inside its write and killed."; group = "the kill"; askedBy = "the-suite" }
        $answer = Invoke-HordeDecision -Operation "add" -Request @{ id = ("ab" * 16); actor = "warchief"; question = $question } -Root $Root
        $told = "operations|" + $answer.state
    } else { $told = "store|" + (Add-HordeDecisionRecord -Root $Root -Sequence 1 -Text ('{"racer":' + $Racer + ',"body":"' + ("word " * 120) + '"}')) }
    [System.IO.File]::WriteAllLines($LogFile, [string[]]@($told, "END"))
    exit 0
}

$deadline = [datetime]::UtcNow.AddSeconds(300)
while (-not (Test-Path -LiteralPath $GoFile)) {
    if ([datetime]::UtcNow -gt $deadline) { throw "no go file within 300 s" }
    Start-Sleep -Milliseconds 20
}
$startTicks = [long]([System.IO.File]::ReadAllText($GoFile).Trim())

$log = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $Count; $i++) {
    $target = $startTicks + [long]$i * [long]$TickMs * 10000
    if ($Mode -ceq "requests") { $target = $target + [long]$requests[$i].offsetMs * 10000 }
    while ([datetime]::UtcNow.Ticks -lt $target) { }
    $line = ""
    if ($Mode -ceq "requests") {
        try {
            $answer = Invoke-HordeDecision -Operation "$($requests[$i].operation)" -Request $requests[$i].request -Root $Root
            if ($answer.state -ceq "known") {
                $v = $answer.value
                $sequence = 0; $attempts = 0; $flag = ""
                if ($null -ne $v.PSObject.Properties["sequence"]) { $sequence = $v.sequence }
                if ($null -ne $v.PSObject.Properties["attempts"]) { $attempts = $v.attempts }
                if ($null -ne $v.PSObject.Properties["message"] -and $v.message.arrivedAfterClosing) { $flag = "after-closing" }
                $line = "" + $i + "|known|" + $v.outcome + "|" + $sequence + "|" + $attempts + "|" + $flag + "|" + ("$($v.reason)" -replace "[\r\n|]", " ")
            } else { $line = "" + $i + "|" + $answer.state + "||0|0||" + ("$($answer.reason)" -replace "[\r\n|]", " ") }
        } catch { $line = "" + $i + "|threw||0|0||" + ("$($_.Exception.Message)" -replace "[\r\n|]", " ") }
    }
    elseif ($Mode -ceq "inbox") {
        # The two halves of `horde decisions inbox -Json`, as cli/commands/decisions.ps1 runs them, with
        # the pause between them where the printing would be.
        try {
            $first = Invoke-HordeDecisionCommand -Verb "inbox" -Given @{ Verb = "inbox"; Json = $true }
            $printed = @()
            $parsed = (@($first.lines)[0] | ConvertFrom-Json)
            if ($first.failure -eq "" -and $parsed.state -ceq "known") { $printed = @($parsed.value.messages | ForEach-Object { $_.message.sequence }) }
            if ($PauseMs -gt 0) { Start-Sleep -Milliseconds $PauseMs }
            $second = Complete-HordeDecisionCommand -After $first.after
            $line = "" + $i + "|" + ($printed -join ",") + "|" + ("$($first.failure)$($second.failure)" -replace "[\r\n|]", " ")
        } catch { $line = "" + $i + "||threw: " + ("$($_.Exception.Message)" -replace "[\r\n|]", " ") }
    }
    elseif ($Mode -ceq "store") {
        try { $line = "" + $i + "|" + (Add-HordeDecisionRecord -Root $Root -Sequence ($i + 1) -Text ('{"racer":' + $Racer + ',"index":' + $i + '}')) + "|" }
        catch { $line = "" + $i + "|threw|" + ("$($_.Exception.Message)" -replace "[\r\n|]", " ") }
    } else {
        # 32 hex digits, different for every racer and question: each add is its own request.
        $id = ([long]($Racer + 1)).ToString("x16") + ([long]($i + 1)).ToString("x16")
        $question = @{ title = ("Does racer " + $Racer + " keep its question " + $i + " in this race?"); kind = "yes-no"; whatItIs = "Several processes add at once."; group = "the race"; askedBy = ("racer-" + $Racer) }
        try {
            $answer = Invoke-HordeDecision -Operation "add" -Request @{ id = $id; actor = "warchief"; question = $question } -Root $Root
            if ($answer.state -ceq "known") {
                $v = $answer.value
                $number = 0; $sequence = 0; $attempts = 0
                if ($null -ne $v.PSObject.Properties["number"]) { $number = $v.number }
                if ($null -ne $v.PSObject.Properties["sequence"]) { $sequence = $v.sequence }
                if ($null -ne $v.PSObject.Properties["attempts"]) { $attempts = $v.attempts }
                $line = "" + $i + "|known|" + $v.outcome + "|" + $number + "|" + $sequence + "|" + $attempts + "|" + ("$($v.reason)" -replace "[\r\n|]", " ")
            } else { $line = "" + $i + "|" + $answer.state + "||0|0|0|" + ("$($answer.reason)" -replace "[\r\n|]", " ") }
        } catch { $line = "" + $i + "|threw||0|0|0|" + ("$($_.Exception.Message)" -replace "[\r\n|]", " ") }
    }
    [void]$log.Add($line)
}
[void]$log.Add("END")
[System.IO.File]::WriteAllLines($LogFile, [string[]]$log.ToArray())
exit 0
