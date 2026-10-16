# DOES `horde fleet record` WRITE DOWN EXACTLY THE RUNNING, UNRETIRED SESSIONS - NEVER THE MASTER UNLESS
# NAMED, NEVER AN EMPTY RECORD, AND NOTHING AT ALL WHEN THE REGISTRY CANNOT BE READ WHOLE?
#
# fleet/Hibernation.ps1. The fleet registry is a real folder of records this suite writes under TEMP and
# reads with the shipped reader (core/WezfleetState.ps1). The harness and the terminal are stand-ins, but
# they go through the shipped seam: each is registered with Register-HordeFleetAgent / -Host and found
# with Resolve-HordeFleetAdapter, so a stand-in that does not fit the port fails here, not in use. The
# real adapters are tested against their own seams, each in its own folder's test-fleet-*.ps1 (agents/
# and hosts/). Every record is written in a Horde home under TEMP; the
# command-line cases run the real horde.ps1 with HORDE_HOME and WEZFLEET_ROOT pointed there.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "fleet\Hibernation.ps1")

function Section { param([string]$Title) Write-Host ""; Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan }

$work = Join-Path $env:TEMP ("horde-fleet-record-" + [guid]::NewGuid().ToString("N"))
$hh = Join-Path $work "home"
$wf = Join-Path $work "wezfleet"
$regDir = Join-Path $wf "registry\sessions"
[void](New-Item -ItemType Directory -Path $regDir -Force)
[void](New-Item -ItemType Directory -Path $hh -Force)

$ids = @{
    M = "11111111-0000-4000-8000-000000000001"; K = "11111111-0000-4000-8000-000000000002"; K1 = "11111111-0000-4000-8000-000000000003"
    L = "11111111-0000-4000-8000-000000000004"; R = "11111111-0000-4000-8000-000000000005"; S = "11111111-0000-4000-8000-000000000006"
    T = "11111111-0000-4000-8000-000000000007"; W = "11111111-0000-4000-8000-000000000008"
}
$cwdK = Join-Path $work "lanes\k"
$cwdU = Join-Path $work ("lanes\caf" + [char]0x00E9)
[void](New-Item -ItemType Directory -Path $cwdK -Force)
[void](New-Item -ItemType Directory -Path $cwdU -Force)

function Write-Reg {
    # One registry record, as the fleet's hook writes it (the field names of a real one, 2026-10-16).
    param([string]$Label, [hashtable]$More = @{})
    $r = [ordered]@{ claudeSessionId = $ids[$Label]; origin = "user"; fleetSessionId = ""; pane = "5"; instance = "inst-1"; cwd = $cwdK; transcriptPath = (Join-Path $work ($Label + ".jsonl")); owner = ""; label = $Label }
    foreach ($k in $More.Keys) { if ($null -eq $More[$k]) { $r.Remove($k) } else { $r[$k] = $More[$k] } }
    [System.IO.File]::WriteAllText((Join-Path $regDir ($ids[$Label] + ".json")), (ConvertTo-Json -InputObject $r))
}
Write-Reg "M" @{ role = "master" }
Write-Reg "K" @{ role = "orchestrator"; pane = "7" }
Write-Reg "K1" @{ parent = $ids["K"]; pane = "8"; role = "session" }
Write-Reg "L" @{ role = "orchestrator"; cwd = $cwdU }
Write-Reg "R" @{ retired = $true; retiredAt = "2026-10-15T10:00:00Z" }
Write-Reg "S" @{}
Write-Reg "T" @{ label = $null; role = $null }
Write-Reg "W" @{ role = "warchief"; label = "W" }

# The harness stand-in: which ids run, which are stopped, which are unknown.
$world = @{ state = @{}; error = "" }
foreach ($k in @("M", "K", "K1", "L", "R", "T", "W")) { $world.state[$ids[$k]] = "running" }
$world.state[$ids["S"]] = "stopped"
Register-HordeFleetAgent -Name "stand-in" `
    -Snapshot { [pscustomobject]@{ error = $world.error; state = $world.state.Clone() } }.GetNewClosure() `
    -Verdict { param($snap, $id, $cwd, $ignore)
        if ($snap.error -ne "") { return [pscustomobject]@{ state = "unknown"; kind = "reading"; reason = $snap.error; pid = "" } }
        $st = $snap.state[$id]; if ($null -eq $st) { $st = "stopped" }
        $kind = $(if ($st -ceq "running") { "live" } elseif ($st -ceq "unknown") { "unconfirmed" } else { "" })
        [pscustomobject]@{ state = $st; kind = $kind; reason = ("stand-in says " + $st); pid = "" } } `
    -Running { param($snap) @() } -ResumeLine { param($id) "resume " + $id } -Scrub { @{} }
$placementAsked = New-Object System.Collections.ArrayList
$hostAnswer = @{ mode = "known" }
Register-HordeFleetHost -Name "stand-in" `
    -Placement { param($refs)
        foreach ($r in @($refs)) { [void]$placementAsked.Add($r) }
        if ($hostAnswer.mode -ceq "unknown") { return (New-HordeUnknown -Reason "the stand-in terminal is not answering") }
        $placed = @{}
        foreach ($r in @($refs)) { if ($r.pane -ne "5") { $placed[$r.sessionId] = [pscustomobject][ordered]@{ windowKey = ($r.instance + ":1"); tabIndex = 0; left = $(if ($r.pane -eq "8") { 60 } else { 0 }); top = 0; cols = 60; rows = 40; tabCols = 120; tabRows = 40 } } }
        New-HordeKnown -Value ([pscustomobject]@{ placed = $placed; notes = @(@($refs) | Where-Object { -not $placed.ContainsKey($_.sessionId) } | ForEach-Object { $_.sessionId + ": not in the stand-in's list" }) }) }.GetNewClosure() `
    -Open { New-HordeUnknown -Reason "never opened by a record" } -Describe { param($r) "describe" }
$agent = Resolve-HordeFleetAdapter -Kind "agent"
$hostA = Resolve-HordeFleetAdapter -Kind "host"
Check ($agent.state -ceq "known" -and $hostA.state -ceq "known") "CONTROL: the stand-ins pass the shipped registration and are found by the shipped resolver"

$clock = @{ at = [datetime]::new(2026, 10, 16, 9, 15, 0, [System.DateTimeKind]::Utc) }
$deps = [pscustomobject]@{ Now = { $clock.at }.GetNewClosure(); Agent = $agent.value; Host = $hostA.value; Registry = { Read-HordeRegistry -Root $wf }.GetNewClosure() }
function Next-Second { $clock.at = $clock.at.AddSeconds(1) }
function All-Selection { param([string[]]$Exclude = @()) return [pscustomobject][ordered]@{ kind = "all"; labels = @(); exclude = @($Exclude) } }
function Label-Selection { param([string[]]$Labels) return [pscustomobject][ordered]@{ kind = "labels"; labels = @($Labels); exclude = @() } }
function Count-Records { $d = Get-HordeFleetHibernationsDir -HordeHome $hh; if (-not (Test-Path -LiteralPath $d)) { return 0 }; return @(Get-ChildItem -LiteralPath $d -Directory).Count }
function Labels-Of { param($Rec) return (@($Rec.sessions | ForEach-Object { if (Test-HordeTestMember $_ "label") { $_.label } else { "-" } }) -join ",") }

# NOT ONE try AROUND THE CHECKS (test/test-files-cli.ps1 says why): after an error no check expected, the
# trap goes on with the next statement of the script, and one try around everything is one statement.
Section "-All records the running, unretired sessions, never the master"
[System.IO.File]::WriteAllText((Join-Path $cwdK "PARKED-K.md"), "parked")
$r = Invoke-HordeFleetRecord -Deps $deps -Selector (New-HordeFleetSelectorAll) -Selection (All-Selection) -HordeHome $hh
Check ($r.id -ceq "20261016-091500") ("the id is the UTC second it was taken (" + $r.id + ")")
$back = Read-HordeFleetRecord -Id $r.id -HordeHome $hh
Check ($back.state -ceq "known") ("the record reads back and fits its schema (" + $back.reason + ")")
$rec = $back.value
$labels = Labels-Of $rec
Check ($labels -ceq "K,K1,L,-") ("exactly K, K1, L and the unlabelled running session are recorded (" + $labels + ")")
Check (-not ($labels -split "," -ccontains "M")) "the session labelled M is not recorded by -All"
Check (-not ($labels -split "," -ccontains "W")) "a session holding the warchief's role is not recorded by -All either"
Check (-not ($labels -split "," -ccontains "R")) "a retired session is not recorded, though it runs"
Check (-not ($labels -split "," -ccontains "S")) "a stopped session is not recorded"
$k = @($rec.sessions | Where-Object { $_.sessionId -ceq $ids["K"] })[0]
$k1 = @($rec.sessions | Where-Object { $_.sessionId -ceq $ids["K1"] })[0]
$t = @($rec.sessions | Where-Object { $_.sessionId -ceq $ids["T"] })[0]
Check ($k.role -ceq "orc" -and $k1.role -ceq "warg" -and $t.role -ceq "other") ("roles read through the alias table, a missing one is other (" + $k.role + "," + $k1.role + "," + $t.role + ")")
Check ((Get-HordeTestMember $k1 "parent") -ceq $ids["K"]) "a warg keeps its parent"
Check ($k.state -ceq "recorded" -and @($k.history).Count -eq 1 -and $k.history[0].state -ceq "recorded" -and $k.history[0].at -ceq "2026-10-16T09:15:00Z") "each session starts recorded, with its history stamped"
Check ((Get-HordeTestMember $k "parkedFile") -ceq (Join-Path $cwdK "PARKED-K.md")) "a PARKED file that is there is recorded"
Check (-not (Test-HordeTestMember $k1 "parkedFile")) "CONTROL: one that is not there is left out, never guessed"
Check ((Get-HordeTestMember $k1 "placement.left") -eq 60 -and (Get-HordeTestMember $k1 "placement.windowKey") -ceq "inst-1:1") "placement is what the terminal adapter answered"
Check (-not (Test-HordeTestMember $t "placement") -and @($r.notes | Where-Object { $_ -like "*placement unknown*" }).Count -ge 1) "a session the terminal cannot place is recorded without placement, and said"
Check (@($placementAsked | Where-Object { $_.sessionId -ceq $ids["K"] -and $_.instance -ceq "inst-1" -and $_.pane -ceq "7" }).Count -eq 1) "the terminal is asked by the registry's own instance and pane"
$bytes = [System.IO.File]::ReadAllBytes($r.path)
Check (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0) "the record file is ASCII"
$l = @($rec.sessions | Where-Object { $_.sessionId -ceq $ids["L"] })[0]
Check ($l.cwd -ceq $cwdU) "CONTROL: a folder with a character past ASCII reads back exactly, from its escape"
Check ($rec.selection.kind -ceq "all" -and $rec.agent -ceq "stand-in" -and $rec.host -ceq "stand-in") "the record says how it chose and which adapters it used"
Check (@(Get-ChildItem -LiteralPath (Split-Path $r.path) | Where-Object { $_.Name -like "*.tmp" }).Count -eq 0) "no temporary file is left beside the record"

Section "-Labels and -Exclude"
Next-Second
$r = Invoke-HordeFleetRecord -Deps $deps -Selector (New-HordeFleetSelectorLabels -Labels @("K", "M")) -Selection (Label-Selection @("K", "M")) -HordeHome $hh
Check ((Labels-Of $r.record) -ceq "K,M") ("the master is recorded when -Labels names it (" + (Labels-Of $r.record) + ")")
Next-Second
$r = Invoke-HordeFleetRecord -Deps $deps -Selector (New-HordeFleetSelectorAll) -Selection (All-Selection -Exclude @("K1")) -Exclude @("K1") -HordeHome $hh
Check ((Labels-Of $r.record) -ceq "K,L,-") ("-Exclude leaves a label out (" + (Labels-Of $r.record) + ")")
Next-Second
$before = Count-Records
Check (Throws { Invoke-HordeFleetRecord -Deps $deps -Selector (New-HordeFleetSelectorLabels -Labels @("K", "Q")) -Selection (Label-Selection @("K", "Q")) -HordeHome $hh } "no running, unretired session is labelled Q") "a label that names no running session is refused, never dropped"
Check (Throws { Invoke-HordeFleetRecord -Deps $deps -Selector (New-HordeFleetSelectorLabels -Labels @("S")) -Selection (Label-Selection @("S")) -HordeHome $hh } "labelled S") "a label of a stopped session is refused too"
Check ((Count-Records) -eq $before) "a refused selection writes nothing"

Section "fail closed, never empty"
$before = Count-Records
Check (Throws { Invoke-HordeFleetRecord -Deps $deps -Selector (New-HordeFleetSelectorLabels -Labels @("K")) -Selection (Label-Selection @("K")) -Exclude @("K") -HordeHome $hh } "no running session was chosen") "a selection that comes to nothing is refused: an empty record is never written"
[System.IO.File]::WriteAllText((Join-Path $regDir "99999999-0000-4000-8000-000000000009.json"), "{ not json")
Check (Throws { Invoke-HordeFleetRecord -Deps $deps -Selector (New-HordeFleetSelectorAll) -Selection (All-Selection) -HordeHome $hh } "cannot be read whole") "a registry with a record that cannot be read is refused whole, never read shorter"
Remove-Item -LiteralPath (Join-Path $regDir "99999999-0000-4000-8000-000000000009.json") -Force
$gone = [pscustomobject]@{ Now = $deps.Now; Agent = $deps.Agent; Host = $deps.Host; Registry = { Read-HordeRegistry -Root (Join-Path $work "no-registry") }.GetNewClosure() }
Check (Throws { Invoke-HordeFleetRecord -Deps $gone -Selector (New-HordeFleetSelectorAll) -Selection (All-Selection) -HordeHome $hh } "cannot be read whole") "a registry folder that is not there is refused"
$emptyRoot = Join-Path $work "empty-registry"
[void](New-Item -ItemType Directory -Path (Join-Path $emptyRoot "registry\sessions") -Force)
$empty = [pscustomobject]@{ Now = $deps.Now; Agent = $deps.Agent; Host = $deps.Host; Registry = { Read-HordeRegistry -Root $emptyRoot }.GetNewClosure() }
Check (Throws { Invoke-HordeFleetRecord -Deps $empty -Selector (New-HordeFleetSelectorAll) -Selection (All-Selection) -HordeHome $hh } "holds no session at all") "a registry with no session at all is refused, as a wrong folder"
$world.error = "the control folder is empty"
Check (Throws { Invoke-HordeFleetRecord -Deps $deps -Selector (New-HordeFleetSelectorAll) -Selection (All-Selection) -HordeHome $hh } "which sessions run cannot be read") "a liveness reading that cannot be trusted is refused"
$world.error = ""
$world.state[$ids["L"]] = "unknown"
Next-Second
$r = Invoke-HordeFleetRecord -Deps $deps -Selector (New-HordeFleetSelectorAll) -Selection (All-Selection) -HordeHome $hh
Check ((Labels-Of $r.record) -ceq "K,K1,-" -and @($r.notes | Where-Object { $_ -like "L *left out*" }).Count -eq 1) ("a session whose liveness is unknown is left out and said (" + (Labels-Of $r.record) + "; " + ($r.notes -join " | ") + ")")
$world.state[$ids["L"]] = "running"
Check ((Count-Records) -eq $before + 1) "CONTROL: only the one good record was added by this section"
$before = Count-Records
Check (Throws { Invoke-HordeFleetRecord -Deps $deps -Selector (New-HordeFleetSelectorAll) -Selection (All-Selection) -HordeHome $hh } "already recorded at") "a second record in the same second is refused, never merged"
Check ((Count-Records) -eq $before) "and writes nothing"
$hostAnswer.mode = "unknown"
Next-Second
$r = Invoke-HordeFleetRecord -Deps $deps -Selector (New-HordeFleetSelectorAll) -Selection (All-Selection) -HordeHome $hh
Check (@($r.record.sessions | Where-Object { Test-HordeTestMember $_ "placement" }).Count -eq 0 -and @($r.notes | Where-Object { $_ -like "no placement was read*" }).Count -eq 1) "a terminal that does not answer leaves every placement out, and says so"
$hostAnswer.mode = "known"

Section "the record's own checks"
$bad = $r.record
$bad.sessions = @($bad.sessions[0], $bad.sessions[0])
Check (Throws { Write-HordeFleetRecord -Dir (Join-Path (Get-HordeFleetHibernationsDir -HordeHome $hh) $bad.id) -Record $bad } "in the record twice") "a session twice is refused, nothing written"
$bad.sessions = @()
Check (Throws { Write-HordeFleetRecord -Dir (Join-Path (Get-HordeFleetHibernationsDir -HordeHome $hh) $bad.id) -Record $bad } "holds no session") "an empty record is refused by the writer too"
Check ((Read-HordeFleetRecord -Id "2026-10-16" -HordeHome $hh).state -ceq "unknown") "an id that is not yyyymmdd-hhmmss is refused"
Check ((Read-HordeFleetRecord -Id "20000101-000000" -HordeHome $hh).state -ceq "absent") "a hibernation that does not exist is absent"

Section "the command line"
$cliEnv = @{ HORDE_HOME = (Join-Path $work "cli-home"); WEZFLEET_ROOT = (Join-Path $work "no-registry") }
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "record") -Env $cliEnv
Check ($c.code -eq 2 -and $c.out -like "*exactly one of -All or -Labels*") ("fleet record with neither -All nor -Labels is a usage error, exit 2 (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "record", "-All", "-Labels", "K") -Env $cliEnv
Check ($c.code -eq 2) ("both is a usage error too (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "record", "-All") -Env $cliEnv
Check ($c.code -eq 1 -and $c.out -like "*cannot be read whole*") ("an unreadable registry fails the command with the reason (exit " + $c.code + ")")
Check (-not (Test-Path -LiteralPath (Join-Path $cliEnv.HORDE_HOME "fleet"))) "and leaves nothing in Horde's home"
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet", "wake", "20000101-000000", "-DryRun") -Env $cliEnv
Check ($c.code -eq 1 -and $c.out -like "*there is no hibernation 20000101-000000*") ("waking a hibernation that does not exist fails with the reason (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("fleet") -Env $cliEnv
Check ($c.code -eq 2) ("fleet with no verb is a usage error, never a prompt (exit " + $c.code + ")")
$c = Invoke-HordeCliProcess -Root $root -HordeArgs @("help") -Env $cliEnv
Check ($c.code -eq 0 -and $c.out -like "*horde fleet record*") "horde help lists the command"

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

Complete-HordeSuite -Success "a hibernation record holds exactly the running, unretired sessions asked for, and nothing is written when that cannot be known"
