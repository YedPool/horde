# END TO END: a Horde window standing beside a WezTerm window - against a terminal this scenario
# starts, never the one in use.
#
# The finder half of the WezTerm host (hosts/wezterm/Window.ps1) and, through the real command
# `horde decisions open`, the whole chain it serves: the fleet's record of who holds the role -> that
# session's pane and instance -> this terminal's own listing -> one native window -> a Horde window
# owned by it, placed beside it, following it.
#
# ISOLATION (CONTRIBUTING 3). The terminal is an instance of its own (Isolation.ps1: its own gui
# process and mux, --skip-config, the socket pin, --no-auto-start), and nothing is done before
# Assert-HordeIsolated has measured that this process can see only that instance's panes. The windows
# this scenario moves, minimises and restores are that instance's OWN windows, found from the process
# the harness started; the second window is spawned in that instance. The fleet's registry is a folder
# this scenario made, naming that instance. Every running gui's pid is listed before and after, and
# the list must be the same: the terminal in use is never listed to, moved or ended.
#
# A WINDOW MAY SHOW BRIEFLY on the screen of whoever sits at this machine: the test terminal's, small,
# and the Horde window beside it. Neither is ever given the keyboard, and the scenario checks that the
# Horde window is not the foreground window at any step.
#
# WHAT IT PROVES, in order:
#   1. one window: the finder names the instance's one window, from the real listing.
#   2. two windows: with a second window spawned in the instance, each pane's window is told from the
#      other by its own title, from the same listing - the case the running fleet is in (16 windows in
#      one gui process, measured 2026-10-06).
#   3. `horde decisions open` stands beside the window of the pane the registry names: owned by it,
#      at the place platform/windows/WindowFollow.ps1 works out, in real pixels.
#   4. it follows a move and a resize, is hidden while the terminal window is minimised, and is back
#      in place when it is restored.
#   5. when the terminal ends, the Horde window says it is no longer attached, and closes when asked.
#
# NOT PROVED HERE: closing the terminal WINDOW while its process lives on (the test terminal asks
# before it closes a window); a second screen or a second scale; a terminal that titles its windows
# its own way.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
. (Join-Path (Split-Path -Parent $here) "Isolation.ps1")
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "hosts\wezterm\Window.ps1")
. (Join-Path $root "platform\windows\WindowFollow.ps1")
. (Join-Path $root "test\lib\WindowProbe.ps1")

$fails = @()
function Check { param($Cond, [string]$What)
    if ($Cond -is [bool] -and $Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }
function Wait-Until { param([scriptblock]$Cond, [int]$Seconds) $d = (Get-Date).AddSeconds($Seconds); while ((Get-Date) -lt $d) { if (& $Cond) { return $true }; Start-Sleep -Milliseconds 200 }; return [bool](& $Cond) }
function Get-Expected { param([long]$Terminal) $r = Get-HordeProbeWindow -Handle $Terminal; return (Get-HordeWindowFollowPlacement -Target ([pscustomobject]@{ left = $r.left; top = $r.top; right = $r.right; bottom = $r.bottom }) -Dpi $r.dpi) }
function Test-Beside { param([long]$Window, [long]$Terminal) $w = Get-HordeProbeWindow -Handle $Window; $e = Get-Expected $Terminal; return [bool]($w.left -eq $e.left -and $w.top -eq $e.top -and ($w.right - $w.left) -eq $e.width -and ($w.bottom - $w.top) -eq $e.height) }
function Show-Rect { param([long]$H) $r = Get-HordeProbeWindow -Handle $H; return ("" + $r.left + "," + $r.top + " " + ($r.right - $r.left) + "x" + ($r.bottom - $r.top)) }

$work = Join-Path $env:TEMP ("horde-e2e-window-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$guisBefore = (@(Get-HordeWeztermGuiPids | Sort-Object) -join ",")
Write-Host ("  the gui processes running before this scenario: " + $guisBefore) -ForegroundColor DarkGray
$open = $null

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
        $gui = Get-Process -Id $iso.pid
        Check ((Wait-Until { $gui.Refresh(); $gui.MainWindowHandle -ne [IntPtr]::Zero } 20)) "the instance has a window"
        $terminal = $gui.MainWindowHandle.ToInt64()
        # The instance's own window: shown small, without the keyboard, where it is out of the way.
        [void][HordeProbe.Native]::ShowWindow([IntPtr]$terminal, 4)                                             # SW_SHOWNOACTIVATE
        [void][HordeProbe.Native]::SetWindowPos([IntPtr]$terminal, [IntPtr]::Zero, 40, 40, 1040, 600, 0x0004 -bor 0x0010)   # no order change, no activation
        Start-Sleep -Milliseconds 500

        Write-Host ""
        Write-Host "--- 1. one window ---" -ForegroundColor Cyan
        $one = Find-HordeWeztermSessionWindow -Pane $paneOne -Instance $instance
        Check ($one.state -ceq "known" -and $one.value.handle -eq $terminal) ("pane " + $paneOne + " of " + $instance + " is shown in the instance's one window, by the real listing" + $(if ($one.state -cne "known") { " (" + $one.reason + ")" } else { "" }))
        Check ($one.state -ceq "known" -and $one.value.detail -ceq "the terminal has one window") "and the finder says there was nothing to tell apart"
        Check ((Find-HordeWeztermSessionWindow -Pane "987" -Instance $instance).reason -like "the terminal lists no pane 987*") "a pane this instance does not have: unknown, from the real listing"
        Check ((Find-HordeWeztermSessionWindow -Pane $paneOne -Instance "gui-sock-1").state -ceq "unknown") "an instance that is not running: unknown, and nothing is asked of any terminal"

        Write-Host ""
        Write-Host "--- 2. two windows, told apart by their own titles ---" -ForegroundColor Cyan
        # ANOTHER PROGRAM, so that the two windows are titled differently: a pane is titled after what runs
        # in it. Measured 2026-10-06 with a second cmd.exe instead: both windows were titled "cmd.exe", and
        # the finder answered unknown for each pane - "2 of the terminal's windows are titled as the
        # window of pane 0 would be, and one is never chosen over another" - which is the right answer.
        $spawned = "" + (Invoke-HordeWeztermCli -Rest @("spawn", "--new-window", "--", "ping.exe", "-n", "300", "127.0.0.1"))
        $paneTwo = $spawned.Trim()
        Check ($paneTwo -cmatch '\A[0-9]+\z' -and $paneTwo -cne $paneOne) ("a second window was spawned in the instance (pane " + $paneTwo + ")")
        $twoWindows = Wait-Until { @(Get-HordeWeztermNativeWindows -ProcessId $iso.pid).Count -eq 2 } 20
        Check $twoWindows "the instance's gui process now has two terminal windows"
        $second = [long]0
        foreach ($w in @(Get-HordeWeztermNativeWindows -ProcessId $iso.pid)) { if ($w.handle -ne $terminal) { $second = $w.handle } }
        if ($second -ne 0) { [void][HordeProbe.Native]::ShowWindow([IntPtr]$second, 7) }                         # SW_SHOWMINNOACTIVE: out of the way
        $script:a = $null; $script:b = $null
        $told = Wait-Until { $script:a = Find-HordeWeztermSessionWindow -Pane $paneOne -Instance $instance; $script:b = Find-HordeWeztermSessionWindow -Pane $paneTwo -Instance $instance; ($script:a.state -ceq "known" -and $script:b.state -ceq "known") } 20
        Write-Host ("  the two windows are titled: " + ((@(Get-HordeWeztermNativeWindows -ProcessId $iso.pid) | ForEach-Object { "[" + $_.title + "]" }) -join " and ")) -ForegroundColor DarkGray
        Check $told ("each pane's window is known" + $(if (-not $told) { " (" + $script:a.reason + " / " + $script:b.reason + ")" } else { "" }))
        Check ($told -and $script:a.value.handle -eq $terminal -and $script:b.value.handle -eq $second -and $second -ne 0) "the first pane is in the first window and the second pane in the second: neither is taken for the other"
        Check ($told -and $script:a.value.detail -ceq "the one of the terminal's 2 windows titled after its panes") "and they were told apart by title, from the listing"

        Write-Host ""
        Write-Host "--- 3. horde decisions open stands beside the window of the pane the registry names ---" -ForegroundColor Cyan
        $sessionId = "aaaaaaaa-0000-4000-8000-0000000000e2"
        [void](New-HordeProbeRegistry -Root (Join-Path $work "fleet") -Records @(@{ id = $sessionId; role = "master"; pane = $paneOne; instance = $instance }))
        $report = Join-Path $work "report.json"
        $foregroundBefore = [HordeProbe.Native]::GetForegroundWindow().ToInt64()
        $open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Report", $report) -Env @{ HORDE_HOME = (Join-Path $work "home"); WEZFLEET_ROOT = (Join-Path $work "fleet"); PSModulePath = $null }
        $r = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 120 -Until { param($x) $null -ne $x.rendered -and $x.handle -gt 0 -and $null -ne $x.attachment.placed }
        Check ($null -ne $r -and $r.attachment.attached -eq $true -and $r.attachment.target -eq $terminal) ("the window is attached to the first window, the one showing the registry's pane" + $(if ($null -ne $r -and -not $r.attachment.attached) { " (not attached: " + $r.attachment.reason + ")" } else { "" }))
        if ($null -ne $r -and $r.attachment.attached) {
            $window = [long]$r.handle
            $seen = Get-HordeProbeWindow -Handle $window
            Check ($seen.exists -and $seen.visible -and $seen.processId -eq $open.process.Id) "the Horde window exists, is shown, and belongs to the command's process"
            Check ($seen.owner -eq $terminal) "the terminal window is its owner: Windows keeps it above that window and hides it with it"
            Check ((Wait-Until { Test-Beside $window $terminal } 5)) ("it stands at the place worked out from the terminal window's rectangle, in real pixels (terminal " + (Show-Rect $terminal) + ", window " + (Show-Rect $window) + ", scale " + $seen.dpi + ")")
            $e = Get-Expected $terminal
            Check ($r.attachment.placed.left -eq $e.left -and $r.attachment.placed.width -eq $e.width) "and the report says the same place"
            Check (-not $seen.foreground -and [HordeProbe.Native]::GetForegroundWindow().ToInt64() -ne $window) "it was shown without taking the keyboard"
            Check ([HordeProbe.Native]::GetForegroundWindow().ToInt64() -eq $foregroundBefore -or [HordeProbe.Native]::GetForegroundWindow().ToInt64() -ne $window) "whatever had the keyboard before, the Horde window does not have it now"

            Write-Host ""
            Write-Host "--- 4. it follows, hides and returns ---" -ForegroundColor Cyan
            [void][HordeProbe.Native]::SetWindowPos([IntPtr]$terminal, [IntPtr]::Zero, 150, 110, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010)   # move only
            Check ((Wait-Until { (Get-HordeProbeWindow -Handle $terminal).left -eq 150 -and (Test-Beside $window $terminal) } 6)) ("the terminal window moved, and the Horde window moved with it (" + (Show-Rect $window) + ")")
            [void][HordeProbe.Native]::SetWindowPos([IntPtr]$terminal, [IntPtr]::Zero, 0, 0, 1240, 660, 0x0002 -bor 0x0004 -bor 0x0010)  # size only
            Check ((Wait-Until { ((Get-HordeProbeWindow -Handle $terminal).right - (Get-HordeProbeWindow -Handle $terminal).left) -eq 1240 -and (Test-Beside $window $terminal) } 6)) ("the terminal window was resized, and the Horde window was placed again for its new size (" + (Show-Rect $window) + ")")
            [void][HordeProbe.Native]::ShowWindow([IntPtr]$terminal, 7)                                          # SW_SHOWMINNOACTIVE
            Check ((Wait-Until { -not (Get-HordeProbeWindow -Handle $window).visible } 6)) "the terminal window was minimised, and the Horde window is hidden with it"
            [void][HordeProbe.Native]::ShowWindow([IntPtr]$terminal, 4)                                          # SW_SHOWNOACTIVATE
            Check ((Wait-Until { (Get-HordeProbeWindow -Handle $window).visible -and (Test-Beside $window $terminal) } 6)) "the terminal window was restored, and the Horde window is back, in its place"
            Check ([HordeProbe.Native]::GetForegroundWindow().ToInt64() -ne $window) "through all of it the Horde window never took the keyboard"
            $follow = Read-HordeProbeReport -Path $report
            Check (@($follow.errors).Count -eq 0 -and $follow.refused -eq 0) "and nothing failed inside the window, nor was anything refused"
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
    Write-Host "--- 5. the terminal is gone: the Horde window says so, and closes when asked ---" -ForegroundColor Cyan
    if ($null -ne $open) {
        $report = Join-Path $work "report.json"
        $lost = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 20 -Until { param($x) $x.attachment.attached -eq $false }
        Check ($null -ne $lost -and $lost.attachment.attached -eq $false -and $lost.attachment.reason -ceq "the terminal window it stood beside has been closed") "within moments the window reports that it is no longer attached, and why"
        Check (-not $open.process.HasExited -and (Get-HordeProbeWindow -Handle ([long]$lost.handle)).exists) "it is still there, standing free: a terminal that ends does not take the list away"
        $closed = Close-HordeProbeWindow -Process $open.process -Handle ([long]$lost.handle) -Seconds 40
        Check ($closed.asked -and $closed.exited -and -not $closed.killed -and $closed.code -eq 0) ("asked to close, the command ends by itself and exits 0 (" + $closed.code + ")")
        Check ($open.out.Result -like "*Opening the decisions window beside the warchief's terminal window.*" -and $open.out.Result -like "*The decisions window was closed.*") "it said that it opened beside the terminal window, and that it was closed"
    }
}
if ($null -ne $open -and -not $open.process.HasExited) { try { $open.process.Kill() } catch { } }
Start-Sleep -Milliseconds 800
$guisAfter = (@(Get-HordeWeztermGuiPids | Sort-Object) -join ",")
Check ($guisAfter -ceq $guisBefore) ("the gui processes running are exactly those running before: " + $guisAfter)
for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $work); $i++) { try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 } }

Write-Host ""
if ($fails.Count -gt 0) { Write-Host ("==== " + $fails.Count + " FAILURE(S) ====") -ForegroundColor Red; foreach ($f in $fails) { Write-Host ("  - " + $f) -ForegroundColor Red }; exit 1 }
Write-Host "==== a Horde window stands beside the terminal window its own listing proves, follows it, and never takes the keyboard ====" -ForegroundColor Green
exit 0
