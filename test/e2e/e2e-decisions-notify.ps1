# END TO END: `horde decisions open` starts notify beside the window and stops it when the window closes;
# `horde decisions notify -Once` then finds the home free and the answer still untold.
#
# The user of notify is the session that keeps the list: it wants to hear that the founder answered in
# the window, and never to be told a notice went out when none did. This scenario is the window's
# short life with one answer waiting: the founder's answer is written at the real command line; the
# window is opened where nobody sees it, and its report says notify started beside it and what notify
# says - here, with only the in-process test messenger in this Horde, that the answer is pending
# because no messenger on this machine can deliver to a session; the window is closed, the command
# says what notify last said, and notify is gone; `notify -Once` is then run at the real command line,
# finds no other notify holding the home, and says the same plain thing. Nothing is recorded as told,
# and the answer is still unread. Every step is the shipped horde.ps1 run as its own process.
#
# NO WINDOW IS SEEN AND NO KEYBOARD IS TAKEN (-Hidden), and no terminal is involved: the fleet's
# registry is pointed at a folder of this scenario's that does not exist, so no seat is read and no
# session is told anything. HORDE_HOME is a folder this scenario made and removes; the real store is
# listed before and after and must not have changed (CONTRIBUTING 9).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\WindowProbe.ps1")

$script:work = Join-Path $env:TEMP ("horde-notify-e2e-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$hordeHome = Join-Path $script:work "home"
$report = Join-Path $script:work "report.json"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$childEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet"); PSModulePath = $null }
$cliEnv = @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $script:work "no-fleet") }

function Get-RealStoreListing {
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing
function Invoke-Decisions { param([string[]]$HordeArgs) return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("decisions") + $HordeArgs) -Env $cliEnv) }

try {

Write-Host ""
Write-Host "=== an answer waits; the window opens, and notify stands beside it ===" -ForegroundColor Cyan
# A quiet period of 0 s, so the scenario does not wait 30 s for what test/test-decisions-notify.ps1 holds.
New-Item -ItemType Directory -Path (Join-Path $hordeHome "settings") -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $hordeHome "settings\decisions-notify.json"), '{"schemaVersion":1,"settings":{"quietSeconds":0}}', $utf8)
$qFile = Join-Path $script:work "question.json"
[System.IO.File]::WriteAllText($qFile, '{"title":"Should the doorbell ring when he answers in the window?","kind":"yes-no","whatItIs":"A scenario of notify.","group":"the fleet tool","askedBy":"orc-a"}', $utf8)
$added = Invoke-Decisions @("add", "-File", $qFile)
$words = "copper lantern: yes, ring it"
$said = Invoke-Decisions @("answer", "1", "-Text", $words)
Check ($added.code -eq 0 -and $said.code -eq 0) "question 1 is asked and the founder's answer under it is written, at the command line"

$open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Hidden", "-Report", $report) -Env $childEnv
$up = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 120 -Until { param($r) $null -ne $r.notify -and "$($r.notify.said)" -like "pending:*" -and $r.handle -ne 0 }
Check ($null -ne $up -and $up.notify.started -eq $true -and $up.notify.running -eq $true) ("the window's report says notify started beside it and is running (" + $(if ($null -ne $up) { ConvertTo-Json -InputObject $up.notify -Compress } else { "no report" }) + ")")
Check ($null -ne $up -and "$($up.notify.said)" -like "pending: no messenger on this machine can deliver to a session*1 answer, on question 1, stays untold*") "and what it says: pending, because no messenger here can deliver to a session - said plainly"
Check ($null -ne $up -and -not "$($up.notify.said)".Contains("copper lantern")) "CONTROL beside it: the founder's words, which are in the store, are not in what notify says"

Write-Host ""
Write-Host "=== the window closes, and notify with it ===" -ForegroundColor Cyan
$closed = Close-HordeProbeWindow -Process $open.process -Handle ([long]$up.handle) -Seconds 90
$out = "" + $open.out.Result
Check ($closed.asked -and $closed.exited -and -not $closed.killed -and $closed.code -eq 0) ("asked to close, the command ended by itself with exit 0 (" + (ConvertTo-Json -InputObject $closed -Compress) + ")")
Check ($out -like "*The decisions window was closed.*Notify, which stood beside it: stopped: 1 answer(s) left untold; they ring at the next start*") ("and it says what notify last said: stopped, with the answer left for the next start (" + ($out.Trim() -replace "\r?\n", " / ") + ")")
$last = Read-HordeProbeReport -Path $report
Check ($null -ne $last -and $last.notify.running -eq $false) "its last report says notify is no longer running"

Write-Host ""
Write-Host "=== notify -Once: the home is free, nothing is lost, nothing was claimed ===" -ForegroundColor Cyan
$once = Invoke-Decisions @("notify", "-Once")
Check ($once.code -eq 0 -and $once.out -notlike "*not run*" -and $once.out -like "*pending: no messenger on this machine can deliver to a session*") ("no notify holds the home any more, and the answer is still pending (" + $once.out.Trim() + ")")
Check (-not (Test-Path -LiteralPath (Join-Path $hordeHome "decisions\notify-told.json"))) "nothing was recorded as told"
$inbox = Invoke-Decisions @("inbox", "-Peek")
Check ($inbox.code -eq 0 -and $inbox.out.Contains($words)) "and the answer still waits unread, in the founder's words"

} finally {
    if ($null -ne $open -and -not $open.process.HasExited) { try { $open.process.Kill() } catch { } }
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-notify-e2e-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store under the user profile is exactly as it was before the scenario"

Complete-HordeSuite -Success "open starts notify beside the window and stops it on close; notify says plainly what it could not send, and loses nothing"
