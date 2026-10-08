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
# A home of this run, never made: the surface's settings are then their defaults, whatever a person
# has written in the real home's file.
$env:HORDE_HOME = Join-Path $work "home"
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
# IF A REFUSAL BELOW EVER FAILS, A REAL WINDOW OPENS. This spec closes it the moment its engine is up,
# so the check then fails in words ("closed", not "failed") instead of leaving a hidden window open
# until somebody stops the suite - which is what the first red run of the unlisted-file check did,
# 2026-10-07.
$spec = New-HordeSurfaceSpec -Title "never shown" -Mounts ([ordered]@{ shell = $pageDir }) -Start "shell/index.html" -Bridge $bridge -DataFolder (Join-Path $work "data") -Hidden -OnOpened { param($Window, $State) & $Window.close }
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
# A FILE NOBODY LISTED, BESIDE THE PINNED ONES (review of 2026-10-06, finding A7). A program library
# loaded from a folder can pull in another that was put beside it, so the folder may hold the three
# pinned files, their list, Microsoft's licence and notice, and nothing else.
Check ((@($script:HordeWebView2LibOtherFiles) -join ",") -ceq "LICENSE.txt,NOTICE.txt" -and @((Test-HordeFingerprints -Folder $lib).unlisted | Where-Object { $script:HordeWebView2LibOtherFiles -cnotcontains $_ }).Count -eq 0) "CONTROL: the shipped folder holds nothing but the pinned files, their list, the licence and the notice"
foreach ($extra in @(
    @{ name = "version.dll"; what = "a program library nobody listed"; make = { param($d) [System.IO.File]::WriteAllText((Join-Path $d "version.dll"), "planted") } }
    @{ name = "readme.txt"; what = "any other file, even plain text"; make = { param($d) [System.IO.File]::WriteAllText((Join-Path $d "readme.txt"), "hello") } }
    @{ name = "license.txt"; what = "a file whose name differs from an allowed one only in letter case"; make = { param($d) Rename-Item -LiteralPath (Join-Path $d "LICENSE.txt") -NewName "license.txt" } }
    @{ name = "plugins"; what = "a folder"; make = { param($d) New-Item -ItemType Directory -Path (Join-Path $d "plugins") | Out-Null } }
)) {
    $dir = Copy-Lib ("extra-" + $extra.name)
    & $extra.make $dir
    $check = Test-HordeWebView2Libraries -Folder $dir
    Check ($check.ok -eq $false -and @($check.files).Count -eq 0 -and $check.reason -like ("*" + $extra.name + " is in the folder and is neither pinned by the list nor one of the files that may stand beside the pinned ones (LICENSE.txt, NOTICE.txt)*")) ($extra.what + " beside the pinned files refuses the folder whole, by name")
    Check ((Open-HordeWebView2Surface -Spec $spec -LibFolder $dir).state -ceq "failed") ("and no window opens on it (" + $extra.name + ")")
}
# HELD FROM THE CHECK (finding A6): asked to hold, a folder that passes is handed back with its three
# files open, and one that fails holds nothing.
function Test-Writable { param([string]$Path) try { $w = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite); $w.Dispose(); return $true } catch { return $false } }
$heldCopy = Copy-Lib "held"
$holding = Test-HordeWebView2Libraries -Folder $heldCopy -Hold
try { Check ($holding.ok -eq $true -and @($holding.held).Count -eq 3 -and (Test-Writable (Join-Path $heldCopy "WebView2Loader.dll")) -eq $false) "asked to hold, the check hands back the three files open: none can be written to until the caller lets go" }
finally { foreach ($h in @($holding.held)) { $h.Dispose() } }
Check ((Test-Writable (Join-Path $heldCopy "WebView2Loader.dll")) -eq $true) "CONTROL: let go, the file can be written to again"
[System.IO.File]::WriteAllText((Join-Path $heldCopy "version.dll"), "planted")
$refusedHold = Test-HordeWebView2Libraries -Folder $heldCopy -Hold
Check ($refusedHold.ok -eq $false -and @($refusedHold.held).Count -eq 0 -and (Test-Writable (Join-Path $heldCopy "WebView2Loader.dll")) -eq $true) "a folder refused for a file nobody listed holds nothing open, although its three pinned files match"
Check ((Test-EngineLoaded) -eq $false) "after every one of those refusals, nothing of the engine's interface is loaded in this process"

Write-Host ""
Write-Host "--- a data folder the engine could not write to is refused at once, in words ---" -ForegroundColor Cyan
# With a folder it cannot write, the engine waited 67 s and then failed in its own words ("Server
# execution failed (0x80080005)"), and one of its processes outlived the window (review of 2026-10-06,
# finding A10). The surface now tries the folder itself before it starts anything.
$goodData = Join-Path $work "data-ok\profile"
Check ((Test-HordeWebView2DataFolder -Path $goodData) -ceq "" -and (Test-Path -LiteralPath $goodData -PathType Container) -and @(Get-ChildItem -LiteralPath $goodData -Force).Count -eq 0) "CONTROL: a folder that can be made and written to is no problem; it is made, and the trial file is gone"
$blocker = Join-Path $work "a-file-in-the-way"
[System.IO.File]::WriteAllText($blocker, "x")
foreach ($bad in @(@{ path = $blocker; what = "a file where the folder should be" }, @{ path = (Join-Path $blocker "profile"); what = "a folder under a file" })) {
    $said = Test-HordeWebView2DataFolder -Path $bad.path
    Check ($said -like "the folder the window keeps its own files in cannot be made or written to*" -and $said -like "*so the window was not opened*") ($bad.what + " is said in words (" + $said.Substring(0, [Math]::Min(90, $said.Length)) + "...)")
}
$readOnlyDir = Join-Path $work "data-denied"
New-Item -ItemType Directory -Path $readOnlyDir | Out-Null
$acl = Get-Acl -LiteralPath $readOnlyDir
$deny = New-Object System.Security.AccessControl.FileSystemAccessRule([System.Security.Principal.WindowsIdentity]::GetCurrent().User, "CreateFiles,AppendData,WriteData", "ContainerInherit,ObjectInherit", "None", "Deny")
$acl.AddAccessRule($deny)
Set-Acl -LiteralPath $readOnlyDir -AclObject $acl
try { $deniedSaid = Test-HordeWebView2DataFolder -Path $readOnlyDir }
finally { [void]$acl.RemoveAccessRule($deny); Set-Acl -LiteralPath $readOnlyDir -AclObject $acl }
Check ($deniedSaid -like "the folder the window keeps its own files in cannot be made or written to*") "a folder this user may not write in is said the same way"
$quick = [System.Diagnostics.Stopwatch]::StartNew()
$deniedSpec = New-HordeSurfaceSpec -Title "never shown" -Mounts ([ordered]@{ shell = $pageDir }) -Start "shell/index.html" -Bridge $bridge -DataFolder (Join-Path $blocker "profile") -Hidden -OnOpened { param($Window, $State) & $Window.close }
$deniedOpen = Open-HordeWebView2Surface -Spec $deniedSpec
Check ($deniedOpen.state -ceq "failed" -and $deniedOpen.reason -like "the folder the window keeps its own files in cannot be made or written to*" -and $quick.ElapsedMilliseconds -lt 10000) ("and a window asked to keep its files there fails at once, with that sentence, before any engine is started (" + $quick.ElapsedMilliseconds + " ms)")

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
Check ($script:HordeWebView2.errors.Count -eq 0) "CONTROL: an answer and four refusals put nothing in the errors the caller reads"
# A REQUEST WHOSE HANDLER FAILS: the page is told that it failed and no more, and what the handler said
# goes where the window's caller reads errors (surfaces/Port.ps1, A REQUEST THAT FAILS).
$failingBridge = New-HordeSurfaceBridge -Requests ([ordered]@{ "breaks" = @{ run = { throw "C:\made-up\place\store.json is held by another process" } } })
$script:HordeWebView2.spec = New-HordeSurfaceSpec -Title "never shown" -Mounts ([ordered]@{ shell = $pageDir }) -Start "shell/index.html" -Bridge $failingBridge -DataFolder (Join-Path $work "data")
$failedReply = Receive-HordeWebView2Message -Json '{"v":1,"id":7,"request":"breaks"}' -Source ($at + "/shell/index.html")
Check (($failedReply | ConvertFrom-Json).reason -ceq "the request 'breaks' failed" -and $failedReply -notlike "*made-up*") ("a request whose handler throws is answered with the port's one sentence, and nothing the handler said (" + $failedReply + ")")
Check ($script:HordeWebView2.errors.Count -eq 1 -and $script:HordeWebView2.errors[0] -ceq "the request 'breaks' failed: C:\made-up\place\store.json is held by another process") ("and what it said is in the errors the window's caller reads (" + ($script:HordeWebView2.errors -join "; ") + ")")
$script:HordeWebView2.spec = $liveSpec; $script:HordeWebView2.errors.Clear()

Write-Host ""
Write-Host "--- a window never takes the keyboard unless its caller asked ---" -ForegroundColor Cyan
# A free-standing window used to take the keyboard as it appeared (review of 2026-10-06, finding D6):
# whatever a person was typing went to it. Quiet is now the rule for every window; taking the
# keyboard is something a caller asks for by name.
function Look { param([hashtable]$With = @{}) $made = New-HordeSurfaceSpec -Title "never shown" -Mounts ([ordered]@{ shell = $pageDir }) -Start "shell/index.html" -Bridge $bridge -DataFolder (Join-Path $work "data") @With; return (Get-HordeWebView2WindowLook -Spec $made) }
$free = Look
Check ($free.quiet -eq $true -and $free.taskbar -eq $true -and $free.offScreen -eq $false) "a window that stands free appears without taking the keyboard, and has its place in the taskbar"
$asked = Look @{ TakeKeyboard = $true }
Check ($asked.quiet -eq $false -and $asked.taskbar -eq $true) "CONTROL: one whose caller asked takes it"
$beside = Look @{ Companion = $true }
Check ($beside.quiet -eq $true -and $beside.taskbar -eq $false) "a companion appears quietly and out of the taskbar"
$besideAsked = Look @{ Companion = $true; TakeKeyboard = $true }
Check ($besideAsked.quiet -eq $false -and $besideAsked.taskbar -eq $false) "and takes the keyboard only when its caller asked"
$unseen = Look @{ Hidden = $true; TakeKeyboard = $true }
Check ($unseen.quiet -eq $true -and $unseen.taskbar -eq $false -and $unseen.offScreen -eq $true) "a hidden window never takes it, whatever was asked: nobody can see where their keys would go"

Write-Host ""
Write-Host "--- a page that floods is not read ---" -ForegroundColor Cyan
# The window's own clock and meter, stood in for: a clock the suite moves by hand.
$script:read = 0
$floodBridge = New-HordeSurfaceBridge -Requests ([ordered]@{ "list" = @{ run = { $script:read++; return 1 } } })
$floodSpec = New-HordeSurfaceSpec -Title "never shown" -Mounts ([ordered]@{ shell = $pageDir }) -Start "shell/index.html" -Bridge $floodBridge -DataFolder (Join-Path $work "data")
$fakeClock = [pscustomobject]@{ ElapsedMilliseconds = [long]7000 }
$kept = $script:HordeWebView2
$script:engineCalls = New-Object System.Collections.ArrayList
$fakeCore = [pscustomobject]@{ Environment = $fakeEnvironment }
$fakeCore | Add-Member -MemberType ScriptMethod -Name remove_WebMessageReceived -Value { param($Handler) [void]$script:engineCalls.Add("forget " + $Handler) }
$fakeCore | Add-Member -MemberType ScriptMethod -Name add_WebMessageReceived -Value { param($Handler) [void]$script:engineCalls.Add("listen " + $Handler) }
$fakeTimer = [pscustomobject]@{ running = $false }
$fakeTimer | Add-Member -MemberType ScriptMethod -Name Start -Value { $this.running = $true }
$fakeTimer | Add-Member -MemberType ScriptMethod -Name Stop -Value { $this.running = $false }
$script:HordeWebView2 = [pscustomobject]@{ spec = $floodSpec; mounts = $servedMounts; window = $null; opened = $false; view = ([pscustomobject]@{ CoreWebView2 = $fakeCore }); failure = ""; errors = (New-Object System.Collections.ArrayList)
    meter = (New-HordeSurfaceMessageMeter); clock = $fakeClock; messageHandler = "the-one-handler"; deaf = $false; listenTimer = $fakeTimer }
$script:looked = 0
function New-FloodMessage {
    # One message as the engine hands it over, counting each time its text is asked for.
    $m = [pscustomobject]@{ Source = ($at + "/shell/index.html") }
    $m | Add-Member -MemberType ScriptProperty -Name WebMessageAsJson -Value { $script:looked++; return '{"v":1,"id":1,"request":"list"}' }
    return $m
}
$floodHandlers = Get-HordeWebView2Handlers
1..130 | ForEach-Object { & $floodHandlers.message $null (New-FloodMessage) }
Check ($floodSpec.messagesPerSecond -eq 100 -and $script:read -eq 100 -and $script:looked -eq 100) ("of 130 messages inside one second, 100 are read and answered; the other 30 are not even looked at (" + $script:read + " answered, " + $script:looked + " looked at)")
Check ($floodBridge.refused -eq 1 -and $floodBridge.refusals[0].reason -like "*more than 100 messages within a second*dropped unread*") "and the flood is recorded once for that second, not once a message"
Check ($script:HordeWebView2.meter.dropped -eq 30) "what was dropped is counted"
Check (($script:engineCalls -join ",") -ceq "forget the-one-handler" -and $script:HordeWebView2.deaf -eq $true -and $fakeTimer.running -eq $true) "at the first message too many the engine is told, once, to stop handing messages over - by the very handler it was given - and the timer that ends the silence is started"
Check ((Get-HordeSurfaceMeterWindowMs) -eq 1000) "the silence lasts the meter's own second"
$fakeClock.ElapsedMilliseconds = [long]8000
& $floodHandlers.listen
Check (($script:engineCalls -join ",") -ceq "forget the-one-handler,listen the-one-handler" -and $script:HordeWebView2.deaf -eq $false -and $fakeTimer.running -eq $false) "when the timer fires the engine is handed the same handler again, and the timer stops"
& $floodHandlers.listen
Check ($script:engineCalls.Count -eq 2) "a second firing hands it nothing twice"
& $floodHandlers.message $null (New-FloodMessage)
Check ($script:read -eq 101 -and $floodBridge.refused -eq 1) "and the page is read again"
$script:HordeWebView2 = $kept

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
Check (@($handlers.Keys | Sort-Object) -join "," -ceq "closed,download,frame,initialized,listen,message,navigation,newWindow,permission,resource,shown,tick") "the adapter hands .NET twelve handlers"
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
# WHAT A PAGE ASKS THE MACHINE FOR IS DENIED: its place, camera, microphone, clipboard, notices.
$refusedSoFar = [int]$liveBridge.refused
$wish = [pscustomobject]@{ PermissionKind = "Geolocation"; State = "Default"; Uri = ($at + "/shell/index.html") }
& $handlers.permission $null $wish
Check ($wish.State -ceq "Deny" -and $liveBridge.refused -eq ($refusedSoFar + 1) -and $liveBridge.refusals[$liveBridge.refusals.Count - 1].reason -like "*asked the machine for something (the engine's word for it: Geolocation), and it was denied") "what a page asks the machine for is denied and recorded, with the engine's word for what was asked"
$oddWish = [pscustomobject]@{ PermissionKind = "<b>Camera</b>"; State = "Default" }
& $handlers.permission $null $oddWish
Check ($oddWish.State -ceq "Deny" -and $liveBridge.refusals[$liveBridge.refusals.Count - 1].reason -like "*for it: something)*") "and a word that is not one plain word is never put in the record"
$script:ticked = 0
$tickSpec = New-HordeSurfaceSpec -Title "never shown" -Mounts ([ordered]@{ shell = $pageDir }) -Start "shell/index.html" -Bridge $liveBridge -DataFolder (Join-Path $work "data") -State ([pscustomobject]@{ n = 5 }) -OnTick { param($Window, $State) $script:ticked += $State.n; if ($script:ticked -ge 10) { throw "a tick that fails" } }
$script:HordeWebView2.spec = $tickSpec
& $handlers.tick; & $handlers.tick
Check ($script:ticked -eq 10 -and $script:HordeWebView2.errors.Count -eq 1 -and $script:HordeWebView2.errors[0] -ceq "a tick failed: a tick that fails") "the tick handler hands the caller its own state, and a tick that throws is recorded, not fatal"
# A TICK THAT FAILS EVERY TIME must not grow the process for as long as the window is open.
1..60 | ForEach-Object { & $handlers.tick }
Check ($tickSpec.errorsKept -eq 50 -and $script:ticked -eq 310 -and $script:HordeWebView2.errors.Count -eq 50 -and $script:HordeWebView2.errors[49] -ceq "a tick failed: a tick that fails") ("sixty-one failed ticks leave the last fifty in the list the caller reads (" + $script:HordeWebView2.errors.Count + ")")
Write-Host ""
Write-Host "--- a picture is Horde's to ask for, and only of a page that is being drawn ---" -ForegroundColor Cyan
Check ((Start-HordeWebView2Capture -Path (Join-Path $work "p.png")) -eq $false -and -not (Test-Path -LiteralPath (Join-Path $work "p.png"))) "with no engine up there is nothing to take a picture of: not asked, and no file made"
$script:HordeWebView2 = [pscustomobject]@{ spec = $liveSpec; mounts = $servedMounts; window = $null; opened = $true; view = [pscustomobject]@{ CoreWebView2 = [pscustomobject]@{ } }; failure = ""; capture = $null; pictures = 0; errors = (New-Object System.Collections.ArrayList) }
# FROM INSIDE THIS RUN'S OWN FOLDER: if the refusal ever fails, the file a relative path would make
# lands here and is removed with the folder, not wherever the suite was started from (review of
# 2026-10-06, finding A13: two runs of the mutant below each left a file in the starting folder).
Push-Location -LiteralPath $work
try { $relativeTaken = Start-HordeWebView2Capture -Path "p.png" } finally { Pop-Location }
Check ($relativeTaken -eq $false -and $script:HordeWebView2.errors.Count -eq 1 -and $script:HordeWebView2.errors[0] -like "*an absolute path ending .png*") "a relative path is refused and recorded: a picture is never written wherever the process happens to stand"
Check ((Start-HordeWebView2Capture -Path (Join-Path $work "p.txt")) -eq $false -and $script:HordeWebView2.errors.Count -eq 2 -and @(Get-ChildItem -LiteralPath $work -Filter "p.*").Count -eq 0) "and so is a path that is not a .png; neither left a file behind"
# THE ENGINE REFUSES THE ASK (here: the object standing in for it has no such call). The half-opened
# file is the surface's own to remove.
$failedAsk = Start-HordeWebView2Capture -Path (Join-Path $work "q.png")
Check ($failedAsk -eq $false -and $script:HordeWebView2.errors.Count -eq 3 -and $script:HordeWebView2.errors[2] -like "a picture could not be asked for:*" -and $null -eq $script:HordeWebView2.capture) "an ask the engine does not take is answered no and recorded, and no picture is waited for"
Check (@(Get-ChildItem -LiteralPath $work -Filter "q.*").Count -eq 0) ("and it leaves no file behind, not the picture and not the file it was being drawn into (" + (@(Get-ChildItem -LiteralPath $work -Filter "q.*" | ForEach-Object { $_.Name }) -join ", ") + ")")
$script:HordeWebView2.errors.RemoveAt(2)
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
Write-Host "--- real keys for a check: only when the spec asks, only three kinds of call to the engine ---" -ForegroundColor Cyan
# What a step comes to, read back from the JSON the engine would be handed.
function Get-InputCalls { param($Steps) $made = Get-HordeWebView2InputCalls -Steps $Steps; return [pscustomobject]@{ problem = $made.problem; calls = @($made.calls | ForEach-Object { [pscustomobject]@{ method = $_.method; body = ($_.json | ConvertFrom-Json) } }) } }
$enter = Get-InputCalls @([pscustomobject]@{ key = "Enter" })
Check ($enter.problem -ceq "" -and $enter.calls.Count -eq 2 -and $enter.calls[0].body.type -ceq "keyDown" -and $enter.calls[0].body.text -ceq "`r" -and $enter.calls[0].body.windowsVirtualKeyCode -eq 13 -and $enter.calls[1].body.type -ceq "keyUp" -and $enter.calls[1].body.code -ceq "Enter") "one key is pressed and let go: Enter goes down with the character it types, and comes up"
$ctrlEnter = Get-InputCalls @([pscustomobject]@{ key = "Enter"; ctrl = $true })
Check ((@($ctrlEnter.calls | ForEach-Object { $_.body.type + ":" + $_.body.key + ":" + $_.body.modifiers }) -join ",") -ceq "rawKeyDown:Control:2,rawKeyDown:Enter:2,keyUp:Enter:2,keyUp:Control:0" -and $null -eq $ctrlEnter.calls[1].body.PSObject.Properties["text"]) ("Ctrl is pressed around the key and held while it is, and a key held with Ctrl types nothing (" + (@($ctrlEnter.calls | ForEach-Object { $_.body.type + ":" + $_.body.key + ":" + $_.body.modifiers }) -join ",") + ")")
$shiftA = Get-InputCalls @([pscustomobject]@{ key = "a"; shift = $true })
Check ((@($shiftA.calls | ForEach-Object { $_.body.type + ":" + $_.body.key + ":" + $_.body.modifiers }) -join ",") -ceq "rawKeyDown:Shift:8,keyDown:A:8,keyUp:A:8,keyUp:Shift:0" -and $shiftA.calls[1].body.text -ceq "A" -and $shiftA.calls[1].body.code -ceq "KeyA") "Shift is held around a letter, which then types its capital"
$arrows = Get-InputCalls @([pscustomobject]@{ key = "ArrowUp" }, [pscustomobject]@{ key = "ArrowDown" })
Check ((@($arrows.calls | ForEach-Object { $_.body.type + ":" + $_.body.code + ":" + $_.body.windowsVirtualKeyCode }) -join ",") -ceq "rawKeyDown:ArrowUp:38,keyUp:ArrowUp:38,rawKeyDown:ArrowDown:40,keyUp:ArrowDown:40") "the arrows up and down are keys a check can press, and type nothing"
$typed = Get-InputCalls @([pscustomobject]@{ text = "a1 !?" })
Check ((@($typed.calls | ForEach-Object { $_.method + ":" + $(if ($_.method -ceq "Input.insertText") { $_.body.text } else { $_.body.type + "/" + $_.body.code }) }) -join ",") -ceq "Input.dispatchKeyEvent:keyDown/KeyA,Input.dispatchKeyEvent:keyUp/KeyA,Input.dispatchKeyEvent:keyDown/Digit1,Input.dispatchKeyEvent:keyUp/Digit1,Input.dispatchKeyEvent:keyDown/Space,Input.dispatchKeyEvent:keyUp/Space,Input.insertText:!?") "typed text is a key for each small letter, digit and space, and the rest is put in at the caret as text"
$focus = Get-InputCalls @([pscustomobject]@{ focus = $true }, [pscustomobject]@{ focus = $false })
Check ($focus.calls.Count -eq 2 -and $focus.calls[0].method -ceq "Emulation.setFocusEmulationEnabled" -and $focus.calls[0].body.enabled -eq $true -and $focus.calls[1].body.enabled -eq $false) "the page is told it has the keyboard, or has not, by the engine: no window is activated"
foreach ($bad in @(
    @{ steps = @([pscustomobject]@{ key = "Enter" }, [pscustomobject]@{ key = "Delete" }); says = "*names a key this surface has no way to press*"; what = "a key that is not on the list, after one that is" }
    @{ steps = @([pscustomobject]@{ key = "enter" }); says = "*names a key this surface has no way to press*"; what = "a name of the list in another letter case" }
    @{ steps = @([pscustomobject]@{ key = "A" }); says = "*names a key this surface has no way to press*"; what = "a capital letter (Shift is said, not implied)" }
    @{ steps = @("Enter"); says = "*was not an object*"; what = "a step that is not an object" }
    @{ steps = @([pscustomobject]@{ focus = "yes" }); says = "*neither a key, nor text, nor the keyboard*"; what = "a step whose focus is not true or false" }
    @{ steps = @([pscustomobject]@{ text = ("a" * 1001) }); says = "*more than 2000 calls of the engine*"; what = "text that comes to more calls than one ask may" }
)) {
    $no = Get-InputCalls $bad.steps
    Check ($no.problem -like $bad.says -and $no.calls.Count -eq 0) ("" + $bad.what + ": refused in one sentence, and NOTHING is sent, not even the steps before it (" + $no.problem + ")")
}
Check ((Get-InputCalls @([pscustomobject]@{ text = ("a" * 1000) })).calls.Count -eq 2000) "CONTROL: text of exactly as many calls as one ask may come to is acted out"
$methods = @(@($enter, $ctrlEnter, $shiftA, $arrows, $typed, $focus) | ForEach-Object { $_.calls } | ForEach-Object { $_.method } | Sort-Object -Unique)
Check (($methods -join ",") -ceq "Emulation.setFocusEmulationEnabled,Input.dispatchKeyEvent,Input.insertText") ("the engine is asked for three kinds of thing and nothing else: a key, text at the caret, the keyboard given or taken (" + ($methods -join ",") + ")")
$hookTokens = $null; $hookErrors = $null
$hookAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $adapter "Surface.ps1"), [ref]$hookTokens, [ref]$hookErrors)
$engineCalls = @($hookAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Extent.Text -ceq "CallDevToolsProtocolMethodAsync" }, $true) | ForEach-Object { @($_.Arguments | ForEach-Object { $_.Extent.Text }) -join " | " })
Check ($engineCalls.Count -eq 1 -and $engineCalls[0] -ceq '$call.method | $call.json') ("the engine's own input is called in one place, with what Get-HordeWebView2InputCalls built and nothing else (" + ($engineCalls -join "; ") + ")")

# THE WINDOW'S MEMBERS: off unless the spec asks.
$plainWindow = Get-HordeWebView2Window -Form ([pscustomobject]@{ Handle = 1 }) -Errors (New-Object System.Collections.ArrayList)
$probeWindow = Get-HordeWebView2Window -Form ([pscustomobject]@{ Handle = 1 }) -Errors (New-Object System.Collections.ArrayList) -ProbeInput
Check ($null -eq $plainWindow.PSObject.Properties["input"] -and $null -eq $plainWindow.PSObject.Properties["inputIdle"]) "a window opened without probeInput has no input and no inputIdle"
Check ($probeWindow.input -is [scriptblock] -and $probeWindow.inputIdle -is [scriptblock] -and $null -ne $probeWindow.PSObject.Properties["post"]) "CONTROL: one opened with it has both, beside the members every window has"

# HANDED OVER: an engine stood in for by an object that records what it is asked.
$script:engineAsked = New-Object System.Collections.ArrayList
$standIn = [pscustomobject]@{}
Add-Member -InputObject $standIn -MemberType ScriptMethod -Name CallDevToolsProtocolMethodAsync -Value { param($Method, $Json) [void]$script:engineAsked.Add($Method); return [System.Threading.Tasks.Task]::FromResult("{}") }
$probeSpec = New-HordeSurfaceSpec -Title "never shown" -Mounts ([ordered]@{ shell = $pageDir }) -Start "shell/index.html" -Bridge $bridge -DataFolder (Join-Path $work "data") -ProbeInput
$quietSpec = New-HordeSurfaceSpec -Title "never shown" -Mounts ([ordered]@{ shell = $pageDir }) -Start "shell/index.html" -Bridge $bridge -DataFolder (Join-Path $work "data")
Check ($probeSpec.probeInput -eq $true -and $quietSpec.probeInput -eq $false) "CONTROL: the spec carries whether its caller asked"
$script:HordeWebView2 = [pscustomobject]@{ spec = $quietSpec; opened = $true; view = [pscustomobject]@{ CoreWebView2 = $standIn }; errors = (New-Object System.Collections.ArrayList); inputTasks = (New-Object System.Collections.ArrayList) }
$refusedInput = Send-HordeWebView2Input -Steps @([pscustomobject]@{ key = "Enter" })
Check ($refusedInput -eq $false -and $script:engineAsked.Count -eq 0 -and $script:HordeWebView2.errors.Count -eq 1 -and $script:HordeWebView2.errors[0] -like "*not opened to be given any*") "input handed to a window whose spec did not ask for it is refused and recorded, and the engine is asked nothing"
$script:HordeWebView2.spec = $probeSpec; $script:HordeWebView2.errors.Clear()
$handedOver = Send-HordeWebView2Input -Steps @([pscustomobject]@{ focus = $true }, [pscustomobject]@{ text = "hi" }, [pscustomobject]@{ key = "Enter" })
Check ($handedOver -eq $true -and $script:engineAsked.Count -eq 7 -and $script:engineAsked[0] -ceq "Emulation.setFocusEmulationEnabled" -and $script:HordeWebView2.inputTasks.Count -eq 7 -and $script:HordeWebView2.errors.Count -eq 0) ("with probeInput the steps are handed to the engine in order, one call each (" + ($script:engineAsked -join ",") + ")")
Check ((Test-HordeWebView2InputIdle) -eq $true -and $script:HordeWebView2.inputTasks.Count -eq 0) "and once the engine has taken them all the surface says so, and waits for none of them"
$script:engineAsked.Clear()
$halfBad = Send-HordeWebView2Input -Steps @([pscustomobject]@{ key = "Enter" }, [pscustomobject]@{ key = "Delete" })
Check ($halfBad -eq $false -and $script:engineAsked.Count -eq 0 -and $script:HordeWebView2.errors.Count -eq 1 -and $script:HordeWebView2.errors[0] -like "*no way to press*") "an ask with one step that cannot be acted out is refused whole and recorded: the engine is asked nothing"
$script:HordeWebView2.errors.Clear()
$pending = New-Object System.Threading.Tasks.TaskCompletionSource[string]
$broken = New-Object System.Threading.Tasks.TaskCompletionSource[string]
[void]$broken.TrySetException((New-Object System.InvalidOperationException("the engine said no")))
[void]$script:HordeWebView2.inputTasks.Add($broken.Task); [void]$script:HordeWebView2.inputTasks.Add($pending.Task)
Check ((Test-HordeWebView2InputIdle) -eq $false -and $script:HordeWebView2.errors.Count -eq 1 -and $script:HordeWebView2.errors[0] -ceq "the engine did not take an input: the engine said no") "a call the engine refused is recorded in its words, and one it has not finished is still waited for"
[void]$pending.TrySetResult("{}")
Check ((Test-HordeWebView2InputIdle) -eq $true -and $script:HordeWebView2.errors.Count -eq 1) "and when it has finished, the surface is idle and the refusal is not recorded twice"
$script:HordeWebView2 = $null
Check ((Send-HordeWebView2Input -Steps @([pscustomobject]@{ key = "Enter" })) -eq $false -and (Test-HordeWebView2InputIdle) -eq $true) "with no window there is nothing to hand keys to, and nothing to wait for"

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
Check ($calls -ccontains "add_PermissionRequested") "and so is the one that denies what a page asks the machine for"
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
$aware = [pscustomobject]@{ state = "applied"; awareness = "per-monitor-v2"; realScale = "yes"; reason = "Windows took it" }
Check (@(Get-HordeWebView2OpeningNotes -Scale $aware).Count -eq 0) "CONTROL: a window that opens with nothing wrong starts with nothing in the list its caller reads"
$soft = @(Get-HordeWebView2OpeningNotes -Scale ([pscustomobject]@{ state = "already"; awareness = "system"; realScale = "no"; reason = "r" }))
Check ($soft.Count -eq 1 -and $soft[0] -like "*real scale*") "what is said of the screen's scale is put there as the window opens"
# NOTHING OF A SETTINGS FILE IS AMONG THEM ANY MORE: a file with a fault is refused, and no spec is
# made from it (surfaces/Port.ps1, THE SETTINGS), so a window that opens has none to tell.
Check (-not $adapterText.Contains("a setting was not used")) "the adapter has no words for a setting that was not used: there is no such window"
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
# THE WAY A WINDOW LOADS THEM: held from the check, loaded while held, and still held afterwards for
# the engine's start, which is when the third file - not .NET's - is loaded.
$loaded = Import-HordeWebView2Libraries -Hold
Check ($loaded -ceq "" -and (Test-EngineLoaded) -eq $true) "CONTROL: the pinned files, unchanged, are checked and then loaded"
Check (@($script:HordeWebView2Held).Count -eq 3 -and (Test-Writable (Join-Path $lib "WebView2Loader.dll")) -eq $false) "and all three are still held, so the one the engine loads later is the one that was checked"
Clear-HordeWebView2HeldFiles
Check (@($script:HordeWebView2Held).Count -eq 0 -and (Test-Writable (Join-Path $lib "WebView2Loader.dll")) -eq $true) "until the surface lets go of them"
$again = Import-HordeWebView2Libraries
Check ($again -ceq "" -and @($script:HordeWebView2Held).Count -eq 0) "asked only to load, nothing is left held: the check runs again, every time, and lets go"
Check ($null -ne ("HordeSurfaceForm" -as [type]) -and (New-Object HordeSurfaceForm).Quiet -eq $false) "and with them the window type that can be shown without taking the keyboard"
$version = Get-HordeWebView2RuntimeVersion
if ($version -ne "") { Write-Host ("  the engine installed here is " + $version) -ForegroundColor DarkGray }
else { Write-Host "  [SKIP] no engine is installed on this machine, so the real-window suite beside this one cannot show a window here" -ForegroundColor Yellow }

} finally {
    $script:HordeWebView2 = $null
    if ((Split-Path -Leaf $work) -match '\Ahorde-webview2-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "the window surface loads only the files it pins, keeps the page at its own address, and reads only the page's own messages"
