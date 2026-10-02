# DO THE LINK CONTRACTS SAY EXACTLY WHAT MAY CROSS, AND REFUSE EVERYTHING ELSE?
#
# Plan step R1 (planning/execution-plan-remote.md). The link between a hub and a node is an
# allowlisted command protocol, never a remote shell: schema/link-frame.v1 is the envelope,
# schema/link-verbs.v1 the verb table, and remote/Contract.ps1 enforces what the schemas cannot say.
# Most of this suite proves REFUSALS - one per rule, each built from the real contract by changing one
# thing, each asserted to fail for its own reason - because a checker that refused everything would
# pass a "must refuse" check too. The controls against that are first: the real contract and every
# golden fixture produce no findings at all.
#
# The four claims the plan names, and where each is proved:
#   - a verb row without an effect class fails ................................ section B
#   - no verb takes a command line, script, program path, environment or path ... section C
#   - no verb returns raw worker context: results are closed and capped ....... section D
#   - the verbs the design leaves out are each refused ......................... section B
# and one it implies: nothing in remote/ can start a program or a shell ........ section H

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "remote\Contract.ps1")
. (Join-Path $root "core\Tristate.ps1")

$fx = Join-Path $here "fixtures\link"

# A FIXTURE IS DATA, NOT A SCHEMA: read as UTF-8 JSON. Read-HordeSchemaFile checks that what it reads
# is a schema (review of PR #27), so a frame read through it is refused for its member v.
function Read-Data { param([string]$Path) return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) }
function Read-Fx { param([string]$Name) return (Read-Data (Join-Path $fx $Name)) }
function Copy-Json { param($Value) return (($Value | ConvertTo-Json -Depth 40) | ConvertFrom-Json) }
function Says {
    # Is there a finding containing Text? A boolean, never the matching items.
    param($Findings, [string]$Text)
    # Contains, not -like: a path such as $.repos[0] holds brackets, which -like reads as a pattern.
    return (@($Findings | Where-Object { "$_".Contains($Text) }).Count -gt 0)
}
function Show { param($Findings) foreach ($f in @($Findings)) { Write-Host ("         finding: " + $f) -ForegroundColor DarkYellow } }
function Without-Allowlist {
    # The findings that are not the verb allowlist's. A probe verb is never on remote/Contract.ps1's
    # allowlist, so a control built on one asserts that nothing ELSE was found - and that the allowlist
    # did name it, so the filter is not hiding a silent checker.
    param($Findings)
    return @($Findings | Where-Object { -not "$_".Contains("is not a verb of remote/Contract.ps1's allowlist") })
}

$contract = Get-HordeLinkContract
$realVerbs = Get-HordeSchema -Name "link-verbs.v1"
$realFrame = Get-HordeSchema -Name "link-frame.v1"

Write-Host ""
Write-Host "--- A. CONTROLS: the real contract and every golden fixture are valid ---" -ForegroundColor Cyan

$f = @(Test-HordeLinkFrameContract -Frame $realFrame)
Check ($f.Count -eq 0) "schema/link-frame.v1 passes every static rule"; Show $f
$f = @(Test-HordeLinkVerbTable -Verbs $realVerbs)
Check ($f.Count -eq 0) "schema/link-verbs.v1 passes every static rule"; Show $f
Check ($contract.rows.Count -eq 13) "the v1 table has the 13 verbs this step defines (the rest are named as deferred in its description)"

$golden = @(Get-ChildItem -LiteralPath (Join-Path $fx "frames") -Filter "*.json" | Sort-Object Name)
Check ($golden.Count -eq 14) "there are 14 golden frames, one per kind and verb shape this step covers"
foreach ($g in $golden) {
    $f = @(Test-HordeLinkFrame -Frame (Read-Data $g.FullName) -Contract $contract)
    Check ($f.Count -eq 0) ("golden frame " + $g.Name + " is valid"); Show $f
}
$kinds = @($golden | ForEach-Object { "$((Read-Data $_.FullName).kind)" } | Sort-Object -Unique)
Check ((@($kinds) -join ",") -ceq "ack,bye,hello,ping,pong,req,res") "the golden frames cover every kind but evt, which no v1 verb has"
$f = @(Test-HordeContractDocument -Value (Read-Fx "manifest.json") -SchemaName "node-manifest.v1")
Check ($f.Count -eq 0) "the golden node manifest is valid"; Show $f
$f = @(Test-HordeContractDocument -Value (Read-Fx "transport-local.json") -SchemaName "transport-capabilities.v1")
Check ($f.Count -eq 0) "the golden transport capability file is valid"; Show $f
$f = @(Test-HordeContractDocument -Value (Read-Fx "overlay.json") -SchemaName "overlay-endpoint.v1")
Check ($f.Count -eq 0) "the golden overlay endpoint is valid"; Show $f

# The same checker, on a table with ONE change. Returns its findings.
#
# ONLY THE ROWS THE CHANGE TOUCHES ARE CHECKED: a row added, a row whose text now differs from the real
# one, and the rows named in -Keep (a change to a definition names the verb that uses it). The rest are
# the real rows, which section A's control proves produce no findings, so leaving them out loses
# nothing - and a whole-table check costs about a second, which over a hundred refusals made this suite
# the slowest in the repository (measured 2026-09-30).
$realRowText = @(@($realVerbs.'x-horde-verbs') | ForEach-Object { $_ | ConvertTo-Json -Depth 5 -Compress })
function Test-VerbsWith {
    param([scriptblock]$Change, [string[]]$Keep = @())
    $v = Copy-Json $realVerbs
    $null = & $Change $v
    $rows = @($v.'x-horde-verbs')
    $kept = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $text = $rows[$i] | ConvertTo-Json -Depth 5 -Compress
        if ($i -ge $realRowText.Count -or $text -cne $realRowText[$i] -or $Keep -ccontains "$($rows[$i].name)") { [void]$kept.Add($rows[$i]) }
    }
    $v.'x-horde-verbs' = @($kept)
    return @(Test-HordeLinkVerbTable -Verbs $v)
}
function Add-Row {
    # A new row on a table copy, with node.info's harmless args and a result that is certainly valid.
    param($Doc, [string]$Name, [string]$Effect = "read", [string]$Direction = "hub-to-node", [string]$ArgsRef = "#/definitions/no-args", [string]$ResultRef = "#/definitions/report-receipt")
    $row = [pscustomobject]@{ name = $Name; direction = $Direction; effect = $Effect; since = 1; args = $ArgsRef; result = $ResultRef }
    $Doc.'x-horde-verbs' = @($Doc.'x-horde-verbs') + $row
}
function Add-Def {
    param($Doc, [string]$Name, [string]$Json)
    $Doc.definitions | Add-Member -NotePropertyName $Name -NotePropertyValue ($Json | ConvertFrom-Json)
}
function Refuses {
    # This one table change is refused, with a finding that names Text - the reason for THIS rule, so
    # a table refused for some other reason does not pass.
    param([scriptblock]$Change, [string]$Text, [string]$What, [string[]]$Keep = @())
    $got = @(Test-VerbsWith $Change $Keep)
    Check (Says $got $Text) $What
    if (-not (Says $got $Text)) { Show $got }
}

Write-Host ""
Write-Host "--- B. every row has an effect class, and the verbs the design leaves out are refused ---" -ForegroundColor Cyan

Refuses { param($v) $v.'x-horde-verbs'[0].PSObject.Properties.Remove("effect") } "has no 'effect'" "a verb row without an effect class is refused"
Refuses { param($v) $v.'x-horde-verbs'[0].effect = "delete" } "is 'delete', not one of" "an effect outside read, write, spawn and kill is refused"
Refuses { param($v) $v.'x-horde-verbs'[0].PSObject.Properties.Remove("since") } "has no 'since'" "a verb row without since is refused"
Refuses { param($v) $v.'x-horde-verbs'[0].since = 2 } "after this table's protocol" "a verb since a later protocol than the table's is refused"
Refuses { param($v) $v.'x-horde-verbs'[1].name = "node.info" } "is in the table twice" "a verb named twice is refused" @("node.info")
Refuses { param($v) $v.'x-horde-verbs'[0] | Add-Member -NotePropertyName handler -NotePropertyValue "Invoke-Anything" } "does not allow" "a row with a member the row definition does not have is refused"
Refuses { param($v) Add-Row $v "alert.forward" "spawn" "node-to-hub" } "never asks the hub to spawn, drive or kill" "a node-to-hub verb that spawns is refused"
Refuses { param($v) Add-Row $v "alert.forward" "drive" "node-to-hub" } "never asks the hub to spawn, drive or kill" "a node-to-hub verb that drives a session is refused"

# DRIVE: session.deliver types into a running session, which may run with prompts bypassed. Classed
# write, it escaped the permission ceiling that gates spawn (review of PR #40). Its class is pinned in
# remote/Contract.ps1, so a table that reclasses it, or any verb, is refused.
Check ("$($contract.rows['session.deliver'].effect)" -ceq "drive") "session.deliver is classed drive in the real table"
Check (@($realVerbs.definitions.'verb-row'.properties.effect.enum) -ccontains "drive") "drive is an effect class of the verb-row definition"
Check ("$($realVerbs.definitions.'session-deliver-args'.description)".Contains("ONLY a session this hub spawned on this node")) "the deliver contract says it may target only a session this hub spawned on the node"
$deliverAt = [array]::IndexOf(@($realVerbs.'x-horde-verbs' | ForEach-Object { "$($_.name)" }), "session.deliver")
Refuses ([scriptblock]::Create("param(`$v) `$v.'x-horde-verbs'[$deliverAt].effect = 'write'")) "remote/Contract.ps1 classes it 'drive'" "a table that classes session.deliver write is refused: drive is pinned" @("session.deliver")
Refuses { param($v) $v.'x-horde-verbs'[5].effect = "read" } "remote/Contract.ps1 classes it 'spawn'" "a table that reclasses session.spawn read is refused" @("session.spawn")
Refuses { param($v) $v.'x-horde-verbs'[0].args = "#/definitions/nothing-here" } "which is not there" "a row whose args name no definition is refused"
Refuses { param($v) $v.'x-horde-verbs'[0].result = "no-such-schema.v1" } "which is not there" "a row whose result names no schema is refused"
# THE ROW RULES ARE THE REAL FILE'S. A table that loosens its own verb-row must not get a pass.
Refuses { param($v) $v.definitions.'verb-row'.required = @("name"); $v.'x-horde-verbs'[0].PSObject.Properties.Remove("effect") } "has no 'effect'" "a table cannot loosen verb-row for itself: the real definition is used"

foreach ($absent in @("exec", "shell.open", "script.run", "file.read", "file.write", "env.get", "config.set", "provider.define", "credential.get", "secret.send", "process.kill", "pane.kill", "node.update", "node.upgrade", "clone.download")) {
    Refuses ([scriptblock]::Create("param(`$v) Add-Row `$v '$absent'")) "is a verb the protocol never has" ("the absent verb '" + $absent + "' is refused")
}
# CONTROL for the word match: a verb named with 'profile' holds the letters of 'file' and is not refused.
$f = @(Test-VerbsWith { param($v) Add-Row $v "profile.list" })
Check ((Without-Allowlist $f).Count -eq 0 -and $f.Count -eq 1) "a verb whose name only contains the letters of a refused word (profile.list) is refused only for not being on the allowlist"; Show $f

Write-Host ""
Write-Host "--- C. no verb takes a command line, a program, a path or an environment, or an open object ---" -ForegroundColor Cyan

function Add-ArgVerb {
    # A new verb whose args are no-args plus one property.
    param($Doc, [string]$Prop, [string]$Json)
    Add-Def $Doc "probe-args" ('{ "type": "object", "additionalProperties": false, "properties": { "' + $Prop + '": ' + $Json + ' } }')
    Add-Row $Doc "probe.thing" "read" "hub-to-node" "#/definitions/probe-args"
}
$capped = '{ "type": "string", "pattern": "\\S", "x-horde-cap": "nameBytes" }'
foreach ($bad in @("argv", "commandLine", "cmd", "script", "program", "programPath", "exe", "path", "filePath", "fileName", "workingDirectory", "cwd", "env", "environment", "shell", "code")) {
    $j = $capped
    Refuses ([scriptblock]::Create("param(`$v) Add-ArgVerb `$v '$bad' '$j'")) "is an argument named like a command" ("an argument named '" + $bad + "' is refused")
}
Refuses { param($v) Add-ArgVerb $v "env" '{ "type": "object", "additionalProperties": false, "properties": { "name": { "type": "string", "x-horde-cap": "nameBytes" } } }' } "is an argument named like a command" "an environment map is refused even when closed"
Refuses { param($v) Add-ArgVerb $v "options" '{ "type": "object", "properties": { "name": { "type": "string", "x-horde-cap": "nameBytes" } } }' } "is an open object" "an argument that is an object without additionalProperties false is refused"
Refuses { param($v) Add-ArgVerb $v "options" '{ "type": "object", "additionalProperties": true, "properties": {} }' } "is an open object" "an argument that allows any extra keys is refused"
Refuses { param($v) Add-ArgVerb $v "options" '{ "type": "object", "additionalProperties": false }' } "with no properties" "an object argument with no properties list is refused"
Refuses { param($v) Add-ArgVerb $v "anything" '{ "description": "whatever" }' } "has no type" "an untyped argument is refused"
Refuses { param($v) Add-ArgVerb $v "items" '{ "type": "array", "x-horde-cap": "listItems" }' } "with no items schema" "an array argument whose items are unchecked is refused"
Refuses { param($v) Add-ArgVerb $v "items" '{ "type": "array", "items": { "type": "integer" } }' } "does not name the listItems cap" "an array argument with no cap is refused"
Refuses { param($v) Add-ArgVerb $v "note" '{ "type": "string" }' } "is a string that names no cap" "a string argument with no cap is refused"
Refuses { param($v) Add-ArgVerb $v "note" '{ "type": "string", "x-horde-cap": "gigaBytes" }' } "which x-horde-limits does not have" "a string argument naming a cap that does not exist is refused"
Refuses { param($v) Add-Def $v "probe-args" '{ "type": "string", "x-horde-cap": "nameBytes" }'; Add-Row $v "probe.thing" "read" "hub-to-node" "#/definitions/probe-args" } "args is not an object" "a verb whose args are not an object is refused"
Refuses { param($v) Add-Def $v "loop" '{ "type": "object", "additionalProperties": false, "properties": { "next": { "$ref": "#/definitions/loop" } } }'; Add-Row $v "probe.thing" "read" "hub-to-node" "#/definitions/loop" } "a recursive shape has no bound" "a recursive argument shape is refused"
# The nested rule reaches inside the real spawn arguments too: change one closed object there.
Refuses { param($v) $v.definitions.'session-spawn-args'.properties.worktree.additionalProperties = $true } "is an open object" "opening a nested object inside session.spawn's args is refused" @("session.spawn")
Refuses { param($v) $v.definitions.'session-spawn-args'.properties | Add-Member -NotePropertyName "extraEnv" -NotePropertyValue ('{ "type": "string", "x-horde-cap": "nameBytes" }' | ConvertFrom-Json) } "is an argument named like a command" "adding an environment argument to session.spawn is refused" @("session.spawn")
# CONTROL for the word match on arguments: profile, repoId and handoffRef are not refused words.
$f = @(Test-VerbsWith { param($v) Add-ArgVerb $v "profileName" $capped })
Check ((Without-Allowlist $f).Count -eq 0 -and $f.Count -eq 1) "an argument named profileName (holding the letters of file) is not refused for its name"; Show $f

Write-Host ""
Write-Host "--- C2. the verbs, and every argument each takes, are an allowlist in remote/Contract.ps1 ---" -ForegroundColor Cyan

# The word lists miss what nobody thought to list. The review of PR #40 found these verbs and these
# argument names passing them; an allowlist refuses each without having heard of it.
foreach ($novel in @("node.restart", "repo.push", "profile.define", "auth.login", "policy.set", "ceiling.raise")) {
    Refuses ([scriptblock]::Create("param(`$v) Add-Row `$v '$novel'")) "is not a verb of remote/Contract.ps1's allowlist" ("the verb '" + $novel + "', on no word list, is refused because no allowlist names it")
}
foreach ($novel in @("url", "remoteUrl", "uri", "flags", "extraArgs", "options", "hook", "stdin", "mcp", "plugin", "systemPrompt", "settings")) {
    Refuses ([scriptblock]::Create("param(`$v) `$v.definitions.'session-spawn-args'.properties | Add-Member -NotePropertyName '$novel' -NotePropertyValue ('$capped' | ConvertFrom-Json)")) ("args has '" + $novel + "', which is not an argument session.spawn may take") ("an argument named '" + $novel + "' added to session.spawn is refused by its allowlist") @("session.spawn")
}
Refuses { param($v) $v.definitions.'session-spawn-args'.properties.worktree.properties | Add-Member -NotePropertyName "url" -NotePropertyValue ($capped | ConvertFrom-Json) } "args has 'worktree.url'" "a nested argument is on the allowlist by its path: worktree.url is refused" @("session.spawn")
Refuses { param($v) $v.definitions.'session-resume-args'.properties | Add-Member -NotePropertyName "prompt" -NotePropertyValue ($capped | ConvertFrom-Json) } "args has 'prompt', which is not an argument session.resume may take" "an argument allowed to one verb (spawn's prompt) is refused on another (resume)" @("session.resume")
Refuses { param($v) $v.definitions.'session-spawn-args'.properties | Add-Member -NotePropertyName "name" -NotePropertyValue ($capped | ConvertFrom-Json) } "args has 'name', which is not an argument session.spawn may take" "an argument allowed under one parent (worktree.name) is refused at another (name)" @("session.spawn")
Refuses { param($v) $v.definitions.'unowned-report-args'.properties.sessions.items.properties | Add-Member -NotePropertyName "cmdline" -NotePropertyValue ($capped | ConvertFrom-Json) } "args has 'sessions[].cmdline'" "an argument inside an array's items is on the allowlist by its path too" @("unowned.report")

Write-Host ""
Write-Host "--- D. no verb returns raw worker context: every result is closed and capped ---" -ForegroundColor Cyan

function Add-ResultVerb {
    param($Doc, [string]$Prop, [string]$Json)
    Add-Def $Doc "probe-result" ('{ "type": "object", "required": [], "additionalProperties": false, "properties": { "' + $Prop + '": ' + $Json + ' } }')
    Add-Row $Doc "probe.thing" "read" "hub-to-node" "#/definitions/no-args" "#/definitions/probe-result"
}
$summary = '{ "type": "string", "x-horde-cap": "summaryBytes" }'
foreach ($bad in @("transcript", "toolOutput", "toolResult", "stdout", "stderr", "output", "rawText", "log", "conversation", "history", "messages", "scrollback", "screen", "context", "prompt", "content", "diff")) {
    Refuses ([scriptblock]::Create("param(`$v) Add-ResultVerb `$v '$bad' '$summary'")) "is a result named like raw worker context" ("a result field named '" + $bad + "' is refused")
}
Refuses { param($v) Add-ResultVerb $v "document" '{ "type": "string", "x-horde-cap": "textBytes" }' } "may hold at most summaryBytes" "a result string capped above a summary (textBytes) is refused"
Refuses { param($v) Add-ResultVerb $v "document" '{ "type": "string" }' } "is a string that names no cap" "an uncapped result string is refused"
Refuses { param($v) Add-ResultVerb $v "lines" '{ "type": "array", "items": { "type": "string", "x-horde-cap": "nameBytes" } }' } "does not name the listItems cap" "an uncapped result list is refused"
Refuses { param($v) Add-ResultVerb $v "details" '{ "type": "object", "properties": {} }' } "is an open object" "an open result object is refused"
Refuses { param($v) Add-ResultVerb $v "details" '{ "description": "anything the node likes" }' } "has no type" "an untyped result field is refused"
Refuses { param($v) $v.definitions.handoff.additionalProperties = $true } "is an open object" "opening the real handoff result is refused" @("handoff.get")
Refuses { param($v) $v.definitions.handoff.properties.document.'x-horde-cap' = "textBytes" } "may hold at most summaryBytes" "raising the real handoff document's cap above a summary is refused" @("handoff.get")
Refuses { param($v) $v.definitions.handoff.properties | Add-Member -NotePropertyName "transcript" -NotePropertyValue ($summary | ConvertFrom-Json) } "is a result named like raw worker context" "adding a transcript to the real handoff result is refused" @("handoff.get")
# A result may be a whole schema by name; it is held to the same rules. node-manifest.v1 is one: an
# uncapped string added to a copy used as a verb's result would be found. Proved on the real row.
$f = @(Test-VerbsWith { param($v) $v.'x-horde-verbs'[0].result = "overlay-endpoint.v1" })
Check (Says $f "is a string that names no cap") "a verb whose result is a whole schema is held to the cap rule (overlay-endpoint.v1 names no caps and is refused as a result)"
$f = @(Test-VerbsWith { param($v) Add-ResultVerb $v "summaryText" $summary })
Check ((Without-Allowlist $f).Count -eq 0 -and $f.Count -eq 1) "CONTROL: a result string named summaryText, capped at summaryBytes, is refused for nothing but its probe verb's absence from the allowlist"; Show $f

Write-Host ""
Write-Host "--- E. the envelope's own rules ---" -ForegroundColor Cyan

function Test-FrameContractWith {
    param([scriptblock]$Change)
    $fr = Copy-Json $realFrame
    $null = & $Change $fr
    return @(Test-HordeLinkFrameContract -Frame $fr)
}
$f = Test-FrameContractWith { param($fr) $fr.'x-horde-kinds'.PSObject.Properties.Remove("ack") }
Check (Says $f "kind 'ack' has no member rule") "a kind with no member rule is refused"
$f = Test-FrameContractWith { param($fr) $fr.'x-horde-kinds'.ack.required = @("receipt"); $fr.'x-horde-kinds'.ack.allowed = @("receipt") }
Check (Says $f "names member 'receipt', which the envelope does not have") "a member rule naming a member the envelope lacks is refused"
$f = Test-FrameContractWith { param($fr) $fr.'x-horde-kinds'.req.allowed = @("verb", "args") }
Check (Says $f "requires 'requestId' and does not allow it") "a kind that requires a member it does not allow is refused"
$f = Test-FrameContractWith { param($fr) $fr.definitions.bye.properties.reason.PSObject.Properties.Remove("x-horde-cap") }
Check (Says $f "is a string that names no cap") "an envelope string with no cap is refused"
$f = Test-FrameContractWith { param($fr) $fr.definitions.hello.additionalProperties = $true }
Check (Says $f "is an open object") "an open hello body is refused"
$f = Test-FrameContractWith { param($fr) $fr.'x-horde-limits'.frameBytes = 8388608 }
Check (Says $f "frameBytes is above frameBytesCeiling") "a frame cap above its ceiling is refused"
$f = Test-FrameContractWith { param($fr) $fr.'x-horde-limits'.frameBytesCeiling = 8388608; $fr.'x-horde-limits'.frameBytes = 8388608 }
Check (Says $f "above 4 MiB") "a ceiling above 4 MiB is refused"
$f = Test-FrameContractWith { param($fr) $fr.'x-horde-limits'.summaryBytes = 1048576 }
Check (Says $f "would not fit in one frame") "a summary cap that would not fit in a frame is refused"
$f = Test-FrameContractWith { param($fr) $fr.'x-horde-limits'.PSObject.Properties.Remove("listItems") }
Check (Says $f "no positive whole listItems") "a limits table missing a cap is refused"
$f = Test-FrameContractWith { param($fr) $fr.'x-horde-limits'.nameBytes = "256" }
Check (Says $f "no positive whole nameBytes") "a cap written as text is refused"

Write-Host ""
Write-Host "--- F. one frame against the contract ---" -ForegroundColor Cyan

function Test-FrameWith {
    param([string]$Golden, [scriptblock]$Change)
    $fr = Copy-Json (Read-Fx ("frames\" + $Golden))
    $null = & $Change $fr
    return @(Test-HordeLinkFrame -Frame $fr -Contract $contract)
}
function FrameRefuses {
    param([string]$Golden, [scriptblock]$Change, [string]$Text, [string]$What)
    $got = @(Test-FrameWith $Golden $Change)
    Check (Says $got $Text) $What
    if (-not (Says $got $Text)) { Show $got }
}
FrameRefuses "ping.json" { param($x) $x.v = 2 } "$.v is '2', not one of" "a frame of another version is refused, not read as v1"
FrameRefuses "ping.json" { param($x) $x.kind = "exec" } "$.kind is 'exec'" "an unknown kind is refused"
FrameRefuses "ping.json" { param($x) $x.id = $x.id.ToUpperInvariant() } "$.id does not match" "an id in upper case is refused: one id has one spelling"
FrameRefuses "ping.json" { param($x) $x.ts = "2026-09-30T12:00:10" } "$.ts does not match" "a time with no zone is refused"
FrameRefuses "ping.json" { param($x) $x.seq = 0 } "below the minimum" "a sequence number below 1 is refused"
FrameRefuses "ping.json" { param($x) $x | Add-Member -NotePropertyName shell -NotePropertyValue "cmd" } "has 'shell', which the schema does not allow" "an envelope member that does not exist is refused"
FrameRefuses "req-node-info.json" { param($x) $x.PSObject.Properties.Remove("requestId") } "a req frame has no 'requestId'" "a req without a requestId is refused"
# issuedAt: when the hub first recorded the request (plan step R3's replay window). Required on a req,
# a UTC time in ASCII digits, carried by no other kind, and the same on every resend - unlike ts.
FrameRefuses "req-node-info.json" { param($x) $x.PSObject.Properties.Remove("issuedAt") } "a req frame has no 'issuedAt'" "a req without issuedAt is refused"
FrameRefuses "req-node-info.json" { param($x) $x.issuedAt = "2026-09-30T12:00:00" } "$.issuedAt does not match" "an issuedAt with no zone is refused"
FrameRefuses "req-node-info.json" { param($x) $x.issuedAt = "2026-09-30T12:00:00+00:00" } "$.issuedAt does not match" "an issuedAt with an offset instead of Z is refused: one spelling of UTC"
FrameRefuses "req-node-info.json" { param($x) $x.issuedAt = "2026-09-30T12:00:0" + [char]0x0661 + "Z" } "$.issuedAt does not match" "an issuedAt with a non-ASCII digit is refused"
FrameRefuses "req-node-info.json" { param($x) $x.issuedAt = 1759233600 } "$.issuedAt should be string" "an issuedAt as a number is refused"
# ONE SPELLING PER INSTANT, and a real one (review of PR #40). The link carries canonical frames only
# (step R2), so issuedAt has exactly three fraction digits, as Get-HordeLinkTime writes it; and a value
# shaped right but naming no instant is refused by parsing it.
foreach ($other in @("2026-09-30T12:00:00Z", "2026-09-30T12:00:00.0Z", "2026-09-30T12:00:00.0000Z", "2026-09-30T12:00:00.90Z")) {
    FrameRefuses "req-node-info.json" ([scriptblock]::Create("param(`$x) `$x.issuedAt = '$other'")) "$.issuedAt does not match" ("the second spelling " + $other + " of an instant is refused: issuedAt has exactly three fraction digits")
}
foreach ($impossible in @("2026-09-31T12:00:00.000Z", "2026-02-29T12:00:00.000Z", "2026-09-30T24:00:00.000Z", "2026-09-30T12:60:00.000Z", "2026-09-30T12:00:60.000Z", "2026-13-01T12:00:00.000Z", "0000-01-01T00:00:00.000Z")) {
    FrameRefuses "req-node-info.json" ([scriptblock]::Create("param(`$x) `$x.issuedAt = '$impossible'")) "is not a real UTC instant" ("the impossible issuedAt " + $impossible + " is refused")
}
$f = @(Test-FrameWith "req-node-info.json" { param($x) $x.issuedAt = "2028-02-29T23:59:59.999Z" })
Check ($f.Count -eq 0) "CONTROL: a real instant on a leap day, 2028-02-29T23:59:59.999Z, is accepted"; Show $f
FrameRefuses "res-handoff-absent.json" { param($x) $x | Add-Member -NotePropertyName issuedAt -NotePropertyValue "2026-09-30T12:00:00.000Z" } "a res frame may not carry 'issuedAt'" "issuedAt is carried by a req and no other kind"
FrameRefuses "req-node-info.json" { param($x) $x | Add-Member -NotePropertyName re -NotePropertyValue $x.id } "a req frame may not carry 're'" "a req carrying a member of another kind is refused"
FrameRefuses "res-handoff-absent.json" { param($x) $x | Add-Member -NotePropertyName error -NotePropertyValue ([pscustomobject]@{ code = "internal"; reason = "both" }) } "exactly one of result, error" "a res with both a result and an error is refused"
FrameRefuses "res-handoff-absent.json" { param($x) $x.PSObject.Properties.Remove("result") } "exactly one of result, error" "a res with neither a result nor an error is refused"
FrameRefuses "req-node-info.json" { param($x) $x.verb = "exec" } "unsupported-verb: 'exec'" "a req naming a verb the table does not have is refused as unsupported"
FrameRefuses "req-node-info.json" { param($x) $x.args | Add-Member -NotePropertyName argv -NotePropertyValue @("cmd.exe", "/c", "dir") } "$.args has 'argv', which the schema does not allow" "a req smuggling an argv into a verb's arguments is refused"
FrameRefuses "req-session-spawn.json" { param($x) $x.args.worktree | Add-Member -NotePropertyName path -NotePropertyValue "C:\anything" } "$.args.worktree has 'path'" "a spawn smuggling a path into its worktree is refused"
FrameRefuses "req-session-spawn.json" { param($x) $x.args.worktree.name = "..\..\elsewhere" } "$.args.worktree.name does not match" "a worktree name that climbs out of its root is refused"
# NAMES THAT BECOME FILE NAMES ON THE NODE (review of PR #40). Path.Combine("D:\h", "C:..") is "C:..",
# a drive-relative path; "foo." is the folder foo; CON is the console device, with or without a dot.
function Test-Def {
    # One value against one definition of the real verb table. Returns its findings.
    param([string]$Def, [string]$Value)
    return @(Test-HordeSchema -Value $Value -Schema (New-HordeLinkRefSchema -Doc $realVerbs -Ref ("#/definitions/" + $Def)) -Path '$')
}
foreach ($bad in @("C:..", "C:x", "z:abc", "a..b", "abc.", "abc:", "CON", "con", "Nul.txt", "COM1", "lpt9:x", "aux")) {
    Check (Says (Test-Def "session-id" $bad) "does not match") ("the session id '" + $bad + "' is refused")
}
foreach ($good in @("11111111-2222-4333-8444-555555555555", "rollout-2026.09.30", "harness:abc", "CONSOLE", "nullable", "COM")) {
    $f = Test-Def "session-id" $good
    Check ($f.Count -eq 0) ("CONTROL: the session id '" + $good + "' is accepted"); Show $f
}
foreach ($bad in @("foo.", "CON", "con.anything", "LPT1", "a..b", "prn")) {
    Check (Says (Test-Def "worktree-name" $bad) "does not match") ("the worktree name '" + $bad + "' is refused")
}
foreach ($good in @("foo.bar", "CONSOLE", "feature-x", "r1.fix")) {
    $f = Test-Def "worktree-name" $good
    Check ($f.Count -eq 0) ("CONTROL: the worktree name '" + $good + "' is accepted"); Show $f
}
foreach ($bad in @("github.com/../..", "github.com/a/..", "github.com/./x", "github.com/a/b.", "github.com/CON/x", "github.com/a/nul.git", "github..com/a/b", "-github.com/a/b", "github.com./a/b")) {
    Check (Says (Test-Def "repo-id" $bad) "does not match") ("the repository id '" + $bad + "' is refused")
}
foreach ($good in @("github.com/YedPool/horde", "github.com/YedPool/.github", "gitlab.example.org/group/sub/repo", "github.com/a/b.c")) {
    $f = Test-Def "repo-id" $good
    Check ($f.Count -eq 0) ("CONTROL: the repository id '" + $good + "' is accepted"); Show $f
}
FrameRefuses "req-session-spawn.json" { param($x) $x.args.profile = "C:\tools\agent.exe" } "$.args.profile does not match" "a profile given as a program path is refused: profiles are names"
FrameRefuses "req-session-spawn.json" { param($x) $x.args.PSObject.Properties.Remove("closeOn") } "$.args has no 'closeOn'" "a spawn missing a required argument is refused"
FrameRefuses "ping.json" { param($x) $x.PSObject.Properties.Remove("ping"); $x | Add-Member -NotePropertyName pong -NotePropertyValue ([pscustomobject]@{ t1 = $x.ts; t2 = $x.ts; t3 = $x.ts }) } "a ping frame has no 'ping'" "a ping carrying a pong body is refused"
FrameRefuses "hello-node.json" { param($x) $x.hello.PSObject.Properties.Remove("t1") } "$.hello has no 't1'" "a hello without its clock stamp is refused"
FrameRefuses "bye.json" { param($x) $x.bye.reason = "  " } "$.bye.reason does not match" "a bye with a blank reason is refused"
FrameRefuses "res-handoff-known.json" { param($x) $x.kind = "evt"; $x.PSObject.Properties.Remove("requestId") } "streams events" "an evt frame is refused: no v1 verb streams events"

# A RESEND IS THE SAME REQUEST IN A NEW FRAME: a new id, seq and ts, and the same requestId, issuedAt,
# verb and args. The journal (plan step R3) keys on requestId and judges its replay window by issuedAt,
# so a resend that moved issuedAt would reopen a window the first send closed.
$first = Read-Fx "frames\req-session-spawn.json"
function New-Resend {
    param([scriptblock]$Change)
    $r = Copy-Json $first
    $r.id = "0a000000-0000-4000-8000-0000000000e8"; $r.seq = 41; $r.ts = "2026-09-30T12:05:00Z"
    $null = & $Change $r
    return $r
}
$f = @(Test-HordeLinkResend -First $first -Again (New-Resend { param($r) }) -Contract $contract)
Check ($f.Count -eq 0) "CONTROL: a resend with a new id, seq and ts and everything else the same is a resend"; Show $f
$f = @(Test-HordeLinkResend -First $first -Again (New-Resend { param($r) $r.issuedAt = "2026-09-30T12:05:00.000Z" }) -Contract $contract)
Check (Says $f "issuedAt") "a resend whose issuedAt moved is not a resend: issuedAt is fixed when the hub first records the request"
$f = @(Test-HordeLinkResend -First $first -Again (New-Resend { param($r) $r.args.prompt.text = "Something else." }) -Contract $contract)
Check (Says $f "args") "a resend whose arguments changed is not a resend"
# Compared code unit by code unit: a culture-aware comparison ignores these three, and passed each as
# the same request (review of PR #40).
foreach ($hidden in @(0x00AD, 0x0000, 0x200B)) {
    $f = @(Test-HordeLinkResend -First $first -Again (New-Resend ([scriptblock]::Create("param(`$r) `$r.args.prompt.text = `$r.args.prompt.text + [char]$hidden"))) -Contract $contract)
    Check (Says $f "args differ") ("a resend whose prompt gained U+" + $hidden.ToString("X4") + ", which culture-aware comparison ignores, is not a resend")
}
$f = @(Test-HordeLinkResend -First $first -Again (New-Resend { param($r) $r.verb = "session.resume" }) -Contract $contract)
Check (Says $f "verb") "a resend naming another verb is not a resend"
$f = @(Test-HordeLinkResend -First $first -Again (New-Resend { param($r) $r.requestId = "0b000000-0000-4000-8000-0000000000e8" }) -Contract $contract)
Check (Says $f "requestId") "a frame with another requestId is not a resend of this request"
$f = @(Test-HordeLinkResend -First $first -Again (New-Resend { param($r) $r.id = $first.id }) -Contract $contract)
Check (Says $f "new frame id") "a resend reuses no frame id: it is a new frame"
$f = @(Test-HordeLinkResend -First (Read-Fx "frames\ping.json") -Again (Read-Fx "frames\ping.json") -Contract $contract)
Check (Says $f "not a req") "only a req can be resent"

Write-Host ""
Write-Host "--- G. every result is a core/tristate answer, typed by its verb ---" -ForegroundColor Cyan

FrameRefuses "res-node-info-known.json" { param($x) $x.result = $x.result.value } "$.result has no 'state'" "a bare value as a result is refused: no bare value crosses"
FrameRefuses "res-node-info-known.json" { param($x) $x.result.PSObject.Properties.Remove("value") } "is known and carries no value" "a known answer with no value is refused"
FrameRefuses "res-node-info-known.json" { param($x) $x.result.value = $null } "value is null" "a known answer whose value is null is refused"
FrameRefuses "res-node-info-known.json" { param($x) $x.result.PSObject.Properties.Remove("observedAt") } "is known and says nothing of when it was observed" "a known answer with no observation time is refused"
FrameRefuses "res-handoff-absent.json" { param($x) $x.result | Add-Member -NotePropertyName value -NotePropertyValue "none" } "is absent and carries a value" "an absent answer carrying a value is refused"
FrameRefuses "res-handoff-absent.json" { param($x) $x.result.PSObject.Properties.Remove("observedAt") } "is absent and says nothing of when" "an absent answer with no time is refused"
FrameRefuses "res-handoff-unknown.json" { param($x) $x.result.reason = " " } "is unknown and gives no reason" "an unknown answer with no reason is refused"
FrameRefuses "res-handoff-unknown.json" { param($x) $x.result | Add-Member -NotePropertyName value -NotePropertyValue "stale copy" } "is unknown and carries a value" "an unknown answer carrying a value is refused"
FrameRefuses "res-handoff-unknown.json" { param($x) $x.result.state = "unsure" } "$.result.state is 'unsure'" "a fourth state is refused"
FrameRefuses "res-handoff-known.json" { param($x) $x.result.value | Add-Member -NotePropertyName transcript -NotePropertyValue "every line of the session" } "$.result.value has 'transcript', which the schema does not allow" "a handoff value carrying a transcript is refused"
FrameRefuses "res-handoff-known.json" { param($x) $x.result.value = "the whole document as a bare string" } "$.result.value should be object" "a known value of the wrong shape for its verb is refused"
FrameRefuses "res-node-info-known.json" { param($x) $x.result.value.profiles[0] | Add-Member -NotePropertyName apiKey -NotePropertyValue "sk-not-real" } "has 'apiKey', which the schema does not allow" "a manifest carrying a credential value is refused"
FrameRefuses "res-clone-status.json" { param($x) $x.result.value.ahead = [pscustomobject]@{ state = "known"; reason = ""; observedAt = $x.ts } } "$.result.value.ahead is known and carries no value" "a nested answer known with no value is refused, where it is"
FrameRefuses "res-clone-status.json" { param($x) $x.result.value.upstream | Add-Member -NotePropertyName value -NotePropertyValue "origin/main" } "$.result.value.upstream is absent and carries a value" "a nested absent answer carrying a value is refused"
FrameRefuses "res-clone-status.json" { param($x) $x.result.value.pullRequest.reason = "" } "$.result.value.pullRequest is unknown and gives no reason" "a nested unknown with no reason is refused"
FrameRefuses "res-clone-status.json" { param($x) $x.result.value.dirty = 0 } "$.result.value.dirty should be object" "a nested fact given as a bare number is refused: unknown is never zero"

# THE WIRE FORM IS CORE/TRISTATE'S. A null value and time are left out on the wire; the reader of the
# stored form reads what crosses the same way.
$u = ConvertFrom-HordeAnswerRecord (Read-Fx "frames\res-handoff-unknown.json").result
Check ($u.state -ceq "unknown" -and $u.reason -like "*being written*") "an unknown result reads back through ConvertFrom-HordeAnswerRecord as unknown, with its reason"
$a = ConvertFrom-HordeAnswerRecord (Read-Fx "frames\res-handoff-absent.json").result
Check ($a.state -ceq "absent" -and $a.observedAt -is [datetime] -and $a.observedAt.Kind -eq [System.DateTimeKind]::Utc) "an absent result reads back as absent, with a UTC observation time"
$k = ConvertFrom-HordeAnswerRecord (Read-Fx "frames\res-handoff-known.json").result
Check ($k.state -ceq "known" -and "$($k.value.handoffId)" -ceq "0c000000-0000-4000-8000-000000000006") "a known result reads back as known, with its value"
$rec = ConvertTo-HordeAnswerRecord (New-HordeUnknown -Reason "node D unreachable since 12:00")
$wire = [ordered]@{}
foreach ($key in @($rec.Keys)) { if ($null -ne $rec[$key]) { $wire[$key] = $rec[$key] } }
$wireObj = [pscustomobject]$wire
$f = @(Test-HordeLinkAnswer -Answer $wireObj -Path '$.result')
Check ($f.Count -eq 0 -and -not (Test-HordeLinkHasProp $wireObj "value")) "core/tristate's stored form with its nulls left out is a valid wire answer"; Show $f
$f = @(Test-HordeLinkAnswer -Answer ([pscustomobject]$rec) -Path '$.result')
Check (Says $f "value is null") "and the stored form with its nulls written is refused, so there is one wire form"

Write-Host ""
Write-Host "--- H. the other contract documents ---" -ForegroundColor Cyan

function DocRefuses {
    param([string]$File, [string]$Schema, [scriptblock]$Change, [string]$Text, [string]$What)
    $d = Copy-Json (Read-Fx $File)
    $null = & $Change $d
    $got = @(Test-HordeContractDocument -Value $d -SchemaName $Schema)
    Check (Says $got $Text) $What
    if (-not (Says $got $Text)) { Show $got }
}
DocRefuses "manifest.json" "node-manifest.v1" { param($d) $d.profiles[0].resolves = "sk-not-real" } "$.profiles[0].resolves is 'sk-not-real'" "a manifest profile says only set, missing or unknown about its credential"
DocRefuses "manifest.json" "node-manifest.v1" { param($d) $d.repos = @("C:\code\horde") } "$.repos[0] does not match" "a manifest names repositories by id, never by path"
DocRefuses "manifest.json" "node-manifest.v1" { param($d) $d.repos = @("github.com/../..") } "$.repos[0] does not match" "a manifest repository id cannot climb out with .. segments, as the verb table's cannot"
DocRefuses "manifest.json" "node-manifest.v1" { param($d) $d.spaces = @("wsl") } "$.spaces[0] does not match" "a wsl space names its distro"
DocRefuses "transport-local.json" "transport-capabilities.v1" { param($d) $d.capabilities.PSObject.Properties.Remove("encrypt") } "has no 'encrypt'" "a transport declares every capability"
DocRefuses "transport-local.json" "transport-capabilities.v1" { param($d) $d.capabilities.encrypt.support = "n/a" } "is 'n/a', not one of" "a capability is yes, no, declined or unverified, nothing else"
DocRefuses "transport-local.json" "transport-capabilities.v1" { param($d) $d.capabilities.encrypt.evidence = "" } "evidence does not match" "a capability without evidence is refused"
DocRefuses "transport-local.json" "transport-capabilities.v1" { param($d) $d.capabilities | Add-Member -NotePropertyName "exec" -NotePropertyValue ([pscustomobject]@{ support = "yes"; evidence = "x" }) } "has 'exec', which the schema does not allow" "the capability list is closed"
DocRefuses "overlay.json" "overlay-endpoint.v1" { param($d) $d.peers[0].address = "hub.example.net" } "$.peers[0].address does not match" "an overlay peer is an address, never a host name to guess from"
DocRefuses "overlay.json" "overlay-endpoint.v1" { param($d) $d.health.PSObject.Properties.Remove("value") } "$.health is known and carries no value" "an overlay's known health carries its value"
DocRefuses "overlay.json" "overlay-endpoint.v1" { param($d) $d.health = [pscustomobject]@{ state = "unknown"; reason = "" } } "$.health is unknown and gives no reason" "an overlay's unknown health says why"
DocRefuses "overlay.json" "overlay-endpoint.v1" { param($d) $d.health = $true } "$.health should be object" "overlay health is a tristate answer, never a bare boolean"

Write-Host ""
Write-Host "--- I. nothing in remote/ can start a program or a shell ---" -ForegroundColor Cyan

# The verb table cannot express a shell; this proves the code beside it does not hold one either.
# remote/ calls core and the adapters, which run what they run; it never starts anything itself.
# tools/ExecScan.ps1 reads each file's syntax tree against an ALLOWLIST on every axis, because the
# banned-name list it replaced caught 3 of the 27 ways to run something that the review
# of PR #40 wrote (2026-10-01), and its second version, which still kept lists of banned methods and
# types, let 7 of the verification's forms through. Every axis is now an allowlist (tools/ExecScan.ps1).
. (Join-Path $root "tools\ExecScan.ps1")
$known = Get-HordeExecFunctionNames -Roots @(Join-Path $root "remote")
Check ($known.Contains("Test-HordeLinkFrame") -and -not $known.Contains("Invoke-HordeRead")) "CONTROL: the functions remote/ defines are read, and core's are not: only the listed core functions may be called, never Invoke-HordeRead, which runs the block it is given"

function Get-LineFindings {
    param($Findings, [int]$Line)
    return @($Findings | Where-Object { "$_".StartsWith("line " + $Line + ": ") })
}
$ctlPath = Join-Path $fx "shell-control.ps1"
$ctl = @(Get-HordeExecFindings -Path $ctlPath -Known $known)
$ctlAst = [System.Management.Automation.Language.Parser]::ParseFile($ctlPath, [ref]$null, [ref]$null)
$forms = @($ctlAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))
Check ($forms.Count -eq 92) ("CONTROL: the control file holds 92 forms - the review's 27, the first scan's 9, the verification's 13, 42 that each isolate one rule, and a class method (found " + $forms.Count + ")")
foreach ($form in $forms) {
    $hits = @(Get-LineFindings $ctl $form.Extent.StartLineNumber)
    Check ($hits.Count -ge 1) ("CONTROL: the form " + $form.Name + " is refused")
}
# Each form's own reason, so a rule switched off is seen even where another rule also catches the form.
$expectCount = 0
$lineNo = 0
foreach ($text in [System.IO.File]::ReadAllLines($ctlPath)) {
    $lineNo++
    $m = [regex]::Match($text, '#\s*expect:\s*(.+?)\s*$')
    if (-not $m.Success -or $text.TrimStart().StartsWith("#")) { continue }
    $expectCount++
    $want = $m.Groups[1].Value
    $hits = @(Get-LineFindings $ctl $lineNo)
    Check (@($hits | Where-Object { "$_".Contains($want) }).Count -ge 1) ("CONTROL: line " + $lineNo + " is refused because: " + $want)
    if (@($hits | Where-Object { "$_".Contains($want) }).Count -eq 0) { Show $hits }
}
Check ($expectCount -eq 96) ("CONTROL: 96 lines of the control file name their reason (found " + $expectCount + ")")
$clean = @(Get-HordeExecFindings -Path (Join-Path $fx "shell-clean.ps1") -Known $known)
Check ($clean.Count -eq 0) "CONTROL: a file written the way remote/ is written - its loader lines, allowlisted cmdlets, core functions, .NET types that start nothing - has no finding"; Show $clean
$broken = @(Get-HordeExecFindings -Path (Join-Path $fx "shell-unparsed.ps1") -Known $known)
Check (Says $broken "does not parse") "a file that does not parse is a finding, never silence"
$remoteFiles = @(Get-ChildItem -LiteralPath (Join-Path $root "remote") -Filter "*.ps1" -Recurse)
Check ($remoteFiles.Count -ge 1) "there is code in remote/ to check"
foreach ($file in $remoteFiles) {
    $got = @(Get-HordeExecFindings -Path $file.FullName -Known $known)
    Check ($got.Count -eq 0) ("remote/" + $file.Name + " starts no program and no shell"); Show $got
}

Complete-HordeSuite -Success "the link contracts allow exactly the verbs they list, and refuse every shell, path, environment and raw-context shape"
