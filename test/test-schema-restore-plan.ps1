# DOES schema/restore-plan.v1, WITH core/RestorePlan.ps1, ACCEPT EXACTLY THE PLANS SECTION 4 DESCRIBES?
#
# Step 1.3. A plan is valid when the schema and Test-HordeRestorePlan both find nothing. The golden
# fixtures under test/fixtures/restore-plan are the section-4 example, and one fleet as each host in
# the capability table receives it after the engine degrades it (D5). Every invalid fixture differs
# from the section-4 example in one place and must be refused for that reason, by name.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\Schema.ps1")
. (Join-Path $root "core\ReadShared.ps1")
. (Join-Path $root "core\Roles.ps1")
. (Join-Path $root "core\RestorePlan.ps1")

$schema = Get-HordeSchema -Name "restore-plan.v1"
$fx = Join-Path $root "test\fixtures\restore-plan"
function Read-Fixture { param([string]$Rel) $t = Read-HordeSharedText -Path (Join-Path $fx $Rel); $v = $t | ConvertFrom-Json; return ,$v }
function Findings { param($Plan) return @(Test-HordeRestorePlan -Plan $Plan) }

Write-Host ""
Write-Host "--- the schema agrees with the tables it names ---" -ForegroundColor Cyan
$native = @((Get-HordeRoleTable).native)
$enum = @($schema.properties.sessions.items.properties.role.enum)
Check ($native.Count -ge 3) ("CONTROL: core/roles.json was read (" + ($native -join ", ") + ")")
Check ((($enum | Sort-Object) -join ",") -ceq (($native | Sort-Object) -join ",")) ("the role enum is exactly core/roles.json's native roles (" + ($enum -join ", ") + ")")
# NOTHING IS KEYED BY A PANE NUMBER. Measured on the schema text itself, so a field added anywhere -
# a session, a node, the top - is seen. CONTROL: the same search finds a word known to be there.
$schemaText = [System.IO.File]::ReadAllText((Join-Path $root "schema\restore-plan.v1.json"))
$names = @([regex]::Matches($schemaText, '"([A-Za-z_$][A-Za-z0-9_$-]*)"\s*:') | ForEach-Object { $_.Groups[1].Value })
Check ($names -ccontains "slot") "CONTROL: the key scan finds the slot key"
$paneKeys = @($names | Where-Object { $_ -match 'pane' })
Check ($paneKeys.Count -eq 0) ("no key of the schema names a pane (" + ($paneKeys -join ", ") + ")")

Write-Host ""
Write-Host "--- valid plans ---" -ForegroundColor Cyan
$valid = @(Get-ChildItem -LiteralPath (Join-Path $fx "valid") -Filter *.json -File)
Check ($valid.Count -eq 4) ("CONTROL: the valid fixtures are there (" + $valid.Count + ")")
foreach ($f in $valid) {
    $found = Findings (Read-Fixture ("valid\" + $f.Name))
    Check ($found.Count -eq 0) ("valid: " + $f.BaseName + $(if ($found.Count) { " (" + ($found -join "; ") + ")" } else { "" }))
}

Write-Host ""
Write-Host "--- a degraded plan per host fits that host, and drops no session ---" -ForegroundColor Cyan

# What each host in section 4's capability table can apply. The engine that degrades a plan to these
# is step 4.2; here the fixtures are held to them, so a fixture cannot claim a host it does not fit.
# depth: how deep containers nest (a lone leaf is 0). tabs: at most this many per window.
$hosts = @{
    wezterm = @{ depth = 99; ratios = $true;  tabs = 99; workspaces = 99; named = $true }
    vscode  = @{ depth = 1;  ratios = $false; tabs = 1;  workspaces = 1;  named = $false }
    console = @{ depth = 0;  ratios = $false; tabs = 1;  workspaces = 1;  named = $false }
}
function Get-Depth { param($Node) $c = $Node.PSObject.Properties["children"]; if ($null -eq $c) { return 0 }; $m = 0; foreach ($k in @($c.Value)) { $d = Get-Depth $k; if ($d -gt $m) { $m = $d } }; return (1 + $m) }
function Get-Nodes { param($Node) $Node; $c = $Node.PSObject.Properties["children"]; if ($null -ne $c) { foreach ($k in @($c.Value)) { Get-Nodes $k } } }
function Get-Misfits {
    # Every way the plan asks more of the host than it has.
    param($Plan, $Cap)
    $out = @()
    $ws = @($Plan.layout.workspaces)
    if ($ws.Count -gt $Cap.workspaces) { $out += ("" + $ws.Count + " workspaces") }
    foreach ($w in $ws) {
        if (-not $Cap.named -and $null -ne $w.PSObject.Properties["name"]) { $out += "a workspace name" }
        foreach ($win in @($w.windows)) {
            $tabs = @($win.tabs)
            if ($tabs.Count -gt $Cap.tabs) { $out += ("" + $tabs.Count + " tabs in a window") }
            foreach ($t in $tabs) {
                $d = Get-Depth $t.root
                if ($d -gt $Cap.depth) { $out += ("splits " + $d + " deep in '" + $t.title + "'") }
                if (-not $Cap.ratios -and @(Get-Nodes $t.root | Where-Object { $null -ne $_.PSObject.Properties["ratio"] }).Count -gt 0) { $out += ("a ratio in '" + $t.title + "'") }
            }
        }
    }
    return $out
}
function Get-LeafSlots { param($Plan) foreach ($w in @($Plan.layout.workspaces)) { foreach ($win in @($w.windows)) { foreach ($t in @($win.tabs)) { Get-Nodes $t.root | Where-Object { $null -ne $_.PSObject.Properties["slot"] } | ForEach-Object { "$($_.slot)" } } } } }

$full = Read-Fixture "valid\host-wezterm.json"
$fullSessions = ($full.sessions | ConvertTo-Json -Depth 10 -Compress)
$fullSlots = (@(Get-LeafSlots $full | Sort-Object) -join ",")
Check (@(Get-Misfits $full $hosts.vscode).Count -ge 3) ("CONTROL: the full plan does NOT fit VS Code (" + (@(Get-Misfits $full $hosts.vscode) -join "; ") + ")")
Check ((Get-Depth $full.layout.workspaces[0].windows[0].tabs[1].root) -eq 2) "CONTROL: the full plan nests splits two deep, so flattening has something to do"
foreach ($h in @("wezterm", "vscode", "console")) {
    $p = Read-Fixture ("valid\host-" + $h + ".json")
    $mis = @(Get-Misfits $p $hosts[$h])
    Check ($mis.Count -eq 0) ($h + ": the plan asks nothing the host cannot do (" + ($mis -join "; ") + ")")
    Check (($p.sessions | ConvertTo-Json -Depth 10 -Compress) -ceq $fullSessions) ($h + ": the sessions are the full plan's, unchanged - degradation never touches them")
    $slots = (@(Get-LeafSlots $p | Sort-Object) -join ",")
    Check ($slots -ceq $fullSlots) ($h + ": every slot of the full plan is placed, once (" + $slots + ")")
}
$vs = Read-Fixture "valid\host-vscode.json"
Check ((@($vs.layout.workspaces[0].windows[1].tabs[0].root.children | ForEach-Object { $_.slot }) -join ",") -ceq "d,d1,d2") "vscode: the nested split is flattened into one level in its left-to-right, top-to-bottom order"
Check (@($vs.layout.workspaces[0].windows | ForEach-Object { $_.tabs[0].title } | Where-Object { $_ -notmatch '^(fleet|horde): ' }).Count -eq 0) "vscode: the workspace name survives as a prefix on every title"

Write-Host ""
Write-Host "--- invalid plans, each refused for its own reason ---" -ForegroundColor Cyan

# Each fixture, the finding it must produce, and whether JSON Schema alone can see it. The ones it
# cannot are the reason core/RestorePlan.ps1 exists, and the schema is shown to pass them.
$expect = [ordered]@{
    "wrong-version"              = @{ like = '$.schemaVersion is ''2'', not one of*'; n = 1; schema = $true }
    "no-sessions"                = @{ like = '$ has no ''sessions'''; n = 1; schema = $true }
    "no-layout"                  = @{ like = '$ has no ''layout'''; n = 1; schema = $true }
    "session-no-cwd"             = @{ like = '$.sessions`[0`] has no ''cwd'''; n = 1; schema = $true }
    "session-pane-key"           = @{ like = '$.sessions`[0`] has ''pane'', which the schema does not allow'; n = 1; schema = $true }
    "leaf-pane-key"              = @{ like = '$.layout.workspaces`[0`].windows`[0`].tabs`[0`].root.children`[0`] has ''pane'', which*'; n = 1; schema = $true }
    "plan-keyed-by-pane"         = @{ like = '$ has ''panes'', which the schema does not allow'; n = 1; schema = $true }
    "role-alias"                 = @{ like = '$.sessions`[0`].role is ''orchestrator'', not one of*'; n = 1; schema = $true }
    "resume-no-id"               = @{ like = '$.sessions`[0`].resume has no ''id'''; n = 1; schema = $true }
    "advisory-false"             = @{ like = '$.layout.advisory is ''False'', not one of*'; n = 1; schema = $true }
    "split-left"                 = @{ like = '*.root.split is ''left'', not one of*'; n = 1; schema = $true }
    "ratio-text"                 = @{ like = '*.root.ratio should be number'; n = 1; schema = $true }
    "tab-no-root"                = @{ like = '*.tabs`[0`] has no ''root'''; n = 1; schema = $true }
    "leaf-and-container"         = @{ like = '*.tabs`[0`].root is both a leaf and a container*'; n = 2; schema = $false }
    "neither-leaf-nor-container" = @{ like = '*.root.children`[2`] is neither a leaf nor a container*'; n = 1; schema = $false }
    "container-no-split"         = @{ like = '*.tabs`[0`].root is a container with no split'; n = 1; schema = $false }
    "container-no-children"      = @{ like = '*.tabs`[1`].root is a container with no children'; n = 1; schema = $false }
    "one-child"                  = @{ like = '*.root.children`[1`] is a container with 1 child*at least 2'; n = 1; schema = $false }
    "ratio-zero"                 = @{ like = '*.root.ratio is 0; a ratio lies strictly between 0 and 1'; n = 1; schema = $false }
    "ratio-one"                  = @{ like = '*.root.ratio is 1; a ratio lies strictly between 0 and 1'; n = 1; schema = $false }
    "dropped-session"            = @{ like = '$.sessions`[1`] (slot ''s2'') is not in the layout*never drop*'; n = 1; schema = $false }
    "slot-used-twice"            = @{ like = 'slot ''s1'' is placed 2 times*exactly once*'; n = 1; schema = $false }
    "slot-names-no-session"      = @{ like = '*.root.children`[2`] names slot ''s9'', which no session in the plan has'; n = 1; schema = $false }
    "duplicate-slot"             = @{ like = '$.sessions`[1`].slot ''s1'' is also the slot of $.sessions`[0`]'; n = 2; schema = $false }
    "duplicate-session-id"       = @{ like = '$.sessions`[1`].sessionId * is also the sessionId of $.sessions`[0`]'; n = 2; schema = $false }
    "parent-not-in-plan"         = @{ like = '$.sessions`[1`].parent * names no session in the plan'; n = 1; schema = $false }
    "parent-is-self"             = @{ like = '$.sessions`[1`].parent names the session itself'; n = 1; schema = $false }
    "slot-case-differs"          = @{ like = '*.root.children`[0`] names slot ''S1'', which no session in the plan has'; n = 2; schema = $false }
}
$invalid = @(Get-ChildItem -LiteralPath (Join-Path $fx "invalid") -Filter *.json -File | ForEach-Object { $_.BaseName })
$unlisted = @($invalid | Where-Object { -not $expect.Contains($_) })
$missing = @($expect.Keys | Where-Object { $invalid -cnotcontains $_ })
Check ($invalid.Count -eq $expect.Count -and $unlisted.Count -eq 0 -and $missing.Count -eq 0) ("every invalid fixture has an expectation and every expectation a fixture (" + $invalid.Count + " fixtures; unlisted: " + ($unlisted -join ", ") + "; missing: " + ($missing -join ", ") + ")")
foreach ($name in $expect.Keys) {
    $e = $expect[$name]
    $plan = Read-Fixture ("invalid\" + $name + ".json")
    $found = Findings $plan
    $hit = @($found | Where-Object { $_ -like $e.like })
    # Exactly n findings: the reason, and only what truly follows from it. Two for a node that is both
    # (the session placed only beneath it is then unplaced), a duplicate slot (the layout's s2 now
    # names no session), a duplicate id (the child's parent id is now its own), and a slot spelt in
    # another case (it names no session, and s1 is unplaced).
    Check ($hit.Count -eq 1 -and $found.Count -eq $e.n) ("invalid: " + $name + " (" + ($found -join "; ") + ")")
    if (-not $e.schema) {
        $bySchema = @(Test-HordeSchema -Value $plan -Schema $schema)
        Check ($bySchema.Count -eq 0) ("  and JSON Schema alone cannot see it (" + ($bySchema -join "; ") + ")")
    }
}

Write-Host ""
Write-Host "--- the gate reports every problem, not the first ---" -ForegroundColor Cyan
$two = Read-Fixture "valid\section-4-example.json"
$two.sessions[1].parent = $two.sessions[1].sessionId
$two.layout.workspaces[0].windows[0].tabs[0].root.ratio = 1
$found = Findings $two
Check ($found.Count -eq 2) ("a plan with two problems has two findings (" + ($found -join "; ") + ")")
Check (@(Findings (Read-Fixture "valid\section-4-example.json")).Count -eq 0) "CONTROL: the plan it was made from has none"

Write-Host ""
Write-Host "--- a plan built in PowerShell, from hashtables, is read like one parsed from JSON ---" -ForegroundColor Cyan
# The engine will build plans in memory before it writes one. The schema reads an IDictionary (it did
# already); the gate once read only PSObject.Properties, so on a hashtable every node had no slot and
# no children, and a valid plan was refused as "neither a leaf nor a container" (review of PR #17).
function ConvertTo-PlanHashtable {
    # The same tree, with every object a Hashtable and every array an object[].
    param($Value)
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $Value.PSObject.Properties) { $h[$p.Name] = ConvertTo-PlanHashtable $p.Value }
        return $h
    }
    if ($Value -is [System.Collections.IList]) { $a = @(foreach ($v in $Value) { ,(ConvertTo-PlanHashtable $v) }); return ,$a }
    return $Value
}
Check ((Get-HordePlanProp @{ slot = "s1" } "slot") -ceq "s1") "a hashtable's key is read"
# A PowerShell hashtable matches keys ignoring case; the plan's keys are exact, as the schema reads them.
Check ($null -eq (Get-HordePlanProp @{ SLOT = "s1" } "slot")) "a hashtable's key is matched exactly: SLOT is not slot"
$hPlan = ConvertTo-PlanHashtable (Read-Fixture "valid\host-wezterm.json")
Check ($hPlan -is [hashtable] -and $hPlan.layout.workspaces[0].windows[0].tabs[1].root -is [hashtable] -and $hPlan.sessions -is [object[]]) "CONTROL: the plan really is hashtables and arrays"
Check ($hPlan.layout.workspaces[0].windows[0].tabs[1].root.children[1].children.Count -eq 2) "CONTROL: the conversion kept the nested split (2 children two levels down)"
$found = Findings $hPlan
Check ($found.Count -eq 0) ("a valid plan built from hashtables has no findings (" + ($found -join "; ") + ")")
$hBad = ConvertTo-PlanHashtable (Read-Fixture "invalid\dropped-session.json")
$found = @(Findings $hBad)
Check ($found.Count -eq 1 -and $found[0] -like '$.sessions`[1`] (slot ''s2'') is not in the layout*') ("an invalid plan built from hashtables is refused for its own reason (" + ($found -join "; ") + ")")
$hBoth = ConvertTo-PlanHashtable (Read-Fixture "invalid\leaf-and-container.json")
$found = Findings $hBoth
Check (@($found | Where-Object { $_ -like '*.tabs`[0`].root is both a leaf and a container*' }).Count -eq 1) ("a hashtable node with a slot and children is both a leaf and a container (" + ($found -join "; ") + ")")

Complete-HordeSuite -Success "a restore plan is valid exactly when section 4 says it is"
