# DOES THE WINDOW SURFACE REFUSE WHAT IT MUST, BEFORE ANY WINDOW EXISTS?
#
# Everything here runs with no window and no web engine: the pinned files and what happens when one
# byte of one changes, the rule for which address the page may be at, where a message may come from,
# what a machine without the engine is told, and the Windows PowerShell 5.1 trap about event handlers
# that this adapter is written around. The window itself - a real one, opened where nobody sees it,
# on a page of this adapter's own - is surfaces/webview2/test/test-webview2-window.ps1's.
#
# NOTHING OF THE ENGINE IS LOADED INTO THIS PROCESS by the refusals: each damaged folder is refused
# and the suite then looks for the engine's interface among the loaded assemblies. The one case that
# does load it is last, and says so.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "surfaces\Port.ps1")
. (Join-Path $root "surfaces\webview2\Surface.ps1")

$adapter = Join-Path $root "surfaces\webview2"
$lib = Join-Path $adapter "lib"
$work = Join-Path $env:TEMP ("horde-webview2-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
function Test-EngineLoaded { return (@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -like "Microsoft.Web.WebView2*" }).Count -gt 0) }
function Copy-Lib { param([string]$Name) $d = Join-Path $work $Name; Copy-Item -LiteralPath $lib -Destination $d -Recurse; return $d }

try {

Write-Host ""
Write-Host "--- the adapter says what it is ---" -ForegroundColor Cyan
$me = Resolve-HordeSurface -Requires @("page.local", "page.locked", "requests.closed", "push", "window.native", "picture")
Check ($null -ne $me -and $me.name -ceq "webview2" -and $me.folder -ceq $adapter) "it registers under its folder's name, and has every capability a caller can ask for"
Check ((Get-HordeSurfaceNames) -join "," -ceq "webview2") "CONTROL: it is the only surface loaded here"

Write-Host ""
Write-Host "--- the three pinned files, and Microsoft's licence beside them ---" -ForegroundColor Cyan
$real = Test-HordeWebView2Libraries
Check ($real.ok -eq $true -and @($real.files).Count -eq 3) "the three files in lib/ match lib/fingerprints.txt"
Check ((@($real.files | ForEach-Object { Split-Path -Leaf $_ }) -join ",") -ceq "Microsoft.Web.WebView2.Core.dll,Microsoft.Web.WebView2.WinForms.dll,WebView2Loader.dll") "and they are the interface, the control and the loader, in the order they are loaded"
$pins = @{}; foreach ($e in (Read-HordeFingerprintList -Path (Join-Path $lib "fingerprints.txt")).entries) { $pins[$e.name] = $e.sha256 }
Check ($pins["Microsoft.Web.WebView2.Core.dll"] -ceq "d60e6e94245078cb56e44ebd5f360dc04bf18e460136be93bfc4cfca43b98505" -and $pins["Microsoft.Web.WebView2.WinForms.dll"] -ceq "6a9e6856f23c463783c3afb0ca5d78f56324c86657162ccb16d5227b3233b32a" -and $pins["WebView2Loader.dll"] -ceq "3426dcc55fdfb8b5e7ac623cf33b4ccf283fbf68a0c5a65bddfdb4d749a8abee") "the fingerprints are those of package version 1.0.4258.31, as the design names them"
$licence = [System.IO.File]::ReadAllText((Join-Path $lib "LICENSE.txt"))
Check ($licence.Contains("Copyright (C) Microsoft Corporation") -and $licence.Contains("Redistributions in binary form must reproduce the above") -and $licence.Contains("The name of Microsoft Corporation")) "Microsoft's licence text is beside the files it covers (CONTRIBUTING 10)"

Write-Host ""
Write-Host "--- a changed byte refuses to load ---" -ForegroundColor Cyan
$spec = $null
$pageDir = Join-Path $work "page"; New-Item -ItemType Directory -Path $pageDir | Out-Null
[System.IO.File]::WriteAllText((Join-Path $pageDir "index.html"), "<!doctype html><title>x</title>")
$bridge = New-HordeSurfaceBridge -Requests ([ordered]@{ "list" = @{ run = { return 1 } } })
$spec = New-HordeSurfaceSpec -Title "never shown" -Mounts ([ordered]@{ shell = $pageDir }) -Start "shell/index.html" -Bridge $bridge -DataFolder (Join-Path $work "data") -Hidden
foreach ($name in @("Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.WinForms.dll", "WebView2Loader.dll")) {
    $dir = Copy-Lib ("changed-" + $name)
    $path = Join-Path $dir $name
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $at = [int]($bytes.Length / 2)
    $bytes[$at] = [byte](($bytes[$at] + 1) % 256)
    [System.IO.File]::WriteAllBytes($path, $bytes)
    $check = Test-HordeWebView2Libraries -Folder $dir
    Check ($check.ok -eq $false -and $check.reason -like ("*" + $name + " does not match its fingerprint*") -and @($check.files).Count -eq 0) ("one changed byte in " + $name + ": the folder is refused whole, and the file is named")
    $opened = Open-HordeWebView2Surface -Spec $spec -LibFolder $dir
    Check ($opened.state -ceq "failed" -and $opened.reason -like "*are not the ones this version of Horde pins, so none was loaded*") ("and opening a window on that folder fails, in words (" + $name + ")")
}
$short = Copy-Lib "unpinned"
$listText = [System.IO.File]::ReadAllText((Join-Path $short "fingerprints.txt"))
[System.IO.File]::WriteAllText((Join-Path $short "fingerprints.txt"), (@($listText -split "`n" | Where-Object { $_ -notlike "WebView2Loader.dll*" }) -join "`n"))
$unpinned = Test-HordeWebView2Libraries -Folder $short
Check ($unpinned.ok -eq $false -and $unpinned.reason -like "*WebView2Loader.dll is not pinned by the list*") "a list that no longer pins one of the three refuses all three: the unpinned one could be anything"
$gone = Copy-Lib "gone"; Remove-Item -LiteralPath (Join-Path $gone "Microsoft.Web.WebView2.WinForms.dll")
Check ((Test-HordeWebView2Libraries -Folder $gone).ok -eq $false) "a missing file refuses the folder"
Check ((Open-HordeWebView2Surface -Spec $spec -LibFolder (Join-Path $work "no-such-folder")).state -ceq "failed") "and so does a folder with no list at all"
Check ((Test-EngineLoaded) -eq $false) "after every one of those refusals, nothing of the engine's interface is loaded in this process"

Write-Host ""
Write-Host "--- the page may be at a file of its own mount, and nowhere else ---" -ForegroundColor Cyan
$at = $script:HordeWebView2Origin
Check ($at -cmatch '\Ahttps://[a-z.]+\.invalid\z') ("CONTROL: the one origin this adapter serves under is a name that can never be a machine (" + $at + ")")
foreach ($ok in @(($at + "/shell/index.html"), ($at + "/shell/img/dot.png"), ($at + "/shell/index.html?x=1#top"))) {
    Check ((Test-HordeWebView2Address -Uri $ok -StartMount "shell") -eq $true) ("CONTROL: " + $ok + " is a place the page may be")
}
$elsewhere = @(
    "https://example.com/", "https://example.com/shell/index.html", (($at -replace '\Ahttps', 'http') + "/shell/index.html"), ($at + ".example.com/shell/index.html"), ($at + "@example.com/shell/index.html"),
    (($at -replace '://', '://user@') + "/shell/index.html"), ($at + ":8443/shell/index.html"), (($at -replace '://', '://x') + "/shell/index.html"), (($at -replace '://', '://shell.') + "/index.html"),
    "file:///C:/Windows/win.ini", "data:text/html,<script>1</script>", "javascript:alert(1)", "about:blank", "ms-settings:", "horde.invalid/shell/index.html", "", "   ")
foreach ($no in $elsewhere) {
    Check ((Test-HordeWebView2Address -Uri $no -StartMount "shell") -eq $false -and $null -eq (Get-HordeWebView2PagePath -Uri $no)) ("'" + $no + "' is not this adapter's address at all")
}
foreach ($no in @(($at + "/"), ($at + "/shell"), ($at + "/other/other.js"), ($at + "/shellx/index.html"), ($at + "/SHELL/index.html"), ($at + "/surface/bridge.js"))) {
    Check ((Test-HordeWebView2Address -Uri $no -StartMount "shell") -eq $false -and $null -ne (Get-HordeWebView2PagePath -Uri $no)) ("'" + $no + "' is this adapter's address but not a file of the page's own mount: the page may not go there")
}
Check ((Get-HordeWebView2PagePath -Uri ($at + "/shell/a%2e%2e/..%2fx.js?q=1#f")) -ceq "/shell/a%2e%2e/..%2fx.js") "the path is handed on exactly as it was written, escapes and all, cut at the question mark: the port decides what it names"
Check ((Get-HordeWebView2PagePath -Uri $at) -ceq "/") "an address with no path is the root"
$dotted = $at + "/other/../shell/index.html"
Check ((Get-HordeWebView2PagePath -Uri $dotted) -ceq "/other/../shell/index.html" -and (Test-HordeWebView2Address -Uri $dotted -StartMount "shell") -eq $false -and (Get-HordeWebView2ResourceAnswer -Uri $dotted -Kind "Document" -Mounts ([ordered]@{ shell = $pageDir })).status -eq 403) "a path with a dot-dot step is not tidied into the file it would reach: it is handed on as written, and refused"

Write-Host ""
Write-Host "--- every load is answered here: a file of a mount, or a refusal ---" -ForegroundColor Cyan
$treeDir = Join-Path $work "served"; $otherDir = Join-Path $treeDir "other"; New-Item -ItemType Directory -Path $otherDir -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $otherDir "data.json"), '{"n":1}')
$servedMounts = [ordered]@{ shell = $pageDir; other = $otherDir; surface = (Get-HordeSurfaceOwnFiles -BridgeScript (Join-Path $adapter "page\bridge.js")) }
function Answer { param([string]$Uri, [string]$Kind = "Script") return (Get-HordeWebView2ResourceAnswer -Uri $Uri -Kind $Kind -Mounts $servedMounts) }
$page = Answer ($at + "/shell/index.html") "Document"
Check ($page.status -eq 200 -and $page.file -ceq (Join-Path $pageDir "index.html") -and $page.type -ceq "text/html; charset=utf-8" -and $page.refusal -ceq "") "CONTROL: the start page is answered with its file and its type"
$otherFile = Answer ($at + "/other/data.json?v=2") "XmlHttpRequest"
Check ($otherFile.status -eq 200 -and $otherFile.file -ceq (Join-Path $otherDir "data.json") -and $otherFile.type -ceq "application/json; charset=utf-8") "a file of another mount is answered the same way: a page may use it"
$ownBridge = Answer ($at + "/surface/bridge.js")
$ownShapes = Answer ($at + "/surface/bridge-messages.json") "Fetch"
Check ($ownBridge.status -eq 200 -and $ownBridge.file -ceq (Join-Path $adapter "page\bridge.js") -and $ownShapes.status -eq 200 -and $ownShapes.file -ceq (Get-HordeSurfaceMessagesPath)) "the surface's own mount answers with this adapter's bridge script and the port's definition of the messages"
foreach ($out in @("https://example.com/lib.js", "http://127.0.0.1:8080/x.js", ($at + ".example.com/shell/index.html"), "https://cdn.example.com/shell/index.html", "file:///C:/Windows/win.ini", "ftp://example.com/x", "")) {
    $refusedLoad = Answer $out "Script"
    Check ($refusedLoad.status -eq 403 -and $refusedLoad.file -ceq "" -and $refusedLoad.refusal -like "*not one of its own files (the engine's word for the load: Script), and nothing was fetched") ("a load from '" + $out + "' is refused, with the kind of load in the record")
    Check ($out -eq "" -or (-not $refusedLoad.refusal.Contains($out) -and $refusedLoad.refusal -notlike "*example*" -and $refusedLoad.refusal -notlike "*127.0.0.1*")) "and the record does not repeat the address"
}
Check ((Answer "https://example.com/x" "<img src=x onerror=alert(1)>").refusal -like "*the load: something)*" -and (Answer "https://example.com/x" "").refusal -like "*the load: something)*") "a kind that is not one plain word is never put in the record"
foreach ($inside in @(
    @{ uri = ($at + "/shell/missing.js"); says = "a file that is not there, and nothing was served" }
    @{ uri = ($at + "/shell/../secret.txt"); says = "not a file of a mount, and nothing was served" }
    @{ uri = ($at + "/shell/..%2fsecret.txt"); says = "not a file of a mount, and nothing was served" }
    @{ uri = ($at + "/nowhere/index.html"); says = "a mount that was not given, and nothing was served" }
    @{ uri = ($at + "/surface/Surface.ps1"); says = "not a kind of file a page is made of, and nothing was served" }
    @{ uri = ($at + "/"); says = "not a file of a mount, and nothing was served" }
)) {
    $refusedLoad = Answer $inside.uri
    Check ($refusedLoad.status -eq 403 -and $refusedLoad.file -ceq "" -and $refusedLoad.refusal -like ("*" + $inside.says)) ("'" + $inside.uri + "' is this adapter's address and names no file: refused, in the port's words")
}
$icon = Answer ($at + "/favicon.ico") "Other"
Check ($icon.status -eq 404 -and $icon.file -ceq "" -and $icon.refusal -ceq "") "the icon the engine asks for by itself is answered 'not there' and is not held against the page"

Write-Host ""
Write-Host "--- a message is read only when it comes from the page ---" -ForegroundColor Cyan
$script:asked = 0
$liveBridge = New-HordeSurfaceBridge -Requests ([ordered]@{ "list" = @{ run = { param($Arguments, $State, $Window) $script:asked++; return ("for " + $State.who) } } })
$liveSpec = New-HordeSurfaceSpec -Title "never shown" -Mounts ([ordered]@{ shell = $pageDir }) -Start "shell/index.html" -Bridge $liveBridge -DataFolder (Join-Path $work "data") -State ([pscustomobject]@{ who = "the caller" })
# The state a window would hold, with no window: only the members the message path reads.
$script:made = New-Object System.Collections.ArrayList
$fakeEnvironment = [pscustomobject]@{ }
$fakeEnvironment | Add-Member -MemberType ScriptMethod -Name CreateWebResourceResponse -Value {
    param($Body, $Status, $Phrase, $Headers)
    $text = $null
    if ($null -ne $Body) { $text = [System.Text.Encoding]::UTF8.GetString($Body.ToArray()) }
    $made = [pscustomobject]@{ body = $text; status = $Status; phrase = $Phrase; headers = $Headers }
    [void]$script:made.Add($made)
    return $made
}
$fakeView = [pscustomobject]@{ CoreWebView2 = [pscustomobject]@{ Environment = $fakeEnvironment } }
$script:HordeWebView2 = [pscustomobject]@{ spec = $liveSpec; mounts = $servedMounts; window = $null; opened = $false; view = $fakeView; failure = ""; errors = (New-Object System.Collections.ArrayList) }
$fromPage = Receive-HordeWebView2Message -Json '{"v":1,"id":3,"request":"list"}' -Source ($at + "/shell/index.html")
Check (($fromPage | ConvertFrom-Json).value -ceq "for the caller" -and $script:asked -eq 1) "a message from the page's own address reaches the bridge, with the caller's state"
$fromElsewhere = Receive-HordeWebView2Message -Json '{"v":1,"id":4,"request":"list"}' -Source "https://example.com/shell/index.html"
Check ($fromElsewhere -ceq "" -and $script:asked -eq 1 -and $liveBridge.refused -eq 1 -and $liveBridge.refusals[0].reason -like "*not the page's own, and was not read") "the same message from another address is not read, not answered, and recorded as a refusal"
$fromNowhere = Receive-HordeWebView2Message -Json '{"v":1,"id":5,"request":"list"}' -Source ""
Check ($fromNowhere -ceq "" -and $script:asked -eq 1 -and $liveBridge.refused -eq 2) "and so is one that says nothing of where it came from"
$fromOtherMount = Receive-HordeWebView2Message -Json '{"v":1,"id":5,"request":"list"}' -Source ($at + "/other/data.json")
Check ($fromOtherMount -ceq "" -and $script:asked -eq 1 -and $liveBridge.refused -eq 3) "and one from a file of another mount: only the page's own mount speaks"
$unknown = Receive-HordeWebView2Message -Json '{"v":1,"id":6,"request":"open-file"}' -Source ($at + "/shell/index.html")
Check (($unknown | ConvertFrom-Json).ok -eq $false -and $liveBridge.refused -eq 4) "a request off the list, from the page itself, is refused by the bridge and recorded"

Write-Host ""
Write-Host "--- an event handler does not keep the variables of the function that wrote it ---" -ForegroundColor Cyan
# THE TRAP, measured here each run. A script block handed to a .NET event runs later, when the function
# that wrote it has returned. Written the obvious way it reads that function's local variable and
# finds nothing.
function New-NaiveHandler { $bridgeOfThisFunction = $liveBridge; return { return ($null -ne $bridgeOfThisFunction) } }
$naive = New-NaiveHandler
Check ((& $naive) -eq $false) "CONTROL: a handler that reads a local of the function that made it finds nothing once that function has returned"
# THE ADAPTER'S HANDLERS are made by a function that has returned, and still find their window: they
# read the one state object in the script scope.
$handlers = Get-HordeWebView2Handlers
Check (@($handlers.Keys | Sort-Object) -join "," -ceq "closed,download,frame,initialized,message,navigation,newWindow,resource,shown,tick") "the adapter hands .NET ten handlers"
$nav = [pscustomobject]@{ Uri = "https://example.com/"; Cancel = $false }
& $handlers.navigation $null $nav
Check ($nav.Cancel -eq $true -and $liveBridge.refused -eq 5 -and $liveBridge.refusals[4].reason -like "*an address that is not its own*") "its navigation handler, called after the function that made it returned, cancels a navigation elsewhere and records it"
$stay = [pscustomobject]@{ Uri = ($at + "/shell/index.html"); Cancel = $false }
& $handlers.navigation $null $stay
Check ($stay.Cancel -eq $false -and $liveBridge.refused -eq 5) "CONTROL: and leaves a navigation to a file of the page's own mount alone"
$toOther = [pscustomobject]@{ Uri = ($at + "/other/data.json"); Cancel = $false }
& $handlers.navigation $null $toOther
Check ($toOther.Cancel -eq $true -and $liveBridge.refused -eq 6) "a navigation to a file of another mount is cancelled and recorded: the page may use it, not go to it"
$frame = [pscustomobject]@{ Uri = ($at + "/shell/inner.html"); Cancel = $false }
& $handlers.frame $null $frame
Check ($frame.Cancel -eq $true -and $liveBridge.refused -eq 7) "every frame is refused, even one at the page's own address"
$pop = [pscustomobject]@{ Uri = ($at + "/shell/index.html"); Handled = $false }
& $handlers.newWindow $null $pop
Check ($pop.Handled -eq $true -and $liveBridge.refused -eq 8) "a request for a new window is marked handled, so nothing opens, and recorded"
# THE LOAD HANDLER, with an engine stood in for by an object that only records what it is asked to
# answer with. The real engine is surfaces/webview2/test/test-webview2-window.ps1's.
$script:made.Clear()
$load = [pscustomobject]@{ Request = [pscustomobject]@{ Uri = ($at + "/shell/index.html") }; ResourceContext = "Document"; Response = $null }
& $handlers.resource $null $load
Check ($null -ne $load.Response -and $load.Response.status -eq 200 -and $load.Response.body -ceq "<!doctype html><title>x</title>" -and $liveBridge.refused -eq 8) "its load handler answers a file of a mount with that file's bytes, and records nothing"
Check ($load.Response.headers -ceq "Content-Type: text/html; charset=utf-8`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff") "with its kind's type, never kept by the engine, and never guessed at"
$leak = [pscustomobject]@{ Request = [pscustomobject]@{ Uri = "https://example.com/lib.js" }; ResourceContext = "Script"; Response = $null }
& $handlers.resource $null $leak
Check ($null -ne $leak.Response -and $leak.Response.status -eq 403 -and $null -eq $leak.Response.body -and $liveBridge.refused -eq 9 -and $liveBridge.refusals[8].reason -like "*not one of its own files*Script*nothing was fetched") "a load from outside is answered with a refusal and no bytes, and recorded like a refused navigation"
$climb = [pscustomobject]@{ Request = [pscustomobject]@{ Uri = ($at + "/shell/..%2f..%2fsecret.txt") }; ResourceContext = "Fetch"; Response = $null }
& $handlers.resource $null $climb
Check ($climb.Response.status -eq 403 -and $liveBridge.refused -eq 10 -and $liveBridge.refusals[9].reason -like "*not a file of a mount, and nothing was served") "and so is a climb out of the mounts"
$engineAsk = [pscustomobject]@{ Request = [pscustomobject]@{ Uri = ($at + "/favicon.ico") }; ResourceContext = "Other"; Response = $null }
& $handlers.resource $null $engineAsk
Check ($engineAsk.Response.status -eq 404 -and $liveBridge.refused -eq 10) "the engine's own ask for an icon is answered and not recorded"
# DEFAULT DENY WHEN THE CODE ITSELF FAILS: a file that cannot be read is still answered, with a refusal.
$lockedPath = Join-Path $otherDir "data.json"
$lock = [System.IO.File]::Open($lockedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
try {
    $unreadable = [pscustomobject]@{ Request = [pscustomobject]@{ Uri = ($at + "/other/data.json") }; ResourceContext = "Fetch"; Response = $null }
    & $handlers.resource $null $unreadable
} finally { $lock.Dispose() }
Check ($null -ne $unreadable.Response -and $unreadable.Response.status -eq 403 -and $script:HordeWebView2.errors.Count -eq 1 -and $script:HordeWebView2.errors[0] -like "a file the page asked for could not be served:*") "a file that cannot be read is answered with a refusal all the same, and the failure is kept for the caller"
$script:HordeWebView2.errors.Clear()
# A DOWNLOAD IS A FILE WRITTEN WHEREVER THE ENGINE KEEPS DOWNLOADS, outside anything of Horde's. Measured
# 2026-10-06 by the review of this adapter, in a real hidden window on a page that made a link with a
# download name and clicked it: the file appeared in the user's own Downloads folder.
$save = [pscustomobject]@{ ResultFilePath = "C:\elsewhere\saved.txt"; Cancel = $false; Handled = $false }
if ($handlers.ContainsKey("download")) { & $handlers.download $null $save }
Check ($save.Cancel -eq $true -and $liveBridge.refused -eq 11 -and $liveBridge.refusals[10].reason -like "*save a file*") "a download is cancelled, so a page writes no file anywhere, and recorded"
$script:ticked = 0
$tickSpec = New-HordeSurfaceSpec -Title "never shown" -Mounts ([ordered]@{ shell = $pageDir }) -Start "shell/index.html" -Bridge $liveBridge -DataFolder (Join-Path $work "data") -State ([pscustomobject]@{ n = 5 }) -OnTick { param($Window, $State) $script:ticked += $State.n; if ($script:ticked -ge 10) { throw "a tick that fails" } }
$script:HordeWebView2.spec = $tickSpec
& $handlers.tick; & $handlers.tick
Check ($script:ticked -eq 10 -and $script:HordeWebView2.errors.Count -eq 1 -and $script:HordeWebView2.errors[0] -ceq "a tick failed: a tick that fails") "the tick handler hands the caller its own state, and a tick that throws is recorded, not fatal"
Write-Host ""
Write-Host "--- a picture is Horde's to ask for, and only of a page that is being drawn ---" -ForegroundColor Cyan
Check ((Start-HordeWebView2Capture -Path (Join-Path $work "p.png")) -eq $false -and -not (Test-Path -LiteralPath (Join-Path $work "p.png"))) "with no engine up there is nothing to take a picture of: not asked, and no file made"
$script:HordeWebView2 = [pscustomobject]@{ spec = $liveSpec; mounts = $servedMounts; window = $null; opened = $true; view = [pscustomobject]@{ CoreWebView2 = [pscustomobject]@{ } }; failure = ""; capture = $null; pictures = 0; errors = (New-Object System.Collections.ArrayList) }
Check ((Start-HordeWebView2Capture -Path "p.png") -eq $false -and $script:HordeWebView2.errors.Count -eq 1 -and $script:HordeWebView2.errors[0] -like "*an absolute path ending .png*") "a relative path is refused and recorded: a picture is never written wherever the process happens to stand"
Check ((Start-HordeWebView2Capture -Path (Join-Path $work "p.txt")) -eq $false -and $script:HordeWebView2.errors.Count -eq 2 -and @(Get-ChildItem -LiteralPath $work -Filter "p.*").Count -eq 0) "and so is a path that is not a .png; neither left a file behind"
$script:HordeWebView2.capture = [pscustomobject]@{ task = [pscustomobject]@{ IsCompleted = $false } }
Check ((Start-HordeWebView2Capture -Path (Join-Path $work "p.png")) -eq $false -and $script:HordeWebView2.errors.Count -eq 2 -and @(Get-ChildItem -LiteralPath $work -Filter "p.*").Count -eq 0) "while one picture is being drawn a second is not taken: nothing is asked of the engine, and no file is opened"
Complete-HordeWebView2Capture
Check ($null -ne $script:HordeWebView2.capture -and $script:HordeWebView2.pictures -eq 0) "a picture the engine has not finished is left alone"
$replies = @($liveBridge.requests.Keys)
Check ($replies -cnotcontains "capture" -and (Receive-HordeWebView2Message -Json '{"v":1,"id":9,"request":"capture","args":{}}' -Source ($at + "/shell/index.html")) -like "*refused*") "and a page that asks for one is refused like any request off the list"
$script:HordeWebView2 = $null
$quiet = [pscustomobject]@{ Uri = "https://example.com/"; Cancel = $false }
& $handlers.navigation $null $quiet
Check ($quiet.Cancel -eq $false) "with no window, a handler does nothing at all rather than fail"

Write-Host ""
Write-Host "--- no object of Horde's is ever handed to the page ---" -ForegroundColor Cyan
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $adapter "Surface.ps1"), [ref]$tokens, [ref]$errs)
$calls = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Member.Value })
Check (@($errs).Count -eq 0 -and $calls -ccontains "PostWebMessageAsJson" -and $calls -ccontains "Navigate") "CONTROL: the adapter's method calls are read from its syntax tree, and the two it must make are there"
$filters = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Extent.Text -ceq "AddWebResourceRequestedFilter" }, $true) | ForEach-Object { @($_.Arguments | ForEach-Object { $_.Extent.Text }) -join " | " })
Check ($filters.Count -eq 1 -and $filters[0] -ceq '"*" | [Microsoft.Web.WebView2.Core.CoreWebView2WebResourceContext]::All' -and $calls -ccontains "add_WebResourceRequested") "the engine is told to ask this adapter about every address and every kind of load, and is handed the handler that answers"
Check ($calls -cnotcontains "SetVirtualHostNameToFolderMapping") "no folder is mapped to a host name for the engine to serve by itself: a load the adapter does not answer has nowhere to come from"
$browserArgs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$props.AdditionalBrowserArguments' }, $true) | ForEach-Object { $_.Right.Extent.Text })
Check ($browserArgs.Count -eq 1 -and $browserArgs[0] -ceq '$script:HordeWebView2NoNetwork' -and $script:HordeWebView2NoNetwork -ceq "--proxy-server=http://0.0.0.0:0 --proxy-bypass-list=<-loopback>") "the engine is started with every connection sent to an address nothing can listen at, loopback included"
Check ($calls -ccontains "add_DownloadStarting") "the handler that cancels a download is given to the engine: a handler nobody was handed cancels nothing"
Check (@($calls | Where-Object { $_ -like "AddHostObject*" -or $_ -like "*ExecuteScript*" -or $_ -ceq "NavigateToString" -or $_ -ceq "AddScriptToExecuteOnDocumentCreatedAsync" }).Count -eq 0) "it never adds a host object, never runs script it built in the page, and never shows text as a page"
$settings = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -like '$core.Settings.*' }, $true) | ForEach-Object { $_.Left.Extent.Text.Substring(15) + "=" + $_.Right.Extent.Text })
foreach ($off in @("AreDevToolsEnabled", "AreDefaultContextMenusEnabled", "AreBrowserAcceleratorKeysEnabled", "AreHostObjectsAllowed", "IsPasswordAutosaveEnabled", "IsGeneralAutofillEnabled", "IsStatusBarEnabled")) {
    Check ($settings -ccontains ($off + '=$false')) ($off + " is turned off")
}
Write-Host ""
Write-Host "--- the screen's real scale is asked of its one owner ---" -ForegroundColor Cyan
$commands = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
$adapterText = [System.IO.File]::ReadAllText((Join-Path $adapter "Surface.ps1"))
Check ($commands -ccontains "Register-HordeSurface") "CONTROL: the adapter's commands are read from its syntax tree, and the one it must call is there"
Check ($commands -ccontains "Enable-HordeWindowsRealScale" -and -not $adapterText.Contains("SetProcessDpiAwareness")) "the adapter asks platform/windows/Scale.ps1 for real pixels, and carries no call to Windows of its own for it"
Check ((Get-HordeWebView2ScaleNote -Scale ([pscustomobject]@{ state = "applied"; awareness = "per-monitor-v2"; realScale = "yes"; reason = "Windows took it" })) -ceq "") "CONTROL: a process that draws at the screen's real scale is nothing to report"
foreach ($notReal in @("no", "unknown")) {
    $note = Get-HordeWebView2ScaleNote -Scale ([pscustomobject]@{ state = "already"; awareness = "system"; realScale = $notReal; reason = "the process already had an awareness" })
    Check ($note -like "*not known to be drawn at the screen's real scale*" -and $note -like "*awareness system*" -and $note -like "*the process already had an awareness") ("real scale '" + $notReal + "' is said to the caller in words, with what the process is and why: it is decided on the real scale, never on whether the call was taken")
}

$bridgeJs = [System.IO.File]::ReadAllText((Join-Path $adapter "page\bridge.js"))
Check ($bridgeJs.Contains('fetch(new URL("' + $script:HordeSurfaceMessagesFile + '", here))') -and $bridgeJs -cnotmatch 'VERSION|protocol\s*[:=]\s*[0-9]') ("the page's side of the bridge asks for the port's definition of the messages by the name the port serves it under (" + $script:HordeSurfaceMessagesFile + "), and carries no protocol number of its own")
Check ($bridgeJs.Contains("window.HordeBridge = { request: request, on: on, live:") -and -not $bridgeJs.Contains("hostObjects") -and -not $bridgeJs.Contains("eval(") -and -not $bridgeJs.Contains("innerHTML")) "the page's side of the bridge gives a page request, on and live, and uses no host object, no eval and no markup from data"

Write-Host ""
Write-Host "--- a machine without the engine is told so ---" -ForegroundColor Cyan
Check ((Get-HordeWebView2RuntimeProblem -Version "154.0.4258.53") -ceq "") "CONTROL: an installed engine is no problem"
foreach ($none in @("", "   ", $null)) {
    $said = Get-HordeWebView2RuntimeProblem -Version $none
    Check ($said -like "*is not installed on this machine*" -and $said -like "*'WebView2 Runtime'*" -and $said -like "*Every other horde command works without it") "no engine: the reason names what to install, in plain words, and says the rest of horde still works"
}

Write-Host ""
Write-Host "--- the real files load (this is the one case that loads the engine's interface) ---" -ForegroundColor Cyan
$loaded = Import-HordeWebView2Libraries
Check ($loaded -ceq "" -and (Test-EngineLoaded) -eq $true) "CONTROL: the pinned files, unchanged, are checked and then loaded"
Check ($null -ne ("HordeSurfaceForm" -as [type]) -and (New-Object HordeSurfaceForm).Quiet -eq $false) "and with them the window type that can be shown without taking the keyboard"
$version = Get-HordeWebView2RuntimeVersion
if ($version -ne "") { Write-Host ("  the engine installed here is " + $version) -ForegroundColor DarkGray }
else { Write-Host "  [SKIP] no engine is installed on this machine, so the real-window suite beside this one cannot show a window here" -ForegroundColor Yellow }

} finally {
    $script:HordeWebView2 = $null
    if ((Split-Path -Leaf $work) -match '\Ahorde-webview2-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "the window surface loads only the files it pins, keeps the page at its own address, and reads only the page's own messages"
