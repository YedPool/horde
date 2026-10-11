# DOES THE WINDOW SURFACE DO, IN A REAL WINDOW, EACH THING ITS capabilities.json SAYS YES TO?
#
# surfaces/webview2/test/test-webview2-surface.ps1 checks what can be checked with no window. This
# suite opens the real one - hidden, at -32000,-32000, out of the taskbar, never taking the keyboard -
# on a small page of its own (test/pages/probe) that behaves as a hostile page would, and holds three
# things against each other: what the page saw from inside, what the surface recorded on the bridge,
# and what reached a listener the suite itself opens on the loopback address to stand for "outside".
# A handler the engine was never handed records nothing here, so this is also the check that each
# lock is really given to the engine (review of 2026-10-06, finding A5).
#
# MACHINE-BOUND (test/lib/SuiteFiles.ps1): it needs the web engine installed and an interactive
# logon, so it runs through the local gate and never on the remote test box.
#
# WHAT IT TOUCHES: four windows of this process, one after another - three hidden at -32000,-32000 and
# one that stands free, put at -32000,-32000 by its caller, which has a place in the taskbar for the
# second or so it lives; none takes the keyboard. A profile folder for each, a picture and a home of
# its own under %TEMP%; one listening socket on 127.0.0.1 at a port Windows picks, closed at the end.
# It reads and writes nothing under the real Horde home. If the download lock ever fails, the page's file lands in the user's own
# Downloads folder under a name unique to this run, and this suite removes exactly that file.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "surfaces\Port.ps1")
. (Join-Path $root "surfaces\webview2\Surface.ps1")

Add-Type -Namespace HordeSurfaceProbe -Name Native -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int index);
'@

$work = Join-Path $env:TEMP ("horde-webview2-window-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
# A home of this run, never made: the surface's settings are then their defaults, whatever a person
# has written in the real home's file.
$env:HORDE_HOME = Join-Path $work "home"
$pages = Join-Path $here "pages"

function Get-ProbeProcessTree {
    # This process and everything it started, as { id; name }: the engine's processes are among them.
    $all = @((New-Object System.Management.ManagementObjectSearcher("SELECT ProcessId, ParentProcessId, Name FROM Win32_Process")).Get() | ForEach-Object { [pscustomobject]@{ id = [int]$_.ProcessId; parent = [int]$_.ParentProcessId; name = "" + $_.Name } })
    $tree = New-Object System.Collections.ArrayList
    $ids = @{ $PID = $true }
    [void]$tree.Add([pscustomobject]@{ id = $PID; name = "this process" })
    $grew = $true
    while ($grew) {
        $grew = $false
        foreach ($p in $all) { if ($ids.ContainsKey($p.parent) -and -not $ids.ContainsKey($p.id)) { $ids[$p.id] = $true; [void]$tree.Add([pscustomobject]@{ id = $p.id; name = $p.name }); $grew = $true } }
    }
    return @($tree)
}

function Get-ProbeListeners {
    # Every TCP port a process of -Ids listens on, as "<pid> <address:port>", read from Windows' own table.
    param([int[]]$Ids)
    $found = New-Object System.Collections.ArrayList
    $tool = Join-Path ([System.Environment]::SystemDirectory) "netstat.exe"
    foreach ($line in @(& $tool -ano)) {
        if ("$line" -match '^\s*TCP\s+(\S+)\s+\S+\s+LISTENING\s+(\d+)\s*$' -and $Ids -contains [int]$Matches[2]) { [void]$found.Add($Matches[2] + " " + $Matches[1]) }
    }
    return @($found)
}

function Receive-ProbeConnections {
    # Take every connection waiting at the suite's listener, note its first line, answer it as a web
    # server would (so that a load the surface failed to stop is seen by the page as loaded), close it.
    param($State)
    while ($State.listener.Pending()) {
        $client = $State.listener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout = 300
            $stream = $client.GetStream()
            $buffer = New-Object byte[] 2048
            $n = 0
            try { $n = $stream.Read($buffer, 0, $buffer.Length) } catch { $n = 0 }
            $first = @([System.Text.Encoding]::ASCII.GetString($buffer, 0, $n) -split "`r?`n")[0]
            [void]$State.connections.Add("" + $first)
            $answer = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Type: text/javascript`r`nContent-Length: 2`r`nConnection: close`r`n`r`n//")
            try { $stream.Write($answer, 0, $answer.Length) } catch { }
        } finally { $client.Close() }
    }
}

function Add-ProbeResult {
    # One thing the page reports: what it saw, and every refusal the surface recorded since its last report.
    param($State, [string]$Key, [string]$Value)
    $new = [int]$State.bridge.refused - [int]$State.refusedSeen
    $State.refusedSeen = [int]$State.bridge.refused
    $kept = @($State.bridge.refusals | ForEach-Object { $_.reason })
    $reasons = @()
    if ($new -gt 0) { $reasons = @($kept | Select-Object -Last ([Math]::Min($new, $kept.Count))) }
    $State.results[$Key] = [pscustomobject]@{ value = $Value; refusals = $new; reasons = $reasons }
}

function Step-Probe {
    # The suite's side of the window, one small step each tick. A step never waits: it looks, acts
    # once, and names the next step, so the window's thread is never held.
    param($Window, $State)
    Receive-ProbeConnections -State $State
    if ($State.clock.ElapsedMilliseconds -gt $State.limitMs) { $State.timedOut = $State.phase; & $Window.close; return }
    if ($State.phase -ceq "push") {
        & $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "poke" -Value $State.pokeValue)
        $State.phase = "pushed"
    }
    elseif ($State.phase -ceq "pushed") { if ($State.results.Contains("push")) { $State.phase = "window" } }
    elseif ($State.phase -ceq "window") {
        $handle = [IntPtr][long]$Window.handle
        $owner = [uint32]0
        [void][HordeSurfaceProbe.Native]::GetWindowThreadProcessId($handle, [ref]$owner)
        $rect = New-Object HordeSurfaceProbe.Native+RECT
        [void][HordeSurfaceProbe.Native]::GetWindowRect($handle, [ref]$rect)
        $State.native = [pscustomobject]@{
            handle = [long]$Window.handle; isWindow = [HordeSurfaceProbe.Native]::IsWindow($handle); visible = [HordeSurfaceProbe.Native]::IsWindowVisible($handle)
            owner = [int]$owner; left = $rect.Left; top = $rect.Top; width = ($rect.Right - $rect.Left); height = ($rect.Bottom - $rect.Top)
            hasKeyboard = ([HordeSurfaceProbe.Native]::GetForegroundWindow() -eq $handle); hadKeyboardAtOpen = $State.hadKeyboardAtOpen
            inTaskbar = (([HordeSurfaceProbe.Native]::GetWindowLongPtr($handle, -20).ToInt64() -band 0x40000) -ne 0)
        }
        $State.phase = "sockets"
    }
    elseif ($State.phase -ceq "sockets") {
        $State.tree = @(Get-ProbeProcessTree)
        $State.listeners = @(Get-ProbeListeners -Ids @($State.tree | ForEach-Object { $_.id }))
        $State.phase = "picture"
    }
    elseif ($State.phase -ceq "picture") {
        $State.pictureAsked = (& $Window.capture $State.picturePath)
        $State.secondAsked = (& $Window.capture $State.secondPath)
        $State.phase = "drawing"
    }
    elseif ($State.phase -ceq "drawing") { if (Test-Path -LiteralPath $State.picturePath -PathType Leaf) { $State.errorsAtEnd = @($Window.errors); $State.phase = "closing" } }
    elseif ($State.phase -ceq "closing") { & $Window.close }
}

try {

Write-Host ""
Write-Host "--- the engine, and the suite's own instruments ---" -ForegroundColor Cyan
$loaded = Import-HordeWebView2Libraries
$engine = Get-HordeWebView2RuntimeVersion
Check ($loaded -ceq "" -and $engine -ne "") ("the web engine is installed here (" + $engine + "): without it nothing below can be shown, and no capability is proved")

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$probe = [pscustomobject]@{
    bridge = $null; results = [ordered]@{}; refusedSeen = 0; phase = "page"; timedOut = ""; limitMs = 40000
    clock = [System.Diagnostics.Stopwatch]::StartNew(); listener = $listener; connections = (New-Object System.Collections.ArrayList)
    outside = ("http://127.0.0.1:" + $port); socket = ("ws://127.0.0.1:" + $port); stamp = ("horde-surface-probe-" + [guid]::NewGuid().ToString("N"))
    pokeValue = ("poked " + [char]0x05E9 + [char]0x05DC + [char]0x05D5 + [char]0x05DD + " <b>&'")
    picturePath = (Join-Path $work "page.png"); secondPath = (Join-Path $work "second.png"); pictureAsked = $null; secondAsked = $null
    native = $null; tree = @(); listeners = @(); hadKeyboardAtOpen = $null; openedMs = 0; closed = $false; errorsAtEnd = @(); heldAtOpen = -1
}
$knock = New-Object System.Net.Sockets.TcpClient
$knock.Connect([System.Net.IPAddress]::Loopback, $port)
$hello = [System.Text.Encoding]::ASCII.GetBytes("GET /control HTTP/1.1`r`n`r`n")
$knock.GetStream().Write($hello, 0, $hello.Length)
Start-Sleep -Milliseconds 200
Receive-ProbeConnections -State $probe
$knock.Close()
Check (@($probe.connections) -ccontains "GET /control HTTP/1.1") "CONTROL: a connection to the suite's listener is seen and its first line kept, so a load that leaves the engine cannot go unnoticed"
Check (@(Get-ProbeListeners -Ids @($PID)) -ccontains ("" + $PID + " 127.0.0.1:" + $port)) "CONTROL: Windows' table of listening ports shows the suite's own listener under this process"
$probe.connections.Clear()

$probe.bridge = New-HordeSurfaceBridge -Events @("poke") -Requests ([ordered]@{
    "setup"  = @{ run = { param($Arguments, $State, $Window) return [pscustomobject]@{ outside = $State.outside; socket = $State.socket; stamp = $State.stamp } } }
    "report" = @{ args = @{ key = @{ type = "string"; most = 64 }; value = @{ type = "string"; most = 1600 } }
                  run = { param($Arguments, $State, $Window) Add-ProbeResult -State $State -Key $Arguments["key"] -Value $Arguments["value"]; return $true } }
    "done"   = @{ run = { param($Arguments, $State, $Window) $State.phase = "push"; return $true } }
    # A handler that fails as real ones do: with the path of a file in what it says.
    "breaks" = @{ run = { param($Arguments, $State, $Window) throw "C:\made-up\place\store.json is held by another process" } }
})
$spec = New-HordeSurfaceSpec -Title "surface probe" -Mounts ([ordered]@{ probe = (Join-Path $pages "probe"); other = (Join-Path $pages "other") }) -Start "probe/index.html" `
    -Bridge $probe.bridge -DataFolder (Join-Path $work "data") -Hidden -Width 480 -Height 360 -TickMs 50 -State $probe `
    -OnOpened { param($Window, $State) $State.openedMs = $State.clock.ElapsedMilliseconds; $State.heldAtOpen = @($script:HordeWebView2Held).Count; $State.hadKeyboardAtOpen = ([HordeSurfaceProbe.Native]::GetForegroundWindow() -eq [IntPtr][long]$Window.handle) } `
    -OnTick { param($Window, $State) Step-Probe -Window $Window -State $State } `
    -OnClosed { param($Window, $State) $State.closed = $true }
$surface = Resolve-HordeSurface -Requires @("page.local", "page.locked", "requests.closed", "push", "window.native", "picture")
$probe.clock.Restart()
$shown = Open-HordeSurface -Surface $surface -Spec $spec
$tookMs = $probe.clock.ElapsedMilliseconds
Receive-ProbeConnections -State $probe
$r = $probe.results
function Saw { param([string]$Key) if ($r.Contains($Key)) { return $r[$Key] }; return [pscustomobject]@{ value = "<the page never reported " + $Key + ">"; refusals = -1; reasons = @() } }
$steps = @("where", "bridge", "unknown-request", "failed-request", "host-objects", "raw-message",
    "own-fetch", "other-script", "other-fetch", "definition-fetch",
    "in-missing", "in-kind", "in-above", "in-escaped", "in-dots", "in-backslash", "in-port-file",
    "out-script", "out-style", "out-image", "out-fetch", "out-fetch-blind", "out-xhr", "out-beacon", "out-events", "out-font", "out-socket", "out-worker",
    "nav-out", "nav-lookalike", "nav-other-mount", "nav-scheme", "frame-own", "frame-out", "new-window", "download", "ask-place", "ask-notify", "push")

Write-Host ""
Write-Host "--- the window opened, ran the whole probe and closed ---" -ForegroundColor Cyan
Check ($shown.state -ceq "closed" -and $shown.reason -ceq "" -and $probe.closed -eq $true) ("the surface showed the page and says it was closed (" + $shown.state + " " + $shown.reason + "), " + $tookMs + " ms; the engine was up after " + $probe.openedMs + " ms")
Check ($probe.timedOut -ceq "") ("no step of the probe ran out of time (stopped in: '" + $probe.timedOut + "')")
Check ((@($r.Keys) -join ",") -ceq ($steps -join ",")) ("the page reported every step, in order (" + (@($r.Keys) -join ",") + ")")
Check (@($probe.errorsAtEnd).Count -eq 1 -and @($probe.errorsAtEnd)[0] -like "the request 'breaks' failed: *") ("the window recorded no error of its own but the one request this suite makes fail (" + (@($probe.errorsAtEnd) -join "; ") + ")")
Check ($probe.heldAtOpen -eq 0) ("the engine started with its three pinned files held open by the surface - it could read them, nothing could change them - and once it was up the surface had let go of all of them (" + $probe.heldAtOpen + " still held)")

Write-Host ""
Write-Host "--- page.local: the page is files of this machine, and nothing listens ---" -ForegroundColor Cyan
$home1 = (Saw "where").value
Check ($home1 -like "https://*/probe/index.html" -and (Saw "bridge").value -ceq "function function live=true") ("the page was drawn from its mount and found the bridge by a relative address (" + $home1 + "; " + (Saw "bridge").value + ")")
Check ((Saw "where").refusals -eq 0) "and loading it recorded no refusal: what the engine asks for by itself is not held against the page"
$engines = @($probe.tree | Where-Object { $_.name -like "msedgewebview2*" })
Check ($engines.Count -ge 1) ("CONTROL: the engine's own processes were found under this one while the window stood (" + $engines.Count + ")")
$ownListener = "" + $PID + " 127.0.0.1:" + $port
Check (@($probe.listeners) -ccontains $ownListener -and @($probe.listeners | Where-Object { $_ -cne $ownListener }).Count -eq 0) ("while the page was shown, no process of the window listened on any port but the suite's own listener (" + (@($probe.listeners) -join ", ") + ")")

Write-Host ""
Write-Host "--- a page uses its own files and another mount's by relative address ---" -ForegroundColor Cyan
$ownFetch = Saw "own-fetch"
Check ($ownFetch.value -like "status 200 text/css; charset=utf-8 * characters" -and $ownFetch.refusals -eq 0) ("a file beside the page is served with its kind's type (" + $ownFetch.value + ")")
Check ((Saw "other-script").value -ceq "LOADED the other mount" -and (Saw "other-script").refusals -eq 0) ("a script of another mount, asked for as ../other/other.js, runs (" + (Saw "other-script").value + ")")
Check ((Saw "other-fetch").value -ceq 'status 200 { "from": "the other mount" }') ("and another mount's data can be read the same way (" + (Saw "other-fetch").value + ")")
Check ((Saw "definition-fetch").value -ceq "status 200 protocol 1") ("the surface's own mount serves the port's one definition of the messages (" + (Saw "definition-fetch").value + ")")

Write-Host ""
Write-Host "--- what is not a file of a mount is not served, and is recorded ---" -ForegroundColor Cyan
foreach ($try in @(
    @{ key = "in-missing"; what = "a file that is not there"; says = "*a file that is not there*" }
    @{ key = "in-kind"; what = "a kind of file no page is made of, though it is there"; says = "*not a kind of file a page is made of*" }
    @{ key = "in-above"; what = "a climb above the mounts"; says = "*not a file of a mount*" }
    @{ key = "in-escaped"; what = "a climb written with escaped slashes"; says = "*not a file of a mount*" }
    @{ key = "in-dots"; what = "a climb written with escaped dots"; says = "*not a file of a mount*" }
    @{ key = "in-backslash"; what = "a climb written with escaped backslashes"; says = "*not a file of a mount*" }
    @{ key = "in-port-file"; what = "a file of Horde's own beside the two the surface serves"; says = "*not a kind of file a page is made of*" }
)) {
    $seen = Saw $try.key
    Check ($seen.value -ceq "status 403" -and $seen.refusals -eq 1 -and @($seen.reasons)[0] -like $try.says) ("asked for " + $try.what + ", the page is answered 403 and the refusal is recorded once (" + $seen.value + "; " + $seen.refusals + "; " + (@($seen.reasons) -join " | ") + ")")
}

Write-Host ""
Write-Host "--- the surface itself refuses every load from outside ---" -ForegroundColor Cyan
foreach ($try in @(
    @{ key = "out-script"; what = "a script" }, @{ key = "out-style"; what = "a style sheet" }, @{ key = "out-image"; what = "an image" }
    @{ key = "out-fetch"; what = "a call" }, @{ key = "out-fetch-blind"; what = "a call that asks to see no answer" }, @{ key = "out-xhr"; what = "a call of the older kind" }
    @{ key = "out-beacon"; what = "a beacon" }, @{ key = "out-events"; what = "an event stream" }, @{ key = "out-font"; what = "a font" }
)) {
    $seen = Saw $try.key
    Check ($seen.value -notlike "*LOADED*" -and $seen.refusals -ge 1 -and @($seen.reasons) -like "*not one of its own files*") (($try.what + " from outside is not loaded, and the refusal is recorded (" + $seen.value + "; " + $seen.refusals + ")"))
}
$socket = Saw "out-socket"
Check ($socket.value -ceq "blocked") ("a socket to outside does not open (" + $socket.value + "). THE ENGINE HANDS NO SOCKET TO THE SURFACE, so this one is stopped by the engine having no network and is not recorded")
$worker = Saw "out-worker"
Check ($worker.value -notlike "*LOADED*" -and $worker.value -notlike "*OPEN*" -and $worker.value -like "*socket blocked" -and $worker.refusals -ge 1) ("a worker of the page gets no further: its call is refused and recorded, its socket does not open (" + $worker.value + ")")
Check (@($probe.connections).Count -eq 0) ("THROUGH ALL OF IT - loads, sockets, and below the navigations, frames and the download - nothing reached the suite's listener (" + (@($probe.connections) -join " | ") + ")")

Write-Host ""
Write-Host "--- requests.closed: only the list, only as text ---" -ForegroundColor Cyan
$unknown = Saw "unknown-request"
Check ($unknown.value -like "rejected: refused: *not on the list*" -and $unknown.value -notlike "*win.ini*" -and $unknown.value -notlike "*open-file*") ("a request off the list is refused in the real window, and the refusal repeats nothing the page sent (" + $unknown.value + ")")
Check ($unknown.refusals -eq 1 -and @($unknown.reasons)[0] -like "*not on the list*") "and it is recorded on the bridge, once"
# A REQUEST THAT FAILS (surfaces/Port.ps1): what the handler said stays on Horde's side of the window.
$failedAsk = Saw "failed-request"
Check ($failedAsk.value -ceq "rejected: the request 'breaks' failed" -and $failedAsk.refusals -eq 0) ("a request whose handler throws is rejected in the real page with one fixed sentence - not the handler's words, not the path in them - and is no refusal (" + $failedAsk.value + "; " + $failedAsk.refusals + ")")
Check (@($probe.errorsAtEnd) -ccontains "the request 'breaks' failed: C:\made-up\place\store.json is held by another process" -and $probe.bridge.failed -eq 1 -and $probe.bridge.failures[0].reason -ceq @($probe.errorsAtEnd)[0]) ("what the handler said is whole in the errors the window's caller reads, and on the bridge's record (" + (@($probe.errorsAtEnd) -join "; ") + ")")
Check ((Saw "host-objects").value -like "none*") ("the page finds no object of Horde's to call (" + (Saw "host-objects").value + ")")
$rawSeen = Saw "raw-message"
Check ($rawSeen.refusals -eq 1 -and @($rawSeen.reasons)[0] -like "*not one JSON object*") "text posted behind the bridge's back is refused and recorded, not read"
Check ($probe.bridge.answered -eq ($steps.Count + 2)) ("every report, the setup and the done were answered through the list: " + $probe.bridge.answered + " answers")

Write-Host ""
Write-Host "--- page.locked: the page cannot leave, and each lock is the engine's to call ---" -ForegroundColor Cyan
foreach ($try in @(
    @{ key = "nav-out"; what = "an address outside" }
    @{ key = "nav-lookalike"; what = "a host that only begins with the page's own" }
    @{ key = "nav-other-mount"; what = "a file of another mount" }
    @{ key = "nav-scheme"; what = "an address for another program to open" }
)) {
    $seen = Saw $try.key
    Check ($seen.value -ceq ("still at " + $home1) -and $seen.refusals -ge 1 -and @($seen.reasons) -like "*an address that is not its own*") ("sent to " + $try.what + ", the page stays where it is and the refusal is recorded (" + $seen.value + "; " + $seen.refusals + ")")
}
foreach ($try in @(@{ key = "frame-own"; what = "a file of its own" }, @{ key = "frame-out"; what = "an address outside" })) {
    $seen = Saw $try.key
    Check ($seen.value -ceq "no frame ran" -and $seen.refusals -ge 1 -and @($seen.reasons) -like "*load a frame*") ("a frame on " + $try.what + " is not loaded, and is recorded (" + $seen.value + "; " + $seen.refusals + ")")
}
$popped = Saw "new-window"
Check ($popped.value -ceq "no window" -and $popped.refusals -eq 1 -and @($popped.reasons)[0] -like "*a new window*") ("asked for a new window, the page gets none, and it is recorded (" + $popped.value + ")")
$saved = Saw "download"
$downloads = Join-Path ([System.Environment]::GetFolderPath("UserProfile")) "Downloads"
try { $named = (Get-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction Stop)."{374DE290-123F-4565-9164-39C4925E467B}"; if ("$named" -ne "") { $downloads = [System.Environment]::ExpandEnvironmentVariables("$named") } } catch { }
$landed = Join-Path $downloads ($probe.stamp + ".txt")
$wasSaved = Test-Path -LiteralPath $landed -PathType Leaf
if ($wasSaved) { Remove-Item -LiteralPath $landed -Force }
Check ($saved.refusals -eq 1 -and @($saved.reasons)[0] -like "*save a file*" -and -not $wasSaved) ("a download the page starts is refused and recorded, and no file of this run is in " + $downloads)

$place = Saw "ask-place"
Check ($place.value -ceq "denied code 1" -and $place.refusals -eq 1 -and @($place.reasons)[0] -like "*asked the machine for something (the engine's word for it: Geolocation), and it was denied") ("asked where the machine is, the page is denied at once and it is recorded (" + $place.value + "; " + (@($place.reasons) -join " | ") + ")")
$notify = Saw "ask-notify"
Check ($notify.value -ceq "answered denied" -and $notify.refusals -eq 1 -and @($notify.reasons)[0] -like "*(the engine's word for it: Notifications), and it was denied") ("asked to put notices on the person's screen, the same (" + $notify.value + "; " + (@($notify.reasons) -join " | ") + ")")

Write-Host ""
Write-Host "--- push: Horde hands the page an event while it is shown ---" -ForegroundColor Cyan
Check ((Saw "push").value -ceq $probe.pokeValue) "an event pushed to the open page arrives, with text in another alphabet and markup character for character"

Write-Host ""
Write-Host "--- window.native: a window of this process, that never takes the keyboard when hidden ---" -ForegroundColor Cyan
$n = $probe.native
Check ($null -ne $n -and $n.handle -ne 0 -and $n.isWindow -eq $true -and $n.owner -eq $PID) ("the handle the caller is handed is a window, and this process's own (owner " + $(if ($null -ne $n) { $n.owner } else { "?" }) + ", this process " + $PID + ")")
Check ($null -ne $n -and $n.left -eq -32000 -and $n.top -eq -32000 -and $n.visible -eq $true -and $n.inTaskbar -eq $false) "a hidden window is shown where no screen is, at -32000,-32000, and has no place in the taskbar"
Check ($null -ne $n -and $n.hadKeyboardAtOpen -eq $false -and $n.hasKeyboard -eq $false) "and it did not take the keyboard, when it appeared or after"

Write-Host ""
Write-Host "--- picture: Horde can save what the page drew ---" -ForegroundColor Cyan
Check ($probe.pictureAsked -eq $true -and $probe.secondAsked -eq $false -and -not (Test-Path -LiteralPath $probe.secondPath)) "a picture is asked for and taken; a second ask while it is drawn is not, and makes no file"
$colours = @{}
$size = "none"
$isPng = $false
if (Test-Path -LiteralPath $probe.picturePath -PathType Leaf) {
    $bytes = [System.IO.File]::ReadAllBytes($probe.picturePath)
    $isPng = ($bytes.Length -gt 8 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47)
    Add-Type -AssemblyName System.Drawing
    $stream = New-Object System.IO.MemoryStream(, $bytes)
    $bitmap = New-Object System.Drawing.Bitmap($stream)
    try {
        $size = "" + $bitmap.Width + "x" + $bitmap.Height
        for ($x = 0; $x -lt 24; $x++) { for ($y = 0; $y -lt 24; $y++) { $c = $bitmap.GetPixel([int](($x + 0.5) * $bitmap.Width / 24), [int](($y + 0.5) * $bitmap.Height / 24)); $colours[$c.ToArgb()] = $c } }
    } finally { $bitmap.Dispose(); $stream.Dispose() }
}
$hasRed = @($colours.Values | Where-Object { $_.R -gt 180 -and $_.G -lt 80 -and $_.B -lt 80 }).Count -gt 0
$hasBlue = @($colours.Values | Where-Object { $_.B -gt 180 -and $_.R -lt 80 -and $_.G -lt 110 }).Count -gt 0
Check ($isPng -and $size -cne "none" -and $size -cne "0x0") ("the file is a PNG with a size (" + $size + ")")
Check ($colours.Count -ge 4 -and $hasRed -and $hasBlue) ("and it is not blank: " + $colours.Count + " colours at 576 sampled points, the page's red and blue blocks among them")
Check (@(Get-ChildItem -LiteralPath $work -Filter "*.tmp").Count -eq 0) "no half-written picture is left beside it"

Write-Host ""
Write-Host "--- after the window: nothing of the engine is left running ---" -ForegroundColor Cyan
$left = @($engines)
$waited = [System.Diagnostics.Stopwatch]::StartNew()
while ($waited.ElapsedMilliseconds -lt 20000) {
    $left = @($engines | Where-Object { $null -ne (Get-Process -Id $_.id -ErrorAction SilentlyContinue) })
    if ($left.Count -eq 0) { break }
    Start-Sleep -Milliseconds 250
}
Check ($left.Count -eq 0) ("every engine process the window started has gone, " + $waited.ElapsedMilliseconds + " ms after it closed (" + (@($left | ForEach-Object { $_.name + " " + $_.id }) -join ", ") + ")")

Write-Host ""
Write-Host "--- both sides of the bridge read the one definition of the messages ---" -ForegroundColor Cyan
# A SECOND WINDOW, OPENED WITH ANOTHER DEFINITION IN FORCE: protocol 7 and other member names, in a
# file of this run. The port is handed it, and the surface serves it to the page as it serves the
# shipped one. The page (pages/probe/echo.js) names no member of any message. If either side carried
# a name or a number of its own, not one message would cross.
$otherShapes = [ordered]@{ schemaVersion = 1; protocol = 7
    request = [ordered]@{ version = "ver"; id = "n"; name = "ask"; arguments = "with" }
    reply = [ordered]@{ version = "ver"; id = "re"; ok = "fine"; value = "got"; reason = "why" }
    event = [ordered]@{ version = "ver"; name = "happened"; value = "got" } }
$otherShapesPath = Join-Path $work "bridge-messages.json"
[System.IO.File]::WriteAllText($otherShapesPath, (ConvertTo-Json -InputObject $otherShapes -Depth 5))
$echo = [pscustomobject]@{ bridge = $null; heard = (New-Object System.Collections.ArrayList); phase = "talk"; timedOut = ""; limitMs = 30000; clock = [System.Diagnostics.Stopwatch]::StartNew(); inForce = ""; errorsSeen = @()
    burst = 10000; burstAtMs = 0; refusedBeforeBurst = 0; refusedByBurst = -1; floods = -1; lastTickMs = 0; longestGapMs = 0; answeredAfterMs = -1 }
$echo.bridge = New-HordeSurfaceBridge -Events @("poke", "burst") -Requests ([ordered]@{
    "echo" = @{ args = @{ text = @{ type = "string"; most = 600 } }; run = { param($Arguments, $State, $Window) [void]$State.heard.Add($Arguments["text"]); return ("heard " + $Arguments["text"]) } }
    "done" = @{ run = { param($Arguments, $State, $Window) $State.phase = "push"; return $true } }
})
function Step-Echo {
    param($Window, $State)
    if ($State.clock.ElapsedMilliseconds -gt $State.limitMs) { $State.timedOut = $State.phase; & $Window.close; return }
    if ($State.phase -ceq "push") {
        $shapesNow = Get-HordeSurfaceMessages
        $State.inForce = "protocol " + $shapesNow.protocol + ", a request's id is '" + $shapesNow.request.id + "'"
        & $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "poke" -Value "again")
        $State.phase = "pushed"
    }
    elseif ($State.phase -ceq "pushed" -and @($State.heard) -ccontains "pushed again") {
        # THE BURST (review of 2026-10-06, finding A8): the page is told to post ten thousand messages
        # at once behind the bridge's back, and to ask one honest request a second and a half later.
        $State.refusedBeforeBurst = [int]$State.bridge.refused
        $State.burstAtMs = $State.clock.ElapsedMilliseconds
        $State.lastTickMs = $State.burstAtMs
        & $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "burst" -Value $State.burst)
        $State.phase = "burst"
    }
    elseif ($State.phase -ceq "burst") {
        # How long the window's own thread was held is the longest wait between two of its ticks.
        $nowMs = $State.clock.ElapsedMilliseconds
        if (($nowMs - $State.lastTickMs) -gt $State.longestGapMs) { $State.longestGapMs = $nowMs - $State.lastTickMs }
        $State.lastTickMs = $nowMs
        if (@($State.heard) -ccontains "after the burst") {
            $State.answeredAfterMs = $nowMs - $State.burstAtMs
            $State.refusedByBurst = [int]$State.bridge.refused - $State.refusedBeforeBurst
            $State.floods = @($State.bridge.refusals | Where-Object { $_.reason -like "*is not listened to for the next second*" }).Count
            $State.errorsSeen = @($Window.errors)
            & $Window.close
        }
    }
}
# THIS WINDOW ALSO OPENS ON A HOME THAT HAS A SETTINGS FILE, written now. First with a fault in it, a
# name the module never declared beside a good pace: the file is refused, so no spec is made and no
# window opens on the defaults (surfaces/Port.ps1, THE SETTINGS). Then with the fault taken out.
New-Item -ItemType Directory -Path (Join-Path $env:HORDE_HOME "settings") -Force | Out-Null
$settingsFile = (Get-HordeSurfaceSettings).path
[System.IO.File]::WriteAllText($settingsFile, '{ "schemaVersion": 1, "settings": { "colour": "red", "tickMs": 60 } }')
$refusedSpec = "<a spec was made>"
try { $null = New-HordeSurfaceSpec -Title "surface echo" -Mounts ([ordered]@{ probe = (Join-Path $pages "probe") }) -Start "probe/echo.html" -Bridge $echo.bridge -DataFolder (Join-Path $work "data-refused") -Hidden -Width 320 -Height 200 } catch { $refusedSpec = "$($_.Exception.Message)" }
Check ($refusedSpec -ceq ("the settings file '" + $settingsFile + "' of surface is refused: it has the key 'colour', which is no setting of surface") -and -not (Test-Path -LiteralPath (Join-Path $work "data-refused"))) ("asked to show a page while the person's settings file has a fault, the surface makes no spec and so opens no window, and says which file and which key (" + $refusedSpec + ")")
[System.IO.File]::WriteAllText($settingsFile, '{ "schemaVersion": 1, "settings": { "tickMs": 60 } }')
$echoSpec = New-HordeSurfaceSpec -Title "surface echo" -Mounts ([ordered]@{ probe = (Join-Path $pages "probe") }) -Start "probe/echo.html" -Bridge $echo.bridge -DataFolder (Join-Path $work "data-echo") `
    -Hidden -Width 320 -Height 200 -State $echo -OnTick { param($Window, $State) Step-Echo -Window $Window -State $State }
$shippedShapes = $script:HordeSurfaceMessages
$shapesPath = $otherShapesPath
# The suite's own answer to "where is the definition", for this one window (a suite may replace a
# function in its own process: test/test-identity.ps1 does the same).
function Get-HordeSurfaceMessagesPath { return $shapesPath }
try {
    $script:HordeSurfaceMessages = Read-HordeSurfaceMessages -Path $otherShapesPath
    $echo.clock.Restart()
    $echoShown = Open-HordeSurface -Surface $surface -Spec $echoSpec
} finally { $script:HordeSurfaceMessages = $shippedShapes; $shapesPath = Join-Path $root "surfaces\bridge-messages.json" }
Check ($echo.inForce -ceq "protocol 7, a request's id is 'n'" -and (Get-HordeSurfaceMessages).protocol -eq 1) ("CONTROL: while that window stood, the other definition was the one in force (" + $echo.inForce + "), and the shipped one is back")
Check ($echoShown.state -ceq "closed" -and $echo.timedOut -ceq "") ("a second window opens in the same process after the first has closed, and the page finished talking (" + $echoShown.state + " " + $echoShown.reason + "; stopped in '" + $echo.timedOut + "')")
Check (@($echo.heard).Count -eq 4 -and $echo.heard[0] -ceq "hello") ("a request crosses in the other vocabulary (" + (@($echo.heard) -join " || ") + ")")
Check (@($echo.heard).Count -eq 4 -and $echo.heard[1] -like "heard hello | rejected: refused: *not on the list*") "so does the answer, and so does a refusal with its reason"
Check (@($echo.heard).Count -eq 4 -and $echo.heard[2] -ceq "pushed again") "and an event pushed to the page"
Check ($echo.bridge.answered -eq 5 -and $echo.refusedBeforeBurst -eq 1) ("nothing else was refused before the burst: " + $echo.bridge.answered + " answered in all, " + $echo.refusedBeforeBurst + " refused then")

Write-Host ""
Write-Host "--- a burst of messages does not hold the window ---" -ForegroundColor Cyan
Check (@($echo.heard).Count -eq 4 -and $echo.heard[3] -ceq "after the burst") ("after " + $echo.burst + " messages posted at once, a request the page sends a second and a half later is answered, " + $echo.answeredAfterMs + " ms after the burst began")
Check ($echo.floods -eq 1 -and $echo.refusedByBurst -ge 2 -and $echo.refusedByBurst -le 101) ("of the " + $echo.burst + " messages no more than a second's worth was read - each of those refused for what it was - and the rest is one record of a flood: " + $echo.refusedByBurst + " refusals in all, " + $echo.floods + " of them the flood")
Check ($echo.longestGapMs -gt 0 -and $echo.longestGapMs -lt 1500) ("the window's own thread was never held long: the longest wait between two of its ticks through the burst was " + $echo.longestGapMs + " ms (measured 2026-10-07 on a slowed machine: 11535 to 14127 ms when every message was read, 3502 ms when each was handed over and dropped unread, about 230 ms now that a flood is not listened to)")
Check ($echoSpec.tickMs -eq 60 -and @($echo.errorsSeen).Count -eq 0) ("that window took its pace from the person's settings file, and had no error to tell its caller (" + (@($echo.errorsSeen) -join " | ") + ")")

Write-Host ""
Write-Host "--- a window that stands free appears without taking the keyboard ---" -ForegroundColor Cyan
# THE ONE WINDOW HERE THAT IS NOT HIDDEN: it stands free, as a caller's own window does, so it has a
# place in the taskbar for the second or so it lives. It is PUT where no screen is by its caller, and
# it asks for no keyboard, so it must not take it (review of 2026-10-06, finding D6). Nothing here
# asks for the keyboard: that would take it from whoever is at the machine.
$free = [pscustomobject]@{ clock = [System.Diagnostics.Stopwatch]::StartNew(); limitMs = 20000; timedOut = ""; ticks = 0; atOpen = $null; later = $null; inTaskbar = $null; visible = $null; left = $null }
$freeBridge = New-HordeSurfaceBridge -Events @("poke", "burst") -Requests ([ordered]@{
    "echo" = @{ args = @{ text = @{ type = "string"; most = 600 } }; run = { param($Arguments, $State, $Window) return "heard" } }
    "done" = @{ run = { param($Arguments, $State, $Window) return $true } }
})
function Step-Free {
    param($Window, $State)
    $State.ticks = $State.ticks + 1
    if ($State.clock.ElapsedMilliseconds -gt $State.limitMs) { $State.timedOut = "waiting"; & $Window.close; return }
    if ($State.ticks -eq 8) {
        $handle = [IntPtr][long]$Window.handle
        $rect = New-Object HordeSurfaceProbe.Native+RECT
        [void][HordeSurfaceProbe.Native]::GetWindowRect($handle, [ref]$rect)
        $State.later = ([HordeSurfaceProbe.Native]::GetForegroundWindow() -eq $handle)
        $State.inTaskbar = (([HordeSurfaceProbe.Native]::GetWindowLongPtr($handle, -20).ToInt64() -band 0x40000) -ne 0)
        $State.visible = [HordeSurfaceProbe.Native]::IsWindowVisible($handle)
        $State.left = $rect.Left
        & $Window.close
    }
}
$freeSpec = New-HordeSurfaceSpec -Title "surface probe, standing free" -Mounts ([ordered]@{ probe = (Join-Path $pages "probe") }) -Start "probe/echo.html" -Bridge $freeBridge -DataFolder (Join-Path $work "data-free") `
    -Left -32000 -Top -32000 -Width 320 -Height 200 -TickMs 50 -State $free `
    -OnOpened { param($Window, $State) $State.atOpen = ([HordeSurfaceProbe.Native]::GetForegroundWindow() -eq [IntPtr][long]$Window.handle) } `
    -OnTick { param($Window, $State) Step-Free -Window $Window -State $State }
Check ($freeSpec.hidden -eq $false -and $freeSpec.companion -eq $false -and $freeSpec.takeKeyboard -eq $false) "CONTROL: the spec is a plain window's: not hidden, nobody's companion, and it asks for no keyboard"
$free.clock.Restart()
$freeShown = Open-HordeSurface -Surface $surface -Spec $freeSpec
Check ($freeShown.state -ceq "closed" -and $free.timedOut -ceq "" -and $free.visible -eq $true -and $free.left -eq -32000) ("it opened, was shown where its caller put it, and closed (" + $freeShown.state + " " + $freeShown.reason + ")")
Check ($free.inTaskbar -eq $true) "it stands free, so it has its place in the taskbar"
Check ($free.atOpen -eq $false -and $free.later -eq $false) "and it did not take the keyboard, when its engine came up or eight ticks later"

Write-Host ""
Write-Host "--- real keys for a check: made by the engine, for this page alone ---" -ForegroundColor Cyan
# A FOURTH WINDOW, HIDDEN, OPENED WITH probeInput (surfaces/webview2/Surface.ps1, REAL KEYS FOR A
# CHECK). The page (pages/probe/keys.html) focuses its one field, makes one key press of its own by
# script, and counts every key press it sees by whether the engine vouches for it. The suite tells
# the page it has the keyboard, types and presses keys, waits until the engine has taken them all,
# and asks the page what it saw. Nothing here asks Windows for the keyboard: the desktop's
# foreground window is read before and after, and must not change.
$keys = [pscustomobject]@{ clock = [System.Diagnostics.Stopwatch]::StartNew(); limitMs = 30000; timedOut = ""; phase = "wait"; ready = $false; seen = $null
    hasInput = $null; handed = $null; refusedStep = $null; errorsSeen = @(); foregroundBefore = [long][HordeSurfaceProbe.Native]::GetForegroundWindow(); foregroundAfter = 0; handle = 0 }
$keysBridge = New-HordeSurfaceBridge -Events @("report") -Requests ([ordered]@{
    "ready" = @{ run = { param($Arguments, $State, $Window) $State.ready = $true; return $true } }
    "seen"  = @{ args = @{ trusted = @{ type = "integer" }; untrusted = @{ type = "integer" }; pressed = @{ type = "string"; most = 400 }; value = @{ type = "string"; most = 200 }; focused = @{ type = "boolean" } }
                 run = { param($Arguments, $State, $Window) $State.seen = [pscustomobject]@{ trusted = [int]$Arguments["trusted"]; untrusted = [int]$Arguments["untrusted"]; keys = $Arguments["pressed"]; value = $Arguments["value"]; focused = [bool]$Arguments["focused"] }; return $true } }
})
function Step-Keys {
    param($Window, $State)
    if ($State.clock.ElapsedMilliseconds -gt $State.limitMs) { $State.timedOut = $State.phase; & $Window.close; return }
    if ($State.phase -ceq "wait" -and $State.ready) {
        $State.handle = [long]$Window.handle
        $State.hasInput = ($null -ne $Window.PSObject.Properties["input"] -and $null -ne $Window.PSObject.Properties["inputIdle"])
        # One ask that cannot be acted out first: refused whole, so none of its keys reach the page.
        $State.refusedStep = (& $Window.input @([pscustomobject]@{ key = "a" }, [pscustomobject]@{ key = "NoSuchKey" }))
        $State.handed = (& $Window.input @([pscustomobject]@{ focus = $true }, [pscustomobject]@{ text = "hi" }, [pscustomobject]@{ key = "Enter" }, [pscustomobject]@{ key = "ArrowUp" }, [pscustomobject]@{ key = "x" }, [pscustomobject]@{ key = "ArrowDown" }, [pscustomobject]@{ key = "b"; shift = $true }))
        $State.phase = "typing"
    }
    elseif ($State.phase -ceq "typing" -and (& $Window.inputIdle)) {
        & $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "report" -Value $true)
        $State.phase = "asked"
    }
    elseif ($State.phase -ceq "asked" -and $null -ne $State.seen) {
        $State.foregroundAfter = [long][HordeSurfaceProbe.Native]::GetForegroundWindow()
        $State.errorsSeen = @($Window.errors)
        & $Window.close
    }
}
Add-Member -InputObject $keys -NotePropertyName bridge -NotePropertyValue $keysBridge
$keysSpec = New-HordeSurfaceSpec -Title "surface keys" -Mounts ([ordered]@{ probe = (Join-Path $pages "probe") }) -Start "probe/keys.html" -Bridge $keysBridge -DataFolder (Join-Path $work "data-keys") `
    -Hidden -ProbeInput -Width 320 -Height 200 -TickMs 50 -State $keys -OnTick { param($Window, $State) Step-Keys -Window $Window -State $State }
Check ($keysSpec.probeInput -eq $true -and $freeSpec.probeInput -eq $false) "CONTROL: this spec asks for input for a check; the free window's did not"
$keys.clock.Restart()
$keysShown = Open-HordeSurface -Surface $surface -Spec $keysSpec
$seen = $keys.seen
Check ($keysShown.state -ceq "closed" -and $keys.timedOut -ceq "" -and $null -ne $seen) ("it opened, the page was typed into and reported, and it closed (" + $keysShown.state + " " + $keysShown.reason + "; stopped in '" + $keys.timedOut + "')")
Check ($keys.hasInput -eq $true -and $keys.handed -eq $true) "the window opened for a check has input and inputIdle, and the keys were handed over"
Check ($null -ne $seen -and $seen.untrusted -eq 1) ("CONTROL: the one key press the page made by script is counted as not trusted (" + $(if ($null -ne $seen) { $seen.untrusted } else { "?" }) + ")")
Check ($null -ne $seen -and $seen.trusted -eq 8 -and $seen.keys -ceq "h,i,Enter,ArrowUp,x,ArrowDown,Shift,B") ("every key handed over reached the page as a key press the engine vouches for, in order - Shift held for the capital is a key press of its own, as on a keyboard - and the ask that was refused sent none (" + $(if ($null -ne $seen) { "" + $seen.trusted + ": " + $seen.keys } else { "nothing seen" }) + ")")
Check ($null -ne $seen -and $seen.value -ceq "xhi`nB") ("and they did what a real key does: the letters typed, Enter added a line, the caret went up a line and down again (the field holds '" + $(if ($null -ne $seen) { $seen.value -replace "`n", "\n" } else { "?" }) + "')")
Check ($null -ne $seen -and $seen.focused -eq $true) "the page was told it has the keyboard, and its field has it"
Check ($keys.refusedStep -eq $false -and @($keys.errorsSeen).Count -eq 1 -and @($keys.errorsSeen)[0] -like "*no way to press*") ("an ask with a key the surface cannot press was refused whole and recorded, and nothing else went wrong (" + (@($keys.errorsSeen) -join " | ") + ")")
Check ($keys.foregroundAfter -eq $keys.foregroundBefore -and $keys.foregroundAfter -ne $keys.handle) "and the desktop's foreground window is the one it was before: no window was activated and nobody's keyboard was taken"

} finally {
    if ($null -ne (Get-Variable -Name listener -ErrorAction SilentlyContinue) -and $null -ne $listener) { try { $listener.Stop() } catch { } }
    if ((Split-Path -Leaf $work) -match '\Ahorde-webview2-window-[0-9a-f]{32}\z') {
        # The engine lets go of its profile folder a moment after its last process has gone.
        foreach ($try in 1..20) { if (-not (Test-Path -LiteralPath $work)) { break }; try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 250 } }
    }
}

Complete-HordeSuite -Success "in a real window, the surface does each thing its capabilities say yes to, and each lock is the engine's to call"
