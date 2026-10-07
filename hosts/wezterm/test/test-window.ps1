# WHICH NATIVE WINDOW SHOWS A PANE - AND DOES THE FINDER SAY "UNKNOWN" RATHER THAN GUESS?
#
# hosts/wezterm/Window.ps1's decision is a pure function of the terminal's own listing and the titles
# of its process's windows, so every case here is a fixture: one window, several, none, a session whose
# pane is gone, two windows that cannot be told apart, a title that changed while it was read. No
# terminal is touched: the listing comes from a recording runner and the windows from a block.
#
# FAIL CLOSED, as hosts/wezterm/test/test-act.ps1 does: this suite's own pin names a socket that does
# not exist, set as its first act, so a call that escaped the runner would fail to connect instead of
# reaching the terminal the suite was started from.
#
# The finding of a real window - a terminal this repository's scenario starts, never the one in use -
# is test/e2e/e2e-decisions-window.ps1's.

$env:WEZTERM_UNIX_SOCKET = Join-Path $env:TEMP ("horde-test-window-no-terminal-" + [guid]::NewGuid().ToString("N"))
# A HOME OF THIS SUITE'S OWN, which does not exist until the suite makes it: the finder reads its
# settings from Horde's home, and the person's own file must never decide what a check here sees.
$env:HORDE_HOME = Join-Path $env:TEMP ("horde-test-window-home-" + [guid]::NewGuid().ToString("N"))
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "hosts\wezterm\Window.ps1")

$star = [string][char]0x2733
$half = [string][char]0x25D0
function Pane { param([int]$Window, [int]$Tab, [int]$Id, [string]$Title, [bool]$Active = $true, [bool]$Zoomed = $false)
    return [ordered]@{ window_id = $Window; tab_id = $Tab; pane_id = $Id; workspace = "default"; title = $Title; cwd = "file:///C:/work/"; is_active = $Active; is_zoomed = $Zoomed; tty_name = $null } }
function Listing { param([object[]]$Panes) return (ConvertTo-Json -InputObject @($Panes) -Depth 4 -Compress) }
function Win { param([long]$Handle, [string]$Title) return [pscustomobject]@{ handle = $Handle; title = $Title } }
function Rows { param([object[]]$Panes) return @((Read-HordeWeztermWindowList -Raw (Listing $Panes)).value) }
function Pick { param([object[]]$Panes, [string]$Pane, [object[]]$Native, [object[]]$After = @()) return (Select-HordeWeztermSessionWindow -Rows (Rows $Panes) -Pane $Pane -Native $Native -NativeAfter $After) }

# A fleet as it was measured on 2026-10-06, cut down: the keeper of the list alone in window 10, an
# orchestrator with three tabs in window 11, a window with a split tab, and one more.
$fleet = @(
    (Pane 10 16 18 ($star + " keeper")),
    (Pane 11 17 19 ($half + " orchestrator")), (Pane 11 18 20 ($star + " worker one")), (Pane 11 19 21 ($star + " worker two")),
    (Pane 12 21 23 ($star + " left half") $false), (Pane 12 21 24 ($star + " right half") $true),
    (Pane 13 23 25 ($star + " another"))
)
$fleetWindows = @((Win 7001 ("[2/3] " + $star + " worker one")), (Win 7002 ($star + " keeper")), (Win 7003 ($star + " right half")), (Win 7004 ($star + " another")))

Write-Host ""
Write-Host "--- the listing is read, or it is unknown ---" -ForegroundColor Cyan
$read = Read-HordeWeztermWindowList -Raw (Listing $fleet)
Check ($read.state -ceq "known" -and @($read.value).Count -eq 7) "CONTROL: a listing of seven panes is seven rows"
$row = @($read.value | Where-Object { $_.pane -ceq "23" })[0]
Check ($row.window -ceq "12" -and $row.tab -ceq "21" -and $row.title -ceq ($star + " left half") -and $row.active -eq $false -and $row.zoomed -eq $false) "each row keeps its window, its tab, its title exactly, and whether it is its tab's active pane"
Check ((Read-HordeWeztermWindowList -Raw "[]").state -ceq "known" -and @((Read-HordeWeztermWindowList -Raw "[]").value).Count -eq 0) "a terminal that answers [] has no panes, and that is known"
Check ((Read-HordeWeztermWindowList -Raw "").state -ceq "unknown") "empty output is unknown, not no panes"
Check ((Read-HordeWeztermWindowList -Raw "not json").state -ceq "unknown") "output that is not JSON is unknown"
Check ((Read-HordeWeztermWindowList -Raw '[{"window_id":0,"tab_id":0,"pane_id":1,"title":"t"}]').reason -like "*has no is_active*") "a pane with no is_active cannot tell windows apart, so the whole listing is unknown"
Check ((Read-HordeWeztermWindowList -Raw '[7]').state -ceq "unknown" -and (Read-HordeWeztermWindowList -Raw '[null]').state -ceq "unknown") "a list of something that is not a pane is unknown"
# A FIELD OF THE WRONG KIND IS NOT CONVERTED. PowerShell turns any text that is not empty into true and a
# null into "", so "is_active":"no" was an active pane and a missing title an empty one (review of
# 2026-10-06, finding C6): a row read that way can make a title fit, and a fit is believed.
function Row { param([string]$Fields) return (Read-HordeWeztermWindowList -Raw ('[{' + $Fields + '}]')) }
Check ((Row '"window_id":0,"tab_id":0,"pane_id":1,"title":"t","is_active":true,"is_zoomed":false').state -ceq "known") "CONTROL: a row whose every field is of its own kind is read"
foreach ($wrong in @(
    @{ row = '"window_id":0,"tab_id":0,"pane_id":1,"title":"t","is_active":"yes"'; says = "*is_active that is not true or false*"; what = "is_active written as text" }
    @{ row = '"window_id":0,"tab_id":0,"pane_id":1,"title":"t","is_active":1'; says = "*is_active that is not true or false*"; what = "is_active written as a number" }
    @{ row = '"window_id":0,"tab_id":0,"pane_id":1,"title":"t","is_active":null'; says = "*is_active that is not true or false*"; what = "is_active that is null" }
    @{ row = '"window_id":0,"tab_id":0,"pane_id":1,"title":null,"is_active":true'; says = "*title that is not text*"; what = "a title that is null" }
    @{ row = '"window_id":0,"tab_id":0,"pane_id":1,"title":7,"is_active":true'; says = "*title that is not text*"; what = "a title that is a number" }
    @{ row = '"window_id":0,"tab_id":0,"pane_id":1,"title":"t","is_active":true,"is_zoomed":"no"'; says = "*is_zoomed that is not true or false*"; what = "is_zoomed written as text" }
    @{ row = '"window_id":0,"tab_id":0,"pane_id":"1","title":"t","is_active":true'; says = "*pane_id that is not a whole number*"; what = "a pane id written as text" }
    @{ row = '"window_id":1.5,"tab_id":0,"pane_id":1,"title":"t","is_active":true'; says = "*window_id that is not a whole number*"; what = "a window id that is a fraction" }
    @{ row = '"window_id":0,"tab_id":-1,"pane_id":1,"title":"t","is_active":true'; says = "*tab_id that is not a whole number*"; what = "a tab id below zero" }
    @{ row = '"window_id":0,"tab_id":null,"pane_id":1,"title":"t","is_active":true'; says = "*tab_id that is not a whole number*"; what = "a tab id that is null" }
)) {
    $r = Row $wrong.row
    Check ($r.state -ceq "unknown" -and $r.reason -like $wrong.says) ($wrong.what + " is not converted: the listing is unknown, and says which field")
}

Write-Host ""
Write-Host "--- one window ---" -ForegroundColor Cyan
$one = Pick @((Pane 0 0 0 "cmd.exe")) "0" @((Win 4100 "whatever the window is called"))
Check ($one.state -ceq "known" -and $one.value.handle -eq 4100 -and $one.value.window -ceq "0" -and $one.value.detail -ceq "the terminal has one window") "one window listed and one terminal window in the process: that window, whatever its title"
$oneTwoTabs = Pick @((Pane 0 0 0 "first"), (Pane 0 1 1 "second")) "1" @((Win 4100 "[1/2] first"))
Check ($oneTwoTabs.state -ceq "known" -and $oneTwoTabs.value.handle -eq 4100) "a pane in a tab that is not in front is still in that one window"

Write-Host ""
Write-Host "--- several windows: told apart by the session's own window's details ---" -ForegroundColor Cyan
$keeper = Pick $fleet "18" $fleetWindows
Check ($keeper.state -ceq "known" -and $keeper.value.handle -eq 7002 -and $keeper.value.window -ceq "10") "the keeper's pane is in window 10, and the one terminal window titled after that window's pane is it"
$worker = Pick $fleet "21" $fleetWindows
Check ($worker.state -ceq "known" -and $worker.value.handle -eq 7001 -and $worker.value.window -ceq "11") "a pane in a three-tab window is found by the window's title, [2/3] and the title of whichever tab is in front"
$split = Pick $fleet "23" $fleetWindows
Check ($split.state -ceq "known" -and $split.value.handle -eq 7003) "a pane that is not its tab's active pane is in the window titled after the pane that is"
$leftTitled = Pick $fleet "23" @((Win 7001 ("[2/3] " + $star + " worker one")), (Win 7002 ($star + " keeper")), (Win 7003 ($star + " left half")), (Win 7004 ($star + " another")))
Check ($leftTitled.state -ceq "unknown") "and a window titled after a pane that is NOT its tab's active pane is not that window: the terminal never titles one so"
$lone = Pick $fleet "18" @((Win 7001 ("[2/3] " + $star + " worker one")))
Check ($lone.state -ceq "unknown" -and $lone.reason -like "none of the terminal's 1 windows*") "with several window ids listed and only one terminal window on screen, that window is not taken for the session's unless its title says so"
$zoomRows = @((Pane 1 1 1 "editor" $true $true), (Pane 2 2 2 "other"))
$zoomed = Pick $zoomRows "1" @((Win 501 "[Z] editor"), (Win 502 "other"))
Check ($zoomed.state -ceq "known" -and $zoomed.value.handle -eq 501) "a zoomed pane's window carries [Z] before its title, and is found by it"
Check ((Pick $zoomRows "1" @((Win 501 "editor"), (Win 502 "other"))).state -ceq "unknown") "CONTROL: without the [Z] the title is not that window's, and nothing is guessed"
# A ZOOMED PANE IN A WINDOW OF SEVERAL TABS: [Z] comes FIRST, then the tab count. Measured 2026-10-07
# against an isolated instance (20240203-110809-5046fc22): a two-tab window whose front tab's active pane
# was zoomed was titled "[Z] [1/2] PING.EXE". The finder had expected the other order, unmeasured
# (review of 2026-10-06, finding C4), and so answered unknown for such a window.
$zoomTabs = @((Pane 1 1 1 "editor" $true $true), (Pane 1 2 3 "logs"), (Pane 2 4 2 "other"))
$zoomedTab = Pick $zoomTabs "1" @((Win 501 "[Z] [1/2] editor"), (Win 502 "other"))
Check ($zoomedTab.state -ceq "known" -and $zoomedTab.value.handle -eq 501) ("in a window of two tabs the zoomed pane's window is titled [Z] and then the tab count, as the terminal was measured to write it (" + $zoomedTab.state + ")")
Check ((Pick $zoomTabs "1" @((Win 501 "[1/2] [Z] editor"), (Win 502 "other"))).state -ceq "unknown") "and the other order, which the terminal does not write, is no window's title"
Check ((Pick $zoomTabs "3" @((Win 501 "[2/2] logs"), (Win 502 "other"))).value.handle -eq 501) "CONTROL: with the tab that is not zoomed in front, the same window is titled by the count alone"

Write-Host ""
Write-Host "--- a title that changed while it was read ---" -ForegroundColor Cyan
$spinning = @((Win 7001 ("[2/3] " + $star + " worker one")), (Win 7002 ($half + " keeper")), (Win 7003 ($star + " right half")), (Win 7004 ($star + " another")))
$stale = Pick $fleet "18" $spinning
Check ($stale.state -ceq "unknown" -and $stale.reason -like "none of the terminal's 4 windows is titled as the window of pane 18 would be*") "read once, with the title a moment out of step with the listing: unknown, and says a title fits nothing"
$both = Pick $fleet "18" $spinning $fleetWindows
Check ($both.state -ceq "known" -and $both.value.handle -eq 7002) "read before and after the listing, a match in either reading counts"

Write-Host ""
Write-Host "--- never the likeliest ---" -ForegroundColor Cyan
$twins = @((Pane 1 1 1 "PowerShell"), (Pane 2 2 2 "PowerShell"), (Pane 3 3 3 "notes"))
$twinWindows = @((Win 601 "PowerShell"), (Win 602 "PowerShell"), (Win 603 "notes"))
$twin = Pick $twins "1" $twinWindows
Check ($twin.state -ceq "unknown" -and $twin.reason -like "2 of the terminal's windows are titled as the window of pane 1 would be*") "two windows with the session's window's title: unknown, and neither is chosen"
Check ((Pick $twins "3" $twinWindows).value.handle -eq 603) "CONTROL: the window beside the twins, titled alone, is still found"
$shadow = @((Pane 1 1 1 "build"), (Pane 2 2 2 "build"), (Pane 3 3 3 "notes"))
$shadowed = Pick $shadow "1" @((Win 601 "build"), (Win 603 "notes"))
Check ($shadowed.state -ceq "unknown" -and $shadowed.reason -like "*is titled as another of the terminal's windows would be too*") "one window fits, but it fits another window id as well (whose own window was not seen): unknown"
$wrongTabs = Pick $fleet "21" @((Win 7001 ("[2/4] " + $star + " worker one")), (Win 7002 ($star + " keeper")))
Check ($wrongTabs.state -ceq "unknown") "a title that counts four tabs is not the window of a pane the listing puts in a three-tab window"
$bare = Pick $fleet "21" @((Win 7001 ($star + " worker one")), (Win 7002 ($star + " keeper")))
Check ($bare.state -ceq "unknown") "nor is a bare pane title, on a window that has more than one tab"
$caseOnly = Pick $twins "3" @((Win 601 "PowerShell"), (Win 602 "PowerShell"), (Win 603 "Notes"))
Check ($caseOnly.state -ceq "unknown") "titles are compared exactly: Notes is not notes"

Write-Host ""
Write-Host "--- no window, or no pane ---" -ForegroundColor Cyan
$gonePane = Pick $fleet "99" $fleetWindows
Check ($gonePane.state -ceq "unknown" -and $gonePane.reason -ceq "the terminal lists no pane 99: the session's record names a pane that is no longer there") "a session whose pane the terminal no longer lists has no window"
$noWindows = Pick $fleet "18" @()
Check ($noWindows.state -ceq "unknown" -and $noWindows.reason -like "*has no terminal window on screen*") "a terminal process with no window on screen has none to stand beside"
$emptyList = Select-HordeWeztermSessionWindow -Rows @() -Pane "18" -Native $fleetWindows
Check ($emptyList.state -ceq "unknown" -and $emptyList.reason -like "the terminal lists no pane 18*") "a terminal with no panes at all lists no pane 18"
$twice = Pick @((Pane 1 1 5 "a"), (Pane 2 2 5 "b")) "5" @((Win 1 "a"), (Win 2 "b"))
Check ($twice.state -ceq "unknown" -and $twice.reason -like "the terminal lists pane 5 2 times*") "a pane listed twice is in no one window"

Write-Host ""
Write-Host "--- from a session's record to a window, with every call recorded ---" -ForegroundColor Cyan
$sockDir = Join-Path $env:TEMP ("horde-window-socks-" + [guid]::NewGuid().ToString("N"))
$script:calls = New-Object System.Collections.ArrayList
$script:targets = New-Object System.Collections.ArrayList
$script:windowReads = 0
$script:listing = Listing $fleet
$runner = { param($rest, $envMap, $target) [void]$script:calls.Add((@($rest) -join " ")); [void]$script:targets.Add($target); return [pscustomobject]@{ code = 0; out = $script:listing; err = ""; timedOut = $false } }
$windows = { param($processId) $script:windowReads++; $script:pidAsked = $processId; return $fleetWindows }
$alive = { param($p) if ($p -eq 4242) { "133000000000000000" } else { $null } }
# The finder's settings as a person's file would give them (core/ModuleSettings.ps1), from a table.
function Settings { param([hashtable]$With = @{})
    return (Read-HordeModuleSettingsText -Declaration $script:HordeWeztermWindowSettings -Text (ConvertTo-Json -InputObject @{ schemaVersion = 1; settings = $With } -Compress)) }
# Every wait the finder asks for is recorded and none is slept: the suite checks how long it asked for.
$script:waits = New-Object System.Collections.ArrayList
$wait = { param($ms) [void]$script:waits.Add([int]$ms) }
function Find { param([string]$Pane, [string]$Instance, [scriptblock]$W = $windows, [scriptblock]$R = $runner, [int]$Attempts = 3)
    return (Find-HordeWeztermSessionWindow -Pane $Pane -Instance $Instance -Settings (Settings @{ socketFolder = $sockDir; attempts = $Attempts; retryWaitMs = 25 }) -Runner $R -Windows $W -ProcessStart $alive -Wait $wait) }
$found = Find "18" "gui-sock-4242"
Check ($found.state -ceq "known" -and $found.value.handle -eq 7002) "pane 18 of instance gui-sock-4242: the keeper's window"
Check ($script:calls.Count -eq 1 -and $script:calls[0] -ceq "list --format json") "the terminal is asked one thing, its list of panes - nothing that types, moves or closes"
Check ($script:targets[0].socket -ceq (Join-Path $sockDir "gui-sock-4242") -and "" + $script:targets[0].guiPid -ceq "4242" -and $script:targets[0].guiStart -ceq "133000000000000000") "and it is asked as a named terminal: the instance's socket, its gui and that gui's start time"
Check ($script:windowReads -eq 2 -and $script:pidAsked -eq 4242) "the windows read are that gui process's own, once before the listing and once after"

$script:calls.Clear()
foreach ($bad in @(
    @{ pane = "18"; inst = "gui-sock-9999"; says = "the session's terminal is not running"; what = "an instance whose gui is not running" }
    @{ pane = "18"; inst = "..\..\elsewhere\gui-sock-4242"; says = "does not name one of this terminal's instances"; what = "an instance that is a path" }
    @{ pane = "18"; inst = "tty3"; says = "does not name one of this terminal's instances"; what = "an instance of some other terminal" }
    @{ pane = "18"; inst = ""; says = "does not name one of this terminal's instances"; what = "no instance" }
    @{ pane = "%3"; inst = "gui-sock-4242"; says = "names a pane this terminal does not number that way"; what = "a pane another terminal would name" }
    @{ pane = ""; inst = "gui-sock-4242"; says = "names a pane this terminal does not number that way"; what = "no pane" }
)) {
    $r = Find $bad.pane $bad.inst
    Check ($r.state -ceq "unknown" -and $r.reason -like ("*" + $bad.says + "*")) ($bad.what + " is unknown, in words")
}
Check ($script:calls.Count -eq 0) "and for none of those was the terminal asked anything"

$refusing = { param($rest, $envMap, $target) return [pscustomobject]@{ code = 1; out = ""; err = "failed to connect to the socket"; timedOut = $false } }
$r = Find "18" "gui-sock-4242" -R $refusing
Check ($r.state -ceq "unknown" -and $r.reason -ceq "the terminal did not list its panes (exit 1): failed to connect to the socket") "a terminal that does not answer is unknown, with what it said"
$garbled = { param($rest, $envMap, $target) return [pscustomobject]@{ code = 0; out = "<html>"; err = ""; timedOut = $false } }
Check ((Find "18" "gui-sock-4242" -R $garbled).reason -ceq "the terminal's pane list is not JSON") "and so is one that answers with something else"

# A TITLE OUT OF STEP IS READ AGAIN, a few times, and then believed.
$script:windowReads = 0
$settling = { param($processId) $script:windowReads++; if ($script:windowReads -le 2) { return $spinning }; return $fleetWindows }
$script:waits.Clear()
$r = Find "18" "gui-sock-4242" -W $settling
Check ($r.state -ceq "known" -and $r.value.handle -eq 7002 -and $script:windowReads -eq 4) "a title that fitted nothing on the first reading is read again, and found on the second"
Check (($script:waits -join ",") -ceq "25") "after the wait its settings give, asked for once"
$script:windowReads = 0
$never = { param($processId) $script:windowReads++; return $spinning }
$r = Find "18" "gui-sock-4242" -W $never
Check ($r.state -ceq "unknown" -and $r.reason -like "none of the terminal's*" -and $script:windowReads -eq 6) "one that never fits is read three times and is then unknown"
$script:windowReads = 0
$r = Find "99" "gui-sock-4242" -W $never
Check ($r.state -ceq "unknown" -and $script:windowReads -eq 2) "a pane that is not listed is not read again: reading again cannot bring it back"

Write-Host ""
Write-Host "--- its numbers and its folder are settings, with one table and one file ---" -ForegroundColor Cyan
$declared = @($script:HordeWeztermWindowSettings.settings | ForEach-Object { $_.name + "=" + $_.default })
Check (($declared -join " ") -ceq "attempts=3 retryWaitMs=200 socketFolder=") ("the finder declares its settings once, with these defaults (" + ($declared -join " ") + ")")
$none = Get-HordeWeztermWindowSettings
Check ($none.values.attempts -eq 3 -and $none.values.retryWaitMs -eq 200 -and $none.values.socketFolder -ceq "" -and @($none.findings).Count -eq 0 -and -not (Test-Path -LiteralPath $env:HORDE_HOME)) "with no file under the home every setting is its default, nothing is found wrong, and nothing was made"
# The terminal's own place, when the folder is left out: this user's profile. The recording runner is
# handed the socket and nothing is opened.
$script:targets.Clear()
$own = Find-HordeWeztermSessionWindow -Pane "18" -Instance "gui-sock-4242" -Runner $runner -Windows $windows -ProcessStart $alive -Wait $wait
Check ($own.state -ceq "known" -and $script:targets[0].socket -ceq (Join-Path (Join-Path $env:USERPROFILE ".local\share\wezterm") "gui-sock-4242")) "with no folder set, the instance's socket is looked for in the terminal's own place under this user's profile"
Check ((Get-HordeWeztermWindowSockDir -Configured "") -ceq (Join-Path $env:USERPROFILE ".local\share\wezterm") -and (Get-HordeWeztermWindowSockDir -Configured $sockDir) -ceq $sockDir) "one function says where the sockets are: the folder a person set, or the terminal's own place"
$finderSrc = [System.IO.File]::ReadAllText((Join-Path $root "hosts\wezterm\Window.ps1"))
$actSrc = [System.IO.File]::ReadAllText((Join-Path $root "hosts\wezterm\Act.ps1"))
Check (([regex]::Matches($finderSrc, [regex]::Escape('Join-Path $env:USERPROFILE'))).Count -eq 1 -and $finderSrc.Contains('(Join-Path $env:USERPROFILE ".local\share\wezterm")') -and $actSrc.Contains('".local\share\wezterm"')) "the terminal's own place is written once in the finder, in the act file's own words (which that file's next owner replaces)"
# A person's file: fewer readings, another wait, another folder.
$settingsDir = Join-Path $env:HORDE_HOME "settings"
New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
$settingsFile = Join-Path $settingsDir "wezterm-window.json"
$neverFits = { param($processId) $script:windowReads++; return $spinning }
try {
    [System.IO.File]::WriteAllText($settingsFile, (ConvertTo-Json -InputObject @{ schemaVersion = 1; settings = @{ attempts = 2; retryWaitMs = 7; socketFolder = $sockDir } } -Compress))
    $script:windowReads = 0; $script:waits.Clear(); $script:targets.Clear()
    $r = Find-HordeWeztermSessionWindow -Pane "18" -Instance "gui-sock-4242" -Runner $runner -Windows $neverFits -ProcessStart $alive -Wait $wait
    Check ($r.state -ceq "unknown" -and $script:windowReads -eq 4 -and ($script:waits -join ",") -ceq "7") ("a file under the home that says two readings and 7 ms: read twice, 7 ms apart (" + $script:windowReads + " window reads, waits " + ($script:waits -join ",") + ")")
    Check ($script:targets.Count -gt 0 -and $script:targets[0].socket -ceq (Join-Path $sockDir "gui-sock-4242")) "and the folder it names is where the socket is looked for"
    Check ($r.reason -notlike "*a setting was not used*") "CONTROL: a good file adds nothing to the answer"
    [System.IO.File]::WriteAllText($settingsFile, (ConvertTo-Json -InputObject @{ schemaVersion = 1; settings = @{ attempts = 0; retries = 9; socketFolder = $sockDir } } -Compress))
    $script:windowReads = 0
    $r = Find-HordeWeztermSessionWindow -Pane "18" -Instance "gui-sock-4242" -Runner $runner -Windows $neverFits -ProcessStart $alive -Wait $wait
    Check ($r.state -ceq "unknown" -and $script:windowReads -eq 6) ("a setting outside its range is not used: the default of three readings is (" + $script:windowReads + " window reads)")
    Check ($r.reason -like "none of the terminal's*; a setting was not used: *attempts*" -and $r.reason -like "*retries*") "and the answer says so, naming the setting out of range and the key nobody declared"
    $k = Find-HordeWeztermSessionWindow -Pane "18" -Instance "gui-sock-4242" -Runner $runner -Windows $windows -ProcessStart $alive -Wait $wait
    Check ($k.state -ceq "known" -and $k.value.handle -eq 7002 -and $k.value.detail -like "*; a setting was not used: *attempts*") "a window that is found says it too: a setting that did nothing is never silent"
} finally { if ((Split-Path -Leaf $env:HORDE_HOME) -match '\Ahorde-test-window-home-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $env:HORDE_HOME)) { Remove-Item -LiteralPath $env:HORDE_HOME -Recurse -Force } }

Write-Host ""
Write-Host "--- the terminal writes UTF-8, whatever code page its answer was read in ---" -ForegroundColor Cyan
# THE HOST'S ONE CALL (hosts/wezterm/Act.ps1) leaves the decoding of the terminal's answer to .NET, which
# reads it in the console's code page, or the machine's when there is no console. A pane title of one
# character outside ASCII then comes back as three others and does not equal itself, and this finder
# compares titles exactly. That file is not this one's to change, so the finder mends its own listing:
# it notes the code page the answer was read in, turns the text back into the bytes the terminal
# wrote, and reads those as UTF-8. MEASURED HERE EACH RUN, through the real call: the tool standing in
# for the terminal's command prints the bytes of a listing in three alphabets, with this process set
# to a console code page that has none of them.
. (Join-Path $root "test\lib\PaneTool.ps1")
$hebrew = "" + [char]0x05E9 + [char]0x05DC + [char]0x05D5 + [char]0x05DD
$wide = @((Pane 10 16 18 ($star + " " + $hebrew + " caf" + [char]0x00E9)), (Pane 11 17 19 ($half + " other")))
$said = Listing $wide
$wideWindows = { param($processId) return @((Win 8001 ($half + " other")), (Win 8002 ($star + " " + $hebrew + " caf" + [char]0x00E9))) }
$oem = [System.Text.Encoding]::GetEncoding(437)
function Mend { param([string]$Text, $ReadAs)
    if ($null -eq (Get-Command -Name ConvertTo-HordeWeztermAnswerText -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ state = "missing"; value = $null; reason = "the finder has nothing that mends its listing" } }
    return (ConvertTo-HordeWeztermAnswerText -Text $Text -ReadAs $ReadAs) }
$saveExe = $script:HordeWeztermActExe
$script:HordeWeztermActExe = Get-HordePaneTool
$wasEncoding = $null; $raw = $null; $readIn = $null
try { $wasEncoding = [Console]::OutputEncoding; [Console]::OutputEncoding = $oem } catch { $wasEncoding = $null }
try {
    try { $readIn = [Console]::OutputEncoding } catch { $readIn = [System.Text.Encoding]::Default }
    $raw = Invoke-HordeWeztermAct -Rest @("say", [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($said))) -Target ([pscustomobject]@{ socket = (Join-Path $sockDir "gui-sock-4242"); guiPid = 4242; guiStart = "133000000000000000" })
} finally { $script:HordeWeztermActExe = $saveExe; if ($null -ne $wasEncoding) { try { [Console]::OutputEncoding = $wasEncoding } catch { } } }
Check ($raw.code -eq 0 -and $raw.out -cne $said -and $readIn.CodePage -ne 65001) ("CONTROL: read as the host's call reads it, in code page " + $readIn.CodePage + ", the listing does not equal what the terminal wrote)
$mended = Mend $raw.out $readIn
Check ($mended.state -ceq "known" -and $mended.value -ceq $said) "mended, it is what the terminal wrote, character for character, in three alphabets"
$garbledWide = { param($rest, $envMap, $target) return [pscustomobject]@{ code = 0; out = $oem.GetString([System.Text.Encoding]::UTF8.GetBytes($said)); err = ""; timedOut = $false } }
$once = Settings @{ socketFolder = $sockDir; attempts = 1; retryWaitMs = 0 }
$unmended = Find-HordeWeztermSessionWindow -Pane "18" -Instance "gui-sock-4242" -Settings $once -Runner $garbledWide -Windows $wideWindows -ProcessStart $alive -Wait $wait
Check ($unmended.state -ceq "unknown" -and $unmended.reason -like "none of the terminal's*") "CONTROL: a listing left as it was read fits no window's title, so the finder answers unknown"
$viaFinder = $null
try { $viaFinder = Find-HordeWeztermSessionWindow -Pane "18" -Instance "gui-sock-4242" -Settings $once -Runner $garbledWide -ReadAs $oem -Windows $wideWindows -ProcessStart $alive -Wait $wait } catch { $viaFinder = [pscustomobject]@{ state = "threw"; value = $null; reason = "$($_.Exception.Message)" } }
Check ($viaFinder.state -ceq "known" -and $viaFinder.value.handle -eq 8002) ("the finder mends the listing before it compares titles: the window titled in three alphabets is found (" + $viaFinder.state + ")")
$plain = Mend '[{"title":"plain"}]' $oem
Check ($plain.state -ceq "known" -and $plain.value -ceq '[{"title":"plain"}]') "text that is all ASCII is the same in every code page, and is left as it is"
$already = Mend $said ([System.Text.Encoding]::UTF8)
Check ($already.state -ceq "known" -and $already.value -ceq $said) "an answer that was read as UTF-8 is not mended a second time"
$ansi = [System.Text.Encoding]::GetEncoding(1252)
$fromAnsi = Mend ($ansi.GetString([System.Text.Encoding]::UTF8.GetBytes($said))) $ansi
Check ($fromAnsi.state -ceq "known" -and $fromAnsi.value -ceq $said) "the same from the code page a process with no console reads in"
$notUtf8 = Mend ("caf" + [char]0x00E9) $ansi
Check ($notUtf8.state -ceq "unknown" -and $notUtf8.reason -like "*is not UTF-8*") "text whose bytes are not UTF-8 is unknown, never half mended"
$lost = Mend $hebrew $oem
Check ($lost.state -ceq "unknown" -and $lost.reason -like "*code page 437*cannot be turned back*") "text holding a character its code page does not have was not read whole: unknown, never mended from what is left"
$twoByte = Mend ("caf" + [char]0x00E9) ([System.Text.Encoding]::GetEncoding(932))
Check ($twoByte.state -ceq "unknown" -and $twoByte.reason -like "*cannot be turned back*") "a code page that cannot give the terminal's bytes back is unknown, with the page named"

Write-Host ""
Write-Host "--- the port ---" -ForegroundColor Cyan
Check (@(Get-HordeHostWindowFinderFiles -Root $root | ForEach-Object { $_.Substring($root.Length + 1) }) -ccontains "hosts\wezterm\Window.ps1") "the finder file is found by folder"
$viaPort = Find-HordeSessionWindow -Seat ([pscustomobject]@{ pane = "%3"; instance = "tty3" })
Check ($viaPort.state -ceq "unknown" -and $viaPort.reason -like "wezterm: *does not number that way*") "through the port, a seat that is not this terminal's is unknown, under this host's name"
$src = [System.IO.File]::ReadAllText((Join-Path $root "hosts\wezterm\Window.ps1"))
Check (([regex]::Matches($src, 'Invoke-HordeWeztermCall -Rest')).Count -eq 1 -and $src.Contains('Invoke-HordeWeztermCall -Rest @("list", "--format", "json")')) "the finder's one call to the terminal is the listing, and there is no other"
Check (-not ($src -match 'SetWindowPos|ShowWindow|SetForegroundWindow|SendMessage|PostMessage|SetWindowLong|keybd_event|SendInput|DestroyWindow|CloseWindow')) "and of Windows it asks only what windows there are: nothing that moves, shows, types into or closes one"

Complete-HordeSuite -Success "a session's window is the one its own terminal's listing proves, or it is unknown"
