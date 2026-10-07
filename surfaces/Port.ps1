# surfaces/Port.ps1 - the surface port: how Horde shows a page it owns, and how that page talks to it.
#
# WHAT A SURFACE IS (decisions design 2026-10-06, sections 3.5 and 3.6, decision 2). A surface shows a
# page made of plain files, and carries the page's requests to Horde and Horde's events to the page.
# It knows nothing of what the page is about: the first page is the list of questions waiting for a
# person, and the same surface can show any other. Each one is a folder, surfaces/<name>/, holding
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
# WHAT GOES BACK is one line of ASCII JSON: { v; reply; ok; value } or { v; reply; ok; reason }, and for
# an event Horde pushes, { v; event; value }. Every character outside printable ASCII is a \u escape,
# which the page's JSON reader turns back into the same character, so text in any alphabet crosses
# whatever sits between unchanged (decisions/Console.ps1 does the same for -Json).
#
# THE SURFACE CONTRACT. surfaces/<name>/Surface.ps1 is dot-sourced and calls Register-HordeSurface
# with one script block:
#   Open  param($Spec) -> { state; reason }   state is closed (it was shown and has been closed) or
#                                             failed (it could not be shown; reason says why, in words)
# -Spec is plain data and script blocks, made by New-HordeSurfaceSpec:
#   title      the window's first title
#   mounts     an ordered table, name -> folder: each folder is served to the page under the name
#   start      "<mount>/<file>": the page to show, a file at the top of one of the mounts
#   bridge     a bridge from New-HordeSurfaceBridge
#   dataFolder where the surface may keep its own files (a web engine's profile)
#   theme      system, light or dark: which of its two looks the page is drawn in; system is the
#              machine's own setting
#   hidden     shown where nobody sees it and out of the taskbar: a start that must not interrupt, a test
#   companion  it belongs beside another window: out of the taskbar, and shown without taking the
#              keyboard from whatever has it
#   left, top, width, height   where it first stands, in pixels; with no left and top, mid-screen
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
# A callback is given the window as { handle; sync; errors; post; setTitle; show; close }: handle is
# the native window handle (capability window.native), sync an object events can be marshalled through
# to the window's own thread, errors the list the surface adds to when a callback or a message fails
# (a failure inside a window has no console to be printed on, so a caller that reports must be able
# to read it), and the rest are script blocks. With the capability picture there is one more, capture:
# & $Window.capture <absolute path.png> asks the surface to save a picture of the page as it is drawn
# now, and answers whether it was asked; the file appears, whole, a moment later. ONLY HORDE CAN ASK:
# capture is not a request, and no message from the page reaches it. A CALLBACK TAKES WHAT IT NEEDS FROM $State,
# never from the variables of the function that wrote it: Windows PowerShell 5.1 does not keep them
# (the first surface's own Surface.ps1 says what was measured, and its suite measures it on every run).
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")

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
# The most one message from the page may be, in characters. The largest thing a page sends today is a
# few numbers; a later answer in a person's own words is capped by the decisions rules, far below this.
# Checked before the text is parsed, so an oversized message costs nothing to refuse.
$script:HordeSurfaceRequestChars = 65536
# How many refusals a bridge remembers. A page that misbehaves in a loop must not grow the process.
$script:HordeSurfaceRefusalsKept = 50
$script:HordeSurfaceNamePattern = '\A[a-z][a-z-]{0,31}\z'
$script:HordeSurfaceArgTypes = @("string", "integer", "boolean")
# The longest text one argument may hold unless its request says less.
$script:HordeSurfaceArgChars = 16384

# The mount every surface serves itself (header, WHERE A PAGE FINDS A FILE).
$script:HordeSurfaceOwnMount = "surface"
# A mount's name is one step of an address a page writes.
$script:HordeSurfaceMountPattern = '\A[a-z][a-z0-9-]{0,31}\z'

function Get-HordeSurfaceRoot { return $PSScriptRoot }

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
    try { $parsed = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { throw ("the definition of the bridge's messages at " + $Path + " is not JSON: " + $_.Exception.Message) }
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
    if (@($Mounts.Keys) -cnotcontains $mount) { return (& $no "the page asked for a file of a mount that was not given") }
    foreach ($s in $steps) { if ($s -imatch $script:HordeSurfaceDeviceNamePattern) { return (& $no "the page asked for a name Windows keeps for a device") } }
    $extension = [System.IO.Path]::GetExtension($steps[$steps.Count - 1])
    if (@($script:HordeSurfaceFileTypes.Keys) -cnotcontains $extension) { return (& $no "the page asked for something that is not a kind of file a page is made of") }
    $missing = "the page asked for a file that is not there"
    $held = $null
    foreach ($k in @($Mounts.Keys)) { if ($k -ceq $mount) { $held = $Mounts[$k] } }
    $file = ""
    if ($held -is [System.Collections.IDictionary]) {
        if ($steps.Count -ne 1 -or @($held.Keys) -cnotcontains $steps[0]) { return (& $no $missing) }
        foreach ($k in @($held.Keys)) { if ($k -ceq $steps[0]) { $file = "" + $held[$k] } }
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
    $caps = [System.IO.File]::ReadAllText($capPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
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

function Get-HordeSurfaceNames { return @($script:HordeSurfaces.Keys | Sort-Object) }

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

function ConvertTo-HordeSurfaceJson {
    # A value as one line of ASCII JSON (header, WHAT GOES BACK).
    param($Value)
    $json = ConvertTo-Json -InputObject $Value -Compress -Depth 16
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
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Requests, [string[]]$Events = @())
    $table = [ordered]@{}
    foreach ($name in @($Requests.Keys)) {
        if ("$name" -cnotmatch $script:HordeSurfaceNamePattern) { throw ("'" + $name + "' is not a request name: lowercase letters and hyphens") }
        $entry = $Requests[$name]
        if ($null -eq $entry -or $entry["run"] -isnot [scriptblock]) { throw ("the request '" + $name + "' has no run block") }
        $argTable = [ordered]@{}
        if ($null -ne $entry["args"]) {
            foreach ($argName in @($entry["args"].Keys)) {
                if ("$argName" -cnotmatch '\A[a-z][A-Za-z0-9]{0,31}\z') { throw ("'" + $argName + "' of request '" + $name + "' is not an argument name") }
                $spec = $entry["args"][$argName]
                if ($script:HordeSurfaceArgTypes -cnotcontains "$($spec["type"])") { throw ("argument '" + $argName + "' of request '" + $name + "' has the type '" + $spec["type"] + "', not one of " + ($script:HordeSurfaceArgTypes -join ", ")) }
                $most = [long]$script:HordeSurfaceArgChars
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
        # Counted for ever, kept only for the last few: what a page was refused, and when.
        refused = 0
        refusals = (New-Object System.Collections.ArrayList)
        answered = 0
    }
}

function Add-HordeSurfaceRefusal {
    # Record one refusal on the bridge: the count goes up, and the reason joins the short record. The
    # reason is Horde's own words about what was wrong; it never holds what the page sent.
    param([Parameter(Mandatory = $true)]$Bridge, [Parameter(Mandatory = $true)][string]$Reason, [datetime]$Now = [datetime]::UtcNow)
    $Bridge.refused = [int]$Bridge.refused + 1
    [void]$Bridge.refusals.Add([pscustomobject]@{ at = $Now.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture); reason = $Reason })
    while ($Bridge.refusals.Count -gt $script:HordeSurfaceRefusalsKept) { $Bridge.refusals.RemoveAt(0) }
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
    foreach ($argName in @($Request.args.Keys)) {
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
    # Answer one message from the page. -Text is exactly what arrived. Returns { reply; refused; request }:
    # reply is the line to hand back to the page, or "" when the message carried no id to answer;
    # refused is why it was refused, or ""; request is the request's name when it was one of the list.
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
        return [pscustomobject]@{ reply = $line; refused = $Why; request = "" }
    }
    if ([string]::IsNullOrEmpty($Text)) { return (& $refuse "the message was empty" $null) }
    if ($Text.Length -gt $script:HordeSurfaceRequestChars) { return (& $refuse ("the message was " + $Text.Length + " characters, more than the " + $script:HordeSurfaceRequestChars + " one may be; it was not read") $null) }
    $message = $null
    try { $message = $Text | ConvertFrom-Json } catch { $message = $null }
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
        return (& $refuse ("the message asked for something that is not on the list; the list is: " + (@($Bridge.requests.Keys) -join ", ")) $id)
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
    catch {
        # The handler is Horde's own code, so its message is Horde's words and may be shown; the page
        # is told the request failed, which is not a refusal and is not recorded as one.
        $failLine = ConvertTo-HordeSurfaceJson -Value ([ordered]@{ $say.version = $protocol; $say.id = $id; $say.ok = $false; $say.reason = ("'" + $request.name + "' failed: " + $_.Exception.Message) })
        return [pscustomobject]@{ reply = $failLine; refused = ""; request = $request.name }
    }
    $Bridge.answered = [int]$Bridge.answered + 1
    $line = ConvertTo-HordeSurfaceJson -Value ([ordered]@{ $say.version = $protocol; $say.id = $id; $say.ok = $true; $say.value = $value })
    return [pscustomobject]@{ reply = $line; refused = ""; request = $request.name }
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
        [switch]$Hidden, [switch]$Companion, $Left = $null, $Top = $null, [int]$Width = 520, [int]$Height = 760, [string]$Theme = "system",
        $State = $null, [scriptblock]$OnOpened = $null, [scriptblock]$OnTick = $null, [int]$TickMs = 250, [scriptblock]$OnClosed = $null
    )
    $mountTable = [ordered]@{}
    foreach ($name in @($Mounts.Keys)) {
        # A mount's name is a step of the addresses a page writes, so it is held to a plain one.
        if ("$name" -cnotmatch $script:HordeSurfaceMountPattern) { throw ("'" + $name + "' is not a mount name: lowercase letters, digits and hyphens") }
        if ("$name" -ceq $script:HordeSurfaceOwnMount) { throw ("the mount '" + $name + "' is the surface's own, where it serves the page's side of the bridge; a caller gives its page another name") }
        $folder = "$($Mounts[$name])"
        if (-not [System.IO.Path]::IsPathRooted($folder) -or -not (Test-Path -LiteralPath $folder -PathType Container)) { throw ("the mount '" + $name + "' is not a folder that exists: '" + $folder + "'") }
        $mountTable["$name"] = [System.IO.Path]::GetFullPath($folder)
    }
    if ($mountTable.Count -eq 0) { throw "a surface needs at least one mount: the folder its page is in" }
    if ($Start -cnotmatch '\A([a-z][a-z0-9-]{0,31})/([A-Za-z0-9][A-Za-z0-9._-]{0,63})\z' -or -not $mountTable.Contains($Matches[1])) { throw ("the start page '" + $Start + "' is not <mount>/<file> of a mount that was given") }
    $startMount = $Matches[1]; $startFile = $Matches[2]
    if (-not (Test-Path -LiteralPath (Join-Path $mountTable[$startMount] $startFile) -PathType Leaf)) { throw ("the start page '" + $Start + "' is not a file that exists") }
    if (-not [System.IO.Path]::IsPathRooted($DataFolder)) { throw "the surface's data folder must be an absolute path" }
    if ($Width -lt 200 -or $Height -lt 150 -or $TickMs -lt 50) { throw "a surface is at least 200 by 150 pixels, and ticks no faster than every 50 ms" }
    if (($null -eq $Left) -ne ($null -eq $Top)) { throw "a surface is given both its left and its top, or neither" }
    if ($script:HordeSurfaceThemes -cnotcontains $Theme) { throw ("'" + $Theme + "' is not a theme; the themes are: " + ($script:HordeSurfaceThemes -join ", ")) }
    return [pscustomobject]@{
        PSTypeName = "Horde.SurfaceSpec"
        title = $Title; mounts = $mountTable; startMount = $startMount; startFile = $startFile; bridge = $Bridge; dataFolder = $DataFolder
        hidden = [bool]$Hidden; companion = [bool]$Companion; left = $Left; top = $Top; width = $Width; height = $Height; theme = $Theme
        state = $State; onOpened = $OnOpened; onTick = $OnTick; tickMs = $TickMs; onClosed = $OnClosed
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
