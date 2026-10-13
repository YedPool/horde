# END TO END: "CHANGE MY ANSWER" - a real window on a real list, opened where nobody sees it (the way
# e2e-decisions-answering-keys.ps1 opens it), the keeper's side by the real command line.
#
# WHY (2026-10-13): since the founder's rule that an answered question leaves his list at once, a
# question he has answered is under the folded "With Thrall", where it was only read - so a wrong
# answer could not be put right. Each such row now offers "Change my answer": his answer goes back
# into a field, and what he changes is sent as a CORRECTION - a NEW record that names the record of
# the answer it corrects. Nothing is edited in place; the keeper's inbox and its doorbell say it is a
# correction. A change that is not saved keeps its words and shows the reason.
# NOTHING OF THE OWNER'S IS USED: HORDE_HOME is a folder this scenario made and removes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
. (Join-Path $root "test\lib\WindowProbe.ps1")

$script:work = Join-Path $env:TEMP ("horde-answer-change-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$report = Join-Path $script:work "report.json"
$script:probeFile = Join-Path $script:work "probe.json"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$childEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet"); PSModulePath = $null }
$cliEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet") }
$script:probeN = 0
$script:open = $null

function Get-Said {
    param([int]$Number)
    $keep = $env:HORDE_HOME
    try { $env:HORDE_HOME = $hordeHome; return @((Invoke-HordeDecision -Operation "show" -Request @{ number = $Number }).value.question.thread.messages) } finally { $env:HORDE_HOME = $keep }
}
function Get-SaidLine { param([int]$Number) return (@(Get-Said $Number | ForEach-Object { "" + $_.sequence + ":" + $_.part + ":" + $_.corrects + "=" + $_.text }) -join " | ") }
function Write-Whole {
    param([string]$Path, [string]$Text)
    $temp = $Path + ".tmp"
    [System.IO.File]::WriteAllText($temp, $Text, $utf8)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { [System.IO.File]::Replace($temp, $Path, [NullString]::Value) } else { [System.IO.File]::Move($temp, $Path) }
}
function Key { param([string]$Name, [switch]$Shift, [switch]$Ctrl) return [pscustomobject]([ordered]@{ key = $Name; shift = [bool]$Shift; ctrl = [bool]$Ctrl }) }
function Typed { param([string]$Text) return [pscustomobject]([ordered]@{ text = $Text }) }
function Step { param([string]$Do, $Q = $null, $Part = $null, [string]$Text = "") $s = [ordered]@{ do = $Do }; if ($null -ne $Q) { $s["q"] = [int]$Q }; if ($null -ne $Part) { $s["part"] = [int]$Part }; if ($Do -ceq "change-type") { $s["text"] = $Text }; return [pscustomobject]$s }
function Send-Probe {
    param([object[]]$Keys = @(), [object[]]$Steps = @(), [int]$Seconds = 120)
    $script:probeN++
    Write-Whole -Path $script:probeFile -Text (ConvertTo-Json -InputObject ([ordered]@{ n = $script:probeN; keys = @($Keys); steps = @($Steps) }) -Depth 5 -Compress)
    $script:wantProbe = $script:probeN
    return (Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds $Seconds -Until { param($r) $null -ne $r.drawn -and $null -ne $r.drawn.answer -and $r.drawn.answer.probe -eq $script:wantProbe -and $r.drawn.answer.pending -eq 0 })
}
function Wait-Report { param([scriptblock]$Until, [int]$Seconds = 60) return (Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds $Seconds -Until $Until) }
function Get-Line { param($Report, [int]$Number) return @($Report.drawn.lines | Where-Object { $_.n -ceq ("" + $Number) })[0] }
function Get-Done { param($Report, [int]$Number) return @($Report.drawn.done | Where-Object { $_.n -ceq ("" + $Number) })[0] }
function Horde { param([string[]]$Arguments) return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("decisions") + $Arguments) -Env $cliEnv) }

try {

$pins = @(Set-HordeTestMessengerPins -Root $root -HordeHome $hordeHome)
Check ($pins.Count -ge 1 -and @($pins | Where-Object { -not (Test-Path -LiteralPath (Join-Path $hordeHome ("settings\messenger-" + $_ + ".json")) -PathType Leaf) }).Count -eq 0) ("PIN: every messenger that has a pin is pinned in this home, so no horde started here can post for real (" + ($pins -join ", ") + ")")

Write-Host ""
Write-Host "=== three questions: one answered already, one of two parts answered already, one still to answer ===" -ForegroundColor Cyan
$keepHome = $env:HORDE_HOME
try {
    $env:HORDE_HOME = $hordeHome
    . (Join-Path $root "decisions\Operations.ps1")
    $when = [datetime]::SpecifyKind([datetime]"2026-01-01T09:00:00", [System.DateTimeKind]::Utc)
    $asks = @(
        [ordered]@{ title = "Should the closing chime play when the assistant closes?"; kind = "yes-no"; whatItIs = "The app has no closing sound today."; recommendation = "yes"; group = "The voice"; askedBy = "Orc B" },
        [ordered]@{ title = "Two things to settle about the chime, one by one."; kind = "parts"; whatItIs = "Follow-ups."; parts = @("(a) Which of the three chimes?", "(b) How loud should it be?"); group = "The voice"; askedBy = "Orc B" },
        [ordered]@{ title = "Should the plain question still to answer go ahead as written?"; kind = "yes-no"; whatItIs = "A plain question."; recommendation = "yes"; group = "The voice"; askedBy = "Orc B" }
    )
    $i = 0
    foreach ($q in $asks) { $i++; $added = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $q } -Now $when.AddMinutes(10 - $i); if ($added.state -cne "known" -or $added.value.outcome -cne "done") { throw ("not added: " + $added.reason + " " + (@($added.value.findings) -join "; ")) } }
    foreach ($say in @(@{ number = 1; text = "Yes, play it." }, @{ number = 2; text = "The second chime."; part = "a" }, @{ number = 2; text = "Quiet."; part = "b" })) {
        $r = @{ id = [guid]::NewGuid().ToString("N"); actor = "founder"; speaker = "founder"; route = "window"; wordingVersion = 1 }
        foreach ($k in $say.Keys) { $r[$k] = $say[$k] }
        $done = Invoke-HordeDecision -Operation "say" -Request $r
        if ($done.state -cne "known" -or $done.value.outcome -cne "done") { throw ("not said: " + $done.reason + " " + (@($done.value.findings) -join "; ")) }
    }
} finally { $env:HORDE_HOME = $keepHome }
$first1 = @(Get-Said 1)[0]

$script:open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Hidden", "-Report", $report, "-Probe", $script:probeFile) -Env $childEnv
$first = Wait-Report { param($r) $null -ne $r.drawn -and @($r.drawn.lines).Count -eq 1 -and @($r.drawn.done).Count -eq 2 -and $null -ne $r.drawn.answer } 150
Check ((@($first.drawn.lines | ForEach-Object { $_.n }) -join ",") -ceq "3" -and (Get-Done $first 1).k -ceq "thrall" -and (Get-Done $first 2).k -ceq "thrall") "the two he has answered are with the keeper, out of his list; the third is the list"
Check ((Get-Done $first 1).cb -eq $true -and (Get-Done $first 1).ch -eq $false -and (Get-Done $first 2).cb -eq $true -and (Get-Done $first 1).a -ceq "Yes, play it." -and (Get-Done $first 2).a -ceq "(a) The second chime.`n(b) Quiet.") "EACH ANSWERED QUESTION OFFERS 'Change my answer', under his answer as he gave it"

Write-Host ""
Write-Host "=== Change my answer: his words go back into a field; cancelled, nothing is sent ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "change" -Q 1))
Check ((Get-Done $r 1).ch -eq $true -and (@((Get-Done $r 1).cf) -join "|") -ceq "Yes, play it." -and (Get-Done $r 2).ch -eq $false) "pressed, question 1's row holds a field with his answer in it; the other row is as it was"
$r = Send-Probe -Steps @((Step "change-type" -Q 1 -Part 0 -Text "No, never."), (Step "change-cancel" -Q 1))
Check ((Get-Done $r 1).ch -eq $false -and (Get-Done $r 1).a -ceq "Yes, play it." -and @(Get-Said 1).Count -eq 1) "CANCELLED, the row is read-only again with his answer as it was, and nothing was sent"
$r = Send-Probe -Steps @((Step "change" -Q 1), (Step "change-save" -Q 1), (Step "settle"))
Check ((Get-Done $r 1).ch -eq $false -and @(Get-Said 1).Count -eq 1) "saved with nothing changed, nothing is sent either: an answer is not corrected by itself"

Write-Host ""
Write-Host "=== saved: a NEW record that names the answer it corrects; the old record is as he said it ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "change" -Q 1), (Step "change-type" -Q 1 -Part 0 -Text "No - do not play it."), (Step "change-save" -Q 1), (Step "settle"))
$said1 = @(Get-Said 1)
Check ($said1.Count -eq 2 -and $said1[1].text -ceq "No - do not play it." -and $said1[1].corrects -eq [long]$first1.sequence -and $said1[1].replaces -eq $true -and $said1[1].route -ceq "window" -and $said1[1].speaker -ceq "founder") ("THE CHANGE IS A SECOND RECORD, typed in the window, that names the record of the answer it corrects (" + (Get-SaidLine 1) + ")")
Check ($said1[0].text -ceq "Yes, play it." -and $said1[0].corrects -eq 0 -and [long]$said1[0].sequence -eq [long]$first1.sequence) "AND THE FIRST RECORD IS NOT EDITED: it holds his first words still"
$shown = Wait-Report { param($x) "$((@($x.drawn.done | Where-Object { $_.n -ceq '1' })[0]).a)" -ceq "No - do not play it." } 30
Check ((Get-Done $shown 1).a -ceq "No - do not play it." -and (Get-Done $shown 1).ch -eq $false -and (Get-Done $shown 1).k -ceq "thrall" -and $null -eq (Get-Line $shown 1)) "the row is read-only again and shows the changed words; the question is still with the keeper, not back in his list"
$inbox = Horde @("inbox", "-Peek")
Check ($inbox.code -eq 0 -and $inbox.out -like ("*(A CORRECTION: he changed his answer. This replaces what he said in record " + $first1.sequence + ")*") -and $inbox.out -like "*No - do not play it.*") "THE KEEPER'S INBOX SAYS IT IS A CORRECTION, and of which record"
$listed = Horde @("list")
Check ($listed.code -eq 0 -and $listed.out -like "*answered, and off his list: No - do not play it.*") "and the keeper's list shows the corrected words as his answer"

Write-Host ""
Write-Host "=== a change that is NOT saved keeps its words, with the reason under them ===" -ForegroundColor Cyan
$secret = "the key is ghp_" + ("C" * 36)
$r = Send-Probe -Steps @((Step "change" -Q 1), (Step "change-type" -Q 1 -Part 0 -Text $secret), (Step "change-save" -Q 1), (Step "settle"))
$refused = Wait-Report { param($x) "$(@((@($x.drawn.done | Where-Object { $_.n -ceq '1' })[0]).cr)[0])" -ne "" } 30
$d1 = Get-Done $refused 1
Check ($d1.ch -eq $true -and @($d1.cr)[0] -clike "Not saved:*" -and @($d1.cr)[0] -notlike "*ghp_*" -and @($d1.cf)[0] -ceq $secret -and @(Get-Said 1).Count -eq 2) ("REFUSED, the field is still open with his words in it and the reason under them, which repeats none of them; nothing is in the store (" + @($d1.cr)[0] + ")")
$r = Send-Probe -Steps @((Step "change-type" -Q 1 -Part 0 -Text "No - and no chime at all."), (Step "change-save" -Q 1), (Step "settle"))
$said1 = @(Get-Said 1)
Check ($said1.Count -eq 3 -and $said1[2].text -ceq "No - and no chime at all." -and $said1[2].corrects -eq [long]$said1[1].sequence) ("with words that can be saved the change is saved - as a correction of the answer that stood, which was itself a correction (" + (Get-SaidLine 1) + ")")

Write-Host ""
Write-Host "=== a question answered part by part: one part changed, the other left alone ===" -ForegroundColor Cyan
$before2 = @(Get-Said 2)
$r = Send-Probe -Steps @((Step "change" -Q 2))
Check ((@((Get-Done $r 2).cf) -join "|") -ceq "The second chime.|Quiet.") "its row holds a field for each part, each with that part's answer"
$r = Send-Probe -Steps @((Step "change-type" -Q 2 -Part 1 -Text "Loud."), (Step "change-save" -Q 2), (Step "settle"))
$said2 = @(Get-Said 2)
Check ($said2.Count -eq 3 -and $said2[2].part -ceq "b" -and $said2[2].text -ceq "Loud." -and $said2[2].corrects -eq [long]$before2[1].sequence -and $said2[0].text -ceq "The second chime." -and $said2[1].text -ceq "Quiet.") ("ONLY THE PART HE CHANGED IS SENT: one new record, for part (b), naming that part's answer; part (a) is untouched (" + (Get-SaidLine 2) + ")")
$shown2 = Wait-Report { param($x) "$((@($x.drawn.done | Where-Object { $_.n -ceq '2' })[0]).a)" -ceq "(a) The second chime.`n(b) Loud." } 30
Check ((Get-Done $shown2 2).a -ceq "(a) The second chime.`n(b) Loud." -and (Get-Done $shown2 2).k -ceq "thrall") "and the row shows part (a) as it was and part (b) as changed"

Write-Host ""
Write-Host "=== the keys, real ones: Enter saves a change, Escape leaves it ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "change" -Q 2))
$r = Send-Probe -Keys @((Typed " The one from the second recording."), (Key "Escape")) -Steps @((Step "settle"))
Check ((Get-Done $r 2).ch -eq $false -and @(Get-Said 2).Count -eq 3 -and $r.handBack.asked -eq 0) "a real Escape in the field leaves the answer as it was, sends nothing - and is not the window's Escape: the keyboard is not handed away"
$r = Send-Probe -Steps @((Step "change" -Q 2))
$r = Send-Probe -Keys @((Typed " The one from the second recording."), (Key "Enter")) -Steps @((Step "settle"))
$said2 = @(Get-Said 2)
Check ($said2.Count -eq 4 -and $said2[3].part -ceq "a" -and $said2[3].text -ceq "The second chime. The one from the second recording." -and $said2[3].corrects -eq [long]$before2[0].sequence) ("a real Enter in the field of part (a), after words typed at its end, saves that part's change (" + (Get-SaidLine 2) + ")")
Check ((Get-Line $r 3).a -ceq "" -and @(Get-Said 3).Count -eq 0) "and the question still to answer was never touched: nothing was typed into it or sent for it"

$closed = Close-HordeProbeWindow -Process $script:open.process -Handle ([long]$first.handle) -Seconds 40
Check ($closed.exited -and $closed.code -eq 0) "the window is closed and the command exits 0"
$final = Read-HordeProbeReport -Path $report
Check ($final.saysRefused -eq 1 -and @($final.errors).Count -eq 0) ("one change was refused - the one that held a secret - and nothing failed inside the window (refused " + $final.saysRefused + "; " + (@($final.errors) -join " | ") + ")")

} finally {
    if ($null -ne $script:open -and -not $script:open.process.HasExited) { try { $script:open.process.Kill() } catch { } }
    Start-Sleep -Milliseconds 500
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-answer-change-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
        for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $script:work); $i++) { try { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 } }
    }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the scenario's temp folder is removed"

Complete-HordeSuite -Success "an answer that is with the keeper can be changed: the change is a new record that names the answer it corrects, the keeper is told it is a correction, and nothing is edited in place"
