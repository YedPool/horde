# DOES THE SURFACE PORT REFUSE EVERYTHING A PAGE MAY NOT ASK, AND ANSWER ONLY WHAT IS ON THE LIST?
#
# surfaces/Port.ps1's Invoke-HordeSurfaceRequest stands between a page - text that may quote anything
# a session wrote - and Horde. It is a pure function of a bridge and the text that arrived, so every
# case here runs with no window: each named request, a request that is not on the list, a message that
# is not a message, an oversized one, wrong arguments, a handler that throws. Then the port's own
# promises: only a registered surface is opened, a surface is picked by what it can do and never by
# name, and a spec a surface could only half honour is refused before any window exists.
#
# The surfaces here are invented in %TEMP% ("zorbview", "zorbfile"), so nothing in this file names a
# real one (CONTRIBUTING 14).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "surfaces\Port.ps1")

$work = Join-Path $env:TEMP ("horde-surface-port-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
# A HOME OF THIS RUN: the port reads its settings from <home>\settings\surface.json, and the real
# home's file, if a person wrote one, is not this suite's to be steered by. Not created: with no file
# every setting is its default, which is what every check above the settings section assumes.
$env:HORDE_HOME = Join-Path $work "home"

$script:calls = New-Object System.Collections.ArrayList
$bridge = New-HordeSurfaceBridge -Events @("list-changed") -Requests ([ordered]@{
    "list"     = @{ run = { param($Arguments, $State, $Window) [void]$script:calls.Add("list"); return [pscustomobject]@{ questions = @(1, 2, 3); who = $State.who } } }
    "rendered" = @{ args = @{ rows = @{ type = "integer"; most = 100000 }; note = @{ type = "string"; most = 20 }; whole = @{ type = "boolean" } }
                    run = { param($Arguments, $State, $Window) [void]$script:calls.Add("rendered " + $Arguments["rows"] + " " + $Arguments["note"] + " " + $Arguments["whole"]); return $true } }
    "breaks"   = @{ run = { param($Arguments, $State, $Window) throw "the store could not be read: C:\made-up\place\store.json is held by another process" } }
})
$state = [pscustomobject]@{ who = "the caller's own state" }
function Ask { param([string]$Text) return (Invoke-HordeSurfaceRequest -Bridge $bridge -Text $Text -State $state -Now ([datetime]::new(2026, 10, 7, 9, 0, 0, [System.DateTimeKind]::Utc))) }
function Reply { param($R) return ($R.reply | ConvertFrom-Json) }

try {

Write-Host ""
Write-Host "--- every named request is answered, and only through its handler ---" -ForegroundColor Cyan
$a = Ask '{"v":1,"id":7,"request":"list"}'
$av = Reply $a
Check ($a.refused -ceq "" -and $a.request -ceq "list" -and $av.ok -eq $true -and $av.reply -eq 7 -and $av.v -eq 1) "a request on the list is answered, under the id the page chose"
Check (@($av.value.questions).Count -eq 3 -and $av.value.who -ceq "the caller's own state") "its handler is given the caller's state, and what it returns is the value"
$b = Ask '{"v":1,"id":8,"request":"rendered","args":{"rows":22,"note":"ok","whole":true}}'
Check ((Reply $b).ok -eq $true -and $script:calls[$script:calls.Count - 1] -ceq "rendered 22 ok True") "a request with arguments hands its handler exactly those arguments"
$c = Ask '{"v":1,"id":9,"request":"list","args":{}}'
Check ((Reply $c).ok -eq $true) "a request that takes no argument may give an empty args"
Check ($bridge.answered -eq 3 -and $bridge.refused -eq 0) "CONTROL: three answered, none refused so far"
$f = Ask '{"v":1,"id":10,"request":"breaks"}'
$fv = Reply $f
# WHAT A HANDLER SAID AS IT FAILED IS NOT THE PAGE'S TO READ (review of 2026-10-06, finding A11): its
# words are whatever the code under it threw, the path of a file among them, and a page may quote
# anything a session wrote. The page is told one fixed sentence; the words stay on Horde's side.
Check ($fv.ok -eq $false -and $fv.reply -eq 10 -and $fv.reason -ceq "the request 'breaks' failed" -and $f.refused -ceq "") ("a handler that throws is answered as a failure, in one fixed sentence that names the request and nothing else (" + $fv.reason + "), and is not a refusal")
Check ($f.reply -notlike "*store*" -and $f.reply -notlike "*made-up*" -and $f.reply -notlike "*another process*") ("nothing the handler said - the path of a file least of all - is in what the page is handed (" + $f.reply + ")")
Check ($f.failed -ceq "the request 'breaks' failed: the store could not be read: C:\made-up\place\store.json is held by another process") ("what it said is handed to the surface whole, for the errors its caller reads (" + $f.failed + ")")
Check ($bridge.failed -eq 1 -and $bridge.failures.Count -eq 1 -and $bridge.failures[0].reason -ceq $f.failed -and $bridge.failures[0].at -ceq "2026-10-07T09:00:00.0000000Z") "and it is kept on the bridge's own record with when it happened, which is where it is read when there is no window"
Check ($bridge.refused -eq 0 -and $bridge.answered -eq 3) "it is not counted as a refusal, nor as answered"
Check ($a.failed -ceq "" -and (Invoke-HordeSurfaceRequest -Bridge (New-HordeSurfaceBridge -Requests ([ordered]@{ "list" = @{ run = { return 1 } } })) -Text '{"v":1,"id":11,"request":"nope"}').failed -ceq "") "CONTROL: a request that is answered, and one that is refused, say nothing failed"

Write-Host ""
Write-Host "--- a request that is not on the list ---" -ForegroundColor Cyan
$callsBefore = $script:calls.Count
$u = Ask '{"v":1,"id":11,"request":"run-program","args":{"path":"calc.exe"}}'
$uv = Reply $u
Check ($u.refused -like "*not on the list; the list is: list, rendered, breaks" -and $uv.ok -eq $false -and $uv.reply -eq 11 -and $uv.reason -like "refused: *") "an unknown request is refused, and the page is told so under its id"
Check ($u.reply -notlike "*run-program*" -and $u.reply -notlike "*calc*") "the refusal does not repeat what the page sent"
Check ($script:calls.Count -eq $callsBefore) "and no handler ran"
Check ((Ask '{"v":1,"id":12,"request":"List"}').refused -like "*not on the list*") "a name is matched exactly: List is not list"
Check ((Ask '{"v":1,"id":13,"request":7}').refused -like "*not on the list*") "a request that is not text is not on the list"
Check ((Ask '{"v":1,"id":14}').refused -like "*not on the list*") "nor is a message with no request"
Check ($bridge.refused -eq 4 -and $bridge.refusals.Count -eq 4 -and $bridge.refusals[0].at -ceq "2026-10-07T09:00:00.0000000Z" -and $bridge.refusals[0].reason -like "*not on the list*") "every refusal is counted and recorded, with when"

Write-Host ""
Write-Host "--- a message that is not a message ---" -ForegroundColor Cyan
foreach ($bad in @(
    @{ text = ""; says = "was empty"; what = "nothing at all" }
    @{ text = "not json at all"; says = "not one JSON object"; what = "text that is not JSON" }
    @{ text = '{"v":1,"id":1,"request":"list"'; says = "not one JSON object"; what = "JSON cut short" }
    @{ text = '[{"v":1,"id":1,"request":"list"}]'; says = "not one JSON object"; what = "a list of messages" }
    @{ text = '"list"'; says = "not one JSON object"; what = "a bare string" }
    @{ text = 'null'; says = "not one JSON object"; what = "null" }
    @{ text = '{"v":1,"request":"list"}'; says = "carried no id"; what = "no id" }
    @{ text = '{"v":1,"id":0,"request":"list"}'; says = "carried no id"; what = "an id of 0" }
    @{ text = '{"v":1,"id":-3,"request":"list"}'; says = "carried no id"; what = "a negative id" }
    @{ text = '{"v":1,"id":1.5,"request":"list"}'; says = "carried no id"; what = "an id that is not whole" }
    @{ text = '{"v":1,"id":"1","request":"list"}'; says = "carried no id"; what = "an id that is text" }
    @{ text = '{"v":1,"id":99999999999,"request":"list"}'; says = "carried no id"; what = "an id too large to answer under" }
)) {
    $r = Ask $bad.text
    Check ($r.refused -like ("*" + $bad.says + "*") -and $r.reply -ceq "" -and $r.request -ceq "") ($bad.what + " is refused, and nothing is sent back: there is no id to answer")
}
foreach ($bad in @(
    @{ text = '{"v":2,"id":20,"request":"list"}'; says = "is not version 1"; what = "another version of the requests" }
    @{ text = '{"id":20,"request":"list"}'; says = "is not version 1"; what = "no version" }
    @{ text = '{"v":"1","id":20,"request":"list"}'; says = "is not version 1"; what = "a version that is text" }
    @{ text = '{"v":1,"id":20,"request":"list","run":"calc.exe"}'; says = "a member that is not v, id, request or args"; what = "a member nobody defined" }
    @{ text = '{"v":1,"id":20,"request":"rendered","args":{"rows":22,"note":"ok"}}'; says = "does not give 'whole'"; what = "a missing argument" }
    @{ text = '{"v":1,"id":20,"request":"rendered","args":{"rows":22,"note":"ok","whole":true,"extra":1}}'; says = "gives an argument 'rendered' does not take"; what = "an argument nobody declared" }
    @{ text = '{"v":1,"id":20,"request":"list","args":{"state":"all"}}'; says = "gives an argument 'list' does not take"; what = "an argument to a request that takes none" }
    @{ text = '{"v":1,"id":20,"request":"rendered","args":{"rows":"22","note":"ok","whole":true}}'; says = "'rows' is not a whole number"; what = "text where a number is wanted" }
    @{ text = '{"v":1,"id":20,"request":"rendered","args":{"rows":2.5,"note":"ok","whole":true}}'; says = "'rows' is not a whole number"; what = "a number that is not whole" }
    @{ text = '{"v":1,"id":20,"request":"rendered","args":{"rows":1e30,"note":"ok","whole":true}}'; says = "'rows' is not a whole number"; what = "a number no count can be" }
    @{ text = '{"v":1,"id":20,"request":"rendered","args":{"rows":-1,"note":"ok","whole":true}}'; says = "'rows' is not between 0 and 100000"; what = "a negative count" }
    @{ text = '{"v":1,"id":20,"request":"rendered","args":{"rows":100001,"note":"ok","whole":true}}'; says = "'rows' is not between 0 and 100000"; what = "a count past its cap" }
    @{ text = '{"v":1,"id":20,"request":"rendered","args":{"rows":1,"note":7,"whole":true}}'; says = "'note' is not text"; what = "a number where text is wanted" }
    @{ text = '{"v":1,"id":20,"request":"rendered","args":{"rows":1,"note":"123456789012345678901","whole":true}}'; says = "'note' is 21 characters, more than the 20 it may be"; what = "text past its cap" }
    @{ text = '{"v":1,"id":20,"request":"rendered","args":{"rows":1,"note":"ok","whole":"true"}}'; says = "'whole' is not true or false"; what = "text where true or false is wanted" }
    @{ text = '{"v":1,"id":20,"request":"rendered","args":[22,"ok",true]}'; says = "its args is not an object"; what = "args given as a list" }
)) {
    $before = $script:calls.Count
    $r = Ask $bad.text
    $rv = $null; if ($r.reply -ne "") { $rv = Reply $r }
    Check ($r.refused -like ("*" + $bad.says + "*") -and $null -ne $rv -and $rv.ok -eq $false -and $rv.reply -eq 20 -and $script:calls.Count -eq $before) ($bad.what + " is refused under its id, and no handler runs")
}
$edge = Ask '{"v":1,"id":21,"request":"rendered","args":{"rows":100000,"note":"12345678901234567890","whole":false}}'
Check ((Reply $edge).ok -eq $true -and $script:calls[$script:calls.Count - 1] -ceq "rendered 100000 12345678901234567890 False") "CONTROL: a count and a text exactly at their caps are taken"

Write-Host ""
Write-Host "--- an oversized message is refused before it is read ---" -ForegroundColor Cyan
$big = '{"v":1,"id":30,"request":"rendered","args":{"rows":1,"note":"' + ("x" * 70000) + '","whole":true}}'
$o = Ask $big
Check ($o.refused -like "*characters, more than the 65536 one may be; it was not read" -and $o.reply -ceq "") "a message past 65536 characters is refused unread, so it has no id to answer"
$fits = '{"v":1,"id":31,"request":"list"}' + (" " * (65536 - 32))
Check ($fits.Length -eq 65536 -and (Reply (Ask $fits)).ok -eq $true) "CONTROL: one of exactly 65536 characters is read"

Write-Host ""
Write-Host "--- the record of refusals stays short ---" -ForegroundColor Cyan
$small = New-HordeSurfaceBridge -Requests ([ordered]@{ "list" = @{ run = { return 1 } } })
1..60 | ForEach-Object { [void](Invoke-HordeSurfaceRequest -Bridge $small -Text ('{"v":1,"id":' + $_ + ',"request":"nope"}')) }
Check ($small.refused -eq 60 -and $small.refusals.Count -eq 50) "sixty refusals are all counted, and the last fifty are kept"

Write-Host ""
Write-Host "--- the shapes of the messages are written once, in a file both sides read ---" -ForegroundColor Cyan
$shapes = Get-HordeSurfaceMessages
Check ((Get-HordeSurfaceMessagesPath) -ceq (Join-Path $root "surfaces\bridge-messages.json") -and (Test-Path -LiteralPath (Get-HordeSurfaceMessagesPath) -PathType Leaf)) "the definition is one file beside the port"
Check ($shapes.protocol -eq 1 -and ($shapes.request.version + "," + $shapes.request.id + "," + $shapes.request.name + "," + $shapes.request.arguments) -ceq "v,id,request,args") "CONTROL: it gives protocol 1 and a request's four members"
Check (($shapes.reply.version + "," + $shapes.reply.id + "," + $shapes.reply.ok + "," + $shapes.reply.value + "," + $shapes.reply.reason) -ceq "v,reply,ok,value,reason" -and ($shapes.event.version + "," + $shapes.event.name + "," + $shapes.event.value) -ceq "v,event,value") "and a reply's five and an event's three"
# THE PORT READS THE FILE, NOT A COPY OF IT: hand it another definition and every message it reads
# and writes is in that vocabulary, and the shipped one is refused.
$otherShapes = [ordered]@{ schemaVersion = 1; protocol = 7
    request = [ordered]@{ version = "ver"; id = "n"; name = "ask"; arguments = "with" }
    reply = [ordered]@{ version = "ver"; id = "re"; ok = "fine"; value = "got"; reason = "why" }
    event = [ordered]@{ version = "ver"; name = "happened"; value = "got" } }
function Write-Shapes { param($Shapes, [string]$Name) $p = Join-Path $work $Name; [System.IO.File]::WriteAllText($p, (ConvertTo-Json -InputObject $Shapes -Depth 5)); return $p }
$shipped = $script:HordeSurfaceMessages
try {
    $script:HordeSurfaceMessages = Read-HordeSurfaceMessages -Path (Write-Shapes $otherShapes "other-shapes.json")
    $inOther = Ask '{"ver":7,"n":3,"ask":"rendered","with":{"rows":4,"note":"other","whole":true}}'
    $ov = Reply $inOther
    Check ($inOther.refused -ceq "" -and @($ov.PSObject.Properties | ForEach-Object { $_.Name }) -join "," -ceq "ver,re,fine,got" -and $ov.ver -eq 7 -and $ov.re -eq 3 -and $ov.fine -eq $true) "given another definition, a request in its vocabulary is read, and the reply is written in it"
    Check ($script:calls[$script:calls.Count - 1] -ceq "rendered 4 other True") "its arguments are found under that definition's name for them"
    $inShipped = Ask '{"v":1,"id":3,"request":"list"}'
    Check ($inShipped.refused -like "*carried no n:*" -and $inShipped.reply -ceq "") "and a message in the shipped vocabulary is refused: no name is written twice"
    $wrongOther = Reply (Ask '{"ver":7,"n":4,"ask":"list","extra":1}')
    Check ($wrongOther.fine -eq $false -and $wrongOther.why -like "refused: *a member that is not ver, n, ask or with") "a refusal names the members of the definition in force"
    Check ((Reply (Ask '{"ver":1,"n":5,"ask":"list"}')).why -like "*is not version 7 of*") "and its protocol number"
    $otherEvent = (ConvertTo-HordeSurfaceEvent -Bridge $bridge -Name "list-changed" -Value 5) | ConvertFrom-Json
    Check (@($otherEvent.PSObject.Properties | ForEach-Object { $_.Name }) -join "," -ceq "ver,happened,got" -and $otherEvent.ver -eq 7 -and $otherEvent.happened -ceq "list-changed") "an event is written in it too"
} finally { $script:HordeSurfaceMessages = $shipped }
Check ((Reply (Ask '{"v":1,"id":41,"request":"list"}')).ok -eq $true) "CONTROL: with the shipped definition back, the shipped vocabulary is read again"
function New-Shapes { param([scriptblock]$Change) $s = ConvertTo-Json -InputObject $otherShapes -Depth 5 | ConvertFrom-Json; & $Change $s; return $s }
foreach ($bad in @(
    @{ what = "a part left out"; says = "arguments"; change = { param($s) $s.request.PSObject.Properties.Remove("arguments") } }
    @{ what = "a part nobody reads"; says = "extra"; change = { param($s) $s.event | Add-Member -NotePropertyName extra -NotePropertyValue "x" } }
    @{ what = "a member name that is not a plain name"; says = "request"; change = { param($s) $s.request.name = "ask me" } }
    @{ what = "no protocol number from 1 up"; says = "protocol"; change = { param($s) $s.protocol = 0 } }
    @{ what = "two parts of one shape under one name"; says = "the request gives two parts the name 'n'"; change = { param($s) $s.request.name = "n" } }
    @{ what = "a reply that could be taken for an event"; says = "a reply and an event could not be told apart"; change = { param($s) $s.event.name = "re" } }
)) {
    Check (Throws { Read-HordeSurfaceMessages -Path (Write-Shapes (New-Shapes $bad.change) "bad-shapes.json") } $bad.says) ("a definition with " + $bad.what + " is refused when it is read")
}
Check (Throws { Read-HordeSurfaceMessages -Path (Join-Path $work "no-such-shapes.json") } "is not there") "and so is one that is not there: without it nothing can cross"

Write-Host ""
Write-Host "--- what Horde sends ---" -ForegroundColor Cyan
$he = ([string][char]0x05E9) + [char]0x05DC + [char]0x05D5 + [char]0x05DD
$line = ConvertTo-HordeSurfaceEvent -Bridge $bridge -Name "list-changed" -Value ([pscustomobject]@{ title = $he + " <b>&'" })
Check ($line -cmatch '\A[\x20-\x7E]+\z' -and $line -notmatch "[\r\n]") "an event is one line of printable ASCII"
$back = $line | ConvertFrom-Json
Check ($back.v -eq 1 -and $back.event -ceq "list-changed" -and $back.value.title -ceq ($he + " <b>&'")) "and text in another alphabet, and markup, come back character for character"
Check (Throws { ConvertTo-HordeSurfaceEvent -Bridge $bridge -Name "anything-else" } "is not an event this bridge pushes") "an event the bridge does not list is not pushed"
Check (Throws { New-HordeSurfaceBridge -Requests ([ordered]@{ "Run It" = @{ run = { } } }) } "is not a request name") "a bridge refuses a request name that is not lowercase letters and hyphens"
Check (Throws { New-HordeSurfaceBridge -Requests ([ordered]@{ "list" = @{ } }) } "has no run block") "and a request with nothing to answer it"
Check (Throws { New-HordeSurfaceBridge -Requests ([ordered]@{ "list" = @{ args = @{ x = @{ type = "object" } }; run = { } } }) } "not one of string, integer, boolean") "and an argument of a type that could carry anything"

Write-Host ""
Write-Host "--- a value too deep to be written whole is a failure, never half a value ---" -ForegroundColor Cyan
# Past its depth, Windows PowerShell 5.1 writes the rest of a value as the NAME OF ITS TYPE and says
# nothing: a page was handed the text "System.Collections.Hashtable" where its data should be (review
# of 2026-10-06, finding A11).
function New-Nested { param([int]$Levels, [string]$Kind = "table") $v = "leaf"; for ($i = 0; $i -lt $Levels; $i++) { if ($Kind -ceq "table") { $v = @{ a = $v } } elseif ($Kind -ceq "object") { $v = [pscustomobject]@{ a = $v } } else { $v = @($v, 0) } }; return , $v }
$script:deep = $null
$deepBridge = New-HordeSurfaceBridge -Events @("told") -Requests ([ordered]@{ "deep" = @{ run = { return , $script:deep } } })
function AskDeep { return (Invoke-HordeSurfaceRequest -Bridge $deepBridge -Text '{"v":1,"id":5,"request":"deep"}') }
foreach ($kind in @("table", "object", "list")) {
    $script:deep = New-Nested 16 $kind
    $fits = AskDeep
    Check ($fits.refused -ceq "" -and $fits.reply -like '*"ok":true*' -and $fits.reply -like '*"leaf"*' -and $fits.reply -notlike "*System.*" -and $fits.reply -notlike "*@{*") ("CONTROL: a " + $kind + " nested 16 deep crosses whole")
    $script:deep = New-Nested 17 $kind
    $tooDeep = AskDeep
    $said = $tooDeep.reply | ConvertFrom-Json
    Check ($said.ok -eq $false -and $said.reply -eq 5 -and $said.reason -ceq "the request 'deep' failed" -and $tooDeep.refused -ceq "") ("a " + $kind + " nested 17 deep is answered as a failure of the request, in the one sentence a page is told (" + $said.reason + ")")
    Check ($tooDeep.failed -like "the request 'deep' failed: its answer could not be handed over: the value nests more than 16 levels deep*" -and $deepBridge.failures[$deepBridge.failures.Count - 1].reason -ceq $tooDeep.failed) ("and why is said on Horde's side, in words (" + $tooDeep.failed + ")")
    Check ($tooDeep.reply -notlike "*leaf*" -and $tooDeep.reply -notlike "*System.*" -and $tooDeep.reply -notlike "*@{*") "and nothing of the value, and no type's name, is handed to the page"
    Check (Throws { ConvertTo-HordeSurfaceEvent -Bridge $deepBridge -Name "told" -Value (New-Nested 17 $kind) } "nests more than 16 levels deep") ("an event carrying such a " + $kind + " is not pushed")
}
$loop = @{ name = "loop" }; $loop["self"] = $loop
$script:deep = $loop
$looped = AskDeep
Check (($looped.reply | ConvertFrom-Json).ok -eq $false -and ($looped.reply | ConvertFrom-Json).reason -ceq "the request 'deep' failed" -and $looped.failed -like "*nests more than 16 levels deep*") "a value that holds itself is a failure too, said the same two ways, and does not hang the window"
Check ($deepBridge.refused -eq 0 -and $deepBridge.answered -eq 3 -and $deepBridge.failed -eq 4) "none of these is a refusal - the page asked properly - and only the three that crossed count as answered, the other four as failed"

Write-Host ""
Write-Host "--- a surface is registered, picked by what it can do, and only then opened ---" -ForegroundColor Cyan
function New-FakeSurface {
    param([string]$Name, [string]$Native = "yes", [string]$Declared = "")
    $dir = Join-Path $work $Name
    New-Item -ItemType Directory -Path $dir | Out-Null
    $caps = [ordered]@{}
    foreach ($c in @(Get-HordeSurfaceCapabilityNames)) { $caps[$c] = @{ support = "yes"; evidence = "invented for this suite" } }
    $caps["window.native"] = @{ support = $Native; evidence = "invented for this suite" }
    $named = $Name; if ($Declared -ne "") { $named = $Declared }
    [System.IO.File]::WriteAllText((Join-Path $dir "capabilities.json"), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = 1; surface = $named; capabilities = $caps }) -Depth 5))
    return $dir
}
Check ((Get-HordeSurfaceCapabilityNames) -join "," -ceq "page.local,page.locked,requests.closed,push,window.native,picture") "the capability names are the schema's six"
Check (Throws { Register-HordeSurface -Folder (Join-Path $work "nothing-here") -Open { } } "has no capabilities.json") "a folder with no capabilities.json is not a surface"
Check (Throws { Register-HordeSurface -Folder (New-FakeSurface "zorbwrong" -Declared "zorbother") -Open { } } "but sits in the folder 'zorbwrong'") "nor is one whose capabilities name another folder"
Check (Throws { Register-HordeSurface -Folder (New-FakeSurface "zorbmaybe" -Native "perhaps") -Open { } } "refused") "nor one with a support word outside the vocabulary"
$script:opened = New-Object System.Collections.ArrayList
$fileDir = New-FakeSurface "zorbfile" -Native "no"
$viewDir = New-FakeSurface "zorbview"
$zFile = Register-HordeSurface -Folder $fileDir -Open { param($Spec) [void]$script:opened.Add("file " + $Spec.title); return [pscustomobject]@{ state = "closed"; reason = "" } }
$zView = Register-HordeSurface -Folder $viewDir -Open { param($Spec) [void]$script:opened.Add("view " + $Spec.title); "noise on the way"; return [pscustomobject]@{ state = "closed"; reason = "" } }
Check (Throws { Register-HordeSurface -Folder $viewDir -Open { } } "is already registered") "a second registration of one name is refused: the first stands"
Check ((Get-HordeSurfaceNames) -join "," -ceq "zorbfile,zorbview") "CONTROL: both invented surfaces are registered"
Check ((Resolve-HordeSurface -Requires @("page.local", "window.native")).name -ceq "zorbview") "a caller that needs a native window gets the one surface that has one"
Check ((Resolve-HordeSurface -Requires @("page.local")).name -ceq "zorbfile") "and one that needs only a local page gets the first that has that"
Check ($null -eq (Resolve-HordeSurface -Requires @("window.native", "push") | Where-Object { $_.name -ceq "zorbfile" })) "a surface that says no to a capability is never picked for it"
Check (Throws { Test-HordeSurfaceCapability -Surface $zView -Capability "window.magic" } "is not a surface capability") "a capability outside the list is a programming error, not a no"

$pageDir = Join-Path $work "page"; New-Item -ItemType Directory -Path $pageDir | Out-Null
[System.IO.File]::WriteAllText((Join-Path $pageDir "index.html"), "<!doctype html><title>x</title>")
$spec = New-HordeSurfaceSpec -Title "a page" -Mounts ([ordered]@{ shell = $pageDir }) -Start "shell/index.html" -Bridge $bridge -DataFolder (Join-Path $work "data") -Hidden
Check ($spec.startMount -ceq "shell" -and $spec.startFile -ceq "index.html" -and $spec.hidden -eq $true -and $spec.mounts["shell"] -ceq [System.IO.Path]::GetFullPath($pageDir)) "a spec keeps its mounts, its start page and whether it is hidden"
$done = Open-HordeSurface -Surface $zView -Spec $spec
Check ($done.state -ceq "closed" -and $script:opened[$script:opened.Count - 1] -ceq "view a page") "a registered surface is opened with the spec, and its last word is the answer whatever else it printed"
$look = [pscustomobject]@{ PSTypeName = "Horde.Surface"; name = "zorbview"; open = { param($Spec) [void]$script:opened.Add("LOOK-ALIKE"); return [pscustomobject]@{ state = "closed"; reason = "" } } }
$refusedLook = Open-HordeSurface -Surface $look -Spec $spec
Check ($refusedLook.state -ceq "failed" -and $refusedLook.reason -like "*not a surface registered*" -and @($script:opened) -cnotcontains "LOOK-ALIKE") "an object that only looks like a registered surface is not opened"
$zThrow = Register-HordeSurface -Folder (New-FakeSurface "zorbthrows") -Open { param($Spec) throw "the engine is not installed" }
$failed = Open-HordeSurface -Surface $zThrow -Spec $spec
Check ($failed.state -ceq "failed" -and $failed.reason -ceq "the surface could not be shown: the engine is not installed") "a surface that throws comes back failed, with its reason"
$zMute = Register-HordeSurface -Folder (New-FakeSurface "zorbmute") -Open { param($Spec) return "shown, probably" }
Check ((Open-HordeSurface -Surface $zMute -Spec $spec).reason -ceq "the surface did not say whether it was shown") "and one that answers with something else is failed too, never taken as shown"

Write-Host ""
Write-Host "--- a spec a surface could only half honour is refused ---" -ForegroundColor Cyan
$m = [ordered]@{ shell = $pageDir }
Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts ([ordered]@{ "Shell Page" = $pageDir }) -Start "shell/index.html" -Bridge $bridge -DataFolder $work } "is not a mount name") "a mount name that could not be part of an address"
Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts ([ordered]@{ shell = (Join-Path $work "no-such-folder") }) -Start "shell/index.html" -Bridge $bridge -DataFolder $work } "is not a folder that exists") "a mount that is not a folder"
# From the folder that holds it, so that the relative name does reach a real folder: without the
# check for a rooted path this would be accepted, and then served from wherever the process stood.
Push-Location -LiteralPath $work
try { Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts ([ordered]@{ shell = "page" }) -Start "shell/index.html" -Bridge $bridge -DataFolder $work } "is not a folder that exists") "a mount given as a relative path, even one that exists from here" }
finally { Pop-Location }
Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts ([ordered]@{}) -Start "shell/index.html" -Bridge $bridge -DataFolder $work } "at least one mount") "no mount at all"
Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts ([ordered]@{ surface = $pageDir }) -Start "surface/index.html" -Bridge $bridge -DataFolder $work } "is the surface's own") "a mount under the name the surface serves its own bridge at"
$portText = [System.IO.File]::ReadAllText((Join-Path $root "surfaces\Port.ps1"))
Check ((Get-HordeSurfaceOwnMount) -ceq "surface" -and $portText.Contains("WHERE A PAGE FINDS A FILE: BY A RELATIVE ADDRESS, ALWAYS")) "CONTROL: the port's own text is read, and it says how a page addresses a file"
Check (-not $portText.Contains("://") -and -not $portText.Contains(".invalid") -and $null -eq (Get-Command -Name "Get-HordeSurfaceMountHost" -ErrorAction SilentlyContinue)) "the port names no address at all: where a surface serves the mounts is that surface's private detail, so a page cannot be written against it"
Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $bridge -DataFolder $work -Left 10 } "both its left and its top") "a left with no top"
Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "other/index.html" -Bridge $bridge -DataFolder $work } "is not <mount>/<file> of a mount that was given") "a start page in a mount that was not given"
Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/../../secret.html" -Bridge $bridge -DataFolder $work } "is not <mount>/<file>") "a start page that climbs out of its mount"
Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/missing.html" -Bridge $bridge -DataFolder $work } "is not a file that exists") "a start page that is not there"
Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $bridge -DataFolder "data" } "must be an absolute path") "a relative data folder"
Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $bridge -DataFolder $work -TickMs 5 } "ticks no faster") "a tick faster than every 50 ms"
Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $bridge -DataFolder $work -Theme "Dark" } "is not a theme; the themes are: system, light, dark") "a theme that is not one of the three, exactly"
Check ($spec.takeKeyboard -eq $false -and (New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $bridge -DataFolder $work -TakeKeyboard).takeKeyboard -eq $true) "a spec does not ask for the keyboard unless its caller says so: a window that appears while a person types elsewhere must not swallow the keys"
Check ($spec.theme -ceq "system" -and (New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $bridge -DataFolder $work -Theme "dark").theme -ceq "dark") "a spec follows the machine's theme unless it is given one"
Check (-not $bridge.requests.Contains("capture") -and (Ask '{"v":1,"id":40,"request":"capture","args":{"path":"C:\\x.png"}}').refused -like "*not on the list*") "a picture is not something a page can ask for: capture is no request"

Write-Host ""
Write-Host "--- the port's numbers are settings of the module 'surface', read from the home ---" -ForegroundColor Cyan
$declared = Get-HordeSurfaceSettingsDeclaration
Check ($declared.module -ceq "surface" -and (@($declared.settings | ForEach-Object { $_.name + "=" + $_.default }) -join " ") -ceq "widthPx=520 heightPx=760 tickMs=250 messageChars=65536 argumentChars=16384 refusalsKept=50 errorsKept=50 messagesPerSecond=100") ("the module declares one table, with the defaults the port had (" + (@($declared.settings | ForEach-Object { $_.name + "=" + $_.default }) -join " ") + ")")
$limits = Get-HordeSurfaceLimits
Check ($limits.smallestWidthPx -eq 200 -and $limits.smallestHeightPx -eq 150 -and $limits.fastestTickMs -eq 50) "what no setting may go below is the port's to say, once: 200 by 150 pixels, a tick every 50 ms"
$floor = @{}; foreach ($e in $declared.settings) { $floor[$e.name] = $e.min }
Check ($floor["widthPx"] -eq $limits.smallestWidthPx -and $floor["heightPx"] -eq $limits.smallestHeightPx -and $floor["tickMs"] -eq $limits.fastestTickMs) "and the settings' own smallest values are those same numbers, not a second copy"
$unset = Get-HordeSurfaceSettings
Check ($unset.state -ceq "defaults" -and @($unset.findings).Count -eq 0 -and $unset.values.widthPx -eq 520 -and $unset.values.messageChars -eq 65536 -and $unset.path -ceq (Join-Path $env:HORDE_HOME "settings\surface.json") -and -not (Test-Path -LiteralPath $env:HORDE_HOME)) "CONTROL: with no file every setting is its default, nothing is reported, and reading made no folder"
$defaultSpec = New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $bridge -DataFolder $work
Check ($defaultSpec.width -eq 520 -and $defaultSpec.height -eq 760 -and $defaultSpec.tickMs -eq 250) "CONTROL: a spec that names no size and no pace gets the defaults"
New-Item -ItemType Directory -Path (Join-Path $env:HORDE_HOME "settings") -Force | Out-Null
[System.IO.File]::WriteAllText($unset.path, '{ "schemaVersion": 1, "settings": { "widthPx": 640, "heightPx": 480, "tickMs": 100, "messageChars": 2000, "argumentChars": 100, "refusalsKept": 3 } }')
$set = Get-HordeSurfaceSettings
Check ($set.state -ceq "read" -and @($set.findings).Count -eq 0 -and $set.values.widthPx -eq 640 -and $set.values.refusalsKept -eq 3) "a person's file under the home overrides them"
$tight = New-HordeSurfaceBridge -Settings $set -Requests ([ordered]@{ "say" = @{ args = @{ text = @{ type = "string" }; short = @{ type = "string"; most = 5 } }; run = { return 1 } } })
Check ((Invoke-HordeSurfaceRequest -Bridge $tight -Text ('{"v":1,"id":1,"request":"say","args":{"text":"' + ("x" * 1900) + '","short":"ab"}}' + (" " * 100))).refused -like "*characters, more than the 2000 one may be; it was not read") "a bridge refuses a message past the size its settings give, unread"
Check ((Invoke-HordeSurfaceRequest -Bridge $tight -Text ('{"v":1,"id":2,"request":"say","args":{"text":"' + ("x" * 101) + '","short":"ab"}}')).refused -like "*'text' is 101 characters, more than the 100 it may be") "an argument that declared no length of its own is held to the setting"
Check ((Invoke-HordeSurfaceRequest -Bridge $tight -Text ('{"v":1,"id":3,"request":"say","args":{"text":"' + ("x" * 100) + '","short":"abcdef"}}')).refused -like "*'short' is 6 characters, more than the 5 it may be") "and one that declared its own is held to that"
Check ((Invoke-HordeSurfaceRequest -Bridge $tight -Text ('{"v":1,"id":4,"request":"say","args":{"text":"' + ("x" * 100) + '","short":"abcde"}}')).refused -ceq "") "CONTROL: a message inside every limit is answered"
Check ($tight.refused -eq 3 -and $tight.refusals.Count -eq 3) "CONTROL: three refused so far, three kept"
[void](Invoke-HordeSurfaceRequest -Bridge $tight -Text "x"); [void](Invoke-HordeSurfaceRequest -Bridge $tight -Text "y")
Check ($tight.refused -eq 5 -and $tight.refusals.Count -eq 3) "the record keeps as many refusals as the setting says: five counted, the last three kept"
$sized = New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $tight -DataFolder $work -Settings $set
Check ($sized.width -eq 640 -and $sized.height -eq 480 -and $sized.tickMs -eq 100) "a spec that names no size and no pace gets the settings'"
$named = New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $tight -DataFolder $work -Settings $set -Width 300 -Height 200 -TickMs 60
Check ($named.width -eq 300 -and $named.height -eq 200 -and $named.tickMs -eq 60) "and one that names them gets what it named: a caller's word is above a setting"
Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $tight -DataFolder $work -Settings $set -Width 199 } "at least 200 by 150 pixels") "a caller's size below the smallest is still refused"
Check (Throws { New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $tight -DataFolder $work -Settings $set -Height 149 } "at least 200 by 150 pixels") "in either direction"
$unsaid = New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $tight -DataFolder $work
Check ($unsaid.width -eq 640) "a spec handed no settings reads the file itself"
# A SETTINGS FILE THAT FAILS A CHECK IS REFUSED, AND SO IS THE SURFACE (core/ModuleSettings.ps1: "an
# override file that fails its checks refuses with a reason and never silently falls back to the
# defaults"). One bad key beside good ones: no bridge and no spec is made, so nothing can be opened,
# and what is thrown is the file's own findings - the file and each key by name.
[System.IO.File]::WriteAllText($unset.path, '{ "schemaVersion": 1, "settings": { "widthPx": 5, "heightPx": 480, "colour": "red" } }')
$bad = Get-HordeSurfaceSettings
Check ($bad.state -ceq "refused" -and $null -eq $bad.values -and @($bad.findings).Count -eq 2) ("CONTROL: a value out of range and a name nobody declared refuse the file, with one finding each and no values (" + $bad.state + "; " + @($bad.findings).Count + ")")
function Said { param([scriptblock]$Block) try { $null = & $Block; return "<it did not throw>" } catch { return "$($_.Exception.Message)" } }
$whole = @($bad.findings) -join [Environment]::NewLine
$noSpec = Said { New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $bridge -DataFolder $work }
Check ($noSpec -ceq $whole -and $noSpec -like ("*the settings file '" + $unset.path + "' of surface is refused: *") -and $noSpec -like "*'widthPx'*" -and $noSpec -like "*'colour'*") ("with that file no spec is made, so no surface opens on defaults: what is thrown names the file and each key (" + $noSpec + ")")
$noBridge = Said { New-HordeSurfaceBridge -Requests ([ordered]@{ "list" = @{ run = { return 1 } } }) }
Check ($noBridge -ceq $whole) ("nor is a bridge made, for the same reasons (" + $noBridge + ")")
Check ((Said { New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $bridge -DataFolder $work -Settings $bad }) -ceq $whole -and (Said { New-HordeSurfaceBridge -Settings $bad -Requests ([ordered]@{ "list" = @{ run = { return 1 } } }) }) -ceq $whole) "a caller that read the file itself and hands on a refusal is refused the same way: nothing reads a default out of it"
Check ((Said { New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $bridge -DataFolder $work -Width 640 -Height 480 -TickMs 100 }) -ceq $whole) "and a caller that names its own size and pace is refused too: a spec is never made beside a refused file"
foreach ($notOne in @([pscustomobject]@{ values = $set.values; findings = @() }, [pscustomobject]@{ state = "fine"; values = $set.values; findings = @() }, "read")) {
    Check ((Throws { New-HordeSurfaceBridge -Settings $notOne -Requests ([ordered]@{ "list" = @{ run = { return 1 } } }) } "is not an answer of Get-HordeSurfaceSettings") -and (Throws { New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $bridge -DataFolder $work -Settings $notOne } "is not an answer of Get-HordeSurfaceSettings")) "settings whose state is not defaults or read are not taken for good ones"
}
Check (@($unsaid.PSObject.Properties | ForEach-Object { $_.Name }) -cnotcontains "findings") "a spec carries no findings: when a spec exists there was nothing wrong to carry"
Check ($tight.limits.messageChars -eq 2000 -and (Invoke-HordeSurfaceRequest -Bridge $tight -Text ("z" * 2001)).refused -like "*more than the 2000*") "a bridge keeps the limits it was made with: a file changed later does not move them under a page"
# THE LIST OF ERRORS A SURFACE KEEPS FOR ITS CALLER IS SHORT TOO. A tick that fails every time adds
# four lines a second for as long as the window is open (review of 2026-10-06, finding A9).
Check ($defaultSpec.errorsKept -eq 50 -and $sized.errorsKept -eq 50) "CONTROL: a spec carries how many errors its surface keeps, 50 unless a person's file says otherwise"
$kept = New-Object System.Collections.ArrayList
1..7 | ForEach-Object { Add-HordeSurfaceError -Errors $kept -Text ("failure " + $_) -Kept 5 }
Check ($kept.Count -eq 5 -and $kept[0] -ceq "failure 3" -and $kept[4] -ceq "failure 7") "seven errors added to a list that keeps five leave the last five, oldest first"
Add-HordeSurfaceError -Errors $kept -Text "" -Kept 5
Check ($kept.Count -eq 5 -and $kept[4] -ceq "failure 7") "an empty line is not an error, and pushes nothing out"
[System.IO.File]::WriteAllText($unset.path, '{ "schemaVersion": 1, "settings": { "errorsKept": 2 } }')
Check ((New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $bridge -DataFolder $work).errorsKept -eq 2) "and the number is the module's setting errorsKept"
# THE BRIDGE'S RECORD OF FAILED REQUESTS IS HELD TO THE SAME NUMBER: a handler that fails every time
# a page asks must not grow the process either.
$script:failing = 0
$breaking = New-HordeSurfaceBridge -Requests ([ordered]@{ "breaks" = @{ run = { $script:failing++; throw ("failure " + $script:failing) } } })
Check ($breaking.limits.errorsKept -eq 2 -and $bridge.limits.errorsKept -eq 50) "a bridge keeps as many failed requests as the setting was when it was made (2 now, 50 for the bridge made before any file)"
1..5 | ForEach-Object { [void](Invoke-HordeSurfaceRequest -Bridge $breaking -Text ('{"v":1,"id":' + $_ + ',"request":"breaks"}')) }
Check ($breaking.failed -eq 5 -and $breaking.failures.Count -eq 2 -and $breaking.failures[0].reason -ceq "the request 'breaks' failed: failure 4" -and $breaking.failures[1].reason -ceq "the request 'breaks' failed: failure 5") "five failed requests are all counted, and the last two kept, oldest first"
# A PAGE THAT FLOODS IS NOT READ. Ten thousand messages in one burst held a window's thread for 11 to
# 14 seconds, every one of them parsed, refused and recorded (review of 2026-10-06, finding A8;
# measured again 2026-10-07). The meter says, for each message as it arrives, whether it is read.
Check ($defaultSpec.messagesPerSecond -eq 100) "CONTROL: a spec carries how many messages a second its surface reads, 100 unless a person's file says otherwise"
$meter = New-HordeSurfaceMessageMeter
$turns = @(0..6 | ForEach-Object { Test-HordeSurfaceMessageMeter -Meter $meter -NowMs (5000 + $_) -PerSecond 5 })
Check (($turns -join ",") -ceq "read,read,read,read,read,refuse,drop") ("of seven messages in one second, a meter set to five reads five, says once that the rest are refused, and drops them (" + ($turns -join ",") + ")")
Check ((Test-HordeSurfaceMessageMeter -Meter $meter -NowMs 5999 -PerSecond 5) -ceq "drop" -and $meter.dropped -eq 3) "to the end of that second everything more is dropped, and counted"
Check ((Test-HordeSurfaceMessageMeter -Meter $meter -NowMs 6000 -PerSecond 5) -ceq "read") "a second after the first message of the burst, messages are read again"
$again = @(1..6 | ForEach-Object { Test-HordeSurfaceMessageMeter -Meter $meter -NowMs 6001 -PerSecond 5 })
Check (($again -join ",") -ceq "read,read,read,read,refuse,drop" -and $meter.dropped -eq 5) "and the next second is counted from nothing, with its own one refusal"
Check ((Test-HordeSurfaceMessageMeter -Meter $meter -NowMs 100 -PerSecond 5) -ceq "read") "a clock that went backwards starts a new second rather than dropping for ever"
[System.IO.File]::WriteAllText($unset.path, '{ "schemaVersion": 1, "settings": { "messagesPerSecond": 7 } }')
Check ((New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $bridge -DataFolder $work).messagesPerSecond -eq 7) "and the number is the module's setting messagesPerSecond"
$handed = New-HordeSurfaceBridge -Settings $set -Requests ([ordered]@{ "list" = @{ run = { return 1 } } })
$handedSpec = New-HordeSurfaceSpec -Title "t" -Mounts $m -Start "shell/index.html" -Bridge $handed -DataFolder $work -Settings $set
Check ($handed.limits.messageChars -eq 2000 -and $handed.limits.refusalsKept -eq 3 -and $handedSpec.width -eq 640) "a bridge and a spec that are handed settings use those and do not read the file again: one reading serves both, and its findings are the caller's to report once"
$fresh = New-HordeSurfaceBridge -Requests ([ordered]@{ "list" = @{ run = { return 1 } } })
Check ($fresh.limits.messageChars -eq 65536 -and $fresh.limits.argumentChars -eq 16384 -and $fresh.limits.refusalsKept -eq 50) "and a bridge made now, handed no settings, reads the file as it is now"
Remove-Item -LiteralPath $env:HORDE_HOME -Recurse -Force

Write-Host ""
Write-Host "--- which file an address names: only a file of a mount, of a kind a page is made of ---" -ForegroundColor Cyan
$tree = Join-Path $work "tree"
$shellDir = Join-Path $tree "shell"; $otherDir = Join-Path $tree "other"; $surfaceDir = Join-Path $tree "adapter"
foreach ($d in @($shellDir, (Join-Path $shellDir "img\deep"), $otherDir, $surfaceDir)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
foreach ($f in @("shell\index.html", "shell\Look.css", "shell\img\dot.png", "shell\img\deep\a.svg", "shell\tool.exe", "shell\notes.md", "shell\nul.js", "other\data.json", "other\other.js", "adapter\bridge.js", "adapter\secret.js", "secret.txt")) {
    try { [System.IO.File]::WriteAllText((Join-Path $tree $f), "x") } catch { }
}
$own = Get-HordeSurfaceOwnFiles -BridgeScript (Join-Path $surfaceDir "bridge.js")
Check ((@($own.Keys) -join ",") -ceq "bridge.js,bridge-messages.json" -and $own["bridge-messages.json"] -ceq (Get-HordeSurfaceMessagesPath) -and $own["bridge.js"] -ceq (Join-Path $surfaceDir "bridge.js")) "the surface's own mount is two named files: its side of the bridge, and the port's definition of the messages"
$served = [ordered]@{ shell = $shellDir; other = $otherDir; surface = $own }
function Find { param([string]$Path) return (Resolve-HordeSurfacePageFile -Mounts $served -Path $Path) }
foreach ($ok in @(
    @{ path = "/shell/index.html"; file = (Join-Path $shellDir "index.html"); type = "text/html; charset=utf-8" }
    @{ path = "/shell/Look.css"; file = (Join-Path $shellDir "Look.css"); type = "text/css; charset=utf-8" }
    @{ path = "/shell/img/dot.png"; file = (Join-Path $shellDir "img\dot.png"); type = "image/png" }
    @{ path = "/shell/img/deep/a.svg"; file = (Join-Path $shellDir "img\deep\a.svg"); type = "image/svg+xml" }
    @{ path = "/other/data.json"; file = (Join-Path $otherDir "data.json"); type = "application/json; charset=utf-8" }
    @{ path = "/other/other.js"; file = (Join-Path $otherDir "other.js"); type = "text/javascript; charset=utf-8" }
    @{ path = "/surface/bridge.js"; file = (Join-Path $surfaceDir "bridge.js"); type = "text/javascript; charset=utf-8" }
    @{ path = "/surface/bridge-messages.json"; file = (Get-HordeSurfaceMessagesPath); type = "application/json; charset=utf-8" }
)) {
    $got = Find $ok.path
    Check ($got.file -ceq $ok.file -and $got.type -ceq $ok.type -and $got.reason -ceq "") ("CONTROL: " + $ok.path + " is a file of a mount, served as " + $ok.type)
}
foreach ($no in @(
    @{ path = ""; says = "not a file of a mount"; what = "nothing" }
    @{ path = "/"; says = "not a file of a mount"; what = "the root" }
    @{ path = "/shell"; says = "not a file of a mount"; what = "a mount with no file" }
    @{ path = "/shell/"; says = "not a file of a mount"; what = "a mount's folder" }
    @{ path = "shell/index.html"; says = "not a file of a mount"; what = "a path with no leading slash" }
    @{ path = "//shell/index.html"; says = "not a file of a mount"; what = "a doubled slash in front" }
    @{ path = "/shell//index.html"; says = "not a file of a mount"; what = "an empty step" }
    @{ path = "/shell/index.html/"; says = "not a file of a mount"; what = "a file used as a folder" }
    @{ path = "/shell/../secret.txt"; says = "not a file of a mount"; what = "a climb out of the mount" }
    @{ path = "/shell/..%2fsecret.txt"; says = "not a file of a mount"; what = "a climb written with an escape" }
    @{ path = "/shell/%2e%2e/secret.txt"; says = "not a file of a mount"; what = "dots written with escapes" }
    @{ path = "/shell/..\secret.txt"; says = "not a file of a mount"; what = "a climb with the other slash" }
    @{ path = "/shell/img\dot.png"; says = "not a file of a mount"; what = "the other slash" }
    @{ path = "/shell/index.html:stream"; says = "not a file of a mount"; what = "a second stream of a file" }
    @{ path = "/shell/index.html."; says = "not a file of a mount"; what = "a name ending in a dot, which Windows reads as the name without it" }
    @{ path = "/shell/.index.html"; says = "not a file of a mount"; what = "a name beginning with a dot" }
    @{ path = "/shell/a/b/c/d/e/f/g/h/i.js"; says = "not a file of a mount"; what = "a path nine steps deep" }
    @{ path = "/SHELL/index.html"; says = "a mount that was not given"; what = "a mount in other letter case" }
    @{ path = "/fleet/panel.js"; says = "a mount that was not given"; what = "a mount nobody gave" }
    @{ path = "/shell/tool.exe"; says = "not a kind of file a page is made of"; what = "a program" }
    @{ path = "/shell/notes.md"; says = "not a kind of file a page is made of"; what = "a kind nobody listed" }
    @{ path = "/shell/index.HTML"; says = "not a kind of file a page is made of"; what = "a kind in other letter case" }
    @{ path = "/shell/nul.js"; says = "a name Windows keeps for a device"; what = "a device name" }
    @{ path = "/shell/img/COM1.png"; says = "a name Windows keeps for a device"; what = "a device name in a folder, in capitals" }
    @{ path = "/shell/missing.js"; says = "a file that is not there"; what = "a file that is not there" }
    @{ path = "/shell/look.css"; says = "a file that is not there"; what = "a name in other letter case than the file's own" }
    @{ path = "/shell/IMG/dot.png"; says = "a file that is not there"; what = "a folder in other letter case than its own" }
    @{ path = "/shell/img"; says = "not a kind of file a page is made of"; what = "a folder, which has no kind" }
    @{ path = "/shell/img/deep.svg"; says = "a file that is not there"; what = "a name that is a folder beside the file" }
    @{ path = "/surface/secret.js"; says = "a file that is not there"; what = "a file beside the surface's own two" }
    @{ path = "/surface/sub/bridge.js"; says = "a file that is not there"; what = "a folder under the surface's own mount" }
)) {
    $got = Find $no.path
    Check ($got.file -ceq "" -and $got.type -ceq "" -and $got.reason -like ("*" + $no.says + "*")) ($no.what + " is refused (" + $no.path + ")")
    Check ($no.path.Length -lt 6 -or -not $got.reason.Contains($no.path.Substring(1))) "and the reason does not repeat the address"
}
$types = Get-HordeSurfaceFileTypes
Check ((@($types.Keys | Sort-Object) -join " ") -ceq ".css .gif .html .ico .jpg .js .json .png .svg .txt .webp .woff2") "the kinds of file a page is made of are one closed list, the port's"
Check (@($types.Values | Where-Object { $_ -notmatch '\A[a-z]+/[a-z0-9.+-]+(; charset=utf-8)?\z' }).Count -eq 0) "each with the type it is served as"

} finally {
    if ((Split-Path -Leaf $work) -match '\Ahorde-surface-port-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "a page reaches Horde only through the closed list of requests, and only a registered surface is opened"
