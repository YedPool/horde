# One racer for test/test-decisions-store-race.ps1. Not a suite: it is started as its own process,
# several at once, all aimed at ONE decisions store, and it races the others in one of two ways.
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
# What it is TOLD goes to -LogFile, one line an attempt, fields separated by |:
#   store:       index|created or exists or threw|reason
#   operations:  index|state|outcome|number|sequence|attempts|reason
# The suite compares what every racer was told with what the store holds afterwards.
#
# The ticks come from the wall clock every racer reads, as in test/fixtures/journal/race-worker.ps1:
# its coarse resolution (about 15.6 ms on Windows by default) makes the racers start together rather
# than take turns.
param(
    [Parameter(Mandatory = $true)][ValidateSet("store", "operations")][string]$Mode,
    [Parameter(Mandatory = $true)][string]$CodePath,
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$GoFile,
    [Parameter(Mandatory = $true)][string]$ReadyFile,
    [Parameter(Mandatory = $true)][string]$LogFile,
    [Parameter(Mandatory = $true)][int]$Racer,
    [Parameter(Mandatory = $true)][int]$Count,
    [Parameter(Mandatory = $true)][int]$TickMs
)
$ErrorActionPreference = "Stop"
. $CodePath
# Everything slow is done before the clock starts, so start-up is not part of the race.
if ($Mode -ceq "operations") { $null = Get-HordeDecisionDefinitions }
[System.IO.File]::WriteAllText($ReadyFile, "ready")

$deadline = [datetime]::UtcNow.AddSeconds(300)
while (-not (Test-Path -LiteralPath $GoFile)) {
    if ([datetime]::UtcNow -gt $deadline) { throw "no go file within 300 s" }
    Start-Sleep -Milliseconds 20
}
$startTicks = [long]([System.IO.File]::ReadAllText($GoFile).Trim())

$log = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $Count; $i++) {
    $target = $startTicks + [long]$i * [long]$TickMs * 10000
    while ([datetime]::UtcNow.Ticks -lt $target) { }
    $line = ""
    if ($Mode -ceq "store") {
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
