# WHAT MAY THE DECISIONS WINDOW'S PAGE ASK, AND WHAT IS IT HANDED - WITH NO WINDOW OPEN?
#
# decisions/Window.ps1 puts four parts together for `horde decisions open`. Everything of it that
# needs no window is tested here: the closed list of five requests, each asked through the surface
# port exactly as a page's message would arrive, and answered from a real list in a home this suite
# made; a request that is not on the list, a malformed one and an oversized one; the title; the name a
# second `open` finds the first by; standing beside a terminal window or saying why not, on registries
# and finders this suite invents; the redraw when the store changes, and only then; the report file.
#
# NOTHING HERE OPENS A WINDOW, AND NOTHING TOUCHES A TERMINAL. HORDE_HOME is a folder this suite made
# and removes, the fleet's registry is one it made, and the real store is listed before and after.
# The window itself - a real one, on a real list - is test/e2e/e2e-decisions-window.ps1's.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-decisions-window-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$keepHome = $env:HORDE_HOME; $keepFleet = $env:WEZFLEET_ROOT
function Get-RealStoreListing {
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing
$hordeHome = Join-Path $work "home"
$env:HORDE_HOME = $hordeHome
$env:WEZFLEET_ROOT = Join-Path $work "no-fleet"
. (Join-Path $root "decisions\Window.ps1")
. (Join-Path $root "test\lib\WindowProbe.ps1")

function Add-Question {
    param([int]$N, [string[]]$Waiting = @(), [string]$AskedBy = "Orc A", [string]$Group = "the first group")
    $q = [ordered]@{ title = ("Should question number " + $N + " be shown in the window?"); kind = "yes-no"; whatItIs = ("The context of question " + $N + ", with <b>markup</b> a page must show as text."); recommendation = "yes"; group = $Group; askedBy = $AskedBy; waiting = @($Waiting) }
    $a = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $q }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("the fixture question " + $N + " was not added: " + $a.state + " " + $a.reason) }
}
function Ask { param($State, [string]$Text, $Window = $null) return (Invoke-HordeSurfaceRequest -Bridge $State.bridge -Text $Text -State $State -Window $Window) }
function Reply { param($R) return ($R.reply | ConvertFrom-Json) }
# What a window hands a watcher to marshal its events through, standing in for the window: it counts
# what it is handed and runs none of it, so no script ever runs on a thread that is not this one.
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
public class HordeTestSync : ISynchronizeInvoke {
    public int Handed;
    public bool InvokeRequired { get { return true; } }
    public IAsyncResult BeginInvoke(Delegate method, object[] args) { System.Threading.Interlocked.Increment(ref Handed); return null; }
    public object EndInvoke(IAsyncResult result) { return null; }
    public object Invoke(Delegate method, object[] args) { System.Threading.Interlocked.Increment(ref Handed); return null; }
}
'@
function New-FakeWindow {
    $script:posted = New-Object System.Collections.ArrayList
    $script:titles = New-Object System.Collections.ArrayList
    return [pscustomobject]@{ handle = [long]4242; sync = (New-Object HordeTestSync); errors = (New-Object System.Collections.ArrayList)
        post = { param($Json) [void]$script:posted.Add($Json) }; setTitle = { param($Text) [void]$script:titles.Add("" + $Text) }; show = { $script:shown = 1 + [int]$script:shown }; close = { } }
}

try {

Write-Host ""
Write-Host "--- the closed list: five requests, each answered from the operations ---" -ForegroundColor Cyan
$state = New-HordeDecisionWindowState -Attachment ([pscustomobject]@{ attached = $false; handle = [long]0; reason = "no session holds the role of warchief" })
Check ((@($state.bridge.requests.Keys) -join ",") -ceq "kinds,list,fleet,attachment,rendered") "the page may ask five things: kinds, list, fleet, attachment, rendered"
Check ((@($state.bridge.events) -join ",") -ceq "list-changed,fleet-changed,attachment-changed,show") "and may be pushed four: list-changed, fleet-changed, attachment-changed, show"
$window = New-FakeWindow
$empty = Reply (Ask $state '{"v":1,"id":1,"request":"list"}' $window)
Check ($empty.ok -eq $true -and $empty.value.state -ceq "known" -and $empty.value.value.outcome -ceq "done" -and @($empty.value.value.questions).Count -eq 0) "list, on a home with no store at all: a known, empty list"
Check (-not (Test-Path -LiteralPath $hordeHome)) "and asking made no folder: a read makes none"
Check ($script:titles[$script:titles.Count - 1] -ceq "Open decisions: 0, 0 waiting") "the title is set from the list the page was just handed"

Add-Question 1 @("Orc A (the first build)") "Orc A"
Add-Question 2 @() "Orc B"
Add-Question 3 @("Orc B", "the warchief") "the warchief" "the second group"
[void](Invoke-HordeDecision -Operation "close" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; number = 2; outcome = "Done as asked." })
$list = Reply (Ask $state '{"v":1,"id":2,"request":"list","args":{}}' $window)
$qs = @($list.value.value.questions)
Check ($list.ok -eq $true -and $qs.Count -eq 3 -and (@($qs | ForEach-Object { "" + $_.number + ":" + $_.state }) -join ",") -ceq "1:open,2:closed,3:open") "list hands the page every question, open and closed, each under its permanent number"
Check ($qs[0].title -ceq "Should question number 1 be shown in the window?" -and $qs[0].whatItIs.Contains("<b>markup</b>") -and @($qs[2].waiting).Count -eq 2 -and $qs[1].outcome -ceq "Done as asked.") "as the list operation answers them: the words unchanged, who is waiting, what was done"
Check ($list.value.value.counts.open -eq 2 -and $list.value.value.counts.closed -eq 1 -and $null -ne $list.value.value.PSObject.Properties["unreadable"]) "with the operation's own counts, and its account of any record it could not read"
Check ($null -eq $list.value.PSObject.Properties["observedAt"]) "the time the list was read is not part of what the page is handed, so the same list read twice is the same"
Check ($script:titles[$script:titles.Count - 1] -ceq "Open decisions: 2, 2 waiting") "the title counts the open questions and those with someone waiting"
$kinds = Reply (Ask $state '{"v":1,"id":3,"request":"kinds"}' $window)
Check ($kinds.ok -eq $true -and $kinds.value.state -ceq "known" -and $kinds.value.value.kinds.'yes-no'.label -ceq "yes or no" -and $null -ne $kinds.value.value.kinds.'do-then-say') "kinds hands the page the kinds operation's table, the one every caller reads"
$attach = Reply (Ask $state '{"v":1,"id":4,"request":"attachment"}' $window)
Check ($attach.ok -eq $true -and $attach.value.attached -eq $false -and $attach.value.reason -ceq "no session holds the role of warchief") "attachment says whether the window stands beside a terminal window, and why not"
$fleet = Reply (Ask $state '{"v":1,"id":5,"request":"fleet"}' $window)
Check ($fleet.ok -eq $true -and $fleet.value.state -ceq "not-configured" -and @($fleet.value.orcs).Count -eq 0) "fleet, with nothing configured: not-configured, and no Orc"
$rendered = Reply (Ask $state '{"v":1,"id":6,"request":"rendered","args":{"rows":2,"open":2,"closed":1,"waiting":2,"expanded":0,"entries":4,"written":0,"filter":"open","picked":""}}' $window)
Check ($rendered.ok -eq $true -and $state.rendered.rows -eq 2 -and $state.rendered.closed -eq 1 -and $state.rendered.filter -ceq "open" -and $state.reports -eq 1 -and $state.reportDue -eq $true) "rendered records what the page says is on screen, in numbers"
Check ($state.bridge.refused -eq 0 -and $state.bridge.answered -eq 6) "CONTROL: six requests answered so far, none refused"

Write-Host ""
Write-Host "--- anything else is refused, and nothing a page can ask changes the list ---" -ForegroundColor Cyan
$records = @(Get-ChildItem -LiteralPath (Join-Path $hordeHome "store\decisions") -File | ForEach-Object { $_.Name + "|" + $_.Length }) -join ";"
foreach ($bad in @(
    @{ text = '{"v":1,"id":7,"request":"add","args":{"title":"x"}}'; what = "a request to add a question" }
    @{ text = '{"v":1,"id":7,"request":"close","args":{"number":1}}'; what = "a request to close one" }
    @{ text = '{"v":1,"id":7,"request":"answer","args":{"number":1,"words":"yes"}}'; what = "a request to answer one, which is the next slice's" }
    @{ text = '{"v":1,"id":7,"request":"open-file","args":{"path":"C:\\Windows\\win.ini"}}'; what = "a request to open a file" }
    @{ text = '{"v":1,"id":7,"request":"run","args":{"command":"calc.exe"}}'; what = "a request to run a program" }
    @{ text = '{"v":1,"id":7,"request":"list","args":{"state":"all","root":"C:\\elsewhere"}}'; what = "list with arguments of the page's own" }
    @{ text = '{"v":1,"id":7,"request":"rendered","args":{"rows":"22"}}'; what = "rendered with text for a count and the rest missing" }
)) {
    $r = Ask $state $bad.text $window
    Check ($r.refused -ne "" -and (Reply $r).ok -eq $false) ($bad.what + " is refused")
}
foreach ($bad in @(
    @{ text = "list"; what = "a bare word" }
    @{ text = '{"v":1,"request":"list"}'; what = "a message with no id" }
    @{ text = ('{"v":1,"id":8,"request":"rendered","args":{"rows":1,"open":1,"closed":0,"waiting":0,"expanded":0,"entries":1,"written":0,"filter":"open","picked":"' + ("x" * 70000) + '"}}'); what = "a message of 70000 characters" }
)) {
    $r = Ask $state $bad.text $window
    Check ($r.refused -ne "" -and $r.reply -ceq "") ($bad.what + " is refused, with nothing sent back")
}
Check ($state.bridge.refused -eq 10 -and $state.bridge.refusals.Count -eq 10) "all ten refusals are counted and recorded"
Check ((@(Get-ChildItem -LiteralPath (Join-Path $hordeHome "store\decisions") -File | ForEach-Object { $_.Name + "|" + $_.Length }) -join ";") -ceq $records) "and the store holds exactly the records it held: nothing the page asked wrote one"
$src = [System.IO.File]::ReadAllText((Join-Path $root "decisions\Window.ps1"))
$operations = @([regex]::Matches($src, 'Get-HordeDecisionWindowRecord -Operation "([a-z-]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Check (($operations -join ",") -ceq "kinds,list") "the window's file asks the decisions operations for the list and the kinds, and for nothing else"
Check (-not ($src -match 'Get-HordeDecisionRecords|ConvertTo-HordeDecisionState|Add-HordeDecisionRecord|Get-ChildItem|ReadAllText|Get-Content')) "and reads no record of the store itself: no listing of it, no file of it opened"

Write-Host ""
Write-Host "--- the list is pushed when it changed, and only then ---" -ForegroundColor Cyan
$script:posted.Clear()
Check ((Update-HordeDecisionWindowList -State $state -Window $window) -eq $false -and $script:posted.Count -eq 0 -and $state.pushes -eq 0) "asked again with nothing changed: nothing is pushed, so the page is not redrawn"
Add-Question 4 @("Orc C") "Orc C"
Check ((Update-HordeDecisionWindowList -State $state -Window $window) -eq $true -and $script:posted.Count -eq 1 -and $state.pushes -eq 1) "after a fourth question is added: one push"
$event = $script:posted[0] | ConvertFrom-Json
Check ($event.event -ceq "list-changed" -and @($event.value.value.questions).Count -eq 4 -and $script:posted[0] -cmatch '\A[\x20-\x7E]+\z') "the push is the list-changed event carrying the whole new list, as one line of ASCII"
Check ($script:titles[$script:titles.Count - 1] -ceq "Open decisions: 3, 3 waiting" -and $state.title -ceq "Open decisions: 3, 3 waiting") "and the title follows"
Check ((Update-HordeDecisionWindowList -State $state -Window $window) -eq $false -and $script:posted.Count -eq 1) "CONTROL: asked once more, nothing is pushed again"

Write-Host ""
Write-Host "--- the store's folder is watched, and a change is only noted ---" -ForegroundColor Cyan
$script:HordeDecisionWindow = $state
$state.dirtyAt = $null
Check ((Start-HordeDecisionWindowWatch -State $state) -eq $false -and $null -eq $state.watcher) "with nothing to marshal its events through there is no watch: its handler would run where no script can"
Check ((Start-HordeDecisionWindowWatch -State $state -Sync $window.sync) -eq $true -and $null -ne $state.watcher -and $state.watcher.Path -ceq (Join-Path $hordeHome "store\decisions") -and $state.watcher.Filter -ceq "*.json") "the watch is on the store's own folder, for its records"
Check ([object]::ReferenceEquals($state.watcher.SynchronizingObject, $window.sync) -and $state.watcher.EnableRaisingEvents -eq $true) "and its events go through what the window handed it"
Check ($null -ne $state.dirtyAt) "starting it notes a change, so whatever was written before it started is picked up once"
Check ((Start-HordeDecisionWindowWatch -State $state -Sync $window.sync) -eq $false) "it is started once"
$handedBefore = $window.sync.Handed
Add-Question 6 @() "Orc A"
for ($wait = 0; $wait -lt 40 -and $window.sync.Handed -eq $handedBefore; $wait++) { Start-Sleep -Milliseconds 100 }
Check ($window.sync.Handed -gt $handedBefore) "a record written to the store reaches the watch, which hands it on to the window's thread and runs nothing itself"
$state.dirtyAt = $null; $before = $state.changes
Set-HordeDecisionWindowDirty
Check ($null -ne $state.dirtyAt -and $state.changes -eq ($before + 1)) "a change notes the time and is counted; the list is asked for later, on the window's own tick"
$nowhere = New-HordeDecisionWindowState
$nowhere.storeRoot = Join-Path $work "no-such-store"
Check ((Start-HordeDecisionWindowWatch -State $nowhere -Sync $window.sync) -eq $false -and $null -eq $nowhere.watcher) "a store folder that does not exist yet is not watched yet: the tick tries again when it appears"
Invoke-HordeDecisionWindowClosed -Window $window -State $state
Check ($null -eq $state.watcher) "closing the window stops the watch"

Write-Host ""
Write-Host "--- one tick, with a recording window ---" -ForegroundColor Cyan
$tick = New-HordeDecisionWindowState -Attachment ([pscustomobject]@{ attached = $false; handle = [long]0; reason = "none" })
$script:HordeDecisionWindow = $tick
$tick.showEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset)
$script:posted.Clear(); $script:shown = 0
[void](Ask $tick '{"v":1,"id":1,"request":"list"}' $window)
[void](Ask $tick '{"v":1,"id":2,"request":"fleet"}' $window)
Invoke-HordeDecisionWindowTick -Window $window -State $tick
Check ($null -ne $tick.watcher -and $script:shown -eq 0) "the first tick starts the watch, and brings nothing forward unasked"
Check ($script:posted.Count -eq 0) "nothing is pushed while the gathered change is under 400 ms old, or when the list is what the page has"
[void]$tick.showEvent.Set()
Invoke-HordeDecisionWindowTick -Window $window -State $tick
Check ($script:shown -eq 1) "a second open's signal brings the window forward, once"
Invoke-HordeDecisionWindowTick -Window $window -State $tick
Check ($script:shown -eq 1) "and not again on the next tick"
Add-Question 5 @() "Orc A"
$tick.dirtyAt = [datetime]::UtcNow
$tick.fleetDueAt = [datetime]::UtcNow.AddMinutes(5)
Invoke-HordeDecisionWindowTick -Window $window -State $tick
Check ($script:posted.Count -eq 0 -and $null -ne $tick.dirtyAt) "a change noted this instant is not acted on yet: a burst of records is one redraw"
$tick.dirtyAt = [datetime]::UtcNow.AddMilliseconds(-450)
Invoke-HordeDecisionWindowTick -Window $window -State $tick
Check ($script:posted.Count -eq 1 -and $null -eq $tick.dirtyAt -and @((($script:posted[0] | ConvertFrom-Json).value.value.questions)).Count -eq 6) "450 ms after the last change the list is asked for and pushed, once"
Check ($tick.title -ceq "Open decisions: 5, 3 waiting") "the title then counts five open and three with someone waiting: two open questions block nobody"
Invoke-HordeDecisionWindowClosed -Window $window -State $tick
$tick.showEvent.Dispose()

Write-Host ""
Write-Host "--- the title, and the name a second open finds the first by ---" -ForegroundColor Cyan
Check ((Get-HordeDecisionWindowTitle -Record $null) -ceq "Open decisions: the list could not be read") "no list: the title says so, never a count of nothing"
Check ((Get-HordeDecisionWindowTitle -Record ([pscustomobject]@{ state = "unknown"; value = $null; reason = "the store could not be read" })) -ceq "Open decisions: the list could not be read") "an unknown list: the same"
Check ((Get-HordeDecisionWindowTitle -Record ([pscustomobject]@{ state = "known"; value = [pscustomobject]@{ outcome = "refused" }; reason = "" })) -ceq "Open decisions: the list could not be read") "a refused one: the same"
$nameA = Get-HordeDecisionWindowName -HordeHome "C:\Homes\One"
Check ($nameA -cmatch '\Ahorde-decisions-window-[0-9a-f]{16}\z') "the name is fixed words and sixteen hex digits"
Check ((Get-HordeDecisionWindowName -HordeHome "c:\homes\one\") -ceq $nameA) "the same home written in another case, or with a slash after it, is the same window"
Check ((Get-HordeDecisionWindowName -HordeHome "C:\Homes\Two") -cne $nameA) "another home is another window: a test's window never meets the real one"

Write-Host ""
Write-Host "--- beside a terminal window, or saying why not ---" -ForegroundColor Cyan
$hidden = Resolve-HordeDecisionWindowAttachment -Hidden
Check ($hidden.attached -eq $false -and $hidden.reason -like "it was opened hidden*") "opened hidden: not attached, whatever the fleet says"
$noFleet = Resolve-HordeDecisionWindowAttachment
Check ($noFleet.attached -eq $false -and $noFleet.handle -eq 0 -and $noFleet.reason -like "the session records could not all be read*") "no fleet registry: not attached, with the reason"
function Set-Registry { param([hashtable[]]$Records)
    $env:WEZFLEET_ROOT = New-HordeProbeRegistry -Root (Join-Path $work ("fleet-" + [guid]::NewGuid().ToString("N").Substring(0, 8))) -Records $Records }
$keeper = @{ id = "aaaaaaaa-0000-4000-8000-000000000001"; role = "master"; pane = "18"; instance = "zorb-instance-1" }
Set-Registry @(@{ id = "aaaaaaaa-0000-4000-8000-000000000002"; role = "orchestrator"; pane = "19"; instance = "zorb-instance-1" })
$nobody = Resolve-HordeDecisionWindowAttachment
Check ($nobody.attached -eq $false -and $nobody.reason -ceq "no session holds the role of warchief, so there is no terminal window to stand beside") "no session holds the role: not attached, and says so"
Set-Registry @($keeper, @{ id = "aaaaaaaa-0000-4000-8000-000000000003"; role = "master"; pane = "30"; instance = "zorb-instance-1" })
$two = Resolve-HordeDecisionWindowAttachment
Check ($two.attached -eq $false -and $two.reason -like "2 live sessions each say they are the warchief*") "two sessions hold it: not attached, and neither is chosen"
Set-Registry @($keeper)
$script:HordeHostWindowFinders.Clear()
$script:seatSeen = $null
Register-HordeHostWindowFinder -Name "zorbterm" -Find { param($Seat) $script:seatSeen = $Seat; return (New-HordeUnknown -Reason "two of the terminal's windows carry that title") }
$unsure = Resolve-HordeDecisionWindowAttachment
Check ($unsure.attached -eq $false -and $unsure.reason -ceq "zorbterm: two of the terminal's windows carry that title") "the terminal cannot prove one window: not attached, with the terminal's own reason"
Check ($script:seatSeen.pane -ceq "18" -and $script:seatSeen.instance -ceq "zorb-instance-1") "the terminal's adapter was handed the pane and the terminal the keeper's record names"
Register-HordeHostWindowFinder -Name "zorbterm" -Find { param($Seat) return (New-HordeKnown -Value ([pscustomobject]@{ handle = [long]70022; detail = "its one window" })) }
$beside = Resolve-HordeDecisionWindowAttachment
Check ($beside.attached -eq $true -and $beside.handle -eq 70022 -and $beside.reason -ceq "") "one session holds the role and its terminal proves one window: attached to exactly that window"
Check ((Resolve-HordeDecisionWindowAttachment -Hidden).attached -eq $false) "CONTROL: and still not when opened hidden"

Write-Host ""
Write-Host "--- the report file ---" -ForegroundColor Cyan
$reportPath = Join-Path $work "report.json"
$rs = New-HordeDecisionWindowState -ReportPath $reportPath -Attachment $beside
$rs.handle = 4242; $rs.title = "Open decisions: 3, 3 waiting"
Write-HordeDecisionWindowReport -State $rs
$first = [System.IO.File]::ReadAllText($reportPath) | ConvertFrom-Json
Check ($first.schemaVersion -eq 1 -and $first.pid -eq $PID -and $first.handle -eq 4242 -and $first.title -ceq "Open decisions: 3, 3 waiting" -and $first.attachment.attached -eq $true -and $first.attachment.target -eq 70022 -and $null -eq $first.rendered -and $rs.reportDue -eq $false) "the report says which process and window, the title, what it stands beside, and that the page has reported nothing yet"
[void](Ask $rs '{"v":1,"id":1,"request":"rendered","args":{"rows":3,"open":3,"closed":1,"waiting":3,"expanded":1,"entries":5,"written":2,"filter":"waiting","picked":"orc:B"}}')
[void](Ask $rs '{"v":1,"id":2,"request":"nonsense"}')
Write-HordeDecisionWindowReport -State $rs
$second = [System.IO.File]::ReadAllText($reportPath) | ConvertFrom-Json
Check ($second.rendered.rows -eq 3 -and $second.rendered.expanded -eq 1 -and $second.rendered.picked -ceq "orc:B" -and $second.reports -eq 1 -and $second.refused -eq 1 -and $second.secondsToFirstReport -ge 0) "written again over itself, it holds what the page then reported, and how many requests were refused"
Check (@(Get-ChildItem -LiteralPath $work -File | Where-Object { $_.Name -like "report.json*" }).Count -eq 1) "and no half-written copy is left beside it"
$none = New-HordeDecisionWindowState
Write-HordeDecisionWindowReport -State $none
Check ($none.reportPath -ceq "") "CONTROL: with no report asked for, none is written"

} finally {
    $script:HordeDecisionWindow = $null
    $env:HORDE_HOME = $keepHome; $env:WEZFLEET_ROOT = $keepFleet
    if ((Split-Path -Leaf $work) -match '\Ahorde-decisions-window-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's temp folder is removed"
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store under the user profile is exactly as it was before the suite"

Complete-HordeSuite -Success "the decisions window's page may ask five things, is refused everything else, and can change nothing"
