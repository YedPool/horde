# decisions/Window.ps1 - `horde decisions open`: the list of questions in a window Horde owns, standing
# beside the terminal window of the session that keeps the list.
#
# THIS FILE ONLY PUTS FOUR PARTS TOGETHER, and is the only place that knows all four (decisions design
# 2026-10-06, "how it is put together so it can grow"; attach design of the same day). Each is asked
# through its port and none is named:
#   a surface shows a page          surfaces/Port.ps1 - asked for by what it can do
#   a window follows a window       core/WindowFollowPort.ps1 - two native handles; no platform's
#                                   function is called from here
#   a session's terminal window     core/SessionSeat.ps1 (who holds the role, and where it sits) and
#                                   core/HostWindow.ps1 (the terminal's own adapter names the window)
#   the pages                       decisions/window (the frame), decisions/page (the document) and
#                                   fleet/line (the fleet line), with fleet/StatusPanel.ps1 reading
#                                   what that line shows
# None of the four knows another. A later way of showing the list - a file for a phone, a view across
# a link - is another surface under the same bridge, and nothing here but the choice of surface moves.
#
# WHAT THE PAGE MAY ASK is the closed list below, seven requests, and nothing else (surfaces/Port.ps1
# checks every message before a handler sees it): setup, kinds, list, fleet, attachment, report, say.
# kinds and list are the decisions operations of those names, called through decisions/Operations.ps1's
# one entry point: THIS FILE READS NO RECORD OF THE STORE.
#
# ANSWERING (TRIAL). say is the one request that writes: the founder's words under a question, typed
# in the window. It is the operation say, asked with speaker founder, route window, the wording the
# page showed and an id the page chose (so the same words sent twice are one record). What may be
# said is decided by the operation and its rules alone; a refusal is ANSWERED, as { ok = false;
# reason }, in the rule's own sentence, so that the page can show it under the words it keeps.
# THE LIST THE PAGE IS HANDED CARRIES EACH CONVERSATION: the list operation gives a thread's counts
# and whose turn it is, and for a question somebody has spoken under the operation show is asked for
# its messages, once per change of that thread (Add-HordeDecisionWindowThreads keeps what it was
# given by what the list said of the thread). Each message says who has not read it (the store's
# own), and "told": whether a notifier has announced it, read from the file -ToldMarks names -
# { schemaVersion: 1, rung: [ { question, message, at } ] }, message being the record's number. That
# file is somebody else's and is only ever read; missing or not what it should be, nothing is marked
# told, the report says why, and answering goes on.
# -Probe names a file of steps for a check of the page that cannot press keys: { n; steps }, pushed
# to the page once per n, which acts them out on its own fields and nowhere else. The file may also
# hold keys: REAL key presses and typed text, { key; shift; ctrl } or { text }, which the surface
# hands to its own input for this page alone (surfaces/Port.ps1, probeInput: asked for only when
# -Probe is given) BEFORE the steps of the same n are pushed. Nothing is sent to the desktop.
#
# WHAT THE PAGE DREW, IN ITS OWN WORDS (the request report). After each change the page says what
# stands in it: every question line's number and text as drawn, the headings, which are unfolded, the
# fleet line, and the computed size of its letters with the screen's scale. Counts alone could not
# see a question that vanished from the page while the count stayed right (measured 2026-10-06 by the
# review of the earlier page: two questions in a group named __proto__ were drawn as one, twice, and
# the page reported the right number of rows). The report is what -Report writes, and what a scenario
# holds against the list. IT IS BOUNDED, by the one table below ($script:HordeDecisionWindowReportBounds):
# at most 400 question lines, 200 sub-lines and 80 fleet lines, 400 characters of each, and 60,000
# characters in all as the text of one message - less if the person's surface settings allow a
# message less. What does not fit is left out from the end and counted, and the page says how many.
#
# THE LIST REDRAWS WHEN THE STORE CHANGES. The store's folder is watched - the folder, whatever is in
# it: what a record's file is called is the store's own business (decisions/Store.ps1), and this file
# asks only where the folder is. It may not exist yet: it is made by the first question, and the
# watch starts when it appears. Changes are gathered for a moment (the setting changeQuietMs),
# because one command writes one record and a burst of them should be one redraw; then the list is
# asked for again and pushed to the page ONLY IF it differs from what the page was last given.
# AND WHEN NO CHANGE IS HEARD the list is asked for again all the same, every listRereadMs (30 s): a
# watch can fail without a word - more changes at once than its buffer holds, the folder removed and
# made again - and the list must not stay stale with nothing said. A watch that reports its own
# failure is counted, ended and started again on the next tick.
#
# ATTACHED, OR SAYING WHY NOT. The window stands beside the terminal window of the session that holds
# a role (the setting role: warchief, the session that keeps the list), found from the fleet's
# records and that terminal's own listing. When no such window can be proven it stands free, as an
# ordinary window, and its page says so with the reason. A window is never guessed. When the terminal
# window goes, the follower has already set this one free (core/WindowFollowPort.ps1, "lost"), and
# the page says that. -Hidden and -OffScreen are never attached. IT NEVER TAKES THE KEYBOARD when it
# appears, attached or free: no surface does unless asked (surfaces/Port.ps1), and this file never asks.
#
# ONE WINDOW PER HOME. A second `open` finds the first, asks it to come forward and returns at once
# with a plain sentence. THE TWO THINGS THAT CARRY THIS ARE THIS PLATFORM'S: a named mutex says "a
# window of this home is open" and a named event carries "come forward", both in the logon session's
# own namespace (the Local\ prefix), their name ending in a fingerprint of HORDE_HOME so that a
# test's window on a home of its own never meets the real one. A system without named kernel objects
# would hold a lock file under the home and listen on a local socket or a signal instead: that is the
# lines under ONE WINDOW PER HOME in Open-HordeDecisionWindow and the first line of the tick, and
# nothing else here.
# WHAT "COME FORWARD" DOES is the surface's and then the system's: the first window counts that it
# was asked and asks its surface to show it. Windows gives the keyboard only to a program the person
# is already using, so a window asked by a command in another program is, as a rule, not raised:
# measured 2026-10-07 by test/e2e/e2e-decisions-window.ps1, which prints what happened on each run -
# a real first window standing where no screen is counted that it was asked, was not made the
# foreground window, and what had the keyboard kept it. Whether its taskbar button flashed was not
# looked at; a companion has no taskbar button to flash.
#
# THE COMMAND STAYS UNTIL THE WINDOW IS CLOSED, and exits 0 then. A caller that wants its prompt back
# starts it in the background.
#
# WHAT IT WRITES: the web engine's own profile, under <HordeHome>\cache\decisions-window, and the
# files -Report and -Picture name. Nothing else, and never the store. A home that cannot be written
# is refused by the surface at once, in its own plain words, which are handed on.
#
# -Picture SAVES A PICTURE OF THE PAGE AS IT IS DRAWN, once, when the page has reported what it drew
# and been quiet for a moment (pictureSettleMs). It is the surface's own capture; the page cannot ask.
# -Unfold AND -Orc say what the reader is shown first: these questions unfolded; the fleet line
# unfolded with that Orc picked. The session that opens the window to point at a question uses them,
# and so does a check of the page that cannot click.
#
# EVERY NUMBER A PERSON MIGHT TUNE IS A SETTING of the module "decisions-window"
# (core/ModuleSettings.ps1, <HordeHome>\settings\decisions-window.json), declared once below; the
# rest are named constants with their reasons. The surface's and the follower's settings are theirs;
# each is read ONCE here and handed to its owner, and what was wrong in any of the three files is
# said on the command line, on the page and in -Report.
#
# A CALLBACK TAKES WHAT IT NEEDS FROM ITS $State, never from a local of the function that wrote it
# (surfaces/Port.ps1): the file watcher's handlers, which no surface calls, read the same object from
# $script:HordeDecisionWindow.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Operations.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "surfaces\Port.ps1")
foreach ($surfaceFile in @(Get-HordeSurfaceFiles)) { . $surfaceFile }
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\WindowFollowPort.ps1")
foreach ($followerFile in @(Get-HordeWindowFollowerFiles)) { . $followerFile }
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\SessionSeat.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\HostWindow.ps1")
foreach ($finderFile in @(Get-HordeHostWindowFinderFiles)) { . $finderFile }
. (Join-Path (Split-Path -Parent $PSScriptRoot) "fleet\StatusPanel.ps1")

# What a surface must be able to do to show this window.
$script:HordeDecisionWindowNeeds = @("page.local", "page.locked", "requests.closed", "push", "window.native")
# The module's name: its settings file, and the folder under the home's cache the surface keeps its
# own files in, are both named after it and nowhere else.
$script:HordeDecisionWindowModule = "decisions-window"
# How many characters of the home's fingerprint end the window's name. 16 hex are 64 bits: two homes
# on one machine do not meet by chance, and the name stays short enough to read in a list of handles.
$script:HordeDecisionWindowNameHexChars = 16
# How many of the surface's errors -Report repeats: the newest few say what is failing now, and the
# report is rewritten on every change.
$script:HordeDecisionWindowReportErrors = 5
# Where -OffScreen stands the window: where no screen is, at the place Windows itself gives a window
# it has put away. Real, visible to Windows and in the taskbar, and in front of nobody.
$script:HordeDecisionWindowOffScreen = [pscustomobject]@{ left = -32000; top = -32000 }
# THE BOUNDS OF WHAT THE PAGE MAY REPORT (header). One table: the page is handed it in the answer to
# setup and carries no number of its own. Named constants and not settings: they bound a message
# between two halves of Horde, which only a change to both could need moved. quietMs is how long the
# page waits after a change before it reports, so that one redraw is one report.
$script:HordeDecisionWindowReportBounds = [pscustomobject]@{ lines = 400; subLines = 200; fleetRows = 80; lineChars = 400; textChars = 2000; chars = 60000; quietMs = 60 }
# What a message is besides its one argument: the envelope the bridge wraps a report in. The report's
# own bound is the surface's most for a message less this, when a person has set that most low.
$script:HordeDecisionWindowEnvelopeChars = 1024

# THE SETTINGS OF THE MODULE (header). The role's allowed values are the role table's own.
$script:HordeDecisionWindowSettings = New-HordeModuleSettings -Module $script:HordeDecisionWindowModule -Settings @(
    @{ name = "role"; kind = "text"; default = "warchief"; values = @((Get-HordeRoleTable).native); what = "The role whose session's terminal window the window stands beside: the session that keeps the list." }
    @{ name = "changeQuietMs"; kind = "whole"; default = 400; min = 50; max = 10000; what = "How long changes to the list are gathered before it is read again and redrawn, in milliseconds." }
    @{ name = "listRereadMs"; kind = "whole"; default = 30000; min = 1000; max = 3600000; what = "How often the list is read again when no change to it was heard, in milliseconds." }
    @{ name = "fleetReadMs"; kind = "whole"; default = 5000; min = 1000; max = 600000; what = "How often the Orcs' status records are read again, in milliseconds." }
    @{ name = "followCheckMs"; kind = "whole"; default = 1000; min = 100; max = 60000; what = "How often the window is placed again beside the terminal window whatever was reported, and asked whether that window is still there, in milliseconds." }
    @{ name = "pictureSettleMs"; kind = "whole"; default = 700; min = 100; max = 10000; what = "How long the page must have drawn nothing new before -Picture saves its picture, in milliseconds." }
    @{ name = "fontFamily"; kind = "text"; default = '"Segoe UI Variable Text", "Segoe UI", system-ui, sans-serif'; min = 1; max = 200; what = "The font families the page is drawn in, first choice first, as a style sheet writes them." }
    @{ name = "textPx"; kind = "whole"; default = 14; min = 10; max = 32; what = "The size of the page's letters, in pixels at the ordinary scale; drawn at the nearest whole number of the screen's own pixels." }
    @{ name = "linePx"; kind = "whole"; default = 22; min = 12; max = 64; what = "The height of a line of the page, in pixels at the ordinary scale." }
    @{ name = "smallTextPx"; kind = "whole"; default = 12; min = 9; max = 28; what = "The size of the page's small marks (its notice, its last line), in pixels at the ordinary scale." }
    @{ name = "foldedGroups"; kind = "text"; default = "Parked"; min = 1; max = 400; what = "The groups whose questions are kept folded at the foot of the page, out of the way of answering: their names exactly as the list writes them, a semicolon between two." }
    @{ name = "smallLinePx"; kind = "whole"; default = 18; min = 10; max = 56; what = "The height of a line of small marks, in pixels at the ordinary scale." }
)
$script:HordeDecisionWindow = $null
# Who types in the window, and by what route: the two labels of decisions/Rules.ps1 a say from here carries.
$script:HordeDecisionWindowSpeaker = "founder"
$script:HordeDecisionWindowRoute = "window"
# The most a file of announced messages, or of a check's steps, may be before it is left unread.
$script:HordeDecisionWindowSideFileBytes = 1048576

function Get-HordeDecisionWindowSettingsDeclaration { return $script:HordeDecisionWindowSettings }

function Get-HordeDecisionWindowSettings {
    # The module's settings as they are now: { values; findings; path } (core/ModuleSettings.ps1).
    param([string]$HordeHome = "")
    return (Get-HordeModuleSettings -Declaration $script:HordeDecisionWindowSettings -HordeHome $HordeHome)
}

function Get-HordeDecisionWindowName {
    # The name the one window of -HordeHome is known by to a second `open`: fixed words and a
    # fingerprint of the home's path, compared as Windows compares paths.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\').ToLowerInvariant())) | ForEach-Object { $_.ToString("x2") }) }
    finally { $sha.Dispose() }
    return ("horde-" + $script:HordeDecisionWindowModule + "-" + $hash.Substring(0, $script:HordeDecisionWindowNameHexChars))
}

function Get-HordeDecisionWindowDataFolder {
    # Where the surface keeps its own files for this window: under the home's cache, by the module's name.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return (Join-Path (Join-Path $HordeHome "cache") $script:HordeDecisionWindowModule)
}

function Get-HordeDecisionWindowTitle {
    # The window's title from a list answer's record: "Open decisions: 22, 16 waiting". When the list
    # could not be had, the title says that, never a count of nothing.
    param($Record)
    if ($null -eq $Record -or "$($Record.state)" -cne "known" -or "$($Record.value.outcome)" -cne "done") { return "Open decisions: the list could not be read" }
    $open = @($Record.value.questions | Where-Object { "$($_.state)" -ceq "open" })
    $waiting = @($open | Where-Object { @($_.waiting).Count -gt 0 }).Count
    return ("Open decisions: " + $open.Count + ", " + $waiting + " waiting")
}

function Get-HordeDecisionWindowRecord {
    # One decisions operation's answer as the plain record a page is handed: { state; value; reason },
    # core/Tristate.ps1's stored form without the time it was read, so that the same list read twice
    # is the same record.
    param([Parameter(Mandatory = $true)][string]$Operation, $Request = @{})
    $answer = Invoke-HordeDecision -Operation $Operation -Request $Request
    $record = ConvertTo-HordeAnswerRecord -Answer $answer
    return [pscustomobject]@{ state = "$($record.state)"; value = $record.value; reason = "$($record.reason)" }
}

function Read-HordeDecisionWindowToldMarks {
    # The messages a notifier has announced, from the file -Path names (header): { told; problem }.
    # told is a table keyed by a message's record number as text. A file that is not there, too
    # large, or not the agreed shape marks NOTHING, and problem says why in words; it never throws.
    param([string]$Path)
    $none = { param([string]$Why) return [pscustomobject]@{ told = @{}; problem = $Why } }
    if ("$Path" -eq "") { return (& $none "") }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return (& $none "the file of announced messages is not there yet, so no message is marked as told") }
    $parsed = $null
    try {
        if ((Get-Item -LiteralPath $Path).Length -gt $script:HordeDecisionWindowSideFileBytes) { return (& $none "the file of announced messages is larger than it may be, so no message is marked as told") }
        $parsed = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch { return (& $none "the file of announced messages could not be read as JSON, so no message is marked as told") }
    if ($null -eq $parsed -or $parsed -isnot [System.Management.Automation.PSCustomObject] -or $null -eq $parsed.PSObject.Properties["schemaVersion"] -or "$($parsed.schemaVersion)" -cne "1" -or $null -eq $parsed.PSObject.Properties["rung"]) {
        return (& $none "the file of announced messages is not version 1 with a list named rung, so no message is marked as told")
    }
    $told = @{}
    foreach ($entry in @($parsed.rung)) {
        if ($null -eq $entry -or $entry -isnot [System.Management.Automation.PSCustomObject] -or $null -eq $entry.PSObject.Properties["message"]) { continue }
        $id = "$($entry.message)"
        if ($id -cmatch '\A[1-9][0-9]{0,17}\z') { $told[$id] = $true }
    }
    return [pscustomobject]@{ told = $told; problem = "" }
}

function Add-HordeDecisionWindowThreads {
    # Put each conversation into a list record (header, THE LIST THE PAGE IS HANDED): for every
    # question somebody has spoken under, thread.messages, each with told. -Cache is a table this
    # function keeps between calls: a thread is asked for again only when what the list says of it
    # has changed. -Told is the table of announced messages. -Show answers the operation show for a
    # number, for a test that hands one in. A thread that could not be had says so (thread.problem)
    # and holds no message: never an old one passed off as current.
    param($Record, [System.Collections.IDictionary]$Cache, [System.Collections.IDictionary]$Told = @{}, [scriptblock]$Show = $null)
    if ($null -eq $Record -or "$($Record.state)" -cne "known" -or $null -eq $Record.value -or "$($Record.value.outcome)" -cne "done") { return $Record }
    if ($null -eq $Show) { $Show = { param($Number) return (Invoke-HordeDecision -Operation "show" -Request @{ number = [int]$Number }) } }
    foreach ($q in @($Record.value.questions)) {
        $messages = @(); $problem = ""
        if ([int]$q.thread.count -gt 0) {
            $key = "" + $q.state + "|" + $q.wordingVersion + "|" + (ConvertTo-Json -InputObject $q.thread -Compress -Depth 6)
            $kept = $Cache["" + $q.number]
            if ($null -ne $kept -and $kept.key -ceq $key) { $messages = @($kept.messages) }
            else {
                $shown = & $Show ([int]$q.number)
                if ($null -ne $shown -and "$($shown.state)" -ceq "known" -and "$($shown.value.outcome)" -ceq "done") {
                    $messages = @($shown.value.question.thread.messages)
                    $Cache["" + $q.number] = [pscustomobject]@{ key = $key; messages = $messages }
                }
                else { $problem = "the conversation under this question could not be read: " + $(if ($null -ne $shown) { "$($shown.reason)" } else { "no answer" }) }
            }
        }
        $views = @($messages | ForEach-Object {
            $view = [ordered]@{}
            foreach ($p in $_.PSObject.Properties) { $view[$p.Name] = $p.Value }
            $view["told"] = [bool]$Told.Contains("" + $_.sequence)
            [pscustomobject]$view
        })
        Add-Member -InputObject $q.thread -NotePropertyName messages -NotePropertyValue $views -Force
        Add-Member -InputObject $q.thread -NotePropertyName problem -NotePropertyValue $problem -Force
    }
    return $Record
}

function Get-HordeDecisionWindowList {
    # The whole list, every state: the page lists what is not open under its own heading. With
    # -State, each conversation is in it (Add-HordeDecisionWindowThreads).
    param($State = $null)
    $record = Get-HordeDecisionWindowRecord -Operation "list" -Request @{ state = "all" }
    if ($null -eq $State) { return $record }
    return (Add-HordeDecisionWindowThreads -Record $record -Cache $State.threadCache -Told $State.told)
}

function Invoke-HordeDecisionWindowSay {
    # The request say (header, ANSWERING): -Arguments is { number; text; wording; id } as the page
    # sent them. A PURE FUNCTION of them and of what -Invoke answers (the operations' entry point,
    # for a test that hands one in). IT NEVER THROWS FOR ANYTHING THE PAGE SENT and it decides
    # nothing about the words: the operation and its rules do. Returns
    #   { ok = true;  sequence; replayed; arrivedAfterClosing; saidToEarlierWording }  the words are stored
    #   { ok = false; reason }                                                         they are not, and why
    # A reason is the operation's own sentences, which never repeat the words.
    param($Arguments, [scriptblock]$Invoke = $null)
    $no = { param([string]$Why) return [pscustomobject]@{ ok = $false; reason = $Why } }
    $get = { param([string]$Name) if ($Arguments -is [System.Collections.IDictionary]) { if ($Arguments.Contains($Name)) { return $Arguments[$Name] }; return $null }; if ($null -ne $Arguments -and $null -ne $Arguments.PSObject.Properties[$Name]) { return $Arguments.PSObject.Properties[$Name].Value }; return $null }
    $number = & $get "number"; $text = & $get "text"; $wording = & $get "wording"; $id = & $get "id"
    if (($number -isnot [int] -and $number -isnot [long]) -or [long]$number -lt 1) { return (& $no "Not saved: the question's number did not arrive as a whole number from 1.") }
    if (($wording -isnot [int] -and $wording -isnot [long]) -or [long]$wording -lt 1) { return (& $no "Not saved: the wording that was on screen did not arrive as a whole number from 1.") }
    if ($text -isnot [string]) { return (& $no "Not saved: the words did not arrive as text.") }
    if ($id -isnot [string] -or $id -cnotmatch '\A[0-9a-f]{32}\z') { return (& $no "Not saved: the request carried no id of 32 lowercase hex digits.") }
    if ($null -eq $Invoke) { $Invoke = { param($Request) return (Invoke-HordeDecision -Operation "say" -Request $Request) } }
    $request = [ordered]@{ id = $id; actor = $script:HordeDecisionWindowSpeaker; number = [long]$number; speaker = $script:HordeDecisionWindowSpeaker; route = $script:HordeDecisionWindowRoute; text = $text; wordingVersion = [long]$wording }
    $answer = $null
    try { $answer = & $Invoke $request } catch { return (& $no ("Not saved: the list could not be asked: " + $_.Exception.Message)) }
    if ($null -eq $answer) { return (& $no "Not saved: the list gave no answer.") }
    if ("$($answer.state)" -cne "known") { return (& $no ("Not saved: " + $answer.reason)) }
    $value = $answer.value
    if ("$($value.outcome)" -ceq "refused") {
        $why = "$($value.reason)"
        $found = @($value.findings | ForEach-Object { "" + $_ } | Where-Object { $_ -ne "" -and $_ -cne $why })
        if ($found.Count -gt 0) { $why = $why + ": " + ($found -join "; ") }
        return (& $no ("Not saved: " + $why))
    }
    $message = $value.message
    return [pscustomobject]@{ ok = $true; sequence = [long]$value.sequence; replayed = [bool]("$($value.outcome)" -ceq "replayed")
        arrivedAfterClosing = [bool]($null -ne $message -and $message.arrivedAfterClosing); saidToEarlierWording = [bool]($null -ne $message -and $message.saidToEarlierWording) }
}

function Read-HordeDecisionWindowProbe {
    # A check's steps from the file -Path names (header, -Probe): { n; steps } or $null when the file
    # is not there, too large, or not that shape. Never throws.
    param([string]$Path)
    if ("$Path" -eq "" -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        if ((Get-Item -LiteralPath $Path).Length -gt $script:HordeDecisionWindowSideFileBytes) { return $null }
        $parsed = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($null -eq $parsed -or ($parsed.n -isnot [int] -and $parsed.n -isnot [long]) -or [long]$parsed.n -lt 1) { return $null }
        $keys = @()
        if ($null -ne $parsed.PSObject.Properties["keys"]) { $keys = @($parsed.keys | Where-Object { $null -ne $_ }) }
        $steps = @()
        if ($null -ne $parsed.PSObject.Properties["steps"]) { $steps = @($parsed.steps | Where-Object { $null -ne $_ }) }
        return [pscustomobject]@{ n = [long]$parsed.n; steps = $steps; keys = $keys }
    } catch { return $null }
}

function Get-HordeDecisionWindowFleet {
    # The fleet's status as the fleet line is handed it, and the text it is compared by. An Orc's file
    # ages every second without changing; compared with its age in whole minutes, the line is redrawn
    # when something was written or a minute turned, not every time it is read.
    $status = Get-HordeFleetStatus
    $coarse = @($status.orcs | ForEach-Object { "" + $_.folder + "|" + $_.written + "|" + $_.orc + "|" + $_.lane + "|" + $_.doing + "|" + $_.finished + "|" + $_.blocked + "|" + $_.blockedBy + "|" + (@($_.problems) -join ";") + "|" + [Math]::Floor($_.ageSeconds / 60) })
    return [pscustomobject]@{ status = $status; signature = ($status.state + "|" + $status.reason + "|" + $status.notRead + "|" + (@($status.findings) -join ";") + "|" + ($coarse -join "`n")) }
}

function Resolve-HordeDecisionWindowAttachment {
    # Which window to stand beside, as { attached; handle; reason }: attached only when the session
    # that holds -Role has a seat and a terminal's adapter proves that seat's window (header,
    # ATTACHED, OR SAYING WHY NOT). Everything else is not attached, with the reason in words.
    # -Identity is a reading of who is running, for a test that made one (core/SessionSeat.ps1).
    param([Parameter(Mandatory = $true)][string]$Role, [switch]$Hidden, [switch]$OffScreen, $Identity = $null)
    $free = { param([string]$Why) return [pscustomobject]@{ attached = $false; handle = [long]0; reason = $Why } }
    if ($Hidden) { return (& $free "it was opened hidden, and a hidden window stands beside nothing") }
    if ($OffScreen) { return (& $free "it was opened where no screen is, and stands beside nothing there") }
    $seat = $null
    try { if ($null -ne $Identity) { $seat = Get-HordeRoleSeat -Role $Role -Identity $Identity } else { $seat = Get-HordeRoleSeat -Role $Role } }
    catch { return (& $free ("the fleet's session records could not be read: " + $_.Exception.Message)) }
    if ($seat.state -ceq "absent") { return (& $free ("no session holds the role of " + $Role + ", so there is no terminal window to stand beside")) }
    if ($seat.state -cne "known") { return (& $free $seat.reason) }
    $window = Find-HordeSessionWindow -Seat $seat.value
    if ($window.state -cne "known") { return (& $free $window.reason) }
    return [pscustomobject]@{ attached = $true; handle = [long]$window.value.handle; reason = "" }
}

function ConvertTo-HordeDecisionWindowView {
    # What the reader is shown first, from the command's -Unfold and -Orc: { unfold; fleetOpen; pick }.
    # Throws, in words, for a value that is not what the flag takes.
    param([string]$Unfold = "", [string]$Orc = "")
    $numbers = @()
    if ($Unfold -ne "") {
        if ($Unfold -cnotmatch '\A[1-9][0-9]{0,8}(,[1-9][0-9]{0,8}){0,49}\z') { throw "-Unfold takes question numbers with commas between them and nothing else, as in -Unfold 3,7" }
        $numbers = @($Unfold -split "," | ForEach-Object { [int]$_ })
    }
    if ($Orc -ne "" -and $Orc -cnotmatch '\A[A-Z]\z') { throw "-Orc takes the one capital letter an Orc is known by, as in -Orc B" }
    return [pscustomobject]@{ unfold = $numbers; fleetOpen = [bool]($Orc -ne ""); pick = $Orc }
}

function ConvertFrom-HordeDecisionWindowDrawn {
    # What the page says it drew, from the text of its report: { ok; value; reason }. A PURE FUNCTION
    # of the text and the bounds. The page is not trusted: the text is held to the shape and the
    # bounds it was told (header, WHAT THE PAGE DREW), and anything else is refused in words that
    # repeat nothing it sent.
    param([AllowNull()][AllowEmptyString()][string]$Text, $Bounds = $script:HordeDecisionWindowReportBounds)
    $bad = { param([string]$Why) return [pscustomobject]@{ ok = $false; value = $null; reason = ("the page's report " + $Why) } }
    $drawn = $null
    try { $drawn = "$Text" | ConvertFrom-Json } catch { $drawn = $null }
    if ($null -eq $drawn -or $drawn -isnot [System.Management.Automation.PSCustomObject]) { return (& $bad "is not one JSON object") }
    $has = { param($Object, [string]$Name) return ($null -ne $Object -and $Object -is [System.Management.Automation.PSCustomObject] -and $null -ne $Object.PSObject.Properties[$Name]) }
    foreach ($name in @("v", "draws", "counts", "headings", "lines", "sub", "fleet", "notice", "foot", "text", "left")) { if (-not (& $has $drawn $name)) { return (& $bad ("has no member " + $name)) } }
    if ($drawn.v -isnot [int] -or $drawn.v -ne 1) { return (& $bad "is not version 1") }
    $lists = @(@{ name = "headings"; most = $Bounds.lines }, @{ name = "lines"; most = $Bounds.lines }, @{ name = "sub"; most = $Bounds.subLines })
    foreach ($list in $lists) {
        $items = $drawn.PSObject.Properties[$list.name].Value
        if ($null -ne $items -and $items -isnot [array]) { return (& $bad ("gives " + $list.name + " as something that is not a list")) }
        if (@($items).Count -gt $list.most) { return (& $bad ("holds " + @($items).Count + " " + $list.name + ", more than the " + $list.most + " it may")) }
        foreach ($item in @($items)) {
            if (-not (& $has $item "t") -or $item.t -isnot [string] -or $item.t.Length -gt $Bounds.lineChars) { return (& $bad ("holds one of its " + $list.name + " with no text, or with more than " + $Bounds.lineChars + " characters of it")) }
            if ($list.name -cne "headings" -and (-not (& $has $item "n") -or $item.n -isnot [string] -or $item.n -cnotmatch '\A[0-9]{1,9}(\.[0-9]{1,4})?\z')) { return (& $bad ("holds one of its " + $list.name + " with no number")) }
        }
    }
    foreach ($line in @($drawn.lines)) {
        if (-not (& $has $line "s") -or $line.s -isnot [string] -or $line.s.Length -gt $Bounds.lineChars -or -not (& $has $line "open") -or $line.open -isnot [bool] -or -not (& $has $line "dim") -or $line.dim -isnot [bool] -or -not (& $has $line "g") -or $line.g -isnot [int]) { return (& $bad "holds a question line that does not say its suffix, its heading, and whether it is unfolded and dimmed") }
    }
    if (-not (& $has $drawn.fleet "head") -or $drawn.fleet.head -isnot [string] -or $drawn.fleet.head.Length -gt $Bounds.textChars -or -not (& $has $drawn.fleet "rows") -or @($drawn.fleet.rows).Count -gt $Bounds.fleetRows) { return (& $bad "does not say what the fleet line shows, within its bounds") }
    foreach ($row in @($drawn.fleet.rows)) { if ($row -isnot [string] -or $row.Length -gt $Bounds.lineChars) { return (& $bad "holds a fleet line that is not text within its bounds") } }
    if ($drawn.notice -isnot [string] -or $drawn.notice.Length -gt $Bounds.textChars -or $drawn.foot -isnot [string] -or $drawn.foot.Length -gt $Bounds.lineChars) { return (& $bad "does not give its notice and its last line as text within their bounds") }
    foreach ($name in @("fontPx", "linePx", "smallFontPx", "smallLinePx", "ratio")) {
        if (-not (& $has $drawn.text $name)) { return (& $bad ("does not say the letters' " + $name)) }
        $number = $drawn.text.PSObject.Properties[$name].Value
        if ($null -ne $number -and $number -isnot [int] -and $number -isnot [long] -and $number -isnot [decimal] -and $number -isnot [double]) { return (& $bad ("gives the letters' " + $name + " as something that is not a number")) }
    }
    return [pscustomobject]@{ ok = $true; value = $drawn; reason = "" }
}

function Get-HordeDecisionWindowReportBounds {
    # The bounds the page is handed (header): the table, with the whole report's most lowered to what
    # one message of -Bridge may be, less its envelope, when a person's surface setting is below it.
    param($Bridge = $null)
    $b = $script:HordeDecisionWindowReportBounds
    $chars = [int]$b.chars
    if ($null -ne $Bridge) { $chars = [Math]::Min($chars, [int]$Bridge.limits.messageChars - $script:HordeDecisionWindowEnvelopeChars) }
    return [pscustomobject]@{ lines = $b.lines; subLines = $b.subLines; fleetRows = $b.fleetRows; lineChars = $b.lineChars; textChars = $b.textChars; chars = $chars; quietMs = $b.quietMs }
}

function New-HordeDecisionWindowBridge {
    # THE CLOSED LIST of what the page may ask, and of what it may be pushed (header). Each handler
    # reads the state it is handed; none takes anything from here. -SurfaceSettings is the answer of
    # Get-HordeSurfaceSettings, read once by the caller.
    param($SurfaceSettings = $null)
    $most = [long]$script:HordeDecisionWindowReportBounds.chars
    return (New-HordeSurfaceBridge -Settings $SurfaceSettings -Events @("list-changed", "fleet-changed", "attachment-changed", "probe") -Requests ([ordered]@{
        # What the page needs before it draws a letter: the letters themselves, the bounds of its
        # report, what to show first, and what was wrong in the settings files.
        "setup" = @{ run = { param($Arguments, $State, $Window)
            $v = $State.settings
            return [pscustomobject]@{
                look = [pscustomobject]@{ fontFamily = "$($v.fontFamily)"; textPx = [int]$v.textPx; linePx = [int]$v.linePx; smallTextPx = [int]$v.smallTextPx; smallLinePx = [int]$v.smallLinePx }
                report = (Get-HordeDecisionWindowReportBounds -Bridge $State.bridge)
                view = $State.view
                # PARKED (TRIAL): a question set aside is, for now, a question whose group is one of
                # these. A state of its own, with its own record, is the proper form and a later unit's.
                foldedGroups = @("$($v.foldedGroups)" -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
                findings = @($State.findings | ForEach-Object { "" + $_ })
            } } }
        "kinds" = @{ run = { param($Arguments, $State, $Window) return (Get-HordeDecisionWindowRecord -Operation "kinds") } }
        "list" = @{ run = { param($Arguments, $State, $Window)
            $record = Get-HordeDecisionWindowList -State $State
            # What the page now has, so that the next change is compared with it and not pushed twice.
            $State.listJson = ConvertTo-HordeSurfaceJson -Value $record
            $State.listReadAt = [datetime]::UtcNow
            $State.title = Get-HordeDecisionWindowTitle -Record $record
            if ($null -ne $Window) { & $Window.setTitle $State.title }
            $State.reportDue = $true
            return $record } }
        "fleet" = @{ run = { param($Arguments, $State, $Window)
            $fleet = Get-HordeDecisionWindowFleet
            $State.fleetSignature = $fleet.signature
            return $fleet.status } }
        "attachment" = @{ run = { param($Arguments, $State, $Window) return [pscustomobject]@{ attached = [bool]$State.attachment.attached; reason = "$($State.attachment.reason)" } } }
        "report" = @{
            args = @{ text = @{ type = "string"; most = $most } }
            run = { param($Arguments, $State, $Window)
                $drawn = ConvertFrom-HordeDecisionWindowDrawn -Text $Arguments["text"] -Bounds (Get-HordeDecisionWindowReportBounds -Bridge $State.bridge)
                if (-not $drawn.ok) { $State.reportsRefused = [int]$State.reportsRefused + 1; throw $drawn.reason }
                $State.drawn = $drawn.value
                $State.reports = [int]$State.reports + 1
                $State.lastReportAt = [datetime]::UtcNow
                $State.reportDue = $true
                return $true }
        }
        # THE ONE REQUEST THAT WRITES (header, ANSWERING). The words' most is the rules' own for any
        # text; one message of the bridge may be less, and a longer one is refused there unread.
        "say" = @{
            args = @{ number = @{ type = "integer"; most = (Get-HordeDecisionMaxNumber) }; text = @{ type = "string"; most = $script:HordeDecisionMaxTextChars }; wording = @{ type = "integer"; most = (Get-HordeDecisionMaxNumber) }; id = @{ type = "string"; most = 32 } }
            run = { param($Arguments, $State, $Window)
                $said = Invoke-HordeDecisionWindowSay -Arguments $Arguments
                if ($said.ok) { $State.says = [int]$State.says + 1; $State.dirtyAt = [datetime]::UtcNow } else { $State.saysRefused = [int]$State.saysRefused + 1 }
                $State.reportDue = $true
                return $said }
        }
    }))
}

function New-HordeDecisionWindowState {
    # The one object every callback and handler of an open window reads and writes. -Settings is the
    # module's values; -Findings what was wrong in any settings file read for this window.
    param([string]$ReportPath = "", $Attachment = $null, [datetime]$Now = [datetime]::UtcNow, [string]$PicturePath = "", $Settings = $null, $SurfaceSettings = $null, $FollowSettings = $null, [string[]]$Findings = @(), $View = $null, [string]$ToldPath = "", [string]$ProbePath = "")
    if ($null -eq $Attachment) { $Attachment = [pscustomobject]@{ attached = $false; handle = [long]0; reason = "" } }
    if ($null -eq $Settings) { $Settings = (Read-HordeModuleSettingsText -Declaration $script:HordeDecisionWindowSettings -Text $null).values }
    if ($null -eq $View) { $View = ConvertTo-HordeDecisionWindowView }
    $storeRoot = ""
    try { $storeRoot = Get-HordeDecisionStoreRoot } catch { $storeRoot = "" }
    return [pscustomobject]@{
        bridge = (New-HordeDecisionWindowBridge -SurfaceSettings $SurfaceSettings); settings = $Settings; followSettings = $FollowSettings; findings = @($Findings); view = $View
        storeRoot = $storeRoot; watcher = $null; watchFailed = $false; watchFailures = 0; dirtyAt = $null
        listJson = ""; listReadAt = $Now; rereads = 0; title = ""; fleetSignature = ""; fleetDueAt = $Now; followDueAt = $Now
        attachment = $Attachment; followed = $false; lost = $false
        reportPath = $ReportPath; reportDue = $true; drawn = $null; reports = 0; reportsRefused = 0; pushes = 0; changes = 0; errors = $null
        showEvent = $null; shows = 0; handle = [long]0; openedAt = $Now; firstReportAt = $null
        picturePath = $PicturePath; pictureAsked = $false; pictureSeen = $false; lastReportAt = $null
        threadCache = @{}; told = @{}; toldPath = $ToldPath; toldStamp = ""; toldProblem = ""; says = 0; saysRefused = 0
        probePath = $ProbePath; probeStamp = ""; probeSent = [long]0; probeHeld = $null
    }
}

function Set-HordeDecisionWindowDirty {
    # Called for every change in the store's folder, on the window's own thread: note when, and no more.
    $s = $script:HordeDecisionWindow
    if ($null -ne $s) { $s.dirtyAt = [datetime]::UtcNow; $s.changes = [int]$s.changes + 1 }
}

function Set-HordeDecisionWindowWatchFailed {
    # Called when the watch reports its own failure, on the window's own thread: note it, and ask for
    # the list again, since what was missed cannot be known. The tick ends the watch and starts another.
    $s = $script:HordeDecisionWindow
    if ($null -ne $s) { $s.watchFailed = $true; $s.watchFailures = [int]$s.watchFailures + 1; $s.dirtyAt = [datetime]::UtcNow }
}

function Stop-HordeDecisionWindowWatch {
    param([Parameter(Mandatory = $true)]$State)
    if ($null -ne $State.watcher) { try { $State.watcher.EnableRaisingEvents = $false; $State.watcher.Dispose() } catch { } }
    $State.watcher = $null
    $State.watchFailed = $false
}

function Start-HordeDecisionWindowWatch {
    # Watch the store's folder, once it exists: every file in it, by no name (header). Its events are
    # marshalled through -Sync to the window's thread, where the handlers - one line each, reading
    # the script's state - only note the time.
    #
    # NEVER WITHOUT -Sync. A watcher with nothing to marshal through calls its handler on a thread of
    # its own, where PowerShell has no way to run a script block, and the process ends at once with no
    # error to read (measured 2026-10-06: this file's suite stopped mid-run, exit 2, at the first record
    # written after a watch was started bare). So with no -Sync there is no watch.
    param([Parameter(Mandatory = $true)]$State, $Sync = $null)
    if ($null -eq $Sync) { return $false }
    if ($null -ne $State.watcher -or $State.storeRoot -eq "" -or -not (Test-Path -LiteralPath $State.storeRoot -PathType Container)) { return $false }
    $watcher = New-Object System.IO.FileSystemWatcher($State.storeRoot)
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
    $watcher.SynchronizingObject = $Sync
    $noted = { Set-HordeDecisionWindowDirty }
    $watcher.add_Created($noted); $watcher.add_Changed($noted); $watcher.add_Deleted($noted); $watcher.add_Renamed($noted)
    $watcher.add_Error({ Set-HordeDecisionWindowWatchFailed })
    $watcher.EnableRaisingEvents = $true
    $State.watcher = $watcher
    # Whatever was written between the page's first list and this moment is picked up by one refresh.
    $State.dirtyAt = [datetime]::UtcNow
    return $true
}

function Write-HordeDecisionWindowReport {
    # -Report's file: one JSON object saying what the window shows, replaced whole. Written beside
    # itself and moved into place, so a reader never finds half of it. drawn is the page's own report,
    # as it sent it (header, WHAT THE PAGE DREW).
    param([Parameter(Mandatory = $true)]$State)
    if ($State.reportPath -eq "") { return }
    $follow = Get-HordeWindowFollow
    $placed = $null
    if ($null -ne $follow -and $null -ne $follow.placed) { $placed = [ordered]@{ left = $follow.placed.left; top = $follow.placed.top; width = $follow.placed.width; height = $follow.placed.height } }
    if ($State.reports -ge 1 -and $null -eq $State.firstReportAt) { $State.firstReportAt = [datetime]::UtcNow }
    $seconds = $null
    if ($null -ne $State.firstReportAt) { $seconds = [Math]::Round(($State.firstReportAt - $State.openedAt).TotalSeconds, 2) }
    $report = [ordered]@{
        schemaVersion = 2; pid = $PID; handle = [long]$State.handle; title = $State.title
        attachment = [ordered]@{ attached = [bool]$State.attachment.attached; reason = "$($State.attachment.reason)"; target = [long]$State.attachment.handle; follow = "$($follow.state)"; placed = $placed }
        drawn = $State.drawn; reports = [int]$State.reports; reportsRefused = [int]$State.reportsRefused; pushes = [int]$State.pushes; rereads = [int]$State.rereads
        picture = [ordered]@{ path = "$($State.picturePath)"; asked = [bool]$State.pictureAsked; saved = [bool]($State.picturePath -ne "" -and (Test-Path -LiteralPath $State.picturePath -PathType Leaf)) }
        refused = [int]$State.bridge.refused; watching = ($null -ne $State.watcher); watchFailures = [int]$State.watchFailures; changes = [int]$State.changes
        askedForward = [int]$State.shows
        says = [int]$State.says; saysRefused = [int]$State.saysRefused; toldMarks = [ordered]@{ path = "$($State.toldPath)"; told = @($State.told.Keys).Count; problem = "$($State.toldProblem)" }
        findings = @($State.findings)
        errors = @($State.errors | Where-Object { $null -ne $_ } | Select-Object -Last $script:HordeDecisionWindowReportErrors | ForEach-Object { "" + $_ })
        secondsToFirstReport = $seconds
    }
    $text = ConvertTo-HordeSurfaceJson -Value $report
    $temp = $State.reportPath + "." + $PID + ".tmp"
    [System.IO.File]::WriteAllText($temp, $text, (New-Object System.Text.UTF8Encoding($false)))
    # [NullString]::Value, not $null: PowerShell hands a .NET string parameter "" for $null, and Replace
    # read "" as the name of a backup file and threw "The path is not of a legal form" on every write
    # after the first (measured 2026-10-06: the report stayed at its first version while the window ran on).
    if (Test-Path -LiteralPath $State.reportPath -PathType Leaf) { [System.IO.File]::Replace($temp, $State.reportPath, [NullString]::Value) } else { [System.IO.File]::Move($temp, $State.reportPath) }
    $State.reportDue = $false
}

function Update-HordeDecisionWindowList {
    # Ask for the list again and push it to the page if it is not what the page has. Returns whether
    # it was pushed.
    param([Parameter(Mandatory = $true)]$State, $Window = $null, [datetime]$Now = [datetime]::UtcNow)
    $record = Get-HordeDecisionWindowList -State $State
    $State.listReadAt = $Now
    $json = ConvertTo-HordeSurfaceJson -Value $record
    if ($json -ceq $State.listJson) { return $false }
    $State.listJson = $json
    $State.title = Get-HordeDecisionWindowTitle -Record $record
    $State.pushes = [int]$State.pushes + 1
    $State.reportDue = $true
    if ($null -ne $Window) {
        & $Window.setTitle $State.title
        & $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "list-changed" -Value $record)
    }
    return $true
}

function Set-HordeDecisionWindowFree {
    # The window no longer stands beside anything: say so, to the report and to the page.
    param([Parameter(Mandatory = $true)]$State, $Window = $null, [Parameter(Mandatory = $true)][string]$Reason)
    $State.followed = $false
    $State.attachment = [pscustomobject]@{ attached = $false; handle = [long]0; reason = $Reason }
    $State.reportDue = $true
    if ($null -ne $Window) { & $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "attachment-changed" -Value ([pscustomobject]@{ attached = $false; reason = $Reason })) }
}

function Invoke-HordeDecisionWindowOpened {
    # The surface's engine is up. Stand beside the terminal window if one was proven, and start watching.
    param($Window, $State)
    $State.handle = [long]$Window.handle
    $State.errors = $Window.errors
    if ($State.attachment.attached) {
        $follow = Start-HordeWindowFollow -Target $State.attachment.handle -Companion $Window.handle -Settings $State.followSettings
        if ($follow.state -ceq "following") { $State.followed = $true }
        else { Set-HordeDecisionWindowFree -State $State -Reason ("the terminal window was found and could not be followed: " + $follow.reason) }
    }
    [void](Start-HordeDecisionWindowWatch -State $State -Sync $Window.sync)
    $State.reportDue = $true
}

function Invoke-HordeDecisionWindowTick {
    # On every tick, on the window's thread: a second `open` asking to be seen; the watch, started or
    # started again; a gathered change, or the list read again because none was heard; the Orcs'
    # files; the follow; the picture; the report.
    param($Window, $State, [datetime]$Now = [datetime]::UtcNow)
    if ($null -ne $State.showEvent -and $State.showEvent.WaitOne(0)) { $State.shows = [int]$State.shows + 1; $State.reportDue = $true; & $Window.show }
    if ($State.watchFailed) { Stop-HordeDecisionWindowWatch -State $State }
    if ($null -eq $State.watcher) { [void](Start-HordeDecisionWindowWatch -State $State -Sync $Window.sync) }
    # THE FILE OF ANNOUNCED MESSAGES (header): read again when it is not as it was last seen, and the
    # list with it. Its stamp is its time and size; a file that comes or goes is a change too.
    if ($State.toldPath -ne "") {
        $stamp = "none"
        try { $file = Get-Item -LiteralPath $State.toldPath -ErrorAction Stop; $stamp = "" + $file.LastWriteTimeUtc.Ticks + "|" + $file.Length } catch { $stamp = "none" }
        if ($stamp -cne $State.toldStamp) {
            $State.toldStamp = $stamp
            $marks = Read-HordeDecisionWindowToldMarks -Path $State.toldPath
            $State.told = $marks.told; $State.toldProblem = $marks.problem; $State.reportDue = $true
            if ($null -eq $State.dirtyAt) { $State.dirtyAt = $Now.AddMilliseconds(-1 * [int]$State.settings.changeQuietMs) }
        }
    }
    if ($State.probePath -ne "" -and [int]$State.reports -ge 1) {
        $stamp = "none"
        try { $file = Get-Item -LiteralPath $State.probePath -ErrorAction Stop; $stamp = "" + $file.LastWriteTimeUtc.Ticks + "|" + $file.Length } catch { $stamp = "none" }
        if ($stamp -cne $State.probeStamp) {
            $State.probeStamp = $stamp
            $probe = Read-HordeDecisionWindowProbe -Path $State.probePath
            if ($null -ne $probe -and [long]$probe.n -gt [long]$State.probeSent) {
                $State.probeSent = [long]$probe.n
                # The real keys first, by the surface's own input; the steps are pushed when it has
                # taken them all (below). A surface with no such input says so in the errors it keeps.
                if (@($probe.keys).Count -gt 0) {
                    if ($null -ne $Window.PSObject.Properties["input"]) { [void](& $Window.input @($probe.keys)) }
                    else { [void]$Window.errors.Add("a check's keys were not pressed: this window has no input of its own to hand them to") }
                }
                $State.probeHeld = [pscustomobject]@{ n = [long]$probe.n; steps = @($probe.steps) }
            }
        }
    }
    if ($null -ne $State.probeHeld -and ($null -eq $Window.PSObject.Properties["inputIdle"] -or [bool](& $Window.inputIdle))) {
        $held = $State.probeHeld
        $State.probeHeld = $null
        & $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "probe" -Value $held)
    }
    if ($null -ne $State.dirtyAt -and ($Now - $State.dirtyAt).TotalMilliseconds -ge $State.settings.changeQuietMs) {
        $State.dirtyAt = $null
        [void](Update-HordeDecisionWindowList -State $State -Window $Window -Now $Now)
    }
    elseif ($null -eq $State.dirtyAt -and ($Now - $State.listReadAt).TotalMilliseconds -ge $State.settings.listRereadMs) {
        # NO CHANGE WAS HEARD FOR THIS LONG (header): read it all the same.
        $State.rereads = [int]$State.rereads + 1
        $State.reportDue = $true
        [void](Update-HordeDecisionWindowList -State $State -Window $Window -Now $Now)
    }
    if ($Now -ge $State.fleetDueAt) {
        $State.fleetDueAt = $Now.AddMilliseconds($State.settings.fleetReadMs)
        $fleet = Get-HordeDecisionWindowFleet
        if ($fleet.signature -cne $State.fleetSignature) {
            $State.fleetSignature = $fleet.signature
            & $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "fleet-changed" -Value $fleet.status)
        }
    }
    if ($State.followed -and $Now -ge $State.followDueAt) {
        $State.followDueAt = $Now.AddMilliseconds($State.settings.followCheckMs)
        $follow = Update-HordeWindowFollow
        if ($follow.state -ceq "lost") {
            # The window it stood beside is gone, and the follower has already set this one free
            # (core/WindowFollowPort.ps1). It says so; finding the session's next window is a later unit's.
            $State.lost = $true
            Set-HordeDecisionWindowFree -State $State -Window $Window -Reason "the terminal window it stood beside is gone, and it stands free where it was"
        }
        elseif ($follow.state -cne "following") { Set-HordeDecisionWindowFree -State $State -Window $Window -Reason ("it stopped following the terminal window: " + $follow.reason) }
        $State.reportDue = $true
    }
    # -Picture: once, when the page has reported what it drew and has then been quiet for a moment.
    if ($State.picturePath -ne "" -and -not $State.pictureAsked -and $null -ne $State.lastReportAt -and ($Now - $State.lastReportAt).TotalMilliseconds -ge $State.settings.pictureSettleMs) {
        $State.pictureAsked = [bool](& $Window.capture $State.picturePath)
        $State.reportDue = $true
    }
    if ($State.pictureAsked -and -not $State.pictureSeen -and (Test-Path -LiteralPath $State.picturePath -PathType Leaf)) { $State.pictureSeen = $true; $State.reportDue = $true }
    if ($State.reportDue) { Write-HordeDecisionWindowReport -State $State }
}

function Invoke-HordeDecisionWindowClosed {
    param($Window, $State)
    Stop-HordeDecisionWindowWatch -State $State
    [void](Stop-HordeWindowFollow)
}

function Open-HordeDecisionWindow {
    # `horde decisions open`. Writes its lines as it goes and returns when the window has been closed;
    # throws, in words, when the window could not be shown. -Report is a file to keep an account of
    # what the window shows in; -Picture a .png to save a picture of the page in; -Hidden opens it
    # where nobody sees it and out of the taskbar; -OffScreen as an ordinary window where no screen
    # is; -Unfold and -Orc say what the reader is shown first (header).
    param([switch]$Hidden, [switch]$OffScreen, [string]$Report = "", [string]$Picture = "", [string]$Unfold = "", [string]$Orc = "", [string]$ToldMarks = "", [string]$Probe = "")
    $hordeHome = Get-HordeHome
    if ($Hidden -and $OffScreen) { throw "-Hidden and -OffScreen are two ways of standing where nobody sees it; give one of them" }
    $view = ConvertTo-HordeDecisionWindowView -Unfold $Unfold -Orc $Orc
    $picturePath = ""
    if ($Picture -ne "") {
        $picturePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Picture)
        if ([System.IO.Path]::GetExtension($picturePath) -ine ".png") { throw "-Picture names the file a picture of the window is saved in, and it must end .png" }
    }
    $toldPath = ""
    if ($ToldMarks -ne "") {
        if (-not [System.IO.Path]::IsPathRooted($ToldMarks)) { throw "-ToldMarks names the file of messages a notifier has announced, by its full path" }
        $toldPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ToldMarks)
    }
    $probePath = ""
    if ($Probe -ne "") { $probePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Probe) }
    $reportPath = ""
    if ($Report -ne "") { $reportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Report) }
    # ONE WINDOW PER HOME, by this platform's named objects (header).
    $name = Get-HordeDecisionWindowName -HordeHome $hordeHome
    $first = $false
    $mutex = New-Object System.Threading.Mutex($true, ("Local\" + $name), [ref]$first)
    $show = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, ("Local\" + $name + "-show"))
    if (-not $first) {
        [void]$show.Set()
        $show.Dispose(); $mutex.Dispose()
        Write-Output "The decisions window is already open; it was asked to come forward."
        return
    }
    try {
        $surface = Resolve-HordeSurface -Requires $script:HordeDecisionWindowNeeds
        if ($null -eq $surface) { throw "no way of showing a window is part of this Horde on this machine, so the decisions window cannot be opened; horde decisions list prints the same list" }
        if ($picturePath -ne "" -and -not (Test-HordeSurfaceCapability -Surface $surface -Capability "picture")) { throw "the way this Horde shows a window here cannot save a picture of it, so -Picture cannot be honoured" }
        # THE THREE SETTINGS FILES, each read once and handed to its owner (header).
        $own = Get-HordeDecisionWindowSettings -HordeHome $hordeHome
        $surfaceSettings = Get-HordeSurfaceSettings -HordeHome $hordeHome
        $followSettings = Get-HordeWindowFollowSettings -HordeHome $hordeHome
        $findings = @(@($own.findings) + @($surfaceSettings.findings) + @($followSettings.findings) | ForEach-Object { "" + $_ })
        foreach ($finding in $findings) { Write-Output ("A setting was not used: " + $finding) }
        # Real pixels before any window is read or made, or a rectangle read is a scaled one.
        [void](Enable-HordeWindowFollowRealScale)
        $attachment = Resolve-HordeDecisionWindowAttachment -Role $own.values.role -Hidden:$Hidden -OffScreen:$OffScreen
        $at = $null
        if ($attachment.attached) {
            # Where it will stand, worked out before it is shown, so that it does not first appear
            # mid-screen and then jump: the same pure rule the follower then keeps it by.
            $beside = Get-HordeWindowFollowRectangle -Handle $attachment.handle
            if ($beside.state -ceq "known") { $at = Get-HordeWindowFollowPlacement -Target $beside.value -Scale $beside.value.scale -Settings $followSettings.values }
            if ($null -eq $at -or $at.state -cne "known") {
                $why = "the terminal window was found, and where it is could not be read"
                if ($null -ne $at) { $why = $at.reason } elseif ("$($beside.reason)" -ne "") { $why = $beside.reason }
                $attachment = [pscustomobject]@{ attached = $false; handle = [long]0; reason = $why }
            }
        }
        $state = New-HordeDecisionWindowState -ReportPath $reportPath -Attachment $attachment -PicturePath $picturePath -Settings $own.values -SurfaceSettings $surfaceSettings -FollowSettings $followSettings.values -Findings $findings -View $view -ToldPath $toldPath -ProbePath $probePath
        $state.showEvent = $show
        $script:HordeDecisionWindow = $state
        $root = Split-Path -Parent $PSScriptRoot
        $specArgs = @{
            Title = "Open decisions"; Start = "window/index.html"; Bridge = $state.bridge; State = $state; Settings = $surfaceSettings
            Mounts = ([ordered]@{ window = (Join-Path $PSScriptRoot "window"); list = (Join-Path $PSScriptRoot "page"); fleet = (Join-Path $root "fleet\line") })
            DataFolder = (Get-HordeDecisionWindowDataFolder -HordeHome $hordeHome)
            OnOpened = { param($Window, $State) Invoke-HordeDecisionWindowOpened -Window $Window -State $State }
            OnTick = { param($Window, $State) Invoke-HordeDecisionWindowTick -Window $Window -State $State }
            OnClosed = { param($Window, $State) Invoke-HordeDecisionWindowClosed -Window $Window -State $State }
        }
        if ($Hidden) { $specArgs["Hidden"] = $true }
        # A check's real keys (header, -Probe): the surface is asked for an input of its own only then.
        if ($probePath -ne "") { $specArgs["ProbeInput"] = $true }
        if ($OffScreen) { $specArgs["Left"] = $script:HordeDecisionWindowOffScreen.left; $specArgs["Top"] = $script:HordeDecisionWindowOffScreen.top }
        if ($attachment.attached) {
            # Never smaller than a surface may be: the port says what that is, and this file keeps no copy.
            $limits = Get-HordeSurfaceLimits
            $specArgs["Companion"] = $true; $specArgs["Left"] = $at.value.left; $specArgs["Top"] = $at.value.top
            $specArgs["Width"] = [Math]::Max([int]$at.value.width, [int]$limits.smallestWidthPx); $specArgs["Height"] = [Math]::Max([int]$at.value.height, [int]$limits.smallestHeightPx)
            Write-Output ("Opening the decisions window beside the " + $own.values.role + "'s terminal window. This command returns when the window is closed.")
        }
        else { Write-Output ("Opening the decisions window, standing free (not attached: " + $attachment.reason + "). This command returns when the window is closed.") }
        $spec = New-HordeSurfaceSpec @specArgs
        $result = Open-HordeSurface -Surface $surface -Spec $spec
        if ($result.state -cne "closed") { throw ("the decisions window could not be shown: " + $result.reason) }
        if ($state.reportPath -ne "") { try { Write-HordeDecisionWindowReport -State $state } catch { } }
        Write-Output "The decisions window was closed."
    }
    finally {
        $script:HordeDecisionWindow = $null
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose(); $show.Dispose()
    }
}
