# WHICH NATIVE WINDOW SHOWS A PANE - AND DOES THE FINDER SAY "UNKNOWN" RATHER THAN GUESS?
#
# hosts/wezterm/Window.ps1's decision is a pure function of the terminal's own listing and the sizes
# and titles of its process's windows, so every case here is a fixture: one window, several, none, a
# session whose pane is gone, two windows that cannot be told apart, a title that changed while it was
# read. No terminal is touched: the listing comes from a recording runner and the windows from a block.
# THE SIZES AND TITLE SHAPES ARE THE FLEET'S OWN TERMINAL'S, read on 2026-10-07 (the section "by size"):
# the first finder, which asked a title to equal the listing's, answered unknown there for the one
# window it was built for, and no fixture written from that finder's own rule could have said so.
#
# FAIL CLOSED, as hosts/wezterm/test/test-act.ps1 does: this suite's own pin names a socket that does
# not exist, set as its first act, so a call that escaped the runner would fail to connect instead of
# reaching the terminal the suite was started from.
#
# The finding of a real window - in a terminal the scenario starts, never the one in use - is
# hosts/wezterm/test/e2e/e2e-session-window.ps1's.

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
$turn = [string][char]0x25D1
# A pane as the listing gives it. With -Cols it has a size, as the terminal of 2026-10-07 gave one: cells
# of 14 x 32 pixels, the pane's own columns and lines, and where it starts in its tab.
function Pane { param([int]$Window, [int]$Tab, [int]$Id, [string]$Title, [bool]$Active = $true, [bool]$Zoomed = $false, [int]$Cols = 0, [int]$Lines = 0, [int]$Left = 0, [int]$Top = 0)
    $p = [ordered]@{ window_id = $Window; tab_id = $Tab; pane_id = $Id; workspace = "default"; title = $Title; cwd = "file:///C:/work/"; is_active = $Active; is_zoomed = $Zoomed; tty_name = $null }
    if ($Cols -gt 0) { $p["size"] = [ordered]@{ rows = $Lines; cols = $Cols; pixel_width = (14 * $Cols); pixel_height = (32 * $Lines); dpi = 144 }; $p["left_col"] = $Left; $p["top_row"] = $Top }
    return $p }
function Listing { param([object[]]$Panes) return (ConvertTo-Json -InputObject @($Panes) -Depth 4 -Compress) }
function Win { param([long]$Handle, [string]$Title, [long]$Width = 0, [long]$Height = 0) return [pscustomobject]@{ handle = $Handle; title = $Title; width = $Width; height = $Height } }
function Rows { param([object[]]$Panes) return @((Read-HordeWeztermWindowList -Raw (Listing $Panes)).value) }
function Pick { param([object[]]$Panes, [string]$Pane, [object[]]$Native, [object[]]$After = @()) return (Select-HordeWeztermSessionWindow -Rows (Rows $Panes) -Pane $Pane -Native $Native -NativeAfter $After) }

# A fleet as it was measured on 2026-10-06, cut down: the holder of a role ("keeper") alone in window 10, an
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
# ONE WINDOW ID LISTED AND ONE WINDOW IN THE PROCESS: THE TITLE NEED NOT FIT, ON PURPOSE (review of
# 2026-10-06, finding C3, "taken without looking at its title"). The proof here is the count - the
# terminal says it has one window and its process shows one - and a count does not rest on a title,
# which is text a session sets and the weaker evidence of the two. Asking the title to fit as well
# would turn a certain answer into unknown for every terminal that titles its windows its own way.
# What the count can get wrong is a window opening or closing as it is read, and that is what the
# second reading is for (below): the count must hold twice.
Check ($one.state -ceq "known" -and $one.value.handle -eq 4100 -and $one.value.window -ceq "0" -and $one.value.detail -ceq "the terminal has one window") "one window listed and one terminal window in the process: that window, whatever its title"
$oneTwoTabs = Pick @((Pane 0 0 0 "first"), (Pane 0 1 1 "second")) "1" @((Win 4100 "[1/2] first"))
Check ($oneTwoTabs.state -ceq "known" -and $oneTwoTabs.value.handle -eq 4100) "a pane in a tab that is not in front is still in that one window"

Write-Host ""
Write-Host "--- several windows, and nothing known of their sizes: told apart by the title each carries ---" -ForegroundColor Cyan
$keeper = Pick $fleet "18" $fleetWindows
Check ($keeper.state -ceq "known" -and $keeper.value.handle -eq 7002 -and $keeper.value.window -ceq "10") "the keeper's pane is in window 10, and the one terminal window that carries that window's pane's title is it"
$worker = Pick $fleet "21" $fleetWindows
Check ($worker.state -ceq "known" -and $worker.value.handle -eq 7001 -and $worker.value.window -ceq "11") "a pane in a three-tab window is found by the window's title, which carries the title of whichever tab is in front"
$split = Pick $fleet "23" $fleetWindows
Check ($split.state -ceq "known" -and $split.value.handle -eq 7003) "a pane that is not its tab's active pane is in the window titled after the pane that is"
$leftTitled = Pick $fleet "23" @((Win 7001 ("[2/3] " + $star + " worker one")), (Win 7002 ($star + " keeper")), (Win 7003 ($star + " left half")), (Win 7004 ($star + " another")))
Check ($leftTitled.state -ceq "unknown") "and a window titled after a pane that is NOT its tab's active pane is not that window: the terminal never titles one so"
$lone = Pick $fleet "18" @((Win 7001 ("[2/3] " + $star + " worker one")))
Check ($lone.state -ceq "unknown" -and $lone.reason -like "none of the terminal's 1 windows*") "with several window ids listed and only one terminal window on screen, that window is not taken for the session's unless its title says so"
$zoomRows = @((Pane 1 1 1 "editor" $true $true), (Pane 2 2 2 "other"))
$zoomed = Pick $zoomRows "1" @((Win 501 "[Z] editor"), (Win 502 "other"))
Check ($zoomed.state -ceq "known" -and $zoomed.value.handle -eq 501) "a zoomed pane's window carries [Z] before its title, and is found: what the terminal writes around a pane's title is not asked for"
# A ZOOMED PANE IN A WINDOW OF SEVERAL TABS: [Z] comes FIRST, then the tab count. Measured 2026-10-07
# against an isolated instance (20240203-110809-5046fc22): a two-tab window whose front tab's active pane
# was zoomed was titled "[Z] [1/2] PING.EXE". The first finder expected the other order, unmeasured
# (review of 2026-10-06, finding C4), and so answered unknown for such a window: a rule about what
# stands around a pane's title is a rule about a format this finder does not control, and it has none.
$zoomTabs = @((Pane 1 1 1 "editor" $true $true), (Pane 1 2 3 "logs"), (Pane 2 4 2 "other"))
$zoomedTab = Pick $zoomTabs "1" @((Win 501 "[Z] [1/2] editor"), (Win 502 "other"))
Check ($zoomedTab.state -ceq "known" -and $zoomedTab.value.handle -eq 501) ("in a window of two tabs the zoomed pane's window is titled [Z] and then the tab count, as the terminal was measured to write it (" + $zoomedTab.state + ")")
Check ((Pick $zoomTabs "1" @((Win 501 "[1/2] [Z] editor"), (Win 502 "other"))).value.handle -eq 501) "and written in the other order, or in a format of the person's own, it is found the same"
Check ((Pick $zoomTabs "3" @((Win 501 "[2/2] logs"), (Win 502 "other"))).value.handle -eq 501) "CONTROL: with the tab that is not zoomed in front, the same window is titled by the count alone"

Write-Host ""
Write-Host "--- a title that changed while it was read ---" -ForegroundColor Cyan
$spinning = @((Win 7001 ("[2/3] " + $star + " worker one")), (Win 7002 ($half + " keeper")), (Win 7003 ($star + " right half")), (Win 7004 ($star + " another")))
$stale = Pick $fleet "18" $spinning
Check ($stale.state -ceq "unknown" -and $stale.reason -like "none of the terminal's 4 windows carries the title of the window of pane 18, and sizes do not tell them apart (the listing gives no size for pane 18)*") "read once, with the title a moment out of step with the listing and no sizes to go by: unknown, and says so"
$both = Pick $fleet "18" $spinning $fleetWindows
Check ($both.state -ceq "known" -and $both.value.handle -eq 7002) "read before and after the listing, a match in either reading counts"

Write-Host ""
Write-Host "--- never the likeliest ---" -ForegroundColor Cyan
$twins = @((Pane 1 1 1 "PowerShell"), (Pane 2 2 2 "PowerShell"), (Pane 3 3 3 "notes"))
$twinWindows = @((Win 601 "PowerShell"), (Win 602 "PowerShell"), (Win 603 "notes"))
$twin = Pick $twins "1" $twinWindows
Check ($twin.state -ceq "unknown" -and $twin.reason -like "2 of the terminal's windows carry the title of the window of pane 1, and one is never chosen over another") "two windows with the session's window's title: unknown, and neither is chosen"
Check ((Pick $twins "3" $twinWindows).value.handle -eq 603) "CONTROL: the window beside the twins, titled alone, is still found"
$shadow = @((Pane 1 1 1 "build"), (Pane 2 2 2 "build"), (Pane 3 3 3 "notes"))
$shadowed = Pick $shadow "1" @((Win 601 "build"), (Win 603 "notes"))
Check ($shadowed.state -ceq "unknown" -and $shadowed.reason -like "*carries the title of another of the terminal's windows too*") "one window fits, but it fits another window id as well (whose own window was not seen): unknown"
# NO RULE ABOUT THE TAB COUNT. The first finder refused a title whose count was not the listing's; the
# count is the terminal's own decoration, and a person's format may leave it out or write it otherwise.
$wrongTabs = Pick $fleet "21" @((Win 7001 ("[2/4] " + $star + " worker one")), (Win 7002 ($star + " keeper")))
Check ($wrongTabs.state -ceq "known" -and $wrongTabs.value.handle -eq 7001) "a title with another tab count around the pane's title still carries it"
$bare = Pick $fleet "21" @((Win 7001 ($star + " worker one")), (Win 7002 ($star + " keeper")))
Check ($bare.state -ceq "known" -and $bare.value.handle -eq 7001) "and so does the bare pane title, on a window that has more than one tab"
$untitled = Pick @((Pane 1 1 1 ""), (Pane 2 2 2 "notes")) "1" @((Win 601 "anything at all"), (Win 602 "notes"))
Check ($untitled.state -ceq "unknown" -and $untitled.reason -like "none of the terminal's 2 windows carries the title*") "a pane with no title is carried by no window: the empty text is inside every title"
$caseOnly = Pick $twins "3" @((Win 601 "PowerShell"), (Win 602 "PowerShell"), (Win 603 "Notes"))
Check ($caseOnly.state -ceq "unknown") "titles are compared exactly: Notes is not notes"

Write-Host ""
Write-Host "--- by size: the shapes of the fleet's own terminal, where the first finder answered unknown ---" -ForegroundColor Cyan
# READ 2026-10-07, read-only, from the terminal the fleet runs in (16 windows; nine are kept here, with
# their sizes as they were and their titles renamed). Its cells were 14 x 32 pixels. The window of pane
# 18 - the session the companion window is for - was 180 x 39 cells in a client area of 2560 x 1334;
# the next size down 178 x 36 in 2520 x 1248; three windows 179 x 38 in 2536 x 1310; windows of 80 x 24
# in 1148 x 842 and of 89 x 17 in 1274 x 618. The session was working, and its title's first character
# was a different one in each of three readings 300 ms apart: U+25D0 on its window, U+25D1 in the
# listing, U+2733 on its window again. Window 14 is given a tab split left and right, and window 6 one
# split top and bottom, as the terminal lists such tabs.
$real = @(
    (Pane 10 16 18 ($turn + " keeper") $true $false 180 39), (Pane 10 40 42 ($star + " device check") $true $false 180 39),
    (Pane 0 0 0 ($star + " telemetry") $true $false 178 36),
    (Pane 1 1 3 ($star + " lanes script") $true $false 179 38), (Pane 1 2 4 ($star + " gates") $true $false 179 38),
    (Pane 6 9 11 ($star + " voice") $true $false 179 19), (Pane 6 9 47 ($star + " voice log") $false $false 179 18 0 20),
    (Pane 14 24 26 ($star + " forms") $true $false 89 38), (Pane 14 24 46 ($star + " forms log") $false $false 89 38 90 0),
    (Pane 11 17 19 ($star + " capture") $true $false 80 24), (Pane 11 29 31 ($star + " step two") $true $false 80 24),
    (Pane 13 23 25 ($half + " prompts") $true $false 80 24),
    (Pane 7 10 12 ($star + " shell") $true $false 89 17), (Pane 15 25 27 ($star + " shell") $true $false 89 17)
)
function RealWindows { param([string]$KeeperGlyph = $half, [hashtable]$Sizes = @{}, [hashtable]$Titles = @{}, [long[]]$Without = @())
    $w = @(
        @(460684, ("[1/2] " + $KeeperGlyph + " keeper"), 2560, 1334), @(394602, ($star + " telemetry"), 2520, 1248),
        @(395012, ("[1/2] " + $star + " lanes script"), 2536, 1310), @(1443386, ($star + " voice"), 2536, 1310), @(460556, ($star + " forms"), 2536, 1310),
        @(722212, ("[2/2] " + $star + " step two"), 1148, 842), @(134586, ($turn + " prompts"), 1148, 842),
        @(4588442, ($star + " shell"), 1274, 618), @(199664, ($star + " shell"), 1274, 618))
    return @($w | Where-Object { $Without -notcontains [long]$_[0] } | ForEach-Object {
        $size = @($_[2], $_[3]); if ($Sizes.ContainsKey([long]$_[0])) { $size = $Sizes[[long]$_[0]] }
        $title = $_[1]; if ($Titles.ContainsKey([long]$_[0])) { $title = $Titles[[long]$_[0]] }
        Win ([long]$_[0]) $title ([long]$size[0]) ([long]$size[1]) }) }
$before = RealWindows
$after = RealWindows -KeeperGlyph $star
$listedTitle = @(Rows $real | Where-Object { $_.pane -ceq "18" })[0].title
Check (@(@($before) + @($after) | Where-Object { $_.handle -eq 460684 -and $_.title.Contains($listedTitle) }).Count -eq 0) "CONTROL: the working session's window carries, in neither reading, the title the listing gives its pane - the three were read at three moments"
$live = Pick $real "18" $before $after
Check ($live.state -ceq "known" -and $live.value.handle -eq 460684 -and $live.value.window -ceq "10") ("THE LIVE CASE: a title that changes between the readings while everything else agrees - the window is found, by its size (" + $live.state + $(if ($live.state -cne "known") { ": " + $live.reason } else { "" }) + ")")
Check ($live.state -ceq "known" -and $live.value.detail -ceq "the one of the terminal's 9 windows with the size of the pane's window (180 x 39 cells)") "and the answer says what proved it: the one window of that size, in cells"
Check ((Pick $real "42" $before $after).value.handle -eq 460684) "the pane of that window's other tab is in the same window"
Check ((Pick $real "0" $before $after).value.handle -eq 394602) "the window two columns narrower and three lines shorter is another window, and is not taken for it"
$third = Pick $real "11" $before $after
Check ($third.state -ceq "known" -and $third.value.handle -eq 1443386 -and $third.value.detail -ceq "the one of 3 windows that could be the pane's window by size (179 x 38 cells) that carries its title") "three windows of one size: the size leaves three, and the title each carries says which"
Check ((Pick $real "47" $before $after).value.handle -eq 1443386) "a tab split top and bottom is as tall as its panes reach: 19 lines, a divider, 18 - the window of 38"
$splitWide = Pick $real "46" $before $after
Check ($splitWide.state -ceq "known" -and $splitWide.value.handle -eq 460556) ("a tab split left and right is as wide as its panes reach: 89 columns, a divider, 89 - the window of 179, not one of 89 (" + $splitWide.state + ")")
$outOfStep = Pick $real "25" $before $after
Check ($outOfStep.state -ceq "unknown" -and $outOfStep.reason -ceq "2 of the terminal's 9 windows could be the window of pane 25 by size (80 x 24 cells), and none of them carries its title, so which it is cannot be told" -and $null -ne $outOfStep.PSObject.Properties["readAgain"]) "two windows of one size and the session's title out of step: unknown, said in sizes, and marked to be read again"
$equal = Pick $real "12" $before $after
Check ($equal.state -ceq "unknown" -and $equal.reason -ceq "2 of the terminal's windows carry the title of the window of pane 12 and could be it by size (89 x 17 cells), and one is never chosen over another" -and $null -eq $equal.PSObject.Properties["readAgain"]) "TWO WINDOWS OF EQUAL SIZE AND NOTHING ELSE TO TELL THEM APART: unknown, and neither is chosen"
$elsewhere = RealWindows -Titles @{ [long]394602 = ($half + " prompts"); [long]134586 = ($half + " prompts") }
$inStep = Pick $real "25" $elsewhere $elsewhere
Check ($inStep.state -ceq "known" -and $inStep.value.handle -eq 134586) "a window of another size that carries the same title is not counted: the title is asked only of windows of the right size"
# THE PADDING IS NOT ASSUMED. The same windows under another padding - ten pixels wider, six taller, as
# another font or border would give - are found the same.
$padded = RealWindows -Sizes @{ [long]460684 = @(2570, 1340); [long]394602 = @(2530, 1254); [long]395012 = @(2546, 1316); [long]1443386 = @(2546, 1316); [long]460556 = @(2546, 1316); [long]722212 = @(1158, 848); [long]134586 = @(1158, 848); [long]4588442 = @(1284, 624); [long]199664 = @(1284, 624) }
Check ((Pick $real "18" $padded $padded).value.handle -eq 460684 -and (Pick $real "0" $padded $padded).value.handle -eq 394602) "under another padding the windows are found the same: the padding is worked out from the windows, never written down"

Write-Host ""
Write-Host "--- by size: a window with no size, and sizes that say nothing ---" -ForegroundColor Cyan
# A MINIMISED WINDOW HAS NO CLIENT SIZE (0 x 0). It is still the session's window.
$otherMin = RealWindows -Sizes @{ [long]394602 = @(0, 0) }
Check ((Pick $real "18" $otherMin $otherMin).value.detail -ceq "the one of the terminal's 9 windows with the size of the pane's window (180 x 39 cells)") "another window minimised: the session's window is still the one of its size"
$wantedMin = RealWindows -Sizes @{ [long]460684 = @(0, 0) }
$leftOver = Pick $real "18" $wantedMin $wantedMin
Check ($leftOver.state -ceq "known" -and $leftOver.value.handle -eq 460684 -and $leftOver.value.detail -ceq "the one of the terminal's 9 windows that is not another's by size: the pane's window has no one size on screen (minimised, or its size was changing)") ("THE WANTED WINDOW MINIMISED, every other window another's by size, as many windows as listed: it is the one left, and the answer says it has no size (" + $leftOver.state + ")")
$zero = Pick $real "18" (RealWindows -Sizes @{ [long]460684 = @(2560, 0) }) (RealWindows -Sizes @{ [long]460684 = @(2560, 0) })
Check ($zero.state -ceq "known" -and $zero.value.detail -like "*has no one size on screen*") "a client area of no height is no size, the same"
$twoMin = RealWindows -Sizes @{ [long]460684 = @(0, 0); [long]394602 = @(0, 0) }
$either = Pick $real "18" $twoMin $twoMin
Check ($either.state -ceq "unknown" -and $either.reason -ceq "2 of the terminal's 9 windows could be the window of pane 18 by size (180 x 39 cells), and none of them carries its title, so which it is cannot be told") "the wanted window and one other minimised, its title out of step: either could be it - unknown"
$twoMinInStep = RealWindows -KeeperGlyph $turn -Sizes @{ [long]460684 = @(0, 0); [long]394602 = @(0, 0) }
$byTitle = Pick $real "18" $twoMinInStep $twoMinInStep
Check ($byTitle.state -ceq "known" -and $byTitle.value.handle -eq 460684 -and $byTitle.value.detail -ceq "the one of 2 windows that could be the pane's window by size (180 x 39 cells) that carries its title") "and when its title is in step, the title says which of the two it is"
$fewer = RealWindows -Sizes @{ [long]460684 = @(0, 0) } -Without @([long]199664)
$notLeft = Pick $real "18" $fewer $fewer
Check ($notLeft.state -ceq "unknown" -and $notLeft.reason -like "1 of the terminal's 8 windows could be the window of pane 18 by size*") "the one left over is believed only when the process has as many windows as the listing has window ids: with one fewer, the session's window may be the one not seen"
$resizing = Pick $real "18" (RealWindows) (RealWindows -Sizes @{ [long]460684 = @(2400, 1200) })
Check ($resizing.state -ceq "known" -and $resizing.value.detail -like "*has no one size on screen*") "a size that is not the same before and after the listing is no size: it is never matched as either"
$gone = RealWindows -Without @([long]394602)
Check ((Pick $real "18" $gone $gone).value.handle -eq 460684) "a window missing from the process does not undo the others: the one window of the session's size is still it"
$noneOfSize = Pick $real "0" $gone $gone
Check ($noneOfSize.state -ceq "unknown" -and $noneOfSize.reason -ceq "none of the terminal's 8 windows has the size of the window of pane 0 (178 x 36 cells), so it is not on screen as the terminal lists it" -and $null -ne $noneOfSize.PSObject.Properties["readAgain"]) "and the pane whose window is the missing one has no window: none is of its size"
# SIZES THAT SAY NOTHING: then only titles are left, and the answer says why sizes were not used.
$stranger = @(RealWindows) + @((Win 999 "a window the listing does not have" 800 600))
$noPadding = Pick $real "18" $stranger $stranger
Check ($noPadding.state -ceq "unknown" -and $noPadding.reason -like "none of the terminal's 10 windows carries the title of the window of pane 18, and sizes do not tell them apart (no one padding explains the sizes of the terminal's windows)*") "a window whose size is no listed window's under any padding: sizes are not used at all, and the answer says so"
Check ((Pick $real "11" $stranger $stranger).value.detail -ceq "the one of the terminal's 10 windows that carries the title of its pane") "and a window whose title is in step is then found by title alone"
$sizeless = @($real | ForEach-Object { if ($_.pane_id -eq 42) { Pane 10 40 42 ($star + " device check") } else { $_ } })
$noSize = Pick $sizeless "18" $before $after
Check ($noSize.state -ceq "unknown" -and $noSize.reason -like "*sizes do not tell them apart (the listing gives no size for pane 42)*") "a listing that gives one pane no size gives no window a size: never half used"
$uneven = @($real | ForEach-Object { if ($_.pane_id -eq 42) { Pane 10 40 42 ($star + " device check") $true $false 180 38 } else { $_ } })
Check ((Pick $uneven "18" $before $after).reason -like "*sizes do not tell them apart (the tabs of window 10 are not of one size)*") "a window whose tabs are not of one size has no size"
$mixed = Rows @((Pane 1 1 1 "a" $true $false 80 24), (Pane 1 1 2 "b" $false $false 80 24 81 0))
$mixed[1].shape.cellWidth = 7
Check ((Get-HordeWeztermWindowShapes -Rows $mixed).why -ceq "the panes of window 1 do not have cells of one size") "nor has a window whose panes have cells of two sizes"
function Shape { param([string]$Size, [string]$Rest = '"left_col":0,"top_row":0') return @((Read-HordeWeztermWindowList -Raw ('[{"window_id":0,"tab_id":0,"pane_id":1,"title":"t","is_active":true,"size":' + $Size + ',' + $Rest + '}]')).value)[0].shape }
$whole = Shape '{"rows":24,"cols":80,"pixel_width":1120,"pixel_height":768,"dpi":144}'
Check ($null -ne $whole -and $whole.cols -eq 80 -and $whole.rows -eq 24 -and $whole.cellWidth -eq 14 -and $whole.cellHeight -eq 32 -and $whole.left -eq 0 -and $whole.top -eq 0) "CONTROL: a pane's size is read as the terminal gives it: columns, lines, and cells of 14 x 32"
Check ($null -eq (Shape '{"rows":24,"cols":80,"pixel_width":1121,"pixel_height":768}')) "a width that is not a whole number of cells is no size"
Check ($null -eq (Shape '{"rows":24,"cols":80,"pixel_width":1120,"pixel_height":770}')) "nor a height that is not"
Check ($null -eq (Shape '{"rows":24,"cols":80,"pixel_width":1120,"pixel_height":768}' '"top_row":0')) "a pane that does not say where it starts in its tab has no size: a split tab would look as narrow as one pane"
Check ($null -eq (Shape '{"rows":24,"cols":"80","pixel_width":1120,"pixel_height":768}') -and $null -eq (Shape '{"rows":0,"cols":80,"pixel_width":1120,"pixel_height":768}') -and $null -eq (Shape '"80x24"')) "a size written as text, or of no lines, is no size - and the listing is still read"
# ONE DIRECTION OF THE PADDING, on its own: a client 1148 wide, and listed windows 80 and 81 columns wide.
$ways = @(Get-HordeWeztermAxisFits -Lengths @([long]1148) -Spans @("1120|14", "1134|14"))
Check ($ways.Count -eq 2 -and @($ways | Where-Object { @($_["1148"]).Count -ne 1 }).Count -eq 0 -and ((@($ways | ForEach-Object { $_["1148"] }) | Sort-Object) -join " ") -ceq "1120|14 1134|14") "a width fits a span when less than one cell is left over: 1148 is 80 columns under a padding of 28 and 81 under one of 14, never both at once"
# A DOUBT WIDENS. One window with a size, one minimised, and listed windows of 80 and 81 columns: the
# sized window is the first under one padding and the second under another, so size proves nothing.
$near = @((Pane 1 1 1 "first" $true $false 80 24), (Pane 2 2 2 "second" $true $false 81 24))
$doubt = Pick $near "1" @((Win 71 "busy" 1162 842), (Win 72 "busy too" 0 0))
Check ($doubt.state -ceq "unknown" -and $doubt.reason -like "2 of the terminal's 2 windows could be the window of pane 1 by size*") "one sized window that two paddings would give to either listed window is not taken by size"
$narrow = @((Pane 1 1 1 "first" $true $false 80 24), (Pane 2 2 2 "second" $true $false 83 24))
$fitsOne = Pick $narrow "1" @((Win 71 "busy" 1148 842), (Win 72 "busy too" 0 0))
Check ($fitsOne.state -ceq "known" -and $fitsOne.value.handle -eq 71 -and $fitsOne.value.detail -like "*with the size of the pane's window (80 x 24 cells)") "a window narrower than a listed window's cells cannot be that window: a padding below zero is not a padding"
# Two windows of one size on screen, and listed windows of two sizes: no padding gives each its own.
$crowd = Pick $near "1" @((Win 71 "busy" 1162 842), (Win 72 "busy too" 1162 842))
Check ($crowd.state -ceq "unknown" -and $crowd.reason -like "*sizes do not tell them apart (no one padding explains the sizes of the terminal's windows)*") "two windows of one size cannot both be the one listed window of that size: such a padding explains nothing, and is not used"

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
Check ($script:calls.Count -eq 2 -and @($script:calls | Where-Object { $_ -cne "list --format json" }).Count -eq 0) "the terminal is asked one thing, its list of panes, once for each of two readings - nothing that types, moves or closes"
Check ($found.value.detail -ceq "the one of the terminal's 4 windows that carries the title of its pane, and again on a second reading 300 ms later" -and ($script:waits -join ",") -ceq "300") "the second reading is taken after the wait its settings give, 300 ms unless a person says otherwise, and the answer says it held twice"
Check ($script:targets[0].socket -ceq (Join-Path $sockDir "gui-sock-4242") -and "" + $script:targets[0].guiPid -ceq "4242" -and $script:targets[0].guiStart -ceq "133000000000000000") "and it is asked as a named terminal: the instance's socket, its gui and that gui's start time"
Check ($script:windowReads -eq 4 -and $script:pidAsked -eq 4242) "the windows read are that gui process's own, before each listing and after it"

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
Check ($r.state -ceq "known" -and $r.value.handle -eq 7002 -and $script:windowReads -eq 6) "a title that fitted nothing on the first reading is read again, found, and found once more"
Check (($script:waits -join ",") -ceq "25,300") "after the wait its settings give before a retry, and then the wait before the second reading"
$script:windowReads = 0; $script:waits.Clear()
$never = { param($processId) $script:windowReads++; return $spinning }
$r = Find "18" "gui-sock-4242" -W $never
Check ($r.state -ceq "unknown" -and $r.reason -like "none of the terminal's*" -and $script:windowReads -eq 6 -and ($script:waits -join ",") -ceq "25,25") "one that never fits is read three times and is then unknown"
$script:windowReads = 0
$r = Find "99" "gui-sock-4242" -W $never
Check ($r.state -ceq "unknown" -and $script:windowReads -eq 2) "a pane that is not listed is not read again: reading again cannot bring it back"

Write-Host ""
Write-Host "--- a window is believed only when a second reading, a moment later, names it again ---" -ForegroundColor Cyan
# THE REVIEW'S CASE (2026-10-06, finding C2). Window 100 truly shows pane 0 and window 200 pane 1. Both
# panes have just been retitled; the listing is newer than both readings of the windows, and pane 0's
# new title is what window 200 still shows. One reading names window 200: known, and wrong.
$staleRows = @((Pane 1 1 0 "deploy"), (Pane 2 2 1 "logs"))
$staleWindows = @((Win 100 "build"), (Win 200 "deploy"))
$trueWindows = @((Win 100 "deploy"), (Win 200 "logs"))
$wrong = Pick $staleRows "0" $staleWindows $staleWindows
Check ($wrong.state -ceq "known" -and $wrong.value.handle -eq 200) "CONTROL: one reading whose titles are both stale names window 200, which does not hold the pane - one reading is a likelihood, not a proof"
$right = Pick $staleRows "0" $trueWindows $trueWindows
Check ($right.state -ceq "known" -and $right.value.handle -eq 100) "CONTROL: read when the titles have caught up, the same listing names window 100"
function Twice { param($First, $Second)
    if ($null -eq (Get-Command -Name Compare-HordeWeztermWindowReadings -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ state = "missing"; value = $null; reason = "the finder has nothing that holds two readings against each other" } }
    return (Compare-HordeWeztermWindowReadings -First $First -Second $Second -ApartMs 300) }
$held = Twice $wrong $right
Check ($held.state -ceq "unknown" -and $held.reason -ceq "two readings 300 ms apart named different windows for the pane (200, then 100), so neither is believed") ("the two readings disagree: unknown, with both windows named and neither chosen (" + $held.state + ")")
$same = Twice $right (Pick $staleRows "0" $trueWindows $trueWindows)
Check ($same.state -ceq "known" -and $same.value.handle -eq 100 -and $same.value.window -ceq "1" -and $same.value.detail -ceq "the one of the terminal's 2 windows that carries the title of its pane, and again on a second reading 300 ms later") "the two readings name the same window for the same pane: known, and it says it held twice"
$gone = Twice $right (Pick $staleRows "0" @((Win 100 "mid redraw"), (Win 200 "logs")))
Check ($gone.state -ceq "unknown" -and $gone.reason -like "a window was found for the pane and was not found again on a second reading 300 ms later (none of the terminal's 2 windows*") "found once and not found again: unknown, with what the second reading said"
$renumbered = Twice $right (Pick @((Pane 7 1 0 "deploy"), (Pane 2 2 1 "logs")) "0" $trueWindows $trueWindows)
Check ($renumbered.state -ceq "unknown" -and $renumbered.reason -ceq "two readings 300 ms apart put the pane in different windows of the terminal's own numbering (1, then 7), so neither is believed") "the same native window, but the terminal's own number for the pane's window changed between the readings: unknown"
$never1 = Twice (Pick $staleRows "9" $trueWindows) $right
Check ($never1.state -ceq "unknown" -and $never1.reason -like "the terminal lists no pane 9*") "a first reading that found nothing is the answer as it is: there is nothing for a second to hold"
# Through the finder: the whole reading - windows, listing, windows - is taken twice.
$script:listing = Listing $staleRows
$catching = { param($processId) $script:windowReads++; if ($script:windowReads -le 2) { return $staleWindows }; return $trueWindows }
$script:windowReads = 0; $script:waits.Clear(); $script:calls.Clear()
$r = Find "0" "gui-sock-4242" -W $catching -Attempts 1
Check ($r.state -ceq "unknown" -and $r.reason -like "two readings 300 ms apart named different windows for the pane (200, then 100)*" -and $script:calls.Count -eq 2 -and $script:windowReads -eq 4 -and ($script:waits -join ",") -ceq "300") ("THE REVIEW'S CASE, through the finder: the stale match is not believed - " + $r.state + ", " + $script:calls.Count + " listings, waits " + ($script:waits -join ","))
$script:windowReads = 0; $script:waits.Clear()
$r = Find "0" "gui-sock-4242" -W $catching
Check ($r.state -ceq "known" -and $r.value.handle -eq 100 -and $script:windowReads -eq 8 -and ($script:waits -join ",") -ceq "300,25,300") "and read again, the window that holds twice is the one that truly shows the pane"
$script:windowReads = 0
$r = Find "0" "gui-sock-4242" -W { param($processId) $script:windowReads++; return $staleWindows } -Attempts 1
Check ($r.state -ceq "known" -and $r.value.handle -eq 200) "THE LIMIT, WRITTEN DOWN AS A CHECK: titles that stay stale in the same way through both readings are still believed; the second reading shortens the time a coincidence must last, it does not end it"
# One window id and one window (finding C3, above): the count must hold on the second reading too.
$script:listing = Listing @((Pane 0 0 0 "cmd.exe"))
$script:windowReads = 0
$r = Find "0" "gui-sock-4242" -W { param($processId) $script:windowReads++; return @((Win 4100 "a title that fits nothing")) } -Attempts 1
Check ($r.state -ceq "known" -and $r.value.handle -eq 4100 -and $r.value.detail -ceq "the terminal has one window, and again on a second reading 300 ms later") "one window id and one window, on both readings: that window, by count, though its title fits nothing"
$script:windowReads = 0
$r = Find "0" "gui-sock-4242" -W { param($processId) $script:windowReads++; if ($script:windowReads -le 2) { return @((Win 4100 "a title that fits nothing")) }; return @((Win 4100 "a title that fits nothing"), (Win 4200 "one that has just opened")) } -Attempts 1
Check ($r.state -ceq "unknown" -and $r.reason -like "a window was found for the pane and was not found again on a second reading 300 ms later*") "one window on the first reading and two on the second: the count did not hold, and no title says which it is - unknown"
# THE LIVE CASE, THROUGH THE FINDER: the session's title is another one every time its window is read,
# and never the listing's. Two listings, one wait, and the window is known.
$script:listing = Listing $real
$script:windowReads = 0; $script:waits.Clear(); $script:calls.Clear()
$glyphs = @($half, $star, $turn + "x", $half)
$r = Find "18" "gui-sock-4242" -W { param($processId) $script:windowReads++; return (RealWindows -KeeperGlyph $glyphs[($script:windowReads - 1) % 4]) } -Attempts 1
Check ($r.state -ceq "known" -and $r.value.handle -eq 460684 -and $script:calls.Count -eq 2 -and $script:windowReads -eq 4 -and ($script:waits -join ",") -ceq "300") ("THE LIVE CASE, through the finder: a title that never holds still does not matter - " + $r.state + ", " + $script:calls.Count + " listings, " + $script:windowReads + " readings of the windows")
Check ($r.state -ceq "known" -and $r.value.detail -ceq "the one of the terminal's 9 windows with the size of the pane's window (180 x 39 cells), and again on a second reading 300 ms later") "and it held on the second reading, by size both times"
$script:listing = Listing $fleet

Write-Host ""
Write-Host "--- its numbers and its folder are settings, with one table and one file ---" -ForegroundColor Cyan
$declared = @($script:HordeWeztermWindowSettings.settings | ForEach-Object { $_.name + "=" + $_.default })
Check (($declared -join " ") -ceq "attempts=3 retryWaitMs=200 confirmWaitMs=300 socketFolder=") ("the finder declares its settings once, with these defaults (" + ($declared -join " ") + ")")
$none = Get-HordeWeztermWindowSettings
Check ($none.state -ceq "defaults" -and $none.values.attempts -eq 3 -and $none.values.retryWaitMs -eq 200 -and $none.values.confirmWaitMs -eq 300 -and $none.values.socketFolder -ceq "" -and @($none.findings).Count -eq 0 -and -not (Test-Path -LiteralPath $env:HORDE_HOME)) "with no file under the home every setting is its default, nothing is found wrong, and nothing was made"
# The terminal's own place, when the folder is left out: this user's profile. The recording runner is
# handed the socket and nothing is opened.
$script:targets.Clear()
$own = Find-HordeWeztermSessionWindow -Pane "18" -Instance "gui-sock-4242" -Runner $runner -Windows $windows -ProcessStart $alive -Wait $wait
# WHERE THAT PLACE IS belongs to the host's one owner of it, Get-HordeWeztermSockDir in hosts/wezterm/Act.ps1:
# the finder hands its default to that function, and this suite asks the same function what it says.
$ownPlace = Get-HordeWeztermSockDir
Check ($own.state -ceq "known" -and $script:targets[0].socket -ceq (Join-Path $ownPlace "gui-sock-4242")) "with no folder set, the instance's socket is looked for in the terminal's own place, as the host's one owner of that place says it"
Check ((Get-HordeWeztermWindowSockDir -Configured "") -ceq $ownPlace -and (Get-HordeWeztermWindowSockDir -Configured $sockDir) -ceq $sockDir) "one function says where the sockets are: the folder a person set, or the terminal's own place"
# AND THE PLACE'S WORDS ARE WRITTEN NOWHERE IN THIS UNIT (review of 2026-10-06, finding C7: they were
# written twice). The words are taken from the owner itself, under a profile folder invented here, so
# this suite does not write them either; and the same search must find them in the act file, where
# they are known to be, before finding none here means anything.
$probeProfile = Join-Path $env:TEMP "horde-test-window-no-such-profile"
$placeWords = ("" + (Get-HordeWeztermSockDir -ProfileDir $probeProfile)).Substring($probeProfile.Length).TrimStart("\")
$finderSrc = [System.IO.File]::ReadAllText((Join-Path $root "hosts\wezterm\Window.ps1"))
$actSrc = [System.IO.File]::ReadAllText((Join-Path $root "hosts\wezterm\Act.ps1"))
Check ($placeWords.Length -gt 0 -and $actSrc.Contains($placeWords)) ("CONTROL: the search finds the place's words where they are written, in the act file (" + $placeWords + ")")
Check (-not $finderSrc.Contains($placeWords) -and -not $finderSrc.Contains('$env:USERPROFILE') -and $finderSrc.Contains('return (Get-HordeWeztermSockDir)')) "the finder writes the terminal's own place nowhere: its default is handed to the host's one owner of it"
foreach ($mine in @("hosts\wezterm\test\test-window.ps1", "hosts\wezterm\test\mutations\window.psd1")) {
    Check (-not [System.IO.File]::ReadAllText((Join-Path $root $mine)).Contains($placeWords)) ("nor does " + ($mine -replace "\\", "/"))
}
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
    Check ((Get-HordeWeztermWindowSettings).state -ceq "read") "CONTROL: that file passed every check, and the finder went on with what it says"
    [System.IO.File]::WriteAllText($settingsFile, (ConvertTo-Json -InputObject @{ schemaVersion = 1; settings = @{ confirmWaitMs = 60; socketFolder = $sockDir } } -Compress))
    $script:waits.Clear()
    $r = Find-HordeWeztermSessionWindow -Pane "18" -Instance "gui-sock-4242" -Runner $runner -Windows $windows -ProcessStart $alive -Wait $wait
    Check ($r.state -ceq "known" -and ($script:waits -join ",") -ceq "60" -and $r.value.detail -like "*again on a second reading 60 ms later") "a file that says the second reading comes 60 ms later: it does, and the answer says 60"
    # A FILE THAT FAILS A CHECK IS REFUSED, AND THE FINDER THEN ASKS NOTHING (core/ModuleSettings.ps1: an
    # override file that fails its checks refuses with a reason and never falls back to the defaults).
    # A setting out of its range beside a key nobody declared: no window is read and no terminal asked,
    # even though the defaults would have found the window, and the answer names the file and each key.
    [System.IO.File]::WriteAllText($settingsFile, (ConvertTo-Json -InputObject @{ schemaVersion = 1; settings = @{ attempts = 0; retries = 9; socketFolder = $sockDir } } -Compress))
    $script:windowReads = 0; $script:calls.Clear(); $script:targets.Clear(); $r = $null
    $r = Find-HordeWeztermSessionWindow -Pane "18" -Instance "gui-sock-4242" -Runner $runner -Windows $windows -ProcessStart $alive -Wait $wait
    Check ($r.state -ceq "unknown") ("a settings file that fails a check: the window is unknown, though the defaults would have found it (" + $r.state + ")")
    Check ($script:windowReads -eq 0 -and $script:calls.Count -eq 0 -and $script:targets.Count -eq 0) ("and nothing was read with defaults in the bad file's place: no window, no listing (" + $script:windowReads + " window reads, " + $script:calls.Count + " calls)")
    Check (("" + $r.reason).StartsWith("the finder's settings are refused, so no terminal was asked: ") -and ("" + $r.reason).Contains("the settings file '" + $settingsFile + "' of wezterm-window is refused: ")) ("the answer says the settings are refused and names the file (" + $r.reason + ")")
    Check (("" + $r.reason).Contains("its key 'attempts' must be ") -and ("" + $r.reason).Contains("it has the key 'retries', which is no setting of wezterm-window")) "and each key that is wrong, with why: the one out of its range and the one nobody declared"
    $handed = Find-HordeWeztermSessionWindow -Pane "18" -Instance "gui-sock-4242" -Settings (Settings @{ attempts = 99; socketFolder = $sockDir }) -Runner $runner -Windows $windows -ProcessStart $alive -Wait $wait
    Check ($handed.state -ceq "unknown" -and ("" + $handed.reason).Contains("its key 'attempts' must be ") -and $script:calls.Count -eq 0) "a caller that hands in settings it read already is answered the same when they are refused"
    # THROUGH THE PORT (core/HostWindow.ps1): a caller that may not name this terminal asks the loaded
    # finders for their settings before it starts anything, and is handed this file's refusal whole.
    $viaPortRefused = Get-HordeSessionWindowSettingsState -HordeHome $env:HORDE_HOME
    Check ($viaPortRefused.state -ceq "refused" -and @($viaPortRefused.findings).Count -eq 2 -and @($viaPortRefused.findings | Where-Object { $_ -clike ("the settings file '" + $settingsFile + "' of wezterm-window is refused: *") }).Count -eq 2) ("through the port the bad file is refused, every finding naming the file (" + (@($viaPortRefused.findings) -join " / ") + ")")
    Check ((@($viaPortRefused.files) -join ",") -ceq $settingsFile -and $script:calls.Count -eq 0 -and $script:windowReads -eq 0) "and the port names the file it read, and asking it asked no terminal and read no window"
    $otherHome = Join-Path $env:HORDE_HOME "another-home"
    $viaPortOther = Get-HordeSessionWindowSettingsState -HordeHome $otherHome
    Check ($viaPortOther.state -ceq "defaults" -and (@($viaPortOther.files) -join ",") -ceq (Join-Path $otherHome "settings\wezterm-window.json")) "CONTROL: a home with no file under it is the defaults: the finder reads the home it is handed, not its own"
    [System.IO.File]::WriteAllText($settingsFile, (ConvertTo-Json -InputObject @{ schemaVersion = 1; settings = @{ attempts = 2 } } -Compress))
    Check ((Get-HordeSessionWindowSettingsState -HordeHome $env:HORDE_HOME).state -ceq "read") "CONTROL: the same file mended is read, through the port"
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
    # THE STAND-IN IS COMPILED A MOMENT BEFORE IT IS RUN, and this machine's application control has
    # refused to start a program that new: "An Application Control policy has blocked this file"
    # (review of 2026-10-06, "one transient noise"; measured here 2026-10-07 in 5 of 17 runs under
    # tools\Mutate.ps1, each of which compiles its own; waiting four seconds for the same file did not
    # help). A call that never started measured nothing, so the stand-in is compiled again and the
    # call made again, a few times; a call that ran is never repeated, and what it read stands.
    for ($go = 1; $go -le 4; $go++) {
        $raw = Invoke-HordeWeztermAct -Rest @("say", [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($said))) -Target ([pscustomobject]@{ socket = (Join-Path $sockDir "gui-sock-4242"); guiPid = 4242; guiStart = "133000000000000000" })
        if ($raw.code -ne -1) { break }
        Remove-HordePaneTool
        Start-Sleep -Milliseconds 500
        $script:HordeWeztermActExe = Get-HordePaneTool
    }
} finally { $script:HordeWeztermActExe = $saveExe; if ($null -ne $wasEncoding) { try { [Console]::OutputEncoding = $wasEncoding } catch { } } }
Check ($raw.code -eq 0 -and $raw.out -cne $said -and $readIn.CodePage -ne 65001) ("CONTROL: read as the host's call reads it, in code page " + $readIn.CodePage + ", the listing does not equal what the terminal wrote (exit " + $raw.code + $(if ($raw.code -ne 0) { ": " + ("" + $raw.err).Trim() } else { "" }) + ")")
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

Check ($src.Contains('SetThreadDpiAwarenessContext((IntPtr)(-4))') -and $src.Contains('finally { if (real) SetThreadDpiAwarenessContext(was); }')) "sizes are asked for in real pixels, on the reading's own thread, and the thread is put back as it was"

Complete-HordeSuite -Success "a session's window is the one its own terminal's listing proves, or it is unknown"
