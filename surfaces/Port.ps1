# surfaces/Port.ps1 - the surface port: how Horde shows a page it owns, and how that page talks to it.
#
# WHAT A SURFACE IS (decisions design 2026-10-06, sections 3.5 and 3.6, decision 2). A surface shows a
# page made of plain files, and carries the page's requests to Horde and Horde's events to the page.
# It knows nothing of what the page is about, or of who opens it: any caller shows any page through
# the same contract. Each one is a folder, surfaces/<name>/, holding
# Surface.ps1 (its code) and capabilities.json (what it can do, as data, checked against
# schema/surface-capabilities.v1). This file names no surface: a second one - another platform's
# window, a file to send to a phone, a view across a link - is a new folder, not an edit here.
#
# THE BRIDGE IS THE ONLY WAY ACROSS, AND IT IS A CLOSED LIST. A page is text that may quote anything a
# session wrote, so nothing it sends is trusted. The caller that opens a surface makes a bridge: a
# table of named requests, each with the handful of arguments it takes and the function that answers
# it. A message from the page is one JSON object, { v; id; request; args }, and it is checked HERE,
# before any handler sees it: its size, that it is JSON and an object, its members, the name against the
# table, each argument against what the request declared. THE SHAPES THEMSELVES - that one, the two
# under WHAT GOES BACK, and the protocol number - ARE DEFINED ONCE, in surfaces/bridge-messages.json
# (schema/surface-bridge-messages.v1). This file reads every member name from it, and so does the
# page's side of the bridge, to which a surface serves that same file; the names written in this
# header are that file's, quoted for the reader. Anything else is refused, counted and kept
# in the bridge's short record of refusals, and answered - when it carried a usable id - with the fact
# of the refusal and never with an echo of what was sent. No object of Horde's is ever handed to the
# page to call; a surface that offers one is not a surface (capability requests.closed).
#
# Invoke-HordeSurfaceRequest IS A PURE FUNCTION of the bridge and the text: it opens no window and
# needs none, so every case of it is tested without one (test/test-surface-port.ps1).
#
# A REQUEST THAT FAILS - its handler threw, or its answer could not be written whole - IS SAID TO THE
# PAGE IN ONE FIXED SENTENCE, "the request '<name>' failed", and nothing more. What a handler says as
# it fails is whatever the code under it threw: the path of a file, a line of somebody's data. The
# page is text that may quote anything a session wrote, so those words are not its to read (review of
# 2026-10-06, finding A11: they were handed over as they were). THEY STAY ON HORDE'S SIDE, IN TWO PLACES:
#   - THE BRIDGE'S OWN RECORD, always: failed counts every one, and failures keeps the last errorsKept
#     as { at; reason }, as refusals are kept. This function is handed no list of a window's and needs
#     no window, so with none - a test, a surface that shows no window - this record is where the
#     words are.
#   - THE ERRORS A SURFACE KEEPS FOR ITS CALLER ($Window.errors, below): the answer of
#     Invoke-HordeSurfaceRequest carries the same words as failed, and a surface adds them to that
#     list with Add-HordeSurfaceError, so a caller that reports reads them there with every other failure.
# A failure is not a refusal - the page asked properly - and is counted as neither refused nor answered.
#
# WHAT GOES BACK is one line of ASCII JSON: { v; reply; ok; value } or { v; reply; ok; reason }, and for
# an event Horde pushes, { v; event; value }. Every character outside printable ASCII is a \u escape,
# which the page's JSON reader turns back into the same character, so text in any alphabet crosses
# whatever sits between unchanged.
#
# THE SURFACE CONTRACT. surfaces/<name>/Surface.ps1 is dot-sourced and calls Register-HordeSurface
# with one script block:
#   Open  param($Spec) -> { state; reason }   state is closed (it was shown and has been closed) or
#                                             failed (it could not be shown; reason says why, in words)
# -Spec is plain data and script blocks, made by New-HordeSurfaceSpec:
#   title      what the page is called where a surface has a place to say it (a window's first title)
#   mounts     an ordered table, name -> folder: each folder is served to the page under the name
#   start      "<mount>/<file>": the page to show, a file at the top of one of the mounts
#   bridge     a bridge from New-HordeSurfaceBridge
#   dataFolder where the surface may keep its own files (a web engine's profile)
#   theme      system, light or dark: which of its two looks the page is drawn in; system is the
#              machine's own setting
#   hidden     shown where nobody sees it and out of the taskbar: a start that must not interrupt, a test
#   companion  it belongs beside another window: out of the taskbar
#   takeKeyboard   it takes the keyboard as it first appears. WITHOUT THIS NO SURFACE DOES: a window
#              that appears while a person is typing somewhere else must not swallow their keys, so
#              appearing quietly is the rule and the person clicks into it. A hidden surface never
#              takes it, whatever is asked
#   left, top, width, height   where it first stands, in pixels; with no left and top, mid-screen;
#              with no width or height, the module's settings (520 by 760 unless a person's file
#              says otherwise); never smaller than Get-HordeSurfaceLimits says. These, hidden,
#              companion and takeKeyboard are words about a WINDOW: a surface that is not one - a
#              file, a view across a link - has nothing to place and ignores them
#   tickMs     how often onTick runs; with none, the module's setting (250 ms)
#   probeInput     FOR A CHECK, NEVER FOR A CALLER'S OWN WORK: the window also gives input and
#              inputIdle (below). Off unless asked
#   errorsKept how many of its own errors the surface keeps (the module's setting, 50)
#   messagesPerSecond   the most messages the surface reads from the page in one second (the module's
#              setting, 100): a page that sends more has the rest of that second dropped unread and
#              unanswered - a request() the page made in it never settles - and the flood recorded
#              once as a refusal (Test-HordeSurfaceMessageMeter)
#   state      anything: handed back, untouched, to every callback
#   onOpened   param($Window, $State) once the page's engine is up; onTick the same, every tickMs
#   onClosed   param($Window, $State) as the window goes
# WHERE A PAGE FINDS A FILE: BY A RELATIVE ADDRESS, ALWAYS. The page is plain files, and a file names
# another by an address, so what a page may write is part of this contract and not of any one
# surface. The mounts stand side by side as the folders of one tree, <mount>/<file> or
# <mount>/<folder>/.../<file>, and a file of a page writes
#     <file>                 a file beside it                       list.js   img/dot.png
#     ../<mount>/<file>      a file of another mount                ../fleet/panel.js
#     ../surface/bridge.js   the page's side of the bridge, which every surface serves by that name
# (from a file at the top of its mount; one more ../ for each folder the writing file is deep), AND
# NOTHING ELSE: no scheme, no host name, no leading slash. WHERE the tree stands - an origin inside a
# web engine, a folder a snapshot was copied into, a path across a link - is each surface's private
# detail, and a page that wrote it could be shown by that one surface only.
#   - WHAT AN ADDRESS NAMES is decided by Resolve-HordeSurfacePageFile, for every surface alike: a
#     file of a mount that was given, at most eight steps under it, each step a plain name in the
#     file's own letter case, of a kind on the port's list (Get-HordeSurfaceFileTypes: .html .css .js
#     .json .txt .svg .png .jpg .gif .webp .ico .woff2).
#   - A SURFACE SERVES THAT AND REFUSES EVERYTHING ELSE - an address outside the tree, a climb out of
#     it, a file of another kind - and records each refusal on the bridge as it records a refused
#     request. A page loads nothing from anywhere else, whatever policy line it carries or lacks.
#   - A page may USE the files of every mount (run a script of another, read its data). It may only
#     BE at a file of the mount its start page is in: going anywhere else is refused.
#   - One mount is the surface's own, "surface", a closed list of two files: bridge.js, and
#     bridge-messages.json, the definition of the messages that bridge.js reads. A caller may not give
#     a mount that name.
#
# WHAT A CALLBACK IS HANDED, as $Window. EVERY surface gives these five:
#   errors     the list the surface adds to when a callback, a message, a load or a request's
#              handler fails (A REQUEST THAT FAILS, above). A failure
#              inside a surface has no console to be printed on, so a caller that reports must be able
#              to read it. It holds the last errorsKept of them, oldest first.
#   post       & $Window.post <one line from ConvertTo-HordeSurfaceEvent>: push an event to the page
#   setTitle   & $Window.setTitle <text>
#   show       & $Window.show: bring it in front of the person, where that means something
#   close      & $Window.close
# TWO MORE EXIST ONLY ON A SURFACE WITH THE CAPABILITY window.native, and mean nothing anywhere else:
#   handle     the native window handle, for something that must own or place the window
#   sync       an object through which an event raised on another thread is brought to the window's
#              own thread
# A caller that needs them says so when it picks a surface (Resolve-HordeSurface -Requires
# window.native) and must not read them otherwise: a surface that is a file or a view across a link
# has no handle to give. AND ONE MORE ONLY WITH THE CAPABILITY picture:
#   capture    & $Window.capture <absolute path.png> asks the surface to save a picture of the page as
#              it is drawn now, and answers whether it was asked; the file appears, whole, a moment
#              later. ONLY HORDE CAN ASK: capture is not a request, and no message from the page
#              reaches it.
# AND TWO MORE ONLY ON A SURFACE WHOSE SPEC WAS MADE WITH probeInput - FOR A CHECK, never for a
# caller's own work. A check of a page must see what a REAL key press does - a Tab moving the caret,
# an Enter adding a line - and an event a script makes is not trusted and does none of it; a real key
# press made through the desktop would take the keyboard from whoever is typing. So a surface that
# can hands keys to its own engine, for its own page alone (the window surface's Surface.ps1 says how,
# and what was measured). A surface that cannot leaves both out, as one does without probeInput:
#   input      & $Window.input <steps> hands key presses and typed text to the surface's own input,
#              for the page alone - never to the desktop, and whatever has the keyboard keeps it.
#              A step is { key; shift; ctrl }, { text }, or { focus }: the page told it has the
#              keyboard (true) or has not, with no window activated. Answers whether they were
#              handed over; none is when one step cannot be acted out.
#   inputIdle  & $Window.inputIdle: has the surface taken everything it was handed?
# A CALLBACK TAKES WHAT IT NEEDS FROM $State, never from the variables of the function that wrote it:
# Windows PowerShell 5.1 does not keep them (the window surface's own Surface.ps1 says what was
# measured, and its suite measures it on every run).
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ModuleSettings.ps1")
# ConvertFrom-HordeJson (T-0366): under 7 bare ConvertFrom-Json unwrapped a top-level list into its first item, so a
# list of messages was read as one message, and date-shaped text became a [datetime].
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")

if ($null -eq (Get-Variable -Name HordeSurfaces -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeSurfaces = @{} }
$script:HordeSurfaceCapabilityNames = @("page.local", "page.locked", "requests.closed", "push", "window.native", "picture")
# What a caller may ask a page to be drawn in: the machine's own setting, or one of the two.
$script:HordeSurfaceThemes = @("system", "light", "dark")
# THE MESSAGE SHAPES ARE WRITTEN ONCE, in the file beside this one, and read below when this file is
# loaded: the protocol number and every member name. Nothing in this file, and nothing in a page's
# side of the bridge, carries a copy (test/test-surface-port.ps1 hands the port another definition and
# sees every message follow it).
$script:HordeSurfaceMessagesFile = "bridge-messages.json"
$script:HordeSurfaceMessagesSchema = "surface-bridge-messages.v1"
$script:HordeSurfaceNamePattern = '\A[a-z][a-z-]{0,31}\z'
$script:HordeSurfaceArgTypes = @("string", "integer", "boolean")
# NAMES ARE THE CALLER'S, SO NO NAME MAY STAND FOR A MEMBER OF THE TABLE THAT HOLDS IT. Windows
# PowerShell reads $table.Keys, .Values, .Count and every other member name of a table as the ENTRY of
# that name when there is one, in any letter case: a bridge with a request named keys was refused with
# "'System.Collections.Hashtable' is not a request name" (measured 2026-10-08). So in this file a
# table of names - requests, arguments, mounts, surfaces, and a value about to be written - is walked
# with get_Keys() and get_Values() and asked with Contains() and its indexer, never through a member
# read as a property (test/test-surface-port.ps1 names requests, arguments and mounts after them).
# AND A FEW NAMES CAN NEVER ARRIVE: Windows PowerShell 5.1's ConvertFrom-Json refuses an object with a
# member named any of these, in any letter case (measured 2026-10-08), so an argument, or a member of
# a request in the definition, by one of them is refused when it is declared rather than refused on
# every message.
$script:HordeSurfaceJsonReservedNames = @("psobject", "psbase", "psadapted", "psextended", "pstypenames")

# WHAT NO SURFACE IS ASKED TO GO BELOW. Named constants and not settings: they are what a spec may ask
# of ANY surface, so a person's file must not be able to move them, and they are the settings' own
# smallest values below, written here once (Get-HordeSurfaceLimits hands them to a caller that needs
# them, so no caller keeps a copy). A window narrower or shorter than this cannot show a line of
# text and its own frame; a tick faster than this is a busy loop on the window's own thread.
$script:HordeSurfaceSmallestWidthPx = 200
$script:HordeSurfaceSmallestHeightPx = 150
$script:HordeSurfaceFastestTickMs = 50
# How deep a value Horde hands a page may nest: tables, objects and lists inside one another. A named
# constant and not a setting: it bounds Horde's own data shapes, which only a change to Horde's code
# can deepen. IT IS ENFORCED, NOT TRUSTED (Test-HordeSurfaceDepth): past its depth Windows PowerShell
# 5.1 writes the rest of a value as the name of its type and says nothing (measured 2026-10-07: a
# message whose value nests 16 deep is written whole, tables, objects and lists alike; at 18 the text
# "System.Collections.Hashtable" stands where the data was).
$script:HordeSurfaceJsonDepth = 16

# THE SETTINGS OF THE MODULE "surface" (core/ModuleSettings.ps1): one table, read from
# <HORDE_HOME>\settings\surface.json. With no such file the defaults below are used.
# A FILE THAT FAILS A CHECK IS REFUSED, AND SO IS THE SURFACE. The rule is the settings module's: an
# override file that fails its checks refuses with a reason and never silently falls back to the
# defaults - an unknown key, a wrong kind, a value out of range, text that is not JSON, each refuses
# the whole file. So a bridge and a spec are NOT MADE from a refused file (Resolve-HordeSurfaceSettings):
# New-HordeSurfaceBridge and New-HordeSurfaceSpec throw the file's own findings, one to a line, each
# naming the file and the key. With no spec there is nothing for Open-HordeSurface to open, so no
# surface is ever shown on defaults a person's file tried and failed to change; a command that
# composes a surface lets the throw go, and horde exits 1 with those sentences. This holds for a
# caller that names its own size and pace too: the file is the person's, and a fault in it is theirs
# to hear of before anything is shown.
# WHO READS THEM, AND WHEN: a bridge and a spec are each made with the settings of that moment and
# keep them (New-HordeSurfaceBridge, New-HordeSurfaceSpec), so a file edited while a window is open
# moves nothing under a page. A caller that wants one reading for both, or to say a refusal in its
# own way before it makes either, reads once with Get-HordeSurfaceSettings, looks at state, and
# hands the answer to both.
$script:HordeSurfaceSettings = New-HordeModuleSettings -Module "surface" -Settings @(
    @{ name = "widthPx"; kind = "whole"; default = 520; min = $script:HordeSurfaceSmallestWidthPx; max = 8000; what = "Width a surface first has when its caller names none, in pixels." }
    @{ name = "heightPx"; kind = "whole"; default = 760; min = $script:HordeSurfaceSmallestHeightPx; max = 8000; what = "Height a surface first has when its caller names none, in pixels." }
    @{ name = "tickMs"; kind = "whole"; default = 250; min = $script:HordeSurfaceFastestTickMs; max = 60000; what = "How often a caller's tick runs when the caller names no pace, in milliseconds." }
    @{ name = "messageChars"; kind = "whole"; default = 65536; min = 1024; max = 1048576; what = "The most characters one message from a page may be; a longer one is refused before it is read." }
    @{ name = "argumentChars"; kind = "whole"; default = 16384; min = 64; max = 1048576; what = "The longest text one argument of a request may hold, unless the request itself says less." }
    @{ name = "refusalsKept"; kind = "whole"; default = 50; min = 1; max = 1000; what = "How many refusals a bridge remembers; every one is counted, the oldest are dropped." }
    @{ name = "errorsKept"; kind = "whole"; default = 50; min = 1; max = 1000; what = "How many of its own errors a surface keeps for its caller to read, and how many failed requests a bridge remembers; the oldest are dropped." }
    @{ name = "messagesPerSecond"; kind = "whole"; default = 100; min = 1; max = 10000; what = "The most messages a surface reads from a page within one second; the rest of that second are dropped unread." }
)

# The mount every surface serves itself (header, WHERE A PAGE FINDS A FILE).
$script:HordeSurfaceOwnMount = "surface"
# A mount's name is one step of an address a page writes.
$script:HordeSurfaceMountPattern = '\A[a-z][a-z0-9-]{0,31}\z'

function Get-HordeSurfaceRoot { return $PSScriptRoot }

function Get-HordeSurfaceSettingsDeclaration { return $script:HordeSurfaceSettings }

function Get-HordeSurfaceSettings {
    # The module's settings as they are now: { state; values; findings; path } (core/ModuleSettings.ps1).
    # state is defaults (no file), read (the file passed every check) or refused (it failed one:
    # values is nothing and findings names every problem). It never throws for a bad file: what a
    # refusal means for a surface is said by Resolve-HordeSurfaceSettings.
    # Reads the one file and writes nothing. -HordeHome is for a caller that already knows the home.
    param([string]$HordeHome = "")
    return (Get-HordeModuleSettings -Declaration $script:HordeSurfaceSettings -HordeHome $HordeHome)
}

function Resolve-HordeSurfaceSettings {
    # The settings a bridge or a spec is made with: -Settings as its caller handed it, or the file
    # as it is now. THROWS when they are refused (header, A FILE THAT FAILS A CHECK IS REFUSED): the
    # findings, one to a line, as the settings module wrote them. Only an answer whose state is
    # defaults or read comes back; anything else handed in is a programming error and throws too, so
    # nothing without values is ever read for one.
    param($Settings = $null)
    if ($null -eq $Settings) { $Settings = Get-HordeSurfaceSettings }
    $state = ""
    if ($Settings -is [System.Management.Automation.PSCustomObject] -and $null -ne $Settings.PSObject.Properties["state"]) { $state = "$($Settings.state)" }
    if ($state -ceq "refused") { throw (@($Settings.findings) -join [Environment]::NewLine) }
    if (@("defaults", "read") -cnotcontains $state) { throw "what was handed as the surface's settings is not an answer of Get-HordeSurfaceSettings" }
    return $Settings
}

function Get-HordeSurfaceLimits {
    # What no spec may go below, for a caller that sizes a surface itself (header, WHAT NO SURFACE IS
    # ASKED TO GO BELOW): { smallestWidthPx; smallestHeightPx; fastestTickMs }.
    return [pscustomobject]@{ smallestWidthPx = $script:HordeSurfaceSmallestWidthPx; smallestHeightPx = $script:HordeSurfaceSmallestHeightPx; fastestTickMs = $script:HordeSurfaceFastestTickMs }
}

function Get-HordeSurfaceMessagesPath {
    # The file that defines the bridge's messages. A surface serves this very file to the page.
    return (Join-Path (Get-HordeSurfaceRoot) $script:HordeSurfaceMessagesFile)
}

function Test-HordeSurfaceMessages {
    # Findings for a parsed message definition: the schema's, plus the two rules a schema cannot say.
    param($Messages)
    $findings = @(Test-HordeSchema -Value $Messages -Schema (Get-HordeSchema -Name $script:HordeSurfaceMessagesSchema))
    if ($findings.Count -gt 0) { return $findings }
    foreach ($shape in @("request", "reply", "event")) {
        # Compared exactly, as the wire compares them: a plain @{} would take "Id" and "id" for one name.
        $seen = New-Object System.Collections.ArrayList
        foreach ($part in $Messages.$shape.PSObject.Properties) {
            if ($seen -ccontains $part.Value) { $findings += ("the " + $shape + " gives two parts the name '" + $part.Value + "'") }
            [void]$seen.Add($part.Value)
        }
    }
    # A request is read with ConvertFrom-Json, which refuses some member names outright (above).
    foreach ($part in $Messages.request.PSObject.Properties) {
        if ($script:HordeSurfaceJsonReservedNames -contains "$($part.Value)") { $findings += ("the request names a part '" + $part.Value + "', a name the JSON reader keeps for itself") }
    }
    # The page tells Horde's two kinds of message apart by the one member each has and the other has not.
    $replyNames = @($Messages.reply.PSObject.Properties | ForEach-Object { $_.Value })
    $eventNames = @($Messages.event.PSObject.Properties | ForEach-Object { $_.Value })
    if ($eventNames -ccontains $Messages.reply.id -or $replyNames -ccontains $Messages.event.name) { $findings += "a reply and an event could not be told apart: the reply's id and the event's name must each be a member the other shape has not" }
    return @($findings)
}

function Read-HordeSurfaceMessages {
    # The definition at -Path, checked. THROWS, naming every finding, when it is missing or wrong: it
    # is Horde's own file, and without it not one message can be read or written.
    param([string]$Path = (Get-HordeSurfaceMessagesPath))
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ("the definition of the bridge's messages is not there: " + $Path) }
    $parsed = $null
    try { $parsed = ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)) } catch { throw ("the definition of the bridge's messages at " + $Path + " is not JSON: " + $_.Exception.Message) }
    $findings = @(Test-HordeSurfaceMessages -Messages $parsed)
    if ($findings.Count -gt 0) { throw ("the definition of the bridge's messages at " + $Path + " is refused: " + ($findings -join "; ")) }
    return $parsed
}

$script:HordeSurfaceMessages = Read-HordeSurfaceMessages

function Get-HordeSurfaceMessages { return $script:HordeSurfaceMessages }

function Get-HordeSurfaceOwnMount { return $script:HordeSurfaceOwnMount }

# WHAT A PAGE IS MADE OF: the kinds of file a surface serves from a mount, each with the type it is
# served as. A closed list, the port's and not any one surface's, so that a page shown by one
# surface is shown the same by the next. Compared exactly: index.HTML is not on it.
$script:HordeSurfaceFileTypes = [ordered]@{
    ".html" = "text/html; charset=utf-8"; ".css" = "text/css; charset=utf-8"; ".js" = "text/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"; ".txt" = "text/plain; charset=utf-8"; ".svg" = "image/svg+xml"
    ".png" = "image/png"; ".jpg" = "image/jpeg"; ".gif" = "image/gif"; ".webp" = "image/webp"; ".ico" = "image/x-icon"; ".woff2" = "font/woff2"
}
# One step of an address: a plain name that begins and ends with a letter or a digit. No dot in
# front (hidden files), none at the end (Windows reads "a.js." as "a.js"), no colon (a second stream
# of a file), no percent sign (an escape is never decoded: an address that needs one is refused), no
# slash of either kind.
$script:HordeSurfacePathStep = '[A-Za-z0-9](?:[A-Za-z0-9._-]{0,62}[A-Za-z0-9])?'
# How many steps may follow the mount's name: folders inside a mount, and the file. A page of plain
# files is a few folders deep; the bound keeps one address from walking a tree.
$script:HordeSurfacePathSteps = 8
# Names Windows keeps for devices, with any extension: opening shell\nul.js opens the device.
$script:HordeSurfaceDeviceNamePattern = '\A(con|prn|aux|nul|com[0-9]|lpt[0-9])(\.|\z)'
# The two files of the surface's own mount (header, WHERE A PAGE FINDS A FILE).
$script:HordeSurfaceBridgeScript = "bridge.js"

function Get-HordeSurfaceFileTypes {
    # extension -> the type a file of that kind is served as (a copy).
    $copy = [ordered]@{}
    foreach ($k in @($script:HordeSurfaceFileTypes.Keys)) { $copy[$k] = $script:HordeSurfaceFileTypes[$k] }
    return $copy
}

function Get-HordeSurfaceOwnFiles {
    # The surface's own mount, as file name -> full path: -BridgeScript, that surface's own page side
    # of the bridge, under the name every page asks for it by; and the port's one definition of the
    # messages, which that script reads. A closed list of two: nothing else is served from it.
    param([Parameter(Mandatory = $true)][string]$BridgeScript)
    return ([ordered]@{ $script:HordeSurfaceBridgeScript = $BridgeScript; $script:HordeSurfaceMessagesFile = (Get-HordeSurfaceMessagesPath) })
}

function Resolve-HordeSurfacePageFile {
    # Which file -Path names among -Mounts, for a surface that is asked for one: { file; type; reason }.
    # file is its full path and type what to serve it as; or both are "" and reason says, in Horde's
    # own words and never with the address, why nothing is served. PURE but for looking at the disk.
    #
    # -Mounts is name -> folder, or name -> a table of file name -> full path (a mount that is a closed
    # list of files, as the surface's own is). -Path is the address's path exactly as it arrived,
    # "/<mount>/<step>/.../<file>", NOT decoded and NOT tidied by anything first: the rule is applied
    # to what was asked, so there is no second reading of it for an escape or a dot-dot to hide in.
    # A NAME IS MATCHED EXACTLY, letter case included, although Windows would not mind: a page that
    # only worked because this file system forgives would break on the next surface.
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Mounts, [AllowNull()][AllowEmptyString()][string]$Path)
    $no = { param([string]$Why) return [pscustomobject]@{ file = ""; type = ""; reason = $Why } }
    $step = $script:HordeSurfacePathStep
    if ("$Path" -cnotmatch ('\A/(' + $step + ')((?:/' + $step + '){1,' + $script:HordeSurfacePathSteps + '})\z')) { return (& $no "the page asked for an address that is not a file of a mount") }
    $mount = $Matches[1]
    $steps = @($Matches[2].Substring(1) -split "/")
    # Exactly: the table a caller made with [ordered] would take SHELL for shell.
    if (@($Mounts.get_Keys()) -cnotcontains $mount) { return (& $no "the page asked for a file of a mount that was not given") }
    foreach ($s in $steps) { if ($s -imatch $script:HordeSurfaceDeviceNamePattern) { return (& $no "the page asked for a name Windows keeps for a device") } }
    $extension = [System.IO.Path]::GetExtension($steps[$steps.Count - 1])
    if (@($script:HordeSurfaceFileTypes.Keys) -cnotcontains $extension) { return (& $no "the page asked for something that is not a kind of file a page is made of") }
    $missing = "the page asked for a file that is not there"
    $held = $null
    foreach ($k in @($Mounts.get_Keys())) { if ($k -ceq $mount) { $held = $Mounts[$k] } }
    $file = ""
    if ($held -is [System.Collections.IDictionary]) {
        if ($steps.Count -ne 1 -or @($held.get_Keys()) -cnotcontains $steps[0]) { return (& $no $missing) }
        foreach ($k in @($held.get_Keys())) { if ($k -ceq $steps[0]) { $file = "" + $held[$k] } }
        if ($file -eq "" -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { return (& $no $missing) }
    }
    else {
        $at = "" + $held
        for ($i = 0; $i -lt $steps.Count; $i++) {
            $last = ($i -eq $steps.Count - 1)
            # The entry's own name, as the disk spells it: a step has no wildcard in it, so this finds
            # one entry or none, and its letter case is then compared exactly.
            $found = @()
            try { if ($last) { $found = @([System.IO.Directory]::GetFiles($at, $steps[$i])) } else { $found = @([System.IO.Directory]::GetDirectories($at, $steps[$i])) } } catch { $found = @() }
            $exact = @($found | Where-Object { [System.IO.Path]::GetFileName($_) -ceq $steps[$i] })
            if ($exact.Count -ne 1) { return (& $no $missing) }
            $at = $exact[0]
        }
        $file = $at
    }
    return [pscustomobject]@{ file = $file; type = $script:HordeSurfaceFileTypes[$extension]; reason = "" }
}

function Get-HordeSurfaceFiles {
    # Every surface's Surface.ps1, for the caller to dot-source:
    #   foreach ($f in @(Get-HordeSurfaceFiles)) { . $f }
    param([string]$Root = (Get-HordeSurfaceRoot))
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Surface.ps1" } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Get-HordeSurfaceCapabilityNames { return @($script:HordeSurfaceCapabilityNames) }

function Test-HordeSurfaceCapabilities {
    # Findings for a parsed capabilities.json read from -Folder: the schema's, plus the rule the schema
    # cannot say - the surface it names is its own folder.
    param($Capabilities, [string]$Folder)
    $schema = Get-HordeSchema -Name "surface-capabilities.v1"
    $findings = @(Test-HordeSchema -Value $Capabilities -Schema $schema)
    if ($findings.Count -gt 0) { return $findings }
    $leaf = Split-Path -Leaf $Folder
    if ("$($Capabilities.surface)" -cne $leaf) { return @("capabilities.json names the surface '" + $Capabilities.surface + "' but sits in the folder '" + $leaf + "'") }
    return @()
}

function Register-HordeSurface {
    # Called by a surface's own Surface.ps1. Throws, naming every finding, when its capabilities.json is
    # missing or invalid: a surface that cannot say what it does is not one.
    param([Parameter(Mandatory = $true)][string]$Folder, [Parameter(Mandatory = $true)][scriptblock]$Open)
    $capPath = Join-Path $Folder "capabilities.json"
    if (-not (Test-Path -LiteralPath $capPath -PathType Leaf)) { throw ("surface folder '" + $Folder + "' has no capabilities.json") }
    $caps = ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($capPath, [System.Text.Encoding]::UTF8))
    $findings = @(Test-HordeSurfaceCapabilities -Capabilities $caps -Folder $Folder)
    if ($findings.Count -gt 0) { throw ("surface '" + (Split-Path -Leaf $Folder) + "' refused: " + ($findings -join "; ")) }
    # Once per name, as a messenger is: a second registration would silently swap the surface every
    # caller resolves by that name.
    if ($script:HordeSurfaces.ContainsKey("$($caps.surface)")) {
        throw ("surface '" + $caps.surface + "' is already registered, from " + $script:HordeSurfaces["$($caps.surface)"].folder + "; the first registration stands")
    }
    $s = [pscustomobject]@{ PSTypeName = "Horde.Surface"; name = "$($caps.surface)"; folder = $Folder; capabilities = $caps; open = $Open }
    $script:HordeSurfaces[$s.name] = $s
    return $s
}

function Get-HordeSurfaceNames { return @($script:HordeSurfaces.get_Keys() | Sort-Object) }

function Test-HordeSurfaceCapability {
    # Does the surface have the capability? Only "yes" counts: unverified, declined and no are all no.
    param([Parameter(Mandatory = $true)]$Surface, [Parameter(Mandatory = $true)][string]$Capability)
    if ($script:HordeSurfaceCapabilityNames -cnotcontains $Capability) { throw ("'" + $Capability + "' is not a surface capability") }
    return ("$($Surface.capabilities.capabilities.$Capability.support)" -ceq "yes")
}

function Resolve-HordeSurface {
    # The first registered surface, by name, that has every capability in -Requires; $null when none
    # has. The caller says what it needs, never which surface: that is what keeps a surface's name in
    # its own folder.
    param([string[]]$Requires = @())
    foreach ($name in @(Get-HordeSurfaceNames)) {
        $s = $script:HordeSurfaces[$name]
        $lacks = @($Requires | Where-Object { -not (Test-HordeSurfaceCapability -Surface $s -Capability $_) })
        if ($lacks.Count -eq 0) { return $s }
    }
    return $null
}

function Test-HordeSurfaceDepth {
    # Does -Value nest no more than -Most deep? A table, an object or a list is one level, and what it
    # holds is the next. It stops at the first branch that is too deep, so a value that holds itself
    # is answered no and never walked for ever. Text, numbers, true, false and nothing are no level.
    param($Value, [Parameter(Mandatory = $true)][int]$Most)
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [System.ValueType]) { return $true }
    $inside = $null
    if ($Value -is [System.Collections.IDictionary]) { $inside = @($Value.get_Values()) }
    elseif ($Value -is [System.Management.Automation.PSCustomObject]) { $inside = @($Value.PSObject.Properties | ForEach-Object { , $_.Value }) }
    elseif ($Value -is [System.Collections.IEnumerable]) { $inside = @($Value) }
    else { return $true }
    if ($Most -le 0) { return $false }
    foreach ($one in $inside) { if (-not (Test-HordeSurfaceDepth -Value $one -Most ($Most - 1))) { return $false } }
    return $true
}

function ConvertTo-HordeSurfaceJson {
    # A message as one line of ASCII JSON (header, WHAT GOES BACK). THROWS for a message whose value
    # nests deeper than can be written whole: the message itself is one level, its value up to
    # $script:HordeSurfaceJsonDepth more.
    param($Value)
    if (-not (Test-HordeSurfaceDepth -Value $Value -Most ($script:HordeSurfaceJsonDepth + 1))) { throw ("the value nests more than " + $script:HordeSurfaceJsonDepth + " levels deep, and a page is handed whole values only") }
    $json = ConvertTo-Json -InputObject $Value -Compress -Depth $script:HordeSurfaceJsonDepth
    return [regex]::Replace($json, '[^\x20-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") })
}

function New-HordeSurfaceBridge {
    # A bridge: the closed list of requests a page may make, and of events Horde may push to it.
    # -Requests is an ordered table, name -> @{ args = @{ <name> = @{ type; most } }; run = { param($Arguments, $State, $Window) } }:
    #   args   the arguments the request takes; every one must be given, and nothing else may be. type is
    #          string, integer or boolean; most caps a string's length or an integer's value.
    #   run    answers it, with plain data. It is given the checked arguments as a table, and the
    #          caller's state and window as the surface holds them.
    # -Events is the names Horde may push. A malformed table is a programming error and throws.
    # -Settings is the answer of Get-HordeSurfaceSettings; without it the file is read here. A
    # refused file THROWS its findings and no bridge is made (Resolve-HordeSurfaceSettings). Either
    # way the bridge keeps the four limits it was made with: the most a message may be, the longest
    # an argument may be unless it says less, how many refusals are remembered and how many failed
    # requests (errorsKept: what a handler said as it failed is an error of Horde's own).
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Requests, [string[]]$Events = @(), $Settings = $null)
    $Settings = Resolve-HordeSurfaceSettings -Settings $Settings # no bridge from a refused file
    $limits = [pscustomobject]@{ messageChars = [int]$Settings.values.messageChars; argumentChars = [int]$Settings.values.argumentChars; refusalsKept = [int]$Settings.values.refusalsKept; errorsKept = [int]$Settings.values.errorsKept }
    $table = [ordered]@{}
    foreach ($name in @($Requests.get_Keys())) {
        if ("$name" -cnotmatch $script:HordeSurfaceNamePattern) { throw ("'" + $name + "' is not a request name: lowercase letters and hyphens") }
        $entry = $Requests[$name]
        if ($null -eq $entry -or $entry["run"] -isnot [scriptblock]) { throw ("the request '" + $name + "' has no run block") }
        $argTable = [ordered]@{}
        if ($null -ne $entry["args"]) {
            foreach ($argName in @($entry["args"].get_Keys())) {
                if ("$argName" -cnotmatch '\A[a-z][A-Za-z0-9]{0,31}\z') { throw ("'" + $argName + "' of request '" + $name + "' is not an argument name") }
                if ($script:HordeSurfaceJsonReservedNames -contains "$argName") { throw ("'" + $argName + "' of request '" + $name + "' is a name the JSON reader keeps for itself, so no page could send it") }
                $spec = $entry["args"][$argName]
                if ($script:HordeSurfaceArgTypes -cnotcontains "$($spec["type"])") { throw ("argument '" + $argName + "' of request '" + $name + "' has the type '" + $spec["type"] + "', not one of " + ($script:HordeSurfaceArgTypes -join ", ")) }
                $most = [long]$limits.argumentChars
                if ("$($spec["type"])" -ceq "integer") { $most = [long][int]::MaxValue }
                if ($null -ne $spec["most"]) { $most = [long]$spec["most"] }
                $argTable["$argName"] = [pscustomobject]@{ type = "$($spec["type"])"; most = $most }
            }
        }
        $table["$name"] = [pscustomobject]@{ name = "$name"; args = $argTable; run = $entry["run"] }
    }
    foreach ($e in @($Events)) { if ("$e" -cnotmatch $script:HordeSurfaceNamePattern) { throw ("'" + $e + "' is not an event name: lowercase letters and hyphens") } }
    return [pscustomobject]@{
        PSTypeName = "Horde.SurfaceBridge"
        requests = $table
        events = @($Events)
        limits = $limits
        # Counted for ever, kept only for the last few: what a page was refused, and when.
        refused = 0
        refusals = (New-Object System.Collections.ArrayList)
        answered = 0
        # The same for requests whose handler failed (header, A REQUEST THAT FAILS): what it said, and when.
        failed = 0
        failures = (New-Object System.Collections.ArrayList)
    }
}

function Add-HordeSurfaceRefusal {
    # Record one refusal on the bridge: the count goes up, and the reason joins the short record. The
    # reason is Horde's own words about what was wrong; it never holds what the page sent.
    param([Parameter(Mandatory = $true)]$Bridge, [Parameter(Mandatory = $true)][string]$Reason, [datetime]$Now = [datetime]::UtcNow)
    $Bridge.refused = [int]$Bridge.refused + 1
    [void]$Bridge.refusals.Add([pscustomobject]@{ at = $Now.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture); reason = $Reason })
    while ($Bridge.refusals.Count -gt $Bridge.limits.refusalsKept) { $Bridge.refusals.RemoveAt(0) }
}

function Add-HordeSurfaceFailure {
    # Record one failed request on the bridge (header, A REQUEST THAT FAILS): the count goes up, and
    # what was said joins the short record. Unlike a refusal's reason, -Reason holds the handler's own
    # words, so nothing of this record is ever handed to a page.
    param([Parameter(Mandatory = $true)]$Bridge, [Parameter(Mandatory = $true)][string]$Reason, [datetime]$Now = [datetime]::UtcNow)
    $Bridge.failed = [int]$Bridge.failed + 1
    [void]$Bridge.failures.Add([pscustomobject]@{ at = $Now.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture); reason = $Reason })
    while ($Bridge.failures.Count -gt $Bridge.limits.errorsKept) { $Bridge.failures.RemoveAt(0) }
}

function Add-HordeSurfaceError {
    # Add one line to the list of errors a surface keeps for its caller, and drop the oldest past
    # -Kept (a spec's errorsKept). A surface adds every error this way: something that fails on every
    # tick must not grow the process for as long as the window is open. An empty line is no error.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$Errors, [AllowNull()][AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][int]$Kept)
    if ("$Text" -eq "") { return }
    [void]$Errors.Add($Text)
    while ($Errors.Count -gt $Kept) { $Errors.RemoveAt(0) }
}

# The length of the "second" messages are counted in. A named constant: the setting is how many
# messages it may hold, and a surface that stops listening to a flood does so for this long.
$script:HordeSurfaceMeterWindowMs = 1000

function Get-HordeSurfaceMeterWindowMs { return $script:HordeSurfaceMeterWindowMs }

function New-HordeSurfaceMessageMeter {
    # A count of the messages a surface has read in the second now running (Test-HordeSurfaceMessageMeter).
    return [pscustomobject]@{ startedMs = [long]-1; read = 0; told = $false; dropped = 0 }
}

function Test-HordeSurfaceMessageMeter {
    # What a surface does with one message that has just arrived, BEFORE it looks at it: "read" it;
    # "refuse" - the first past -PerSecond in this second, to be recorded once as a flood and not
    # read; or "drop" - every one after that, not read and not recorded. A second runs from the first
    # message read in it. -NowMs is the surface's own clock, in milliseconds from any start.
    # WHY BEFORE: reading is the cost. Ten thousand messages posted at once, each parsed, refused and
    # recorded, held a window's own thread for 11 to 14 seconds (measured 2026-10-07; the review of
    # 2026-10-06 measured 29.5 s, finding A8). An honest page sends a handful a second and never meets
    # this; a page that floods has what it sends in the rest of that second unanswered, its own
    # requests among them. A SURFACE SHOULD STOP LISTENING on "refuse", not go on being handed
    # messages to drop: for the window surface the hand-over itself was a third of the cost.
    param([Parameter(Mandatory = $true)]$Meter, [Parameter(Mandatory = $true)][long]$NowMs, [Parameter(Mandatory = $true)][int]$PerSecond)
    # A clock that went backwards starts a new second rather than dropping for ever.
    if ($Meter.startedMs -lt 0 -or ($NowMs - $Meter.startedMs) -ge $script:HordeSurfaceMeterWindowMs -or $NowMs -lt $Meter.startedMs) { $Meter.startedMs = $NowMs; $Meter.read = 0; $Meter.told = $false }
    if ($Meter.read -lt $PerSecond) { $Meter.read = $Meter.read + 1; return "read" }
    $Meter.dropped = $Meter.dropped + 1
    if (-not $Meter.told) { $Meter.told = $true; return "refuse" }
    return "drop"
}

function Test-HordeSurfaceArguments {
    # Why -Given is not what -Request takes, in words, or "" when it is. -Checked is filled with the
    # arguments as a plain table for the handler. A name is never repeated back unless it is one the
    # request itself declares.
    param($Request, $Given, [System.Collections.IDictionary]$Checked)
    if ($null -eq $Given) { $Given = [pscustomobject]@{} }
    if ($Given -isnot [System.Management.Automation.PSCustomObject]) { return "its args is not an object" }
    $names = @($Given.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($n in $names) { if (-not $Request.args.Contains($n)) { return ("it gives an argument '" + $Request.name + "' does not take") } }
    foreach ($argName in @($Request.args.get_Keys())) {
        if ($names -cnotcontains $argName) { return ("it does not give '" + $argName + "', which '" + $Request.name + "' needs") }
        $spec = $Request.args[$argName]
        $v = $Given.PSObject.Properties[$argName].Value
        if ($spec.type -ceq "string") {
            if ($v -isnot [string]) { return ("'" + $argName + "' is not text") }
            if ($v.Length -gt $spec.most) { return ("'" + $argName + "' is " + $v.Length + " characters, more than the " + $spec.most + " it may be") }
        }
        elseif ($spec.type -ceq "integer") {
            # A whole number as JSON wrote it: ConvertFrom-Json gives an int or a long for one, and a
            # decimal or double for 1.5 and for 1e30, which are refused here rather than cast.
            if ($v -isnot [int] -and $v -isnot [long]) { return ("'" + $argName + "' is not a whole number") }
            if ([long]$v -lt 0 -or [long]$v -gt $spec.most) { return ("'" + $argName + "' is not between 0 and " + $spec.most) }
        }
        elseif ($v -isnot [bool]) { return ("'" + $argName + "' is not true or false") }
        $Checked[$argName] = $v
    }
    return ""
}

function Invoke-HordeSurfaceRequest {
    # Answer one message from the page. -Text is exactly what arrived. Returns { reply; refused; request; failed }:
    # reply is the line to hand back to the page, or "" when the message carried no id to answer;
    # refused is why it was refused, or ""; request is the request's name when it was one of the list;
    # failed is what went wrong inside Horde when the request failed, or "" - the handler's own words,
    # for the surface's list of errors and never for the page (header, A REQUEST THAT FAILS).
    # It never throws for anything the page sent: a handler that throws is answered as a failure.
    param([Parameter(Mandatory = $true)]$Bridge, [AllowNull()][AllowEmptyString()][string]$Text, $State = $null, $Window = $null, [datetime]$Now = [datetime]::UtcNow)
    # Every name below is the definition's (header, THE BRIDGE): $ask is a request's, $say a reply's.
    $protocol = $script:HordeSurfaceMessages.protocol
    $ask = $script:HordeSurfaceMessages.request
    $say = $script:HordeSurfaceMessages.reply
    $refuse = {
        param([string]$Why, $Id)
        Add-HordeSurfaceRefusal -Bridge $Bridge -Reason $Why -Now $Now
        $line = ""
        if ($null -ne $Id) { $line = ConvertTo-HordeSurfaceJson -Value ([ordered]@{ $say.version = $protocol; $say.id = $Id; $say.ok = $false; $say.reason = ("refused: " + $Why) }) }
        return [pscustomobject]@{ reply = $line; refused = $Why; request = ""; failed = "" }
    }
    # A request that failed (header, A REQUEST THAT FAILS): the page is told the one sentence, and
    # -What - the handler's words - goes on the bridge's record and back to the surface.
    $fail = {
        param([string]$What)
        $told = "the request '" + $request.name + "' failed"
        $kept = $told + ": " + $What
        Add-HordeSurfaceFailure -Bridge $Bridge -Reason $kept -Now $Now
        $failLine = ConvertTo-HordeSurfaceJson -Value ([ordered]@{ $say.version = $protocol; $say.id = $id; $say.ok = $false; $say.reason = $told })
        return [pscustomobject]@{ reply = $failLine; refused = ""; request = $request.name; failed = $kept }
    }
    if ([string]::IsNullOrEmpty($Text)) { return (& $refuse "the message was empty" $null) }
    if ($Text.Length -gt $Bridge.limits.messageChars) { return (& $refuse ("the message was " + $Text.Length + " characters, more than the " + $Bridge.limits.messageChars + " one may be; it was not read") $null) }
    $message = $null
    try { $message = ConvertFrom-HordeJson -Text $Text } catch { $message = $null }
    if ($null -eq $message -or $message -isnot [System.Management.Automation.PSCustomObject]) { return (& $refuse "the message was not one JSON object" $null) }
    # THE ID FIRST, so that every later refusal can be answered: a whole number the page chose.
    $idProp = $message.PSObject.Properties[$ask.id]
    $id = $null
    if ($null -ne $idProp -and ($idProp.Value -is [int] -or $idProp.Value -is [long]) -and [long]$idProp.Value -ge 1 -and [long]$idProp.Value -le [int]::MaxValue) { $id = [int]$idProp.Value }
    if ($null -eq $id) { return (& $refuse ("the message carried no " + $ask.id + ": a whole number from 1 up") $null) }
    $members = @($ask.version, $ask.id, $ask.name, $ask.arguments)
    foreach ($p in $message.PSObject.Properties) {
        if ($members -cnotcontains $p.Name) { return (& $refuse ("the message has a member that is not " + ($members[0..2] -join ", ") + " or " + $members[3]) $id) }
    }
    $vProp = $message.PSObject.Properties[$ask.version]
    if ($null -eq $vProp -or ($vProp.Value -isnot [int] -and $vProp.Value -isnot [long]) -or [long]$vProp.Value -ne $protocol) { return (& $refuse ("the message is not version " + $protocol + " of the page's requests") $id) }
    $nameProp = $message.PSObject.Properties[$ask.name]
    if ($null -eq $nameProp -or $nameProp.Value -isnot [string] -or $nameProp.Value -cnotmatch $script:HordeSurfaceNamePattern -or -not $Bridge.requests.Contains($nameProp.Value)) {
        return (& $refuse ("the message asked for something that is not on the list; the list is: " + (@($Bridge.requests.get_Keys()) -join ", ")) $id)
    }
    $request = $Bridge.requests[$nameProp.Value]
    $given = $null
    $argsProp = $message.PSObject.Properties[$ask.arguments]
    if ($null -ne $argsProp) { $given = $argsProp.Value }
    $checked = @{}
    $wrong = Test-HordeSurfaceArguments -Request $request -Given $given -Checked $checked
    if ($wrong -ne "") { return (& $refuse ("'" + $request.name + "' was asked wrongly: " + $wrong) $id) }
    $value = $null
    try { $value = & $request.run $checked $State $Window }
    catch { return (& $fail ("" + $_.Exception.Message)) }
    # An answer that cannot be written whole - it nests too deep - is the handler's failure, said to
    # the page as one: never half a value, and never the name of a type where the data should be.
    $line = ""
    try { $line = ConvertTo-HordeSurfaceJson -Value ([ordered]@{ $say.version = $protocol; $say.id = $id; $say.ok = $true; $say.value = $value }) }
    catch { return (& $fail ("its answer could not be handed over: " + $_.Exception.Message)) }
    $Bridge.answered = [int]$Bridge.answered + 1
    return [pscustomobject]@{ reply = $line; refused = ""; request = $request.name; failed = "" }
}

function ConvertTo-HordeSurfaceEvent {
    # The line that pushes one event to the page. Throws for a name the bridge does not list: pushing
    # an event nobody declared is a programming error, not something the page did.
    param([Parameter(Mandatory = $true)]$Bridge, [Parameter(Mandatory = $true)][string]$Name, $Value = $null)
    if (@($Bridge.events) -cnotcontains $Name) { throw ("'" + $Name + "' is not an event this bridge pushes; its events are: " + (@($Bridge.events) -join ", ")) }
    $tell = $script:HordeSurfaceMessages.event
    return (ConvertTo-HordeSurfaceJson -Value ([ordered]@{ $tell.version = $script:HordeSurfaceMessages.protocol; $tell.name = $Name; $tell.value = $Value }))
}

function New-HordeSurfaceSpec {
    # What a caller asks a surface to show (header, THE SURFACE CONTRACT), checked: a spec a surface
    # could only half honour is refused here, in words, before any window exists.
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Mounts,
        [Parameter(Mandatory = $true)][string]$Start,
        [Parameter(Mandatory = $true)]$Bridge,
        [Parameter(Mandatory = $true)][string]$DataFolder,
        [switch]$Hidden, [switch]$Companion, [switch]$TakeKeyboard, [switch]$ProbeInput, $Left = $null, $Top = $null, $Width = $null, $Height = $null, [string]$Theme = "system",
        $State = $null, [scriptblock]$OnOpened = $null, [scriptblock]$OnTick = $null, $TickMs = $null, [scriptblock]$OnClosed = $null,
        $Settings = $null
    )
    # A size or a pace the caller names is the caller's; one it leaves out is the module's setting.
    # A refused settings file throws its findings here, whatever the caller named, and no spec is
    # made (Resolve-HordeSurfaceSettings).
    $Settings = Resolve-HordeSurfaceSettings -Settings $Settings # no spec from a refused file
    if ($null -eq $Width) { $Width = $Settings.values.widthPx }
    if ($null -eq $Height) { $Height = $Settings.values.heightPx }
    if ($null -eq $TickMs) { $TickMs = $Settings.values.tickMs }
    $Width = [int]$Width; $Height = [int]$Height; $TickMs = [int]$TickMs
    $mountTable = [ordered]@{}
    foreach ($name in @($Mounts.get_Keys())) {
        # A mount's name is a step of the addresses a page writes, so it is held to a plain one.
        if ("$name" -cnotmatch $script:HordeSurfaceMountPattern) { throw ("'" + $name + "' is not a mount name: lowercase letters, digits and hyphens") }
        if ("$name" -ceq $script:HordeSurfaceOwnMount) { throw ("the mount '" + $name + "' is the surface's own, where it serves the page's side of the bridge; a caller gives its page another name") }
        $folder = "$($Mounts[$name])"
        if (-not [System.IO.Path]::IsPathRooted($folder) -or -not (Test-Path -LiteralPath $folder -PathType Container)) { throw ("the mount '" + $name + "' is not a folder that exists: '" + $folder + "'") }
        $mountTable["$name"] = [System.IO.Path]::GetFullPath($folder)
    }
    if ($mountTable.get_Count() -eq 0) { throw "a surface needs at least one mount: the folder its page is in" }
    if ($Start -cnotmatch '\A([a-z][a-z0-9-]{0,31})/([A-Za-z0-9][A-Za-z0-9._-]{0,63})\z' -or -not $mountTable.Contains($Matches[1])) { throw ("the start page '" + $Start + "' is not <mount>/<file> of a mount that was given") }
    $startMount = $Matches[1]; $startFile = $Matches[2]
    if (-not (Test-Path -LiteralPath (Join-Path $mountTable[$startMount] $startFile) -PathType Leaf)) { throw ("the start page '" + $Start + "' is not a file that exists") }
    if (-not [System.IO.Path]::IsPathRooted($DataFolder)) { throw "the surface's data folder must be an absolute path" }
    if ($Width -lt $script:HordeSurfaceSmallestWidthPx -or $Height -lt $script:HordeSurfaceSmallestHeightPx -or $TickMs -lt $script:HordeSurfaceFastestTickMs) { throw ("a surface is at least " + $script:HordeSurfaceSmallestWidthPx + " by " + $script:HordeSurfaceSmallestHeightPx + " pixels, and ticks no faster than every " + $script:HordeSurfaceFastestTickMs + " ms") }
    if (($null -eq $Left) -ne ($null -eq $Top)) { throw "a surface is given both its left and its top, or neither" }
    if ($script:HordeSurfaceThemes -cnotcontains $Theme) { throw ("'" + $Theme + "' is not a theme; the themes are: " + ($script:HordeSurfaceThemes -join ", ")) }
    return [pscustomobject]@{
        PSTypeName = "Horde.SurfaceSpec"
        title = $Title; mounts = $mountTable; startMount = $startMount; startFile = $startFile; bridge = $Bridge; dataFolder = $DataFolder
        hidden = [bool]$Hidden; companion = [bool]$Companion; takeKeyboard = [bool]$TakeKeyboard; probeInput = [bool]$ProbeInput; left = $Left; top = $Top; width = $Width; height = $Height; theme = $Theme
        state = $State; onOpened = $OnOpened; onTick = $OnTick; tickMs = $TickMs; onClosed = $OnClosed
        errorsKept = [int]$Settings.values.errorsKept; messagesPerSecond = [int]$Settings.values.messagesPerSecond
    }
}

function Open-HordeSurface {
    # Show -Spec on -Surface and return when it has been closed: { state; reason } (header, THE SURFACE
    # CONTRACT). Only a surface registered here is opened, and whatever it throws or answers that is
    # not that shape comes back as failed with the reason.
    param([Parameter(Mandatory = $true)]$Surface, [Parameter(Mandatory = $true)]$Spec)
    $registered = $null
    if ($null -ne $Surface -and $script:HordeSurfaces.ContainsKey("$($Surface.name)")) { $registered = $script:HordeSurfaces["$($Surface.name)"] }
    if ($null -eq $registered -or -not [object]::ReferenceEquals($registered, $Surface)) { return [pscustomobject]@{ state = "failed"; reason = "that is not a surface registered with the surface port" } }
    $result = $null
    try { $result = & $Surface.open $Spec }
    catch { return [pscustomobject]@{ state = "failed"; reason = ("the surface could not be shown: " + $_.Exception.Message) } }
    $last = @($result) | Select-Object -Last 1
    if ($null -eq $last -or @("closed", "failed") -cnotcontains "$($last.state)") { return [pscustomobject]@{ state = "failed"; reason = "the surface did not say whether it was shown" } }
    return [pscustomobject]@{ state = "$($last.state)"; reason = "$($last.reason)" }
}
