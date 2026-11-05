# DOES THE RESTART RETRY RUN THE NIGHTLY NET ONCE, AND ONLY WHEN IT SHOULD? T-0397.
#
# On 2026-11-04 a restart at 23:02 killed the net 57 minutes in and nothing ran it again. tools/nightly/NightlyRetry.ps1
# (a logon task) decides from evidence on disk, in core Get-HordeNightlyRetryDecision, and runs the net at most once a
# night. The first half drives the pure decision (every condition); the second drives the REAL script with a temp work
# folder and a stand-in net script, never the real net and never the scheduler.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\NightlyNet.ps1")

function G { param($Obj, [string]$Path) return (Get-HordeTestMember -Object $Obj -Path $Path) }
function Dec { param([string]$At, [string[]]$Names = @(), [bool]$Marker = $false, [bool]$Alive = $false, [int]$Min = 180)
    return (Get-HordeNightlyRetryDecision -Now ([datetime]$At) -ReportNames $Names -MarkerExists $Marker -NetAlive $Alive -MinMinutes $Min)
}

Write-Host ""
Write-Host "--- the decision: every condition ---" -ForegroundColor Cyan
$d = Dec "2026-11-04 23:30"
Check ((G $d "run") -eq $true -and (G $d "condition") -ceq "run" -and (G $d "night") -ceq "2026-11-04") "a night in its window, no report, no marker, no net running: run"
$d = Dec "2026-11-05 01:00"
Check ((G $d "run") -eq $true -and (G $d "night") -ceq "2026-11-04") "at 01:00 the night is still yesterday's date"
foreach ($t in @("2026-11-04 21:59", "2026-11-04 14:00", "2026-11-05 06:30", "2026-11-05 12:00")) {
    $d = Dec $t
    Check ((G $d "run") -eq $false -and (G $d "condition") -ceq "outside the night window") ("outside the window at " + $t + ": no retry")
}
$d = Dec "2026-11-05 03:15:00"
Check ((G $d "run") -eq $true -and (G $d "minutesLeft") -eq 180) "exactly 180 minutes before the 06:15 cutoff still runs"
$d = Dec "2026-11-05 03:15:01"
Check ((G $d "run") -eq $false -and (G $d "condition") -ceq "too little time") "a second less does not"
$d = Dec "2026-11-05 05:00"
Check ((G $d "run") -eq $false -and (G $d "condition") -ceq "too little time") "05:00 is too late"
$d = Dec "2026-11-05 05:00" -Min 60
Check ((G $d "run") -eq $true) "and the limit is a parameter"
$d = Dec "2026-11-04 23:30" -Names @("2026-11-04.txt")
Check ((G $d "run") -eq $false -and (G $d "condition") -ceq "report exists") "a report for the night: no retry"
$d = Dec "2026-11-04 23:30" -Names @("2026-11-04.TXT")
Check ((G $d "condition") -ceq "report exists") "the file name is compared without case"
$d = Dec "2026-11-04 23:30" -Names @("2026-11-03.txt", "2026-11-03-FAILED.txt")
Check ((G $d "run") -eq $true) "the reports of other nights do not count"
foreach ($f in @("2026-11-04-FAILED.txt", "2026-11-04-BUSY.txt", "2026-11-04-REFUSED.txt")) {
    $d = Dec "2026-11-04 23:30" -Names @($f)
    Check ((G $d "run") -eq $false -and (G $d "condition") -ceq "final report exists") ($f + " is a final report: no retry")
}
$d = Dec "2026-11-04 23:30" -Marker $true
Check ((G $d "run") -eq $false -and (G $d "condition") -ceq "already retried") "a marker for the night: no retry"
$d = Dec "2026-11-04 23:30" -Alive $true
Check ((G $d "run") -eq $false -and (G $d "condition") -ceq "net is running") "the net's lock held: no retry"
$d = Dec "2026-11-04 23:30" -Names @("2026-11-04.txt") -Marker $true -Alive $true
Check ((G $d "condition") -ceq "report exists") "with several conditions the first decides, and it is named"
$d = Dec "2026-11-04 23:30" -Marker $true -Alive $true
Check ((G $d "condition") -ceq "already retried") "a marker is named before a running net"
$d = Dec "2027-03-14 03:30"
Check ((G $d "night") -ceq "2027-03-13" -and (G $d "run") -eq $false) "spring-forward morning: 03:30 belongs to night 03-13, with 165 minutes left, too little"

Write-Host ""
Write-Host "--- the watcher: a retried night ---" -ForegroundColor Cyan
$retryLog = "2026-11-04T22:00:02 nightly net 2026-11-04: window open, cutoff 2026-11-05T06:15:00, repos a`n2026-11-04T22:57:17 order: a`n2026-11-04T23:06:00 nightly retry 2026-11-04: the net is run once more after a restart`n2026-11-04T23:06:05 nightly net 2026-11-04: window open, cutoff 2026-11-05T06:15:00, repos a`n2026-11-05T05:00:00 report written: x`n2026-11-05T05:00:30 report sent to M (exit 0)"
$v = Get-HordeNightlyWatchVerdict -Date "2026-11-04" -LogText $retryLog -ReportNames @("2026-11-04.txt")
Check ((G $v "status") -ceq "RAN" -and (G $v "missed") -eq $false) "a retried night that reported is RAN"
$noRep = $retryLog.Substring(0, $retryLog.IndexOf("`n2026-11-05T05:00:00"))
$v = Get-HordeNightlyWatchVerdict -Date "2026-11-04" -LogText $noRep -ReportNames @()
$empty = Read-HordeNightlyWatchState -Text ""
$m = Format-HordeNightlyWatchMessage -Decision (Get-HordeNightlyWatchDecision -Verdict $v -Streak 1 -State $empty) -Verdict $v -Lookback 14
Check ((G $v "status") -ceq "NOT REPORTED" -and (G $v "retried") -eq $true -and (G $v "detail") -like "*retry after a restart*") "a retried night that still has no report says a retry was made"
Check ((G $m "founder") -like "*A retry after the restart was made.*" -and (G $m "founder") -like "*started on the night of 2026-11-04*" -and (G $m "m") -like "*retry after a restart*") "on the phone and to M"
$v = Get-HordeNightlyWatchVerdict -Date "2026-11-04" -LogText "2026-11-04T22:00:02 nightly net 2026-11-04: window open, x" -ReportNames @()
Check ((G $v "retried") -eq $false -and (G $v "detail") -notlike "*retry*") "a night with no retry line claims none"
$v = Get-HordeNightlyWatchVerdict -Date "2026-11-04" -LogText "2026-11-03T23:06:00 nightly retry 2026-11-03: x`n2026-11-04T22:00:02 nightly net 2026-11-04: window open, x" -ReportNames @()
Check ((G $v "retried") -eq $false) "and another night's retry line is not this night's"

Write-Host ""
Write-Host "--- the real script, with a stand-in net ---" -ForegroundColor Cyan
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-retry-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$exe = (Get-Process -Id $PID).Path
$retry = Join-Path $root "tools\nightly\NightlyRetry.ps1"
try {
    $script:cnt = 0
    function New-Rig { param([int]$NetExit = 0)
        $script:cnt++
        $dir = Join-Path $work ("rig" + $script:cnt); $w = Join-Path $dir "work"; $net = Join-Path $dir "net.ps1"
        [void][System.IO.Directory]::CreateDirectory($w)
        # The stand-in net records that it ran and whether the marker already existed when it started.
        $body = "Add-Content -LiteralPath '" + (Join-Path $dir "rec.txt") + "' -Value ('NET STARTED marker=' + (Test-Path -LiteralPath '" + (Join-Path $w "retry\2026-11-04.marker") + "'))`r`nexit " + $NetExit + "`r`n"
        [System.IO.File]::WriteAllText($net, $body)
        return [pscustomobject]@{ work = $w; net = $net; rec = (Join-Path $dir "rec.txt"); marker = (Join-Path $w "retry\2026-11-04.marker"); log = (Join-Path $w "nightly.log"); rlog = (Join-Path $w "nightly-retry.log") }
    }
    function Invoke-Retry { param($Rig, [string]$At = "2026-11-04T23:30:00", [string[]]$More = @())
        $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File $retry -WorkRoot $Rig.work -AtTime $At -NetScript $Rig.net @More)
        return [pscustomobject]@{ code = $LASTEXITCODE; out = ($o -join "`n") }
    }
    function Recs { param($Rig) if (Test-Path -LiteralPath $Rig.rec) { return ,@(Get-Content -LiteralPath $Rig.rec) } else { return ,@() } }
    function RLog { param($Rig) if (Test-Path -LiteralPath $Rig.rlog) { return [System.IO.File]::ReadAllText($Rig.rlog) } else { return "" } }

    $rig = New-Rig
    $r = Invoke-Retry $rig
    Check ($r.code -eq 0 -and (Recs $rig).Count -eq 1) ("the net is started once (exit " + $r.code + ")")
    Check ((Recs $rig)[0] -ceq "NET STARTED marker=True") "and the marker was already there when the net started"
    Check ((Test-Path -LiteralPath $rig.log) -and ([System.IO.File]::ReadAllText($rig.log)) -like "*nightly retry 2026-11-04: *") "nightly.log says a retry was made, for the watcher"
    Check ((RLog $rig) -like "*night 2026-11-04: RUN, decided by: run*") "and its own log names the condition that decided"
    $r = Invoke-Retry $rig
    Check ($r.code -eq 0 -and (Recs $rig).Count -eq 1) "a second call does nothing: still one start"
    Check ((RLog $rig) -like "*no retry, decided by: already retried*") "and its log says why"
    $r = Invoke-Retry $rig -At "2026-11-04T23:50:00"
    Check ((Recs $rig).Count -eq 1) "nor a third, later that night (repeated reboots cannot loop)"

    foreach ($kind in @("garbage", "empty", "folder")) {
        $rig = New-Rig
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $rig.marker))
        if ($kind -ceq "garbage") { [System.IO.File]::WriteAllBytes($rig.marker, [byte[]](0, 255, 7, 13, 200, 0)) }
        elseif ($kind -ceq "empty") { [System.IO.File]::WriteAllBytes($rig.marker, [byte[]]@()) }
        else { [void][System.IO.Directory]::CreateDirectory($rig.marker) }
        $r = Invoke-Retry $rig
        Check ($r.code -eq 0 -and (Recs $rig).Count -eq 0 -and (RLog $rig) -like "*already retried*") ("a corrupt marker (" + $kind + ") counts as already retried: the net is not started")
    }

    $rig = New-Rig
    [void][System.IO.Directory]::CreateDirectory((Join-Path $rig.work "reports"))
    [System.IO.File]::WriteAllText((Join-Path $rig.work "reports\2026-11-04.txt"), "x")
    $r = Invoke-Retry $rig
    Check ((Recs $rig).Count -eq 0 -and -not (Test-Path -LiteralPath $rig.marker) -and (RLog $rig) -like "*decided by: report exists*") "a report for the night: no start, no marker, one line says why"
    $rig = New-Rig
    [void][System.IO.Directory]::CreateDirectory((Join-Path $rig.work "reports"))
    [System.IO.File]::WriteAllText((Join-Path $rig.work "reports\2026-11-04-BUSY.txt"), "x")
    $r = Invoke-Retry $rig
    Check ((Recs $rig).Count -eq 0 -and (RLog $rig) -like "*decided by: final report exists*") "a BUSY file is a final report: no start"
    $rig = New-Rig
    $r = Invoke-Retry $rig -At "2026-11-04T14:00:00"
    Check ($r.code -eq 0 -and (Recs $rig).Count -eq 0 -and -not (Test-Path -LiteralPath $rig.marker) -and -not (Test-Path -LiteralPath $rig.log) -and (RLog $rig) -like "*decided by: outside the night window*") "a daytime logon: exit 0, nothing started, no marker, nothing written to nightly.log"
    $rig = New-Rig
    $r = Invoke-Retry $rig -At "2026-11-05T05:00:00"
    Check ((Recs $rig).Count -eq 0 -and (RLog $rig) -like "*decided by: too little time*") "too little time before the cutoff: no start"

    $rig = New-Rig
    $mxName = "HordeRetryTest" + [guid]::NewGuid().ToString("N")
    $mx = New-Object System.Threading.Mutex($true, $mxName)
    try {
        $r = Invoke-Retry $rig -More @("-MutexName", $mxName)
        Check ((Recs $rig).Count -eq 0 -and -not (Test-Path -LiteralPath $rig.marker) -and (RLog $rig) -like "*decided by: net is running*") "the net's lock held: no start, and no marker spent"
    } finally { $mx.ReleaseMutex(); $mx.Dispose() }

    $rig = New-Rig
    [System.IO.File]::WriteAllText((Join-Path $rig.work "retry"), "a file where the marker folder should be")
    $r = Invoke-Retry $rig
    Check ($r.code -eq 0 -and (Recs $rig).Count -eq 0 -and (RLog $rig) -like "*marker could not be written, so nothing runs*") "a marker that cannot be written means nothing runs"

    $rig = New-Rig -NetExit 5
    $r = Invoke-Retry $rig
    Check ($r.code -eq 5 -and (Recs $rig).Count -eq 1) "the net's exit code is the task's result"

    $rig = New-Rig
    $r = Invoke-Retry $rig -More @("-Plan")
    Check ($r.code -eq 0 -and $r.out -like "*PLAN*RUN, decided by: run*" -and (Recs $rig).Count -eq 0 -and -not (Test-Path -LiteralPath $rig.marker) -and -not (Test-Path -LiteralPath $rig.rlog) -and -not (Test-Path -LiteralPath $rig.log)) "-Plan prints the decision and writes and starts nothing"

    Write-Host ""
    Write-Host "--- the registration, dry ---" -ForegroundColor Cyan
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\Register-NightlyRetryTask.ps1") -Plan -HordeRoot $root)
    $txt = $o -join "`n"
    Check ($LASTEXITCODE -eq 0 -and $txt -like "*dry run: nothing registered*" -and $txt -like "*task \Horde\HordeNightlyRetry*") ("-Plan registers nothing (" + $LASTEXITCODE + ") and names the separate task")
    Check ($txt -like "*trigger: at logon*" -and $txt -like "*NightlyRetry.ps1*" -and $txt -notlike "*HordeNightlyNet*") "it is a logon task running the retry script, not the net's task"
    Check ($txt -like "*PT8H30M*" -and $txt -like "*multiple instances IgnoreNew*" -and $txt -like "*start on battery, not stopped on battery*") "with the net's settings: 8 h 30 min, one instance, battery"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the restart retry runs the net once after a restart killed it: inside the window with enough time, no report, no final report, no marker (written before the start, a corrupt one counts) and no live net; otherwise it exits 0 saying which condition decided, and the watcher reads a retried night as RAN or says a retry happened"
