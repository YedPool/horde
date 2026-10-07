# DOES THE COMMAND LINE'S SIDE OF THE CONVERSATION SAY WHAT HAPPENED, IN WORDS, AND MARK ONLY WHAT IT PRINTED?
#
# decisions/Console.ps1's verbs answer, reply and inbox, and the thread as list and show print it -
# called in this process, the way cli/commands/decisions.ps1 calls them: Invoke-HordeDecisionCommand
# for the lines, then Complete-HordeDecisionCommand for what a verb does once its lines are out. This
# suite attacks the caller's own side:
#   - WHO SPEAKS IS THE VERB'S: answer records the founder's words as recorded from chat, reply the
#     warchief's own; neither can be made to say otherwise by a flag;
#   - THE WORDS ARE PRINTED AS THEY ARE: every line of them, indented, none joined, cut or dropped;
#   - EVERY LINE CAN BE READ WITH NO OTHER CONTEXT: who said it, how it was recorded, under which
#     question, that it arrived after closing, that it was said to an earlier wording;
#   - inbox -Json NEVER MARKS (the caller marks, with mark-read); in plain text inbox PRINTS, THEN MARKS, AND MARKS ONLY WHAT IT PRINTED: a message that arrives between the two
#     halves stays unread, a failed marking says the messages will be shown again, -Peek marks nothing;
#   - a command line that cannot be acted on is refused in words, and a refusal repeats no text.
# The same commands as real processes - argv, files, a console, a pipe, exit codes - are
# test/test-decisions-cli.ps1 and test/e2e/e2e-decisions.ps1. They cost seconds a call; this costs none.
#
# THE STORE IS UNDER A HOME THIS SUITE MADE under %TEMP% and removes (CONTRIBUTING 9): HORDE_HOME is set
# to it for this process and put back at the end. The real store is listed before and after.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "decisions\Console.ps1")

$script:work = Join-Path $env:TEMP ("horde-decisions-console-threads-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:n = 0

function Get-RealStoreListing {
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing
$keepHome = $env:HORDE_HOME

function New-Home {
    # A home of this suite's own, made the process's HORDE_HOME. Returns its store folder.
    $script:n++
    $homeDir = Join-Path $script:work ("home-" + $script:n)
    $env:HORDE_HOME = $homeDir
    return (Join-Path $homeDir "store\decisions")
}
function Run {
    # One command, both halves, as the command file runs it. Returns { lines; failure; first; then }:
    # lines is everything printed, in order; first and then are the two halves' own lines. A command
    # line that is refused (a throw) comes back as a failure beginning "THREW: ".
    param([string]$Verb, [hashtable]$Given = @{}, [scriptblock]$Between = $null)
    $have = @{ Verb = $Verb }
    foreach ($k in @($Given.Keys)) { $have[$k] = $Given[$k] }
    try {
        $first = Invoke-HordeDecisionCommand -Verb $Verb -Given $have
        if ($first.failure -ne "") { return [pscustomobject]@{ lines = @($first.lines); failure = "$($first.failure)"; first = @($first.lines); then = @() } }
        # What happens between the printing and what follows it: another writer, in a test.
        if ($null -ne $Between) { $null = & $Between }
        $then = Complete-HordeDecisionCommand -After $first.after
        return [pscustomobject]@{ lines = (@($first.lines) + @($then.lines)); failure = "$($then.failure)"; first = @($first.lines); then = @($then.lines) }
    } catch { return [pscustomobject]@{ lines = @(); failure = ("THREW: " + $_.Exception.Message); first = @(); then = @() } }
}
function Write-Words { param([string]$Name, [string]$Text) $p = Join-Path $script:work $Name; [System.IO.File]::WriteAllText($p, $Text, $utf8); return $p }
function Add-Q {
    param([string]$Title = "Should the closing sound play when the assistant closes?")
    $file = Write-Words ("question-" + [guid]::NewGuid().ToString("N") + ".json") ('{"title":"' + $Title + '","kind":"yes-no","whatItIs":"The app has no closing sound today.","group":"voice","askedBy":"orc-b"}')
    return (Run "add" @{ File = $file })
}
function Test-Line { param($Result, [string]$Exactly) return (@($Result.lines | Where-Object { $_ -ceq $Exactly }).Count -eq 1) }
function Test-Trimmed { param($Result, [string]$Exactly) return (@($Result.lines | Where-Object { "$_".Trim() -ceq $Exactly }).Count -eq 1) }
function Get-Kinds { param([string]$Store) if (-not (Test-Path -LiteralPath $Store)) { return "" }; return (@(Get-ChildItem -LiteralPath $Store -File -Filter "*.json" | Sort-Object Name | ForEach-Object { ([System.IO.File]::ReadAllText($_.FullName, $utf8) | ConvertFrom-Json).kind -creplace '\Aquestion-', '' -creplace '\Amessages?-', '' }) -join ",") }
function Read-Record { param([string]$Store, [long]$Sequence) return ([System.IO.File]::ReadAllText((Join-Path $Store ($Sequence.ToString("D10") + ".json")), $utf8) | ConvertFrom-Json) }
$title = "Should the closing sound play when the assistant closes?"

try {

Write-Host ""
Write-Host "--- answer and reply: who speaks is the verb's ---" -ForegroundColor Cyan
$store = New-Home
$null = Add-Q
$a = Run "answer" @{ Number = "1"; Text = "Yes, play it." }
Check ($a.failure -eq "" -and @($a.lines).Count -eq 1 -and $a.lines[0] -ceq ("Kept the founder's words, recorded by the warchief from chat, under question 1 (record 2): " + $title)) ("answer says whose words it recorded, how, under which question and in which record (" + $a.failure + @($a.lines)[0] + ")")
$rec = Read-Record $store 2
Check ($rec.kind -ceq "message-said" -and $rec.actor -ceq "warchief" -and $rec.data.speaker -ceq "founder" -and $rec.data.route -ceq "chat-recorded" -and $rec.data.text -ceq "Yes, play it.") "and the record is the founder's words, by the route 'recorded from chat', made by the warchief"
$r = Run "reply" @{ Number = "1"; Text = "It plays from the next build." }
Check ($r.failure -eq "" -and @($r.lines).Count -eq 1 -and $r.lines[0] -ceq ("Replied under question 1 (record 3): " + $title)) ("reply says under which question and in which record (" + $r.failure + @($r.lines)[0] + ")")
$rec = Read-Record $store 3
Check ($rec.data.speaker -ceq "warchief" -and $rec.data.route -ceq "command" -and $rec.actor -ceq "warchief") "and the record is the warchief's own words, by command"
Check ($null -eq $rec.data.PSObject.Properties["asks"]) "a reply records no asks: words said to him ask him (TRIAL)"
$id = [guid]::NewGuid().ToString("N")
$once = Run "answer" @{ Number = "1"; Text = "Only once."; Id = $id }
$twice = Run "answer" @{ Number = "1"; Text = "Only once."; Id = $id }
Check ($once.failure -eq "" -and $twice.failure -eq "" -and (Test-Line $twice "Question 1: this request was already recorded (record 4), so nothing was written again.") -and (Get-Kinds $store) -ceq "added,said,said,said") ("the same answer sent twice with one -Id is one message, and the second says so (" + (Get-Kinds $store) + ")")
# -Json: one line, all ASCII, and the words come back from it exactly.
$hebrew = "" + [char]0x05DB + [char]0x05DF + [char]0x200F + " " + [char]0x200E + [char]0x05EA + [char]0x05D5 + [char]0x05D3 + [char]0x05D4 + [char]0x200D
$j = Run "answer" @{ Number = "1"; File = (Write-Words "hebrew.txt" $hebrew); Json = $true }
$parsed = $null
try { $parsed = (@($j.lines)[0] | ConvertFrom-Json) } catch { }
Check ($j.failure -eq "" -and @($j.lines).Count -eq 1 -and "$(@($j.lines)[0])" -cnotmatch '[^\x20-\x7E]' -and $null -ne $parsed -and [string]::Equals($parsed.value.message.text, $hebrew, [System.StringComparison]::Ordinal)) "-Json is one line of ASCII, and the Hebrew with its direction marks reads back from it character for character"

Write-Host ""
Write-Host "--- TRIAL: a note, and an answer that replaces his earlier one, said in words ---" -ForegroundColor Cyan
$store = New-Home
$null = Add-Q
$null = Run "answer" @{ Number = "1"; Text = "Yes, play it." }
$note = Run "reply" @{ Number = "1"; Text = "Noted, I am on it."; Note = $true }
Check ($note.failure -eq "" -and (Read-Record $store 3).data.asks -eq $false -and (Test-Trimmed (Run "show" @{ Number = "1" }) "(a note: it asks him nothing, and the turn stayed the keeper's)")) "reply -Note records asks false, and show says the note asks him nothing"
Check ((Test-Trimmed (Run "list") "conversation: 2 message(s); 1 not yet read by the warchief; turn: the warchief")) "and after the note the turn is still the keeper's"
$null = Run "inbox"
$null = Run "answer" @{ Number = "1"; Text = "Yes, and play it twice." }
$plain = Run "inbox" @{ Peek = $true }
Check (-not (Test-Trimmed $plain "(replaces his earlier answer)")) "CONTROL: his words after the keeper's note replace nothing, and say nothing of it"
$null = Run "answer" @{ Number = "1"; Text = "Yes, and play it three times." }
$replacing = Run "inbox" @{ Peek = $true }
Check ((Test-Trimmed $replacing "(replaces his earlier answer)")) "HIS WORDS STRAIGHT AFTER HIS OWN: the inbox says, once, that they replace his earlier answer"

Write-Host ""
Write-Host "--- the words, from a file, are printed as they are ---" -ForegroundColor Cyan
$store = New-Home
$null = Add-Q
$words = "  two spaces lead this line" + "`r`n" + "`r`n" + "a blank line came before this one" + "`n" + "`tand a tab leads the last, which ends in spaces  "
$a = Run "answer" @{ Number = "1"; File = (Write-Words "words.txt" $words) }
Check ($a.failure -eq "" -and [string]::Equals((Read-Record $store 2).data.text, $words, [System.StringComparison]::Ordinal)) "words from a file are recorded exactly as the file holds them: spaces at both ends, the blank line, both kinds of line break"
$shown = Run "show" @{ Number = "1" }
# Each line of the words is printed after six spaces of indent, and is otherwise exactly itself.
$at = [array]::IndexOf(@($shown.lines), "        two spaces lead this line")
Check ($at -gt 0 -and @($shown.lines)[$at + 1] -ceq "      " -and @($shown.lines)[$at + 2] -ceq "      a blank line came before this one" -and @($shown.lines)[$at + 3] -ceq ("      " + "`t" + "and a tab leads the last, which ends in spaces  ")) "show prints every line of them as its own line, indented, in order: the blank one kept, nothing trimmed, nothing joined"
Check ($at -gt 0 -and @($shown.lines)[$at - 1] -like "  the founder, recorded by the warchief from chat, 20* UTC (record 2, wording not stated)") "under a line that says who said it, how it was recorded, when, in which record, and that the wording he saw was not stated"
Check ((Test-Line $shown "Conversation: 1 message(s); 1 not yet read by the warchief; turn: the warchief") -and (Test-Line $shown "    (not yet read by the warchief)")) "the conversation is headed by its counts and whose turn it is, and the message says it is not yet read"
$twoLines = Run "answer" @{ Number = "1"; Text = ("first line of it`nsecond line of it") }
Check ($twoLines.failure -like "THREW: -Text is one line, and it has a line break*-File <path>*" -and $twoLines.failure -notlike "*first line of it*" -and (Get-Kinds $store) -ceq "added,said") "a -Text of two lines is refused and sent to -File, without being repeated, and nothing is written"

Write-Host ""
Write-Host "--- list and show: the thread in words ---" -ForegroundColor Cyan
$store = New-Home
$null = Add-Q
$null = Add-Q "Which languages besides English should the test talker speak?"
$null = Run "answer" @{ Number = "1"; Text = "Which sound do you mean?" }
$listed = Run "list"
Check (@($listed.lines | Where-Object { $_.Trim() -ceq "conversation: 1 message(s); 1 not yet read by the warchief; turn: the warchief" }).Count -eq 1) "list says of a question that has been spoken under: how many messages, how many unread, whose turn"
Check (@($listed.lines | Where-Object { $_ -like "*conversation:*" }).Count -eq 1) "and says nothing of a question nobody has spoken under"
$null = Run "inbox"
$null = Run "reply" @{ Number = "1"; Text = "The short one." }
$listed = Run "list"
Check (@($listed.lines | Where-Object { $_.Trim() -ceq "conversation: 2 message(s); turn: the founder" }).Count -eq 1) "once read and replied to: two messages, nothing unread, and the founder's turn"
$shown = Run "show" @{ Number = "1" }
$first = [array]::IndexOf(@($shown.lines), "      Which sound do you mean?")
$second = [array]::IndexOf(@($shown.lines), "      The short one.")
Check ($first -gt 0 -and $second -gt $first -and @($shown.lines)[$second - 1] -like "  the warchief, by command, 20* UTC (record 5, wording not stated)" -and -not (Test-Line $shown "    (not yet read by the warchief)")) "show prints the thread in order, the reply named as the warchief's by command, and nothing marked unread"
Check ((Test-Line $shown "History:") -and @($shown.lines | Where-Object { $_ -like "*(by warchief, record *" }).Count -eq 1) "the question's history is still one record: what was said is the conversation, not the history"

Write-Host ""
Write-Host "--- inbox: prints, then marks what it printed ---" -ForegroundColor Cyan
$store = New-Home
$empty = Run "inbox"
Check ($empty.failure -eq "" -and @($empty.lines).Count -eq 1 -and $empty.lines[0] -ceq "Nothing unread: nothing has been said that was not already read." -and -not (Test-Path -LiteralPath $store)) "with nothing said, inbox says so in one line, marks nothing, and makes no store"
$null = Add-Q
$null = Add-Q "Which languages besides English should the test talker speak?"
$null = Run "answer" @{ Number = "1"; Text = "Yes, play it." }           # record 3
$null = Run "answer" @{ Number = "2"; Text = "Hebrew first." }           # record 4
$null = Run "reply" @{ Number = "1"; Text = "It plays from the next build." }   # record 5
$peek = Run "inbox" @{ Peek = $true }
Check ($peek.failure -eq "" -and $peek.lines[0] -ceq "2 message(s) not yet read, oldest first:" -and (Test-Line $peek ("Question 1: " + $title)) -and (Test-Line $peek "Question 2: Which languages besides English should the test talker speak?") -and (Test-Line $peek "      Yes, play it.") -and (Test-Line $peek "      Hebrew first.")) "inbox -Peek prints the founder's unread words, each under its question's number and plain-words title"
Check ([array]::IndexOf(@($peek.lines), "      Yes, play it.") -lt [array]::IndexOf(@($peek.lines), "      Hebrew first.") -and @($peek.lines | Where-Object { $_ -like "*It plays from the next build*" }).Count -eq 0) "oldest first, and not the warchief's own reply"
Check ((Test-Line $peek "Nothing was marked as read (-Peek).") -and @($peek.then).Count -eq 0 -and (Get-Kinds $store) -ceq "added,added,said,said,said") "-Peek says nothing was marked, and nothing was: no record was written"
$box = Run "inbox"
Check ($box.failure -eq "" -and (@($box.first) -join "`n") -ceq (@($peek.first | Where-Object { $_ -cne "Nothing was marked as read (-Peek)." }) -join "`n").TrimEnd("`n")) "inbox without -Peek prints the same messages"
Check (@($box.then).Count -eq 2 -and $box.then[1] -ceq "Marked as read: 2 message(s), up to record 4." -and (Get-Kinds $store) -ceq "added,added,said,said,said,read" -and (Read-Record $store 6).data.upTo -eq 4) "and AFTER them, says it marked two as read, up to the last one it printed - which is what the record says"
$again = Run "inbox"
Check ($again.failure -eq "" -and @($again.lines).Count -eq 1 -and $again.lines[0] -like "Nothing unread*" -and (Get-Kinds $store) -ceq "added,added,said,said,said,read") "read a second time the inbox is empty, says nothing of marking, and writes nothing"
# -Json NEVER MARKS. The one line holds the unread messages, says "marked": false, and names the last
# record it showed (upTo). The caller marks explicitly, with `mark-read -UpTo`, once it HAS the line:
# so a caller killed at any point has never marked a message it did not receive.
$null = Run "answer" @{ Number = "2"; Text = "And Spanish after." }       # record 7
$asData = Run "inbox" @{ Json = $true }
$parsed = $null
try { $parsed = (@($asData.lines)[0] | ConvertFrom-Json) } catch { }
Check ($asData.failure -eq "" -and @($asData.lines).Count -eq 1 -and @($asData.then).Count -eq 0 -and $null -ne $parsed -and @($parsed.value.messages).Count -eq 1 -and $parsed.value.messages[0].message.text -ceq "And Spanish after.") "inbox -Json prints ONE line holding the unread messages, and nothing after it"
Check ($null -ne $parsed -and $null -ne $parsed.PSObject.Properties["marked"] -and $parsed.marked -is [bool] -and $parsed.marked -eq $false -and $parsed.upTo -eq 7) "that line says outright that nothing was marked, and names the last record it showed: record 7"
Check ((Get-Kinds $store) -ceq "added,added,said,said,said,read,said") ("and NOTHING WAS MARKED: the store has no new record (" + (Get-Kinds $store) + ")")
$asDataAgain = Run "inbox" @{ Json = $true }
Check ("$(@($asDataAgain.lines)[0])" -like '*And Spanish after.*' -and (Get-Kinds $store) -ceq "added,added,said,said,said,read,said") "asked again it hands over the same message: a caller that lost the line has lost nothing"
$peekData = Run "inbox" @{ Json = $true; Peek = $true }
Check ("$(@($peekData.lines)[0])" -like '*And Spanish after.*' -and "$(@($peekData.lines)[0])" -like '*"marked":false*' -and (Get-Kinds $store) -ceq "added,added,said,said,said,read,said") "-Peek with -Json is the same line: there is nothing for it to hold back"
# THE CALLER MARKS, EXPLICITLY: `mark-read -UpTo <record>`.
$markId = [guid]::NewGuid().ToString("N")
$mark = Run "mark-read" @{ UpTo = "7"; Id = $markId }
Check ($mark.failure -eq "" -and @($mark.lines).Count -eq 1 -and $mark.lines[0] -ceq "Marked as read: 1 message(s), up to record 7." -and (Get-Kinds $store) -ceq "added,added,said,said,said,read,said,read" -and (Read-Record $store 8).data.upTo -eq 7) ("mark-read -UpTo 7 records that the warchief has read up to record 7, and says how many messages that marked (" + $mark.failure + @($mark.lines)[0] + ")")
$markAgain = Run "mark-read" @{ UpTo = "7"; Id = $markId }
Check ($markAgain.failure -eq "" -and $markAgain.lines[0] -ceq "This marking was already recorded (record 8), so nothing was written again." -and (Get-Kinds $store) -ceq "added,added,said,said,said,read,said,read") "the same command sent again with the same -Id says it was already recorded, and writes nothing"
$markSame = Run "mark-read" @{ UpTo = "7" }
Check ($markSame.failure -eq "" -and $markSame.lines[0] -ceq "Nothing to mark: everything up to record 7 was already read." -and (Get-Kinds $store) -ceq "added,added,said,said,said,read,said,read") "marking up to a record already read says there was nothing to mark, and writes nothing"
$markData = Run "mark-read" @{ UpTo = "7"; Json = $true }
$parsedMark = $null
try { $parsedMark = (@($markData.lines)[0] | ConvertFrom-Json) } catch { }
Check (@($markData.lines).Count -eq 1 -and $null -ne $parsedMark -and $parsedMark.value.outcome -ceq "done" -and $parsedMark.value.upTo -eq 7 -and $parsedMark.value.marked -eq 0) "mark-read -Json is one line saying what it marked"
$emptyData = Run "inbox" @{ Json = $true }
$parsedEmpty = $null
try { $parsedEmpty = (@($emptyData.lines)[0] | ConvertFrom-Json) } catch { }
Check ($null -ne $parsedEmpty -and $emptyData.failure -eq "" -and @($parsedEmpty.value.messages).Count -eq 0 -and $parsedEmpty.marked -eq $false -and $parsedEmpty.upTo -eq 0) "and now inbox -Json holds no message, and its last record is 0"
$future = Run "mark-read" @{ UpTo = "99" }
Check ($future.failure -like "*not before this record*" -and $future.lines[0] -like "Refused:*" -and (Get-Kinds $store) -ceq "added,added,said,said,said,read,said,read") ("marking up to a record that is not written is refused, in words, and writes nothing (" + $future.failure + ")")
Check ((Run "mark-read" @{}).failure -like "THREW: decisions mark-read needs -UpTo <record>*Usage: horde decisions mark-read -UpTo <record>*") "mark-read with no record named is refused, with its usage: there is no 'mark everything'"
Check ((Run "mark-read" @{ UpTo = "all" }).failure -like "THREW: -UpTo is a record's number*" -and (Run "mark-read" @{ UpTo = "0" }).failure -like "THREW: -UpTo is a record's number*") "-UpTo that is not a record's number is refused"
Check ((Run "mark-read" @{ UpTo = "7"; Number = "1" }).failure -like "THREW: decisions mark-read takes no question number*" -and (Run "mark-read" @{ UpTo = "7"; Peek = $true }).failure -like "THREW: -Peek does not belong to decisions mark-read*" -and (Run "inbox" @{ UpTo = "7" }).failure -like "THREW: -UpTo does not belong to decisions inbox*") "mark-read takes no question number and no -Peek, and inbox takes no -UpTo"

Write-Host ""
Write-Host "--- a message that arrives between the printing and the marking is never marked unseen ---" -ForegroundColor Cyan
$store = New-Home
$null = Add-Q
$null = Run "answer" @{ Number = "1"; Text = "Printed by this inbox." }       # record 2
$arrive = { $null = Invoke-HordeDecision -Operation "say" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; number = 1; speaker = "founder"; route = "chat-recorded"; text = "Arrived after the printing." } }
$box = Run "inbox" @{} $arrive
Check ($box.failure -eq "" -and (Test-Line $box "      Printed by this inbox.") -and @($box.lines | Where-Object { $_ -like "*Arrived after the printing*" }).Count -eq 0) "CONTROL: the inbox printed the one message that was there, and the other arrived after"
Check ((Get-Kinds $store) -ceq "added,said,said,read" -and (Read-Record $store 4).data.upTo -eq 2 -and (Test-Line $box "Marked as read: 1 message(s), up to record 2.")) ("the marking, made after the new message was already in the store, marks only what was printed: up to record 2 (" + (Get-Kinds $store) + ")")
$next = Run "inbox" @{ Peek = $true }
Check ((Test-Line $next "1 message(s) not yet read, oldest first:") -and (Test-Line $next "      Arrived after the printing.")) "and the message that arrived in between is the next inbox: it was not marked read unseen"
# Two readers at once: the other one marks the same messages between this one's printing and its marking.
$store = New-Home
$null = Add-Q
$null = Run "answer" @{ Number = "1"; Text = "Read by two at once." }   # record 2
$other = { $null = Invoke-HordeDecision -Operation "mark-read" -Request @{ actor = "warchief"; id = [guid]::NewGuid().ToString("N"); upTo = 2 } }
$box = Run "inbox" @{} $other
Check ($box.failure -eq "" -and (Test-Line $box "      Read by two at once.") -and (Test-Line $box "Nothing was left to mark: the messages above were marked as read by another reader in the meantime.") -and (Get-Kinds $store) -ceq "added,said,read") ("when another reader marked them first, this one says so and writes no second marking (" + (Get-Kinds $store) + ")")
# A MARKING THAT IS REFUSED is a failed marking too, and says why: here its id was used, between the
# printing and the marking, for another request.
$store = New-Home
$null = Add-Q
$null = Run "answer" @{ Number = "1"; Text = "Printed, and its marking refused." }   # record 2
$usedId = [guid]::NewGuid().ToString("N")
$takeId = { $null = Invoke-HordeDecision -Operation "say" -Request @{ id = $usedId; actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "took the id" } }
$box = Run "inbox" @{ Id = $usedId } $takeId
Check ((Test-Line $box "      Printed, and its marking refused.") -and $box.failure -like "the messages above were NOT marked as read, and will be shown again:*already used for a different request*" -and @($box.then).Count -eq 0 -and (Get-Kinds $store) -ceq "added,said,said") ("a marking that is refused fails the command, says the messages were not marked, and gives the reason (" + $box.failure + ")")
# A MARKING THAT FAILS says so, and says the messages will be shown again - which they are.
$store = New-Home
$null = Add-Q
$null = Run "answer" @{ Number = "1"; Text = "Shown, and the marking fails." }   # record 2
$block = { New-Item -ItemType Directory -Path (Join-Path $store "0000000003.json") | Out-Null }
$box = Run "inbox" @{} $block
Check ((Test-Line $box "      Shown, and the marking fails.") -and $box.failure -like "the messages above were NOT marked as read, and will be shown again:*" -and @($box.then).Count -eq 0) ("when the marking cannot be written, the command fails saying the messages were not marked and will be shown again (" + $box.failure + ")")
Remove-Item -LiteralPath (Join-Path $store "0000000003.json")
$next = Run "inbox"
Check ($next.failure -eq "" -and (Test-Line $next "      Shown, and the marking fails.") -and (Test-Line $next "Marked as read: 1 message(s), up to record 2.")) "and they are: the next inbox prints them again, and marks them"

Write-Host ""
Write-Host "--- words under a closed question, and words to an earlier wording, say so ---" -ForegroundColor Cyan
$store = New-Home
$null = Add-Q
$null = Run "update" @{ Number = "1"; File = (Write-Words "change.json" '{"title":"Should the closing sound play at the end of every session?"}') }
$old = Run "answer" @{ Number = "1"; Text = "Yes to how it read before."; Wording = "1" }
Check ($old.failure -eq "" -and (Test-Line $old "  NOTE: they were said to wording 1, and the question is now at wording 2. They are kept, and marked as said to an earlier wording.") -and (Read-Record $store 3).data.wordingVersion -eq 1) "words said to an earlier wording are recorded with that wording, and the command says they are marked as such"
$now = Run "answer" @{ Number = "1"; Text = "Yes to how it reads now." }
Check ($now.failure -eq "" -and @($now.lines).Count -eq 1 -and $null -eq (Read-Record $store 4).data.PSObject.Properties["wordingVersion"]) "with no -Wording, the words are recorded with no wording at all - not stated, never guessed - and carry no note"
$null = Run "close" @{ Number = "1"; Outcome = "Done: it plays at the end of every session." }
$late = Run "answer" @{ Number = "1"; Text = "Wait - not on the first launch." }
Check ($late.failure -eq "" -and (Test-Line $late "  NOTE: question 1 is closed. The words are kept under it, and it stays closed: saying something reopens nothing.") -and (Get-Kinds $store) -ceq "added,updated,said,said,closed,said") ("words said under a closed question are recorded, not refused, and the command says the question stays closed (" + (Get-Kinds $store) + ")")
$box = Run "inbox" @{ Peek = $true }
Check (@($box.lines | Where-Object { $_ -ceq "Question 1: Should the closing sound play at the end of every session? [closed]" }).Count -eq 3) "the inbox names the question as it reads now, and says it is closed"
Check (@($box.lines | Where-Object { $_ -like "  the founder, recorded by the warchief from chat, 20* UTC (record 3, said to wording 1)" }).Count -eq 1 -and @($box.lines | Where-Object { $_ -like "*(record 4, wording not stated)" -or $_ -like "*(record 6, wording not stated)" }).Count -eq 2) "each message says which wording it was said to when that was stated, and 'wording not stated' when it was not"
Check ((Test-Line $box "    NOTE: this arrived after the question was closed. It is kept, and it reopened nothing.") -and (Test-Line $box "    NOTE: this was said to an earlier wording (wording 1). Check that it still answers the question as it reads now.")) "and carries both notes, each on the message it belongs to and on no other"
$shown = Run "show" @{ Number = "1" }
Check ((Test-Line $shown "Question 1 - closed (wording 2)") -and (Test-Line $shown "Conversation: 3 message(s); 3 not yet read by the warchief; turn: nobody") -and (Test-Line $shown "    NOTE: this was said to an earlier wording (wording 1; the question is now at wording 2). Check that it still answers the question as it reads now.")) "show says the same of the thread, with the wording the question is at now, and that it is nobody's turn"

Write-Host ""
Write-Host "--- a refusal says why, repeats nothing, and writes nothing ---" -ForegroundColor Cyan
$store = New-Home
$null = Add-Q
$token = "gh" + "p_" + ("Qw8" * 12)
$secret = Run "answer" @{ Number = "1"; Text = ("use " + $token + " for it") }
Check ($secret.failure -ne "" -and $secret.failure -notlike "THREW*" -and @($secret.lines | Where-Object { $_ -like "*'text' holds what looks like an access token*" }).Count -eq 1 -and $secret.lines[0] -like "Refused:*") "words holding a token are refused, with the field and the kind of secret"
Check (-not ((@($secret.lines) -join "`n") + $secret.failure).Contains($token) -and -not ((@($secret.lines) -join "`n") + $secret.failure).Contains("for it") -and (Get-Kinds $store) -ceq "added") "neither the token nor the words around it are printed, and nothing is written"
$none = Run "reply" @{ Number = "99"; Text = "to a question that is not there" }
Check ($none.failure -like "*there is no question 99*" -and @($none.lines | Where-Object { $_ -like "Nothing was done: there is no question 99*" }).Count -eq 1 -and (Get-Kinds $store) -ceq "added") "a reply under a number that was never given says there is no such question, and writes nothing"
Check ((Run "answer" @{ Number = "1" }).failure -like "THREW: decisions answer needs the words exactly once: -Text <one line>, or -File <path> for more than a line. Usage: horde decisions answer <number>*") "answer with no words is refused, with how the words are given and the verb's usage"
Check ((Run "reply" @{ Number = "1"; Text = "a"; File = "b" }).failure -like "THREW: decisions reply needs the words exactly once*") "the words given twice, as -Text and as -File, are refused"
Check ((Run "answer" @{ Text = "a" }).failure -like "THREW: decisions answer needs the question's number*" -and (Run "inbox" @{ Number = "3" }).failure -like "THREW: decisions inbox takes no question number*") "answer without a question's number, and inbox with one, are refused"
Check ((Run "answer" @{ Number = "1"; Text = "a"; Peek = $true }).failure -like "THREW: -Peek does not belong to decisions answer*" -and (Run "inbox" @{ Text = "a" }).failure -like "THREW: -Text does not belong to decisions inbox*" -and (Run "list" @{ Wording = "1" }).failure -like "THREW: -Wording does not belong to decisions list*") "a flag of another verb is refused, never ignored"
Check ((Run "answer" @{ Number = "1"; Text = "a"; Wording = "two" }).failure -like "THREW: -Wording is the number of the wording*" -and (Run "answer" @{ Number = "1"; Text = "a"; Wording = "0" }).failure -like "THREW: -Wording is the number of the wording*") "-Wording that is not a wording's number is refused"
Check ((Run "answer" @{ Number = "1"; File = (Join-Path $script:work "no-such-file.txt") }).failure -like "THREW: the file of words*was not found") "a file of words that is not there is refused by name"
Check ((Run "inbox" @{ Id = "not-an-id" }).failure -like "THREW: -Id is 32 lowercase hex digits*") "an -Id that is not one is refused for inbox as for every verb that writes"
Check ((Get-Kinds $store) -ceq "added") "CONTROL: none of these wrote anything"

} finally {
    $env:HORDE_HOME = $keepHome
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-decisions-console-threads-test-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"
Check ("$env:HORDE_HOME" -ceq "$keepHome") "HORDE_HOME is what it was before the suite"
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store under the user profile is exactly as it was before the suite"

Complete-HordeSuite -Success "the command line says in words who said what under which question, prints the words as they are, and marks as read only what it printed"
