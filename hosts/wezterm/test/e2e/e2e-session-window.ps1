# END TO END: which native window shows a pane - against a terminal this scenario starts, never the one
# in use.
#
# The finder half of the WezTerm host (hosts/wezterm/Window.ps1), alone: the real listing, the real
# windows of a real gui process, and the answer. It needs no page, no other window and no command of
# Horde's; whatever stands a window beside the one found here has its own scenario.
#
# ISOLATION (CONTRIBUTING 3). The terminal is an instance of its own (Isolation.ps1: its own gui
# process and mux, --skip-config, the socket pin, --no-auto-start), and nothing is done before
# Assert-HordeIsolated has measured that this process can see only that instance's panes. Every pane
# and window this scenario makes is made in that instance; the only windows it touches are that
# instance's own, found from the process the harness started, and all it does to them is put them out
# of the way, minimised, without the keyboard. Every running gui's pid is listed before and after, and
# the list must be the same: the terminal in use is never listed, moved or ended.
#
# A WINDOW MAY SHOW BRIEFLY on the screen of whoever sits at this machine: each new window of the test
# terminal, until it is minimised a moment later.
#
# WHAT IT PROVES, in order:
#   1. one window: the finder names the instance's one window from the real listing, and says it held
#      on a second reading; the answer takes at least the wait between the two readings.
#   2. a pane the instance does not list, and an instance that is not running: unknown, in words.
#   3. two windows running different programs are told apart by their own titles.
#   4. THE SECOND READING, FOR REAL: a window with the same title as the session's is opened between
#      the two readings of one find. The first reading found the window; the second cannot tell it
#      from its twin; the answer is unknown and says the match did not hold.
#   5. two windows running the same program: unknown for each, and neither is chosen; the window
#      titled alone beside them is still found.
#   6. how the terminal titles a zoomed pane, with one tab and with two: the finder still finds its
#      window (the order "[Z] [1/2] title" was measured here first, 2026-10-07).
#
# NOT PROVED HERE: a terminal that titles its windows its own way; the live fleet's sixteen windows;
# a second screen.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
# A home of this scenario's own, never made: the finder's settings are their defaults here, whatever
# the person at this machine has set.
$env:HORDE_HOME = Join-Path $env:TEMP ("horde-e2e-session-window-home-" + [guid]::NewGuid().ToString("N"))
. (Join-Path (Split-Path -Parent $here) "Isolation.ps1")
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "hosts\wezterm\Window.ps1")

# All this scenario does to a window: minimise it without giving it the keyboard.
Add-Type -Namespace HordeSessionWindowScenario -Name Native -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd);'

$fails = @()
function Check { param($Cond, [string]$What)
    if ($Cond -is [bool] -and $Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }
function Wait-Until { param([scriptblock]$Cond, [int]$Seconds) $d = (Get-Date).AddSeconds($Seconds); while ((Get-Date) -lt $d) { if (& $Cond) { return $true }; Start-Sleep -Milliseconds 200 }; return [bool](& $Cond) }
function Why { param($Answer) if ($Answer.state -ceq "known") { return ("known, window " + $Answer.value.handle) }; return ("" + $Answer.state + ": " + $Answer.reason) }
function Get-Windows { return @(Get-HordeWeztermNativeWindows -ProcessId $iso.pid) }
function Hide-New {
    # Minimise, without the keyboard, every window of the instance that -Known does not hold; returns
    # the handle of the one new window, or 0 when there is not exactly one.
    param([long[]]$Known)
    $new = @(Get-Windows | Where-Object { $Known -notcontains $_.handle })
    foreach ($w in $new) { [void][HordeSessionWindowScenario.Native]::ShowWindow([IntPtr]$w.handle, 7) }     # SW_SHOWMINNOACTIVE
    if ($new.Count -eq 1) { return [long]$new[0].handle }
    return [long]0
}
function Show-Titles { Write-Host ("  the instance's windows are titled: " + ((@(Get-Windows) | ForEach-Object { "[" + $_.title + "]" }) -join " ")) -ForegroundColor DarkGray }

$guisBefore = (@(Get-HordeWeztermGuiPids | Sort-Object) -join ",")
Write-Host ("  the gui processes running before this scenario: " + $guisBefore) -ForegroundColor DarkGray

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
        Check ((Wait-Until { @(Get-Windows).Count -eq 1 } 20)) "the instance has one window"
        $first = [long]@(Get-Windows)[0].handle
        [void][HordeSessionWindowScenario.Native]::ShowWindow([IntPtr]$first, 7)

        Write-Host ""
        Write-Host "--- 1. one window ---" -ForegroundColor Cyan
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $one = Find-HordeWeztermSessionWindow -Pane $paneOne -Instance $instance
        $took = $clock.ElapsedMilliseconds
        Check ($one.state -ceq "known" -and $one.value.handle -eq $first) ("pane " + $paneOne + " of " + $instance + " is shown in the instance's one window, by the real listing (" + (Why $one) + ")")
        Check ($one.state -ceq "known" -and $one.value.detail -ceq "the terminal has one window, and again on a second reading 300 ms later") "and the finder says there was nothing to tell apart, and that it held on a second reading 300 ms later"
        Check ($took -ge 300) ("the answer took " + $took + " ms: at least the wait between the two readings")

        Write-Host ""
        Write-Host "--- 2. a pane that is not listed, an instance that is not running ---" -ForegroundColor Cyan
        $noPane = Find-HordeWeztermSessionWindow -Pane "987" -Instance $instance
        Check ($noPane.state -ceq "unknown" -and $noPane.reason -like "the terminal lists no pane 987*") ("a pane this instance does not have: unknown, from the real listing (" + (Why $noPane) + ")")
        $noGui = Find-HordeWeztermSessionWindow -Pane $paneOne -Instance "gui-sock-1"
        Check ($noGui.state -ceq "unknown" -and $noGui.reason -like "the session's terminal is not running*") ("an instance whose gui is not running: unknown, and no terminal is asked anything (" + (Why $noGui) + ")")

        Write-Host ""
        Write-Host "--- 3. two windows, told apart by their own titles ---" -ForegroundColor Cyan
        # ANOTHER PROGRAM, so that the two windows are titled differently: a pane is titled after what
        # runs in it.
        $panePing = ("" + (Invoke-HordeWeztermCli -Rest @("spawn", "--new-window", "--", "ping.exe", "-n", "300", "127.0.0.1"))).Trim()
        Check ($panePing -cmatch '\A[0-9]+\z' -and $panePing -cne $paneOne) ("a second window was spawned in the instance (pane " + $panePing + ")")
        Check ((Wait-Until { @(Get-Windows).Count -eq 2 } 20)) "the instance's gui process now has two terminal windows"
        $second = Hide-New -Known @($first)
        $script:a = $null; $script:b = $null
        $told = Wait-Until { $script:a = Find-HordeWeztermSessionWindow -Pane $paneOne -Instance $instance; $script:b = Find-HordeWeztermSessionWindow -Pane $panePing -Instance $instance; ($script:a.state -ceq "known" -and $script:b.state -ceq "known") } 20
        Show-Titles
        Check $told ("each pane's window is known (" + (Why $script:a) + " / " + (Why $script:b) + ")")
        Check ($told -and $second -ne 0 -and $script:a.value.handle -eq $first -and $script:b.value.handle -eq $second) "the first pane is in the first window and the second pane in the second: neither is taken for the other"
        Check ($told -and $script:b.value.detail -ceq "the one of the terminal's 2 windows titled after its panes, and again on a second reading 300 ms later") "and they were told apart by title, from the listing, on two readings"

        Write-Host ""
        Write-Host "--- 4. the second reading, for real: a twin opens between the two readings ---" -ForegroundColor Cyan
        # One find, one attempt. Its wait between the two readings is this block: it opens a third window
        # running what the first runs, so titled the same, waits until the gui shows it, and then waits
        # the time it was asked to. The first reading saw two windows and told them apart; the second
        # sees a twin.
        $script:paneTwin = ""; $script:waitedMs = 0
        $openTwin = { param($ms)
            $script:waitedMs = [int]$ms
            $script:paneTwin = ("" + (Invoke-HordeWeztermCli -Rest @("spawn", "--new-window"))).Trim()
            [void](Wait-Until { $w = @(Get-Windows); ($w.Count -eq 3 -and @($w | Where-Object { $_.title -ceq (@($w | Where-Object { $_.handle -eq $first })[0].title) }).Count -eq 2) } 20)
            Start-Sleep -Milliseconds $ms }
        $onceOnly = Read-HordeModuleSettingsText -Declaration $script:HordeWeztermWindowSettings -Text '{"schemaVersion":1,"settings":{"attempts":1}}'
        $caught = Find-HordeWeztermSessionWindow -Pane $paneOne -Instance $instance -Settings $onceOnly -Wait $openTwin
        $twin = Hide-New -Known @($first, $second)
        Show-Titles
        Check ($script:paneTwin -cmatch '\A[0-9]+\z' -and $twin -ne 0 -and $script:waitedMs -eq 300) ("between the two readings a third window was opened in the instance (pane " + $script:paneTwin + "), in the 300 ms wait the finder asked for")
        Check ($caught.state -ceq "unknown" -and $caught.reason -like "a window was found for the pane and was not found again on a second reading 300 ms later (2 of the terminal's windows are titled as the window of pane *") ("found on the first reading and not on the second: unknown, and it says the match did not hold (" + (Why $caught) + ")")

        Write-Host ""
        Write-Host "--- 5. two windows running the same program: unknown, and neither is chosen ---" -ForegroundColor Cyan
        $script:a = $null; $script:b = $null
        $settled = Wait-Until { $script:a = Find-HordeWeztermSessionWindow -Pane $paneOne -Instance $instance; $script:b = Find-HordeWeztermSessionWindow -Pane $script:paneTwin -Instance $instance; ($script:a.reason -like "2 of the terminal's windows*" -and $script:b.reason -like "2 of the terminal's windows*") } 20
        Check ($settled -and $script:a.state -ceq "unknown" -and $script:a.reason -like "2 of the terminal's windows are titled as the window of pane * would be, and one is never chosen over another*") ("the first pane, whose window now has a twin: unknown (" + (Why $script:a) + ")")
        Check ($settled -and $script:b.state -ceq "unknown") ("and the twin's pane: unknown too (" + (Why $script:b) + ")")
        $alone = Find-HordeWeztermSessionWindow -Pane $panePing -Instance $instance
        Check ($alone.state -ceq "known" -and $alone.value.handle -eq $second) ("CONTROL: the window titled alone beside the twins is still found (" + (Why $alone) + ")")

        Write-Host ""
        Write-Host "--- 6. a zoomed pane, with one tab and with two ---" -ForegroundColor Cyan
        $listed = @(ConvertFrom-HordeWeztermJson (Invoke-HordeWeztermCli -Rest @("list", "--format", "json")))
        $pingWindowId = "" + (@($listed | Where-Object { "" + $_.pane_id -ceq $panePing })[0].window_id)
        $paneSplit = ("" + (Invoke-HordeWeztermCli -Rest @("split-pane", "--pane-id", $panePing, "--", "ping.exe", "-n", "300", "127.0.0.2"))).Trim()
        [void](Invoke-HordeWeztermCli -Rest @("zoom-pane", "--pane-id", $paneSplit, "--zoom"))
        $script:z = $null
        $zoomedOne = Wait-Until { $script:z = Find-HordeWeztermSessionWindow -Pane $paneSplit -Instance $instance; ($script:z.state -ceq "known" -and @(Get-Windows | Where-Object { $_.handle -eq $second -and $_.title -clike "[[]Z[]] *" }).Count -eq 1) } 20
        Show-Titles
        Check ($zoomedOne -and $script:z.value.handle -eq $second) ("one tab, its active pane zoomed: the window is titled [Z] and its title, and is found (" + (Why $script:z) + ")")
        $paneTab = ("" + (Invoke-HordeWeztermCli -Rest @("spawn", "--window-id", $pingWindowId, "--", "ping.exe", "-n", "300", "127.0.0.3"))).Trim()
        [void](Invoke-HordeWeztermCli -Rest @("activate-tab", "--tab-index", "0", "--pane-id", $paneSplit))
        $zoomedTwo = Wait-Until { $script:z = Find-HordeWeztermSessionWindow -Pane $paneSplit -Instance $instance; ($script:z.state -ceq "known" -and @(Get-Windows | Where-Object { $_.handle -eq $second -and $_.title -clike "[[]Z[]] [[]1/2[]] *" }).Count -eq 1) } 20
        Show-Titles
        Check ($paneTab -cmatch '\A[0-9]+\z' -and $zoomedTwo -and $script:z.value.handle -eq $second) ("two tabs, the zoomed pane's tab in front: the window is titled [Z] and then [1/2], and is found (" + (Why $script:z) + ")")
        $viaTab = Find-HordeWeztermSessionWindow -Pane $paneTab -Instance $instance
        Check ($viaTab.state -ceq "known" -and $viaTab.value.handle -eq $second) ("and the pane of the tab that is not in front is in that same window (" + (Why $viaTab) + ")")
    }
    catch { Check $false ("the scenario stopped: " + $_.Exception.Message) }
    finally {
        # Teardown runs whatever happened above. A teardown that only runs on success is the leak.
        $result = Stop-HordeIsolatedWezterm -Instance $iso
    }
    Check (-not $result.refused) "teardown accepted the instance Start issued"
    Check ($result.stopped -and -not $result.survived -and @($result.orphansSurvived).Count -eq 0) "the terminal and everything that ran in it are gone"
}
Start-Sleep -Milliseconds 800
$guisAfter = (@(Get-HordeWeztermGuiPids | Sort-Object) -join ",")
Check ($guisAfter -ceq $guisBefore) ("the gui processes running are exactly those running before: " + $guisAfter)
Check (-not (Test-Path -LiteralPath $env:HORDE_HOME)) "and nothing was made under the home this scenario named"

Write-Host ""
if ($fails.Count -gt 0) { Write-Host ("==== " + $fails.Count + " FAILURE(S) ====") -ForegroundColor Red; foreach ($f in $fails) { Write-Host ("  - " + $f) -ForegroundColor Red }; exit 1 }
Write-Host "==== a pane's window is the one the terminal's own listing proves on two readings, or it is unknown ====" -ForegroundColor Green
exit 0
