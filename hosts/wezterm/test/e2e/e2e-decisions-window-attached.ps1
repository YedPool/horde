# END TO END: `horde decisions open` standing beside a WezTerm window - against a terminal this
# scenario starts, never the one in use.
#
# THE COMPOSITION, through the real command run as its own process: the fleet's record of who holds
# the role -> that session verified running -> its pane and instance -> this terminal's own listing ->
# one native window -> a Horde window owned by it, placed beside it, following it, hidden with it,
# and standing free when it is gone. Each link has its own proof elsewhere - the finder alone in
# e2e-session-window.ps1 beside this file, the follower alone in test/test-window-follow.ps1, the
# page in test/e2e/e2e-decisions-window.ps1 - and none of those is repeated here: this scenario
# proves they hold TOGETHER, in the shipped command.
#
# ISOLATION (CONTRIBUTING 3). The terminal is an instance of its own (Isolation.ps1: its own gui
# process and mux, --skip-config, the socket pin, --no-auto-start), and nothing is done before
# Assert-HordeIsolated has measured that this process can see only that instance's panes. The one
# window this scenario moves, minimises and restores is that instance's OWN window, found from the
# process the harness started. Every running gui's pid is listed before and after, and the list must
# be the same: the terminal in use is never listed to, moved or ended.
#
# THE COMMAND READS NOTHING OF THIS MACHINE'S FLEET. It is started with a home, a fleet registry and
# a user profile that are folders of this scenario's: the registry holds one record naming the
# instance's pane; the profile holds the one control file that says that record's session is running
# (as the terminal's own gui process, which this scenario started); and the home's settings tell the
# finder where this instance keeps its socket, since the profile it would look under is not the real
# one. THIS PROCESS loads the isolation harness and therefore not core/SessionSeat.ps1 (each has a
# reader of the process table by one name): the command is driven as a child and never called here.
#
# WHAT A PERSON AT THIS MACHINE MAY SEE: nothing in front of them. The test terminal's window is put
# where no screen is the moment it exists, without the keyboard, and the Horde window stands beside
# it there. The terminal has a taskbar button while it lives; the Horde window has one from the
# moment it stands free until it is closed. No window is ever activated, and the scenario checks at
# each step that the Horde window is not the foreground window.
#
# NOT PROVED HERE: closing the terminal WINDOW while its process lives on (the follower's own suite
# does that against a plain window); a second screen or a second scale; a window that is on screen.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
$work = Join-Path $env:TEMP ("horde-e2e-attached-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$hordeHome = Join-Path $work "home"
# This process's own home too: the settings it reads to work out where the window should stand are
# the defaults the command reads, whatever the person at this machine has set.
$env:HORDE_HOME = $hordeHome
. (Join-Path (Split-Path -Parent $here) "Isolation.ps1")
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "hosts\wezterm\Window.ps1")
. (Join-Path $root "test\lib\WindowProbe.ps1")

$fails = @()
function Check { param($Cond, [string]$What)
    if ($Cond -is [bool] -and $Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }
function Wait-Until { param([scriptblock]$Cond, [int]$Seconds) $d = (Get-Date).AddSeconds($Seconds); while ((Get-Date) -lt $d) { if (& $Cond) { return $true }; Start-Sleep -Milliseconds 200 }; return [bool](& $Cond) }
$followSettings = (Get-HordeWindowFollowSettings -HordeHome $hordeHome).values
function Get-Expected {
    # Where the port's own pure rule stands a companion beside the terminal window as it is now.
    param([long]$Terminal)
    $r = Get-HordeWindowFollowRectangle -Handle $Terminal
    if ($r.state -cne "known") { return $null }
    $at = Get-HordeWindowFollowPlacement -Target $r.value -Scale $r.value.scale -Settings $followSettings
    if ($at.state -cne "known") { return $null }
    return $at.value
}
function Test-Beside { param([long]$Window, [long]$Terminal) $w = Get-HordeProbeWindow -Handle $Window; $e = Get-Expected $Terminal; return [bool]($null -ne $e -and $w.left -eq $e.left -and $w.top -eq $e.top -and ($w.right - $w.left) -eq $e.width -and ($w.bottom - $w.top) -eq $e.height) }
function Show-Rect { param([long]$H) $r = Get-HordeProbeWindow -Handle $H; return ("" + $r.left + "," + $r.top + " " + ($r.right - $r.left) + "x" + ($r.bottom - $r.top)) }
function Get-Foreground { return [HordeProbe.Native]::GetForegroundWindow().ToInt64() }
# SetWindowPos flags: no size, no move, no order change, no activation.
$noSize = 0x0001; $noMove = 0x0002; $noOrder = 0x0004; $noActivate = 0x0010

$guisBefore = (@(Get-HordeWeztermGuiPids | Sort-Object) -join ",")
Write-Host ("  the gui processes running before this scenario: " + $guisBefore) -ForegroundColor DarkGray
Check ($script:HordeProbeRealScale.realScale -ceq "yes") ("this process reads windows in real pixels, asked through the follow port (" + $script:HordeProbeRealScale.state + ")")
$open = $null
$report = Join-Path $work "report.json"

$iso = Start-HordeIsolatedWezterm -TimeoutSeconds 45
Check ($null -ne $iso) "an isolated instance started and answered"
if ($iso) {
    $result = $null
    try {
        $count = Assert-HordeIsolated -Instance $iso
        Check ($count -ge 1) ("THE CONTROL: this process can see only the isolated instance's panes (" + $count + ")")
        Check (@($guisBefore -split "," | Where-Object { $_ -ne "" }) -notcontains ("" + $iso.pid)) "the instance's gui is a process that was not running before"
        $instance = Split-Path -Leaf $iso.socket
        $panes = @(ConvertFrom-HordeWeztermJson (Invoke-HordeWeztermCli -Rest @("list", "--format", "json")))
        $paneOne = "" + $panes[0].pane_id
        Check ((Wait-Until { @(Get-HordeWeztermNativeWindows -ProcessId $iso.pid).Count -eq 1 } 20)) "the instance has one window"
        $terminal = [long]@(Get-HordeWeztermNativeWindows -ProcessId $iso.pid)[0].handle
        # The instance's own window: where no screen is, at a size of this scenario's, without the keyboard.
        [void][HordeProbe.Native]::SetWindowPos([IntPtr]$terminal, [IntPtr]::Zero, -31000, -31000, 1040, 600, ($noOrder -bor $noActivate))
        [void][HordeProbe.Native]::ShowWindow([IntPtr]$terminal, 4)                                             # SW_SHOWNOACTIVATE
        Check ((Wait-Until { $t = Get-HordeProbeWindow -Handle $terminal; ($t.left -eq -31000 -and ($t.right - $t.left) -eq 1040) } 10)) ("the test terminal's window stands where no screen is (" + (Show-Rect $terminal) + ")")

        Write-Host ""
        Write-Host "--- 1. the fleet's records, as the command will read them ---" -ForegroundColor Cyan
        $sessionId = "aaaaaaaa-0000-4000-8000-0000000000e2"
        $stand = Join-Path $work "profile"
        $started = New-HordeProbeRunningSession -Profile $stand -SessionId $sessionId -ProcessId $iso.pid
        [void](New-HordeProbeRegistry -Root (Join-Path $work "fleet") -Records @(@{ id = $sessionId; role = "master"; pane = $paneOne; instance = $instance; lastSeen = [datetime]::UtcNow.ToString("o") }))
        New-Item -ItemType Directory -Path (Join-Path $hordeHome "settings") -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $hordeHome "settings\wezterm-window.json"), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = 1; settings = [ordered]@{ socketFolder = (Split-Path -Parent $iso.socket) } }) -Compress))
        Check ($started -lt [datetime]::UtcNow) ("one record names pane " + $paneOne + " of " + $instance + " as the role's seat, written after the process that its control file says runs the session was started")

        Write-Host ""
        Write-Host "--- 2. horde decisions open finds that window, is owned by it and stands beside it ---" -ForegroundColor Cyan
        $foregroundBefore = Get-Foreground
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Report", $report) -Env @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $work "fleet"); USERPROFILE = $stand; PSModulePath = $null }
        $r = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 120 -Until { param($x) $null -ne $x.drawn -and $x.handle -gt 0 -and ($x.attachment.attached -eq $false -or $null -ne $x.attachment.placed) }
        Check ($null -ne $r -and $r.attachment.attached -eq $true -and $r.attachment.target -eq $terminal) ("FOUND: the window is attached to the instance's window, the one showing the pane the record names (" + [Math]::Round($clock.Elapsed.TotalSeconds, 1) + " s after the command was started)" + $(if ($null -ne $r -and -not $r.attachment.attached) { " - NOT ATTACHED: " + $r.attachment.reason } elseif ($null -eq $r) { " - no report; the command said: " + $(if ($open.process.HasExited) { $open.out.Result + " " + $open.err.Result } else { "(still running)" }) } else { "" }))
        if ($null -ne $r -and $r.attachment.attached) {
            $window = [long]$r.handle
            $seen = Get-HordeProbeWindow -Handle $window
            Check ($seen.exists -and $seen.visible -and $seen.processId -eq $open.process.Id) "the Horde window exists, is shown, and belongs to the command's process"
            Check ($seen.owner -eq $terminal -and $r.attachment.follow -ceq "following") "OWNED: the terminal window is its owner, and the follow port says it is following"
            Check ((Wait-Until { Test-Beside $window $terminal } 5)) ("PLACED: it stands where the port's own rule puts a companion of that window, in real pixels (terminal " + (Show-Rect $terminal) + ", window " + (Show-Rect $window) + ")")
            $e = Get-Expected $terminal
            Check ($r.attachment.placed.left -eq $e.left -and $r.attachment.placed.top -eq $e.top -and $r.attachment.placed.width -eq $e.width -and $r.attachment.placed.height -eq $e.height) "and the report says the same place"
            Check (-not $seen.foreground -and (Get-Foreground) -eq $foregroundBefore) "it was shown without taking the keyboard: the foreground window is the one it was before"
            Check ($r.drawn.notice -ceq "" -and $r.refused -eq 0 -and @($r.errors).Count -eq 0 -and @($r.findings).Count -eq 0) "its page says nothing of standing free, nothing was refused, nothing failed, and no setting was faulted"

            Write-Host ""
            Write-Host "--- 3. it follows, hides and returns ---" -ForegroundColor Cyan
            [void][HordeProbe.Native]::SetWindowPos([IntPtr]$terminal, [IntPtr]::Zero, -30800, -30900, 0, 0, ($noSize -bor $noOrder -bor $noActivate))
            Check ((Wait-Until { (Get-HordeProbeWindow -Handle $terminal).left -eq -30800 -and (Test-Beside $window $terminal) } 6)) ("FOLLOWS: the terminal window moved, and the Horde window moved with it (" + (Show-Rect $window) + ")")
            [void][HordeProbe.Native]::SetWindowPos([IntPtr]$terminal, [IntPtr]::Zero, 0, 0, 1240, 660, ($noMove -bor $noOrder -bor $noActivate))
            Check ((Wait-Until { $t = Get-HordeProbeWindow -Handle $terminal; (($t.right - $t.left) -eq 1240 -and (Test-Beside $window $terminal)) } 6)) ("the terminal window was resized, and the Horde window was placed again for its new size (" + (Show-Rect $window) + ")")
            [void][HordeProbe.Native]::ShowWindow([IntPtr]$terminal, 7)                                          # SW_SHOWMINNOACTIVE
            Check ((Wait-Until { -not (Get-HordeProbeWindow -Handle $window).visible } 6)) "HIDDEN ON MINIMISE: the terminal window was minimised, and the Horde window is hidden with it"
            [void][HordeProbe.Native]::ShowWindow([IntPtr]$terminal, 4)                                          # SW_SHOWNOACTIVATE
            Check ((Wait-Until { (Get-HordeProbeWindow -Handle $window).visible -and (Test-Beside $window $terminal) } 6)) "the terminal window was restored, and the Horde window is back, in its place"
            Check ((Get-Foreground) -ne $window) "through all of it the Horde window never became the foreground window"
            $follow = Read-HordeProbeReport -Path $report
            Check ($follow.attachment.attached -eq $true -and @($follow.errors).Count -eq 0 -and $follow.refused -eq 0) "it still says it is attached, and nothing failed inside the window"
        }
    }
    catch { Check $false ("the scenario stopped: " + $_.Exception.Message) }
    finally {
        # Teardown runs whatever happened above. A teardown that only runs on success is the leak.
        $result = Stop-HordeIsolatedWezterm -Instance $iso
    }
    Check (-not $result.refused) "teardown accepted the instance Start issued"
    Check ($result.stopped -and -not $result.survived -and @($result.orphansSurvived).Count -eq 0) "the terminal and everything that ran in it are gone"

    Write-Host ""
    Write-Host "--- 4. the terminal is gone: the Horde window stands free, in the taskbar, and says so ---" -ForegroundColor Cyan
    if ($null -ne $open) {
        $lost = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 30 -Until { param($x) $x.attachment.attached -eq $false -and $null -ne $x.drawn -and "$($x.drawn.notice)" -ne "" }
        Check ($null -ne $lost -and $lost.attachment.attached -eq $false -and $lost.attachment.reason -ceq "the terminal window it stood beside is gone, and it stands free where it was" -and $lost.attachment.follow -ceq "lost") "LOST: within moments the window reports that the terminal window is gone, in words, and the follow port says lost"
        if ($null -ne $lost) {
            $free = Get-HordeProbeWindow -Handle ([long]$lost.handle)
            Check (-not $open.process.HasExited -and $free.exists -and $free.visible) "it is still there and still shown: a terminal that ends does not take the list away"
            Check ($free.owner -eq 0) "STANDING FREE IN THE TASKBAR: it is owned by nothing now, so Windows gives it a taskbar button"
            Check (-not $free.foreground -and (Get-Foreground) -ne [long]$lost.handle) "NEVER THE FOREGROUND WINDOW: becoming free did not give it the keyboard"
            Check ($lost.drawn.notice -ceq "Standing free: the terminal window it stood beside is gone, and it stands free where it was") "and its page says so to the reader"
            $closed = Close-HordeProbeWindow -Process $open.process -Handle ([long]$lost.handle) -Seconds 40
            Check ($closed.asked -and $closed.exited -and -not $closed.killed -and $closed.code -eq 0) ("asked to close, the command ends by itself and exits 0 (" + $closed.code + ")")
            Check ($open.out.Result -like "*Opening the decisions window beside the warchief's terminal window.*" -and $open.out.Result -like "*The decisions window was closed.*" -and $open.err.Result.Trim() -ceq "") "it said that it opened beside the terminal window, and that it was closed; nothing on the error stream"
        }
    }
}
if ($null -ne $open -and -not $open.process.HasExited) { try { $open.process.Kill() } catch { } }
Start-Sleep -Milliseconds 800
$guisAfter = (@(Get-HordeWeztermGuiPids | Sort-Object) -join ",")
Check ($guisAfter -ceq $guisBefore) ("the gui processes running are exactly those running before: " + $guisAfter)
for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $work); $i++) { try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 } }
Check (-not (Test-Path -LiteralPath $work)) "the scenario's folder - its home, registry and profile - is removed"

Write-Host ""
if ($fails.Count -gt 0) { Write-Host ("==== " + $fails.Count + " FAILURE(S) ====") -ForegroundColor Red; foreach ($f in $fails) { Write-Host ("  - " + $f) -ForegroundColor Red }; exit 1 }
Write-Host "==== horde decisions open stands beside the terminal window the fleet's records and the terminal's own listing prove, follows it, and stands free when it is gone ====" -ForegroundColor Green
exit 0
