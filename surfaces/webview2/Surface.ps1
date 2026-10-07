# surfaces/webview2/Surface.ps1 - a surface that is a window of this machine, drawn by the web engine
# that ships inside Windows 11 (decisions design 2026-10-06, sections 3.5, 3.6 and 3.11).
#
# WHAT IT DOES, and nothing else: it puts a page from folders on disk into a window Horde owns, keeps
# the page from going anywhere else, and carries text between the page and surfaces/Port.ps1's bridge.
# What the page is about, where the window stands and whose window it stands beside are its caller's.
#
# NO WEB SERVER, NO PORT. Each mount is a folder mapped to a host name that exists only inside the
# engine (surfaces/Port.ps1, WHERE A PAGE FINDS A MOUNT). Nothing listens, so no other page, program or
# machine can reach it: the whole question of who may post to it does not arise.
#
# THE PAGE CANNOT LEAVE, AND CANNOT REACH HORDE EXCEPT BY TEXT.
#   - a navigation to any address but the start page's own host is cancelled; every frame navigation
#     is cancelled; a request for a new window is marked handled and opens nothing. Each is recorded
#     on the bridge as a refusal.
#   - the page is handed NO object of Horde's: AddHostObjectToScript is never called (the suite reads
#     this file's syntax tree for it). The page posts text; a message whose source is not the start
#     page's host is refused; everything else goes to Invoke-HordeSurfaceRequest, which checks it.
#   - developer tools, the context menu, the browser's own keys (reload, find, print), the status bar
#     and saved form data are off.
#   - a download is cancelled, and recorded as a refusal. Left to the engine, a page that makes a link
#     with a download name and clicks it writes a file into the user's own Downloads folder, outside
#     anything of Horde's (measured 2026-10-06 by the review of this adapter, in a real hidden window:
#     the file was there).
#
# THE THREE PINNED FILES in lib/ are Microsoft's, under the licence beside them. They are checked
# against lib/fingerprints.txt BEFORE anything is loaded (core/Fingerprints.ps1), and a mismatch
# refuses to load: a changed file would run inside Horde with everything Horde can do.
#
# THE ENGINE ITSELF is not in this folder. It is the "WebView2 Runtime", part of Windows 11 and updated
# with Edge. Where it is not installed the surface says so in plain words and fails.
#
# MEASURED 2026-10-06 on a machine slowed on purpose, Windows PowerShell 5.1, engine 154.0.4258.53, a
# hidden window on a one-file page: the engine was up 1.2 s after the surface was asked to open, and
# the page's first request was answered 0.1 s after that.
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

$script:HordeWebView2Folder = $PSScriptRoot
$script:HordeWebView2LibFolder = Join-Path $PSScriptRoot "lib"
# Every one of these must be pinned by the list, or nothing is loaded: a list that pinned two of the
# three would let the third be anything.
$script:HordeWebView2LibFiles = @("Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.WinForms.dll", "WebView2Loader.dll")
$script:HordeWebView2 = $null
# Where a hidden window stands: far outside any screen, the coordinates Windows itself gives a
# minimised window, so nothing is drawn where a person can see it.
$script:HordeWebView2HiddenAt = -32000

# The window: a form that can be shown without taking the keyboard, and the one call that makes this
# process see real pixels on every screen. Compiled once per process.
$script:HordeWebView2NativeSource = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class HordeSurfaceForm : Form {
    public bool Quiet;
    protected override bool ShowWithoutActivation { get { return Quiet; } }
}
public static class HordeSurfaceNative {
    [DllImport("user32.dll", SetLastError = true)] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2. False when the process already has an awareness, or
    // on a Windows older than 10 1703, where the entry point is missing: the window then still works,
    // drawn by Windows at the wrong scale.
    public static bool PerMonitorDpi() {
        try { return SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch (EntryPointNotFoundException) { return false; }
    }
    public static void BringForward(IntPtr h) {
        if (IsIconic(h)) { ShowWindow(h, 9); }   // SW_RESTORE
        SetForegroundWindow(h);
    }
}
'@

function Test-HordeWebView2Address {
    # Is -Uri an address on the start page's own host, and nothing cleverer? https, exactly that host,
    # no user name in front of it, no port of its own. Everything else - another host, a host that only
    # begins with ours, a file, a data address, text that is no address - is not.
    param([AllowNull()][AllowEmptyString()][string]$Uri, [Parameter(Mandatory = $true)][string]$StartHost)
    $parsed = $null
    if (-not [System.Uri]::TryCreate("$Uri", [System.UriKind]::Absolute, [ref]$parsed)) { return $false }
    return [bool]($parsed.Scheme -ceq "https" -and $parsed.Host -ceq $StartHost.ToLowerInvariant() -and $parsed.UserInfo -eq "" -and $parsed.IsDefaultPort)
}

function Get-HordeWebView2RuntimeProblem {
    # "" when -Version is the version of an installed engine; otherwise what to tell a person.
    param([AllowNull()][AllowEmptyString()][string]$Version)
    if ("$Version".Trim() -ne "") { return "" }
    return "the web engine this window is drawn with is not installed on this machine. It is Microsoft's 'WebView2 Runtime', which comes with Windows 11 and with the Edge browser; install it from Microsoft and run this again. Every other horde command works without it"
}

function Test-HordeWebView2Libraries {
    # Are the pinned files in -Folder the ones its list says, all three of them? { ok; reason; files }.
    param([string]$Folder = $script:HordeWebView2LibFolder)
    $check = Test-HordeFingerprints -Folder $Folder
    $why = @($check.findings)
    $have = @($check.files | ForEach-Object { Split-Path -Leaf $_ })
    foreach ($need in $script:HordeWebView2LibFiles) { if ($have -cnotcontains $need) { $why += ($need + " is not pinned by the list, or did not match it") } }
    if ($why.Count -gt 0) { return [pscustomobject]@{ ok = $false; reason = ("the window's program files in " + $Folder + " are not the ones this version of Horde pins, so none was loaded: " + (@($why | Select-Object -Unique) -join "; ")); files = @() } }
    return [pscustomobject]@{ ok = $true; reason = ""; files = @($script:HordeWebView2LibFiles | ForEach-Object { Join-Path $Folder $_ }) }
}

function Import-HordeWebView2Libraries {
    # Check the pinned files, then load them. Returns "" when they are loaded, or why they were not.
    # THE CHECK COMES FIRST, every time: nothing of the folder is loaded unless all of it matches.
    param([string]$Folder = $script:HordeWebView2LibFolder)
    $libs = Test-HordeWebView2Libraries -Folder $Folder
    if (-not $libs.ok) { return $libs.reason }
    if ($null -eq ("Microsoft.Web.WebView2.Core.CoreWebView2Environment" -as [type])) {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        Add-Type -Path $libs.files[0]
        Add-Type -Path $libs.files[1]
        # The third file is not .NET: the first two find it through this folder when the engine starts.
        [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::SetLoaderDllFolderPath($Folder)
    }
    if ($null -eq ("HordeSurfaceForm" -as [type])) { Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition $script:HordeWebView2NativeSource }
    return ""
}

function Get-HordeWebView2RuntimeVersion {
    # The installed engine's version, or "" when there is none. Call only after the files are loaded.
    try { return ("" + [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::GetAvailableBrowserVersionString()) } catch { return "" }
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
    if (-not (Test-HordeWebView2Address -Uri $Source -StartHost $s.startHost)) {
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
        # DenyCors: a page on one mount may use a script or a style sheet of another, as a page uses a
        # file beside it, and may not read another mount's files as data.
        # The page has a light and a dark look and follows the machine's setting unless the caller chose.
        if ($s.spec.theme -ceq "dark") { $core.Profile.PreferredColorScheme = [Microsoft.Web.WebView2.Core.CoreWebView2PreferredColorScheme]::Dark }
        elseif ($s.spec.theme -ceq "light") { $core.Profile.PreferredColorScheme = [Microsoft.Web.WebView2.Core.CoreWebView2PreferredColorScheme]::Light }
        $kind = [Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind]::DenyCors
        foreach ($mount in @($s.mounts.Keys)) { $core.SetVirtualHostNameToFolderMapping((Get-HordeSurfaceMountHost -Mount $mount), $s.mounts[$mount], $kind) }
        $h = $s.handlers
        $core.add_NavigationStarting($h.navigation)
        $core.add_FrameNavigationStarting($h.frame)
        $core.add_NewWindowRequested($h.newWindow)
        $core.add_DownloadStarting($h.download)
        $core.add_WebMessageReceived($h.message)
        $core.Navigate("https://" + $s.startHost + "/" + $s.spec.startFile)
        $s.opened = $true
        if ($null -ne $s.spec.onOpened) { & $s.spec.onOpened $s.window $s.spec.state }
        $s.timer.Start()
    } catch { Stop-HordeWebView2 -Reason ("the window could not be set up: " + $_.Exception.Message) }
}

function Invoke-HordeWebView2Navigation {
    param($What)
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    if (Test-HordeWebView2Address -Uri ("" + $What.Uri) -StartHost $s.startHost) { return }
    $What.Cancel = $true
    Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason "the page tried to go to an address that is not its own, and was kept where it is"
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

function Invoke-HordeWebView2Message {
    param($What)
    $s = $script:HordeWebView2
    if ($null -eq $s) { return }
    try {
        $reply = Receive-HordeWebView2Message -Json ("" + $What.WebMessageAsJson) -Source ("" + $What.Source)
        if ("$reply" -ne "") { Send-HordeWebView2Json -Json $reply }
    } catch { [void]$s.errors.Add("a message from the page could not be answered: " + $_.Exception.Message) }
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
    if (-not [System.IO.Path]::IsPathRooted("$Path") -or [System.IO.Path]::GetExtension("$Path") -ine ".png") { [void]$s.errors.Add("a picture is saved at an absolute path ending .png, and none was made"); return $false }
    $stream = $null
    try {
        $temp = $Path + "." + $PID + ".tmp"
        $stream = [System.IO.File]::Open($temp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $task = $s.view.CoreWebView2.CapturePreviewAsync([Microsoft.Web.WebView2.Core.CoreWebView2CapturePreviewImageFormat]::Png, $stream)
        $s.capture = [pscustomobject]@{ path = $Path; temp = $temp; stream = $stream; task = $task }
        return $true
    } catch {
        if ($null -ne $stream) { $stream.Dispose() }
        [void]$s.errors.Add("a picture could not be asked for: " + $_.Exception.Message)
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
        [void]$s.errors.Add("a picture could not be saved: " + $_.Exception.Message)
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
    try { & $s.spec.onTick $s.window $s.spec.state } catch { [void]$s.errors.Add("a tick failed: " + $_.Exception.Message) }
}

function Invoke-HordeWebView2Closed {
    $s = $script:HordeWebView2
    if ($null -eq $s -or $null -eq $s.spec.onClosed) { return }
    try { & $s.spec.onClosed $s.window $s.spec.state } catch { [void]$s.errors.Add("closing failed: " + $_.Exception.Message) }
}

function Get-HordeWebView2Handlers {
    # The script blocks given to .NET events, each one line that calls a named function (header, A
    # HANDLER TAKES WHAT IT NEEDS FROM $script:HordeWebView2). This function has returned long before
    # any of them runs, which is exactly the case they must work in.
    return @{
        shown       = { Invoke-HordeWebView2Shown }
        initialized = { param($From, $What) Invoke-HordeWebView2Initialized -What $What }
        navigation  = { param($From, $What) Invoke-HordeWebView2Navigation -What $What }
        frame       = { param($From, $What) Invoke-HordeWebView2Frame -Frame $What }
        newWindow   = { param($From, $What) Invoke-HordeWebView2NewWindow -What $What }
        download    = { param($From, $What) Invoke-HordeWebView2Download -Download $What }
        message     = { param($From, $What) Invoke-HordeWebView2Message -What $What }
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
    $notLoaded = Import-HordeWebView2Libraries -Folder $LibFolder
    if ($notLoaded -ne "") { return (& $fail $notLoaded) }
    $noEngine = Get-HordeWebView2RuntimeProblem -Version (Get-HordeWebView2RuntimeVersion)
    if ($noEngine -ne "") { return (& $fail $noEngine) }

    # Before the first window of the process exists, or Windows will not take it.
    $realPixels = [HordeSurfaceNative]::PerMonitorDpi()
    $form = New-Object HordeSurfaceForm
    $form.Text = $Spec.title
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.Size = New-Object System.Drawing.Size($Spec.width, $Spec.height)
    $form.Quiet = [bool]($Spec.companion -or $Spec.hidden)
    if ($Spec.companion -or $Spec.hidden) { $form.ShowInTaskbar = $false }
    if ($null -ne $Spec.left) {
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $form.Location = New-Object System.Drawing.Point([int]$Spec.left, [int]$Spec.top)
    }
    if ($Spec.hidden) {
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $form.Location = New-Object System.Drawing.Point($script:HordeWebView2HiddenAt, $script:HordeWebView2HiddenAt)
    }
    $view = New-Object Microsoft.Web.WebView2.WinForms.WebView2
    $props = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
    $props.UserDataFolder = $Spec.dataFolder
    $view.CreationProperties = $props
    $view.Dock = [System.Windows.Forms.DockStyle]::Fill
    $form.Controls.Add($view)
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [int]$Spec.tickMs

    # The caller's mounts, and the surface's own: the page's side of the bridge.
    $mounts = [ordered]@{}
    foreach ($m in @($Spec.mounts.Keys)) { $mounts[$m] = $Spec.mounts[$m] }
    $mounts[(Get-HordeSurfaceOwnMount)] = (Join-Path $script:HordeWebView2Folder "page")

    $handlers = Get-HordeWebView2Handlers
    $errors = New-Object System.Collections.ArrayList
    $script:HordeWebView2 = [pscustomobject]@{
        spec = $Spec; form = $form; view = $view; timer = $timer; mounts = $mounts; handlers = $handlers
        startHost = (Get-HordeSurfaceMountHost -Mount $Spec.startMount)
        window = (Get-HordeWebView2Window -Form $form -Errors $errors)
        opened = $false; failure = ""; realPixels = $realPixels; capture = $null; pictures = 0
        errors = $errors
    }
    $state = $script:HordeWebView2
    try {
        $view.add_CoreWebView2InitializationCompleted($handlers.initialized)
        $form.add_Shown($handlers.shown)
        $form.add_FormClosed($handlers.closed)
        $timer.add_Tick($handlers.tick)
        [System.Windows.Forms.Application]::Run($form)
    }
    catch { if ($state.failure -eq "") { $state.failure = ("the window stopped: " + $_.Exception.Message) } }
    finally {
        $timer.Stop(); $timer.Dispose()
        try { $view.Dispose() } catch { }
        try { $form.Dispose() } catch { }
        $script:HordeWebView2 = $null
    }
    if ($state.failure -ne "") { return (& $fail $state.failure) }
    if (-not $state.opened) { return (& $fail "the window was closed before the web engine had started") }
    return [pscustomobject]@{ state = "closed"; reason = "" }
}

$null = Register-HordeSurface -Folder $script:HordeWebView2Folder -Open { param($Spec) return (Open-HordeWebView2Surface -Spec $Spec) }
