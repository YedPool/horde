# CAN WORDS SAID UNDER A QUESTION BE LOST BETWEEN TWO PROCESSES, OR MARKED READ WITHOUT BEING SEEN?
#
# The races are real: separate powershell.exe processes (test/fixtures/decisions/race-worker.ps1), aimed
# at one store, acting on the same wall-clock ticks. Each writes down what it was TOLD, and the suite
# then reads the store itself and compares. Three things only real processes can show:
#   I.   A SAY RACING A CLOSE. One process closes a question on the tick another says something under
#        it. Whichever lands first, the words must be in the store, the close must stand, and the words
#        must be flagged "arrived after closing" exactly when the close's record is the earlier one.
#   II.  AN INBOX RACING A NEW MESSAGE. One process runs `horde decisions inbox` as the command runs it
#        - print, then mark what was printed - while another keeps saying new things, each landing
#        between a printing and its marking. No message may be marked read that was not printed.
#   III. A WRITER KILLED INSIDE A SAY, AND INSIDE A MARKING, at a named step: before its record has its
#        name, and just after. Either the whole message is in the store or nothing is; the writer was
#        told nothing; and the same request sent again leaves exactly one message, and loses no word.
#
# A RACE THAT NEVER COLLIDES PROVES NOTHING, so each has its controls:
#   - I:  two rounds are not races - the close is sent well before the say, and well after - and must
#         come out the two ways, so that the flag is seen to tell them apart; and across the racing
#         rounds at least one write must say it took more than one try, which happens only when the
#         other process took its place.
#   - II: at least one message must have landed between a printing and its marking; and the same race
#         against a copy of the module that marks everything unread, ignoring what was printed, must
#         be seen to lose a message - or this harness could not have seen it here.
#
# Every store is a fresh folder under %TEMP% that this suite made and removes (CONTRIBUTING 9). The
# machine this was written on was throttled (2026-10-06): one operation takes about a second there,
# so the ticks are 2 s apart and each race is two processes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "decisions\Operations.ps1")

$worker = Join-Path $root "test\fixtures\decisions\race-worker.ps1"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:work = Join-Path $env:TEMP ("horde-decisions-threads-race-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$tickMs = 2000

function New-RaceFolder { param([string]$Name) $dir = Join-Path $script:work $Name; New-Item -ItemType Directory -Path $dir | Out-Null; return [pscustomobject]@{ dir = $dir; home = (Join-Path $dir "home"); store = (Join-Path $dir "home\store\decisions") } }
function New-Id { return [guid]::NewGuid().ToString("N") }
function Add-Question { param([string]$Store, [int]$Index) return (Invoke-HordeDecision -Operation "add" -Root $Store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = ("Is question " + $Index + " of this race kept as it was asked?"); kind = "yes-no"; whatItIs = "Two processes act on it at once."; group = "the race"; askedBy = "the-suite" } }) }
function Write-RequestFile { param([string]$Path, $Value) [System.IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth 8), $utf8) }
function Get-StoreRecords { param([string]$Store) return @((Get-HordeDecisionRecords -Root $Store).records | Where-Object { $_.kind -ceq "ok" } | ForEach-Object { $_.data }) }

function Start-Racer {
    # One racer process. Returns { p; out; err; ready; log }.
    param($Folder, [string]$Name, [string]$Mode, [string]$Code, [int]$Count, [string]$RequestFile = "", [int]$PauseMs = 0, [string]$GoFile = "")
    if ($GoFile -eq "") { $GoFile = Join-Path $Folder.dir "go.txt" }
    $ready = Join-Path $Folder.dir ("ready-" + $Name)
    $log = Join-Path $Folder.dir ("log-" + $Name + ".txt")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = ("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + $worker + "`" -Mode " + $Mode + " -CodePath `"" + $Code + "`" -Root `"" + $Folder.store +
        "`" -GoFile `"" + $GoFile + "`" -ReadyFile `"" + $ready + "`" -LogFile `"" + $log + "`" -Racer 1 -Count " + $Count + " -TickMs " + $tickMs + " -PauseMs " + $PauseMs +
        $(if ($RequestFile -ne "") { " -RequestFile `"" + $RequestFile + "`"" } else { "" }))
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    # A racer must never find the real store, whatever it is handed: its home is the race's own.
    $psi.EnvironmentVariables["HORDE_HOME"] = $Folder.home
    $p = [System.Diagnostics.Process]::Start($psi)
    return [pscustomobject]@{ p = $p; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync(); ready = $ready; log = $log; name = $Name }
}

function Invoke-RacePair {
    # Start the racers given, wait until each has loaded its code, give them one start tick, and wait
    # for them to end. Returns { problems; logs }: logs is a table of each racer's lines, split into
    # fields, by its name. Only the processes this started are ever killed, by the handles held here.
    param($Folder, [object[]]$Racers)
    $problems = New-Object System.Collections.ArrayList
    $logs = @{}
    try {
        $deadline = (Get-Date).AddSeconds(240)
        while (@($Racers | Where-Object { -not (Test-Path -LiteralPath $_.ready) }).Count -gt 0) {
            if ((Get-Date) -gt $deadline) { [void]$problems.Add("not every racer was ready within 240 s"); break }
            if (@($Racers | Where-Object { $_.p.HasExited }).Count -gt 0) { [void]$problems.Add("a racer exited before it was ready"); break }
            Start-Sleep -Milliseconds 50
        }
        $go = Join-Path $Folder.dir "go.txt"
        # One second ahead, so that a racer told to act before the tick (a negative offset) still can.
        [System.IO.File]::WriteAllText(($go + ".tmp"), ([datetime]::UtcNow.AddMilliseconds(1500).Ticks).ToString())
        [System.IO.File]::Move(($go + ".tmp"), $go)
        foreach ($x in $Racers) {
            if (-not $x.p.WaitForExit(480000)) { [void]$problems.Add("racer " + $x.name + " ran past 480 s without finishing"); continue }
            $x.p.WaitForExit()
            if ($x.p.ExitCode -ne 0) { [void]$problems.Add("racer " + $x.name + " exited " + $x.p.ExitCode + ": " + $x.err.Result) }
        }
    } finally {
        foreach ($x in $Racers) { if (-not $x.p.HasExited) { try { $x.p.Kill() } catch { } }; $x.p.Dispose() }
    }
    foreach ($x in $Racers) {
        $lines = New-Object System.Collections.ArrayList
        if (-not (Test-Path -LiteralPath $x.log)) { [void]$problems.Add("racer " + $x.name + " left no log") }
        else { foreach ($line in [System.IO.File]::ReadAllLines($x.log)) { if ($line -cne "END") { [void]$lines.Add($line.Split("|")) } } }
        $logs[$x.name] = @($lines)
    }
    return [pscustomobject]@{ problems = @($problems); logs = $logs }
}

function Invoke-InboxRace {
    # Race II against the module at -CodeRoot: one process says -Messages things, one a tick; the other
    # runs the inbox command's two halves on every tick, starting before the say and marking after it.
    # Returns { problems; said; printed; lost; between; unreadAtEnd; marks }.
    param([string]$Name, [string]$CodeRoot, [int]$Messages)
    $f = New-RaceFolder $Name
    $null = Add-Question $f.store 1
    $sayFile = Join-Path $f.dir "say.json"
    Write-RequestFile $sayFile @(0..($Messages - 1) | ForEach-Object { @{ offsetMs = 0; operation = "say"; request = @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "founder"; route = "chat-recorded"; text = ("message " + $_ + " of the race") } } })
    $sayer = Start-Racer -Folder $f -Name "sayer" -Mode "requests" -Code (Join-Path $CodeRoot "decisions\Operations.ps1") -Count $Messages -RequestFile $sayFile
    # The reader begins each round well before the tick and waits past it before it marks, so that the
    # say of that tick lands between its printing and its marking. Two rounds more than there are
    # messages, so the last ones are printed too.
    $readerGo = Join-Path $f.dir "go-reader.txt"
    $reader = Start-Racer -Folder $f -Name "reader" -Mode "inbox" -Code (Join-Path $CodeRoot "decisions\Console.ps1") -Count ($Messages + 2) -PauseMs 1000 -GoFile $readerGo
    $problems = New-Object System.Collections.ArrayList
    $logs = @{}
    try {
        $deadline = (Get-Date).AddSeconds(240)
        while (@(@($sayer, $reader) | Where-Object { -not (Test-Path -LiteralPath $_.ready) }).Count -gt 0) {
            if ((Get-Date) -gt $deadline) { [void]$problems.Add("not every racer was ready within 240 s"); break }
            if (@(@($sayer, $reader) | Where-Object { $_.p.HasExited }).Count -gt 0) { [void]$problems.Add("a racer exited before it was ready"); break }
            Start-Sleep -Milliseconds 50
        }
        # The reader's clock starts 700 ms before the sayer's: its printing half is under way when the say begins.
        $start = [datetime]::UtcNow.AddMilliseconds(1500)
        foreach ($pair in @(@((Join-Path $f.dir "go.txt"), $start), @($readerGo, $start.AddMilliseconds(-700)))) {
            [System.IO.File]::WriteAllText(($pair[0] + ".tmp"), ($pair[1].Ticks).ToString())
            [System.IO.File]::Move(($pair[0] + ".tmp"), $pair[0])
        }
        foreach ($x in @($sayer, $reader)) {
            if (-not $x.p.WaitForExit(480000)) { [void]$problems.Add("racer " + $x.name + " ran past 480 s without finishing"); continue }
            $x.p.WaitForExit()
            if ($x.p.ExitCode -ne 0) { [void]$problems.Add("racer " + $x.name + " exited " + $x.p.ExitCode + ": " + $x.err.Result) }
        }
    } finally {
        foreach ($x in @($sayer, $reader)) { if (-not $x.p.HasExited) { try { $x.p.Kill() } catch { } }; $x.p.Dispose() }
    }
    foreach ($x in @($sayer, $reader)) {
        $lines = New-Object System.Collections.ArrayList
        if (-not (Test-Path -LiteralPath $x.log)) { [void]$problems.Add("racer " + $x.name + " left no log") }
        else { foreach ($line in [System.IO.File]::ReadAllLines($x.log)) { if ($line -cne "END") { [void]$lines.Add($line.Split("|")) } } }
        $logs[$x.name] = @($lines)
    }
    # What the store holds, read here: every message, and every marking with how far it marked.
    $records = @(Get-StoreRecords $f.store)
    $said = @($records | Where-Object { $_.kind -ceq "message-said" } | ForEach-Object { [long]$_.sequence })
    $marks = @($records | Where-Object { $_.kind -ceq "messages-read" } | ForEach-Object { [pscustomobject]@{ sequence = [long]$_.sequence; upTo = [long]$_.data.upTo } })
    $printed = New-Object 'System.Collections.Generic.HashSet[long]'
    foreach ($line in @($logs["reader"])) { foreach ($piece in @("$($line[1])".Split(",") | Where-Object { $_ -ne "" })) { [void]$printed.Add([long]$piece) } }
    $markedUpTo = [long]0
    foreach ($m in $marks) { if ($m.upTo -gt $markedUpTo) { $markedUpTo = $m.upTo } }
    # LOST: a message the store says is read, that the reader never printed.
    $lost = @($said | Where-Object { $_ -le $markedUpTo -and -not $printed.Contains($_) })
    # BETWEEN: a message whose record is after what a marking marked up to, and before that marking's
    # own record - it landed between the printing and the marking.
    $between = @($said | Where-Object { $seq = $_; @($marks | Where-Object { $seq -gt $_.upTo -and $seq -lt $_.sequence }).Count -gt 0 })
    return [pscustomobject]@{ problems = @($problems); said = $said; printed = @($printed); lost = $lost; between = $between
        unreadAtEnd = @($said | Where-Object { $_ -gt $markedUpTo }); marks = $marks
        failures = @(@($logs["reader"]) | Where-Object { "$($_[2])" -ne "" } | ForEach-Object { "$($_[2])" })
        sayOutcomes = @(@($logs["sayer"]) | ForEach-Object { "$($_[1])" + " " + "$($_[2])" }) }
}

function Start-StalledWriter {
    # Start a writer that makes the one request in -RequestFile and stops inside its write at -Mode's
    # step (the worker says how). Returns { problems; proc; log }. The caller kills it with
    # Stop-StalledWriter; only the process this started is ever killed.
    param($Folder, [string]$Name, [string]$Mode, [string]$RequestFile)
    $mark = Join-Path $Folder.dir ("stalled-" + $Name)
    $racer = Start-Racer -Folder $Folder -Name $Name -Mode $Mode -Code (Join-Path $root "decisions\Operations.ps1") -Count 1 -RequestFile $RequestFile -GoFile $mark
    $problems = New-Object System.Collections.ArrayList
    $deadline = (Get-Date).AddSeconds(240)
    while (-not (Test-Path -LiteralPath $mark) -and -not $racer.p.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 20 }
    if (-not (Test-Path -LiteralPath $mark)) { [void]$problems.Add("the writer did not reach its step within 240 s" + $(if ($racer.p.HasExited) { " (it exited " + $racer.p.ExitCode + ": " + $racer.err.Result + ")" } else { "" })) }
    elseif ($racer.p.HasExited) { [void]$problems.Add("the writer had ended by itself at its step") }
    return [pscustomobject]@{ problems = $problems; proc = $racer.p; log = $racer.log }
}
function Stop-StalledWriter {
    param($Writer)
    try {
        if (-not $Writer.proc.HasExited) { try { $Writer.proc.Kill() } catch { [void]$Writer.problems.Add("the writer could not be killed: " + $_.Exception.Message) } }
        if (-not $Writer.proc.WaitForExit(30000)) { [void]$Writer.problems.Add("the writer was still running 30 s after the kill") }
    } finally { $Writer.proc.Dispose() }
}

try {

$opsCode = Join-Path $root "decisions\Operations.ps1"

Write-Host ""
Write-Host "--- I. one process closes a question on the tick another says something under it ---" -ForegroundColor Cyan
# Six questions, one a tick. Round 0: the close is sent 1.4 s before the say - not a race, the close
# is first. Round 1: 1.4 s after - the say is first. Rounds 2 to 5: the same tick, give or take 20 ms.
$rounds = 6
$offsets = @(-1400, 1400, 0, 0, -20, 20)
$f = New-RaceFolder "close-say"
foreach ($i in 1..$rounds) { $null = Add-Question $f.store $i }
$closeFile = Join-Path $f.dir "close.json"
$sayFile = Join-Path $f.dir "say.json"
Write-RequestFile $closeFile @(0..($rounds - 1) | ForEach-Object { @{ offsetMs = $offsets[$_]; operation = "close"; request = @{ id = (New-Id); actor = "warchief"; number = ($_ + 1); outcome = ("Closed in round " + $_ + ".") } } })
Write-RequestFile $sayFile @(0..($rounds - 1) | ForEach-Object { @{ offsetMs = 0; operation = "say"; request = @{ id = (New-Id); actor = "warchief"; number = ($_ + 1); speaker = "founder"; route = "chat-recorded"; text = ("said in round " + $_ + ", as it was being closed") } } })
$race = Invoke-RacePair -Folder $f -Racers @(
    (Start-Racer -Folder $f -Name "closer" -Mode "requests" -Code $opsCode -Count $rounds -RequestFile $closeFile),
    (Start-Racer -Folder $f -Name "sayer" -Mode "requests" -Code $opsCode -Count $rounds -RequestFile $sayFile))
Check (@($race.problems).Count -eq 0) "both racers started, ran and exited cleanly"
foreach ($pr in @($race.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
$closes = @($race.logs["closer"]); $says = @($race.logs["sayer"])
Check ($closes.Count -eq $rounds -and $says.Count -eq $rounds) ("each racer was answered for every round (" + $closes.Count + " closes, " + $says.Count + " says)")
Check (@($says | Where-Object { -not ($_[1] -ceq "known" -and $_[2] -ceq "done") }).Count -eq 0) ("EVERY say was told done: not one was refused because its question was being closed, and not one could not tell (" + (@($says | ForEach-Object { $_[2] }) -join ",") + ")")
foreach ($odd in @($says | Where-Object { -not ($_[1] -ceq "known" -and $_[2] -ceq "done") } | Select-Object -First 4)) { Write-Host ("         say " + $odd[0] + ": " + $odd[1] + " " + $odd[2] + " " + $odd[6]) -ForegroundColor Red }
Check (@($closes | Where-Object { -not ($_[1] -ceq "known" -and $_[2] -ceq "done") }).Count -eq 0) "and every close was told done"
# What the store holds, read here and not taken from the racers.
$listed = Invoke-HordeDecision -Operation "list" -Request @{ state = "all" } -Root $f.store
$records = @(Get-StoreRecords $f.store)
$wrong = New-Object System.Collections.ArrayList
$flagged = 0; $unflagged = 0
foreach ($i in 1..$rounds) {
    $shown = Invoke-HordeDecision -Operation "show" -Request @{ number = $i } -Root $f.store
    if ($shown.state -cne "known") { [void]$wrong.Add("question " + $i + " could not be shown: " + $shown.reason); continue }
    $q = $shown.value.question
    $closeSeq = [long](@($records | Where-Object { $_.kind -ceq "question-closed" -and $_.data.number -eq $i }) | Select-Object -First 1).sequence
    $saySeq = [long](@($records | Where-Object { $_.kind -ceq "message-said" -and $_.data.number -eq $i }) | Select-Object -First 1).sequence
    if ($q.state -cne "closed") { [void]$wrong.Add("question " + $i + " is " + $q.state + ", not closed") }
    if ($q.thread.count -ne 1 -or $q.thread.messages[0].text -cne ("said in round " + ($i - 1) + ", as it was being closed")) { [void]$wrong.Add("question " + $i + " does not hold its one message, whole"); continue }
    $shouldFlag = ($closeSeq -lt $saySeq)
    if ([bool]$q.thread.messages[0].arrivedAfterClosing -ne $shouldFlag) { [void]$wrong.Add("question " + $i + ": close is record " + $closeSeq + ", say is record " + $saySeq + ", and the message's flag is " + $q.thread.messages[0].arrivedAfterClosing) }
    if ($shouldFlag) { $flagged++ } else { $unflagged++ }
}
Write-Host ("  " + $rounds + " rounds: " + $flagged + " say(s) landed after the close, " + $unflagged + " before it; tries: closes " + (@($closes | ForEach-Object { $_[4] }) -join ",") + "; says " + (@($says | ForEach-Object { $_[4] }) -join ",")) -ForegroundColor DarkGray
Check ($wrong.Count -eq 0) "in the store, every question is closed and holds its one message, whole - and the message is flagged 'arrived after closing' exactly when the close's record is the earlier one"
foreach ($w in $wrong) { Write-Host ("         " + $w) -ForegroundColor Red }
Check ($listed.state -ceq "known" -and @($listed.value.unreadable).Count -eq 0 -and @($listed.value.ignored).Count -eq 0 -and $records.Count -eq (3 * $rounds)) ("the store holds " + (3 * $rounds) + " records - asked, closed, said, for each - with nothing unreadable and nothing ignored (" + $records.Count + ")")
Check ((Invoke-HordeDecision -Operation "show" -Request @{ number = 1 } -Root $f.store).value.question.thread.messages[0].arrivedAfterClosing -eq $true -and (Invoke-HordeDecision -Operation "show" -Request @{ number = 2 } -Root $f.store).value.question.thread.messages[0].arrivedAfterClosing -eq $false) "CONTROL: the round whose close was sent well before the say is flagged, and the round whose close was sent well after is not - the flag tells the two orders apart"
$retries = [int](@(@($closes) + @($says) | ForEach-Object { [int]$_[4] - 1 }) | Measure-Object -Sum).Sum
Check ($retries -ge 1) ("CONTROL: at least one write lost its place to the other process and tried again, so the two met (" + $retries + " extra tries)")

Write-Host ""
Write-Host "--- II. the inbox command, print then mark, while another process keeps saying new things ---" -ForegroundColor Cyan
$messages = 5
$real = Invoke-InboxRace -Name "inbox-real" -CodeRoot $root -Messages $messages
Write-Host ("  real module: said " + ($real.said -join ",") + "; printed " + (@($real.printed | Sort-Object) -join ",") + "; markings " + (@($real.marks | ForEach-Object { "" + $_.sequence + " up to " + $_.upTo }) -join "; ") + "; landed between a printing and its marking " + ($real.between -join ",") + "; lost " + ($real.lost -join ",")) -ForegroundColor DarkGray
Check (@($real.problems).Count -eq 0) "both racers started, ran and exited cleanly"
foreach ($pr in @($real.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
Check (@($real.said).Count -eq $messages -and @($real.sayOutcomes | Where-Object { $_ -cne "known done" }).Count -eq 0) ("every one of the " + $messages + " messages was told done and is in the store (" + @($real.said).Count + ")")
Check (@($real.failures).Count -eq 0) ("the inbox command never failed to read or to mark" + $(if (@($real.failures).Count) { " (" + ($real.failures[0]) + ")" } else { "" }))
Check (@($real.lost).Count -eq 0) ("NO MESSAGE WAS MARKED READ WITHOUT BEING PRINTED (" + @($real.lost).Count + " lost)")
Check (@($real.said | Where-Object { $real.printed -notcontains $_ -and $real.unreadAtEnd -notcontains $_ }).Count -eq 0) "every message was either printed by the inbox or is still unread at the end: none is nowhere"
Check (@($real.marks).Count -ge 2) ("CONTROL: the inbox did mark, several times (" + @($real.marks).Count + " markings)")
Check (@($real.between).Count -ge 1) ("CONTROL: at least one message landed between a printing and its marking, so the race was run (" + @($real.between).Count + ")")
Check (@($real.between | Where-Object { $real.printed -notcontains $_ -and $real.unreadAtEnd -notcontains $_ }).Count -eq 0) "and each message that landed there was left unread by that marking, and printed by a later one or still unread"
# CONTROL: the same race against a copy of the module whose marking ignores what was printed and marks
# everything unread. It must be seen to mark a message nobody printed.
$broken = Join-Path $script:work "broken-tree"
foreach ($folder in @("decisions", "core", "schema")) { Copy-Item -LiteralPath (Join-Path $root $folder) -Destination (Join-Path $broken $folder) -Recurse }
$opsCopy = Join-Path $broken "decisions\Operations.ps1"
$src = [System.IO.File]::ReadAllText($opsCopy)
$find = 'if ([long]$Data["upTo"] -gt 0) { $bound = [long]$Data["upTo"] }'
Check (([regex]::Matches($src, [regex]::Escape($find))).Count -eq 1) "the control's edit matches exactly once in decisions/Operations.ps1"
[System.IO.File]::WriteAllText($opsCopy, $src.Replace($find, ''))
$bad = Invoke-InboxRace -Name "inbox-broken" -CodeRoot $broken -Messages $messages
Write-Host ("  module that marks everything unread: said " + ($bad.said -join ",") + "; printed " + (@($bad.printed | Sort-Object) -join ",") + "; markings " + (@($bad.marks | ForEach-Object { "" + $_.sequence + " up to " + $_.upTo }) -join "; ") + "; lost " + ($bad.lost -join ",")) -ForegroundColor DarkGray
Check (@($bad.problems).Count -eq 0) "the control's racers ran cleanly"
Check (@($bad.lost).Count -ge 1) ("CONTROL: when the marking ignores what was printed, this race sees a message marked read that nobody printed (" + @($bad.lost).Count + " lost)")

Write-Host ""
Write-Host "--- III. a writer killed inside a say, and inside a marking, at a named step ---" -ForegroundColor Cyan
# Hebrew with a right-to-left mark, and two lines: the words must be whole or absent, never part.
$words = "" + [char]0x05DB + [char]0x05DF + [char]0x200F + ", do it." + "`r`n" + ("and a second line of it " * 40)
foreach ($step in @("stall-before-move", "stall-after-move")) {
    $f = New-RaceFolder ("say-" + $step)
    $null = Add-Question $f.store 1
    $request = @{ id = ("cd" * 16); actor = "warchief"; number = 1; speaker = "founder"; route = "chat-recorded"; text = $words }
    $requestFile = Join-Path $f.dir "request.json"
    Write-RequestFile $requestFile @{ operation = "say"; request = $request }
    $w = Start-StalledWriter -Folder $f -Name "sayer" -Mode $step -RequestFile $requestFile
    Stop-StalledWriter $w
    foreach ($pr in @($w.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
    Check (@($w.problems).Count -eq 0 -and -not (Test-Path -LiteralPath $w.log)) ("a say was stopped at " + $step + " and killed before it was told anything")
    $thread = (Invoke-HordeDecision -Operation "show" -Request @{ number = 1 } -Root $f.store).value.question.thread
    if ($step -ceq "stall-before-move") { Check ($thread.count -eq 0) ("killed before the move, NOTHING of the message is in the store (" + $thread.count + " message(s))") }
    else { Check ($thread.count -eq 1 -and [string]::Equals($thread.messages[0].text, $words, [System.StringComparison]::Ordinal)) "killed after the move, the WHOLE message is in the store, character for character" }
    $again = Invoke-HordeDecision -Operation "say" -Request $request -Root $f.store
    $expected = "done"; if ($step -ceq "stall-after-move") { $expected = "replayed" }
    Check ($again.state -ceq "known" -and $again.value.outcome -ceq $expected -and [string]::Equals($again.value.message.text, $words, [System.StringComparison]::Ordinal)) ("the same request sent again, same id, is " + $expected + ", and answers with the words (" + $again.state + $(if ($again.state -ceq "known") { " " + $again.value.outcome } else { ": " + $again.reason }) + ")")
    $thread = (Invoke-HordeDecision -Operation "show" -Request @{ number = 1 } -Root $f.store).value.question.thread
    Check ($thread.count -eq 1 -and [string]::Equals($thread.messages[0].text, $words, [System.StringComparison]::Ordinal) -and @(Get-StoreRecords $f.store | Where-Object { $_.kind -ceq "message-said" }).Count -eq 1) "and the thread holds the message exactly once, whole"
}
foreach ($step in @("stall-before-move", "stall-after-move")) {
    $f = New-RaceFolder ("mark-" + $step)
    $null = Add-Question $f.store 1
    $null = Invoke-HordeDecision -Operation "say" -Root $f.store -Request @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "founder"; route = "chat-recorded"; text = $words }
    $request = @{ id = ("ef" * 16); actor = "warchief"; mark = $true }
    $requestFile = Join-Path $f.dir "request.json"
    Write-RequestFile $requestFile @{ operation = "inbox"; request = $request }
    $w = Start-StalledWriter -Folder $f -Name "reader" -Mode $step -RequestFile $requestFile
    Stop-StalledWriter $w
    foreach ($pr in @($w.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
    Check (@($w.problems).Count -eq 0 -and -not (Test-Path -LiteralPath $w.log)) ("a marking was stopped at " + $step + " and killed before it was handed the words")
    $unread = @((Invoke-HordeDecision -Operation "inbox" -Request @{ actor = "warchief" } -Root $f.store).value.messages).Count
    if ($step -ceq "stall-before-move") { Check ($unread -eq 1) ("killed before the move, nothing is marked: the message is still unread (" + $unread + ")") }
    else { Check ($unread -eq 0) ("killed after the move, the marking is in the store - and its caller never got the words (" + $unread + " unread)") }
    # THE WORDS ARE NOT LOST EITHER WAY: the same request sent again, same id, hands them over.
    $again = Invoke-HordeDecision -Operation "inbox" -Request $request -Root $f.store
    $expected = "done"; if ($step -ceq "stall-after-move") { $expected = "replayed" }
    Check ($again.state -ceq "known" -and $again.value.outcome -ceq $expected -and @($again.value.messages).Count -eq 1 -and [string]::Equals($again.value.messages[0].message.text, $words, [System.StringComparison]::Ordinal) -and $again.value.marked -eq 1) ("the same marking sent again, same id, is " + $expected + " and hands over the words: a reader that died holding a marking has not lost them (" + $again.state + $(if ($again.state -ceq "known") { " " + $again.value.outcome } else { ": " + $again.reason }) + ")")
    Check (@(Get-StoreRecords $f.store | Where-Object { $_.kind -ceq "messages-read" }).Count -eq 1) "and there is exactly one marking in the store"
}

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-decisions-threads-race-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the race's temp folder is removed"

Complete-HordeSuite -Success "between racing processes no word said under a question is lost, none is marked read unseen, and each race can see the failure it guards against"
