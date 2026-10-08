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
#   3. two windows running different programs are told apart by the titles they carry (both are
#      minimised here, so neither has a size).
#   4. THE SECOND READING, FOR REAL: a window with the same title as the session's is opened between
#      the two readings of one find. The first reading found the window; the second cannot tell it
#      from its twin; the answer is unknown and says the match did not hold.
#   5. two windows running the same program: unknown for each, and neither is chosen; the window
#      titled alone beside them is still found.
#   6. how the terminal titles a zoomed pane, with one tab and with two: the finder still finds its
#      window (the order "[Z] [1/2] title" was measured here first, 2026-10-07).
#
#   7. A TERMINAL THAT TITLES AND PADS ITS WINDOWS ITS OWN WAY, AND SESSIONS THAT REDRAW THEIR TITLES - the
#      case the first finder answered unknown for on the fleet's own terminal (trial of 2026-10-07). A
#      second instance is started with a config of this scenario's own: a format-window-title handler
#      that writes "[<tab>/<tabs>] <pane title> - horde test", and a padding no default has. Its windows
#      stand where no screen is, at sizes this scenario gives them; in one a program redraws its title
#      several times a second with another first character each time, as a working session does.
#        - that window, alone of its size, is found by size while its title never holds still;
#        - a pane in its second tab is in the same window;
#        - two windows of one size with one title: unknown, neither chosen;
#        - a third of that size with a title of its own: found, by size and then title;
#        - the instance's first window, minimised and so of no size: found as the one left over.
#
# NOT PROVED HERE: the live fleet's sixteen windows (read-only runs of the finder against them are in
# the trial's notes, not in a scenario: a scenario never lists the terminal in use); a second screen;
# screens of two scales.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
# A home of this scenario's own, never made: the finder's settings are their defaults here, whatever
# the person at this machine has set.
$env:HORDE_HOME = Join-Path $env:TEMP ("horde-e2e-session-window-home-" + [guid]::NewGuid().ToString("N"))
. (Join-Path (Split-Path -Parent $here) "Isolation.ps1")
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "hosts\wezterm\Window.ps1")

# All this scenario does to a window, and only to windows of the instances it started: minimise it
# without giving it the keyboard, or (part 7) stand it where no screen is, at a size, the same way.
Add-Type -Namespace HordeSessionWindowScenario -Name Native -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd); [DllImport("user32.dll")] public static extern bool SetWindowPos(System.IntPtr h, System.IntPtr after, int x, int y, int cx, int cy, uint flags);'

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
        Check ($told -and $script:b.value.detail -ceq "the one of the terminal's 2 windows that carries the title of its pane, and again on a second reading 300 ms later") "and they were told apart by title, from the listing, on two readings"

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
        Check ($caught.state -ceq "unknown" -and $caught.reason -like "a window was found for the pane and was not found again on a second reading 300 ms later (2 of the terminal's windows carry the title of the window of pane *") ("found on the first reading and not on the second: unknown, and it says the match did not hold (" + (Why $caught) + ")")

        Write-Host ""
        Write-Host "--- 5. two windows running the same program: unknown, and neither is chosen ---" -ForegroundColor Cyan
        $script:a = $null; $script:b = $null
        $settled = Wait-Until { $script:a = Find-HordeWeztermSessionWindow -Pane $paneOne -Instance $instance; $script:b = Find-HordeWeztermSessionWindow -Pane $script:paneTwin -Instance $instance; ($script:a.reason -like "2 of the terminal's windows*" -and $script:b.reason -like "2 of the terminal's windows*") } 20
        Check ($settled -and $script:a.state -ceq "unknown" -and $script:a.reason -like "2 of the terminal's windows carry the title of the window of pane *, and one is never chosen over another*") ("the first pane, whose window now has a twin: unknown (" + (Why $script:a) + ")")
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

Write-Host ""
Write-Host "--- 7. a terminal with a config of its own: its own title format, its own padding, a title that never holds still ---" -ForegroundColor Cyan
$configDir = Join-Path $env:TEMP ("horde-e2e-session-window-config-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $configDir | Out-Null
$configFile = Join-Path $configDir "own.lua"
[System.IO.File]::WriteAllText($configFile, @'
local wezterm = require 'wezterm'
wezterm.on('format-window-title', function(tab, pane, tabs, panes, config)
  return string.format('[%d/%d] %s - horde test', tab.tab_index + 1, #tabs, pane.title)
end)
return {
  window_padding = { left = 11, right = 5, top = 3, bottom = 7 },
  initial_cols = 80, initial_rows = 24,
  check_for_updates = false,
  window_close_confirmation = 'NeverPrompt',
}
'@, (New-Object System.Text.UTF8Encoding($false)))
function Start-Titled {
    # A new window of the instance whose one pane runs a program that titles itself: with -Turning, a
    # title whose first character is another one about seven times a second, as a working session's
    # is; otherwise one title, set once. Returns the pane id as text.
    param([string]$Name, [switch]$Turning, [string]$WindowId = "")
    $program = "[Console]::Title = '" + $Name + "'; Start-Sleep -Seconds 900"
    if ($Turning) { $program = '$g = @([char]0x25D0, [char]0x25D1, [char]0x2733); $i = 0; while ($true) { [Console]::Title = ([string]$g[$i % 3]) + " ' + $Name + '"; $i++; Start-Sleep -Milliseconds 140 }' }
    $where = @("--new-window")
    if ($WindowId -ne "") { $where = @("--window-id", $WindowId) }
    return ("" + (Invoke-HordeWeztermCli -Rest (@("spawn") + $where + @("--", "powershell.exe", "-NoProfile", "-EncodedCommand", [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($program)))))).Trim()
}
function Set-Aside {
    # Stand every window of the instance that -Known does not hold where no screen is, -Width by -Height
    # outside, without the keyboard and without changing which window is in front; returns the handle
    # of the one new window, or 0 when there is not exactly one.
    param([long[]]$Known, [int]$Width, [int]$Height)
    $new = @(Get-Windows | Where-Object { $Known -notcontains $_.handle })
    foreach ($w in $new) { [void][HordeSessionWindowScenario.Native]::SetWindowPos([IntPtr]$w.handle, [IntPtr]::Zero, -32000, -32000, $Width, $Height, 0x0014) }     # SWP_NOZORDER | SWP_NOACTIVATE
    if ($new.Count -eq 1) { return [long]$new[0].handle }
    return [long]0
}
function Find-Pane { param([string]$Pane) return (Find-HordeWeztermSessionWindow -Pane $Pane -Instance $instance) }
$iso = Start-HordeIsolatedWezterm -TimeoutSeconds 45 -ConfigFile $configFile
Check ($null -ne $iso) "a second isolated instance started with this scenario's own config, and answered"
if ($iso) {
    $result = $null
    try {
        $count = Assert-HordeIsolated -Instance $iso
        Check ($count -ge 1) ("THE CONTROL: this process can see only that instance's panes (" + $count + ")")
        Check (@($guisBefore -split "," | Where-Object { $_ -ne "" }) -notcontains ("" + $iso.pid)) "its gui is a process that was not running before"
        $instance = Split-Path -Leaf $iso.socket
        $paneZero = "" + @(ConvertFrom-HordeWeztermJson (Invoke-HordeWeztermCli -Rest @("list", "--format", "json")))[0].pane_id
        Check ((Wait-Until { @(Get-Windows).Count -eq 1 } 20)) "the instance has one window"
        $w0 = [long]@(Get-Windows)[0].handle
        [void][HordeSessionWindowScenario.Native]::ShowWindow([IntPtr]$w0, 7)                                 # SW_SHOWMINNOACTIVE
        Check ((Wait-Until { @(Get-Windows | Where-Object { $_.handle -eq $w0 -and $_.title -cmatch '\A\[1/1\] .* - horde test\z' -and $_.width -eq 0 -and $_.height -eq 0 }).Count -eq 1 } 20)) ("the config is in force - the window is titled in the config's own format - and, minimised, it has no size: [" + @(Get-Windows)[0].title + "]")

        $paneA = Start-Titled -Name "alpha" -Turning
        Check ((Wait-Until { @(Get-Windows).Count -eq 2 } 20)) "a second window, whose session redraws its title"
        $wA = Set-Aside -Known @($w0) -Width 1000 -Height 620
        $paneB = Start-Titled -Name "beta"
        Check ((Wait-Until { @(Get-Windows).Count -eq 3 } 20)) "a third window, titled beta"
        $wB = Set-Aside -Known @($w0, $wA) -Width 760 -Height 480
        $paneC = Start-Titled -Name "beta"
        Check ((Wait-Until { @(Get-Windows).Count -eq 4 } 20)) "a fourth, titled beta too"
        $wC = Set-Aside -Known @($w0, $wA, $wB) -Width 760 -Height 480
        $paneD = Start-Titled -Name "gamma"
        Check ((Wait-Until { @(Get-Windows).Count -eq 5 } 20)) "a fifth, titled gamma"
        $wD = Set-Aside -Known @($w0, $wA, $wB, $wC) -Width 760 -Height 480
        Check ($paneA -cmatch '\A[0-9]+\z' -and $paneB -cmatch '\A[0-9]+\z' -and $paneC -cmatch '\A[0-9]+\z' -and $paneD -cmatch '\A[0-9]+\z' -and $wA -ne 0 -and $wB -ne 0 -and $wC -ne 0 -and $wD -ne 0) ("four windows were opened in the instance and stood where no screen is (panes " + $paneA + ", " + $paneB + ", " + $paneC + ", " + $paneD + ")")
        # The programs have started and titled themselves, and the sizes are as given.
        $settled = Wait-Until { $w = @(Get-Windows); (@($w | Where-Object { $_.handle -eq $wA -and $_.title -clike "*alpha - horde test" }).Count -eq 1 -and @($w | Where-Object { $_.title -ceq "[1/1] beta - horde test" }).Count -eq 2 -and @($w | Where-Object { $_.title -ceq "[1/1] gamma - horde test" }).Count -eq 1) } 60
        Show-Titles
        Check $settled "every window is titled by the config's format around its own session's title"
        $sizes = @(Get-Windows | ForEach-Object { "" + $_.width + "x" + $_.height })
        Write-Host ("  their client sizes: " + ($sizes -join " ")) -ForegroundColor DarkGray
        $sizeOf = { param([long]$h) $n = @(Get-Windows | Where-Object { $_.handle -eq $h })[0]; "" + $n.width + "x" + $n.height }
        Check ((& $sizeOf $wB) -ceq (& $sizeOf $wC) -and (& $sizeOf $wC) -ceq (& $sizeOf $wD) -and (& $sizeOf $wA) -cne (& $sizeOf $wB) -and (& $sizeOf $wA) -cne "0x0" -and (& $sizeOf $wB) -cne "0x0") "one window of a size of its own, three of one size - in real pixels"
        # THE TITLE NEVER HOLDS STILL: forty readings, 50 ms apart.
        $seenTitles = New-Object System.Collections.ArrayList
        for ($k = 0; $k -lt 40; $k++) { $t = "" + @(Get-Windows | Where-Object { $_.handle -eq $wA })[0].title; if ($seenTitles -cnotcontains $t) { [void]$seenTitles.Add($t) }; Start-Sleep -Milliseconds 50 }
        Check ($seenTitles.Count -ge 2) ("CONTROL: the redrawing session's window was seen with " + $seenTitles.Count + " different titles in two seconds")

        $script:a = $null
        $foundA = Wait-Until { $script:a = Find-Pane $paneA; ($script:a.state -ceq "known") } 30
        Check ($foundA -and $script:a.value.handle -eq $wA) ("THE LIVE CASE, FOR REAL: the window whose title never holds still, in a format of the config's own, is found (" + (Why $script:a) + ")")
        Check ($foundA -and $script:a.value.detail -clike "the one of the terminal's 5 windows with the size of the pane's window (* cells), and again on a second reading 300 ms later") ("by its size, on two readings: " + $(if ($foundA) { $script:a.value.detail } else { "" }))
        $again = @(1..4 | ForEach-Object { Find-Pane $paneA })
        Check (@($again | Where-Object { $_.state -ceq "known" -and $_.value.handle -eq $wA }).Count -eq 4) ("and four times more of four, whatever its title was at each moment (" + ((@($again) | ForEach-Object { $_.state }) -join ", ") + ")")

        $listed = @(ConvertFrom-HordeWeztermJson (Invoke-HordeWeztermCli -Rest @("list", "--format", "json")))
        $windowA = "" + (@($listed | Where-Object { "" + $_.pane_id -ceq $paneA })[0].window_id)
        $paneTab = Start-Titled -Name "delta" -WindowId $windowA
        $script:t = $null
        $inTab = Wait-Until { $script:t = Find-Pane $paneTab; ($script:t.state -ceq "known" -and @(Get-Windows | Where-Object { $_.handle -eq $wA -and $_.title -clike "[[]2/2[]] *" }).Count -eq 1) } 30
        Show-Titles
        Check ($paneTab -cmatch '\A[0-9]+\z' -and $inTab -and $script:t.value.handle -eq $wA) ("a second tab in that window, now in front, titled [2/2] by the config: its pane is in the same window (" + (Why $script:t) + ")")
        Check ((Find-Pane $paneA).value.handle -eq $wA) "and so, still, is the pane of the tab behind it"

        $script:b = $null; $script:c = $null
        $twins = Wait-Until { $script:b = Find-Pane $paneB; $script:c = Find-Pane $paneC; ($script:b.reason -like "2 of the terminal's windows carry the title*" -and $script:c.reason -like "2 of the terminal's windows carry the title*") } 30
        Check ($twins -and $script:b.state -ceq "unknown" -and $script:b.reason -clike "2 of the terminal's windows carry the title of the window of pane * and could be it by size (* cells), and one is never chosen over another") ("TWO WINDOWS OF EQUAL SIZE AND ONE TITLE: unknown, neither chosen (" + (Why $script:b) + ")")
        Check ($twins -and $script:c.state -ceq "unknown") ("and the same for the other (" + (Why $script:c) + ")")
        $script:d = $null
        $foundD = Wait-Until { $script:d = Find-Pane $paneD; ($script:d.state -ceq "known") } 30
        Check ($foundD -and $script:d.value.handle -eq $wD -and $script:d.value.detail -clike "the one of 3 windows that could be the pane's window by size (* cells) that carries its title, and again*") ("the third window of that size, with a title of its own, is found by size and then title (" + (Why $script:d) + ")")
        $script:z = $null
        $foundZero = Wait-Until { $script:z = Find-Pane $paneZero; ($script:z.state -ceq "known") } 30
        Check ($foundZero -and $script:z.value.handle -eq $w0 -and $script:z.value.detail -clike "the one of the terminal's 5 windows that is not another's by size: the pane's window has no one size on screen*") ("the instance's first window, minimised, is the one left when every other is another's by size (" + (Why $script:z) + ")")
    }
    catch { Check $false ("part 7 stopped: " + $_.Exception.Message) }
    finally { $result = Stop-HordeIsolatedWezterm -Instance $iso }
    Check (-not $result.refused) "teardown accepted the second instance"
    Check ($result.stopped -and -not $result.survived -and @($result.orphansSurvived).Count -eq 0) "the second terminal and everything that ran in it are gone"
}
if ((Split-Path -Leaf $configDir) -match '\Ahorde-e2e-session-window-config-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $configDir)) { Remove-Item -LiteralPath $configDir -Recurse -Force }
Start-Sleep -Milliseconds 800
$guisAfter = (@(Get-HordeWeztermGuiPids | Sort-Object) -join ",")
Check ($guisAfter -ceq $guisBefore) ("the gui processes running are exactly those running before: " + $guisAfter)
Check (-not (Test-Path -LiteralPath $env:HORDE_HOME)) "and nothing was made under the home this scenario named"

Write-Host ""
if ($fails.Count -gt 0) { Write-Host ("==== " + $fails.Count + " FAILURE(S) ====") -ForegroundColor Red; foreach ($f in $fails) { Write-Host ("  - " + $f) -ForegroundColor Red }; exit 1 }
Write-Host "==== a pane's window is the one the terminal's own listing proves on two readings, or it is unknown ====" -ForegroundColor Green
exit 0
