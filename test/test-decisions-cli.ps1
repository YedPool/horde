# DOES `horde decisions` DO, AT A REAL COMMAND LINE, WHAT THE OPERATIONS PROMISE - AND SAY IT SO A PERSON
# CAN READ IT?
#
# The shipped horde.ps1, run as its own process the way a script or a session runs it
# (test/lib/Cli.ps1), against a home this suite made. It starts no pane and touches no terminal, so
# it needs no isolated one (CONTRIBUTING 2 and 3). What it attacks is the caller's own side, the part
# decisions/Operations.ps1 cannot answer for:
#   - text in another alphabet and a 100,000-character text survive the trip in through a file and
#     out through -Json, character for character, whatever code page the console is in;
#   - a refusal prints its reasons and exits 1; a refused secret is not printed back;
#   - a flag given to the wrong verb, a missing number and an unreadable file are refused, not ignored;
#   - a damaged record is named in what a person reads, not only in the data;
#   - HORDE_HOME decides where the store is, and nothing is ever written to the real one.
# The user story from an empty list to a reopened question is test/e2e/e2e-decisions.ps1.
#
# Each call starts powershell.exe, about 5 s on the throttled machine this was written on (2026-10-06),
# so the checks are packed into few calls.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")

$script:work = Join-Path $env:TEMP ("horde-decisions-cli-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$store = Join-Path $hordeHome "store\decisions"
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-RealStoreListing {
    # What the real store holds, WITHOUT touching it. Read from the profile directly, not through
    # HORDE_HOME, which a gate may have set.
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing

function Invoke-Decisions {
    # `horde decisions <args>` as its own process, with HORDE_HOME aimed at this suite's home unless
    # -Env says otherwise. Returns { code; out; lines }.
    param([string[]]$HordeArgs, [hashtable]$Env = $null)
    if ($null -eq $Env) { $Env = @{ HORDE_HOME = $hordeHome } }
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs (@("decisions") + $HordeArgs) -Env $Env
    return [pscustomobject]@{ code = $r.code; out = $r.out; lines = @($r.out -split "\r?\n") }
}
function Get-JsonLine {
    # The one line of a -Json answer, parsed; $null when the output holds no such line.
    param($Run)
    $line = @($Run.lines | Where-Object { $_.StartsWith('{"state":') }) | Select-Object -First 1
    if ($null -eq $line) { return $null }
    try { return ($line | ConvertFrom-Json) } catch { return $null }
}
function Write-Json { param([string]$Name, [string]$Text) $p = Join-Path $script:work $Name; [System.IO.File]::WriteAllText($p, $Text, $utf8); return $p }
function Get-Files { if (-not (Test-Path -LiteralPath $store)) { return "" }; return (@(Get-ChildItem -LiteralPath $store -File | Sort-Object Name | ForEach-Object { $_.Name }) -join ",") }

try {

# Hebrew as escapes (CONTRIBUTING 13), with a quote, a backslash and angle brackets beside it.
$hebrew = "" + [char]0x05D4 + [char]0x05D0 + [char]0x05DD + " " + [char]0x05DC + [char]0x05D4 + [char]0x05E9 + [char]0x05DE + [char]0x05D9 + [char]0x05E2 + " " + [char]0x05E6 + [char]0x05DC + [char]0x05D9 + [char]0x05DC + " " + [char]0x05E1 + [char]0x05D2 + [char]0x05D9 + [char]0x05E8 + [char]0x05D4 + "?"
$title = "Should a closing sound play? " + $hebrew
$long = ("word " * 19999) + "end!!"
$tricky = $hebrew + ' "quoted" \back\slash <tag> & done'
$question = [ordered]@{ title = $title; kind = "choice"; options = @("a tone", "a spoken line", $hebrew); whatItIs = $long; yesMeans = $tricky; group = "voice"; groupNote = "How the assistant closes a conversation."
    askedBy = "orc-b"; waiting = @("orc-b"); files = @("notes\closing-proposal.html"); references = @("PR 1583") }
# The file is written as UTF-8 by this suite, with the Hebrew as its own bytes: what an author's editor saves.
$questionFile = Write-Json "question.json" (ConvertTo-Json -InputObject $question -Depth 5)
$id = [guid]::NewGuid().ToString("N")

Write-Host ""
Write-Host "--- add, from a file, and the same command sent twice ---" -ForegroundColor Cyan
$add = Invoke-Decisions @("add", "-File", $questionFile, "-Id", $id, "-Json")
$j = Get-JsonLine $add
Check ($add.code -eq 0 -and $null -ne $j -and $j.state -ceq "known" -and $j.value.outcome -ceq "done" -and $j.value.number -eq 1) ("add exits 0 and its one line of data says done, number 1 (exit " + $add.code + ")")
if ($add.code -ne 0) { Write-Host ("         " + $add.out.Trim()) -ForegroundColor Red }
Check (@($add.lines | Where-Object { $_.Trim() -ne "" }).Count -eq 1 -and $add.out -cnotmatch '[^\x00-\x7F]') "-Json is exactly one line, and every character of it is ASCII"
Check ((Get-Files) -ceq "0000000001.json") "one record is in the store under this suite's HORDE_HOME"
$again = Invoke-Decisions @("add", "-File", $questionFile, "-Id", $id)
Check ($again.code -eq 0 -and $again.out -like "*Question 1: this request was already recorded (record 1), so nothing was written again.*" -and (Get-Files) -ceq "0000000001.json") "the same command with the same -Id says it was already recorded, exits 0, and writes nothing: one question, not two"

Write-Host ""
Write-Host "--- text comes back character for character ---" -ForegroundColor Cyan
$show = Invoke-Decisions @("show", "1", "-Json")
$j = Get-JsonLine $show
Check ($show.code -eq 0 -and $show.out -cnotmatch '[^\x00-\x7F]' -and $null -ne $j) "show -Json is one ASCII line"
Check ($null -ne $j -and [string]::Equals($j.value.question.title, $title, [System.StringComparison]::Ordinal)) "the Hebrew title comes back exactly, through a file, the store, a console and a pipe"
Check ($null -ne $j -and [string]::Equals($j.value.question.yesMeans, $tricky, [System.StringComparison]::Ordinal) -and [string]::Equals($j.value.question.options[2], $hebrew, [System.StringComparison]::Ordinal)) "so do the quote, the backslash and the angle brackets, and the Hebrew option"
Check ($null -ne $j -and $j.value.question.whatItIs.Length -eq 100000 -and [string]::Equals($j.value.question.whatItIs, $long, [System.StringComparison]::Ordinal)) "and all 100,000 characters of the background"
$list = Invoke-Decisions @("list", "-Json")
$j = Get-JsonLine $list
Check ($list.code -eq 0 -and $list.out -cnotmatch '[^\x00-\x7F]' -and $null -ne $j -and @($j.value.questions).Count -eq 1 -and [string]::Equals($j.value.questions[0].title, $title, [System.StringComparison]::Ordinal)) "list -Json gives the same title, exactly, on one ASCII line"

Write-Host ""
Write-Host "--- the words a person reads, through a pipe: the bytes, from two code pages ---" -ForegroundColor Cyan
# The session that keeps the list reads these commands through a pipe. Measured 2026-10-06, before the
# console set its own encoding for the print: the Hebrew title above came out of `show` as
# "??? ????? ?? ??????" - question marks, with nothing to say so. So the plain-text output is checked
# as BYTES, taken from the process's own output stream and decoded here as UTF-8, from a console in
# code page 437 and from one in 65001. cmd sets the code page (chcp) and starts the command in it.
function Get-OutputBytes {
    # Run a command line under cmd in code page -CodePage; returns { code; bytes }: what it wrote to
    # its standard output, undecoded.
    param([string]$CommandLine, [int]$CodePage)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/d /c chcp " + $CodePage + " >nul & " + $CommandLine
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_HOME"] = $hordeHome
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $errTask = $p.StandardError.ReadToEndAsync()
        $mem = New-Object System.IO.MemoryStream
        $p.StandardOutput.BaseStream.CopyTo($mem)
        $p.WaitForExit()
        $null = $errTask.Result
        return [pscustomobject]@{ code = $p.ExitCode; bytes = $mem.ToArray() }
    } finally { $p.Dispose() }
}
function Test-HoldsBytes {
    param([byte[]]$Hay, [byte[]]$Needle)
    for ($i = 0; $i -le $Hay.Length - $Needle.Length; $i++) {
        $same = $true
        for ($k = 0; $k -lt $Needle.Length; $k++) { if ($Hay[$i + $k] -ne $Needle[$k]) { $same = $false; break } }
        if ($same) { return $true }
    }
    return $false
}
$hordeLine = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $root "horde.ps1") + '" decisions '
$titleBytes = $utf8.GetBytes($title)
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
foreach ($page in @(437, 65001)) {
    foreach ($verbLine in @("show 1", "list")) {
        $got = Get-OutputBytes -CommandLine ($hordeLine + $verbLine) -CodePage $page
        $decodes = $true
        try { $null = $strictUtf8.GetString($got.bytes) } catch { $decodes = $false }
        Check ($got.code -eq 0 -and (Test-HoldsBytes $got.bytes $titleBytes)) ("from a console in code page " + $page + ", '" + $verbLine + "' through a pipe carries the Hebrew title as its own UTF-8 bytes")
        Check ($decodes -and -not (Test-HoldsBytes $got.bytes ([byte[]]@(0x3F, 0x3F, 0x3F)))) "and the whole output is valid UTF-8, with no run of question marks in it"
        Check ($got.bytes.Length -ge 3 -and -not ($got.bytes[0] -eq 0xEF -and $got.bytes[1] -eq 0xBB -and $got.bytes[2] -eq 0xBF)) "and no byte-order mark opens it"
    }
}
# CONTROL: the same letters written by a process that sets nothing, from code page 437, ARE question
# marks - so the reading above can see the failure it guards against.
$plainLine = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Write-Output ((' + (@($hebrew.ToCharArray() | ForEach-Object { "[char]" + [int]$_ }) -join "+") + '))"'
$control = Get-OutputBytes -CommandLine $plainLine -CodePage 437
Check ($control.code -eq 0 -and (Test-HoldsBytes $control.bytes ([byte[]]@(0x3F, 0x3F, 0x3F))) -and -not (Test-HoldsBytes $control.bytes ($utf8.GetBytes($hebrew)))) "CONTROL: a process that sets no encoding writes the same Hebrew as question marks from code page 437"
# The encoding is put back: a command that prints after horde, in the same console, is not changed.
$after = Get-OutputBytes -CommandLine ($hordeLine + 'list >nul & powershell.exe -NoProfile -Command "[Console]::OutputEncoding.CodePage"') -CodePage 437
Check (([System.Text.Encoding]::ASCII.GetString($after.bytes)).Trim() -ceq "437") ("after the command, the console's code page is what it was (" + ([System.Text.Encoding]::ASCII.GetString($after.bytes)).Trim() + ")")

Write-Host ""
Write-Host "--- what a person reads ---" -ForegroundColor Cyan
$text = Invoke-Decisions @("list")
Check ($text.code -eq 0 -and @($text.lines | Where-Object { $_ -ceq "Decisions: 1 open, 0 closed." }).Count -eq 1) "list opens with how many questions are open and closed, in words"
Check (@($text.lines | Where-Object { $_ -ceq "voice" }).Count -eq 1 -and @($text.lines | Where-Object { $_ -ceq "  (How the assistant closes a conversation.)" }).Count -eq 1) "the question sits under its group, with the group's note"
Check (@($text.lines | Where-Object { $_.StartsWith("  1. Should a closing sound play? ") }).Count -eq 1) "numbered with its permanent number, the question in its own words"
Check (@($text.lines | Where-Object { $_.Trim() -ceq "a choice among options; asked by orc-b; waiting: orc-b" }).Count -eq 1) "then its kind in words, who asked and who is waiting"
Check ($text.out -notmatch '\{"|schemaVersion|question-added|\.json') "and nothing of how the list is kept: no JSON, no record names"
$one = Invoke-Decisions @("show", "1")
Check ($one.code -eq 0 -and @($one.lines | Where-Object { $_ -ceq "Question 1 - open (wording 1)" }).Count -eq 1 -and @($one.lines | Where-Object { $_ -ceq "Kind: a choice among options. Answered by picking one of the options listed with the question." }).Count -eq 1) "show names the question, its state and wording, and says what its kind means"
Check (@($one.lines | Where-Object { $_ -ceq "  1. a tone" -or $_ -ceq "  2. a spoken line" }).Count -eq 2 -and @($one.lines | Where-Object { $_ -ceq "Recommendation: none given" }).Count -eq 1 -and @($one.lines | Where-Object { $_ -ceq "References: PR 1583" }).Count -eq 1) "its options are listed, a missing recommendation is said, and the reference is shown as a reference"

Write-Host ""
Write-Host "--- refusals say why, exit 1, and write nothing ---" -ForegroundColor Cyan
$refFile = Write-Json "reference.json" '{"title":"PR 1469?","kind":"yes-no","whatItIs":"See the pull request.","group":"voice","askedBy":"orc-b"}'
$ref = Invoke-Decisions @("add", "-File", $refFile)
Check ($ref.code -eq 1 -and $ref.out -like "*Refused:*the title is only a pull-request or issue reference*" -and (Get-Files) -ceq "0000000001.json") "a question whose title is just 'PR 1469?' is refused with the reason, exits 1, and is not stored"
$token = "gh" + "p_" + ("Qr7" * 12)
$secretFile = Write-Json "secret.json" ('{"title":"Should the test login be rotated this week?","kind":"yes-no","whatItIs":"The token is ' + $token + ' today.","group":"accounts","askedBy":"orc-d"}')
$sec = Invoke-Decisions @("add", "-File", $secretFile, "-Json")
$j = Get-JsonLine $sec
Check ($sec.code -eq 1 -and $null -ne $j -and $j.value.outcome -ceq "refused" -and "$($j.value.findings)" -like "*'whatItIs' holds what looks like an access token*") "a question holding a token is refused, naming the field and the kind of secret; -Json still prints its line, and the exit is 1"
Check (-not $sec.out.Contains($token) -and -not $sec.out.Contains("Qr7Qr7") -and (Get-Files) -ceq "0000000001.json") "the token is not printed back, on either stream, and nothing is stored"
$twiceFile = Write-Json "twice.json" '{"title":"Should the closing sound be a tone or a spoken line?","title":"PR 1469?","kind":"yes-no","whatItIs":"x","group":"voice","askedBy":"orc-b"}'
$twice = Invoke-Decisions @("add", "-File", $twiceFile)
Check ($twice.code -eq 1 -and $twice.out -like "*gives a key twice*title*" -and (Get-Files) -ceq "0000000001.json") "a file that gives the title twice is refused: one of the two would be stored unseen"
$ansiFile = Join-Path $script:work "ansi.json"
[System.IO.File]::WriteAllBytes($ansiFile, [byte[]](@(0x7B, 0x22, 0x74, 0x69, 0x74, 0x6C, 0x65, 0x22, 0x3A, 0x22, 0xE9, 0xE8, 0xE0, 0x22, 0x7D)))
$ansi = Invoke-Decisions @("add", "-File", $ansiFile)
Check ($ansi.code -eq 1 -and $ansi.out -like "*is not UTF-8 text*" -and (Get-Files) -ceq "0000000001.json") "a file in a legacy code page is refused, not read as other letters"
# A FILE THAT IS NOT JSON IS REFUSED WITHOUT BEING QUOTED. Windows PowerShell 5.1's JSON parser puts
# the text it could not read into its own message - the whole file for a string left open - so
# repeating that message printed a token from a question file one quote short of valid (measured
# 2026-10-06). The second file is a token and nothing else, which the parser names as a "primitive".
$cutFile = Write-Json "cut.json" ('{"title":"Should the test login be rotated this week?","kind":"yes-no","whatItIs":"The token is ' + $token + ' today.')
$cut = Invoke-Decisions @("add", "-File", $cutFile)
Check ($cut.code -eq 1 -and $cut.out -like "*the question file*is not JSON*" -and (Get-Files) -ceq "0000000001.json") "a question file that is cut-off JSON is refused as not JSON, and nothing is stored"
Check (-not $cut.out.Contains($token) -and -not $cut.out.Contains("rotated this week")) "and the refusal quotes nothing of the file: not the token, not the title"
$bareFile = Write-Json "bare.json" $token
$bare = Invoke-Decisions @("add", "-File", $bareFile)
Check ($bare.code -eq 1 -and $bare.out -like "*is not JSON*" -and -not $bare.out.Contains($token)) "a file holding only a token is refused as not JSON, and the token is not printed back"
$none = Invoke-Decisions @("show", "99")
Check ($none.code -eq 1 -and $none.out -like "*there is no question 99; the highest number given is 1*") "show 99 says there is no question 99, and exits 1"

Write-Host ""
Write-Host "--- a command line that cannot be acted on ---" -ForegroundColor Cyan
$wrongFlag = Invoke-Decisions @("list", "-File", $questionFile)
Check ($wrongFlag.code -eq 1 -and $wrongFlag.out -like "*-File does not belong to decisions list, which takes: -State, -Json*") "a flag that belongs to another verb is refused, never ignored"
$noNumber = Invoke-Decisions @("close", "-Outcome", "Done.")
Check ($noNumber.code -eq 1 -and $noNumber.out -like "*decisions close needs the question's number*") "close with no number is refused"
$unknownFlag = Invoke-Decisions @("list", "-Everything")
Check ($unknownFlag.code -eq 2 -and $unknownFlag.out -like "*usage: horde decisions add*") "a flag no verb has exits 2 with the usage"
Check ((Get-Files) -ceq "0000000001.json") "none of these wrote anything"

Write-Host ""
Write-Host "--- update, close with a file, and reopen ---" -ForegroundColor Cyan
$changeFile = Write-Json "change.json" '{"recommendation":"yes, a short tone","title":"Should a short closing sound play when the assistant closes unanswered?"}'
$upd = Invoke-Decisions @("update", "1", "-File", $changeFile)
Check ($upd.code -eq 0 -and $upd.out -like "*Changed question 1: Should a short closing sound play when the assistant closes unanswered?*" -and $upd.out -like "*changed title, recommendation (now wording 2)*") "update changes the fields the file names and says which, and that the wording is now 2"
$outcomeFile = Write-Json "outcome.txt" ("Built: a short tone plays." + "`r`n" + "Shipped in the next test build. " + $hebrew)
$close = Invoke-Decisions @("close", "1", "-OutcomeFile", $outcomeFile)
Check ($close.code -eq 0 -and $close.out -like "*Closed question 1:*") "close takes its outcome from a file"
$both = Invoke-Decisions @("close", "1", "-Outcome", "Done.", "-OutcomeFile", $outcomeFile)
Check ($both.code -eq 1 -and $both.out -like "*needs the outcome exactly once*") "an outcome given twice, as a line and as a file, is refused"
$late = Invoke-Decisions @("update", "1", "-File", $changeFile)
Check ($late.code -eq 1 -and $late.out -like "*question 1 is closed, and only an open question can be changed; reopen it first*") "a change to a closed question is refused, and told how to go on"
$closed = Invoke-Decisions @("show", "1", "-Json")
$j = Get-JsonLine $closed
Check ($null -ne $j -and $j.value.question.state -ceq "closed" -and [string]::Equals($j.value.question.outcome, ("Built: a short tone plays." + "`r`n" + "Shipped in the next test build. " + $hebrew), [System.StringComparison]::Ordinal)) "the outcome is stored whole: both lines, their line break and the Hebrew, exactly"
$reopen = Invoke-Decisions @("reopen", "1", "-Reason", "the tone was too quiet")
Check ($reopen.code -eq 0 -and $reopen.out -like "*Reopened question 1:*" -and (Get-Files) -ceq "0000000001.json,0000000002.json,0000000003.json,0000000004.json") "reopen opens question 1 again under its number; four records for the four accepted commands"

Write-Host ""
Write-Host "--- a damaged record is named where a person will see it ---" -ForegroundColor Cyan
# This suite's own store: record 5 is planted cut off, as a crash mid-write would leave it.
[System.IO.File]::WriteAllText((Join-Path $store "0000000005.json"), '{"schemaVersion":1,"sequence":5,"id":"', $utf8)
$warn = Invoke-Decisions @("list", "-State", "all")
Check ($warn.code -eq 0 -and @($warn.lines | Where-Object { $_.StartsWith("  1. Should a short closing sound play") }).Count -eq 1) "with a torn record in the store, list still shows the question and exits 0"
Check ($warn.out -like "*WARNING: 1 record(s) in the store could not be read.*" -and $warn.out -like "*record 5 (0000000005.json): it is not complete JSON*") "and warns in words, naming the record, its file and why"
$warnJson = Invoke-Decisions @("list", "-State", "all", "-Json")
$j = Get-JsonLine $warnJson
Check ($null -ne $j -and @($j.value.unreadable).Count -eq 1 -and $j.value.unreadable[0].sequence -eq 5) "the data names it too"
# A file far ahead of the order is a stray (decisions/Store.ps1): shown by name, and nothing else moves.
[System.IO.File]::WriteAllText((Join-Path $store "0000002000.json"), '{"stray":true}', $utf8)
$strayRun = Invoke-Decisions @("list", "-State", "all")
Check ($strayRun.code -eq 0 -and $strayRun.out -like "*NOTE: 1 file(s) in the store folder are named like a record and are not part of the list:*" -and $strayRun.out -like "*0000002000.json: it is 1994 places past record 5*") "a stray file far ahead in the store is named where a person will see it, with how far"
Check ($strayRun.out -like "*WARNING: 1 record(s) in the store could not be read.*") "and it is not counted among the records that could not be read: still one"

Write-Host ""
Write-Host "--- HORDE_HOME decides where the store is ---" -ForegroundColor Cyan
# With HORDE_HOME empty and the profile aimed at a folder of this suite, the store must appear under
# THAT profile's .horde - the default, proven without going near the real one.
$fakeProfile = Join-Path $script:work "fake-profile"
New-Item -ItemType Directory -Path $fakeProfile | Out-Null
$plainFile = Write-Json "plain.json" '{"title":"Is the default home under the user profile used here?","kind":"yes-no","whatItIs":"A test of where the store is.","group":"the fleet tool","askedBy":"orc-a"}'
$def = Invoke-Decisions @("add", "-File", $plainFile) -Env @{ HORDE_HOME = ""; USERPROFILE = $fakeProfile }
Check ($def.code -eq 0 -and (Test-Path -LiteralPath (Join-Path $fakeProfile ".horde\store\decisions\0000000001.json"))) "with no HORDE_HOME the store is <profile>\.horde\store\decisions"
$other = Join-Path $script:work "other-home"
$set = Invoke-Decisions @("add", "-File", $plainFile) -Env @{ HORDE_HOME = $other; USERPROFILE = $fakeProfile }
Check ($set.code -eq 0 -and (Test-Path -LiteralPath (Join-Path $other "store\decisions\0000000001.json"))) "with HORDE_HOME set the store is under it"
Check (@(Get-ChildItem -LiteralPath (Join-Path $fakeProfile ".horde\store\decisions") -File).Count -eq 1) "and nothing more was written under the profile: the two homes are two lists"

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-decisions-cli-test-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store under the user profile is exactly as it was before the suite"

Complete-HordeSuite -Success "horde decisions does at a real command line what the operations promise, in words a person can read"
