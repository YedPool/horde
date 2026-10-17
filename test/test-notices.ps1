# DOES A SESSION'S NOTICE REACH THE FOUNDER'S NOTICES UNDER ITS OWN PROVEN NAME, NEVER ANOTHER'S, NEVER A
# SECRET, AND NEVER MORE THAN THE HOURLY CAP - AND DOES A FOLLOWED LANE'S NEW PROGRESS ENTRY BECOME ONE
# NOTICE, AND AN UNFOLLOWED OR ALREADY-SEEN ONE NONE?
#
# notices/ (Sender.ps1, Decide.ps1, Store.ps1) and the shipped `horde notify`, in homes of the suite's own.
# It attacks:
#   1. THE SENDER PROOF, through the real identity reader (core/Identity.ps1) with the suite's own control
#      files and process tables: the session's process above the caller is proven; a caller naming
#      ANOTHER running session (a process that is not its ancestor) is refused; a parent pid taken again
#      by a later process does not count; no session, a session whose process is gone, and a session
#      with no label and no name are refused; the label is the registry's, else the agent's own name.
#   2. THE NOTIFY LINE: written once, with its sender; a secret is refused on the WHOLE text - one that
#      straddles the cut too - and the notice carries the fixed sentence, never a character of it.
#   3. THE CAP: perHour sent, the next one cut off and the founder told ONCE, every later one held and
#      the founder told nothing more; another session has its own count; the next hour starts again.
#   4. FOLLOWING: off by default; a followed lane's new entry is one notice; an unfollowed one none; an
#      entry of two lanes is one notice when either is followed; an entry offered again is none; an
#      entry of no lane is the Thrall's; the later signature of a switch stands.
#   5. THE SHIPPED COMMAND, end to end: `horde notify` run as a child of this suite, which is the
#      "session" its control file names - sent, with the label; then the same command claiming another
#      running session is refused, and so is a -From the command does not have.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "notices\Sender.ps1")
. (Join-Path $root "notices\Decide.ps1")
Set-StrictMode -Version Latest

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$work = Join-Path $env:TEMP ("horde-notices-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$realHome = $env:HORDE_HOME
# The variable the agent sets to say which session is asking, as core names it (test/test-files-cli.ps1).
$sessionVariable = ("" + (Get-HordeSelfSessionId -Environment @{}).reason).Split(" ")[0]

function Sid { param([int]$N) return ("bbbbbbbb-0000-4000-8000-" + $N.ToString("000000000000")) }
function New-Home {
    param([string]$Settings = "")
    $h = Join-Path $work ("home-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    if ($Settings -cne "") { [System.IO.File]::WriteAllText((Join-Path $h "settings\notices.json"), ('{"schemaVersion": 1, "settings": ' + $Settings + '}'), $utf8) }
    return $h
}
function Get-Notices { param([string]$HordeHome) $r = Read-HordeNoticeLog -Store (Join-Path $HordeHome "notices"); if ($r.state -cne "known") { throw $r.reason }; return @($r.value) }
function Proven { param([string]$Sid, [string]$Label) return [pscustomobject]@{ ok = $true; reason = ""; sessionId = $Sid; label = $Label } }
function Write-ControlFile {
    # A control file of the agent, in the shape core/Identity.ps1 reads (the builder of test/test-identity.ps1).
    param([string]$Dir, [int]$ProcId, [string]$SessionId, [datetime]$Created, [string]$Name = "")
    $ms = ([DateTimeOffset]$Created.ToUniversalTime().AddSeconds(90)).ToUnixTimeMilliseconds()
    $o = [ordered]@{ pid = $ProcId; sessionId = $SessionId; cwd = "C:\work"; startedAt = $ms; procStart = "" + $Created.ToFileTimeUtc(); version = "9.9.9"; peerProtocol = 1; peerFeatures = @("f")
        kind = "interactive"; entrypoint = "cli"; messagingSocketPath = ("\\.\pipe\LOCAL\notices-" + $ProcId); name = $Name; nameSource = "user"; nameSince = $ms; updatedAt = $ms
        status = "busy"; statusUpdatedAt = $ms; bridgeSessionId = ("bridge-" + $ProcId) }
    if ($Name -ceq "") { $o.Remove("name"); $o.Remove("nameSource"); $o.Remove("nameSince") }
    [System.IO.File]::WriteAllText((Join-Path $Dir ("" + $ProcId + ".json")), ($o | ConvertTo-Json -Depth 4), $utf8)
}
function Write-Registry {
    # A fleet registry record of a session, with its label.
    param([string]$Root, [string]$SessionId, [string]$Label)
    $dir = Join-Path $Root "registry\sessions"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dir ($SessionId + ".json")), ('{"claudeSessionId":"' + $SessionId + '","label":"' + $Label + '"}'), $utf8)
}
function Table {
    # A process table: rows of @(pid, parent, created).
    param([object[]]$Rows)
    $t = @{}
    foreach ($r in $Rows) { $t[[int]$r[0]] = [pscustomobject]@{ pid = [int]$r[0]; parent = [int]$r[1]; name = "p"; created = $r[2]; commandLine = "" } }
    return (New-HordeKnown -Value $t)
}

$t0 = (New-Object DateTime 2026, 10, 14, 1, 0, 0, ([DateTimeKind]::Utc)).AddTicks(1234560)
try {
    Write-Host ""
    Write-Host "--- 1. the sender is proven by its process, never by what it says ---" -ForegroundColor Cyan
    Check ($sessionVariable -cmatch '\A[A-Z][A-Z0-9_]{3,}\z') "CONTROL: core names the variable that says which session is asking"
    $ctl = Join-Path $work "control"; New-Item -ItemType Directory -Path $ctl -Force | Out-Null
    $proj = Join-Path $work "projects"; New-Item -ItemType Directory -Path $proj -Force | Out-Null
    $reg = Join-Path $work "fleet"; New-Item -ItemType Directory -Path (Join-Path $reg "registry\sessions") -Force | Out-Null
    # Session 1 runs as process 100; its shell 200; the command 300. Session 2 runs as 400, beside it.
    Write-ControlFile -Dir $ctl -ProcId 100 -SessionId (Sid 1) -Created $t0
    Write-ControlFile -Dir $ctl -ProcId 400 -SessionId (Sid 2) -Created $t0.AddSeconds(5) -Name "the other one"
    Write-Registry -Root $reg -SessionId (Sid 1) -Label "E"
    $ident = @{ ClaudeDir = $ctl; ProjectsDir = $proj }
    $tab = Table @(@(100, 1, $t0), @(200, 100, $t0.AddSeconds(1)), @(300, 200, $t0.AddSeconds(2)), @(400, 1, $t0.AddSeconds(5)), @(500, 400, $t0.AddSeconds(6)))
    $who = Resolve-HordeNoticeSender -Environment @{ $sessionVariable = (Sid 1) } -Identity $ident -Processes $tab -RegistryRoot $reg -Self 300
    Check ($who.ok -and $who.sessionId -ceq (Sid 1) -and $who.label -ceq "E") ("the session whose process is above the command is proven, and named by its registry label (" + $who.reason + ")")
    $who = Resolve-HordeNoticeSender -Environment @{ $sessionVariable = (Sid 2) } -Identity $ident -Processes $tab -RegistryRoot $reg -Self 300
    Check (-not $who.ok -and $who.label -ceq "" -and $who.reason -like "*does not run inside session*") ("A CALLER CLAIMING ANOTHER RUNNING SESSION is refused: that session's process is not above it (" + $who.reason + ")")
    $who = Resolve-HordeNoticeSender -Environment @{ $sessionVariable = (Sid 2) } -Identity $ident -Processes $tab -RegistryRoot $reg -Self 500
    Check ($who.ok -and $who.label -ceq "the other one" -and $who.labelSource -ceq "agent-name") ("CONTROL: the same claim from under session 2's own process is proven, named by the agent's own name with no label (" + $who.reason + ")")
    # A SESSION CANNOT TAKE A SERVICE'S FORM (PR 332 review, S2): a registry label that reads "service: x" - however it is
    # dressed - is refused, so the phone's "service: <name>" is a registered service's alone.
    $zw = [string][char]0x200B
    $hostile = @("service: postmerge-net", ($zw + "service: x"), ([string][char]0x2060 + "service: x"), ("s" + [char]0x0435 + "rvice: x"), ("service" + [char]0x02D0 + " x"), ("service" + [char]0x2236 + " x"),
        ("service" + [char]0xA789 + " x"), "services: x", ("service" + [char]0xFF1A + "x"), ("ser" + $zw + "vice: x"), ([string][char]0xFF53 + "ervice: x"), "  SERVICE : y",
        [string]::Concat("ser", [char]0x034F, "vice: x"), [string]::Concat("service", [char]0xFE0F, ": x"), [string]::Concat("ser", [char]::ConvertFromUtf32(0xE0020), "vice: x"), [string]::Concat("service", [char]::ConvertFromUtf32(0xE0100), ": x"),
        [string]::Concat("service", [char]0xA4FD, " x"), "service; x", "service - x", "service x", "service", [string]::Concat("service", [char]0x205A, " x"))
    foreach ($lbl in $hostile) {
        Check (Test-HordeNoticeServiceForm -Label $lbl) ("the fold alone reads as a service: " + $lbl.Length + " characters, first U+" + ([int][char]$lbl[0]).ToString("X4") + ", whole " + (($lbl.ToCharArray() | ForEach-Object { ([int]$_).ToString("X4") }) -join " "))
        Write-Registry -Root $reg -SessionId (Sid 1) -Label $lbl
        $who = Resolve-HordeNoticeSender -Environment @{ $sessionVariable = (Sid 1) } -Identity $ident -Processes $tab -RegistryRoot $reg -Self 300
        Check (-not $who.ok -and $who.reason -like "*labelled like a service*") ("A SESSION LABELLED LIKE A SERVICE IS REFUSED: U+" + (([int][char]$lbl[0]).ToString("X4")) + " ... '" + ($lbl.Length) + "' characters (" + $who.reason + ")")
    }
    Write-Registry -Root $reg -SessionId (Sid 1) -Label ($zw + "E9")
    $who = Resolve-HordeNoticeSender -Environment @{ $sessionVariable = (Sid 1) } -Identity $ident -Processes $tab -RegistryRoot $reg -Self 300
    Check ($who.ok -and $who.label -ceq "E9" -and $who.labelSource -ceq "registry") "CONTROL: an invisible format character is not part of the label that is shown, and its source is the registry"
    foreach ($lbl in @("the service desk", "Thrall", "Orc E3", [string]::Concat([char]0x05E9, [char]0x05DC, [char]0x05D5, [char]0x05DD, [char]0x05E9, [char]0x05DC, [char]0x05D5, ": x"))) {
        Write-Registry -Root $reg -SessionId (Sid 1) -Label $lbl
        $who = Resolve-HordeNoticeSender -Environment @{ $sessionVariable = (Sid 1) } -Identity $ident -Processes $tab -RegistryRoot $reg -Self 300
        Check ($who.ok -and $who.label -ceq $lbl) ("CONTROL: the ordinary label (" + $lbl.Length + " characters, starting U+" + ([int][char]$lbl[0]).ToString("X4") + ") is still proven")
    }
    Write-Registry -Root $reg -SessionId (Sid 1) -Label "E"
    # 300's parent pid 200 now belongs to a process started AFTER 300: a stranger, not its parent.
    $reused = Table @(@(100, 1, $t0), @(200, 100, $t0.AddSeconds(9)), @(300, 200, $t0.AddSeconds(2)))
    $who = Resolve-HordeNoticeSender -Environment @{ $sessionVariable = (Sid 1) } -Identity $ident -Processes $reused -RegistryRoot $reg -Self 300
    Check (-not $who.ok -and $who.reason -like "*started after*") ("a parent pid taken again by a later process is not a parent, and the walk ends there (" + $who.reason + ")")
    $who = Resolve-HordeNoticeSender -Environment @{} -Identity $ident -Processes $tab -RegistryRoot $reg -Self 300
    Check (-not $who.ok -and $who.reason -like "*not run from inside a session*") "outside any session it is refused"
    $gone = Table @(@(200, 1, $t0.AddSeconds(1)), @(300, 200, $t0.AddSeconds(2)))
    $who = Resolve-HordeNoticeSender -Environment @{ $sessionVariable = (Sid 1) } -Identity $ident -Processes $gone -RegistryRoot $reg -Self 300
    Check (-not $who.ok -and $who.reason -like "*could not be verified as running*") ("a session whose process is gone is refused (" + $who.reason + ")")
    $who = Resolve-HordeNoticeSender -Environment @{ $sessionVariable = (Sid 9) } -Identity $ident -Processes $tab -RegistryRoot $reg -Self 300
    Check (-not $who.ok -and $who.reason -like "*no running session's own file names*") "a session no control file names is refused"
    Write-ControlFile -Dir $ctl -ProcId 600 -SessionId (Sid 3) -Created $t0.AddSeconds(20)
    $who = Resolve-HordeNoticeSender -Environment @{ $sessionVariable = (Sid 3) } -Identity $ident -Processes (Table @(@(600, 1, $t0.AddSeconds(20)), @(700, 600, $t0.AddSeconds(21)))) -RegistryRoot $reg -Self 700
    Check (-not $who.ok -and $who.reason -like "*no label*no name*") ("a proven session with no label and no name is refused: the founder could not tell who it is (" + $who.reason + ")")
    $noParent = New-HordeKnown -Value @{ 100 = [pscustomobject]@{ pid = 100; name = "p"; created = $t0; commandLine = "" }; 300 = [pscustomobject]@{ pid = 300; name = "p"; created = $t0.AddSeconds(2); commandLine = "" } }
    $who = Resolve-HordeNoticeSender -Environment @{ $sessionVariable = (Sid 1) } -Identity $ident -Processes $noParent -RegistryRoot $reg -Self 300
    Check (-not $who.ok -and $who.reason -like "*does not say what started*") "a process table that does not say who started a process proves nothing"

    Write-Host ""
    Write-Host "--- 2. a notify line, and a secret refused on the whole text ---" -ForegroundColor Cyan
    $H = New-Home
    $now = New-Object DateTime 2026, 10, 14, 3, 10, 0, ([DateTimeKind]::Utc)
    $r = Submit-HordeNotify -Sender (Proven (Sid 1) "E") -Text "the build is green" -HordeHome $H -Now $now
    $all = @(Get-Notices $H)
    Check ($r.outcome -ceq "sent" -and $all.Count -eq 1 -and $all[0].n -eq 1 -and $all[0].kind -ceq "notify" -and $all[0].from -ceq "E" -and $all[0].text -ceq "the build is green" -and $all[0].ts -ceq "2026-10-14T03:10:00.000Z") ("a notify line is written once, numbered 1, with its sender and its time (" + $r.outcome + ")")
    Check (-not ([System.IO.File]::ReadAllText((Join-Path $H "notices\notices.jsonl"))).Contains((Sid 1))) "the session's id is not in what goes to the phone"
    $token = "ghp_" + ("A1b2C3d4E5f6G7h8I9j0" * 2)
    Check ((Find-HordeSecretKind -Text $token) -cne "") "CONTROL: core/Secrets.ps1 knows the token as a secret"
    $r = Submit-HordeNotify -Sender (Proven (Sid 1) "E") -Text ("deployed with " + $token) -HordeHome $H -Now $now
    $last = @(Get-Notices $H)[-1]
    Check ($r.outcome -ceq "sent-refused" -and $last.text -ceq (Get-HordeNoticeSecretWords) -and -not $last.text.Contains("ghp_")) ("a line holding a secret goes as the fixed sentence, never the text (" + $last.text + ")")
    # STRADDLING THE CUT: textChars 300, and the token starts at 290 - cut first, 10 characters of it would
    # remain, which match no pattern, and would go out.
    $pad = "x" * 289
    $cutFirst = ($pad + " " + $token).Substring(0, 297)
    Check ((Find-HordeSecretKind -Text $cutFirst) -ceq "") "CONTROL: the text cut first no longer looks like a secret - the order is what is under test"
    $r = Submit-HordeNotify -Sender (Proven (Sid 1) "E") -Text ($pad + " " + $token) -HordeHome $H -Now $now
    $last = @(Get-Notices $H)[-1]
    Check ($r.outcome -ceq "sent-refused" -and $last.text -ceq (Get-HordeNoticeSecretWords) -and -not ([System.IO.File]::ReadAllText((Join-Path $H "notices\notices.jsonl"))).Contains("ghp_")) "A SECRET STRADDLING THE CUT is refused: the whole text is checked before it is cut"
    $r = Submit-HordeNotify -Sender (Proven (Sid 1) "E") -Text ("y" * 400) -HordeHome $H -Now $now
    $last = @(Get-Notices $H)[-1]
    Check ($r.outcome -ceq "sent" -and $last.text.Length -eq 300 -and $last.text.EndsWith("...")) "a long clean line is cut to textChars, with ..."
    $r = Submit-HordeNotify -Sender (Proven (Sid 1) "E") -Text "two`nlines" -HordeHome $H -Now $now
    Check ($r.outcome -ceq "failed" -and $r.reason -like "*one line*") "a text of two lines is refused"
    $r = Submit-HordeNotify -Sender (Proven (Sid 1) ("lead " + $token)) -Text "hi" -HordeHome $H -Now $now
    Check ($r.outcome -ceq "sent" -and @(Get-Notices $H)[-1].from -ceq "a session") "a label that looks like a secret is not shown either"
    $r = Submit-HordeNotify -Sender ([pscustomobject]@{ ok = $false; reason = "x"; sessionId = (Sid 1); label = "E" }) -Text "hi" -HordeHome $H -Now $now
    Check ($r.outcome -ceq "failed" -and $r.reason -like "*not proven*") "a sender that is not proven sends nothing"

    Write-Host ""
    Write-Host "--- 3. the hourly cap: one over is cut off, the founder told once ---" -ForegroundColor Cyan
    $H = New-Home -Settings '{"perHour": 3}'
    $outs = @(1..3 | ForEach-Object { (Submit-HordeNotify -Sender (Proven (Sid 1) "E") -Text ("line " + $_) -HordeHome $H -Now $now).outcome })
    Check (($outs -join ",") -ceq "sent,sent,sent") "up to perHour (3) are sent"
    $r4 = Submit-HordeNotify -Sender (Proven (Sid 1) "E") -Text "line 4" -HordeHome $H -Now $now.AddMinutes(1)
    $all = @(Get-Notices $H)
    Check ($r4.outcome -ceq "cut-off" -and $all.Count -eq 4 -and $all[-1].kind -ceq "cutoff" -and $all[-1].from -ceq "Horde" -and -not (@($all | Where-Object { $_.text -ceq "line 4" }).Count) -and $all[-1].text -ceq "E sent more than 3 notices this hour, so its notices are held back until 04:00 UTC.") ("THE ONE OVER is not sent: the founder is told, in plain words, which session and until when (" + $all[-1].text + ")")
    $r5 = Submit-HordeNotify -Sender (Proven (Sid 1) "E") -Text "line 5" -HordeHome $H -Now $now.AddMinutes(2)
    $r6 = Submit-HordeNotify -Sender (Proven (Sid 1) "E") -Text "line 6" -HordeHome $H -Now $now.AddMinutes(40)
    Check ($r5.outcome -ceq "held" -and $r6.outcome -ceq "held" -and @(Get-Notices $H).Count -eq 4 -and $r5.reason -like "*cut off until 04:00 UTC*") "every later one that hour is held, and the founder is told NOTHING more"
    $o = Submit-HordeNotify -Sender (Proven (Sid 2) "E") -Text "from the other E" -HordeHome $H -Now $now.AddMinutes(41)
    Check ($o.outcome -ceq "sent") "another session - even with the same label - has its own count"
    $r7 = Submit-HordeNotify -Sender (Proven (Sid 1) "E") -Text "a new hour" -HordeHome $H -Now $now.AddMinutes(51)
    Check ($r7.outcome -ceq "sent" -and @(Get-Notices $H)[-1].text -ceq "a new hour") "the next clock hour starts the count again"
    [System.IO.File]::WriteAllText((Join-Path $H "notices\state.json"), "{not json", $utf8)
    $bad = Submit-HordeNotify -Sender (Proven (Sid 1) "E") -Text "after damage" -HordeHome $H -Now $now.AddMinutes(52)
    Check ($bad.outcome -ceq "failed" -and $bad.reason -like "*notices state*" -and @(Get-Notices $H)[-1].text -ceq "a new hour") "a counts file that does not hold together is never started over: nothing is sent, and it says why"

    Write-Host ""
    Write-Host "--- 4. following: off by default, a followed lane's new entry once ---" -ForegroundColor Cyan
    $H = New-Home
    $e1 = [pscustomobject]@{ id = "p-1"; title = "merged the cards"; kind = "merged"; lanes = @("E") }
    $r = Submit-HordeProgressNotices -Entries @($e1) -HordeHome $H -Now $now
    Check ($r.state -ceq "known" -and @($r.value).Count -eq 0 -and @(Get-Notices $H).Count -eq 0) "OFF BY DEFAULT: with no switch set, no entry is a notice"
    $f = Set-HordeNoticeFollow -Lane "E" -On $true -At 1000 -Key "phone/notices/1/a" -HordeHome $H
    Check ($f.state -ceq "known" -and $f.value.changed) "a switch is set"
    $r = Submit-HordeProgressNotices -Entries @($e1, [pscustomobject]@{ id = "p-2"; title = "voice fixed"; kind = "done"; lanes = @("B") }) -HordeHome $H -Now $now
    $all = @(Get-Notices $H)
    Check (@($r.value).Count -eq 1 -and $all.Count -eq 1 -and $all[0].kind -ceq "progress" -and $all[0].from -ceq "Orc E" -and $all[0].lane -ceq "E" -and $all[0].entry -ceq "p-1" -and $all[0].text -ceq "Merged: merged the cards") ("a followed lane's entry is one notice from Orc E naming the entry; an unfollowed lane's (B) none (" + (@($all | ForEach-Object { $_.text }) -join "|") + ")")
    $r = Submit-HordeProgressNotices -Entries @($e1) -HordeHome $H -Now $now
    Check (@($r.value).Count -eq 0 -and @(Get-Notices $H).Count -eq 1) "the same entry offered again is no second notice"
    $null = Set-HordeNoticeFollow -Lane "F" -On $true -At 1000 -Key "phone/notices/2/a" -HordeHome $H
    $r = Submit-HordeProgressNotices -Entries @([pscustomobject]@{ id = "p-3"; title = "both"; kind = "progress"; lanes = @("C", "F", "E") }) -HordeHome $H -Now $now
    Check (@($r.value).Count -eq 1 -and @(Get-Notices $H)[-1].from -ceq "Orc F") "AN ENTRY OF TWO FOLLOWED LANES is one notice, named by the first of its lanes that is followed"
    $r = Submit-HordeProgressNotices -Entries @([pscustomobject]@{ id = "p-4"; title = "fleet note"; kind = "note"; lanes = @() }) -HordeHome $H -Now $now
    Check (@($r.value).Count -eq 0) "an entry of no lane is no notice while the Thrall is not followed"
    $null = Set-HordeNoticeFollow -Lane "thrall" -On $true -At 1000 -Key "phone/notices/3/a" -HordeHome $H
    $r = Submit-HordeProgressNotices -Entries @([pscustomobject]@{ id = "p-5"; title = "fleet note"; kind = "note"; lanes = @() }) -HordeHome $H -Now $now
    Check (@($r.value).Count -eq 1 -and @(Get-Notices $H)[-1].from -ceq "Thrall" -and @(Get-Notices $H)[-1].lane -ceq "thrall" -and @(Get-Notices $H)[-1].text -ceq "fleet note") "an entry of no lane is the Thrall's: followed, it is a notice from the Thrall"
    $earlier = Set-HordeNoticeFollow -Lane "E" -On $false -At 900 -Key "phone/notices/9/a" -HordeHome $H
    Check ($earlier.state -ceq "known" -and -not $earlier.value.changed -and (Read-HordeNoticeFollows -Store (Join-Path $H "notices")).value["E"].on) "a switch the phone signed EARLIER does not overrule a later one, whatever order they arrive in"
    $same = Set-HordeNoticeFollow -Lane "E" -On $true -At 1000 -Key "phone/notices/1/a" -HordeHome $H
    Check (-not $same.value.changed) "the same switch again changes nothing"
    $off = Set-HordeNoticeFollow -Lane "E" -On $false -At 2000 -Key "phone/notices/4/a" -HordeHome $H
    $r = Submit-HordeProgressNotices -Entries @([pscustomobject]@{ id = "p-6"; title = "after off"; kind = "merged"; lanes = @("E") }) -HordeHome $H -Now $now
    Check ($off.value.changed -and @($r.value).Count -eq 0) "turned off by a later signature, the lane's entries are no notices"
    $tok = Submit-HordeProgressNotices -Entries @([pscustomobject]@{ id = "p-7"; title = ("key " + $token); kind = "merged"; lanes = @("F") }) -HordeHome $H -Now $now
    Check (@($tok.value).Count -eq 1 -and @(Get-Notices $H)[-1].text -ceq (Get-HordeNoticeSecretWords)) "a progress title that looks like a secret is the fixed sentence"
    Check (Throws { Set-HordeNoticeFollow -Lane "E" -On $true -At 1 -Key "k" -HordeHome $H -Bogus 1 }) "CONTROL: a switch takes no parameter it does not declare"
    $badLane = Set-HordeNoticeFollow -Lane "a/b" -On $true -At 1 -Key "k" -HordeHome $H
    Check ($badLane.state -ceq "unknown") "a lane that is not a lane id is refused"

    Write-Host ""
    Write-Host "--- 5. the shipped command, end to end ---" -ForegroundColor Cyan
    # THIS SUITE'S OWN PROCESS IS THE SESSION: a control file names it, with its own start time, so the
    # real identity reader verifies it, and `horde notify`, run as this process's child, is inside it.
    $H = New-Home
    $profileDir = Join-Path $work "profile"
    # The agent's own folder under the profile, where core/Identity.ps1 looks by default.
    $agentHome = Join-Path $profileDir ".claude"
    $agentDir = Join-Path $agentHome "sessions"
    New-Item -ItemType Directory -Path $agentDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $agentHome "projects") -Force | Out-Null
    $me = [System.Diagnostics.Process]::GetCurrentProcess()
    Write-ControlFile -Dir $agentDir -ProcId $PID -SessionId (Sid 11) -Created $me.StartTime.ToUniversalTime()
    # Session 12 is another running process that is NOT above the command: a sleeping child of this suite.
    $other = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-Command", "Start-Sleep -Seconds 120") -WindowStyle Hidden -PassThru
    try {
        Write-ControlFile -Dir $agentDir -ProcId $other.Id -SessionId (Sid 12) -Created $other.StartTime.ToUniversalTime() -Name "sleeper"
        Write-Registry -Root $fleetPin.path -SessionId (Sid 11) -Label "E3"
        $env1 = @{ HORDE_HOME = $H; USERPROFILE = $profileDir }
        $env1[$sessionVariable] = (Sid 11)
        $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify", "-Text", "the cards are merged") -Env $env1
        $all = @(Get-Notices $H)
        Check ($r.code -eq 0 -and $r.out -like "*sent to the founder's phone as notice 1, from E3*" -and $all.Count -eq 1 -and $all[0].from -ceq "E3" -and $all[0].text -ceq "the cards are merged") ("horde notify sends, as the session it runs inside, named by its label (" + $r.code + ": " + $r.out.Trim() + ")")
        $env2 = @{ HORDE_HOME = $H; USERPROFILE = $profileDir }
        $env2[$sessionVariable] = (Sid 12)
        $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify", "-Text", "pretending") -Env $env2
        Check ($r.code -eq 1 -and $r.out -like "*does not run inside session*" -and @(Get-Notices $H).Count -eq 1) ("A SECOND SESSION CANNOT SEND AS THE FIRST: claiming a running session it is not inside, it exits 1 and nothing is sent (" + $r.out.Trim() + ")")
        $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify", "-Text", "as M", "-From", "M") -Env $env1
        Check ($r.code -eq 2 -and @(Get-Notices $H).Count -eq 1) ("there is no -From: a caller cannot name the sender (" + $r.code + ")")
        $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify", "-Text", ("x " + $token)) -Env $env1
        Check ($r.code -eq 1 -and $r.out -like "*was sent without its words*" -and -not ([System.IO.File]::ReadAllText((Join-Path $H "notices\notices.jsonl"))).Contains("ghp_")) "a secret on the command line is not sent, the founder is told the session spoke, and the command fails"
        $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("help") -Env @{ HORDE_HOME = $H }
        Check ($r.code -eq 0 -and $r.out -like "*horde notify -Text <one line>*") "horde help lists the command"
    } finally { try { $other.Kill() } catch { } }
} finally {
    $env:HORDE_HOME = $realHome
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    if ((Split-Path -Leaf $work) -match '^horde-notices-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    Check (-not (Test-Path -LiteralPath $work)) "every folder the suite made is gone"
}

Complete-HordeSuite -Success "a session's notice reaches the founder's notices under its own proven name and never another's, never a secret, never past the hourly cap; a followed lane's new entry is one notice, an unfollowed one none"
