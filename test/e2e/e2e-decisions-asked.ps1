# END TO END: WHEN EACH QUESTION WAS LAST ASKED, driven through the horde command line as its user drives it.
#
# The founder, 2026-10-14: on his decisions page each question shows when it was last asked, and the
# Date order sorts by that. A question the keeper raises again (horde decisions remind), replies under
# with words that ask, or asks a follow-up to, counts as asked again (decisions/Rules.ps1, WHEN A
# QUESTION WAS ASKED). This scenario is the keeper doing each of those at the real command line, from a
# store that already holds a question written the way every earlier version wrote one, and checks:
#   - what the session SEES: the printed lines, the exit code;
#   - what the page is HANDED: `list -Json`, each question's asked list and lastAskedAt;
#   - WHERE THE PAGE PUTS IT: the order list.js gives that very -Json line, run under Node
#     (decisions/page/test/order-of.mjs) - so "it moves to the top" is the shipped sorting's answer;
#   - and what is left in the store: one record per reminder, none for a refusal.
# Every must-pass stands beside a CONTROL that shows the check could have failed.
#
# NO TERMINAL IS INVOLVED, and no agent is started. HORDE_HOME is a folder this scenario makes and
# removes; the real store is listed before and after and must not have changed (CONTRIBUTING 9).
# Node runs the order checks; without it they are said to be skipped and the suite exits 3 (PARTIAL).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "core\JsonText.ps1")

$script:work = Join-Path $env:TEMP ("horde-decisions-asked-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$store = Join-Path $hordeHome "store\decisions"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$listJs = Join-Path $root "decisions\page\list.js"
$orderOf = Join-Path $root "decisions\page\test\order-of.mjs"
$node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$partial = $false

function Get-RealStoreListing {
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing

function Invoke-Decisions {
    param([string[]]$HordeArgs)
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs (@("decisions") + $HordeArgs) -Env @{ HORDE_HOME = $hordeHome }
    return [pscustomobject]@{ code = $r.code; out = $r.out; lines = @($r.out -split "\r?\n") }
}
function Write-File { param([string]$Name, [string]$Text) $p = Join-Path $script:work $Name; [System.IO.File]::WriteAllText($p, $Text, $utf8); return $p }
function Get-RecordCount { if (-not (Test-Path -LiteralPath $store)) { return 0 }; return @(Get-ChildItem -LiteralPath $store -File -Filter "*.json").Count }
# The list as the page is handed it: every question, by number, from one `list -State all -Json` line.
$script:lastLine = ""
function Get-Listed {
    $run = Invoke-Decisions @("list", "-State", "all", "-Json")
    $script:lastLine = @($run.lines | Where-Object { $_.StartsWith('{"state":') }) | Select-Object -First 1
    $byNumber = @{}
    try { foreach ($q in @((ConvertFrom-HordeJson $script:lastLine).value.questions)) { $byNumber[[int]$q.number] = $q } } catch { }
    return $byNumber
}
# Where the shipped page puts the last listed questions, by -Order, as "3,2,1"; "" without Node.
function Get-PageOrder {
    param([string]$Order = "date", [switch]$Turned)
    if ($null -eq $node) { $script:partial = $true; return "" }
    $file = Write-File "listed.json" $script:lastLine
    $nodeArgs = @($orderOf, $listJs, $file, $Order)
    if ($Turned) { $nodeArgs += "turned" }
    return ("" + (& $node.Source @nodeArgs)).Trim()
}
function Format-Asked { param($Q) return (@(@($Q.asked) | ForEach-Object { $_.how + "|" + $_.by + "|" + $_.note }) -join ";") }
function Test-PageOrder {
    # Check the page's order, or say it was skipped: never a pass with no Node to run it.
    param([string]$Got, [string]$Want, [string]$Name)
    if ($null -eq $node) { Write-Host ("  [SKIP] " + $Name + " (node is not installed here)") -ForegroundColor Yellow; return }
    Check ($Got -ceq $Want) ($Name + " (page order " + $Got + ")")
}

try {

Write-Host ""
Write-Host "=== a store from before: one question, written the way every earlier version wrote it ===" -ForegroundColor Cyan
# Exactly the record an earlier version wrote (no importance, no blocks, nothing about asking), dated
# well before anything this scenario adds, so that by date it would stand last.
New-Item -ItemType Directory -Path $store -Force | Out-Null
$oldAt = "2026-10-01T08:00:00.0000000Z"
$oldRecord = '{"schemaVersion":1,"sequence":1,"id":"0123456789abcdef0123456789abcdef","kind":"question-added","at":"' + $oldAt + '","actor":"warchief","requestHash":"' + ("ab" * 32) + '","data":{"number":1,"question":{"title":"Should the old nightly job keep running on the spare machine?","kind":"yes-no","options":[],"parts":[],"whatItIs":"It has run there since September.","yesMeans":"","recommendation":"","group":"Builds","groupNote":"","askedBy":"orc-a","waiting":[],"files":[],"references":[],"needsSecret":false}}}'
[System.IO.File]::WriteAllText((Join-Path $store "0000000001.json"), $oldRecord, $utf8)
$listed = Get-Listed
$old = $listed[1]
Check ($null -ne $old -and "$($old.addedAt)" -ceq $oldAt) "CONTROL: the list reads the old question, added at the time its record says"
Check ($null -ne $old -and (Format-Asked $old) -ceq "first|orc-a|" -and [int]$old.askedCount -eq 1 -and "$($old.lastAskedAt)" -ceq $oldAt -and "$(@($old.asked)[0].at)" -ceq $oldAt) "AN OLD QUESTION READS AS ASKED ONCE, first, by its askedBy, at addedAt - and its last-asked time is addedAt"
Check ($null -ne $old -and (@(@($old.asked)[0].PSObject.Properties | ForEach-Object { $_.Name }) -join ",") -ceq "at,how,by,note") "and an entry holds the four agreed members and nothing else"

Write-Host ""
Write-Host "=== two new questions: each starts with one first entry ===" -ForegroundColor Cyan
$q = Write-File "q.json" '{"title":"Should the release notes go out with each test build?","kind":"yes-no","whatItIs":"They are written by hand today.","group":"Releases","askedBy":"orc-e"}'
$r = Write-File "r.json" '{"title":"Which machine should run the long voice tests overnight?","kind":"choice","options":["the spare machine","the test box"],"whatItIs":"They take four hours.","group":"Voice","askedBy":"orc-b"}'
$add2 = Invoke-Decisions @("add", "-File", $q)
$add3 = Invoke-Decisions @("add", "-File", $r)
$listed = Get-Listed
Check ($add2.code -eq 0 -and $add3.code -eq 0 -and (Format-Asked $listed[2]) -ceq "first|orc-e|" -and (Format-Asked $listed[3]) -ceq "first|orc-b|") "a new question has one entry: first, by whoever asked it"
Check ("$($listed[2].lastAskedAt)" -ceq "$($listed[2].addedAt)" -and "$($listed[3].lastAskedAt)" -ceq "$($listed[3].addedAt)" -and "$($listed[3].addedAt)" -cne "") "and it was last asked when it was added"
Test-PageOrder (Get-PageOrder) "3,2,1" "CONTROL: by date the page puts the newest first and the old question, asked once on 1 October, last"
Test-PageOrder (Get-PageOrder -Turned) "1,2,3" "CONTROL: and turned over, the old one first"

Write-Host ""
Write-Host "=== remind, with a note: the old question is asked again ===" -ForegroundColor Cyan
$before = Get-RecordCount
$remind1 = Invoke-Decisions @("remind", "1", "-Note", "raised again in chat")
$listed = Get-Listed
Check ($remind1.code -eq 0 -and $remind1.out -like "*Asked again: question 1: Should the old nightly job keep running on the spare machine?*" -and $remind1.out -like "*last asked * (2 times; first 2026-10-01 08:00 UTC)*") "remind 1 -Note says the question was asked again, how many times, and when first"
Check ((Get-RecordCount) -eq $before + 1 -and (Format-Asked $listed[1]) -ceq "first|orc-a|;remind|warchief|raised again in chat" -and [int]$listed[1].askedCount -eq 2) "it appends one remind entry, by the keeper's role, with the note - one record of its own"
Check ("$($listed[1].lastAskedAt)" -ceq "$(@($listed[1].asked)[1].at)" -and "$($listed[1].lastAskedAt)" -cne $oldAt -and "$($listed[1].addedAt)" -ceq $oldAt) "its last-asked time is the reminder's, and when it was added is unchanged"
Test-PageOrder (Get-PageOrder) "1,3,2" "AND THE PAGE PUTS IT AT THE TOP OF THE DATE ORDER: the question added first, asked again last, leads"
Test-PageOrder (Get-PageOrder -Turned) "2,3,1" "turned over, it stands last"

Write-Host ""
Write-Host "=== remind, without a note ===" -ForegroundColor Cyan
$before = Get-RecordCount
$remind2 = Invoke-Decisions @("remind", "2")
$listed = Get-Listed
Check ($remind2.code -eq 0 -and (Get-RecordCount) -eq $before + 1 -and (Format-Asked $listed[2]) -ceq "first|orc-e|;remind|warchief|") "remind 2 with no note appends a remind entry with an empty note"
Test-PageOrder (Get-PageOrder) "2,1,3" "and question 2 now leads the date order"
$shown = Invoke-Decisions @("show", "2")
Check ($shown.code -eq 0 -and @($shown.lines | Where-Object { $_ -ceq "Asked 2 time(s):" }).Count -eq 1 -and @($shown.lines | Where-Object { $_ -like "  * UTC  first (by orc-e)" }).Count -eq 1 -and @($shown.lines | Where-Object { $_ -like "  * UTC  remind (by warchief)" }).Count -eq 1 -and @($shown.lines | Where-Object { $_ -like "*asked again (by warchief, record *" }).Count -eq 1) "show 2 lists when it was asked, each time, and the reminder is in its history"

Write-Host ""
Write-Host "=== refusals write nothing ===" -ForegroundColor Cyan
$before = Get-RecordCount
$unknown = Invoke-Decisions @("remind", "99")
Check ($unknown.code -ne 0 -and $unknown.out -like "*there is no question 99*" -and (Get-RecordCount) -eq $before) "remind of an unknown question is refused with a plain reason, exits non-zero, and writes nothing"
$long = "x" * 201
$tooLong = Invoke-Decisions @("remind", "3", "-Note", $long)
Check ($tooLong.code -ne 0 -and $tooLong.out -like "*'note' is 201 characters long; the most is 200*" -and $tooLong.out -notlike ("*" + $long + "*") -and (Get-RecordCount) -eq $before) "a note of 201 characters is refused whole, never repeated, and nothing is written"
$accented = Invoke-Decisions @("remind", "3", "-Note", ("caf" + [char]0x00E9 + " again"))
Check ($accented.code -ne 0 -and $accented.out -like "*'note' holds a character that is not printable ASCII*" -and (Get-RecordCount) -eq $before) "a note with a letter outside ASCII is refused, and nothing is written"
$tabbed = Invoke-Decisions @("remind", "3", "-Note", ("one" + "`t" + "two"))
Check ($tabbed.code -ne 0 -and $tabbed.out -like "*not printable ASCII*" -and (Get-RecordCount) -eq $before) "and so is one with a tab"
$blank = Invoke-Decisions @("remind", "3", "-Note", "   ")
Check ($blank.code -ne 0 -and $blank.out -like "*'note' is blank*" -and (Get-RecordCount) -eq $before) "and a blank one"
$bare = Invoke-Decisions @("remind", "3", "-Note")
Check ($bare.code -ne 0 -and $bare.out -like "*takes a note as -Note <text>*" -and (Get-RecordCount) -eq $before) "-Note with no text after it is refused at the command line, and nothing is written"
$stray = Invoke-Decisions @("show", "1", "extra")
Check ($stray.code -ne 0 -and $stray.out -like "*decisions show takes no further word on its command line*" -and $stray.out -notlike "*NoteText*") "a stray word after another verb is refused as that, never as a flag nobody typed"
$edge = "y" * 200
$atMost = Invoke-Decisions @("remind", "3", "-Note", $edge)
$listed = Get-Listed
Check ($atMost.code -eq 0 -and (Get-RecordCount) -eq $before + 1 -and (Format-Asked $listed[3]) -ceq ("first|orc-b|;remind|warchief|" + $edge)) "CONTROL: a note of exactly 200 printable ASCII characters is taken"
$before = Get-RecordCount
$close3 = Invoke-Decisions @("close", "3", "-Outcome", "The test box runs them.")
$closed = Invoke-Decisions @("remind", "3", "-Note", "once more")
$listed = Get-Listed
Check ($close3.code -eq 0 -and $closed.code -ne 0 -and $closed.out -like "*question 3 is closed, and only an open question is asked again*" -and $closed.out -like "*-FollowsUp 3*" -and (Get-RecordCount) -eq $before + 1) "remind of a closed question is refused, says to ask a follow-up instead, and writes nothing (the one new record is the close)"
Check ((Format-Asked $listed[3]) -ceq ("first|orc-b|;remind|warchief|" + $edge)) "and the closed question's asked list is as it was"

Write-Host ""
Write-Host "=== a reply that asks is a re-ask; a note is not ===" -ForegroundColor Cyan
$before = Get-RecordCount
$note = Invoke-Decisions @("reply", "1", "-Text", "The job ran fine last night, for what it is worth.", "-Note")
$listed = Get-Listed
Check ($note.code -eq 0 -and (Get-RecordCount) -eq $before + 1 -and [int]$listed[1].askedCount -eq 2) "CONTROL: a reply -Note under question 1 is recorded, and asks nothing: no entry"
$reply = Invoke-Decisions @("reply", "1", "-Text", "Still need your call on this one: keep it or stop it?")
$listed = Get-Listed
Check ($reply.code -eq 0 -and (Format-Asked $listed[1]) -ceq "first|orc-a|;remind|warchief|raised again in chat;thrall-reply|warchief|" -and "$($listed[1].lastAskedAt)" -ceq "$(@($listed[1].asked)[2].at)") "A REPLY THAT ASKS appends a thrall-reply entry, and moves its last-asked time"
Test-PageOrder (Get-PageOrder) "1,3,2" "and question 1 leads the date order again, ahead of 3 (reminded with the 200-character note, then closed) and 2"

Write-Host ""
Write-Host "=== a follow-up asks the question it follows again ===" -ForegroundColor Cyan
$f = Write-File "f.json" '{"title":"Should the release notes also go to the phone app as a notice?","kind":"yes-no","whatItIs":"A short notice when a build is out.","group":"Releases","askedBy":"orc-c"}'
$follow = Invoke-Decisions @("add", "-File", $f, "-FollowsUp", "2")
$listed = Get-Listed
Check ($follow.code -eq 0 -and (Format-Asked $listed[2]) -ceq "first|orc-e|;remind|warchief|;follow-up|orc-c|follow-up question 4") "add -FollowsUp 2 appends a follow-up entry to question 2, by whoever asked the follow-up, naming it"
Check ((Format-Asked $listed[4]) -ceq "first|orc-c|" -and "$($listed[2].lastAskedAt)" -ceq "$($listed[4].addedAt)") "the follow-up itself starts with one first entry, and question 2 was last asked at that moment"
Check ((Format-Asked $listed[1]) -ceq "first|orc-a|;remind|warchief|raised again in chat;thrall-reply|warchief|") "CONTROL: the question it does not follow is untouched"
Test-PageOrder (Get-PageOrder) "4,2,1,3" "by date the follow-up (4) and the question it re-asked (2) share the moment; the higher number goes first, as for every tie"

Write-Host ""
Write-Host "=== list and show carry it ===" -ForegroundColor Cyan
$plain = Invoke-Decisions @("list")
Check ($plain.code -eq 0 -and @($plain.lines | Where-Object { $_ -like "*last asked * UTC (3 times; first 2026-10-01 08:00 UTC)" }).Count -eq 1 -and @($plain.lines | Where-Object { $_ -match '\A\s+asked \d{4}-\d\d-\d\d \d\d:\d\d UTC\z' }).Count -eq 1) "the plain list says when each was last asked: question 1 three times since 1 October, question 4 once"
Check ($null -ne $listed[1].PSObject.Properties["asked"] -and $null -ne $listed[1].PSObject.Properties["askedCount"] -and $null -ne $listed[1].PSObject.Properties["lastAskedAt"]) "list -Json carries asked, askedCount and lastAskedAt on every question"

Write-Host ""
Write-Host "=== the state left behind ===" -ForegroundColor Cyan
$kinds = @(Get-ChildItem -LiteralPath $store -File -Filter "*.json" | Sort-Object Name | ForEach-Object { (ConvertFrom-HordeJson ([System.IO.File]::ReadAllText($_.FullName, $utf8))).kind })
Check (($kinds -join ",") -ceq "question-added,question-added,question-added,question-reminded,question-reminded,question-reminded,question-closed,message-said,message-said,question-added") "the store holds one question-reminded record for each reminder taken - three - and none for the eight refused; the rest is the day as it went"
$first = ConvertFrom-HordeJson ([System.IO.File]::ReadAllText((Join-Path $store "0000000001.json"), $utf8))
Check ("$($first.at)" -ceq $oldAt -and $null -eq $first.data.PSObject.Properties["asked"]) "the old record is untouched: nothing was written back into it"

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-decisions-asked-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the scenario's temp folder is removed"
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store under the user profile is exactly as it was before the scenario"

if ($partial) { Complete-HordeSuite -Success "when each question was last asked, at the command line; the page's order was not run (no node)" -PassCode 3 }
Complete-HordeSuite -Success "when each question was last asked: remind, a reply that asks and a follow-up each ask it again, refusals write nothing, an old question reads as asked once, and the page's Date order follows"
