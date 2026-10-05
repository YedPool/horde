# IS A SESSION STARTED WITH EXACTLY THE ARGV ITS RESOLUTION, LEVEL AND NAME CALL FOR, AND NEVER WITH A
# GUESS?
#
# core/AgentLaunch.ps1 (remote plan R9 and engines E9, the act path's A1; issue #67). The launch plan
# is pure: the resolution, the level the node admitted, the session id, the name and the prompt in;
# the program and argv out, or the reason there are none. Nothing is started here.
#
# NEUTRAL NAMES ONLY (CONTRIBUTING 14): the fixture harness harness-a of test-engine-resolve, and a
# fixture launch adapter registered below. Its plan level needs the precondition folder-ok, and its
# bypass level is inexpressible: the two refusals a real node meets.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\EngineResolve.ps1")
. (Join-Path $root "core\AgentLaunch.ps1")

$aText = [System.IO.File]::ReadAllText((Join-Path $root "test\fixtures\agent-descriptor\agents\harness-a\agent.json"))
$descA = Read-HordeAgentDescriptorText -Text $aText -ExpectedName "harness-a"
$descNamed = Read-HordeAgentDescriptorText -Text ($aText.Replace('"session.remoteName": { "support": "unverified"', '"session.remoteName": { "support": "yes"')) -ExpectedName "harness-a"
$fx = Join-Path $root "test\fixtures\engine-config"
$builtin = [pscustomobject]@{ layer = "L0"; source = "fixture L0"; doc = ([System.IO.File]::ReadAllText((Join-Path $fx "builtin.json")) | ConvertFrom-Json) }
$now = [datetime]::Parse("2026-10-05T12:00:00Z").ToUniversalTime()
function Resolve { param($Desc = $descNamed, [object[]]$Extra = @()) return (Resolve-HordeEngine -Layers (@($builtin) + @($Extra)) -Target @{ role = "orc" } -Descriptors @{ "harness-a" = $Desc } -Now $now) }
$sid = "0a1b2c3d-1111-4222-8333-444455556666"

# The fixture adapter. It records what it was handed, so the tests can see the plan passed it on.
$script:handed = $null
$script:verifies = @()
Register-HordeLaunchAdapter -Name "harness-a" -Program "harness-a" `
    -Argv { param($s) $script:handed = $s; $a = @("--id", $s.sessionId) + @($s.permissionArgs); if ("" + $s.name -ne "") { $a += @("--title", $s.name) }; if ("" + $s.prompt -ne "") { $a += @($s.prompt) }; New-HordeKnown -Value ([string[]]$a) } `
    -Preconditions { param($n) $script:verifies } `
    -Identify { param($id, $view) New-HordeAbsent -Note "fixture" } `
    -ReadMode { param($id, $view) New-HordeAbsent -Note "fixture" }
$name = Format-HordeSessionName -Label "E" -Title "client search orc"

Write-Host ""
Write-Host "--- the name: label plus run title, one line, capped (decision 4 of 2026-10-05) ---" -ForegroundColor Cyan
Check ($name.state -eq "known" -and $name.value -ceq "E client search orc") "the label and the run title, joined by a space"
Check ((Format-HordeSessionName -Label "Q12").value -ceq "Q12") "no title: the label alone"
$n = Format-HordeSessionName -Label "E" -Title ("tab`there`r`nnew " + [char]0x00E9 + "  line")
Check ($n.value -ceq "E tab here new line") "tabs, line breaks, runs of spaces and characters outside printable ASCII become single spaces"
$long = Format-HordeSessionName -Label "AB12" -Title ("word " * 30)
Check ($long.value.Length -le 60 -and $long.value.StartsWith("AB12 word") -and -not $long.value.EndsWith(" ") -and $long.value.EndsWith("word")) ("a long title is cut at a word, at most 60 characters (" + $long.value.Length + ")")
$one = Format-HordeSessionName -Label "E" -Title ("x" * 100)
Check ($one.value.Length -eq 60 -and $one.value.StartsWith("E x")) "one long word is cut at the cap"
foreach ($bad in @("e", "ABC", "E0", "", $null, "E 1")) {
    Check ((Format-HordeSessionName -Label $bad -Title "t").state -eq "unknown") ("'" + $bad + "' is not a label, so there is no name")
}

Write-Host ""
Write-Host "--- the plan ---" -ForegroundColor Cyan
$p = New-HordeLaunchPlan -Resolution (Resolve) -Level "ask" -SessionId $sid -Name $name -Prompt "hello"
Check ($p.state -eq "known") ("CONTROL: a resolved engine, an expressible level and a name give a plan" + $(if ($p.state -ne "known") { " (" + $p.reason + ")" } else { "" }))
Check ($p.value.program -ceq "harness-a" -and $p.value.harness -ceq "harness-a" -and $p.value.level -ceq "ask") "the plan names the adapter's program by command name, the harness and the level"
Check ((@($p.value.argv) -join "|") -ceq ("--id|" + $sid + "|--mode|careful|--title|E client search orc|hello")) "the argv is the adapter's, from the descriptor's fragment for the level, the id, the name and the prompt"
Check ($script:handed.name -ceq "E client search orc") "the adapter is handed the name; it never formats one"
$p = New-HordeLaunchPlan -Resolution (Resolve -Desc $descA) -Level "ask" -SessionId $sid -Name $name
Check ($p.state -eq "known" -and (@($p.value.argv) -cnotcontains "--title") -and @($p.value.notes | Where-Object { $_ -like "unnamed:*session.remoteName*" }).Count -eq 1) "a harness whose session.remoteName is not yes gets no name, and the plan says why"
$p = New-HordeLaunchPlan -Resolution (Resolve) -Level "ask" -SessionId $sid -Name (Format-HordeSessionName -Label "lower")
Check ($p.state -eq "known" -and (@($p.value.argv) -cnotcontains "--title")) "no name: no name fragment at all, and the start still goes ahead"

Write-Host ""
Write-Host "--- refusals: never a nearby level, never an unverified precondition (issue #67) ---" -ForegroundColor Cyan
$p = New-HordeLaunchPlan -Resolution (Resolve) -Level "bypass" -SessionId $sid -Name $name
Check ($p.state -eq "unknown" -and $p.reason -like "*cannot express*bypass*never lowered*") "a level the harness cannot express is refused, never lowered"
$script:verifies = @()
$p = New-HordeLaunchPlan -Resolution (Resolve) -Level "plan" -SessionId $sid -Name $name
Check ($p.state -eq "unknown" -and $p.reason -like "*folder-ok*not verified*") "a level whose precondition the adapter did not verify is refused, naming it"
$script:verifies = @("folder-ok")
$p = New-HordeLaunchPlan -Resolution (Resolve) -Level "plan" -SessionId $sid -Name $name
Check ($p.state -eq "known" -and (@($p.value.argv) -join " ") -like "*--mode look*") "CONTROL: the adapter verified it, and the level's fragment is used"
$script:verifies = @("folder-ok", "something-else")
$p = New-HordeLaunchPlan -Resolution (Resolve) -Level "plan" -SessionId $sid -Name $name
Check ($p.state -eq "known") "a name the adapter reports but the level did not ask for is ignored"
$script:verifies = @("Folder-OK")
$p = New-HordeLaunchPlan -Resolution (Resolve) -Level "plan" -SessionId $sid -Name $name
Check ($p.state -eq "unknown") "a precondition is matched exactly: Folder-OK is not folder-ok"
$script:verifies = @()
$p = New-HordeLaunchPlan -Resolution (Resolve) -Level "Ask" -SessionId $sid -Name $name
Check ($p.state -eq "unknown") "Ask is not a level"
$p = New-HordeLaunchPlan -Resolution (Resolve) -Level "ask" -SessionId "not-an-id" -Name $name
Check ($p.state -eq "unknown" -and $p.reason -like "*not a session id*") "a session id the harness does not take is refused"
$unres = Resolve -Extra @([pscustomobject]@{ layer = "L5"; source = "fixture L5"; doc = [pscustomobject]@{ schemaVersion = 1; rules = @([pscustomobject]@{ id = "x"; match = [pscustomobject]@{}; set = [pscustomobject]@{ harness = "harness-z" }; writtenBy = "cli" }) } })
$p = New-HordeLaunchPlan -Resolution $unres -Level "ask" -SessionId $sid -Name $name
Check ($p.state -eq "unknown" -and $p.reason -like "*not resolved*") "an engine that did not resolve gives no plan"
$script:HordeLaunchAdapters.Clear()
$p = New-HordeLaunchPlan -Resolution (Resolve) -Level "ask" -SessionId $sid -Name $name
Check ($p.state -eq "unknown" -and $p.reason -like "*no launch adapter*harness-a*") "a harness with no launch adapter cannot be started"
Register-HordeLaunchAdapter -Name "harness-a" -Program "harness-a" -Argv { param($s) New-HordeUnknown -Reason "the fixture adapter refuses" } -Preconditions { param($n) @() } -Identify { param($id, $v) $null } -ReadMode { param($id, $v) $null }
$p = New-HordeLaunchPlan -Resolution (Resolve) -Level "ask" -SessionId $sid -Name $name
Check ($p.state -eq "unknown" -and $p.reason -ceq "the fixture adapter refuses") "an adapter's own refusal is the plan's answer"

Write-Host ""
Write-Host "--- the port ---" -ForegroundColor Cyan
Check (Throws { Register-HordeLaunchAdapter -Name "x" -Program "C:\bin\x.exe" -Argv { 1 } -Preconditions { 1 } -Identify { 1 } -ReadMode { 1 } } "never a path") "an adapter names its program by command name, never by path"
Check (Throws { Register-HordeLaunchAdapter -Name "X" -Program "x" -Argv { 1 } -Preconditions { 1 } -Identify { 1 } -ReadMode { 1 } } "lowercase") "an adapter name is lower case"
$files = @(Get-HordeLaunchAdapterFiles -Root $root)
Check ($files.Count -ge 1 -and @($files | Where-Object { $_ -notlike "*\agents\*\Launch.ps1" }).Count -eq 0) ("the adapter files are found by folder, agents\<name>\Launch.ps1 (" + $files.Count + ")")

Complete-HordeSuite -Success "a launch plan is exactly what its resolution, level and name call for, or a named refusal"
