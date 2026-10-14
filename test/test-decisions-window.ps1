# DOES THE DECISIONS WINDOW'S COMPOSER KEEP ITS PROMISES, WITH NO WINDOW OPEN?
#
# decisions/Window.ps1 puts four parts together: a surface, a follower, a session's terminal window
# and the pages. Everything it decides is decided in functions that need no window, and this suite
# holds each of them: the module's settings; the closed list of six requests and three events; what
# the page is handed before it draws; the page's report of what it drew, held to its shape and its
# bounds; when the list is read again and when it is pushed; the watch's failure; a second open's
# "come forward"; when the window says it stands free; the report file; and what the composer and the
# page files must NOT hold, each such search with a control beside it.
#
# NOTHING OF THIS MACHINE IS READ. The home, the fleet's registry and the store are folders of this
# suite's own; who is running is a reading this suite made (core/SessionSeat.ps1 takes one); the
# terminal finders and the window followers that loaded with the composer are put aside and replaced
# by stand-ins, so no terminal is listed and no window is touched. The real window, the real follow
# and the real page are test/e2e/e2e-decisions-window.ps1 and the terminal host's own scenario.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-decisions-window-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$hordeHome = Join-Path $work "home"
$keepHome = $env:HORDE_HOME; $keepFleet = $env:WEZFLEET_ROOT
$env:HORDE_HOME = $hordeHome
$env:WEZFLEET_ROOT = Join-Path $work "no-fleet"
. (Join-Path $root "test\lib\WindowProbe.ps1")
. (Join-Path $root "decisions\Window.ps1")
# THE STAND-INS. Whatever finder and follower loaded with the composer is put aside for the length of
# the suite: a check that reached the real one would list a terminal or move a window.
$script:HordeHostWindowFinders.Clear()
$script:HordeWindowFollowers.Clear()
$script:followSays = "following"
$script:followAsked = New-Object System.Collections.ArrayList
$record = { param([string]$Verb) [void]$script:followAsked.Add($Verb); return (New-HordeWindowFollowRecord -State $script:followSays -Reason $(if ($script:followSays -ceq "following") { "" } else { "the stand-in says " + $script:followSays }) -Target 4242 -Companion 77 -Mode "floating" -Placed ([pscustomobject]@{ left = 10; top = 20; width = 320; height = 400 }) -Placements 1) }
Register-HordeWindowFollower -Name "zorb" -Applies { $true } -RealScale { [pscustomobject]@{ state = "already"; awareness = "per-monitor-v2"; realScale = "yes"; reason = "" } } -Rectangle { param($h) New-HordeUnknown -Reason "the stand-in reads no window" } -Start { param($t, $c, $m, $s) & $record "start" } -Update { param($place) & $record "update" } -Release { & $record "release" } -Stop { [void]$script:followAsked.Add("stop"); New-HordeWindowFollowRecord -State "none" }
$script:posted = New-Object System.Collections.ArrayList
$script:titles = New-Object System.Collections.ArrayList
$script:shown = 0
$script:captured = New-Object System.Collections.ArrayList
$window = [pscustomobject]@{ handle = [long]77; sync = $null; errors = (New-Object System.Collections.ArrayList)
    post = { param($Json) [void]$script:posted.Add($Json) }; setTitle = { param($Text) [void]$script:titles.Add($Text) }
    show = { $script:shown++ }; close = { }; capture = { param($Path) [void]$script:captured.Add($Path); return $true } }
function Ask { param($State, [string]$Request, $Arguments = @{}) $script:asked++; return (Invoke-HordeSurfaceRequest -Bridge $State.bridge -Text (ConvertTo-Json -InputObject ([ordered]@{ v = 1; id = $script:asked; request = $Request; args = $Arguments }) -Compress -Depth 6) -State $State -Window $window) }
$script:asked = 0
function Add-Question { param([int]$N, [string]$Group = "A group")
    $q = [ordered]@{ title = ("Should step " + $N + " of the plan go ahead as it is written?"); kind = "yes-no"; whatItIs = ("Step " + $N + " is ready."); recommendation = "yes"; group = $Group; askedBy = "Orc A"; waiting = @("Orc A") }
    $a = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $q }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("question " + $N + " was not added: " + $a.reason) } }
$defaults = (Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionWindowSettingsDeclaration) -Text $null).values

try {

Write-Host ""
Write-Host "--- every number a person might tune is one setting of the module ---" -ForegroundColor Cyan
$names = @($defaults.PSObject.Properties | ForEach-Object { $_.Name })
Check (($names -join ",") -ceq "role,changeQuietMs,listRereadMs,fleetReadMs,followCheckMs,pictureSettleMs,fontFamily,textPx,linePx,smallTextPx,foldedGroups,smallLinePx") ("the module declares twelve settings (" + ($names -join ",") + ")")
Check ($defaults.role -ceq "warchief" -and $defaults.changeQuietMs -eq 400 -and $defaults.listRereadMs -eq 30000 -and $defaults.fleetReadMs -eq 5000 -and $defaults.followCheckMs -eq 1000 -and $defaults.pictureSettleMs -eq 700) "their defaults: the warchief; 400 ms of gathered changes; the list read again after 30 s of silence; the fleet every 5 s; the follow every second; 700 ms of quiet before a picture"
Check ($defaults.fontFamily -ceq '"Segoe UI Variable Text", "Segoe UI", system-ui, sans-serif' -and $defaults.textPx -eq 14 -and $defaults.linePx -eq 22 -and $defaults.smallTextPx -eq 12 -and $defaults.smallLinePx -eq 18) "and the letters: the family list, 14 on 22 and 12 on 18"
Check ((Get-HordeDecisionWindowSettings -HordeHome "C:\h").path -ceq "C:\h\settings\decisions-window.json") "they are read from settings\decisions-window.json under Horde's home"
$person = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionWindowSettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"role":"orc","textPx":16,"fontFamily":"Georgia, serif"}}'
Check ($person.state -ceq "read" -and $person.values.role -ceq "orc" -and $person.values.textPx -eq 16 -and $person.values.fontFamily -ceq "Georgia, serif") "a person's file moves them: another role, larger letters, another family"
$outOfRange = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionWindowSettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"textPx":16,"listRereadMs":5}}'
Check ($outOfRange.state -ceq "refused" -and $null -eq $outOfRange.values -and @($outOfRange.findings).Count -eq 1 -and $outOfRange.findings[0] -like "*listRereadMs*") "a value out of range refuses the file by name, and no default is used in its place"
$notRole = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionWindowSettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"role":"captain"}}'
Check ($notRole.state -ceq "refused" -and @($notRole.findings).Count -eq 1 -and $notRole.findings[0] -like "*'role'*") "a role that is not one of the role table's refuses the file, by name"

Write-Host ""
Write-Host "--- what is told is notify's record under the home, and nothing a caller names ---" -ForegroundColor Cyan
Check (-not (Get-Command Open-HordeDecisionWindow).Parameters.ContainsKey("ToldMarks")) "open takes no file of announced messages: there is one, and notify keeps it"
$composer = [System.IO.File]::ReadAllText((Join-Path $root "decisions\Window.ps1"))
Check ($composer.Contains('$toldPath = Get-HordeDecisionNotifyRecordPath -HordeHome $hordeHome') -and $composer.Contains('$record = Read-HordeDecisionNotifyRecord -Path $Path')) "open hands the window notify's told record under the home, read by notify's own reader"
Check ((Get-HordeDecisionNotifySettingsDeclaration).module -ceq "decisions-notify" -and (Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionNotifySettingsDeclaration) -Text $null).values.startWithWindow -eq $true) "and notify's own settings, read by open, start it beside the window unless a person turns that off"

Write-Host ""
Write-Host "--- a settings file that fails a check refuses the window, every finding said ---" -ForegroundColor Cyan
$ok = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionWindowSettingsDeclaration) -Text $null
Check ((Get-HordeDecisionWindowSettingsRefusal -Answers @($ok, $person, $ok, $ok)) -ceq "") "four answers that are the defaults or read refuse nothing"
$two = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionWindowSettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"listRereadMs":5,"colour":"red"}}' -File 'C:\h\settings\decisions-window.json'
$said = Get-HordeDecisionWindowSettingsRefusal -Answers @($ok, $two, $ok, $notRole)
$saidLines = @($said -split [regex]::Escape([Environment]::NewLine))
Check ($saidLines.Count -eq 3 -and $saidLines[0] -like "the settings file 'C:\h\settings\decisions-window.json' of decisions-window is refused: *listRereadMs*" -and $saidLines[1] -like "*'colour'*" -and $saidLines[2] -like "*'role'*") ("every finding of every refused answer, in order, one to a line, each naming its file and key (" + ($saidLines -join " / ") + ")")
Check ((Get-HordeDecisionWindowSettingsRefusal -Answers @($ok, [pscustomobject]@{ values = $ok.values })) -like "*neither read nor the defaults*") "an answer with no state is no answer, and refuses"
Check ((Get-HordeDecisionWindowSettingsRefusal -Answers @($ok, [pscustomobject]@{ state = "none"; findings = @() })) -ceq "") "the finders' answer that they have no settings at all refuses nothing"

Write-Host ""
Write-Host "--- a refused file of the session-window finder refuses open before anything starts ---" -ForegroundColor Cyan
# The finder is a stand-in that declares settings and finds them refused; the finding is the settings
# module's own sentence. Anything open does past its settings check is replaced by a marker that
# throws, so a check that did not refuse cannot start a helper, an engine or a window.
$script:finderSettingsAsked = New-Object System.Collections.ArrayList
Register-HordeHostWindowFinder -Name "zorb" -Find { param($Seat) return (New-HordeUnknown -Reason "not asked here") } -Settings { param($HordeHome) [void]$script:finderSettingsAsked.Add($HordeHome); return [pscustomobject]@{ state = "refused"; values = $null; findings = [string[]]@("the settings file 'C:\h\settings\zorb-window.json' of zorb-window is refused: its key 'attempts' must be 1 to 10"); path = "C:\h\settings\zorb-window.json" } }
$openRefused = & {
    function Enable-HordeWindowFollowRealScale { throw "PAST THE SETTINGS CHECK" }
    try { Open-HordeDecisionWindow -Hidden | Out-Null; "returned" } catch { "" + $_.Exception.Message }
}
Check ($openRefused -clike "the decisions window was not opened, because a settings file is refused:*" -and $openRefused -clike "*the settings file 'C:\h\settings\zorb-window.json' of zorb-window is refused: its key 'attempts'*") ("open throws the finder's finding as it throws the window's own (" + $openRefused + ")")
Check (($script:finderSettingsAsked -join ",") -ceq $hordeHome) "the finder was asked about the home open reads every other settings file from"
Check (-not (Test-Path -LiteralPath (Join-Path $hordeHome "cache"))) "and nothing was made under the home: no engine profile, no window"
Register-HordeHostWindowFinder -Name "zorb" -Find { param($Seat) return (New-HordeUnknown -Reason "not asked here") } -Settings { param($HordeHome) return [pscustomobject]@{ state = "defaults"; values = $null; findings = [string[]]@(); path = "" } }
$openPast = & {
    function Enable-HordeWindowFollowRealScale { throw "PAST THE SETTINGS CHECK" }
    try { Open-HordeDecisionWindow -Hidden | Out-Null; "returned" } catch { "" + $_.Exception.Message }
}
Check ($openPast -ceq "PAST THE SETTINGS CHECK") ("CONTROL: a finder whose settings are the defaults lets open go on past the check (" + $openPast + ")")
# Notify's settings are read by open too, because open starts notify beside the window.
$notifyFile = Join-Path $hordeHome "settings\decisions-notify.json"
New-Item -ItemType Directory -Path (Split-Path -Parent $notifyFile) -Force | Out-Null
[System.IO.File]::WriteAllText($notifyFile, '{"schemaVersion":1,"settings":{"quietSeconds":-1}}')
$openNotify = & {
    function Enable-HordeWindowFollowRealScale { throw "PAST THE SETTINGS CHECK" }
    try { Open-HordeDecisionWindow -Hidden | Out-Null; "returned" } catch { "" + $_.Exception.Message }
}
Remove-Item -LiteralPath $notifyFile
Check ($openNotify -clike "the decisions window was not opened, because a settings file is refused:*decisions-notify*quietSeconds*") ("a refused settings file of notify, which open starts, refuses the window before anything starts (" + $openNotify + ")")
$script:HordeHostWindowFinders.Clear()
Check ((Get-HordeDecisionWindowName -HordeHome "C:\H\") -ceq (Get-HordeDecisionWindowName -HordeHome "c:\h") -and (Get-HordeDecisionWindowName -HordeHome "C:\h") -cmatch '\Ahorde-decisions-window-[0-9a-f]{16}\z' -and (Get-HordeDecisionWindowName -HordeHome "C:\h2") -cne (Get-HordeDecisionWindowName -HordeHome "C:\h")) "the one window of a home is known by a name ending in 16 hex of the home's fingerprint, the same however the path is written and another for another home"
Check ((Get-HordeDecisionWindowDataFolder -HordeHome "C:\h") -ceq "C:\h\cache\decisions-window") "the surface's own files are kept under the home's cache, by the module's name"

Write-Host ""
Write-Host "--- the closed list: six requests, three events ---" -ForegroundColor Cyan
for ($n = 1; $n -le 3; $n++) { Add-Question $n }
$state = New-HordeDecisionWindowState -ReportPath (Join-Path $work "report.json") -Settings $defaults -Findings @("a finding of the suite's") -View (ConvertTo-HordeDecisionWindowView -Unfold "2,3" -Orc "B")
$script:HordeDecisionWindow = $state
Check ((@($state.bridge.requests.Keys) -join ",") -ceq "setup,kinds,list,fleet,attachment,report,say,say-part,act,hand-back") ("the page may ask for ten things: say, say-part and act write (test/test-decisions-window-say.ps1 holds say; act is his park or unpark), the last hands the keyboard back (" + (@($state.bridge.requests.Keys) -join ",") + ")")
# ESCAPE: hand-back. Standing free, the follow port is NOT asked; followed, it is, and what it said is handed on and counted.
$script:handAsked = 0
$handState = New-HordeDecisionWindowState -Settings $defaults
$freeAnswer = Invoke-HordeDecisionWindowHandBack -State $handState -Hand { $script:handAsked++; [pscustomobject]@{ state = "handed"; reason = "" } }
Check ($freeAnswer.handed -eq $false -and $freeAnswer.state -ceq "none" -and $freeAnswer.reason -clike "it stands free*" -and $script:handAsked -eq 0 -and $handState.handBacks -eq 1 -and $handState.handBacksDone -eq 0 -and $handState.handBackLast -ceq "none") "hand-back from a window that stands free does nothing: the follow port is not asked, and the answer says why"
$viaBridge = (Ask $handState "hand-back").reply | ConvertFrom-Json
Check ($viaBridge.ok -eq $true -and $viaBridge.value.handed -eq $false -and $viaBridge.value.state -ceq "none" -and $handState.handBacks -eq 2 -and @($script:followAsked | Where-Object { $_ -ceq "hand" }).Count -eq 0) "asked through the bridge it is the same answer, and the stand-in follower was asked nothing"
$handState.followed = $true
$done = Invoke-HordeDecisionWindowHandBack -State $handState -Hand { $script:handAsked++; [pscustomobject]@{ state = "handed"; reason = "" } }
Check ($done.handed -eq $true -and $done.state -ceq "handed" -and $script:handAsked -eq 1 -and $handState.handBacks -eq 3 -and $handState.handBacksDone -eq 1 -and $handState.handBackLast -ceq "handed") "from a window that is followed the port is asked once, and handed is handed on and counted"
$no = Invoke-HordeDecisionWindowHandBack -State $handState -Hand { [pscustomobject]@{ state = "refused"; reason = "the system said no" } }
Check ($no.handed -eq $false -and $no.state -ceq "refused" -and $no.reason -ceq "the system said no" -and $handState.handBacksDone -eq 1 -and $handState.handBackLast -ceq "refused" -and $handState.handBackReason -ceq "the system said no") "a refusal is handed on in the port's own words, and is not counted as handed"
$broke = Invoke-HordeDecisionWindowHandBack -State $handState -Hand { throw "it broke" }
Check ($broke.handed -eq $false -and $broke.state -ceq "unavailable" -and $broke.reason -clike "*it broke" -and $handState.handBacks -eq 5) "a port that throws is answered as unavailable, with what it said: the handler never throws"
$viaPort = Invoke-HordeDecisionWindowHandBack -State $handState
Check ($viaPort.handed -eq $false -and $viaPort.state -ceq "unavailable" -and $viaPort.reason -clike "zorb:*no way to hand the keyboard*") ("with no stand-in it asks the follow port itself, and a follower that cannot hand the keyboard over is said by name (" + $viaPort.reason + ")")
Check ((@($state.bridge.events) -join ",") -ceq "list-changed,fleet-changed,attachment-changed,probe,said") "and may be pushed five: the three changes, a check's steps, and the outcome of a save the helper made"
$setup = (Ask $state "setup").reply | ConvertFrom-Json
Check ($setup.ok -eq $true -and $setup.value.look.fontFamily -ceq $defaults.fontFamily -and $setup.value.look.textPx -eq 14 -and $setup.value.look.linePx -eq 22 -and $setup.value.look.smallTextPx -eq 12 -and $setup.value.look.smallLinePx -eq 18) "setup hands the page its letters: the family and the four sizes, from the settings"
Check ($setup.value.report.lines -eq 400 -and $setup.value.report.subLines -eq 200 -and $setup.value.report.fleetRows -eq 80 -and $setup.value.report.lineChars -eq 400 -and $setup.value.report.textChars -eq 2000 -and $setup.value.report.chars -eq 60000 -and $setup.value.report.quietMs -eq 60) "the bounds of its report: 400 lines, 200 sub-lines, 80 fleet lines, 400 characters of a line, 60,000 in all"
Check ((@($setup.value.view.unfold) -join ",") -ceq "2,3" -and $setup.value.view.fleetOpen -eq $true -and $setup.value.view.pick -ceq "B") "what to show first: questions 2 and 3 unfolded, the fleet line unfolded with Orc B picked"
Check ((@($setup.value.findings) -join "|") -ceq "a finding of the suite's") "and what was wrong in the settings files, to be said on the page"
$tight = New-HordeDecisionWindowBridge -SurfaceSettings (Read-HordeModuleSettingsText -Declaration (Get-HordeSurfaceSettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"messageChars":20000}}')
Check ((Get-HordeDecisionWindowReportBounds -Bridge $tight).chars -eq 18976 -and (Get-HordeDecisionWindowReportBounds -Bridge $state.bridge).chars -eq 60000) "where a person's surface allows a message of 20,000 characters, the report's most is that less its envelope, and never more than 60,000"
$kinds = (Ask $state "kinds").reply | ConvertFrom-Json
$direct = ConvertTo-HordeAnswerRecord -Answer (Invoke-HordeDecision -Operation "kinds" -Request @{})
Check ($kinds.ok -eq $true -and (ConvertTo-Json $kinds.value.value -Depth 8 -Compress) -ceq (ConvertTo-Json $direct.value -Depth 8 -Compress)) "kinds is the kinds operation's answer, handed on as it came"
$list = (Ask $state "list").reply | ConvertFrom-Json
Check ($list.ok -eq $true -and $list.value.state -ceq "known" -and @($list.value.value.questions).Count -eq 3 -and $state.title -ceq "Open decisions: 3, 3 waiting" -and $script:titles[$script:titles.Count - 1] -ceq $state.title) "list is the list operation's, every state, and the window's title follows its counts"
$att = (Ask $state "attachment").reply | ConvertFrom-Json
Check ($att.ok -eq $true -and $att.value.attached -eq $false) "attachment says whether the window stands beside a terminal window"
$before = [int]$state.bridge.refused
foreach ($other in @("show", "rendered", "close", "add", "update", "picture", "capture")) { [void](Ask $state $other) }
Check ($state.bridge.refused -eq $before + 7) "anything else is refused and counted: a page cannot add, close, change or picture anything"
$src = [System.IO.File]::ReadAllText((Join-Path $root "decisions\Window.ps1"))
$operations = @([regex]::Matches($src, 'Get-HordeDecisionWindowRecord -Operation "([a-z-]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Check (($operations -join ",") -ceq "kinds,list") "the composer asks the decisions operations for the list and the kinds, and for nothing else"
$reads = 'Get-HordeDecisionRecords|ConvertTo-HordeDecisionState|Add-HordeDecisionRecord|Get-ChildItem|Get-Content|\*\.json'
# The one file it opens itself is not the store's: a check's steps, read whole from the path the command
# was given. The told record is notify's, read by notify's reader (decisions/Notify.ps1).
$opened = @([regex]::Matches($src, '(?m)^.*ReadAllText.*$') | ForEach-Object { $_.Value })
Check (-not ($src -match $reads) -and $opened.Count -eq 1 -and @($opened | Where-Object { $_ -notmatch 'ReadAllText\(\$Path, ' }).Count -eq 0) "and reads no record of the store itself: no listing of it, no name of a record's file, and the only file it opens is the one it was handed by path"
Check ([System.IO.File]::ReadAllText((Join-Path $root "decisions\Store.ps1")) -match $reads) "CONTROL: the same search finds such a read in the store's own file, so finding none in the composer means something"
$platform = 'HordeWindows|platform\\windows|user32|SetForegroundWindow'
Check (-not ($src -match $platform)) "the composer calls no function of a platform by name: the follower and the surface are asked through their ports"
Check ([System.IO.File]::ReadAllText((Join-Path $root "platform\windows\WindowFollow.ps1")) -match $platform) "CONTROL: the same search finds such a call in the platform's own follower"

Write-Host ""
Write-Host "--- what the page says it drew is held to its shape and its bounds ---" -ForegroundColor Cyan
function Drawn { param([scriptblock]$Change = $null)
    $d = [ordered]@{ v = 1; draws = 2; counts = [ordered]@{ open = 2; waiting = 1; other = 0 }
        headings = @([ordered]@{ t = "__proto__"; count = 2; folded = $false })
        lines = @([ordered]@{ n = "1"; t = "Is the first question drawn?"; s = " - Recommended: yes"; g = 0; open = $true; dim = $false }, [ordered]@{ n = "2"; t = "And the second?"; s = ""; g = 0; open = $false; dim = $true })
        sub = @([ordered]@{ n = "1.1"; t = "What it is: a question" })
        fleet = [ordered]@{ open = $false; picked = ""; head = "Fleet: A blocked"; rows = @("Orc A (a lane): doing. Last finished: that."); entries = 1; written = 1; notRead = 0 }
        notice = ""; foot = "Read-only."
        text = [ordered]@{ fontPx = 14; linePx = 22; weight = "400"; smallFontPx = 12; smallLinePx = 18; ratio = 1.5; family = "x" }
        left = [ordered]@{ lines = 0; sub = 0; fleetRows = 0 } }
    if ($null -ne $Change) { & $Change $d }
    return (ConvertTo-Json -InputObject $d -Depth 8 -Compress) }
$good = ConvertFrom-HordeDecisionWindowDrawn -Text (Drawn)
Check ($good.ok -eq $true -and @($good.value.lines).Count -eq 2 -and $good.value.lines[0].n -ceq "1" -and $good.value.lines[0].t -ceq "Is the first question drawn?" -and $good.value.headings[0].t -ceq "__proto__" -and $good.value.text.ratio -eq 1.5) "a report of two question lines under one heading is taken as it was sent: each line's number and text, the heading, the letters"
Check ((ConvertFrom-HordeDecisionWindowDrawn -Text (Drawn { param($d) $d.lines = @(); $d.sub = @(); $d.headings = @(); $d.text.fontPx = $null; $d.text.linePx = $null })).ok -eq $true) "CONTROL: an empty page - no lines, and so no letters measured - is a report too"
$refused = @(
    @{ what = "text that is not JSON"; text = "{not json" }
    @{ what = "a list where the object should be"; text = "[1,2]" }
    @{ what = "another version"; text = (Drawn { param($d) $d.v = 2 }) }
    @{ what = "no lines at all"; text = (Drawn { param($d) $d.Remove("lines") }) }
    @{ what = "lines that are not a list"; text = (Drawn { param($d) $d.lines = "all of them" }) }
    @{ what = "one good line given bare, not in a list"; text = (Drawn { param($d) $d.lines = [ordered]@{ n = "1"; t = "q"; s = ""; g = 0; open = $false; dim = $false } }) }
    @{ what = "no counts"; text = (Drawn { param($d) $d.Remove("counts") }) }
    @{ what = "no account of what was left out"; text = (Drawn { param($d) $d.Remove("left") }) }
    @{ what = "more lines than the bound"; text = (Drawn { param($d) $d.lines = @(1..401 | ForEach-Object { [ordered]@{ n = "$_"; t = "q"; s = ""; g = 0; open = $false; dim = $false } }) }) }
    @{ what = "a line longer than the bound"; text = (Drawn { param($d) $d.lines[0].t = ("x" * 401) }) }
    @{ what = "a line whose number is words"; text = (Drawn { param($d) $d.lines[0].n = "one" }) }
    @{ what = "a line with no number"; text = (Drawn { param($d) $d.lines[0].Remove("n") }) }
    @{ what = "a line that does not say whether it is unfolded"; text = (Drawn { param($d) $d.lines[1].open = "no" }) }
    @{ what = "a line that does not say whether it is dimmed"; text = (Drawn { param($d) $d.lines[1].Remove("dim") }) }
    @{ what = "more sub-lines than the bound"; text = (Drawn { param($d) $d.sub = @(1..201 | ForEach-Object { [ordered]@{ n = "1.$_"; t = "s" } }) }) }
    @{ what = "more fleet lines than the bound"; text = (Drawn { param($d) $d.fleet.rows = @(1..81 | ForEach-Object { "row" }) }) }
    @{ what = "a fleet line that is not text"; text = (Drawn { param($d) $d.fleet.rows = @(7, 8) }) }
    @{ what = "a notice longer than the bound"; text = (Drawn { param($d) $d.notice = ("n" * 2001) }) }
    @{ what = "a letter size that is words"; text = (Drawn { param($d) $d.text.fontPx = "large" }) }
    @{ what = "no scale"; text = (Drawn { param($d) $d.text.Remove("ratio") }) }
)
foreach ($case in $refused) {
    # A throw is a failed check here, not a stopped suite: the function is promised to answer.
    $r = $null
    try { $r = ConvertFrom-HordeDecisionWindowDrawn -Text $case.text } catch { $r = [pscustomobject]@{ ok = "threw"; value = $null; reason = ("THREW: " + $_.Exception.Message) } }
    Check ($r.ok -eq $false -and $null -eq $r.value -and $r.reason -like "the page's report *") ("refused: " + $case.what + " (" + $r.reason + ")")
}
$sent = Ask $state "report" @{ text = (Drawn) }
Check ((($sent.reply | ConvertFrom-Json).ok -eq $true) -and $state.reports -eq 1 -and $null -ne $state.drawn -and $state.drawn.lines[1].t -ceq "And the second?" -and $null -ne $state.lastReportAt) "through the bridge, a good report is kept as what the window shows, and counted"
$badSent = Ask $state "report" @{ text = (Drawn { param($d) $d.v = 9 }) }
Check ((($badSent.reply | ConvertFrom-Json).ok -eq $false) -and $state.reports -eq 1 -and $state.reportsRefused -eq 1 -and $state.drawn.lines[1].t -ceq "And the second?") "a report that breaks its shape is answered as a failure and counted, and the last good one stays"
$long = Ask $state "report" @{ text = ("x" * 60001) }
Check ($long.refused -like "*'text' is 60001 characters, more than the 60000 it may be*") "and one over 60,000 characters is refused by the bridge before any handler sees it"

Write-Host ""
Write-Host "--- what the reader is shown first ---" -ForegroundColor Cyan
$plain = ConvertTo-HordeDecisionWindowView
Check (@($plain.unfold).Count -eq 0 -and $plain.fleetOpen -eq $false -and $plain.pick -ceq "") "with no flag: nothing unfolded, the fleet line folded, no Orc picked"
foreach ($bad in @("0", "3,", "a", "3;7", "-1", "3, 7", "1234567890")) {
    $threw = ""; try { [void](ConvertTo-HordeDecisionWindowView -Unfold $bad) } catch { $threw = $_.Exception.Message }
    Check ($threw -like "-Unfold takes question numbers*") ("-Unfold '" + $bad + "' is refused in words")
}
foreach ($bad in @("b", "BB", "7", "Orc B")) {
    $threw = ""; try { [void](ConvertTo-HordeDecisionWindowView -Orc $bad) } catch { $threw = $_.Exception.Message }
    Check ($threw -like "-Orc takes the one capital letter*") ("-Orc '" + $bad + "' is refused in words")
}

Write-Host ""
Write-Host "--- the list is pushed when it changed, and read again when nothing was heard ---" -ForegroundColor Cyan
$t0 = [datetime]::UtcNow
$script:posted.Clear()
$state.dirtyAt = $t0; $state.listReadAt = $t0
Invoke-HordeDecisionWindowTick -Window $window -State $state -Now $t0.AddMilliseconds(399)
Check ($null -ne $state.dirtyAt -and $state.pushes -eq 0) "a change heard 399 ms ago is still being gathered"
Invoke-HordeDecisionWindowTick -Window $window -State $state -Now $t0.AddMilliseconds(400)
Check ($null -eq $state.dirtyAt -and $state.pushes -eq 0 -and @($script:posted | Where-Object { $_ -like '*"event":"list-changed"*' }).Count -eq 0) "after 400 ms the list is read again; it is the list the page has, so nothing is pushed"
Add-Question 4
$state.dirtyAt = $t0.AddSeconds(1)
Invoke-HordeDecisionWindowTick -Window $window -State $state -Now $t0.AddSeconds(2)
$pushed = @($script:posted | Where-Object { $_ -like '*"event":"list-changed"*' })
Check ($state.pushes -eq 1 -and $pushed.Count -eq 1 -and @(($pushed[0] | ConvertFrom-Json).value.value.questions).Count -eq 4 -and $state.title -ceq "Open decisions: 4, 4 waiting") "a fourth question, and a change heard: the new list is pushed once, whole, and the title follows"
Add-Question 5
$silent = $state.listReadAt
Invoke-HordeDecisionWindowTick -Window $window -State $state -Now $silent.AddMilliseconds(29999)
Check ($state.rereads -eq 0 -and $state.pushes -eq 1) "a fifth question that no change was heard for: 29,999 ms after the last read, nothing yet"
Invoke-HordeDecisionWindowTick -Window $window -State $state -Now $silent.AddMilliseconds(30000)
Check ($state.rereads -eq 1 -and $state.pushes -eq 2 -and $state.title -ceq "Open decisions: 5, 5 waiting") "after 30 s of silence the list is read all the same, and the question nobody announced is pushed"
$quick = New-HordeDecisionWindowState -Settings (Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionWindowSettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"listRereadMs":2000,"changeQuietMs":50}}').values
$quick.listReadAt = $t0
Invoke-HordeDecisionWindowTick -Window $window -State $quick -Now $t0.AddMilliseconds(2000)
Check ($quick.rereads -eq 1) "both waits are the settings': with the silence set to 2 s, the list is read again after 2 s"
$state.watchFailed = $true
Set-HordeDecisionWindowWatchFailed
Check ($state.watchFailures -eq 1 -and $null -ne $state.dirtyAt) "a watch that reports its own failure is counted, and the list is to be read again: what it missed cannot be known"
Invoke-HordeDecisionWindowTick -Window $window -State $state -Now ([datetime]::UtcNow)
Check ($state.watchFailed -eq $false -and $null -eq $state.watcher) "on the next tick that watch is ended, for another to be started (none is, here: there is no window thread to hear it on)"
Check ((Start-HordeDecisionWindowWatch -State $state -Sync $null) -eq $false) "a watch is never started with nothing to bring its events to the window's thread"
Check (-not ($src -match 'FileSystemWatcher\([^)]*,')) "the watch names the store's folder and no pattern of file names: what a record's file is called is the store's business"
Check ('New-Object System.IO.FileSystemWatcher($State.storeRoot, "*.json")' -match 'FileSystemWatcher\([^)]*,') "CONTROL: the same search finds the pattern the earlier composer watched by"

Write-Host ""
Write-Host "--- a second open asks the first to come forward ---" -ForegroundColor Cyan
$state.showEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset)
Invoke-HordeDecisionWindowTick -Window $window -State $state -Now ([datetime]::UtcNow)
Check ($script:shown -eq 0 -and $state.shows -eq 0) "CONTROL: with nothing asked, the window is not brought forward"
[void]$state.showEvent.Set()
Invoke-HordeDecisionWindowTick -Window $window -State $state -Now ([datetime]::UtcNow)
Invoke-HordeDecisionWindowTick -Window $window -State $state -Now ([datetime]::UtcNow)
Check ($script:shown -eq 1 -and $state.shows -eq 1) "asked once, the first window asks its surface to show it once, and counts that it was asked"
$state.showEvent.Dispose(); $state.showEvent = $null

Write-Host ""
Write-Host "--- attached, or saying why not ---" -ForegroundColor Cyan
Check ((Resolve-HordeDecisionWindowAttachment -Role "warchief" -Hidden).reason -ceq "it was opened hidden, and a hidden window stands beside nothing") "hidden: beside nothing, and no record is read to find that out"
Check ((Resolve-HordeDecisionWindowAttachment -Role "warchief" -OffScreen).reason -ceq "it was opened where no screen is, and stands beside nothing there") "where no screen is: the same"
$noFleet = Resolve-HordeDecisionWindowAttachment -Role "warchief"
Check ($noFleet.attached -eq $false -and $noFleet.reason -like "the session records could not all be read, so which session is the warchief cannot be told: there is no registry sessions directory*") "a machine with no fleet's records at all: not attached, in the record reader's own words"
[void](New-HordeProbeRegistry -Root $env:WEZFLEET_ROOT -Records @())
$nobody = Resolve-HordeDecisionWindowAttachment -Role "warchief"
Check ($nobody.attached -eq $false -and $nobody.reason -ceq "no session holds the role of warchief, so there is no terminal window to stand beside") ("an empty registry: no session holds the role, and it says so (" + $nobody.reason + ")")
$sid = "aaaaaaaa-0000-4000-8000-0000000000d1"
[void](New-HordeProbeRegistry -Root $env:WEZFLEET_ROOT -Records @(@{ id = $sid; role = "master"; pane = "5"; instance = "zorb-instance-1"; lastSeen = [datetime]::UtcNow.ToString("o") }))
$identity = [pscustomobject]@{ verifiedLive = (New-HordeKnown -Value @($sid)); records = @{ $sid = [pscustomobject]@{ processCheck = "verified"; fields = @{ procStart = (New-HordeKnown -Value ([datetime]::UtcNow.AddHours(-1).ToFileTimeUtc())) } } } }
$noFinder = Resolve-HordeDecisionWindowAttachment -Role "warchief" -Identity $identity
Check ($noFinder.attached -eq $false -and $noFinder.reason -ceq "no terminal adapter that can find a session's window is loaded") "a holder that is running, and no adapter to name its window: not attached, with that reason"
$script:finderSaw = $null
Register-HordeHostWindowFinder -Name "zorb" -Find { param($Seat) $script:finderSaw = $Seat; return (New-HordeUnknown -Reason "two windows fit, and one is never chosen") }
$unsure = Resolve-HordeDecisionWindowAttachment -Role "warchief" -Identity $identity
Check ($unsure.attached -eq $false -and $unsure.reason -ceq "zorb: two windows fit, and one is never chosen" -and $script:finderSaw.pane -ceq "5" -and $script:finderSaw.instance -ceq "zorb-instance-1") "an adapter that cannot prove the window: not attached, in the adapter's own words; it was asked about the seat the record names"
Register-HordeHostWindowFinder -Name "zorb" -Find { param($Seat) return (New-HordeKnown -Value ([pscustomobject]@{ handle = [long]4242; detail = "the stand-in's one window" })) }
$proven = Resolve-HordeDecisionWindowAttachment -Role "warchief" -Identity $identity
Check ($proven.attached -eq $true -and $proven.handle -eq 4242 -and $proven.reason -ceq "") "a proven window: attached, to that handle"
$stale = Resolve-HordeDecisionWindowAttachment -Role "warchief" -Identity ([pscustomobject]@{ verifiedLive = (New-HordeKnown -Value @()); records = @{} })
Check ($stale.attached -eq $false -and $stale.reason -like "the warchief's session ($sid) is not proven to be running*") "a holder whose session is not running: not attached, though the adapter would name a window"
Check ((Resolve-HordeDecisionWindowAttachment -Role "orc" -Identity $identity).reason -ceq "no session holds the role of orc, so there is no terminal window to stand beside") "the role is the caller's to name: asked for another, it looks for that one"

$attached = New-HordeDecisionWindowState -Attachment $proven -Settings $defaults -FollowSettings (Get-HordeWindowFollowSettings -HordeHome $hordeHome).values
$script:HordeDecisionWindow = $attached
$script:followAsked.Clear(); $script:posted.Clear()
Invoke-HordeDecisionWindowOpened -Window $window -State $attached
Check ($attached.followed -eq $true -and ($script:followAsked -join ",") -ceq "start" -and $attached.handle -eq 77) "opened beside a proven window, the composer asks the follow port to follow it, once"
$tick = [datetime]::UtcNow.AddSeconds(5)
Invoke-HordeDecisionWindowTick -Window $window -State $attached -Now $tick
Invoke-HordeDecisionWindowTick -Window $window -State $attached -Now $tick.AddMilliseconds(999)
Check ((@($script:followAsked | Where-Object { $_ -ceq "update" })).Count -eq 1 -and $attached.followed -eq $true) "the follow is asked again once a second, not on every tick"
$script:followSays = "lost"
Invoke-HordeDecisionWindowTick -Window $window -State $attached -Now $tick.AddMilliseconds(1000)
$freed = @($script:posted | Where-Object { $_ -like '*"event":"attachment-changed"*' })
Check ($attached.lost -eq $true -and $attached.followed -eq $false -and $attached.attachment.attached -eq $false -and $attached.attachment.reason -ceq "the terminal window it stood beside is gone, and it stands free where it was" -and $freed.Count -eq 1 -and ($freed[0] | ConvertFrom-Json).value.attached -eq $false) "when the follower says the other window is lost, the window says it stands free, to the page, once"
Check (-not ($script:followAsked -contains "release") -and -not ($script:followAsked -contains "stop")) "and does nothing else to the window: the follower has already set it free"
Invoke-HordeDecisionWindowTick -Window $window -State $attached -Now $tick.AddSeconds(9)
Check ((@($script:followAsked | Where-Object { $_ -ceq "update" })).Count -eq 2) "a window that stands free is not asked about again"
$script:followSays = "failed"
$refusedFollow = New-HordeDecisionWindowState -Attachment $proven -Settings $defaults
Invoke-HordeDecisionWindowOpened -Window $window -State $refusedFollow
Check ($refusedFollow.followed -eq $false -and $refusedFollow.attachment.attached -eq $false -and $refusedFollow.attachment.reason -ceq "the terminal window was found and could not be followed: the stand-in says failed") "a follow that could not be made: it stands free and says what refused"
$script:followSays = "following"
Invoke-HordeDecisionWindowClosed -Window $window -State $attached
Check ($script:followAsked[$script:followAsked.Count - 1] -ceq "stop") "as the window closes, the follow is stopped"

Write-Host ""
Write-Host "--- the fleet line's data, and the picture ---" -ForegroundColor Cyan
$script:HordeDecisionWindow = $state
$script:posted.Clear()
$fleetHome = Join-Path $work "orcs"; New-Item -ItemType Directory -Path (Join-Path $fleetHome "alpha") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $hordeHome "settings") -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $hordeHome "settings\fleet.json"), ('{"schemaVersion":1,"settings":{"statusFolder":"' + $fleetHome.Replace("\", "\\") + '"}}'))
$fleetAnswer = (Ask $state "fleet").reply | ConvertFrom-Json
Check ($fleetAnswer.ok -eq $true -and $fleetAnswer.value.state -ceq "read" -and @($fleetAnswer.value.orcs).Count -eq 1 -and $fleetAnswer.value.notRead -eq 0) "fleet is the fleet reader's answer, from the folder the fleet module's setting names"
$due = [datetime]::UtcNow.AddSeconds(60); $state.fleetDueAt = $due
Invoke-HordeDecisionWindowTick -Window $window -State $state -Now $due
Check (@($script:posted | Where-Object { $_ -like '*"event":"fleet-changed"*' }).Count -eq 0 -and $state.fleetDueAt -eq $due.AddMilliseconds(5000)) "read again when it is due and unchanged: nothing is pushed, and the next read is 5 s on"
[System.IO.File]::WriteAllText((Join-Path $fleetHome "alpha\status.txt"), "horde-orc-status 1`norc: A`nlane: a lane`ndoing: Something`nfinished: Something else`nblocked: no`n")
Invoke-HordeDecisionWindowTick -Window $window -State $state -Now $due.AddMilliseconds(5000)
Check (@($script:posted | Where-Object { $_ -like '*"event":"fleet-changed"*' }).Count -eq 1) "an Orc wrote its record: the new status is pushed, once"
# THE SEVENTH LINE IS PART OF WHAT THE LINE IS COMPARED BY: an Orc that only adds or changes what it
# waits on, the six lines before it as they were, has written something new for the fleet line.
$sixLines = "horde-orc-status 1`norc: A`nlane: a lane`ndoing: Something`nfinished: Something else`nblocked: no`n"
$waitSig0 = (Get-HordeDecisionWindowFleet).signature
[System.IO.File]::WriteAllText((Join-Path $fleetHome "alpha\status.txt"), ($sixLines + "waiting on: the founder, since 2026-10-13 09:30`n"))
$waitSig1 = (Get-HordeDecisionWindowFleet).signature
[System.IO.File]::WriteAllText((Join-Path $fleetHome "alpha\status.txt"), ($sixLines + "waiting on: nothing, since 2026-10-14 08:00`n"))
$waitSig2 = (Get-HordeDecisionWindowFleet).signature
[System.IO.File]::WriteAllText((Join-Path $fleetHome "alpha\status.txt"), $sixLines)
Check ($waitSig1 -cne $waitSig0 -and $waitSig2 -cne $waitSig1 -and $waitSig1 -clike "*|the founder, since 2026-10-13 09:30|*") "a record that adds a waiting-on line, or changes only that line, changes what the fleet line is compared by"
$pic = New-HordeDecisionWindowState -PicturePath (Join-Path $work "p.png") -Settings $defaults
$now = [datetime]::UtcNow
Invoke-HordeDecisionWindowTick -Window $window -State $pic -Now $now
Check ($script:captured.Count -eq 0) "no picture before the page has reported what it drew"
$pic.lastReportAt = $now
Invoke-HordeDecisionWindowTick -Window $window -State $pic -Now $now.AddMilliseconds(699)
Check ($script:captured.Count -eq 0) "nor while the page drew within the last 700 ms"
Invoke-HordeDecisionWindowTick -Window $window -State $pic -Now $now.AddMilliseconds(700)
Invoke-HordeDecisionWindowTick -Window $window -State $pic -Now $now.AddMilliseconds(5000)
Check ($script:captured.Count -eq 1 -and $script:captured[0] -ceq (Join-Path $work "p.png") -and $pic.pictureAsked -eq $true) "after 700 ms of quiet the surface is asked for the picture, once"

Write-Host ""
Write-Host "--- the report file ---" -ForegroundColor Cyan
[void]$window.errors.AddRange(@("e1", "e2", "e3", "e4", "e5", "e6", "e7"))
$state.errors = $window.errors; $state.handle = 77
Write-HordeDecisionWindowReport -State $state
$file = [System.IO.File]::ReadAllText($state.reportPath) | ConvertFrom-Json
Check ($file.schemaVersion -eq 2 -and $file.pid -eq $PID -and $file.handle -eq 77 -and $file.title -ceq $state.title) "one JSON object: version 2, this process, the window's handle and title"
Check ($null -ne $file.drawn -and $file.drawn.lines[0].n -ceq "1" -and $file.drawn.lines[0].t -ceq "Is the first question drawn?" -and $file.drawn.headings[0].t -ceq "__proto__" -and $file.reports -eq 1 -and $file.reportsRefused -eq 1) "what the page drew, as the page sent it, and how many reports were taken and refused"
Check ($file.pushes -eq 2 -and $file.rereads -eq 1 -and $file.watchFailures -eq 1 -and $file.askedForward -eq 1 -and $file.refused -eq $state.bridge.refused) ("what the window did: lists pushed, the list read again in silence, the watch's failures, times asked to come forward, messages refused (" + $file.pushes + "," + $file.rereads + "," + $file.watchFailures + "," + $file.askedForward + "," + $file.refused + ")")
Check ((@($file.errors) -join ",") -ceq "e3,e4,e5,e6,e7" -and (@($file.findings) -join "|") -ceq "a finding of the suite's") "the newest five of the surface's errors, and what was wrong in the settings"
Check ($file.attachment.attached -eq $false -and $file.attachment.follow -cne "") "and whether it stands beside a window, with the follow's own state"
Write-HordeDecisionWindowReport -State $state
Check (@(Get-ChildItem -LiteralPath $work -File | Where-Object { $_.Name -like "report.json*" }).Count -eq 1) "written again, it is replaced whole: no half-written copy is left beside it"

Write-Host ""
Write-Host "--- the slow work goes to a helper: the window's thread only starts it and hands its result on ---" -ForegroundColor Cyan
$slow = New-HordeDecisionWindowState
Check ($null -ne (Start-HordeDecisionWindowHelper -State $slow)) "a helper is started: a PowerShell of its own, loading the composer"
$script:stepLongest = 0
function Wait-Helper { param($S) for ($i = 0; $i -lt 600 -and ($null -ne $S.helper.pending -or $S.helper.queue.Count -gt 0); $i++) { $c = [System.Diagnostics.Stopwatch]::StartNew(); Step-HordeDecisionWindowHelper -State $S -Window $window; $script:stepLongest = [Math]::Max($script:stepLongest, $c.ElapsedMilliseconds); Start-Sleep -Milliseconds 50 } }
Wait-Helper $slow
$script:posted.Clear()
$askedEarly = Ask $slow "list"
$early = ($askedEarly.reply | ConvertFrom-Json).value
Check ($early.state -ceq "unknown" -and $early.reading -eq $true -and $slow.helper.queue.Count -eq 1) "the page's first asking, before the helper has read the list: an answer that says it is being read, and the reading is asked of the helper - nothing is read on the window's thread"
Wait-Helper $slow
$firstPush = @($script:posted | Where-Object { $_ -like '*"event":"list-changed"*' })
Check ($firstPush.Count -eq 1 -and @(($firstPush[0] | ConvertFrom-Json).value.value.questions).Count -eq 5 -and $slow.title -ceq "Open decisions: 5, 5 waiting") "when the helper has read it, the list is pushed once, whole, with its title"
$sayId = [guid]::NewGuid().ToString("N")
$taken = (Ask $slow "say" @{ number = 1; text = "yes, from the helper"; wording = 1; id = $sayId }).reply | ConvertFrom-Json
Check ($taken.value.taken -eq $true -and $taken.value.id -ceq $sayId -and @((Invoke-HordeDecision -Operation "show" -Request @{ number = 1 }).value.question.thread.messages).Count -eq 0) "a save is answered at once as taken, by the page's id, and nothing is written on the window's thread"
$script:posted.Clear()
Wait-Helper $slow
$saidEvents = @($script:posted | Where-Object { $_ -like '*"event":"said"*' } | ForEach-Object { ($_ | ConvertFrom-Json).value })
Check ($saidEvents.Count -eq 1 -and $saidEvents[0].id -ceq $sayId -and $saidEvents[0].result.ok -eq $true -and $saidEvents[0].result.sequence -ge 1 -and $slow.says -eq 1) "the helper saved it and its outcome is pushed as said, with the page's id and the record's number"
$after = @($script:posted | Where-Object { $_ -like '*"event":"list-changed"*' })
Check ($after.Count -eq 1 -and @(@(($after[0] | ConvertFrom-Json).value.value.questions) | Where-Object { $_.number -eq 1 })[0].thread.count -eq 1) "and the list is read again by the helper after the save, and pushed with the answer in it"
$refusedId = [guid]::NewGuid().ToString("N")
[void](Ask $slow "say" @{ number = 99; text = "to a question that is not there"; wording = 1; id = $refusedId })
$script:posted.Clear()
Wait-Helper $slow
$refusedEvent = @($script:posted | Where-Object { $_ -like '*"event":"said"*' } | ForEach-Object { ($_ | ConvertFrom-Json).value })
Check ($refusedEvent.Count -eq 1 -and $refusedEvent[0].id -ceq $refusedId -and $refusedEvent[0].result.ok -eq $false -and $refusedEvent[0].result.reason -clike "Not saved:*" -and $slow.saysRefused -eq 1) "a refusal comes back the same way, in the rule's own words"
Check ($script:stepLongest -lt 250) ("the window's thread was never held a quarter of a second by any of it: the longest step took " + $script:stepLongest + " ms")
$actState = New-HordeDecisionWindowState
$actAsked = (Ask $actState "act" @{ number = 2; act = "park"; wording = 1; id = [guid]::NewGuid().ToString("N") }).reply | ConvertFrom-Json
$actThread = @((Invoke-HordeDecision -Operation "show" -Request @{ number = 2 }).value.question.thread.messages)
Check ($actAsked.value.ok -eq $true -and $actThread.Count -eq 1 -and $actThread[0].act -ceq "park" -and $actThread[0].speaker -ceq "founder" -and $actThread[0].route -ceq "window") "TRIAL: the request act records his park as his own words in the window, act park, so the keeper sees it"
$actWrong = (Ask $actState "act" @{ number = 2; act = "archive"; wording = 1; id = [guid]::NewGuid().ToString("N") }).reply | ConvertFrom-Json
Check ($actWrong.value.ok -eq $false -and $actWrong.value.reason -clike "Not saved:*act*" -and @((Invoke-HordeDecision -Operation "show" -Request @{ number = 2 }).value.question.thread.messages).Count -eq 1) "an act that is not park or unpark is refused by the operation's rules, and nothing is written"
Stop-HordeDecisionWindowHelper -State $slow
Check ($null -eq $slow.helper) "the helper is ended with the window"

Write-Host ""
Write-Host "--- what the page's files must not hold ---" -ForegroundColor Cyan
$scripts = @("decisions\window\frame.js", "decisions\page\list.js", "fleet\line\line.js")
$sink = 'innerHTML|outerHTML|insertAdjacentHTML|document\.write|\beval\(|new Function|setAttribute\("(on|style|src|href)'
foreach ($file in $scripts) { Check (-not ([System.IO.File]::ReadAllText((Join-Path $root $file)) -match $sink)) ($file + " holds no way of reading data as markup or as script: every text is set as text") }
Check ('node.innerHTML = question.title' -match $sink -and 'document.write(x)' -match $sink -and 'e.setAttribute("onclick", t)' -match $sink) "CONTROL: the same search finds each such way when it is there"
Check (@($scripts | Where-Object { [System.IO.File]::ReadAllText((Join-Path $root $_)) -match 'textContent' }).Count -eq 3) "CONTROL: and each of the three does set text, by textContent"
$frame = [System.IO.File]::ReadAllText((Join-Path $root "decisions\window\index.html"))
Check ($frame.Contains('<meta http-equiv="Content-Security-Policy" content="default-src ''self''; img-src ''none''; object-src ''none''; frame-src ''none''; base-uri ''none''; form-action ''none''">')) "the frame keeps its policy line: its own files, nothing inline, no frame, no object, no form"
Check (-not ($frame -match '<script(?![^>]*\bsrc=)') -and -not ($frame -match '\sstyle=|<style') -and -not ($frame -match '\son[a-z]+=')) "it holds no inline script, no inline style and no handler written into its markup"
Check ('<script>go()</script>' -match '<script(?![^>]*\bsrc=)' -and '<p style="x">' -match '\sstyle=|<style' -and '<p onclick="x">' -match '\son[a-z]+=') "CONTROL: the same searches find each of those when it is there"
$addresses = @([regex]::Matches($frame, '(?:src|href)="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
Check ($addresses.Count -eq 7 -and @($addresses | Where-Object { $_ -cnotmatch '\A(\.\./(list|fleet|surface)/)?[a-z-]+\.(js|css)\z' }).Count -eq 0) ("every file it names is named relatively: beside it, or in another mount (" + ($addresses -join " ") + ")")
$dead = '<input|<textarea|<select|contenteditable|draggable'
Check (-not ($frame -match $dead) -and @($scripts | Where-Object { [System.IO.File]::ReadAllText((Join-Path $root $_)) -match ($dead + '|contentEditable') }).Count -eq 0) "READ-ONLY: nothing to type in and nothing to drag, in the frame or in any script"
Check ('<input type="text">' -match $dead -and 't.contentEditable = "true"' -match ($dead + '|contentEditable')) "CONTROL: the same search finds an answer box or an editable line when there is one"
$styles = @("decisions\window\frame.css", "decisions\page\list.css", "fleet\line\line.css")
$soft = '(font-size:\s*[0-9.]+|line-height:\s*[0-9.]+\s*;|font-weight:\s*(?!400|600)[0-9a-z]+|letter-spacing|transform|opacity|-webkit-line-clamp|filter:)'
# The rules alone: each file's comments say in words what its rules must not do.
function Rules { param([string]$File) return ([System.IO.File]::ReadAllText((Join-Path $root $File)) -replace '(?s)/\*.*?\*/', '') }
Check ((Rules "decisions\window\frame.css").Contains("font-size: var(--text-px); line-height: var(--line-px); font-weight: 400;") -and -not (Rules "decisions\window\frame.css").Contains("SHARP LETTERS")) "CONTROL: a style sheet's rules are read, and its comments are not"
foreach ($file in $styles) { Check (-not ((Rules $file) -match $soft)) ($file + " writes no size of its own, no line height as a ratio, no weight but 400 and 600, and no letter-spacing, transform, opacity, filter or clamp") }
Check ('.a { font-size: 11px; }' -match $soft -and '.a { line-height: 1.35; }' -match $soft -and '.a { font-weight: 700; }' -match $soft -and '.a { opacity: .6; }' -match $soft -and '.a { text-transform: uppercase; }' -match $soft) "CONTROL: the same search finds each fault the earlier pages were measured soft by"
Check (-not ('.a { font-weight: 600; }' -match $soft) -and -not ('.a { line-height: var(--line-px); }' -match $soft)) "CONTROL: and passes what is allowed: weight 600, a line height that is the page's variable"
Check (-not (Test-Path -LiteralPath (Join-Path $root "fleet\panel")) -and -not (Test-Path -LiteralPath (Join-Path $root "decisions\window\shell.js")) -and -not (Test-Path -LiteralPath (Join-Path $root "decisions\page\list.css.old"))) "the earlier dense page is not kept beside this one"

} finally {
    $script:HordeDecisionWindow = $null
    $env:HORDE_HOME = $keepHome; $env:WEZFLEET_ROOT = $keepFleet
    if ((Split-Path -Leaf $work) -match '\Ahorde-decisions-window-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "the decisions window asks only for what is on its list, says what its page drew, and stands free in words when it cannot stand beside"
