# END TO END: a question of several parts answered part by part, WITH REAL KEYS, in a real window on a
# real list opened where nobody sees it (the way e2e-decisions-answering-keys.ps1 opens it; its header
# says why the keys are the engine's own and why no window is activated).
#
# WHY (the owner's question 28, 2026-10-07): a question of five parts, (a) to (e), stored the answer
# "a" - he began typing "a ..." and a key saved it and moved him on. Each part now has a field of its
# own; Enter and Tab go from part to part; the answer is sent once, as one message with a line per
# part, when the last part is left or on Ctrl+Enter (decisions/page/list.js, A QUESTION OF SEVERAL
# PARTS). The parts and the recommendation here are written as the keeper writes them in the real list:
# "(a) words" each, and one recommendation "(a) ...; (b) ...".

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\WindowProbe.ps1")

$script:work = Join-Path $env:TEMP ("horde-answer-parts-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$report = Join-Path $script:work "report.json"
$script:probeFile = Join-Path $script:work "probe.json"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$childEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet"); PSModulePath = $null }
$script:probeN = 0
$script:open = $null

function Get-Said {
    param([int]$Number)
    $keep = $env:HORDE_HOME
    try { $env:HORDE_HOME = $hordeHome; return @((Invoke-HordeDecision -Operation "show" -Request @{ number = $Number }).value.question.thread.messages) } finally { $env:HORDE_HOME = $keep }
}
function Write-Whole {
    param([string]$Path, [string]$Text)
    $temp = $Path + ".tmp"
    [System.IO.File]::WriteAllText($temp, $Text, $utf8)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { [System.IO.File]::Replace($temp, $Path, [NullString]::Value) } else { [System.IO.File]::Move($temp, $Path) }
}
function Key { param([string]$Name, [switch]$Shift, [switch]$Ctrl) return [pscustomobject]([ordered]@{ key = $Name; shift = [bool]$Shift; ctrl = [bool]$Ctrl }) }
function Typed { param([string]$Text) return [pscustomobject]([ordered]@{ text = $Text }) }
function Step { param([string]$Do, $Q = $null) $s = [ordered]@{ do = $Do }; if ($null -ne $Q) { $s["q"] = [int]$Q }; return [pscustomobject]$s }
function Send-Probe {
    param([object[]]$Keys = @(), [object[]]$Steps = @(), [int]$Seconds = 120)
    $script:probeN++
    Write-Whole -Path $script:probeFile -Text (ConvertTo-Json -InputObject ([ordered]@{ n = $script:probeN; keys = @($Keys); steps = @($Steps) }) -Depth 5 -Compress)
    $script:wantProbe = $script:probeN
    return (Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds $Seconds -Until { param($r) $null -ne $r.drawn -and $null -ne $r.drawn.answer -and $r.drawn.answer.probe -eq $script:wantProbe -and $r.drawn.answer.pending -eq 0 })
}
function Get-Line { param($Report, [int]$Number) return @($Report.drawn.lines | Where-Object { $_.n -ceq ("" + $Number) })[0] }

try {

Write-Host ""
Write-Host "=== three questions of parts, one plain question after them ===" -ForegroundColor Cyan
$keepHome = $env:HORDE_HOME
try {
    $env:HORDE_HOME = $hordeHome
    . (Join-Path $root "decisions\Operations.ps1")
    $asks = @(
        [ordered]@{ title = "Video Mode: three follow-ups to the new wording for when she cannot zoom there."; kind = "parts"; whatItIs = "Follow-ups to settle."; parts = @("(a) The sentence when she cannot move the picture: approve, or reword.", "(b) Should the button inside the Reader say Video too?", "(c) Should page turns be refused in Video Mode?"); recommendation = "(a) approve; (b) yes; (c) yes, with a sentence in the same style."; group = "Video Mode"; askedBy = "Orc C" },
        [ordered]@{ title = "Two parts with one recommendation that names no part at all."; kind = "parts"; whatItIs = "Follow-ups to settle."; parts = @("(a) The first thing to settle about the plan.", "(b) The second thing to settle about the plan."); recommendation = "both as the plan says"; group = "Video Mode"; askedBy = "Orc C" },
        [ordered]@{ title = "Three parts the founder will take every suggestion for."; kind = "parts"; whatItIs = "Follow-ups to settle."; parts = @("(a) First of three.", "(b) Second of three.", "(c) Third of three."); recommendation = "(a) one; (b) two; (c) three"; group = "Video Mode"; askedBy = "Orc C" },
        [ordered]@{ title = "Should the plain question after the parts go ahead as written?"; kind = "yes-no"; whatItIs = "A plain question."; recommendation = "yes"; group = "Video Mode"; askedBy = "Orc C" }
    )
    foreach ($q in $asks) {
        $added = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $q }
        if ($added.state -cne "known" -or $added.value.outcome -cne "done") { throw ("not added: " + $added.state + " " + $added.reason + " " + (@($added.value.findings) -join "; ")) }
    }
} finally { $env:HORDE_HOME = $keepHome }

$script:open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Hidden", "-Report", $report, "-Probe", $script:probeFile) -Env $childEnv
$first = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 150 -Until { param($r) $null -ne $r.drawn -and @($r.drawn.lines).Count -eq 4 -and $null -ne $r.drawn.answer }
$l1 = Get-Line $first 1
Check ($null -ne $l1 -and @($l1.pa).Count -eq 3 -and (@($l1.pp) -join "|") -ceq "approve|yes|yes, with a sentence in the same style.") ("A FIELD PER PART, each with its own part of the recommendation as its grey suggestion (" + (@($l1.pp) -join "|") + ")")
$l2 = Get-Line $first 2
Check ($null -ne $l2 -and @($l2.pa).Count -eq 2 -and (@($l2.pp) -join "|") -ceq "|") "a recommendation that names no part gives no part a suggestion (it is shown once, above the fields)"
Check (@((Get-Line $first 4).pa).Count -eq 0) "CONTROL: the plain question has one field, as before"

Write-Host ""
Write-Host "=== Enter and Tab go from part to part; one character is not an answer; leaving the last part sends it once ===" -ForegroundColor Cyan
[void](Send-Probe -Keys @([pscustomobject]@{ focus = $true }))
$r = Wait-HordeProbeReport -Path $report -Process $script:open.process -Seconds 40 -Until { param($x) "" + $x.drawn.answer.focus -ne "" }
Check ($r.drawn.answer.focus -ceq "1" -and $r.drawn.answer.focusPart -eq 0) "given the keyboard, the caret is in part (a) of question 1"
$r = Send-Probe -Keys @((Typed "a"), (Key "Enter"))
Check ($r.drawn.answer.focus -ceq "1" -and $r.drawn.answer.focusPart -eq 1 -and @(Get-Said 1).Count -eq 0) "THE OWNER'S CASE: 'a' and Enter go to part (b) and send nothing"
$r = Send-Probe -Keys @((Key "Tab" -Shift), (Typed " - approved as written"), (Key "Tab"), (Typed "no, keep Live View"), (Key "Tab"))
Check ($r.drawn.answer.focus -ceq "1" -and $r.drawn.answer.focusPart -eq 2 -and (@((Get-Line $r 1).pa) -join "|") -ceq "a - approved as written|no, keep Live View|" -and @(Get-Said 1).Count -eq 0) "Shift+Tab goes back a part, Tab forward; nothing is sent while parts remain"
$r = Send-Probe -Keys @((Key "Tab")) -Steps @((Step "settle"))
Check ($r.drawn.answer.focus -ceq "1" -and (@((Get-Line $r 1).pa) -join "|") -ceq "a - approved as written|no, keep Live View|yes, with a sentence in the same style." -and @(Get-Said 1).Count -eq 0) "Tab on an empty part with a suggestion fills it in and stays"
$r = Send-Probe -Keys @((Key "Enter")) -Steps @((Step "settle"))
$said1 = @(Get-Said 1)
Check ($said1.Count -eq 1 -and $said1[0].text -ceq "(a) a - approved as written`n(b) no, keep Live View`n(c) yes, with a sentence in the same style.") ("LEAVING THE LAST PART SENDS THE ANSWER ONCE, one message with a line per part (" + ($said1[0].text -replace "`n", " / ") + ")")
Check ($r.drawn.answer.focus -ceq "2" -and $r.drawn.answer.focusPart -eq 0 -and (Get-Line $r 1).m -ceq "saved") "and the caret is in the first part of question 2; question 1 says saved"

Write-Host ""
Write-Host "=== a saved answer of parts is read back into its fields ===" -ForegroundColor Cyan
Check ((@((Get-Line $r 1).pa) -join "|") -ceq "a - approved as written|no, keep Live View|yes, with a sentence in the same style.") "the saved message stands in the three fields again, part by part, after the list came back with it"

Write-Host ""
Write-Host "=== Ctrl+Enter on the first part with every part empty takes every suggestion and sends ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "focus" -Q 3))
$r = Send-Probe -Keys @((Key "Enter" -Ctrl)) -Steps @((Step "settle"))
$said3 = @(Get-Said 3)
Check ($said3.Count -eq 1 -and $said3[0].text -ceq "(a) one`n(b) two`n(c) three" -and $r.drawn.answer.focus -ceq "4") ("every part's suggestion, sent as one message, and on to question 4 (" + ($said3[0].text -replace "`n", " / ") + ")")

Write-Host ""
Write-Host "=== Ctrl+Enter in one empty part takes its suggestion and sends what stands ===" -ForegroundColor Cyan
$r = Send-Probe -Steps @((Step "focus" -Q 1))
$r = Send-Probe -Keys @((Key "Tab"), (Key "Tab"))
Check ($r.drawn.answer.focus -ceq "1" -and $r.drawn.answer.focusPart -eq 2) "Tab, Tab: part (c) of question 1"
$r = Send-Probe -Keys @((Key "a" -Ctrl), (Key "Backspace"), (Key "Enter" -Ctrl)) -Steps @((Step "settle"))
$again1 = @(Get-Said 1)
Check ((@((Get-Line $r 1).pa) -join "|") -ceq "a - approved as written|no, keep Live View|yes, with a sentence in the same style." -and $again1.Count -eq 1 -and $r.drawn.answer.focus -ceq "2") "part (c) emptied and Ctrl+Enter: its suggestion goes back in; the answer is then the saved one word for word, so nothing is sent twice, and the caret goes on"

$closed = Close-HordeProbeWindow -Process $script:open.process -Handle ([long]$first.handle) -Seconds 40
Check ($closed.exited -and $closed.code -eq 0) "the window is closed and the command exits 0"
$final = Read-HordeProbeReport -Path $report
Check ($final.saysRefused -eq 0 -and @($final.errors).Count -eq 0) ("nothing refused, nothing failed inside the window (" + (@($final.errors) -join " | ") + ")")

} finally {
    if ($null -ne $script:open -and -not $script:open.process.HasExited) { try { $script:open.process.Kill() } catch { } }
    Start-Sleep -Milliseconds 500
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-answer-parts-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
        for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $script:work); $i++) { try { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 } }
    }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the scenario's temp folder is removed"

Complete-HordeSuite -Success "a question of parts is answered part by part with real keys, and sent once as one message the keeper reads whole"
