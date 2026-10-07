# WHERE DOES A COMPANION WINDOW STAND, GIVEN THE WINDOW IT STANDS BESIDE?
#
# platform/windows/WindowFollow.ps1's placement is a pure function - a rectangle and a scale in, a
# rectangle out - so it is tested here with no window: the rectangles the proof of 2026-10-06 measured
# on a real terminal window (as placed, moved, resized and maximised), a screen at one and a half
# times the ordinary scale, and windows too small to stand beside. Then the refusals of the native
# half that need no window to give. The following itself - a real window, owned, re-placed on a real
# move - is test/e2e/e2e-decisions-window.ps1's, against a terminal window that scenario starts.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "platform\windows\WindowFollow.ps1")

function Rect { param([int]$L, [int]$T, [int]$R, [int]$B) return [pscustomobject]@{ left = $L; top = $T; right = $R; bottom = $B } }
function Place { param($Target, [int]$Dpi = 96) return (Get-HordeWindowFollowPlacement -Target $Target -Dpi $Dpi) }
function Is { param($P, [int]$L, [int]$T, [int]$W, [int]$H) return ($P.left -eq $L -and $P.top -eq $T -and $P.width -eq $W -and $P.height -eq $H) }
function Show { param($P) return ("" + $P.left + "," + $P.top + " " + $P.width + "x" + $P.height) }

Write-Host ""
Write-Host "--- floating: top right, a third of the width, most of the height ---" -ForegroundColor Cyan
$a = Place (Rect 120 90 1120 730)
Check (Is $a 763 138 333 568) ("beside a window at 120,90 of 1000 by 640: 24 in from its right edge, 48 down from its top, a third as wide, its height less the margins (" + (Show $a) + ")")
Check (($a.left + $a.width) -eq (1120 - 24) -and ($a.top + $a.height) -eq (730 - 24)) "its right and bottom edges are each 24 inside the other window's"
$moved = Place (Rect 260 160 1260 800)
Check (Is $moved 903 208 333 568) ("the other window moved by 140,70 and kept its size: the companion moved by exactly that and kept its own (" + (Show $moved) + ")")
$resized = Place (Rect 260 160 1020 680)
Check (Is $resized 676 208 320 448) ("the other window made 760 by 520: a third of that is under the smallest width a list can be read in, so the companion is 320 wide (" + (Show $resized) + ")")
$max = Place (Rect -7 -7 1714 920)
Check (Is $max 1116 41 574 855) ("a maximised window, whose frame hangs 7 outside the screen: still wholly inside it (" + (Show $max) + ")")
$big = Place (Rect 0 0 2400 1300)
Check ($big.width -eq 800 -and $big.height -eq 1228 -and ($big.height / 1300.0) -gt 0.9) "on a large window it is a third of the width and over nine tenths of the height"
Check ($a.left -is [int] -and $a.top -is [int] -and $a.width -is [int] -and $a.height -is [int]) "every number is a whole number of pixels"
$again = Place (Rect 120 90 1120 730)
Check (Is $again $a.left $a.top $a.width $a.height) "the same rectangle always gives the same place"

Write-Host ""
Write-Host "--- a screen at another scale ---" -ForegroundColor Cyan
$hi = Place (Rect 0 0 2520 1400) 144
Check (Is $hi 1644 72 840 1292) ("at one and a half times the scale the margins are one and a half times as many pixels: 36 and 72 (" + (Show $hi) + ")")
$hiSmall = Place (Rect 0 0 1200 900) 144
Check ($hiSmall.width -eq 480) "and so is the smallest width: 480 pixels, the same physical size as 320 at the ordinary scale"
$lowSmall = Place (Rect 0 0 1200 900) 96
Check ($lowSmall.width -eq 400) "CONTROL: the same rectangle at the ordinary scale is a third wide, 400"

Write-Host ""
Write-Host "--- a window too small to stand beside comfortably ---" -ForegroundColor Cyan
$narrow = Place (Rect 100 100 400 700)
Check ($narrow.width -eq 252 -and $narrow.left -eq 124 -and ($narrow.left + $narrow.width) -eq 376) ("a window 300 wide: the companion gives up its smallest width and stays a margin inside each side (" + (Show $narrow) + ")")
$short = Place (Rect 100 100 900 250)
Check ($short.height -eq 102 -and ($short.top + $short.height) -eq 250) ("a window 150 high: the companion ends at the other window's bottom, never below it (" + (Show $short) + ")")
$sliver = Place (Rect 0 0 40 30)
Check ($sliver.width -ge 1 -and $sliver.height -ge 1) "a sliver of a window still gives a rectangle with a size, never zero or less"

Write-Host ""
Write-Host "--- what is refused ---" -ForegroundColor Cyan
Check ((Get-HordeWindowFollowModes) -join "," -ceq "floating") "one way of following is built: floating"
Check (Throws { Get-HordeWindowFollowPlacement -Target (Rect 0 0 100 100) -Mode "side-by-side" } "is not a way a window is followed; the ways built are: floating") "a mode that is not built is refused by name, not guessed at"
Check (Throws { Get-HordeWindowFollowPlacement -Target (Rect 0 0 100 100) -Mode "Floating" } "is not a way a window is followed") "a mode is matched exactly"
Check (Throws { Place (Rect 500 100 500 700) } "is empty") "a window with no width has no place beside it"
Check (Throws { Place (Rect 100 700 500 700) } "is empty") "nor one with no height"
Check (Throws { Place (Rect 0 0 100 100) 0 } "is not a screen's scale") "a scale of nothing is refused"
Check (Throws { Place (Rect 0 0 100 100) 5000 } "is not a screen's scale") "and so is an absurd one"

Write-Host ""
Write-Host "--- the native half refuses without touching any window ---" -ForegroundColor Cyan
Check ($null -eq (Get-HordeWindowFollow) -and (Update-HordeWindowFollow) -ceq "none") "CONTROL: nothing is followed until something is started"
$none = Start-HordeWindowFollow -Target 0 -Follower 0
Check ($none.state -ceq "failed" -and $none.reason -ceq "the window to stand beside does not exist") "no window to stand beside: failed, in words"
$bogus = Start-HordeWindowFollow -Target 2147480001 -Follower 2147480003
Check ($bogus.state -ceq "failed" -and $bogus.reason -ceq "the window to stand beside does not exist") "a handle that is no window: failed"
$mode = Start-HordeWindowFollow -Target 1 -Follower 2 -Mode "tucked"
Check ($mode.state -ceq "failed" -and $mode.reason -like "*is not a way a window is followed") "a mode that is not built: failed before any window is looked at"
Check ($null -eq (Get-HordeWindowFollow)) "and after those refusals nothing is being followed"
Check ($null -eq (Get-HordeWindowRectangle -Handle 2147480001)) "a window that is gone has no rectangle"
Stop-HordeWindowFollow
Check ($null -eq (Get-HordeWindowFollow)) "stopping when nothing is followed does nothing"

Complete-HordeSuite -Success "a companion window's place is worked out from the other window's rectangle and scale alone"
