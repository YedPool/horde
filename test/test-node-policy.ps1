# DOES A NODE START ONLY WHAT ITS OWN POLICY ALLOWS, AT A LEVEL AT OR BELOW ITS OWN CEILING?
#
# core/NodePolicy.ps1 (remote plan R9, the act path's A1; decisions of 2026-10-05). The policy file
# (schema/node-policy.v1) and the engine resolution together decide one spawn request. Every rule has
# a refusal case and a control; a request above the ceiling is refused and never lowered; a ceiling
# from anywhere but the node's own layers (L1, L4) never raises what the node allows.
#
# NEUTRAL NAMES ONLY (CONTRIBUTING 14): the fixture harnesses and layers of test-engine-resolve.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\EngineResolve.ps1")
. (Join-Path $root "core\NodePolicy.ps1")

$aText = [System.IO.File]::ReadAllText((Join-Path $root "test\fixtures\agent-descriptor\agents\harness-a\agent.json"))
$descriptors = @{ "harness-a" = (Read-HordeAgentDescriptorText -Text $aText -ExpectedName "harness-a") }
$fx = Join-Path $root "test\fixtures\engine-config"
function Read-Fixture { param([string]$Name) return ([System.IO.File]::ReadAllText((Join-Path $fx $Name)) | ConvertFrom-Json) }
function New-Layer { param([string]$Layer, $Doc) return [pscustomobject]@{ layer = $Layer; source = ("fixture " + $Layer); doc = $Doc } }
function New-Doc { param([object[]]$Rules = @()) return [pscustomobject]@{ schemaVersion = 1; rules = @($Rules) } }
function New-Rule { param([string]$Id, [hashtable]$Set, [hashtable]$Match = @{}, [string]$By = "user") return [pscustomobject]@{ id = $Id; match = [pscustomobject]$Match; set = [pscustomobject]$Set; writtenBy = $By } }
$builtin = New-Layer "L0" (Read-Fixture "builtin.json")
$now = [datetime]::Parse("2026-10-05T12:00:00Z").ToUniversalTime()
$orc = @{ role = "orc"; run = "20261005-120000-act"; label = "E"; title = "client search orc" }
function Resolve { param([object[]]$Extra = @()) return (Resolve-HordeEngine -Layers (@($builtin) + @($Extra)) -Target $orc -Descriptors $descriptors -Now $now) }
# The level asked for comes from a spawn (L5), the way the node builds one from the link's arguments.
function Ask { param([string]$Level) return (New-Layer "L5" (New-Doc @(New-Rule "spawn" @{ permission = $Level } @{} "cli"))) }
function Ceil { param([string]$Layer, [string]$Level, [string]$By = "user") return (New-Layer $Layer (New-Doc @(New-Rule ("ceiling-" + $Layer.ToLowerInvariant()) @{ "remote.permissionCeiling" = $Level } @{} $By))) }

$policyText = @'
{ "schemaVersion": 1,
  "repos": [ { "repoId": "github.com/example/app", "path": "C:\\code\\app" },
             { "repoId": "github.com/example/lib", "path": "C:\\code\\lib", "worktreeRoot": "D:\\trees\\lib" } ],
  "profiles": ["alpha"],
  "dailySpawnCap": 5 }
'@
$policy = Read-HordeNodePolicyText -Text $policyText
$req = [pscustomobject]@{ profile = "alpha"; repoId = "github.com/example/app"; worktree = $null }
function Decide { param($Res, $Request = $req, [int]$Today = 0, $Pol = $policy) return (Test-HordeRemotePolicy -Policy $Pol -Resolution $Res -Request $Request -SpawnsToday $Today) }
function Has { param($D, [string]$Like) return [bool](@($D.reasons | Where-Object { $_ -like $Like }).Count -ge 1) }

Write-Host ""
Write-Host "--- the registry: the level and the ceiling are settings of the one resolver ---" -ForegroundColor Cyan
$reg = @(Get-HordeConfigKeys)
$levels = @(Get-HordePermissionLevels | ForEach-Object { "" + $_.name })
$perm = @($reg | Where-Object { $_.name -ceq "permission" })
$ceil = @($reg | Where-Object { $_.name -ceq "remote.permissionCeiling" })
Check ($perm.Count -eq 1 -and (@($perm[0].value.values) -join ",") -ceq ($levels -join ",")) "permission is a registered key whose values are R0's levels, in R0's order"
Check ($ceil.Count -eq 1 -and (@($ceil[0].value.values) -join ",") -ceq ($levels -join ",")) "remote.permissionCeiling is a registered key whose values are R0's levels, in R0's order"
Check ($ceil.Count -eq 1 -and (@($ceil[0].layers) -join ",") -ceq "L1,L4" -and "" + $ceil[0].direction -ceq "lower-only") "the ceiling may be set only in the node's own layers, L1 and L4, and only lowered above L1"
Check ($perm.Count -eq 1 -and @($perm[0].layers) -cnotcontains "L0") "no built-in layer chooses a permission level: a level nobody chose is no level"

Write-Host ""
Write-Host "--- the policy file ---" -ForegroundColor Cyan
Check ($policy.state -eq "known") ("CONTROL: a well-formed policy reads" + $(if ($policy.state -ne "known") { " (" + $policy.reason + ")" } else { "" }))
function Bad { param([string]$Text, [string]$Like) $p = Read-HordeNodePolicyText -Text $Text; return [bool]($p.state -eq "unknown" -and $p.reason -like $Like) }
Check (Bad ($policyText.Replace('"dailySpawnCap": 5', '"dailySpawnCap": 5, "permissionCeiling": "bypass"')) "*permissionCeiling*") "a ceiling in the policy file is refused: the ceiling is a setting of the engine configuration, L1 and L4 only"
Check (Bad ($policyText.Replace('"C:\\code\\lib"', '"C:\\code\\app"').Replace('example/lib', 'example/app')) "*registered twice*") "a repository registered twice is refused"
Check (Bad ($policyText.Replace('"C:\\code\\app"', '"C:\\code\\..\\windows"')) "*'..'*") "a path with a '..' segment is refused"
Check (Bad ($policyText.Replace('"D:\\trees\\lib"', '"C:\\code\\lib.\\trees"')) "*'..'*") "a segment with a trailing dot is refused: Windows drops it, so the folder is another (F5)"
Check (Bad ($policyText.Replace('"D:\\trees\\lib"', '"C:\\code\\lib \\trees"')) "*'..'*") "a segment with a trailing space is refused too"
Check (Bad ($policyText.Replace('"D:\\trees\\lib"', '"C:\\code\\lib\\trees"')) "*inside its clone*") "a worktree root inside its clone is refused"
Check (Bad ($policyText.Replace('"C:\\code\\app"', '"code\\app"')) "*malformed*") "a relative path is refused"
Check (Bad ($policyText.Replace('["alpha"]', '["alpha", "alpha"]')) "*offered twice*") "a profile offered twice is refused"
Check (Bad ($policyText.Replace('"dailySpawnCap": 5', '"dailySpawnCap": 1001')) "*not a whole number from 0 to 1000*") "a daily cap above 1000 is refused as a typo"
Check (Bad ($policyText.Replace('"dailySpawnCap": 5', '"dailySpawnCap": 99999999999999999999')) "*not a whole number from 0 to 1000*") "a daily cap that overflows is refused, never read as no cap (review of PR #98, F2)"
$forgedPol = New-HordeKnown -Value ([pscustomobject]@{ repos = $policy.value.repos; profiles = @("alpha"); dailySpawnCap = [decimal]"99999999999999999999" })
$d = Decide (Resolve @(Ask "ask")) -Pol $forgedPol -Today 500000
Check (-not $d.allowed -and (Has $d "*not a whole number*starts nothing*")) "a cap that cannot be read refuses the spawn, even if the file reader was bypassed"
Check ($null -eq (ConvertTo-HordeNodeSpawnCap -Value 1.5) -and $null -eq (ConvertTo-HordeNodeSpawnCap -Value "5") -and (ConvertTo-HordeNodeSpawnCap -Value 0) -eq 0) "a cap is a whole number, never a fraction or text; 0 is a real cap"
Check (Bad ($policyText.Replace('"dailySpawnCap": 5', '"dailySpawnCap": 5, "dailySpawnCap": 9')) "*") "a key repeated in one object is refused"
Check (Bad ($policyText.Replace('example/app', ('example/' + [char]0x00E9))) "*not ASCII*") "a character that is not ASCII is refused"
$missing = Get-HordeNodePolicy -Path (Join-Path $env:TEMP ("horde-no-policy-" + [guid]::NewGuid().ToString("N") + ".json"))
Check ($missing.state -eq "absent") "a node with no policy file has an absent policy, not an empty one"
$d = Decide (Resolve @(Ask "ask")) -Pol $missing
Check (-not $d.allowed -and (Has $d "*no policy file*")) "and a node with no policy file lets a hub start nothing"
Check ((Get-HordeNodePolicyPath -HordeHome "C:\h") -ceq "C:\h\node\policy.json") "the policy file sits in the node folder of the Horde home"
# THE FILE, AS BYTES (review of #109): each is refused with its real cause, never as 'not JSON'.
$pf = Join-Path $env:TEMP ("horde-policy-bytes-" + [guid]::NewGuid().ToString("N") + ".json")
try {
    [System.IO.File]::WriteAllBytes($pf, [System.Text.Encoding]::ASCII.GetBytes($policyText))
    Check ((Get-HordeNodePolicy -Path $pf).state -eq "known") "CONTROL: the policy text saved as plain ASCII is read from its file"
    [System.IO.File]::WriteAllBytes($pf, [byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::ASCII.GetBytes($policyText)))
    $b = Get-HordeNodePolicy -Path $pf
    Check ($b.state -eq "unknown" -and $b.reason -like "*not plain ASCII*byte-order mark*" -and $b.reason -like ("*" + $pf + "*")) ("a policy file with a byte-order mark is refused, naming the file and the mark (" + $b.reason + ")")
    [System.IO.File]::WriteAllBytes($pf, [System.Text.Encoding]::UTF8.GetBytes($policyText.Replace('example/app', ('example/' + [char]0x00E9))))
    $b = Get-HordeNodePolicy -Path $pf
    Check ($b.state -eq "unknown" -and $b.reason -like "*not plain ASCII*holds a byte that is not ASCII*") ("a policy file holding a non-ASCII byte is refused, naming it (" + $b.reason + ")")
    [System.IO.File]::WriteAllBytes($pf, [System.Text.Encoding]::Unicode.GetBytes($policyText))
    $b = Get-HordeNodePolicy -Path $pf
    Check ($b.state -eq "unknown" -and $b.reason -like "*not plain ASCII*UTF-16*") ("a policy file saved as UTF-16 with no mark is named as such (" + $b.reason + ")")
} finally { if ((Split-Path -Leaf $pf) -match '^horde-policy-bytes-[0-9a-f]{32}\.json$') { Remove-Item -LiteralPath $pf -ErrorAction SilentlyContinue } }

Write-Host ""
Write-Host "--- where the session runs (decision 2: no worktree means the registered clone) ---" -ForegroundColor Cyan
$wd = Resolve-HordeNodeWorkdir -Policy $policy.value -RepoId "github.com/example/app"
Check ($wd.state -eq "known" -and $wd.value -ceq "C:\code\app") "no worktree: the registered clone"
$wd = Resolve-HordeNodeWorkdir -Policy $policy.value -RepoId "github.com/example/app" -Worktree ([pscustomobject]@{ name = "act-a3" })
Check ($wd.state -eq "known" -and $wd.value -ceq "C:\code\app-worktrees\act-a3") "a worktree, with no root declared: inside the sibling <clone>-worktrees folder"
$wd = Resolve-HordeNodeWorkdir -Policy $policy.value -RepoId "github.com/example/lib" -Worktree ([pscustomobject]@{ name = "fix-1" })
Check ($wd.state -eq "known" -and $wd.value -ceq "D:\trees\lib\fix-1") "a worktree under a declared root: inside that root"
foreach ($n in @("..", "a\b", "a/b", "x..y", "trailing.", "", "CON", "nul", "com1", "LPT9.txt", "aux.foo")) {
    $wd = Resolve-HordeNodeWorkdir -Policy $policy.value -RepoId "github.com/example/app" -Worktree ([pscustomobject]@{ name = $n })
    Check ($wd.state -eq "unknown") ("the worktree name '" + $n + "' is refused, so no path outside the root is ever built")
}
$wd = Resolve-HordeNodeWorkdir -Policy $policy.value -RepoId "github.com/example/other"
Check ($wd.state -eq "unknown" -and $wd.reason -like "*not registered*") "a repository the node has not registered is refused"
Check ((Test-HordeNodePathInside -Path "C:\a\bc" -Root "C:\a\b") -eq $false -and (Test-HordeNodePathInside -Path "C:\A\B\c" -Root "c:\a\b") -eq $true) "inside means whole segments, compared without case"

Write-Host ""
Write-Host "--- the request ---" -ForegroundColor Cyan
$d = Decide (Resolve @(Ask "ask"))
Check ($d.allowed -and $d.level -ceq "ask" -and $d.workdir -ceq "C:\code\app" -and @($d.reasons).Count -eq 0) "CONTROL: an offered profile, a registered repository, under the cap and under the ceiling is allowed"
$d = Decide (Resolve @(Ask "ask")) -Request ([pscustomobject]@{ profile = "beta"; repoId = "github.com/example/app"; worktree = $null })
Check (-not $d.allowed -and (Has $d "*does not offer the profile 'beta'*")) "a profile the node does not offer is refused"
$d = Decide (Resolve @(Ask "ask")) -Today 5
Check (-not $d.allowed -and (Has $d "*daily spawn cap of 5 is reached*")) "the sixth spawn of a day with a cap of 5 is refused"
$d = Decide (Resolve @(Ask "ask")) -Today 4
Check ($d.allowed) "CONTROL: the fifth is allowed"
$d = Decide (Resolve @())
Check (-not $d.allowed -and (Has $d "*no permission level is resolved*")) "a session with no permission level chosen is refused, never started at a default"
$d = Decide (Resolve @(Ask "ask")) -Request ([pscustomobject]@{ profile = "beta"; repoId = "github.com/example/none"; worktree = $null }) -Today 9
Check (-not $d.allowed -and @($d.reasons).Count -eq 3) "a request breaking three rules is told all three"

Write-Host ""
Write-Host "--- the ceiling: refused above it, never lowered; only the node's own layers set it ---" -ForegroundColor Cyan
$d = Decide (Resolve @(Ask "bypass"))
Check (-not $d.allowed -and $d.ceiling -ceq "edits" -and $d.ceilingFrom -ceq "default" -and (Has $d "*bypass is above this node's ceiling, edits*never lowered*")) "with no ceiling set, the default is the level below the top, and the top is refused"
$d = Decide (Resolve @(Ask "edits"))
Check ($d.allowed -and $d.level -ceq "edits") "CONTROL: the default ceiling itself is allowed"
$d = Decide (Resolve @((Ceil "L1" "bypass"), (Ask "bypass")))
Check ($d.allowed -and $d.ceiling -ceq "bypass" -and $d.ceilingFrom -like "L1*") "the node's owner may set the ceiling to the top in L1 (decision 3 of 2026-10-05), and bypass is then allowed"
$d = Decide (Resolve @((Ceil "L1" "plan"), (Ask "ask")))
Check (-not $d.allowed -and $d.level -ceq "ask" -and (Has $d "*ask is above*plan*")) "a request above a lowered ceiling is refused, and its level is reported as asked, not lowered"
$d = Decide (Resolve @((Ceil "L1" "edits"), (Ceil "L4" "plan" "cli"), (Ask "edits")))
Check (-not $d.allowed -and $d.ceiling -ceq "plan" -and $d.ceilingFrom -like "L4*") "a live rule (L4) may lower the ceiling"
$d = Decide (Resolve @((Ceil "L1" "edits"), (Ceil "L4" "bypass" "cli"), (Ask "bypass")))
Check (-not $d.allowed -and $d.ceiling -ceq "edits") "a live rule (L4) may not raise it"
# A LINK-SUPPLIED CEILING CANNOT RAISE IT (decision 3). The link has no field for it; if a node ever
# compiled one into its spawn layer (L5) or a run spec (L3), it still moves nothing up.
$d = Decide (Resolve @((Ceil "L5" "bypass" "cli"), (Ask "bypass")))
Check (-not $d.allowed -and $d.ceiling -ceq "edits") "a ceiling in the spawn layer (L5), where a link's arguments land, does not raise the default"
$d = Decide (Resolve @((Ceil "L1" "edits"), (Ceil "L5" "bypass" "cli"), (Ask "bypass")))
Check (-not $d.allowed -and $d.ceiling -ceq "edits") "nor an owner's ceiling"
$d = Decide (Resolve @((Ceil "L3" "bypass"), (Ask "bypass")))
Check (-not $d.allowed -and $d.ceiling -ceq "edits") "nor a run spec's (L3)"
# The provenance check is the second line behind the resolver: a resolution whose ceiling claims a
# layer outside L1 and L4 is not believed.
$forged = Resolve @(Ask "bypass")
$forged.settings["remote.permissionCeiling"] = [pscustomobject]@{ key = "remote.permissionCeiling"; answer = (New-HordeKnown -Value "bypass"); layer = "L5"; source = "link"; rule = "forged"; beaten = @(); refused = @() }
$d = Decide $forged
Check (-not $d.allowed -and $null -eq $d.ceiling -and (Has $d "*only the node's own layers*")) "a resolution whose ceiling comes from L5 is not believed: the request is refused, the ceiling is no level"
Check ((Get-HordeNodeCeiling -Resolution $forged).forged -eq $true) "and the ceiling says so by a field, not only in its reason"
$tie = Resolve @(Ask "ask")
$tie.settings["remote.permissionCeiling"] = [pscustomobject]@{ key = "remote.permissionCeiling"; answer = (New-HordeUnknown -Reason "two rules disagree"); layer = $null; source = $null; rule = $null; beaten = @(); refused = @() }
$d = Decide $tie
Check (-not $d.allowed -and (Has $d "*ceiling cannot be told*")) "a ceiling that cannot be told refuses every request"
# A CEILING THE OWNER WROTE AND THE RESOLVER REJECTED NEVER FALLS TO THE DEFAULT (review of PR #98, F1).
foreach ($badv in @("Plan", "read-only", "")) {
    $d = Decide (Resolve @((Ceil "L1" $badv), (Ask "edits")))
    Check (-not $d.allowed -and $null -eq $d.ceiling -and (Has $d ("*sets '" + $badv + "', which is not a permission level*"))) ("an owner's ceiling of '" + $badv + "' refuses every spawn, naming the value - never the default edits")
    $d = Decide (Resolve @((Ceil "L1" $badv), (Ask "plan")))
    Check (-not $d.allowed) ("and refuses even the lowest level under it ('" + $badv + "')")
}
$d = Decide (Resolve @((Ceil "L4" "Plan" "cli"), (Ask "plan")))
Check (-not $d.allowed -and $null -eq $d.ceiling) "a live rule's ceiling that is not a level refuses every spawn too"
$d = Decide (Resolve @((Ceil "L4" "plan" "cli"), (Ask "edits")))
Check (-not $d.allowed -and $d.ceiling -ceq "plan" -and $d.ceilingFrom -like "L4*") "a live rule alone lowers the default: plan in engine-live.json refuses edits"
$d = Decide (Resolve @((Ceil "L4" "ask" "cli"), (Ask "edits")))
Check (-not $d.allowed -and $d.ceiling -ceq "ask") "and ask refuses edits"
$d = Decide (Resolve @((Ceil "L4" "ask" "cli"), (Ask "ask")))
Check ($d.allowed -and $d.ceiling -ceq "ask") "CONTROL: under a live ask ceiling, ask is allowed"
$d = Decide (Resolve @((Ceil "L4" "bypass" "cli"), (Ask "bypass")))
Check (-not $d.allowed -and $d.ceiling -ceq "edits") "a live rule alone cannot raise the default: bypass stays refused"
$d = Decide (Resolve @((New-Layer "L4" (New-Doc @((New-Rule "c1" @{ "remote.permissionCeiling" = "plan" } @{} "cli"), (New-Rule "c2" @{ "remote.permissionCeiling" = "ask" } @{} "cli")))), (Ask "plan")))
Check (-not $d.allowed -and $null -eq $d.ceiling) "two live rules that disagree on the ceiling refuse every spawn"
# The environment moves nothing: the resolver reads no variable, so a variable named like the key
# changes no answer. CONTROL: the L1 rule above did.
$env:HORDE_REMOTE_PERMISSIONCEILING = "bypass"
try { $d = Decide (Resolve @(Ask "bypass")); Check (-not $d.allowed -and $d.ceiling -ceq "edits") "an environment variable named like the ceiling moves nothing" }
finally { Remove-Item Env:\HORDE_REMOTE_PERMISSIONCEILING -ErrorAction SilentlyContinue }

Complete-HordeSuite -Success "a node starts only what its own policy allows, at or below its own ceiling, and refuses everything else with every reason"
