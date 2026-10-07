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
# table, each argument against what the request declared. Anything else is refused, counted and kept
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
#   start      "<mount>/<file>": the page to show
#   bridge     a bridge from New-HordeSurfaceBridge
#   dataFolder where the surface may keep its own files (a web engine's profile)
#   hidden     shown where nobody sees it and out of the taskbar: a start that must not interrupt, a test
#   companion  it belongs beside another window: out of the taskbar, and shown without taking the
#              keyboard from whatever has it
#   left, top, width, height   where it first stands, in pixels; with no left and top, mid-screen
#   state      anything: handed back, untouched, to every callback
#   onOpened   param($Window, $State) once the page's engine is up; onTick the same, every tickMs
#   onClosed   param($Window, $State) as the window goes
# WHERE A PAGE FINDS A MOUNT. The page is plain files, and a file names another by an address, so
# the address is part of this contract and not of any one surface: a mount named <name> is served at
# https://<name>.horde.invalid/ (Get-HordeSurfaceMountHost). ".invalid" is reserved by RFC 2606 never
# to resolve, so the address can only ever mean a folder a surface serves, never a machine. One
# mount is the surface's own: "surface", holding bridge.js, the page's side of the bridge; a caller may
# not give a mount that name.
#
# A callback is given the window as { handle; sync; post; setTitle; show; close }: handle is the
# native window handle (capability window.native), sync an object events can be marshalled through to
# the window's own thread, and the rest are script blocks. A CALLBACK TAKES WHAT IT NEEDS FROM $State,
# never from the variables of the function that wrote it: Windows PowerShell 5.1 does not keep them
# (the first surface's own Surface.ps1 says what was measured, and its suite measures it on every run).
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")

if ($null -eq (Get-Variable -Name HordeSurfaces -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeSurfaces = @{} }
$script:HordeSurfaceCapabilityNames = @("page.local", "page.locked", "requests.closed", "push", "window.native")
# The version of the message shapes above. A page built for another is refused, not half understood.
$script:HordeSurfaceProtocol = 1
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

# The mount every surface serves itself (header, WHERE A PAGE FINDS A MOUNT).
$script:HordeSurfaceOwnMount = "surface"
$script:HordeSurfaceMountSuffix = ".horde.invalid"

function Get-HordeSurfaceRoot { return $PSScriptRoot }

function Get-HordeSurfaceOwnMount { return $script:HordeSurfaceOwnMount }

function Get-HordeSurfaceMountHost {
    # The host name a mount is served to the page under (header, WHERE A PAGE FINDS A MOUNT).
    param([Parameter(Mandatory = $true)][string]$Mount)
    if ($Mount -cnotmatch '\A[a-z][a-z0-9-]{0,31}\z') { throw ("'" + $Mount + "' is not a mount name: lowercase letters, digits and hyphens") }
    return ($Mount + $script:HordeSurfaceMountSuffix)
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
    $refuse = {
        param([string]$Why, $Id)
        Add-HordeSurfaceRefusal -Bridge $Bridge -Reason $Why -Now $Now
        $line = ""
        if ($null -ne $Id) { $line = ConvertTo-HordeSurfaceJson -Value ([ordered]@{ v = $script:HordeSurfaceProtocol; reply = $Id; ok = $false; reason = ("refused: " + $Why) }) }
        return [pscustomobject]@{ reply = $line; refused = $Why; request = "" }
    }
    if ([string]::IsNullOrEmpty($Text)) { return (& $refuse "the message was empty" $null) }
    if ($Text.Length -gt $script:HordeSurfaceRequestChars) { return (& $refuse ("the message was " + $Text.Length + " characters, more than the " + $script:HordeSurfaceRequestChars + " one may be; it was not read") $null) }
    $message = $null
    try { $message = $Text | ConvertFrom-Json } catch { $message = $null }
    if ($null -eq $message -or $message -isnot [System.Management.Automation.PSCustomObject]) { return (& $refuse "the message was not one JSON object" $null) }
    # THE ID FIRST, so that every later refusal can be answered: a whole number the page chose.
    $idProp = $message.PSObject.Properties["id"]
    $id = $null
    if ($null -ne $idProp -and ($idProp.Value -is [int] -or $idProp.Value -is [long]) -and [long]$idProp.Value -ge 1 -and [long]$idProp.Value -le [int]::MaxValue) { $id = [int]$idProp.Value }
    if ($null -eq $id) { return (& $refuse "the message carried no id: a whole number from 1 up" $null) }
    foreach ($p in $message.PSObject.Properties) {
        if (@("v", "id", "request", "args") -cnotcontains $p.Name) { return (& $refuse "the message has a member that is not v, id, request or args" $id) }
    }
    $vProp = $message.PSObject.Properties["v"]
    if ($null -eq $vProp -or ($vProp.Value -isnot [int] -and $vProp.Value -isnot [long]) -or [long]$vProp.Value -ne $script:HordeSurfaceProtocol) { return (& $refuse ("the message is not version " + $script:HordeSurfaceProtocol + " of the page's requests") $id) }
    $nameProp = $message.PSObject.Properties["request"]
    if ($null -eq $nameProp -or $nameProp.Value -isnot [string] -or $nameProp.Value -cnotmatch $script:HordeSurfaceNamePattern -or -not $Bridge.requests.Contains($nameProp.Value)) {
        return (& $refuse ("the message asked for something that is not on the list; the list is: " + (@($Bridge.requests.Keys) -join ", ")) $id)
    }
    $request = $Bridge.requests[$nameProp.Value]
    $given = $null
    $argsProp = $message.PSObject.Properties["args"]
    if ($null -ne $argsProp) { $given = $argsProp.Value }
    $checked = @{}
    $wrong = Test-HordeSurfaceArguments -Request $request -Given $given -Checked $checked
    if ($wrong -ne "") { return (& $refuse ("'" + $request.name + "' was asked wrongly: " + $wrong) $id) }
    $value = $null
    try { $value = & $request.run $checked $State $Window }
    catch {
        # The handler is Horde's own code, so its message is Horde's words and may be shown; the page
        # is told the request failed, which is not a refusal and is not recorded as one.
        $failLine = ConvertTo-HordeSurfaceJson -Value ([ordered]@{ v = $script:HordeSurfaceProtocol; reply = $id; ok = $false; reason = ("'" + $request.name + "' failed: " + $_.Exception.Message) })
        return [pscustomobject]@{ reply = $failLine; refused = ""; request = $request.name }
    }
    $Bridge.answered = [int]$Bridge.answered + 1
    $line = ConvertTo-HordeSurfaceJson -Value ([ordered]@{ v = $script:HordeSurfaceProtocol; reply = $id; ok = $true; value = $value })
    return [pscustomobject]@{ reply = $line; refused = ""; request = $request.name }
}

function ConvertTo-HordeSurfaceEvent {
    # The line that pushes one event to the page. Throws for a name the bridge does not list: pushing
    # an event nobody declared is a programming error, not something the page did.
    param([Parameter(Mandatory = $true)]$Bridge, [Parameter(Mandatory = $true)][string]$Name, $Value = $null)
    if (@($Bridge.events) -cnotcontains $Name) { throw ("'" + $Name + "' is not an event this bridge pushes; its events are: " + (@($Bridge.events) -join ", ")) }
    return (ConvertTo-HordeSurfaceJson -Value ([ordered]@{ v = $script:HordeSurfaceProtocol; event = $Name; value = $Value }))
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
        [switch]$Hidden, [switch]$Companion, $Left = $null, $Top = $null, [int]$Width = 520, [int]$Height = 760,
        $State = $null, [scriptblock]$OnOpened = $null, [scriptblock]$OnTick = $null, [int]$TickMs = 250, [scriptblock]$OnClosed = $null
    )
    $mountTable = [ordered]@{}
    foreach ($name in @($Mounts.Keys)) {
        # A mount's name becomes part of an address the page uses, so it is held to a host label.
        if ("$name" -cnotmatch '\A[a-z][a-z0-9-]{0,31}\z') { throw ("'" + $name + "' is not a mount name: lowercase letters, digits and hyphens") }
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
    return [pscustomobject]@{
        PSTypeName = "Horde.SurfaceSpec"
        title = $Title; mounts = $mountTable; startMount = $startMount; startFile = $startFile; bridge = $Bridge; dataFolder = $DataFolder
        hidden = [bool]$Hidden; companion = [bool]$Companion; left = $Left; top = $Top; width = $Width; height = $Height
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
