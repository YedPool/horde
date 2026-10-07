# CAN A CALLER MAKE ITS WINDOW THE COMPANION OF ANOTHER WINDOW WITHOUT NAMING A PLATFORM, AND IS IT
# ALWAYS ANSWERED, EVEN WHERE NOTHING CAN FOLLOW A WINDOW?
#
# core/WindowFollowPort.ps1. No window is made, read or moved by this suite, on any system:
#   - WHERE THE COMPANION STANDS is a pure function - a rectangle and a scale in, a rectangle out - and
#     is tested on the rectangles the proof of 2026-10-06 measured on a real window (as placed, moved,
#     resized and maximised), on a screen at one and a half times the ordinary scale, and on windows too
#     small to stand beside.
#   - THE PORT is tested with followers this suite registers itself, which record what they were asked:
#     one that answers, one that is for another system, one that throws, one that answers nonsense.
# The following itself - a real window owned, placed, re-placed on a real move, lost and set free - is
# the Windows follower's own suite, test/test-window-follow.ps1, on two plain windows of its own.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\WindowFollowPort.ps1")
# A home of this run's own, which is never made: a follow started with no settings handed in reads the
# person's file, and the person's real one is not this suite's to read.
$env:HORDE_HOME = Join-Path $env:TEMP ("horde-follow-port-home-" + [guid]::NewGuid().ToString("N"))

function Rect { param([int]$L, [int]$T, [int]$R, [int]$B) return [pscustomobject]@{ left = $L; top = $T; right = $R; bottom = $B } }
function Field {
    # A field of an object, or the text "<none>" when it is not there - so that a missing field fails a
    # check instead of raising under strict mode.
    param($From, [string]$Name)
    if ($null -eq $From -or $null -eq $From.PSObject.Properties[$Name]) { return "<none>" }
    return $From.PSObject.Properties[$Name].Value
}
function Place {
    # The place worked out, or an object whose every number is -999999 when none was: a check on a
    # number then fails, and never raises.
    param($Target, [double]$Scale = 1.0)
    $answer = Get-HordeWindowFollowPlacement -Target $Target -Scale $Scale
    if ((Test-HordeAnswer $answer) -and $answer.state -ceq "known") { return $answer.value }
    return [pscustomobject]@{ left = -999999; top = -999999; width = -999999; height = -999999 }
}
function Safe {
    # What the block answered, or one line of text saying it threw: a function that must answer and
    # throws instead then FAILS its check, where the bare call would only raise an error beside it.
    param([scriptblock]$Block)
    try { return (& $Block) } catch { return ("<threw: " + $_.Exception.Message + ">") }
}
function Is { param($P, [int]$L, [int]$T, [int]$W, [int]$H) return [bool]($P.left -eq $L -and $P.top -eq $T -and $P.width -eq $W -and $P.height -eq $H) }
function Show { param($P) return ("" + $P.left + "," + $P.top + " " + $P.width + "x" + $P.height) }
function Refused {
    # Is this an unknown answer whose reason holds -Like? Exactly true or false.
    param($Answer, [string]$Like)
    return [bool]((Test-HordeAnswer $Answer) -and $Answer.state -ceq "unknown" -and "$($Answer.reason)" -like ("*" + $Like + "*"))
}

Write-Host ""
Write-Host "--- floating: top right, a third of the width, most of the height ---" -ForegroundColor Cyan
$a = Place (Rect 120 90 1120 730)
Check (Is $a 763 138 333 568) ("beside a window at 120,90 of 1000 by 640: 24 in from its right edge, 48 down from its top, a third as wide, its height less the margins (" + (Show $a) + ")")
Check (($a.left + $a.width) -eq (1120 - 24) -and ($a.top + $a.height) -eq (730 - 24)) "its right and bottom edges are each 24 inside the other window's"
$moved = Place (Rect 260 160 1260 800)
Check (Is $moved 903 208 333 568) ("the other window moved by 140,70 and kept its size: the companion moved by exactly that and kept its own (" + (Show $moved) + ")")
$resized = Place (Rect 260 160 1020 680)
Check (Is $resized 676 208 320 448) ("the other window made 760 by 520: a third of that is under the smallest width, so the companion is 320 wide (" + (Show $resized) + ")")
$max = Place (Rect -7 -7 1714 920)
Check (Is $max 1116 41 574 855) ("a maximised window, whose frame hangs 7 outside the screen: still wholly inside it (" + (Show $max) + ")")
$big = Place (Rect 0 0 2400 1300)
Check ($big.width -eq 800 -and $big.height -eq 1228 -and ($big.height / 1300.0) -gt 0.9) "on a large window it is a third of the width and over nine tenths of the height"
Check ($a.left -is [int] -and $a.top -is [int] -and $a.width -is [int] -and $a.height -is [int]) "every number is a whole number of pixels"
$again = Place (Rect 120 90 1120 730)
Check (Is $again $a.left $a.top $a.width $a.height) "the same rectangle always gives the same place"
$far = Place (Rect -32000 -32000 -31400 -31600)
Check (Is $far -31744 -31952 320 328) ("a window far off every screen is stood beside like any other (" + (Show $far) + ")")
$table = Place (@{ left = 120; top = 90; right = 1120; bottom = 730 })
Check (Is $table 763 138 333 568) "a rectangle handed in as a table is read like one handed in as an object"

Write-Host ""
Write-Host "--- a screen at another scale ---" -ForegroundColor Cyan
$hi = Place (Rect 0 0 2520 1400) 1.5
Check (Is $hi 1644 72 840 1292) ("at one and a half times the scale the margins are one and a half times as many pixels: 36 and 72 (" + (Show $hi) + ")")
$hiSmall = Place (Rect 0 0 1200 900) 1.5
Check ($hiSmall.width -eq 480) "and so is the smallest width: 480 pixels, the same physical size as 320 at the ordinary scale"
$lowSmall = Place (Rect 0 0 1200 900) 1.0
Check ($lowSmall.width -eq 400) "CONTROL: the same rectangle at the ordinary scale is a third wide, 400"
$hiShort = Place (Rect 0 0 2000 380) 1.5
Check ($hiShort.height -eq 300 -and ($hiShort.top + $hiShort.height) -eq 372) ("and the smallest height: 300 pixels, where the other window's height less the margins would be 272 (" + (Show $hiShort) + ")")
# The window the follower was first measured against, 2026-10-06, at one and a half times the scale.
$measured = Place (Rect 60 60 1160 700) 1.5
Check (Is $measured 644 132 480 532) ("the place measured on a real window on 2026-10-06 - 644,132, 480 by 532 beside 60,60 of 1100 by 640 - is the place worked out (" + (Show $measured) + ")")

Write-Host ""
Write-Host "--- a window too small to stand beside comfortably ---" -ForegroundColor Cyan
$narrow = Place (Rect 100 100 400 700)
Check ($narrow.width -eq 252 -and $narrow.left -eq 124 -and ($narrow.left + $narrow.width) -eq 376) ("a window 300 wide: the companion gives up its smallest width and stays a margin inside each side (" + (Show $narrow) + ")")
$short = Place (Rect 100 100 900 250)
Check ($short.height -eq 102 -and ($short.top + $short.height) -eq 250) ("a window 150 high: the companion ends at the other window's bottom, never below it (" + (Show $short) + ")")
$sliver = Place (Rect 0 0 40 30)
Check ($sliver.width -ge 1 -and $sliver.height -ge 1) "a sliver of a window still gives a rectangle with a size, never zero or less"

Write-Host ""
Write-Host "--- what has no place is answered, never thrown ---" -ForegroundColor Cyan
Check ((@(Get-HordeWindowFollowModes) -join ",") -ceq "floating") "one way of following is built: floating"
$good = Get-HordeWindowFollowPlacement -Target (Rect 0 0 1000 800)
Check ((Test-HordeAnswer $good) -and $good.state -ceq "known") "CONTROL: a place that can be worked out is a known answer"
Check (Refused (Get-HordeWindowFollowPlacement -Target (Rect 0 0 100 100) -Mode "side-by-side") "is not a way a window is followed; the ways built are: floating") "a mode that is not built is refused by name, not guessed at"
Check (Refused (Get-HordeWindowFollowPlacement -Target (Rect 0 0 100 100) -Mode "Floating") "is not a way a window is followed") "a mode is matched exactly"
Check (Refused (Get-HordeWindowFollowPlacement -Target (Rect 500 100 500 700)) "is empty") "a window with no width has no place beside it"
Check (Refused (Get-HordeWindowFollowPlacement -Target (Rect 100 700 500 700)) "is empty") "nor one with no height"
Check (Refused (Get-HordeWindowFollowPlacement -Target (Rect 0 0 100 100) -Scale 0) "is not a screen's scale") "a scale of nothing is refused"
Check (Refused (Get-HordeWindowFollowPlacement -Target (Rect 0 0 100 100) -Scale 144) "is not a screen's scale") "and so is a dots-per-inch figure handed in as a scale"
Check (Refused (Safe { Get-HordeWindowFollowPlacement -Target (Rect 0 0 100 100) -Scale ([double]::NaN) }) "is not a screen's scale") "and a number that is not one"
Check (Refused (Get-HordeWindowFollowPlacement -Target $null) "is not four whole numbers") "no rectangle at all is refused in words"
Check (Refused (Get-HordeWindowFollowPlacement -Target ([pscustomobject]@{ left = 0; top = 0; right = 100 })) "is not four whole numbers") "and so is one with a side missing"
Check (Refused (Get-HordeWindowFollowPlacement -Target ([pscustomobject]@{ left = 0; top = 0; right = "100"; bottom = 100 })) "is not four whole numbers") "and one whose side is text"

Write-Host ""
Write-Host "--- the numbers are the module's settings, which a person may change in one file ---" -ForegroundColor Cyan
$declared = Safe { Get-HordeWindowFollowSettingsDeclaration }
Check ((Field $declared "module") -ceq "window-follow") "the module's settings are declared under its own name, window-follow"
$want = [ordered]@{ floatingMarginTopPx = 48; floatingMarginRightPx = 24; floatingMarginBottomPx = 24; floatingWidthShare = (1.0 / 3); floatingMinWidthPx = 320; floatingMinHeightPx = 200 }
$names = @(@(Field $declared "settings") | ForEach-Object { Field $_ "name" })
Check (($names -join ",") -ceq (@($want.Keys) -join ",")) ("six settings, each named for the mode it belongs to and the unit it is in (" + ($names -join ", ") + ")")
$homeDir = Join-Path $env:TEMP ("horde-follow-home-" + [guid]::NewGuid().ToString("N"))
try {
    $none = Safe { Get-HordeWindowFollowSettings -HordeHome $homeDir }
    $same = $true
    foreach ($name in $want.Keys) { if ((Field (Field $none "values") $name) -ne $want[$name]) { $same = $false } }
    Check ($same -and @(Field $none "findings").Count -eq 0) "with no file every setting is its default, and nothing is found wrong"
    Check ((Field $none "path") -ceq (Join-Path $homeDir "settings\window-follow.json") -and -not (Test-Path -LiteralPath $homeDir)) "the file is <home>\settings\window-follow.json, and asking made neither it nor the home"
    $byDefault = Place (Rect 120 90 1120 730)
    $given = Safe { Get-HordeWindowFollowPlacement -Target (Rect 120 90 1120 730) -Settings (Field $none "values") }
    Check ((Test-HordeAnswer $given) -and $given.state -ceq "known" -and (Is $given.value $byDefault.left $byDefault.top $byDefault.width $byDefault.height)) "a place worked out with no settings handed in is the place the defaults give"

    New-Item -ItemType Directory -Path (Join-Path $homeDir "settings") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $homeDir "settings\window-follow.json"), '{ "schemaVersion": 1, "settings": { "floatingMarginTopPx": 100, "floatingMarginRightPx": 10, "floatingMarginBottomPx": 0, "floatingWidthShare": 0.5, "floatingMinWidthPx": 600, "floatingMinHeightPx": 100 } }')
    $own = Safe { Get-HordeWindowFollowSettings -HordeHome $homeDir }
    $ownValues = Field $own "values"
    Check (@(Field $own "findings").Count -eq 0 -and (Field $ownValues "floatingMarginTopPx") -eq 100 -and (Field $ownValues "floatingWidthShare") -eq 0.5) "a person's file changes them"
    function PlaceWith {
        # The place worked out with settings handed in, shown as text: "left,top widthxheight", or why not.
        param($Target, $With, [double]$Scale = 1.0)
        $answer = Safe { Get-HordeWindowFollowPlacement -Target $Target -Scale $Scale -Settings $With }
        if ((Test-HordeAnswer $answer) -and $answer.state -ceq "known") { return (Show $answer.value) }
        return ("no place: " + $(if (Test-HordeAnswer $answer) { $answer.reason } else { $answer }))
    }
    $at = PlaceWith (Rect 120 90 1120 730) $ownValues
    Check ($at -ceq "510,190 600x540") ("and the place follows them: 10 in from the right, 100 down, the smallest width of 600 over half the width, the whole height below the top margin (" + $at + ")")
    $at = PlaceWith (Rect 0 0 2000 150) $ownValues
    Check ($at -ceq "990,100 1000x50") ("on a wide, low window: half its width, and its own smallest height gives way to the other window's bottom (" + $at + ")")
    $at = PlaceWith (Rect 0 0 2000 190) $ownValues
    Check ($at -ceq "990,100 1000x90") ("a height between: the other window's height less the top margin, where the smallest height of 100 would not fit (" + $at + ")")
    $at = PlaceWith (Rect 0 0 2000 1000) $ownValues 2.0
    Check ($at -ceq "780,200 1200x800") ("and at twice the scale each pixel setting is twice as many pixels, the share the same share (" + $at + ")")
    $bottom = [pscustomobject]@{ floatingMarginTopPx = 0; floatingMarginRightPx = 0; floatingMarginBottomPx = 70; floatingWidthShare = 0.25; floatingMinWidthPx = 100; floatingMinHeightPx = 100 }
    $at = PlaceWith (Rect 0 0 1000 800) $bottom
    Check ($at -ceq "750,0 250x730") ("no top or right margin and a bottom one of 70: flush to the top right corner, a quarter wide, 70 short of the bottom (" + $at + ")")

    [System.IO.File]::WriteAllText((Join-Path $homeDir "settings\window-follow.json"), '{ "schemaVersion": 1, "settings": { "floatingMarginTopPx": -1, "floatingWidthShare": 0.95, "floatingMinWidthPx": 10, "marginTop": 5 } }')
    $bad = Safe { Get-HordeWindowFollowSettings -HordeHome $homeDir }
    $said = @(Field $bad "findings") -join " | "
    Check (@(Field $bad "findings").Count -eq 4 -and $said -like "*'floatingMarginTopPx'*" -and $said -like "*'floatingWidthShare'*" -and $said -like "*'floatingMinWidthPx'*" -and $said -like "*'marginTop'*") ("a margin below nothing, a share over nine tenths, a smallest width under 100 and a name that is not one are each said by name (" + $said + ")")
    $badValues = Field $bad "values"
    Check ((Field $badValues "floatingMarginTopPx") -eq 48 -and (Field $badValues "floatingWidthShare") -eq (1.0 / 3) -and (Field $badValues "floatingMinWidthPx") -eq 320) "and each of those is its default"

    $lacking = [pscustomobject]@{ floatingMarginTopPx = 48; floatingMarginRightPx = 24; floatingMarginBottomPx = 24; floatingWidthShare = 0.3; floatingMinWidthPx = 320 }
    $at = PlaceWith (Rect 0 0 1000 800) $lacking
    Check ($at -like "no place: *floatingMinHeightPx*") ("settings handed in with one missing give no place, and the reason names it (" + $at + ")")
    $wrong = [pscustomobject]@{ floatingMarginTopPx = "48"; floatingMarginRightPx = 24; floatingMarginBottomPx = 24; floatingWidthShare = 0.3; floatingMinWidthPx = 320; floatingMinHeightPx = 200 }
    $at = PlaceWith (Rect 0 0 1000 800) $wrong
    Check ($at -like "no place: *floatingMarginTopPx*") ("nor do settings one of which is not a number (" + $at + ")")
} finally {
    if (Test-Path -LiteralPath $homeDir) { [System.IO.Directory]::Delete($homeDir, $true) }
}

Write-Host ""
Write-Host "--- with no follower loaded, every verb answers that nothing can follow a window here ---" -ForegroundColor Cyan
$files = @(Get-HordeWindowFollowerFiles -Root $root)
Check (@($files | Where-Object { $_ -like "*\platform\windows\WindowFollow.ps1" }).Count -eq 1) "the Windows follower's file is found by folder"
$bare = Join-Path $env:TEMP ("horde-follow-port-" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path (Join-Path $bare "platform\amiga") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $bare "platform\zeta") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $bare "platform\zeta\WindowFollow.ps1"), "# planted")
    [System.IO.File]::WriteAllText((Join-Path $bare "platform\amiga\Other.ps1"), "# planted")
    $planted = @(Get-HordeWindowFollowerFiles -Root $bare)
    Check ($planted.Count -eq 1 -and $planted[0] -like "*\platform\zeta\WindowFollow.ps1") "in a planted tree only a platform folder that has the file is named"
    Check (@(Safe { Get-HordeWindowFollowerFiles -Root (Join-Path $bare "platform\amiga") }).Count -eq 0) "and a tree with no platform folder names none, without an error"
} finally { if (Test-Path -LiteralPath $bare) { Remove-Item -LiteralPath $bare -Recurse -Force } }

$none = "no window follower is loaded, so a window cannot be followed here"
$r = Enable-HordeWindowFollowRealScale
Check ((Field $r "state") -ceq "unavailable" -and (Field $r "realScale") -ceq "unknown" -and (Field $r "awareness") -ceq "unknown" -and (Field $r "reason") -ceq $none) "real scale: unavailable, and whether the process sees real pixels is unknown, never no"
Check (Refused (Get-HordeWindowFollowRectangle -Handle 4242) $none) "another window's rectangle: unknown, with the reason"
$r = Start-HordeWindowFollow -Target 4242 -Companion 4343
Check ((Field $r "state") -ceq "unavailable" -and (Field $r "reason") -ceq $none -and (Field $r "target") -eq 0) "starting: unavailable, with the reason, and nothing is followed"
foreach ($verb in @("Get-HordeWindowFollow", "Update-HordeWindowFollow", "Disconnect-HordeWindowFollow", "Stop-HordeWindowFollow")) {
    $r = & $verb
    Check ((Field $r "state") -ceq "unavailable" -and (Field $r "reason") -ceq $none) ($verb + ": unavailable, with the reason")
}
Check ((@(Get-HordeWindowFollowStates) -join ",") -ceq "none,following,lost,free,failed,unavailable") "the states a follow record can carry are these six, in one list"

Write-Host ""
Write-Host "--- what the port refuses before any follower is asked ---" -ForegroundColor Cyan
$script:asked = New-Object System.Collections.ArrayList
$script:follow = New-HordeWindowFollowRecord -State "none"
function New-TestFollower {
    # A follower that records every block it is asked and answers from $script:follow.
    param([string]$Name, [scriptblock]$Applies = { $true })
    Register-HordeWindowFollower -Name $Name -Applies $Applies `
        -RealScale { [void]$script:asked.Add("realScale"); [pscustomobject]@{ state = "applied"; awareness = "per-monitor-v2"; realScale = "yes"; reason = "taken" } } `
        -Rectangle { param($Handle) [void]$script:asked.Add("rectangle " + $Handle); if ($Handle -eq 7) { New-HordeAbsent -Note "no such window" } else { New-HordeKnown -Value ([pscustomobject]@{ left = 10; top = 20; right = 610; bottom = 420; scale = 1.5 }) } } `
        -Start { param($Target, $Companion, $Mode, $Settings) [void]$script:asked.Add("start " + $Target + " " + $Companion + " " + $Mode + " top=" + (Field $Settings "floatingMarginTopPx")); $script:follow = New-HordeWindowFollowRecord -State "following" -Target $Target -Companion $Companion -Mode $Mode -Placed ([pscustomobject]@{ left = 1; top = 2; width = 3; height = 4 }) -Placements 1; $script:follow } `
        -Update { param($Place) [void]$script:asked.Add("update " + $Place); $script:follow } `
        -Release { [void]$script:asked.Add("release"); $script:follow = New-HordeWindowFollowRecord -State "free" -Reason "let go" -Target $script:follow.target -Companion $script:follow.companion; $script:follow } `
        -Stop { [void]$script:asked.Add("stop"); $script:follow = New-HordeWindowFollowRecord -State "none"; $script:follow }
}
New-TestFollower -Name "elsewhere" -Applies { $false }
New-TestFollower -Name "here"
$r = Start-HordeWindowFollow -Target 100 -Companion 200 -Mode "tucked"
Check ((Field $r "state") -ceq "failed" -and "$(Field $r 'reason')" -like "*is not a way a window is followed") "a mode that is not built: failed"
$r = Start-HordeWindowFollow -Target 0 -Companion 200
Check ((Field $r "state") -ceq "failed" -and (Field $r "reason") -ceq "no window to stand beside was named") "no window to stand beside: failed, in words"
$r = Start-HordeWindowFollow -Target -5 -Companion 200
Check ((Field $r "state") -ceq "failed" -and (Field $r "reason") -ceq "no window to stand beside was named") "a handle below zero names no window"
$r = Start-HordeWindowFollow -Target 100 -Companion 0
Check ((Field $r "state") -ceq "failed" -and (Field $r "reason") -ceq "no window to place was named") "no window to place: failed, in words"
$r = Start-HordeWindowFollow -Target 100 -Companion 100
Check ((Field $r "state") -ceq "failed" -and (Field $r "reason") -ceq "a window cannot stand beside itself") "a window beside itself: failed"
Check (Refused (Get-HordeWindowFollowRectangle -Handle 0) "no window was named") "the rectangle of no window is unknown"
Check ($script:asked.Count -eq 0) ("and for none of those was any follower asked anything (" + ($script:asked -join "; ") + ")")

Write-Host ""
Write-Host "--- the follower for this system is the one asked, with what the caller gave ---" -ForegroundColor Cyan
$r = Enable-HordeWindowFollowRealScale
Check ((Field $r "state") -ceq "applied" -and (Field $r "realScale") -ceq "yes" -and (Field $r "awareness") -ceq "per-monitor-v2") "real scale: the follower's own answer, whole"
$rect = Get-HordeWindowFollowRectangle -Handle 4242
Check ((Test-HordeAnswer $rect) -and $rect.state -ceq "known" -and $rect.value.left -eq 10 -and $rect.value.bottom -eq 420 -and $rect.value.scale -eq 1.5) "another window's rectangle and scale: the follower's known answer"
$gone = Get-HordeWindowFollowRectangle -Handle 7
Check ((Test-HordeAnswer $gone) -and $gone.state -ceq "absent") "a window that is not there is absent, which is not unknown"
$r = Start-HordeWindowFollow -Target 100 -Companion 200
Check ((Field $r "state") -ceq "following" -and (Field $r "target") -eq 100 -and (Field $r "companion") -eq 200 -and (Field $r "mode") -ceq "floating" -and (Field $r "placed").width -eq 3) "starting: the follower's record, with both windows, the mode and the place"
$r = Get-HordeWindowFollow
Check ((Field $r "state") -ceq "following") "asking: following"
$r = Update-HordeWindowFollow
Check ((Field $r "state") -ceq "following") "placing again: following"
$r = Disconnect-HordeWindowFollow
Check ((Field $r "state") -ceq "free" -and (Field $r "reason") -ceq "let go" -and (Field $r "companion") -eq 200) "letting go: free, with the follower's reason"
$r = Stop-HordeWindowFollow
Check ((Field $r "state") -ceq "none") "stopping: none"
Check (($script:asked -join "; ") -ceq "realScale; rectangle 4242; rectangle 7; start 100 200 floating top=48; update False; update True; release; stop") ("each verb asked exactly its block, once, in order - asking moves nothing, placing again does (" + ($script:asked -join "; ") + ")")

Write-Host ""
Write-Host "--- a follow is started with the person's settings ---" -ForegroundColor Cyan
$startHome = Join-Path $env:TEMP ("horde-follow-start-" + [guid]::NewGuid().ToString("N"))
$savedHome = $env:HORDE_HOME
try {
    New-Item -ItemType Directory -Path (Join-Path $startHome "settings") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $startHome "settings\window-follow.json"), '{ "schemaVersion": 1, "settings": { "floatingMarginTopPx": 100, "nonsuch": 1 } }')
    $env:HORDE_HOME = $startHome
    $script:asked.Clear()
    $r = Safe { Start-HordeWindowFollow -Target 100 -Companion 200 }
    Check ((Field $r "state") -ceq "following" -and ($script:asked -join "; ") -ceq "start 100 200 floating top=100") ("started with no settings handed in, the follower is given the ones in the person's file (" + ($script:asked -join "; ") + ")")
    Check (@(Field $r "findings").Count -eq 1 -and "$(@(Field $r 'findings')[0])" -like "*'nonsuch'*") "and what is wrong in that file comes back with the answer, by name"
    $script:asked.Clear()
    $mine = [pscustomobject]@{ floatingMarginTopPx = 7; floatingMarginRightPx = 24; floatingMarginBottomPx = 24; floatingWidthShare = 0.3; floatingMinWidthPx = 320; floatingMinHeightPx = 200 }
    $r = Safe { Start-HordeWindowFollow -Target 100 -Companion 200 -Settings $mine }
    Check ((Field $r "state") -ceq "following" -and ($script:asked -join "; ") -ceq "start 100 200 floating top=7" -and @(Field $r "findings").Count -eq 0) ("settings handed in are the ones the follower is given, and no file is read for them (" + ($script:asked -join "; ") + ")")
    $script:asked.Clear()
    $r = Safe { Start-HordeWindowFollow -Target 100 -Companion 200 -Settings ([pscustomobject]@{ floatingMarginTopPx = 7 }) }
    Check ((Field $r "state") -ceq "failed" -and "$(Field $r 'reason')" -like "*floatingMarginRightPx*" -and $script:asked.Count -eq 0) "settings handed in with one missing: failed, naming it, before any follower is asked"
    $env:HORDE_HOME = "not-a-rooted-path"
    $r = Safe { Start-HordeWindowFollow -Target 100 -Companion 200 }
    Check ((Field $r "state") -ceq "failed" -and "$(Field $r 'reason')" -like "*HORDE_HOME must be an absolute path*" -and $script:asked.Count -eq 0) "a home that cannot be one: failed, in the home's own words, and never a throw"
    $r = Safe { Get-HordeWindowFollow }
    Check (@(Field $r "findings").Count -eq 0 -and (Field $r "findings") -isnot [string]) "CONTROL: a record that read no file carries an empty list of findings"
} finally {
    $env:HORDE_HOME = $savedHome
    if (Test-Path -LiteralPath $startHome) { [System.IO.Directory]::Delete($startHome, $true) }
}
[void](Stop-HordeWindowFollow)

Write-Host ""
Write-Host "--- a follower that fails is answered for, never thrown through ---" -ForegroundColor Cyan
Register-HordeWindowFollower -Name "here" -Applies { $true } -RealScale { throw "scale broke" } -Rectangle { param($Handle) throw "rect broke" } `
    -Start { param($Target, $Companion, $Mode) throw "start broke" } -Update { param($Place) throw "update broke" } -Release { throw "release broke" } -Stop { throw "stop broke" }
$r = Enable-HordeWindowFollowRealScale
Check ((Field $r "state") -ceq "unavailable" -and (Field $r "realScale") -ceq "unknown" -and (Field $r "reason") -ceq "here: its follower failed: scale broke") "real scale from a follower that throws: unavailable, naming it and what it said"
Check (Refused (Get-HordeWindowFollowRectangle -Handle 4242) "here: its follower failed: rect broke") "a rectangle from one that throws: unknown"
$r = Start-HordeWindowFollow -Target 100 -Companion 200
Check ((Field $r "state") -ceq "unavailable" -and (Field $r "reason") -ceq "here: its follower failed: start broke") "starting with one that throws: unavailable"
$r = Get-HordeWindowFollow
Check ((Field $r "state") -ceq "unavailable" -and (Field $r "reason") -ceq "here: its follower failed: update broke") "asking one that throws: unavailable"
$r = Disconnect-HordeWindowFollow
Check ((Field $r "state") -ceq "unavailable" -and (Field $r "reason") -ceq "here: its follower failed: release broke") "letting go with one that throws: unavailable"
$r = Stop-HordeWindowFollow
Check ((Field $r "state") -ceq "unavailable" -and (Field $r "reason") -ceq "here: its follower failed: stop broke") "stopping one that throws: unavailable"

$script:nonsense = $null
Register-HordeWindowFollower -Name "here" -Applies { $true } -RealScale { $script:nonsense } -Rectangle { param($Handle) $script:nonsense } `
    -Start { param($Target, $Companion, $Mode) $script:nonsense } -Update { param($Place) $script:nonsense } -Release { $script:nonsense } -Stop { $script:nonsense }
$shapes = [ordered]@{
    "nothing" = $null
    "a word" = "following"
    "a record with no state" = [pscustomobject]@{ reason = ""; target = 1; companion = 2; mode = "floating"; placed = $null; placements = 0; events = 0; findings = @() }
    "a state that is not one" = [pscustomobject]@{ state = "Following"; reason = ""; target = 1; companion = 2; mode = "floating"; placed = $null; placements = 0; events = 0; findings = @() }
    "a record with a field missing" = [pscustomobject]@{ state = "following"; reason = ""; target = 1; companion = 2; mode = "floating"; placed = $null; placements = 0; findings = @() }
}
foreach ($name in $shapes.Keys) {
    $script:nonsense = $shapes[$name]
    $r = Start-HordeWindowFollow -Target 100 -Companion 200
    Check ((Field $r "state") -ceq "unavailable" -and (Field $r "reason") -ceq "here: its follower did not answer") ("a follower that answers " + $name + " did not answer: unavailable")
}
$script:nonsense = [pscustomobject]@{ state = "applied"; realScale = "maybe" }
Check ((Field (Enable-HordeWindowFollowRealScale) "realScale") -ceq "unknown") "a real scale that is not yes, no or unknown is unknown"
$script:nonsense = [pscustomobject]@{ left = 1; top = 2; right = 3; bottom = 4; scale = 1.0 }
Check (Refused (Safe { Get-HordeWindowFollowRectangle -Handle 4242 }) "did not answer") "a rectangle that is not an answer is unknown"
$script:nonsense = New-HordeKnown -Value ([pscustomobject]@{ left = 1; top = 2; right = 3; scale = 1.0 })
Check (Refused (Get-HordeWindowFollowRectangle -Handle 4242) "did not answer") "a known rectangle with a side missing is unknown"
$script:nonsense = New-HordeKnown -Value ([pscustomobject]@{ left = 1; top = 2; right = 3; bottom = 4 })
Check (Refused (Get-HordeWindowFollowRectangle -Handle 4242) "did not answer") "a known rectangle with no scale is unknown"
$script:nonsense = New-HordeKnown -Value ([pscustomobject]@{ left = 1; top = 2; right = 3; bottom = 4; scale = 1.25 })
$whole = Get-HordeWindowFollowRectangle -Handle 4242
Check ((Test-HordeAnswer $whole) -and $whole.state -ceq "known" -and $whole.value.scale -eq 1.25) "CONTROL: a whole one is known"

Write-Host ""
Write-Host "--- which follower, and what may register ---" -ForegroundColor Cyan
Register-HordeWindowFollower -Name "here" -Applies { "yes" } -RealScale { } -Rectangle { } -Start { } -Update { } -Release { } -Stop { }
$r = Start-HordeWindowFollow -Target 100 -Companion 200
Check ((Field $r "state") -ceq "unavailable" -and "$(Field $r 'reason')" -like "no loaded window follower is for this system*elsewhere: not for this system*here: not for this system*") "a follower whose Applies is not exactly true is not for this system, and each one loaded is named"
Register-HordeWindowFollower -Name "here" -Applies { throw "cannot tell" } -RealScale { } -Rectangle { } -Start { } -Update { } -Release { } -Stop { }
$r = Get-HordeWindowFollow
Check ((Field $r "state") -ceq "unavailable" -and "$(Field $r 'reason')" -like "*here: it could not say whether it is for this system: cannot tell*") "one whose Applies throws is passed over, with what it said"
New-TestFollower -Name "second"
New-TestFollower -Name "third"
$script:asked.Clear()
[void](Stop-HordeWindowFollow)
Check ((Get-HordeValue (Get-HordeWindowFollower)).name -ceq "second" -and $script:asked.Count -eq 1) "of two that apply, the first registered is the one asked, and only it"
Check (Throws { Register-HordeWindowFollower -Name "Windows" -Applies { $true } -RealScale { } -Rectangle { } -Start { } -Update { } -Release { } -Stop { } } "a platform name is lowercase") "a follower's name is lowercase letters, digits and hyphens"
Check (Throws { New-HordeWindowFollowRecord -State "attached" } "is not a state of a followed window") "a follower cannot build a record in a state the port does not know"
New-TestFollower -Name "second" -Applies { $false }
Check ((Get-HordeValue (Get-HordeWindowFollower)).name -ceq "third") "registering a name again replaces it: the one that no longer applies is passed over"

Complete-HordeSuite -Success "a companion window is asked for through one port, and the port always answers"
