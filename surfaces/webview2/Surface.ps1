# surfaces/webview2/Surface.ps1 - a surface that is a window of this machine, drawn by the web engine
# that ships inside Windows 11 (decisions design 2026-10-06, sections 3.5, 3.6 and 3.11).
#
# WHAT IT DOES, and nothing else: it puts a page from folders on disk into a window Horde owns, keeps
# the page from going anywhere else, and carries text between the page and surfaces/Port.ps1's bridge.
# What the page is about, where the window stands and whose window it stands beside are its caller's.
#
# NO WEB SERVER, NO PORT, AND EVERY LOAD IS ANSWERED HERE. The engine asks this adapter for every
# resource a page loads - the page itself, a script, a style sheet, an image, a font, a call - before
# it would go to any network (the engine's resource-request hook, with a filter for every address and
# every kind). The adapter answers each one itself:
#   - an address under its one made-up origin that names a file of a mount (surfaces/Port.ps1,
#     Resolve-HordeSurfacePageFile) is answered with that file's bytes;
#   - EVERYTHING ELSE IS ANSWERED WITH A REFUSAL (403) AND RECORDED on the bridge: default deny.
# Nothing listens, so no other page, program or machine can reach it, and nothing a page asks for is
# fetched from anywhere. WHERE the origin is, is this file's private detail: a page never writes it
# (surfaces/Port.ps1, WHERE A PAGE FINDS A FILE), so another surface serves the same pages unchanged.
#
# WHAT THE HOOK DOES NOT SEE, measured 2026-10-07 on engine 154.0.4258.62 with a listener on the
# loopback address standing for "outside":
#   - a WebSocket, from the page or from a worker: it reached the listener with the hook in place.
#   - the engine's early connection for a navigation this adapter then cancels: the listener received
#     "GET /nav-out" although the page stayed where it was.
#   - a service worker's own script (it failed only because the origin's name does not resolve).
# So the engine is ALSO started with no way to any network: every connection it would make is sent to
# a proxy at an address no program can listen at (port 0), loopback included. With that, the same
# probe reached the listener zero times. These are not recorded on the bridge: nothing tells the
# adapter they were tried. NOT MEASURED: WebRTC's own UDP, which no proxy setting governs.
# data: and blob: addresses are not asked of the hook either; they are bytes the page already has.
#
# THE PAGE CANNOT LEAVE, AND CANNOT REACH HORDE EXCEPT BY TEXT.
#   - a navigation to any address but a file of the start page's own mount is cancelled; every frame
#     navigation is cancelled; a request for a new window is marked handled and opens nothing. Each
#     is recorded on the bridge as a refusal.
#   - the page is handed NO object of Horde's: AddHostObjectToScript is never called (the suite reads
#     this file's syntax tree for it). The page posts text; a message whose source is not a file of
#     the start page's mount is refused; everything else goes to Invoke-HordeSurfaceRequest, which
#     checks it.
#   - developer tools, the context menu, the browser's own keys (reload, find, print), the status bar
#     and saved form data are off.
#   - whatever the page asks the person's machine for - its place, camera, microphone, clipboard,
#     notices on the screen - is denied at once, and recorded as a refusal.
#   - a download is cancelled, and recorded as a refusal. Left to the engine, a page that makes a link
#     with a download name and clicks it writes a file into the user's own Downloads folder, outside
#     anything of Horde's (measured 2026-10-06 by the review of this adapter, in a real hidden window:
#     the file was there).
#
# THE THREE PINNED FILES in lib/ are Microsoft's, under the licence beside them. They are checked
# against lib/fingerprints.txt BEFORE anything is loaded (core/Fingerprints.ps1), and a mismatch
# refuses to load: a changed file would run inside Horde with everything Horde can do. Each is held
# open from the moment it is checked until the engine is up, so the bytes that are loaded are the
# bytes that were checked, and a file nobody listed beside them refuses the folder.
#
# THE ENGINE ITSELF is not in this folder. It is the "WebView2 Runtime", part of Windows 11 and updated
# with Edge. Where it is not installed the surface says so in plain words and fails.
#
# START TIME, measured 2026-10-07 on a machine slowed on purpose, Windows PowerShell 5.1, engine
# 154.0.4258.62, a hidden window on a page of three files, five runs each way. With folders mapped to
# host names by the engine (how this adapter served pages before): the engine up 677 to 896 ms after
# the surface was asked to open, the page's first request answered at 756 to 971 ms. With every load
# answered here: the engine up 777 to 835 ms, the first request answered at 951 to 1039 ms. So the
# engine starts as fast, and answering a page's files here costs about 30 ms a file on that machine.
#
# A HANDLER TAKES WHAT IT NEEDS FROM $script:HordeWebView2, NEVER FROM A LOCAL. A script block given to
# a .NET event is run later with PowerShell's scoping of the moment it runs, not of the function that
# wrote it: it does not keep that function's variables (paid for in the window proof of 2026-10-06, and
# measured again on every run of this adapter's suite, whose control is a handler written the obvious
# way that finds its local empty). So every handler here is one line that calls a named function, the
# named function reads the one state object, and Get-HordeWebView2Handlers returns them from a
# function that has already returned by the time any of them runs.
# surfaces/webview2/test/test-webview2-surface.ps1 pins it both ways.
#
# ONE WINDOW AT A TIME IN ONE PROCESS: the state object is one. A second Open while one is open is
# refused.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Fingerprints.ps1")
# The one owner of "this process draws at each screen's real scale"; this adapter asks it and keeps
# no call to Windows of its own for that.
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "platform\windows\Scale.ps1")

$script:HordeWebView2Folder = $PSScriptRoot
$script:HordeWebView2LibFolder = Join-Path $PSScriptRoot "lib"
# Every one of these must be pinned by the list, or nothing is loaded: a list that pinned two of the
# three would let the third be anything.
$script:HordeWebView2LibFiles = @("Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.WinForms.dll", "WebView2Loader.dll")
# What else may stand in that folder, beside the three and their list: Microsoft's licence and notice.
# ANYTHING ELSE REFUSES THE FOLDER. A program library loaded from a folder can pull in another that
# was put beside it, and a check that only looked at the listed files would never see it (review of
# 2026-10-06, finding A7: an extra file gave "ok").
$script:HordeWebView2LibOtherFiles = @("LICENSE.txt", "NOTICE.txt")
# The pinned files, open, from the moment they are checked until the engine is up
# (Import-HordeWebView2Libraries -Hold; Clear-HordeWebView2HeldFiles).
$script:HordeWebView2Held = @()
$script:HordeWebView2 = $null
# Where a hidden window stands: far outside any screen, the coordinates Windows itself gives a
# minimised window, so nothing is drawn where a person can see it.
$script:HordeWebView2HiddenAt = -32000
# THE ONE ORIGIN EVERY MOUNT IS SERVED UNDER, as <origin>/<mount>/<file>. Private to this file: a
# page is written with relative addresses only. ".invalid" is reserved by RFC 2606 never to resolve,
# so the address can only ever mean a file this adapter answers with, never a machine.
$script:HordeWebView2Origin = "https://horde.invalid"
# What the engine asks for by itself, of every page: answered "not there", and not held against the
# page as a refusal (measured 2026-10-07: one such ask per page load).
$script:HordeWebView2EngineOwnPaths = @("/favicon.ico")
# The engine's way to any network, closed (header, WHAT THE HOOK DOES NOT SEE): every connection goes
# to a proxy at port 0, where nothing can listen, and the loopback address is not excused. Measured
# 2026-10-07: with these two arguments a page's WebSocket and a cancelled navigation's early
# connection reached a loopback listener zero times; without them, both arrived. A proxy named by a
# script in a data address was tried and did NOT stop them.
$script:HordeWebView2NoNetwork = "--proxy-server=http://0.0.0.0:0 --proxy-bypass-list=<-loopback>"

# The window: a form that can be shown without taking the keyboard, and how it is brought forward.
# Compiled once per process.
$script:HordeWebView2NativeSource = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class HordeSurfaceForm : Form {
    public bool Quiet;
    protected override bool ShowWithoutActivation { get { return Quiet; } }
}
public static class HordeSurfaceNative {
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    public static void BringForward(IntPtr h) {
        if (IsIconic(h)) { ShowWindow(h, 9); }   // SW_RESTORE
        SetForegroundWindow(h);
    }
}
'@

function Get-HordeWebView2PagePath {
    # The path of -Uri when it is an address under this adapter's one origin and nothing cleverer:
    # https, exactly that host, no user name in front of it, no port of its own. $null for everything
    # else - another host, a host that only begins with ours, a file, a data address, text that is no
    # address. THE PATH IS HANDED BACK AS IT WAS WRITTEN, cut at the first ? or #, and not as .NET
    # would tidy it: which file it names is decided once, by the port, on what was asked.
    param([AllowNull()][AllowEmptyString()][string]$Uri)
    $parsed = $null
    if (-not [System.Uri]::TryCreate("$Uri", [System.UriKind]::Absolute, [ref]$parsed)) { return $null }
    $origin = [System.Uri]$script:HordeWebView2Origin
    if (-not ($parsed.Scheme -ceq $origin.Scheme -and $parsed.Host -ceq $origin.Host -and $parsed.UserInfo -eq "" -and $parsed.IsDefaultPort)) { return $null }
    if ("$Uri" -cnotmatch '\A[A-Za-z][A-Za-z0-9+.-]*://[^/?#]*(?<path>/[^?#]*)?') { return $null }
    if (("" + $Matches["path"]) -eq "") { return "/" }
    return ("" + $Matches["path"])
}

function Test-HordeWebView2Address {
    # May the page BE at -Uri, or a message come from it? Only a file of the start page's own mount:
    # this adapter's origin (Get-HordeWebView2PagePath) and a path under /<start mount>/. A file of
    # another mount may be USED by the page; the page may not go there.
    param([AllowNull()][AllowEmptyString()][string]$Uri, [Parameter(Mandatory = $true)][string]$StartMount)
    $path = Get-HordeWebView2PagePath -Uri $Uri
    return [bool]($null -ne $path -and $path.StartsWith(("/" + $StartMount + "/"), [System.StringComparison]::Ordinal))
}

function Get-HordeWebView2ResourceAnswer {
    # What one load is answered with: { file; type; status; refusal }. file and type are set only for
    # a file of a mount (status 200). Otherwise the status is a refusal's, and refusal is the sentence
    # to record on the bridge - Horde's own words, with the engine's word for the kind of load and
    # never the address - or "" for the one thing the engine asks for by itself. PURE but for the
    # port's look at the disk. THE DEFAULT IS TO REFUSE: only an address that names a file is served.
    param([AllowNull()][AllowEmptyString()][string]$Uri, [AllowNull()][AllowEmptyString()][string]$Kind, [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Mounts)
    $path = Get-HordeWebView2PagePath -Uri $Uri
    if ($null -eq $path) {
        $word = "something"
        if ("$Kind" -cmatch '\A[A-Za-z]{1,32}\z') { $word = "$Kind" }
        return [pscustomobject]@{ file = ""; type = ""; status = 403; refusal = ("the page asked for something that is not one of its own files (the engine's word for the load: " + $word + "), and nothing was fetched") }
    }
    if ($script:HordeWebView2EngineOwnPaths -ccontains $path) { return [pscustomobject]@{ file = ""; type = ""; status = 404; refusal = "" } }
    $found = Resolve-HordeSurfacePageFile -Mounts $Mounts -Path $path
    if ($found.file -eq "") { return [pscustomobject]@{ file = ""; type = ""; status = 403; refusal = ($found.reason + ", and nothing was served") } }
    return [pscustomobject]@{ file = $found.file; type = $found.type; status = 200; refusal = "" }
}

function Get-HordeWebView2ScaleNote {
    # What to tell the caller about -Scale, the answer of Enable-HordeWindowsRealScale: "" when the
    # process draws at the screen's real scale, else one sentence. DECIDED ON realScale, never on
    # whether the call was taken: "already" can be a process that is not aware, and unknown is not yes
    # (platform/windows/Scale.ps1). The window still opens; its text is then drawn soft, which a
    # person sees and a report should be able to explain.
    param([Parameter(Mandatory = $true)]$Scale)
    if ("$($Scale.realScale)" -ceq "yes") { return "" }
    return ("the window is not known to be drawn at the screen's real scale (awareness " + $Scale.awareness + "), so its text may be soft: " + $Scale.reason)
}

function Get-HordeWebView2OpeningNotes {
    # What the caller is told as the window opens, before anything has failed: sentences that join the
    # list of errors it reads. What is said of the screen's scale, and each thing that was wrong in
    # the person's settings file when the spec read it (surfaces/Port.ps1, findings): a fault in that
    # file is used as its default, and is never silently ignored.
    param([Parameter(Mandatory = $true)]$Scale, [Parameter(Mandatory = $true)]$Spec)
    $notes = @()
    $scaleNote = Get-HordeWebView2ScaleNote -Scale $Scale
    if ($scaleNote -ne "") { $notes += $scaleNote }
    foreach ($finding in @($Spec.findings)) { if ("$finding" -ne "") { $notes += ("a setting was not used: " + $finding) } }
    return @($notes)
}

function Get-HordeWebView2WindowLook {
    # How the window of -Spec first appears: { quiet; taskbar; offScreen }. PURE, so the rule is
    # tested with no window.
    #   quiet      it appears WITHOUT taking the keyboard. That is every window whose caller did not
    #              ask for the keyboard (surfaces/Port.ps1, takeKeyboard), and a hidden one always. A
    #              free-standing window used to take it (review of 2026-10-06, finding D6).
    #   taskbar    it has a place in the taskbar: a window that stands free does; a companion and a
    #              hidden window do not.
    #   offScreen  it stands where no screen is: a hidden window.
    param([Parameter(Mandatory = $true)]$Spec)
    return [pscustomobject]@{
        quiet = [bool]($Spec.hidden -or -not $Spec.takeKeyboard)
        taskbar = [bool](-not ($Spec.companion -or $Spec.hidden))
        offScreen = [bool]$Spec.hidden
    }
}

function Test-HordeWebView2DataFolder {
    # "" when the engine will be able to keep its files in -Path; otherwise what to tell a person.
    # The folder is made if it is not there, and one small file is written in it and removed.
    # WHY THE SURFACE TRIES IT ITSELF: handed a folder it cannot write to, the engine waits and then
    # fails in its own words - 67 s and "Server execution failed (0x80080005)", measured by the review
    # of 2026-10-06, finding A10, with one engine process left running after the window had gone. A
    # trial that takes a moment and answers in plain words is asked first, and nothing is started.
    param([Parameter(Mandatory = $true)][string]$Path)
    $trial = Join-Path $Path ("horde-surface-trial-" + $PID + ".tmp")
    try {
        [void][System.IO.Directory]::CreateDirectory($Path)
        [System.IO.File]::WriteAllText($trial, "x")
        [System.IO.File]::Delete($trial)
        return ""
    } catch {
        return ("the folder the window keeps its own files in cannot be made or written to (" + $Path + "), so the window was not opened: " + $_.Exception.GetBaseException().Message)
    }
}

function Get-HordeWebView2RuntimeProblem {
    # "" when -Version is the version of an installed engine; otherwise what to tell a person.
    param([AllowNull()][AllowEmptyString()][string]$Version)
    if ("$Version".Trim() -ne "") { return "" }
    return "the web engine this window is drawn with is not installed on this machine. It is Microsoft's 'WebView2 Runtime', which comes with Windows 11 and with the Edge browser; install it from Microsoft and run this again. Every other horde command works without it"
}

function Test-HordeWebView2Libraries {
    # Are the pinned files in -Folder the ones its list says, all three of them, with nothing beside
    # them but what may stand there? { ok; reason; files; held }. With -Hold, a folder that passes is
    # handed back with its three files OPEN in held (core/Fingerprints.ps1): the caller loads them
    # while they are held and disposes of every one. A folder that does not pass holds nothing.
    param([string]$Folder = $script:HordeWebView2LibFolder, [switch]$Hold)
    $check = Test-HordeFingerprints -Folder $Folder -Hold:$Hold
    $why = @($check.findings)
    $have = @($check.files | ForEach-Object { Split-Path -Leaf $_ })
    foreach ($need in $script:HordeWebView2LibFiles) { if ($have -cnotcontains $need) { $why += ($need + " is not pinned by the list, or did not match it") } }
    foreach ($other in @($check.unlisted)) {
        if ($script:HordeWebView2LibOtherFiles -cnotcontains $other) { $why += ($other + " is in the folder and is neither pinned by the list nor one of the files that may stand beside the pinned ones (" + ($script:HordeWebView2LibOtherFiles -join ", ") + ")") }
    }
    if ($why.Count -gt 0) {
        foreach ($h in @($check.held)) { $h.Dispose() }
        return [pscustomobject]@{ ok = $false; reason = ("the window's program files in " + $Folder + " are not the ones this version of Horde pins, so none was loaded: " + (@($why | Select-Object -Unique) -join "; ")); files = @(); held = @() }
    }
    return [pscustomobject]@{ ok = $true; reason = ""; files = @($script:HordeWebView2LibFiles | ForEach-Object { Join-Path $Folder $_ }); held = @($check.held) }
}

function Clear-HordeWebView2HeldFiles {
    # Let go of every pinned file this adapter holds open. Safe to call when none is held.
    foreach ($h in @($script:HordeWebView2Held)) { try { $h.Dispose() } catch { } }
    $script:HordeWebView2Held = @()
}

function Import-HordeWebView2Libraries {
    # Check the pinned files, then load them. Returns "" when they are loaded, or why they were not.
    # THE CHECK COMES FIRST, every time: nothing of the folder is loaded unless all of it matches.
    # AND WHAT IS LOADED IS WHAT WAS CHECKED (review of 2026-10-06, finding A6): each file is opened
    # once, fingerprinted from that open file, and kept open - nobody can change it - while it is
    # loaded by path. -Hold keeps all three open after this returns, for a caller that goes on to
    # start the engine, because the third file is loaded only then; that caller lets go with
    # Clear-HordeWebView2HeldFiles once the engine is up. Without -Hold they are let go here.
    param([string]$Folder = $script:HordeWebView2LibFolder, [switch]$Hold)
    Clear-HordeWebView2HeldFiles
    $libs = Test-HordeWebView2Libraries -Folder $Folder -Hold
    if (-not $libs.ok) { return $libs.reason }
    $script:HordeWebView2Held = @($libs.held)
    $kept = $false
    try {
        if ($null -eq ("Microsoft.Web.WebView2.Core.CoreWebView2Environment" -as [type])) {
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
            Add-Type -Path $libs.files[0]
            Add-Type -Path $libs.files[1]
            # The third file is not .NET: the first two find it through this folder when the engine starts.
            [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::SetLoaderDllFolderPath($Folder)
        }
        if ($null -eq ("HordeSurfaceForm" -as [type])) { Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition $script:HordeWebView2NativeSource }
        $kept = [bool]$Hold
    } finally { if (-not $kept) { Clear-HordeWebView2HeldFiles } }
    return ""
}

function Get-HordeWebView2RuntimeVersion {
    # The installed engine's version, or "" when there is none. Call only after the files are loaded.
    try { return ("" + [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::GetAvailableBrowserVersionString()) } catch { return "" }
}

function Add-HordeWebView2Error {
    # One more line for the caller to read, the oldest dropped past what the spec keeps (surfaces/Port.ps1).
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    Add-HordeSurfaceError -Errors $s.errors -Text $Text -Kept $s.spec.errorsKept
}

function Stop-HordeWebView2 {
    # Close the window because it cannot go on; the first reason given is the one reported.
    param([Parameter(Mandatory = $true)][string]$Reason)
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    if ($s.failure -eq "") { $s.failure = $Reason }
    $s.form.Close()
}

function Send-HordeWebView2Json {
    # Hand the page one line of JSON. Before the engine is up, or after the window has gone, it is dropped.
    param([Parameter(Mandatory = $true)][string]$Json)
    $s = $script:HordeWebView2
    if ($null -eq $s -or -not $s.opened -or $null -eq $s.view.CoreWebView2) { return }
    $s.view.CoreWebView2.PostWebMessageAsJson($Json)
}

function Receive-HordeWebView2Message {
    # One message from the page: refused unless it came from the start page's own host, then answered
    # by the bridge. Returns the line to hand back, or "".
    param([AllowNull()][AllowEmptyString()][string]$Json, [AllowNull()][AllowEmptyString()][string]$Source)
    $s = $script:HordeWebView2
    if ($null -eq $s) { return "" }
    if (-not (Test-HordeWebView2Address -Uri $Source -StartMount $s.spec.startMount)) {
        Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason "a message came from an address that is not the page's own, and was not read"
        return ""
    }
    return (Invoke-HordeSurfaceRequest -Bridge $s.spec.bridge -Text $Json -State $s.spec.state -Window $s.window).reply
}

function Invoke-HordeWebView2Shown {
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    try { $null = $s.view.EnsureCoreWebView2Async($null) }
    catch { Stop-HordeWebView2 -Reason ("the web engine could not be started: " + $_.Exception.Message) }
}

function Invoke-HordeWebView2Initialized {
    param($What)
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    # The engine has started, or has failed to: either way its third file has been loaded or never
    # will be, and the pinned files need not be held any longer.
    Clear-HordeWebView2HeldFiles
    try {
        if (-not $What.IsSuccess) { Stop-HordeWebView2 -Reason ("the web engine did not start: " + $What.InitializationException.Message); return }
        $core = $s.view.CoreWebView2
        $core.Settings.AreDevToolsEnabled = $false
        $core.Settings.AreDefaultContextMenusEnabled = $false
        $core.Settings.AreBrowserAcceleratorKeysEnabled = $false
        $core.Settings.IsStatusBarEnabled = $false
        $core.Settings.IsPasswordAutosaveEnabled = $false
        $core.Settings.IsGeneralAutofillEnabled = $false
        $core.Settings.AreHostObjectsAllowed = $false
        # The page has a light and a dark look and follows the machine's setting unless the caller chose.
        if ($s.spec.theme -ceq "dark") { $core.Profile.PreferredColorScheme = [Microsoft.Web.WebView2.Core.CoreWebView2PreferredColorScheme]::Dark }
        elseif ($s.spec.theme -ceq "light") { $core.Profile.PreferredColorScheme = [Microsoft.Web.WebView2.Core.CoreWebView2PreferredColorScheme]::Light }
        $h = $s.handlers
        # EVERY address and EVERY kind of load is asked of this adapter first (header, EVERY LOAD IS
        # ANSWERED HERE), and the handler is in place before the first page is asked for.
        $core.AddWebResourceRequestedFilter("*", [Microsoft.Web.WebView2.Core.CoreWebView2WebResourceContext]::All)
        $core.add_WebResourceRequested($h.resource)
        $core.add_NavigationStarting($h.navigation)
        $core.add_FrameNavigationStarting($h.frame)
        $core.add_NewWindowRequested($h.newWindow)
        $core.add_DownloadStarting($h.download)
        $core.add_PermissionRequested($h.permission)
        # ONE delegate, made here and kept: the engine is asked to forget the handler it was handed,
        # so it is handed and asked with the same object. (Measured 2026-10-07 in the real window:
        # passing the script block itself both times was also honoured; keeping the object means that
        # does not rest on how Windows PowerShell turns a script block into a delegate.)
        $s.messageHandler = [System.EventHandler[Microsoft.Web.WebView2.Core.CoreWebView2WebMessageReceivedEventArgs]]$h.message
        $core.add_WebMessageReceived($s.messageHandler)
        $core.Navigate($script:HordeWebView2Origin + "/" + $s.spec.startMount + "/" + $s.spec.startFile)
        $s.opened = $true
        if ($null -ne $s.spec.onOpened) { & $s.spec.onOpened $s.window $s.spec.state }
        $s.timer.Start()
    } catch { Stop-HordeWebView2 -Reason ("the window could not be set up: " + $_.Exception.Message) }
}

function Invoke-HordeWebView2Navigation {
    param($What)
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    if (Test-HordeWebView2Address -Uri ("" + $What.Uri) -StartMount $s.spec.startMount) { return }
    $What.Cancel = $true
    Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason "the page tried to go to an address that is not its own, and was kept where it is"
}

function Invoke-HordeWebView2Resource {
    # One load the engine is about to make: answered here, with a file of a mount or with a refusal
    # (Get-HordeWebView2ResourceAnswer), and never left to the engine to fetch.
    param($What)
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    $environment = $s.view.CoreWebView2.Environment
    try {
        $answer = Get-HordeWebView2ResourceAnswer -Uri ("" + $What.Request.Uri) -Kind ("" + $What.ResourceContext) -Mounts $s.mounts
        if ($answer.file -ne "") {
            # Read whole and handed over as bytes: a page's files are small, and nothing of the file
            # stays open once the engine has them. Never kept by the engine: a file changed on disk
            # is the file the next load gets.
            $bytes = [System.IO.File]::ReadAllBytes($answer.file)
            $What.Response = $environment.CreateWebResourceResponse((New-Object System.IO.MemoryStream(, $bytes)), 200, "OK", ("Content-Type: " + $answer.type + "`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff"))
            return
        }
        $What.Response = $environment.CreateWebResourceResponse($null, [int]$answer.status, "Refused", "")
        if ($answer.refusal -ne "") { Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason $answer.refusal }
    } catch {
        # DEFAULT DENY HOLDS WHEN THIS CODE FAILS: the load is still answered with a refusal, and what
        # went wrong is kept for the caller.
        try { $What.Response = $environment.CreateWebResourceResponse($null, 403, "Refused", "") } catch { }
        Add-HordeWebView2Error -Text ("a file the page asked for could not be served: " + $_.Exception.Message)
    }
}

function Invoke-HordeWebView2Frame {
    param($Frame)
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    $Frame.Cancel = $true
    Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason "the page tried to load a frame, and no frame is loaded"
}

function Invoke-HordeWebView2NewWindow {
    param($What)
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    $What.Handled = $true
    Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason "the page asked for a new window, and none was opened"
}

function Invoke-HordeWebView2Download {
    # A page may save no file: where the engine keeps downloads is the user's own folder, outside
    # anything of Horde's (header).
    param($Download)
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    $Download.Cancel = $true
    Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason "the page tried to save a file, and none was saved"
}

function Invoke-HordeWebView2Permission {
    # A page asks the person's machine for something - where it is, its camera, its microphone, its
    # clipboard, to put notices on the screen. A PAGE HORDE SHOWS IS GIVEN NONE OF THEM: it is denied
    # here, at once, and recorded. Left to the engine, the ask waits on a prompt inside the window -
    # measured 2026-10-07 in a real hidden window: a page asking where the machine is was still
    # waiting when its own four-second limit ran out, and nothing was recorded.
    param($What)
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    $What.State = "Deny"
    $word = "something"
    if (("" + $What.PermissionKind) -cmatch '\A[A-Za-z]{1,40}\z') { $word = "" + $What.PermissionKind }
    Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason ("the page asked the machine for something (the engine's word for it: " + $word + "), and it was denied")
}

function Invoke-HordeWebView2Message {
    param($What)
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    # METERED BEFORE IT IS LOOKED AT (surfaces/Port.ps1, Test-HordeSurfaceMessageMeter). The first
    # message past what a second may hold is recorded as a flood, and THE ENGINE IS NO LONGER LISTENED
    # TO FOR A SECOND (Suspend-HordeWebView2Listening): merely being handed a message costs this
    # window's thread, so a flood must stop arriving, not only stop being read.
    $turn = Test-HordeSurfaceMessageMeter -Meter $s.meter -NowMs $s.clock.ElapsedMilliseconds -PerSecond $s.spec.messagesPerSecond
    if ($turn -cne "read") {
        if ($turn -ceq "refuse") {
            Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason ("the page sent more than " + $s.spec.messagesPerSecond + " messages within a second, and is not listened to for the next second: what it sends until then is dropped unread and unanswered")
            Suspend-HordeWebView2Listening
        }
        return
    }
    try {
        $reply = Receive-HordeWebView2Message -Json ("" + $What.WebMessageAsJson) -Source ("" + $What.Source)
        if ("$reply" -ne "") { Send-HordeWebView2Json -Json $reply }
    } catch { Add-HordeWebView2Error -Text ("a message from the page could not be answered: " + $_.Exception.Message) }
}

function Suspend-HordeWebView2Listening {
    # Take the message handler back from the engine, and start the one-second timer that returns it.
    # WHY NOT JUST IGNORE THE MESSAGES: measured 2026-10-07 in a real window, 10,000 messages posted at
    # once. Each read, refused and recorded: the window's thread held 11.5 to 14.1 s. Each handed to
    # this adapter and dropped at once, unread: still 3.5 s, because the hand-over itself - the engine
    # calling into PowerShell - is the cost, and a page can post faster than that for ever. With the
    # handler taken back the engine has nobody to call, and the figures are in this adapter's
    # real-window suite, which measures them on every run.
    $s = $script:HordeWebView2
    if ($null -eq $s -or $s.deaf) { return }
    try {
        $s.view.CoreWebView2.remove_WebMessageReceived($s.messageHandler)
        $s.deaf = $true
        $s.listenTimer.Start()
    } catch { Add-HordeWebView2Error -Text ("a flood of messages could not be shut out: " + $_.Exception.Message) }
}

function Resume-HordeWebView2Listening {
    # The second is over: the engine is handed the message handler again.
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    $s.listenTimer.Stop()
    if (-not $s.deaf) { return }
    try {
        $s.view.CoreWebView2.add_WebMessageReceived($s.messageHandler)
        $s.deaf = $false
    } catch { Add-HordeWebView2Error -Text ("the page could not be listened to again: " + $_.Exception.Message) }
}

function Start-HordeWebView2Capture {
    # Ask the engine for a picture of the page as it is drawn now, to be saved at -Path (absolute, a
    # PNG). Answers whether it was asked. The engine draws it in its own time; the tick finishes it
    # (Complete-HordeWebView2Capture), and the file is moved into place whole. One at a time: a second
    # ask while one is being drawn is not taken. ONLY HORDE'S SIDE CALLS THIS: it is no request of
    # the bridge, so nothing a page sends can make a picture or choose where one is written.
    param([AllowEmptyString()][string]$Path)
    $s = $script:HordeWebView2
    if ($null -eq $s -or -not $s.opened -or $null -eq $s.view -or $null -eq $s.view.CoreWebView2 -or $null -ne $s.capture) { return $false }
    if (-not [System.IO.Path]::IsPathRooted("$Path") -or [System.IO.Path]::GetExtension("$Path") -ine ".png") { Add-HordeWebView2Error -Text ("a picture is saved at an absolute path ending .png, and none was made"); return $false }
    $stream = $null
    try {
        $temp = $Path + "." + $PID + ".tmp"
        $stream = [System.IO.File]::Open($temp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $task = $s.view.CoreWebView2.CapturePreviewAsync([Microsoft.Web.WebView2.Core.CoreWebView2CapturePreviewImageFormat]::Png, $stream)
        $s.capture = [pscustomobject]@{ path = $Path; temp = $temp; stream = $stream; task = $task }
        return $true
    } catch {
        # The file this function opened is this function's to remove: an ask the engine does not take
        # must leave nothing beside where the picture would have been. Only when it WAS opened here:
        # a file that could not be opened is somebody else's.
        if ($null -ne $stream) {
            $stream.Dispose()
            try { [System.IO.File]::Delete($temp) } catch { }
        }
        Add-HordeWebView2Error -Text ("a picture could not be asked for: " + $_.Exception.Message)
        return $false
    }
}

function Complete-HordeWebView2Capture {
    # Finish a picture the engine has drawn: close it, and move it into place over any older one.
    $s = $script:HordeWebView2
    if ($null -eq $s -or $null -eq $s.capture -or -not $s.capture.task.IsCompleted) { return }
    $c = $s.capture
    $s.capture = $null
    try {
        $c.stream.Dispose()
        if ($c.task.IsFaulted -or $c.task.IsCanceled) { throw "the engine did not draw it" }
        if (Test-Path -LiteralPath $c.path -PathType Leaf) { [System.IO.File]::Replace($c.temp, $c.path, [NullString]::Value) } else { [System.IO.File]::Move($c.temp, $c.path) }
        $s.pictures = [int]$s.pictures + 1
    } catch {
        Add-HordeWebView2Error -Text ("a picture could not be saved: " + $_.Exception.Message)
        try { if (Test-Path -LiteralPath $c.temp) { [System.IO.File]::Delete($c.temp) } } catch { }
    }
}

function Invoke-HordeWebView2Tick {
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    Complete-HordeWebView2Capture
    if ($null -eq $s.spec.onTick) { return }
    # A tick that throws is recorded and the window stays: it will be asked again a moment later, and
    # a window that closed on one bad tick would lose what the person was reading.
    try { & $s.spec.onTick $s.window $s.spec.state } catch { Add-HordeWebView2Error -Text ("a tick failed: " + $_.Exception.Message) }
}

function Invoke-HordeWebView2Closed {
    $s = $script:HordeWebView2
    if ($null -eq $s -or $null -eq $s.spec.onClosed) { return }
    try { & $s.spec.onClosed $s.window $s.spec.state } catch { Add-HordeWebView2Error -Text ("closing failed: " + $_.Exception.Message) }
}

function Get-HordeWebView2Handlers {
    # The script blocks given to .NET events, each one line that calls a named function (header, A
    # HANDLER TAKES WHAT IT NEEDS FROM $script:HordeWebView2). This function has returned long before
    # any of them runs, which is exactly the case they must work in.
    return @{
        shown       = { Invoke-HordeWebView2Shown }
        initialized = { param($From, $What) Invoke-HordeWebView2Initialized -What $What }
        navigation  = { param($From, $What) Invoke-HordeWebView2Navigation -What $What }
        resource    = { param($From, $What) Invoke-HordeWebView2Resource -What $What }
        frame       = { param($From, $What) Invoke-HordeWebView2Frame -Frame $What }
        newWindow   = { param($From, $What) Invoke-HordeWebView2NewWindow -What $What }
        download    = { param($From, $What) Invoke-HordeWebView2Download -Download $What }
        permission  = { param($From, $What) Invoke-HordeWebView2Permission -What $What }
        message     = { param($From, $What) Invoke-HordeWebView2Message -What $What }
        listen      = { Resume-HordeWebView2Listening }
        tick        = { Invoke-HordeWebView2Tick }
        closed      = { Invoke-HordeWebView2Closed }
    }
}

function Get-HordeWebView2Window {
    # What a caller's callbacks are handed (surfaces/Port.ps1, THE SURFACE CONTRACT). Its script blocks
    # read the state object like every handler.
    param([Parameter(Mandatory = $true)]$Form, [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$Errors)
    return [pscustomobject]@{
        handle = [long]$Form.Handle
        sync = $Form
        errors = $Errors
        post = { param($Json) Send-HordeWebView2Json -Json $Json }
        capture = { param($Path) return (Start-HordeWebView2Capture -Path $Path) }
        setTitle = { param($Text) if ($null -ne $script:HordeWebView2) { $script:HordeWebView2.form.Text = "" + $Text } }
        show = { if ($null -ne $script:HordeWebView2 -and -not $script:HordeWebView2.spec.hidden) { [HordeSurfaceNative]::BringForward($script:HordeWebView2.form.Handle) } }
        close = { if ($null -ne $script:HordeWebView2) { $script:HordeWebView2.form.Close() } }
    }
}

function Open-HordeWebView2Surface {
    # Show -Spec and return when the window has been closed: { state; reason } (surfaces/Port.ps1).
    # -LibFolder is the pinned files' folder, for a test that hands it a folder it damaged.
    param([Parameter(Mandatory = $true)]$Spec, [string]$LibFolder = $script:HordeWebView2LibFolder)
    $fail = { param([string]$Why) return [pscustomobject]@{ state = "failed"; reason = $Why } }
    if ($null -ne $script:HordeWebView2) { return (& $fail "this process already shows a window; one process shows one") }
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) { return (& $fail "the window needs a single-threaded apartment, which Windows PowerShell gives unless it was started with -MTA") }
    $noFolder = Test-HordeWebView2DataFolder -Path $Spec.dataFolder
    if ($noFolder -ne "") { return (& $fail $noFolder) }
    # Held open from here until the engine is up (Invoke-HordeWebView2Initialized), or until this
    # function gives up or returns.
    $notLoaded = Import-HordeWebView2Libraries -Folder $LibFolder -Hold
    if ($notLoaded -ne "") { return (& $fail $notLoaded) }
    $noEngine = Get-HordeWebView2RuntimeProblem -Version (Get-HordeWebView2RuntimeVersion)
    if ($noEngine -ne "") { Clear-HordeWebView2HeldFiles; return (& $fail $noEngine) }

    # Before the first window of the process exists, which is when Windows documents the call.
    $scale = Enable-HordeWindowsRealScale
    $form = New-Object HordeSurfaceForm
    $form.Text = $Spec.title
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.Size = New-Object System.Drawing.Size($Spec.width, $Spec.height)
    $look = Get-HordeWebView2WindowLook -Spec $Spec
    $form.Quiet = $look.quiet
    if (-not $look.taskbar) { $form.ShowInTaskbar = $false }
    if ($null -ne $Spec.left) {
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $form.Location = New-Object System.Drawing.Point([int]$Spec.left, [int]$Spec.top)
    }
    if ($look.offScreen) {
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $form.Location = New-Object System.Drawing.Point($script:HordeWebView2HiddenAt, $script:HordeWebView2HiddenAt)
    }
    $view = New-Object Microsoft.Web.WebView2.WinForms.WebView2
    $props = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
    $props.UserDataFolder = $Spec.dataFolder
    $props.AdditionalBrowserArguments = $script:HordeWebView2NoNetwork
    $view.CreationProperties = $props
    $view.Dock = [System.Windows.Forms.DockStyle]::Fill
    $form.Controls.Add($view)
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [int]$Spec.tickMs
    # How long a page that flooded is not listened to: the meter's own second (surfaces/Port.ps1).
    $listenTimer = New-Object System.Windows.Forms.Timer
    $listenTimer.Interval = Get-HordeSurfaceMeterWindowMs

    # The caller's mounts, and the surface's own: this adapter's page side of the bridge, and the
    # port's definition of the messages it reads.
    $mounts = [ordered]@{}
    foreach ($m in @($Spec.mounts.Keys)) { $mounts[$m] = $Spec.mounts[$m] }
    $mounts[(Get-HordeSurfaceOwnMount)] = (Get-HordeSurfaceOwnFiles -BridgeScript (Join-Path $script:HordeWebView2Folder "page\bridge.js"))

    $handlers = Get-HordeWebView2Handlers
    $errors = New-Object System.Collections.ArrayList
    $script:HordeWebView2 = [pscustomobject]@{
        spec = $Spec; form = $form; view = $view; timer = $timer; mounts = $mounts; handlers = $handlers
        window = (Get-HordeWebView2Window -Form $form -Errors $errors)
        opened = $false; failure = ""; scale = $scale; capture = $null; pictures = 0
        meter = (New-HordeSurfaceMessageMeter); clock = [System.Diagnostics.Stopwatch]::StartNew()
        messageHandler = $null; deaf = $false; listenTimer = $listenTimer
        errors = $errors
    }
    foreach ($note in @(Get-HordeWebView2OpeningNotes -Scale $scale -Spec $Spec)) { Add-HordeSurfaceError -Errors $errors -Text $note -Kept $Spec.errorsKept }
    $state = $script:HordeWebView2
    try {
        $view.add_CoreWebView2InitializationCompleted($handlers.initialized)
        $form.add_Shown($handlers.shown)
        $form.add_FormClosed($handlers.closed)
        $timer.add_Tick($handlers.tick)
        $listenTimer.add_Tick($handlers.listen)
        [System.Windows.Forms.Application]::Run($form)
    }
    catch { if ($state.failure -eq "") { $state.failure = ("the window stopped: " + $_.Exception.Message) } }
    finally {
        $timer.Stop(); $timer.Dispose()
        $listenTimer.Stop(); $listenTimer.Dispose()
        Clear-HordeWebView2HeldFiles
        try { $view.Dispose() } catch { }
        try { $form.Dispose() } catch { }
        $script:HordeWebView2 = $null
    }
    if ($state.failure -ne "") { return (& $fail $state.failure) }
    if (-not $state.opened) { return (& $fail "the window was closed before the web engine had started") }
    return [pscustomobject]@{ state = "closed"; reason = "" }
}

$null = Register-HordeSurface -Folder $script:HordeWebView2Folder -Open { param($Spec) return (Open-HordeWebView2Surface -Spec $Spec) }
