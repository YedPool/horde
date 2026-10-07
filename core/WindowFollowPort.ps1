# core/WindowFollowPort.ps1 - the port through which a window of this process is made the COMPANION of
# another window: it stands beside that window, goes where it goes, and stands free when it is gone.
#
# WHY A PORT. Owning a window across programs, hearing that it moved and placing a window without
# giving it the keyboard are things one operating system does in its own way. Each system that can do
# them has platform/<name>/WindowFollow.ps1, which registers one follower here when it is dot-sourced,
# as hosts/<name>/Act.ps1 registers with core/HostAct.ps1, and is found by folder. A CALLER ASKS THIS
# FILE AND NEVER NAMES A PLATFORM: the second system is a new folder and no edit to any caller.
#
# THIS FILE KNOWS NO WINDOW. It does not know what either window shows, how the other window was
# found, or what program owns it. A window is named by the platform's own number for it (a native
# handle), a whole number above zero, which is passed through unread.
#
# HOW A CALLER USES IT. Load the port, then every follower, at the caller's own scope:
#
#   . (Join-Path <repository> "core\WindowFollowPort.ps1")
#   foreach ($file in @(Get-HordeWindowFollowerFiles)) { . $file }
#
# THE VERBS. None of them throws for anything the world does - no follower for this system, a window
# that is gone, a follower that fails: each answers, with the reason in words.
#
#   Enable-HordeWindowFollowRealScale
#       Make this process see real pixels, ONCE, BEFORE IT MAKES ITS FIRST WINDOW and before it reads
#       another window's rectangle: until then the system may hand it scaled numbers, and a place
#       worked out from them is wrong by the screen's scale. Answers { state; awareness; realScale;
#       reason }, the shape of platform/windows/Scale.ps1: decide on realScale, which is "yes", "no"
#       or "unknown". With no follower: state "unavailable", realScale "unknown".
#   Get-HordeWindowFollowRectangle -Handle <n>
#       Where another window is: a core/Tristate.ps1 answer. known { left; top; right; bottom; scale }
#       in real pixels, scale being its screen's (1 is the ordinary scale, 1.5 one and a half times);
#       absent when there is no such window; unknown, with the reason, when it cannot be asked here.
#   Get-HordeWindowFollowPlacement -Target <rectangle> [-Scale <n>] [-Mode <name>] [-Settings <values>]
#       Where the companion stands: a core/Tristate.ps1 answer, known { left; top; width; height } in
#       real pixels, or unknown with the reason (a mode that is not built, an empty rectangle, a scale
#       no screen has). PURE: no window is read or moved, on any system, so a caller can work out the
#       place before its window exists, and every platform's follower places by the same rule.
#   Start-HordeWindowFollow -Target <n> -Companion <n> [-Mode <name>] [-Settings <values>]
#       Make the window -Companion (this process's own) the companion of the window -Target
#       (anyone's): owned by it, placed, and placed again whenever it moves or is resized. Call it on
#       the thread that runs the companion's message loop. Answers a FOLLOW RECORD (below) whose state
#       is "following", "failed" (it could have been followed and was not: the reason says what
#       refused) or "unavailable" (nothing can follow a window here: the reason says why).
#   Get-HordeWindowFollow
#       The follow record as it is NOW: it looks whether the other window still exists, and moves
#       nothing. This is how a caller learns "lost"; ask it on a timer.
#   Update-HordeWindowFollow
#       The same, after placing the companion again from where the other window is now: the net under
#       a report of a move that never came.
#   Disconnect-HordeWindowFollow
#       Let the companion go: it stands free where it is. State "free".
#   Stop-HordeWindowFollow
#       Stop following altogether, for a companion that is closing. State "none". To keep the window,
#       disconnect it first.
#   Switch-HordeWindowFollowKeyboard                                                          (TRIAL)
#       Hand the keyboard to the other window: the person is done in the companion and goes back to
#       the window it stands beside. Answers { state; reason }, NOT a follow record: "handed" (the
#       other window has the keyboard, read back from the system), "refused" (it was asked and the
#       system did not do it; the reason says what it said), "none" (nothing is followed: a companion
#       that stands free has no window to hand it to, and nothing is done) or "unavailable" (no
#       follower here can do it). Only ever asked because the person asked, with a key in the
#       companion: this file gives no window the keyboard on its own account.
#
# THE FOLLOW RECORD is plain data: { state; reason; target; companion; mode; placed; placements; events }.
#   state       "none"         nothing is followed.
#               "following"    the companion stands beside the other window.
#               "lost"         the other window is gone - closed, or its program ended. The companion
#                              has been let go by the follower itself and STANDS FREE; the caller says
#                              so to the person and need do nothing else.
#               "free"         the caller disconnected it; it stands free.
#               "failed"       Start only: this follow could not be made.
#               "unavailable"  no follower for this system is loaded, or the one that is did not answer.
#   reason      a sentence, empty while following.
#   target, companion   the two handles, 0 when there are none.
#   placed      { left; top; width; height } where the companion was last placed, or nothing.
#   placements  how many times it was placed; events how many moves the system reported. For a report.
# ONE FOLLOW AT A TIME in a process: starting a second ends the first.
#
# WHAT "STANDS FREE" MEANS, on every platform: the companion is no longer owned by anything, is an
# ordinary window the person finds where they find their other windows (the taskbar, on Windows), is
# visible if it had been before the other window went, and was NOT given the keyboard by becoming so.
# A follower owns all of that, whatever made the window.
#
# WHY TWO KINDS OF ANSWER. The two READS answer in core/Tristate.ps1 form, because each has exactly
# its three cases - a value, a known nothing, a "could not tell" - and Get-HordeValue will not hand a
# caller a place out of an unknown. The ACTS answer a record with a state word, as
# platform/windows/Scale.ps1 does, because a follow has more than three states and a caller reports
# the record as it is.
#
# WHAT A FOLLOWER GIVES (Register-HordeWindowFollower): its name, and seven blocks.
#   Applies   ()                              exactly $true when this is the system it is for
#   RealScale ()                              { state; awareness; realScale; reason }
#   Rectangle ($handle)                       a core/Tristate.ps1 answer, as Get-HordeWindowFollowRectangle
#   Start     ($target, $companion, $mode, $settings)   a follow record; the port has already refused a mode that
#                                             is not built, a handle that is not above zero and a
#                                             window beside itself
#   Update    ($place)                        a follow record; places again only when $place is $true
#   Release   ()                              a follow record: the companion stands free
#   Stop      ()                              a follow record: nothing is followed
# and one more it MAY give, without which Switch-HordeWindowFollowKeyboard answers "unavailable":
#   Hand      ()                              { state; reason }: handed, refused or none
# A follower places by Get-HordeWindowFollowPlacement and by nothing of its own. The first registered
# follower whose Applies is true is the one asked.
#
# THE SETTINGS are the module's own, declared here once (core/ModuleSettings.ps1, module
# "window-follow") and changed by a person in <home>\settings\window-follow.json:
#   Get-HordeWindowFollowSettings [-HordeHome <path>]   { values; findings; path }
# A caller reads them once, says each finding, and hands .values to the placement and to Start, so the
# place it works out before its window exists is the place the follower then keeps. Start with no
# -Settings reads the file itself and answers what was wrong in it in the record's findings.
# THEY SAY WHERE A COMPANION STANDS BY DEFAULT, as gaps from the other window's top right corner in
# pixels at the ordinary scale, and are never written by Horde. A place the person drags the companion
# to is not a setting: it is something a later unit remembers, as an offset from that same corner in
# the same scale-free pixels, and hands to the placement beside these. Not built.
#
# ONE MODE IS BUILT: floating, at the top right of the other window. A mode is a name the pure
# function refuses unless it knows it, which is the seam for the next ones (side by side; a small
# tab): each is a branch there and nothing in a caller.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "ModuleSettings.ps1")

# Kept across a second load: a follower's file loads this file too, after the caller has.
if ($null -eq (Get-Variable -Name HordeWindowFollowers -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeWindowFollowers = New-Object System.Collections.ArrayList }

function Get-HordeWindowFollowModes { return @("floating") }

function Get-HordeWindowFollowStates {
    # Every state a follow record can carry, for a caller or a schema that lists them.
    return @("none", "following", "lost", "free", "failed", "unavailable")
}

function Get-HordeWindowFollowSettingsDeclaration {
    # THE MODULE'S SETTINGS, declared once (core/ModuleSettings.ps1): where a companion stands by
    # default. Each pixel setting is in pixels at the ordinary scale and is multiplied by the other
    # window's scale, so it is the same physical size on every screen. The defaults are the proof's of
    # 2026-10-06: 24 from the right edge, and 48 from the top so that the other window's title and tab
    # bar stay visible above the companion. Each name begins with its mode: the next mode adds its own
    # and changes none of these.
    return (New-HordeModuleSettings -Module "window-follow" -Settings @(
        @{ name = "floatingMarginTopPx";    kind = "whole";    default = 48;        min = 0;   max = 2000; what = "Floating: gap between the other window's top edge and the companion's, in pixels at the ordinary scale." },
        @{ name = "floatingMarginRightPx";  kind = "whole";    default = 24;        min = 0;   max = 2000; what = "Floating: gap between the companion's right edge and the other window's, in pixels at the ordinary scale." },
        @{ name = "floatingMarginBottomPx"; kind = "whole";    default = 24;        min = 0;   max = 2000; what = "Floating: gap between the companion's bottom edge and the other window's, in pixels at the ordinary scale." },
        @{ name = "floatingWidthShare";     kind = "fraction"; default = (1.0 / 3); min = 0.1; max = 0.9;  what = "Floating: the share of the other window's width the companion takes." },
        @{ name = "floatingMinWidthPx";     kind = "whole";    default = 320;       min = 100; max = 4000; what = "Floating: the smallest width of the companion, in pixels at the ordinary scale." },
        @{ name = "floatingMinHeightPx";    kind = "whole";    default = 200;       min = 100; max = 4000; what = "Floating: the smallest height of the companion, in pixels at the ordinary scale." }
    ))
}

function Get-HordeWindowFollowSettings {
    # The module's settings as the person has them: { values; findings; path }. It reads the one file
    # <home>\settings\window-follow.json and writes nothing; what is wrong in the file is a finding by
    # name and that setting is its default. A HORDE_HOME that is not an absolute path is the home's own
    # throw, passed on (core/ModuleSettings.ps1).
    param([string]$HordeHome = "")
    return (Get-HordeModuleSettings -Declaration (Get-HordeWindowFollowSettingsDeclaration) -HordeHome $HordeHome)
}

function Get-HordeWindowFollowSettingsFault {
    # What is wrong with settings handed in, in words, or "" when each declared name is there and is a
    # number: a caller hands in the values object Get-HordeWindowFollowSettings answered.
    param($Settings)
    foreach ($entry in @((Get-HordeWindowFollowSettingsDeclaration).settings)) {
        $field = $null
        if ($null -ne $Settings) { $field = $Settings.PSObject.Properties[$entry.name] }
        if ($null -eq $field -or ($field.Value -isnot [int] -and $field.Value -isnot [double])) { return ("the settings handed in are not this module's: '" + $entry.name + "' is not there, or is not a number") }
    }
    return ""
}

function Get-HordeWindowFollowWhole {
    # A field of a rectangle as a whole number, or $null when it is not there or is not one.
    param($From, [string]$Name)
    if ($null -eq $From) { return $null }
    $value = $null
    if ($From -is [System.Collections.IDictionary]) { if ($From.Contains($Name)) { $value = $From[$Name] } }
    else { $field = $From.PSObject.Properties[$Name]; if ($null -ne $field) { $value = $field.Value } }
    if ($value -is [int] -or $value -is [long]) { return [long]$value }
    return $null
}

function Get-HordeWindowFollowPlacement {
    # Where the companion stands (header). -Target is the other window's rectangle { left; top; right;
    # bottom }; -Scale its screen's scale. A PURE FUNCTION: no window is read or moved here.
    #
    # FLOATING: the right edge a margin in from the other window's, the top a margin down from its
    # top, a share of its width and all of its height but the margins - never smaller than the
    # smallest size, nor wider or lower than the other window allows.
    #
    # -Settings is the values object of Get-HordeWindowFollowSettings; left out, the declared defaults
    # are used and no file is read: this function is pure either way.
    param($Target, [double]$Scale = 1.0, [string]$Mode = "floating", $Settings = $null)
    if (@(Get-HordeWindowFollowModes) -cnotcontains $Mode) { return (New-HordeUnknown -Reason ("'" + $Mode + "' is not a way a window is followed; the ways built are: " + (@(Get-HordeWindowFollowModes) -join ", "))) }
    $f = $Settings
    if ($null -eq $f) { $f = (Read-HordeModuleSettingsText -Declaration (Get-HordeWindowFollowSettingsDeclaration) -Text $null).values }
    else { $fault = Get-HordeWindowFollowSettingsFault -Settings $f; if ($fault -ne "") { return (New-HordeUnknown -Reason $fault) } }
    # Half the ordinary scale to ten times it: wider than any screen sold, and it keeps a wrong number
    # (a zero, a dots-per-inch figure handed in as a scale) from being multiplied into a place.
    if ([double]::IsNaN($Scale) -or $Scale -lt 0.5 -or $Scale -gt 10) { return (New-HordeUnknown -Reason ("" + $Scale + " is not a screen's scale")) }
    $left = Get-HordeWindowFollowWhole -From $Target -Name "left"; $top = Get-HordeWindowFollowWhole -From $Target -Name "top"
    $right = Get-HordeWindowFollowWhole -From $Target -Name "right"; $bottom = Get-HordeWindowFollowWhole -From $Target -Name "bottom"
    if ($null -eq $left -or $null -eq $top -or $null -eq $right -or $null -eq $bottom) { return (New-HordeUnknown -Reason "the other window's rectangle is not four whole numbers, so there is nowhere to work out") }
    if ($right -le $left -or $bottom -le $top) { return (New-HordeUnknown -Reason "the other window's rectangle is empty, so there is nowhere beside it") }
    # Whole pixels, rounded once per number, so that two placements from one rectangle are the same.
    $marginTop = [int][Math]::Round($f.floatingMarginTopPx * $Scale)
    $marginRight = [int][Math]::Round($f.floatingMarginRightPx * $Scale)
    $marginBottom = [int][Math]::Round($f.floatingMarginBottomPx * $Scale)
    $smallestWidth = [int][Math]::Round($f.floatingMinWidthPx * $Scale)
    $smallestHeight = [int][Math]::Round($f.floatingMinHeightPx * $Scale)
    $targetWidth = [int]($right - $left); $targetHeight = [int]($bottom - $top)
    $width = [Math]::Max([int][Math]::Round($targetWidth * [double]$f.floatingWidthShare), $smallestWidth)
    # Never wider than the other window less a margin each side: on a narrow window it shrinks with it.
    $width = [Math]::Min($width, [Math]::Max($targetWidth - 2 * $marginRight, 1))
    $height = [Math]::Max($targetHeight - $marginTop - $marginBottom, [Math]::Min($smallestHeight, [Math]::Max($targetHeight - $marginTop, 1)))
    return (New-HordeKnown -Value ([pscustomobject]@{ left = [int]($right - $marginRight - $width); top = [int]($top + $marginTop); width = [int]$width; height = [int]$height }))
}

function New-HordeWindowFollowRecord {
    # A follow record (header), for a follower to answer with and for this file to answer when none can.
    param([Parameter(Mandatory = $true)][string]$State, [string]$Reason = "", [long]$Target = 0, [long]$Companion = 0, [string]$Mode = "", $Placed = $null, [int]$Placements = 0, [int]$Events = 0, [string[]]$Findings = @())
    if (@(Get-HordeWindowFollowStates) -cnotcontains $State) { throw ("'" + $State + "' is not a state of a followed window") }
    return [pscustomobject]@{ state = $State; reason = $Reason; target = $Target; companion = $Companion; mode = $Mode; placed = $Placed; placements = $Placements; events = $Events; findings = [string[]]@($Findings) }
}

function Register-HordeWindowFollower {
    # Called by platform/<name>/WindowFollow.ps1 when it is dot-sourced. Re-registering a name replaces it.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Applies,
        [Parameter(Mandatory = $true)][scriptblock]$RealScale,
        [Parameter(Mandatory = $true)][scriptblock]$Rectangle,
        [Parameter(Mandatory = $true)][scriptblock]$Start,
        [Parameter(Mandatory = $true)][scriptblock]$Update,
        [Parameter(Mandatory = $true)][scriptblock]$Release,
        [Parameter(Mandatory = $true)][scriptblock]$Stop,
        [scriptblock]$Hand = $null
    )
    if ($Name -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("a platform name is lowercase letters, digits and hyphens: '" + $Name + "'") }
    foreach ($known in @($script:HordeWindowFollowers)) { if ($known.name -ceq $Name) { $script:HordeWindowFollowers.Remove($known) } }
    [void]$script:HordeWindowFollowers.Add([pscustomobject]@{ name = $Name; applies = $Applies; realScale = $RealScale; rectangle = $Rectangle; start = $Start; update = $Update; release = $Release; stop = $Stop; hand = $Hand })
}

function Get-HordeWindowFollowerFiles {
    # The follower files, found by folder: platform/<name>/WindowFollow.ps1. The CALLER dot-sources
    # each at its own scope, so the follower's helpers stay visible to the blocks it registers.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $platforms = Join-Path $Root "platform"
    if (-not (Test-Path -LiteralPath $platforms -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $platforms -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "WindowFollow.ps1" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Get-HordeWindowFollower {
    # The follower for this system, as an answer: the first registered one whose Applies is exactly
    # true. Unknown, saying what each loaded follower said, when there is none.
    if ($script:HordeWindowFollowers.Count -eq 0) { return (New-HordeUnknown -Reason "no window follower is loaded, so a window cannot be followed here") }
    $said = New-Object System.Collections.ArrayList
    foreach ($follower in @($script:HordeWindowFollowers)) {
        $here = $null
        try { $here = @(& $follower.applies) | Select-Object -Last 1 } catch { [void]$said.Add($follower.name + ": it could not say whether it is for this system: " + $_.Exception.Message); continue }
        if ($here -is [bool] -and $here) { return (New-HordeKnown -Value $follower) }
        [void]$said.Add($follower.name + ": not for this system")
    }
    return (New-HordeUnknown -Reason ("no loaded window follower is for this system, so a window cannot be followed here (" + ($said -join "; ") + ")"))
}

function Invoke-HordeWindowFollower {
    # One verb of this system's follower: { asked; value; reason }. asked is false, with the reason,
    # when there is no follower or its block threw; a follower's failure is never this file's throw.
    param([Parameter(Mandatory = $true)][string]$Verb, [object[]]$With = @())
    $follower = Get-HordeWindowFollower
    if ($follower.state -cne "known") { return [pscustomobject]@{ asked = $false; value = $null; reason = $follower.reason } }
    $block = $follower.value.PSObject.Properties[$Verb].Value
    try { $got = @(& $block @With) | Select-Object -Last 1 }
    catch { return [pscustomobject]@{ asked = $false; value = $null; reason = ($follower.value.name + ": its follower failed: " + $_.Exception.Message) } }
    return [pscustomobject]@{ asked = $true; value = $got; reason = ($follower.value.name + ": its follower did not answer") }
}

function ConvertTo-HordeWindowFollowRecord {
    # What a follower's block answered, as a follow record: its own when it is one, and "unavailable"
    # with the reason when the follower was not asked or answered something else.
    param([Parameter(Mandatory = $true)]$Asked)
    if (-not $Asked.asked) { return (New-HordeWindowFollowRecord -State "unavailable" -Reason $Asked.reason) }
    $got = $Asked.value
    if ($null -eq $got) { return (New-HordeWindowFollowRecord -State "unavailable" -Reason $Asked.reason) }
    foreach ($field in @("state", "reason", "target", "companion", "mode", "placed", "placements", "events", "findings")) { if ($null -eq $got.PSObject.Properties[$field]) { return (New-HordeWindowFollowRecord -State "unavailable" -Reason $Asked.reason) } }
    if ($got.state -isnot [string] -or @(Get-HordeWindowFollowStates) -cnotcontains $got.state) { return (New-HordeWindowFollowRecord -State "unavailable" -Reason $Asked.reason) }
    return $got
}

function Enable-HordeWindowFollowRealScale {
    # Make this process see real pixels (header). Never throws.
    $asked = Invoke-HordeWindowFollower -Verb "realScale"
    $got = $asked.value
    $words = @("yes", "no", "unknown")
    if (-not $asked.asked -or $null -eq $got -or $null -eq $got.PSObject.Properties["realScale"] -or $got.realScale -isnot [string] -or $words -cnotcontains $got.realScale) {
        return [pscustomobject]@{ state = "unavailable"; awareness = "unknown"; realScale = "unknown"; reason = $asked.reason }
    }
    return $got
}

function Get-HordeWindowFollowRectangle {
    # Where another window is, as an answer (header). Never throws.
    param([Parameter(Mandatory = $true)][long]$Handle)
    if ($Handle -le 0) { return (New-HordeUnknown -Reason "no window was named, so there is none to measure") }
    $asked = Invoke-HordeWindowFollower -Verb "rectangle" -With @($Handle)
    if (-not $asked.asked -or -not (Test-HordeAnswer $asked.value)) { return (New-HordeUnknown -Reason $asked.reason) }
    if ($asked.value.state -cne "known") { return $asked.value }
    $at = $asked.value.value
    foreach ($side in @("left", "top", "right", "bottom")) { if ($null -eq (Get-HordeWindowFollowWhole -From $at -Name $side)) { return (New-HordeUnknown -Reason $asked.reason) } }
    $scale = $at.PSObject.Properties["scale"]
    if ($null -eq $scale -or ($scale.Value -isnot [double] -and $scale.Value -isnot [int])) { return (New-HordeUnknown -Reason $asked.reason) }
    return $asked.value
}

function Start-HordeWindowFollow {
    # Make -Companion the companion of -Target (header). Never throws; answers a follow record.
    param([Parameter(Mandatory = $true)][long]$Target, [Parameter(Mandatory = $true)][long]$Companion, [string]$Mode = "floating", $Settings = $null)
    if (@(Get-HordeWindowFollowModes) -cnotcontains $Mode) { return (New-HordeWindowFollowRecord -State "failed" -Reason ("'" + $Mode + "' is not a way a window is followed")) }
    if ($Target -le 0) { return (New-HordeWindowFollowRecord -State "failed" -Reason "no window to stand beside was named") }
    if ($Companion -le 0) { return (New-HordeWindowFollowRecord -State "failed" -Reason "no window to place was named") }
    if ($Target -eq $Companion) { return (New-HordeWindowFollowRecord -State "failed" -Reason "a window cannot stand beside itself") }
    $found = [string[]]@()
    $with = $Settings
    if ($null -eq $with) {
        # No settings handed in: the person's own, read here, and what is wrong in their file is
        # answered with the record, so that a caller who read nothing still cannot lose a finding.
        try { $read = Get-HordeWindowFollowSettings } catch { return (New-HordeWindowFollowRecord -State "failed" -Reason ("the settings could not be read: " + $_.Exception.Message)) }
        $with = $read.values; $found = [string[]]@($read.findings)
    }
    else { $fault = Get-HordeWindowFollowSettingsFault -Settings $with; if ($fault -ne "") { return (New-HordeWindowFollowRecord -State "failed" -Reason $fault) } }
    $record = ConvertTo-HordeWindowFollowRecord -Asked (Invoke-HordeWindowFollower -Verb "start" -With @($Target, $Companion, $Mode, $with))
    $record.findings = $found
    return $record
}

function Get-HordeWindowFollow {
    # The follow record as it is now; nothing is moved (header).
    return (ConvertTo-HordeWindowFollowRecord -Asked (Invoke-HordeWindowFollower -Verb "update" -With @($false)))
}

function Update-HordeWindowFollow {
    # The follow record, after the companion is placed again (header).
    return (ConvertTo-HordeWindowFollowRecord -Asked (Invoke-HordeWindowFollower -Verb "update" -With @($true)))
}

function Disconnect-HordeWindowFollow {
    # Let the companion go: it stands free (header).
    return (ConvertTo-HordeWindowFollowRecord -Asked (Invoke-HordeWindowFollower -Verb "release"))
}

function Stop-HordeWindowFollow {
    # Stop following altogether (header).
    return (ConvertTo-HordeWindowFollowRecord -Asked (Invoke-HordeWindowFollower -Verb "stop"))
}

function Get-HordeWindowFollowHandStates {
    # Every state an answer of Switch-HordeWindowFollowKeyboard can carry.
    return @("handed", "refused", "none", "unavailable")
}

function Switch-HordeWindowFollowKeyboard {
    # Hand the keyboard to the other window (header): { state; reason }. Never throws.
    $follower = Get-HordeWindowFollower
    if ($follower.state -cne "known") { return [pscustomobject]@{ state = "unavailable"; reason = $follower.reason } }
    if ($null -eq $follower.value.hand) { return [pscustomobject]@{ state = "unavailable"; reason = ($follower.value.name + ": its follower has no way to hand the keyboard to another window") } }
    $asked = Invoke-HordeWindowFollower -Verb "hand"
    $got = $asked.value
    if (-not $asked.asked -or $null -eq $got -or $null -eq $got.PSObject.Properties["state"] -or $null -eq $got.PSObject.Properties["reason"] -or $got.state -isnot [string] -or @("handed", "refused", "none") -cnotcontains $got.state) {
        return [pscustomobject]@{ state = "unavailable"; reason = $asked.reason }
    }
    return [pscustomobject]@{ state = $got.state; reason = ("" + $got.reason) }
}
