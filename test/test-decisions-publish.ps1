# DOES `horde decisions publish` PUBLISH THE CALLING SESSION'S LIST, AND NOBODY ELSE'S?
#
# decisions/Publish.ps1 against a fleet.db this suite seeds in a home of its own (test/fixtures/
# decisions-publish-seed.mjs): the Thrall M, Orcs F and G, questions 7 and 9. The calling session is a
# test double handed in through the proofs' own seams (as test/test-decisions-change.ps1 hands in its
# sender); the real proof is notices/Sender.ps1's own suite. What it attacks:
#   - a list is published for the proven Orc and prints one line; the same list again is "unchanged" and
#     writes no snapshot; a changed list is a new snapshot and the old one is kept;
#   - the file cannot name who publishes: a file naming another Orc is refused, whatever the session is;
#   - a misspelt field, a field that is not text, a word that is no importance, an unknown question number
#     and a secret-looking text are refused, each naming the exact field and never quoting the value;
#   - an empty list is valid; text beyond 400 characters and text beyond plain ASCII are refused;
#   - the live lists read back through `published`, and the real command line does the same under this
#     PowerShell and, from this suite's first run, under the MSI PowerShell 7 too (the same checks run
#     again in a child with -Inner).
# NODE 24 IS NEEDED (node:sqlite). Without it nothing runs, it says so, and the suite exits 3.

param([switch]$Inner)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "decisions\Publish.ps1")
. (Join-Path $root "test\lib\Cli.ps1")

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] no node here: fleet.db cannot run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}

$pwsh7 = "C:\Program Files\PowerShell\7\pwsh.exe"
$isCore = ("" + $PSVersionTable.PSEdition) -ceq "Core"
$shell = $(if ($isCore) { $pwsh7 } else { "powershell.exe" })
$utf8 = New-Object System.Text.UTF8Encoding($false)
$work = Join-Path $env:TEMP ("horde-decisions-publish-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$hordeHome = Join-Path $work "home"
$fakeProfile = Join-Path $work "profile"
New-Item -ItemType Directory -Path $fakeProfile | Out-Null
$keptProfile = $env:USERPROFILE
$keptHome = $env:HORDE_HOME
$sessionF = "11111111-1111-4111-8111-111111111111"
$sessionG = "22222222-2222-4222-8222-222222222222"
$sessionM = "33333333-3333-4333-8333-333333333333"
$senderF = { [pscustomobject]@{ ok = $true; reason = ""; label = "F"; sessionId = "11111111-1111-4111-8111-111111111111" } }
$senderM = { [pscustomobject]@{ ok = $true; reason = ""; label = "M"; sessionId = "33333333-3333-4333-8333-333333333333" } }
$senderNobody = { [pscustomobject]@{ ok = $false; reason = "no notice was sent: this is not run from inside a session"; label = ""; sessionId = "" } }
# The seat proof: an Orc's letter holds the seat of the role orc; the Thrall holds only the warchief's.
$seat = { param($who, $role) if ("$role" -ceq "warchief") { return [pscustomobject]@{ ok = ("$($who.label)" -ceq "M"); reason = "not the warchief" } }; return [pscustomobject]@{ ok = ("$($who.label)" -cne "M"); reason = "M wears no Orc's seat" } }

function Write-List { param([string]$Name, [string]$Text) $p = Join-Path $work $Name; [System.IO.File]::WriteAllText($p, $Text, $utf8); return $p }
function Publish-List {
    # The verb, in this process, as the session $Sender; { lines; failure } or { threw } when it throws.
    param([string]$Text, [scriptblock]$Sender = $senderF)
    $p = Write-List -Name ("list-" + [guid]::NewGuid().ToString("N") + ".json") -Text $Text
    try {
        $r = Invoke-HordeDecisionPublishVerb -Verb publish -Given @{ File = $p } -Sender $Sender -SeatProof $seat
        return [pscustomobject]@{ lines = @($r.lines); failure = "$($r.failure)"; threw = "" }
    } catch { return [pscustomobject]@{ lines = @(); failure = ""; threw = "$($_.Exception.Message)" } }
}
function Get-PublishedJson {
    param([string]$Orc = "")
    $given = @{ Json = $true }
    if ($Orc -ne "") { $given["Orc"] = $Orc }
    $r = Invoke-HordeDecisionPublishVerb -Verb published -Given $given
    return (($r.lines -join "") | ConvertFrom-Json)
}

try {
    $env:HORDE_HOME = $hordeHome
    $null = & $node.Source (Join-Path $root "test\fixtures\decisions-publish-seed.mjs") $hordeHome
    Check (Test-Path -LiteralPath (Join-Path $hordeHome "fleet.db")) "CONTROL: the seeded fleet.db is there"

    Write-Host ""
    Write-Host "=== publish, again, changed ===" -ForegroundColor Cyan
    $one = '{"items":[{"questionNumber":7,"text":"Ship the page?","recommendation":"yes","importance":"high","blocks":"all"},{"questionNumber":null,"text":"Pick a colour"}]}'
    $a = Publish-List $one
    Check ($a.threw -eq "" -and $a.failure -eq "" -and @($a.lines).Count -eq 1 -and $a.lines[0] -cmatch '\Apublished 2 items \(snapshot [0-9A-Z]{26}\)\z') ("a list is published in one line (" + (@($a.lines) -join "|") + $a.threw + $a.failure + ")")
    $live = Get-PublishedJson -Orc "F"
    Check (@($live.lists).Count -eq 1 -and $live.lists[0].count -eq 2 -and $live.lists[0].items[0].questionNumber -eq 7 -and $live.lists[0].items[1].text -ceq "Pick a colour") "it reads back in order, question 7 by its number"
    $snap1 = $live.lists[0].snapshot
    $b = Publish-List $one
    # Since fleet.db migration 5 an equal publish also records a confirm, and the line says when.
    Check ($b.lines.Count -eq 1 -and $b.lines[0] -cmatch ('\Aunchanged, confirmed \d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z \(snapshot ' + $snap1 + '\)\z')) ("the same list again is unchanged, confirmed, naming the same snapshot (" + (@($b.lines) -join "|") + $b.threw + ")")
    Start-Sleep -Milliseconds 20
    $two = '{"items":[{"questionNumber":9,"text":"Merge it?"}]}'
    $c = Publish-List $two
    Check ($c.lines.Count -eq 1 -and $c.lines[0] -cmatch '\Apublished 1 item \(snapshot ' -and $c.lines[0] -cnotlike ("*" + $snap1 + "*")) ("a changed list is a new snapshot (" + (@($c.lines) -join "|") + $c.threw + ")")
    $live2 = Get-PublishedJson -Orc "F"
    Check ($live2.lists[0].count -eq 1 -and $live2.lists[0].items[0].questionNumber -eq 9) "the live list is now the new one"
    $snapCount = (& $node.Source "--input-type=module" "-e" ("import { DatabaseSync } from 'node:sqlite'; const d = new DatabaseSync(process.argv[1], { readOnly: true }); console.log(d.prepare('SELECT count(*) AS n FROM decisions_snapshot').get().n + ' ' + d.prepare('SELECT count(*) AS n FROM decisions_snapshot_item WHERE snapshot_id = ?').get('" + $snap1 + "').n)") (Join-Path $hordeHome "fleet.db"))
    Check ("$snapCount".Trim() -ceq "2 2") ("the old list stays as history with its two lines, beside the new one (snapshots and old lines: " + "$snapCount".Trim() + ")")

    Write-Host ""
    Write-Host "=== who publishes ===" -ForegroundColor Cyan
    $named = Publish-List '{"orc":"G","items":[]}'
    Check ($named.failure -like "refused: the file names who publishes ('orc')*never taken from a file*") ("a file naming another Orc is refused (" + $named.failure + $named.threw + ")")
    Check ((Get-PublishedJson).lists.Count -eq 1) "and nothing was published for G"
    foreach ($key in @("orcId", "letter", "session", "by", "Orc")) {
        $r = Publish-List ('{"' + $key + '":"F","items":[]}')
        Check ($r.failure -like "refused: the file names who publishes*") ("a file with '" + $key + "' is refused too")
    }
    $nobody = Publish-List $one $senderNobody
    Check ($nobody.threw -like "*could not be proven*not run from inside a session*") ("a command outside any session is refused (" + $nobody.threw + ")")
    $thrall = Publish-List '{"items":[{"text":"Thrall asks"}]}' $senderM
    Check ($thrall.lines.Count -eq 1 -and $thrall.lines[0] -cmatch '\Apublished 1 item') ("the Thrall publishes as itself (" + (@($thrall.lines) -join "|") + $thrall.threw + ")")
    Check ((Get-PublishedJson).lists.Count -eq 2) "and its list is its own beside F's"
    $senderLetterNoSeat = { [pscustomobject]@{ ok = $true; reason = ""; label = "X"; sessionId = "44444444-4444-4444-8444-444444444444" } }
    $noRow = Publish-List $one $senderLetterNoSeat
    Check ($noRow.failure -like "*no row for Orc X*" -or $noRow.threw -ne "") ("an Orc fleet.db does not know publishes nowhere (" + $noRow.failure + $noRow.threw + ")")

    Write-Host ""
    Write-Host "=== refusals name the field ===" -ForegroundColor Cyan
    $mis = Publish-List '{"items":[{"txet":"x"}]}'
    Check ($mis.failure -ceq "refused: item 1 has no field 'txet'; its fields are questionNumber, text, recommendation, importance, blocks") ("a misspelt field is refused, named (" + $mis.failure + ")")
    $top = Publish-List '{"itemz":[]}'
    Check ($top.failure -like "refused: the file has no field 'itemz'*") ("a misspelt top field is refused (" + $top.failure + ")")
    $notText = Publish-List '{"items":[{"text":"ok"},{"text":5}]}'
    Check ($notText.failure -ceq "refused: item 2 text must be text") ("a value that is not text is refused (" + $notText.failure + ")")
    $word = Publish-List '{"items":[{"text":"x","importance":"urgent"}]}'
    Check ($word.failure -like "refused: item 1 importance must be one of*") ("an importance that is no word is refused (" + $word.failure + ")")
    $blk = Publish-List '{"items":[{"text":"x","blocks":"some"}]}'
    Check ($blk.failure -like "refused: item 1 blocks must be one of*") "a blocks that is no word is refused"
    $unk = Publish-List '{"items":[{"text":"x"},{"questionNumber":4242,"text":"y"}]}'
    Check ($unk.failure -ceq "refused: item 2 names question 4242, which is not in the decisions store") ("an unknown question number is refused, the number named (" + $unk.failure + ")")
    $badNum = Publish-List '{"items":[{"questionNumber":"7","text":"y"}]}'
    Check ($badNum.failure -like "refused: item 1 questionNumber must be*") "a question number written as text is refused"
    $missing = Publish-List '{"items":[{"questionNumber":7}]}'
    Check ($missing.failure -ceq "refused: item 1 text is missing") ("a line with no text is refused (" + $missing.failure + ")")
    $long = Publish-List ('{"items":[{"text":"' + ("a" * 401) + '"}]}')
    Check ($long.failure -ceq "refused: item 1 text is 401 characters; at most 400") ("text beyond 400 characters is refused (" + $long.failure + ")")
    $edge = Publish-List ('{"items":[{"text":"' + ("a" * 400) + '"}]}')
    Check ($edge.lines.Count -eq 1 -and $edge.lines[0] -cmatch '\Apublished') "400 characters are fine"
    $uni = Publish-List '{"items":[{"text":"caf\u00e9"}]}'
    Check ($uni.failure -ceq "refused: item 1 text holds the character U+00E9, which is not plain ASCII") ("text beyond plain ASCII is refused (" + $uni.failure + ")")
    $nl = Publish-List '{"items":[{"text":"two\nlines"}]}'
    Check ($nl.failure -like "refused: item 1 text holds a line break*") ("a line break inside a text line is refused (" + $nl.failure + ")")
    $tab = Publish-List '{"items":[{"text":"a\tb"}]}'
    Check ($tab.failure -like "refused: item 1 text holds the character U+0009*") ("a tab inside a text line is refused (" + $tab.failure + ")")
    $notArray = Publish-List '{"items":{"text":"x"}}'
    Check ($notArray.failure -ceq "refused: items must be a list (an empty one is a list)") "items that is not a list is refused"
    $noItems = Publish-List '{}'
    Check ($noItems.failure -like "refused: the file needs items*") "a file with no items is refused"
    $notJson = Publish-List 'items: nothing'
    Check ($notJson.threw -like "*is not JSON*") "a file that is not JSON is refused"
    $secretValue = "sk-" + ("A1b2C3d4" * 6)
    $sec = Publish-List ('{"items":[{"text":"use ' + $secretValue + ' now"}]}')
    Check ($sec.failure -like "refused: the file holds what looks like a secret*" -and $sec.failure -notlike ("*" + $secretValue + "*")) ("a secret-looking text is refused and never repeated (" + $sec.failure + ")")
    $secName = Publish-List ('{"items":[{"' + $secretValue + '":"x","text":"y"}]}')
    Check ($secName.failure -like "refused: the file holds what looks like a secret*" -and $secName.failure -notlike ("*" + $secretValue + "*")) "a secret-looking field name is not repeated either"
    $env:HORDE_HOME = ""
    $env:USERPROFILE = $fakeProfile
    try { $nh = Publish-List $one } finally { $env:HORDE_HOME = $hordeHome; $env:USERPROFILE = $keptProfile }
    Check ($nh.threw -like "*needs HORDE_HOME*") ("with HORDE_HOME unset publishing is refused in a sentence about the home (" + $nh.threw + ")")
    Check (-not (Test-Path -LiteralPath (Join-Path $fakeProfile ".horde"))) "and no default home was made under the profile"
    $live3 = Get-PublishedJson -Orc "F"
    Check ($live3.lists[0].count -eq 1 -and $live3.lists[0].items[0].text.Length -eq 400) "none of the refusals changed F's live list (the last good one stands)"

    Write-Host ""
    Write-Host "=== an empty list ===" -ForegroundColor Cyan
    $empty = Publish-List '{"items":[]}'
    Check ($empty.lines.Count -eq 1 -and $empty.lines[0] -cmatch '\Apublished 0 items \(snapshot [0-9A-Z]{26}\)\z') ("an empty list is valid: nothing open (" + (@($empty.lines) -join "|") + $empty.threw + $empty.failure + ")")
    Check ((Get-PublishedJson -Orc "F").lists[0].count -eq 0) "and it is F's live list"
    $empty2 = Publish-List '{"items":[]}'
    Check ($empty2.lines.Count -eq 1 -and $empty2.lines[0] -cmatch '\Aunchanged') "an empty list again is unchanged"

    Write-Host ""
    Write-Host "=== read back, at the real command line ===" -ForegroundColor Cyan
    $cli = @{ HORDE_HOME = $hordeHome }
    $rp = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "published") -Env $cli -Shell $shell
    Check ($rp.code -eq 0 -and $rp.out -cmatch '(?m)^F: 0 items, published ' -and $rp.out -cmatch '(?m)^M: 1 item, published ') ("published lists every Orc's live list (" + $rp.code + ")")
    $rj = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "published", "-Orc", "M", "-Json") -Env $cli -Shell $shell
    $parsed = $null
    try { $parsed = ($rj.out.Trim() -split "\r?\n")[0] | ConvertFrom-Json } catch { }
    Check ($rj.code -eq 0 -and $null -ne $parsed -and @($parsed.lists).Count -eq 1 -and $parsed.lists[0].orc -ceq "M" -and $parsed.lists[0].items[0].text -ceq "Thrall asks") "published -Orc M -Json is one line of data for M alone"
    $rn = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "published", "-Orc", "G") -Env $cli -Shell $shell
    Check ($rn.code -eq 0 -and $rn.out -like "*Orc G has not published a decisions list*") "an Orc with no list says so"
    $rb = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "published", "-Orc", "f") -Env $cli -Shell $shell
    Check ($rb.code -ne 0 -and $rb.out -like "*-Orc is an Orc's lane letter*") "a lower-case letter is refused"
    $rw = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "publish", "-Json") -Env $cli -Shell $shell
    Check ($rw.code -ne 0 -and $rw.out -like "*-Json does not belong to decisions publish*") "a flag that belongs to another verb is refused"
    $fp = Write-List -Name "real.json" -Text $one
    $before = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "published", "-Json") -Env $cli -Shell $shell
    $rr = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "publish", "-File", $fp) -Env $cli -Shell $shell
    $after = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "published", "-Json") -Env $cli -Shell $shell
    # Run from this session's own process tree the proof may succeed or fail by the fleet's own records; either
    # way it must be one line, and a refusal must have changed nothing.
    Check ($rr.code -eq 0 -or ($rr.code -ne 0 -and $before.out -ceq $after.out)) ("the real command line either publishes as the proven session or refuses and changes nothing (exit " + $rr.code + ")")
    $rm = Invoke-HordeCliProcess -Root $root -HordeArgs @("decisions", "publish", "-File", $fp) -Env @{ HORDE_HOME = ""; USERPROFILE = $fakeProfile } -Shell $shell
    Check ($rm.code -ne 0) "with HORDE_HOME unset the real command line publishes nothing"
}
finally {
    $env:HORDE_HOME = $keptHome
    $env:USERPROFILE = $keptProfile
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

if (-not $Inner) {
    Write-Host ""
    Write-Host "=== the same checks under PowerShell 7 (MSI) ===" -ForegroundColor Cyan
    Check (Test-Path -LiteralPath $pwsh7 -PathType Leaf) "CONTROL: the MSI PowerShell 7 is installed"
    if (Test-Path -LiteralPath $pwsh7 -PathType Leaf) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $pwsh7
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $MyInvocation.MyCommand.Path + '" -Inner'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $errTask = $p.StandardError.ReadToEndAsync()
        $out = $p.StandardOutput.ReadToEnd()
        if (-not $p.WaitForExit(600000)) { try { $p.Kill() } catch { } }
        $code = $p.ExitCode
        $p.Dispose()
        $text = $out + "`n" + $errTask.Result
        $passes = ([regex]::Matches($text, '\[PASS\]')).Count
        foreach ($l in ($text -split "\r?\n")) { if ($l -match '\[(FAIL|ERROR)\]') { Write-Host ("  (pwsh 7) " + $l.Trim()) -ForegroundColor Red } }
        Check ($passes -ge 40) ("CONTROL: the PowerShell 7 run really ran its checks (" + $passes + " passed)")
        Check ($code -eq 0 -and $text -notmatch '\[(FAIL|ERROR)\]') ("every check passes under PowerShell 7 (exit " + $code + ")")
    }
}

Complete-HordeSuite -Success "decisions publish publishes the proven session's list and nobody else's"
