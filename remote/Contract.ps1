# remote/Contract.ps1 - the link protocol's contract, read and enforced: which frames exist, which
# verbs exist, and what each may carry.
#
# THE PROTOCOL IS NEVER A REMOTE SHELL (remote-sessions design section 6). One end can ask the other
# for exactly the verbs in schema/link-verbs.v1, each with closed arguments, and can get back exactly a
# core/tristate answer whose value is that verb's closed result. This file is where that is checked,
# twice over:
#
#   - Test-HordeLinkVerbTable checks a verb TABLE, statically, before anything is sent. A row without
#     an effect class, a verb whose name says exec, shell, file, env, config, credential, process or
#     update, an argument named like a command line, a program, a path or an environment, an
#     argument or result that is an open object or untyped, a result field named like a transcript or
#     tool output, and a string or array that names no size cap: each is a finding. So a verb that
#     runs a shell, or returns raw worker context, cannot be added to the table without this file
#     refusing it - test/test-link-contracts.ps1 builds one of each and proves it.
#   - Test-HordeLinkFrame checks one parsed FRAME against the contract: the envelope, the members its
#     kind carries, the verb's own arguments, and the result as a tristate answer typed by the verb.
#
# WHAT IS CHECKED BY NAME, AND WHY THAT IS NOT THE WHOLE DEFENCE. The name lists below catch the
# obvious spellings (argv, commandLine, filePath, env, toolOutput, transcript). A name list alone would
# be weak - a field called "x" can hold anything - so the structural rules carry the weight: every
# object is closed (additionalProperties false), every node has a type, and every string names a cap
# from schema/link-frame.v1's x-horde-limits. A result string can hold at most summaryBytes (64 KiB,
# a distilled handoff, plan step R14), which a raw transcript does not fit in, and it can only be a
# field the table declared.
#
# SIZES ARE NOT ENFORCED HERE. core/Schema.ps1 has no maxLength, maxItems or byte keyword, and two
# other pull requests are changing it, so the caps are data in the contract and remote/Protocol.ps1
# enforces them (plan step R2, ruling of the plan review, 2026-09-30). This file checks that every
# string and array NAMES a cap that exists.
#
# The functions return findings: a list of strings, each saying what is wrong and where. Empty means
# the thing checked is valid. No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")

# A verb whose name holds one of these words is one the protocol deliberately never has (design 6.4:
# exec, shell, script, env, file read or write by path, config set, provider definition, credential
# transfer, process kill by pid, pane kill by id, update). Matched against every word of the name.
$script:HordeLinkAbsentVerbWords = @("exec", "execute", "shell", "script", "eval", "invoke", "run", "command", "cmd",
    "env", "environment", "file", "files", "fs", "path", "config", "configure", "setting", "settings", "provider",
    "credential", "credentials", "secret", "secrets", "key", "keys", "process", "pid", "pane", "kill",
    "update", "upgrade", "install", "download", "upload", "copy", "transfer")

# An argument named with one of these words would carry something the node could run or open.
$script:HordeLinkArgWords = @("argv", "cmd", "cmdline", "command", "commandline", "script", "program", "exe",
    "executable", "binary", "path", "paths", "file", "files", "filename", "filepath", "dir", "directory", "folder",
    "cwd", "env", "environment", "shell", "exec", "eval", "expression", "code")

# A result field named with one of these words would carry raw worker context back (design section 10:
# transcripts, tool output and exploratory notes stay on the node).
$script:HordeLinkResultWords = @("transcript", "transcripts", "tool", "tools", "stdout", "stderr", "output", "outputs",
    "raw", "log", "logs", "conversation", "history", "messages", "scrollback", "buffer", "screen", "context",
    "prompt", "content", "contents", "jsonl", "diff", "patch", "blob", "env", "environment", "secret", "credential")

# The caps a result string may name. textBytes (a prompt, a message body) is for arguments only, so
# the largest string a result can hold is a distilled summary.
$script:HordeLinkResultCaps = @("nameBytes", "reasonBytes", "summaryBytes")

function Get-HordeLinkProp {
    # A property of a parsed JSON object, or $null when it is not there. Looked up, never dereferenced,
    # so a missing key under strict mode is $null and not an error.
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] } else { return $null } }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Test-HordeLinkHasProp {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

function Split-HordeLinkName {
    # The words of a name, lower case: split at every non-alphanumeric and at every lower-to-upper
    # change, plus the whole name squashed into one word. "toolOutput" gives tool, output and
    # tooloutput, so a list holding either spelling finds it; "profile" gives only profile, so the word
    # file inside it is not a match.
    param([string]$Name)
    # Loops, not the pipeline: this runs for every property of every verb, and the pipeline version
    # cost 3.5 ms a call (measured 2026-09-30).
    $spaced = [regex]::Replace($Name, '([a-z0-9])([A-Z])', '$1 $2')
    $words = New-Object System.Collections.Generic.List[string]
    foreach ($w in [regex]::Split($spaced, '[^A-Za-z0-9]+')) {
        if ($w -ne "") { $lw = $w.ToLowerInvariant(); if (-not $words.Contains($lw)) { $words.Add($lw) } }
    }
    $squashed = [regex]::Replace($Name.ToLowerInvariant(), '[^a-z0-9]', '')
    if ($squashed -ne "" -and -not $words.Contains($squashed)) { $words.Add($squashed) }
    return $words.ToArray()
}

function Get-HordeLinkLimits {
    # schema/link-frame.v1's x-horde-limits as name -> integer. The description is not a limit.
    param($Frame)
    $limits = @{}
    $raw = Get-HordeLinkProp $Frame "x-horde-limits"
    if ($null -eq $raw) { return $limits }
    foreach ($p in @($raw.PSObject.Properties)) {
        if ($p.Name -ceq "description") { continue }
        $limits[$p.Name] = $p.Value
    }
    return $limits
}

function Resolve-HordeLinkRef {
    # A local "#/definitions/<name>" in Root, by direct lookup. core/Schema.ps1's Resolve-HordeSchemaRef
    # gives the same answer but lists every definition through the pipeline on each call; over a verb
    # table of 40 definitions and a hundred refs that made one table check take about 8 s (measured
    # 2026-09-30, the first run of test/test-link-contracts.ps1). Throws when the ref names nothing.
    param([string]$Ref, $Root)
    $m = [regex]::Match($Ref, '\A#/definitions/([A-Za-z0-9_-]+)\z')
    if (-not $m.Success) { throw ("the `$ref '" + $Ref + "' is not a local #/definitions/<name>") }
    $defs = Get-HordeLinkProp $Root "definitions"
    if (-not (Test-HordeLinkHasProp $defs $m.Groups[1].Value)) { throw ("the `$ref '" + $Ref + "' names no definition") }
    return (Get-HordeLinkProp $defs $m.Groups[1].Value)
}

function Get-HordeLinkRefClosure {
    # The names of every definition of Doc that Ref reaches, itself included, following $ref through
    # properties and items. A schema file checked by Test-HordeSchema has ALL its definitions checked
    # once per call; carrying only the ones a value can reach keeps a frame check from re-checking the
    # whole verb table every time (measured 2026-09-30: the first version of this suite ran past 120 s).
    param($Doc, [string]$Ref)
    $names = New-Object System.Collections.ArrayList
    $todo = New-Object System.Collections.Stack
    $todo.Push($Ref)
    while ($todo.Count -gt 0) {
        $r = [string]$todo.Pop()
        $m = [regex]::Match($r, '\A#/definitions/([A-Za-z0-9_-]+)\z')
        if (-not $m.Success -or $names -ccontains $m.Groups[1].Value) { continue }
        [void]$names.Add($m.Groups[1].Value)
        $nodes = New-Object System.Collections.Stack
        $nodes.Push((Resolve-HordeLinkRef -Ref $r -Root $Doc))
        while ($nodes.Count -gt 0) {
            $n = $nodes.Pop()
            if ($null -eq $n -or -not ($n -is [System.Management.Automation.PSCustomObject] -or $n -is [System.Collections.IDictionary])) { continue }
            $inner = Get-HordeLinkProp $n '$ref'
            if ($null -ne $inner) { $todo.Push("$inner") }
            $props = Get-HordeLinkProp $n "properties"
            if ($null -ne $props) { foreach ($p in $props.PSObject.Properties) { $nodes.Push($p.Value) } }
            $items = Get-HordeLinkProp $n "items"
            if ($null -ne $items) { $nodes.Push($items) }
        }
    }
    return @($names)
}

function New-HordeLinkRefSchema {
    # A schema that is one definition of Doc, checked at the top: `$ref` beside definitions, which the
    # validator accepts because definitions says nothing about a value. It carries the definitions the
    # ref reaches and no others (Get-HordeLinkRefClosure), so Test-HordeSchema resolves every ref it
    # meets and checks only those.
    param($Doc, [string]$Ref)
    $defs = [ordered]@{}
    $all = Get-HordeLinkProp $Doc "definitions"
    foreach ($name in @(Get-HordeLinkRefClosure -Doc $Doc -Ref $Ref)) { $defs[$name] = Get-HordeLinkProp $all $name }
    return [pscustomobject]@{ '$ref' = $Ref; definitions = [pscustomobject]$defs }
}

function Resolve-HordeLinkTarget {
    # A row's args or result: "#/definitions/<name>" in Doc, or a whole schema by name
    # ("node-manifest.v1"). Returns { schema; root; label } - the node to check a value against and the
    # document its $refs resolve in. Throws when it names nothing.
    param($Doc, [string]$Target)
    if ($Target.StartsWith("#")) {
        $node = Resolve-HordeLinkRef -Ref $Target -Root $Doc
        return [pscustomobject]@{ schema = (New-HordeLinkRefSchema -Doc $Doc -Ref $Target); node = $node; root = $Doc; label = $Target }
    }
    $s = Get-HordeSchema -Name $Target
    return [pscustomobject]@{ schema = $s; node = $s; root = $s; label = $Target }
}

function Get-HordeLinkSchemaFindings {
    # The static rules, for one schema node and everything under it. Role is args, result or frame; it
    # decides which names are refused and which caps a string may name. Where is a readable path into
    # the schema. Exempt lists Where paths that are open on purpose (only the envelope's args and the
    # answer's value, each closed by the verb it carries - see schema/link-frame.v1).
    param($Node, $Root, [string]$Where, [string]$Role, [hashtable]$Limits, [string[]]$Exempt = @(), [string[]]$Refs = @())
    $out = New-Object System.Collections.ArrayList
    if ($Exempt -ccontains $Where) { return @() }
    $ref = Get-HordeLinkProp $Node '$ref'
    if ($null -ne $ref) {
        # A definition that refers back to itself would make a tree of unbounded depth; nothing in the
        # protocol needs one, so it is refused rather than walked.
        if ($Refs -ccontains "$ref") { return @("$Where refers back to ${ref}: a recursive shape has no bound") }
        try { $target = Resolve-HordeLinkRef -Ref "$ref" -Root $Root }
        catch { return @("$Where names $ref, which is not there: " + $_.Exception.Message) }
        return @(Get-HordeLinkSchemaFindings -Node $target -Root $Root -Where "$ref" -Role $Role -Limits $Limits -Exempt $Exempt -Refs (@($Refs) + "$ref"))
    }
    $type = Get-HordeLinkProp $Node "type"
    if ($null -eq $type) { return @("$Where has no type, so it accepts anything") }
    switch ("$type") {
        "object" {
            if ((Get-HordeLinkProp $Node "additionalProperties") -isnot [bool] -or (Get-HordeLinkProp $Node "additionalProperties") -ne $false) {
                [void]$out.Add("$Where is an open object: it must say additionalProperties false")
            }
            $props = Get-HordeLinkProp $Node "properties"
            if ($null -eq $props) { [void]$out.Add("$Where is an object with no properties, so nothing about it is closed"); break }
            foreach ($p in @($props.PSObject.Properties)) {
                $words = Split-HordeLinkName $p.Name
                $refused = $null
                if ($Role -ceq "args") { $refused = @($words | Where-Object { $script:HordeLinkArgWords -ccontains $_ }) }
                elseif ($Role -ceq "result") { $refused = @($words | Where-Object { $script:HordeLinkResultWords -ccontains $_ }) }
                if ($null -ne $refused -and $refused.Count -gt 0) {
                    if ($Role -ceq "args") { [void]$out.Add("$Where.$($p.Name) is an argument named like a command, a program, a path or an environment ('" + ($refused -join "', '") + "'); no verb takes one") }
                    else { [void]$out.Add("$Where.$($p.Name) is a result named like raw worker context ('" + ($refused -join "', '") + "'); no verb returns one") }
                }
                foreach ($f in @(Get-HordeLinkSchemaFindings -Node $p.Value -Root $Root -Where "$Where.$($p.Name)" -Role $Role -Limits $Limits -Exempt $Exempt -Refs $Refs)) { [void]$out.Add($f) }
            }
        }
        "array" {
            $cap = Get-HordeLinkProp $Node "x-horde-cap"
            if ("$cap" -cne "listItems") { [void]$out.Add("$Where is an array that does not name the listItems cap") }
            $items = Get-HordeLinkProp $Node "items"
            if ($null -eq $items) { [void]$out.Add("$Where is an array with no items schema, so its items accept anything") }
            else { foreach ($f in @(Get-HordeLinkSchemaFindings -Node $items -Root $Root -Where "$Where[]" -Role $Role -Limits $Limits -Exempt $Exempt -Refs $Refs)) { [void]$out.Add($f) } }
        }
        "string" {
            # A string from an enum is bounded by the enum. Every other string names a cap that exists.
            if ($null -eq (Get-HordeLinkProp $Node "enum")) {
                $cap = Get-HordeLinkProp $Node "x-horde-cap"
                if ($null -eq $cap) { [void]$out.Add("$Where is a string that names no cap") }
                elseif (-not $Limits.ContainsKey("$cap")) { [void]$out.Add("$Where names the cap '$cap', which x-horde-limits does not have") }
                elseif ($Role -ceq "result" -and $script:HordeLinkResultCaps -cnotcontains "$cap") { [void]$out.Add("$Where is a result string capped at $cap; a result string may hold at most summaryBytes") }
            }
        }
        "integer" { }
        "number" { }
        "boolean" { }
        default { [void]$out.Add("$Where has type '$type', which the link does not carry") }
    }
    return @($out)
}

function Test-HordeLinkVerbTable {
    # Every static rule over a verb table (a parsed link-verbs file). -Frame gives the limits; each row
    # is checked against the verb-row definition of the REAL schema/link-verbs.v1, never the table's
    # own, so a table under test cannot loosen what a row must say.
    param([Parameter(Mandatory = $true)]$Verbs, $Frame = $null)
    if ($null -eq $Frame) { $Frame = Get-HordeSchema -Name "link-frame.v1" }
    $limits = Get-HordeLinkLimits $Frame
    $out = New-Object System.Collections.ArrayList
    $rowSchema = New-HordeLinkRefSchema -Doc (Get-HordeSchema -Name "link-verbs.v1") -Ref "#/definitions/verb-row"
    $protocol = Get-HordeLinkProp $Verbs "x-horde-protocol"
    if (-not ($protocol -is [int] -or $protocol -is [long]) -or $protocol -lt 1) { [void]$out.Add("x-horde-protocol is not a protocol version") }
    $rows = @(Get-HordeLinkProp $Verbs "x-horde-verbs")
    if (-not (Test-HordeLinkHasProp $Verbs "x-horde-verbs") -or $rows.Count -eq 0) { return @($out) + @("the table has no verbs") }
    $seen = @{}
    $i = 0
    foreach ($row in $rows) {
        $at = "verb row " + $i
        $i++
        $name = "$(Get-HordeLinkProp $row 'name')"
        if ($name -ne "") { $at = "verb '" + $name + "'" }
        foreach ($f in @(Test-HordeSchema -Value $row -Schema $rowSchema -Path $at)) { [void]$out.Add($f) }
        if ($name -eq "") { continue }
        if ($seen.ContainsKey($name)) { [void]$out.Add("$at is in the table twice") }
        $seen[$name] = $true
        $absent = @(Split-HordeLinkName $name | Where-Object { $script:HordeLinkAbsentVerbWords -ccontains $_ })
        if ($absent.Count -gt 0) { [void]$out.Add("$at is a verb the protocol never has ('" + ($absent -join "', '") + "'): no exec, shell, file, env, config, credential, process kill or update verb exists") }
        $since = Get-HordeLinkProp $row "since"
        if (($since -is [int] -or $since -is [long]) -and ($protocol -is [int] -or $protocol -is [long]) -and $since -gt $protocol) { [void]$out.Add("$at is since protocol $since, after this table's protocol $protocol") }
        # A node never asks the hub to start or end anything: every spawn and kill travels hub to node,
        # where the node's own admission and policy decide (plan steps R9 and R19).
        $effect = "$(Get-HordeLinkProp $row 'effect')"
        if ("$(Get-HordeLinkProp $row 'direction')" -ceq "node-to-hub" -and ($effect -ceq "spawn" -or $effect -ceq "kill")) { [void]$out.Add("$at travels node to hub with effect $effect; a node never asks the hub to spawn or kill") }
        foreach ($part in @("args", "result")) {
            $target = Get-HordeLinkProp $row $part
            if ($target -isnot [string]) { continue }
            try { $t = Resolve-HordeLinkTarget -Doc $Verbs -Target $target }
            catch { [void]$out.Add("$at $part names $target, which is not there: " + $_.Exception.Message); continue }
            # THE VALIDATOR MUST BE ABLE TO READ IT: every definition the target reaches is checked the
            # way Test-HordeSchema checks a schema (unknown keywords, dangling refs, bad enums), so a
            # frame is never the first to find a broken definition. The findings about the $null value
            # are not the point and are dropped; only a refusal of the schema itself is.
            try { $null = Test-HordeSchema -Value $null -Schema $t.schema }
            catch { [void]$out.Add("$at $part $target is not a schema this validator can read: " + $_.Exception.Message); continue }
            if ($part -ceq "args" -and "$(Get-HordeLinkProp $t.node 'type')" -cne "object") { [void]$out.Add("$at args is not an object") }
            foreach ($f in @(Get-HordeLinkSchemaFindings -Node $t.node -Root $t.root -Where "$at $part $target" -Role $part -Limits $limits)) { [void]$out.Add($f) }
        }
    }
    return @($out)
}

function Test-HordeLinkFrameContract {
    # The static rules over the envelope schema itself: every kind has its member rules, every member a
    # rule names is a property, and every string and array names a cap that exists. The envelope's
    # args and the answer's value are the two open places, each closed by the verb (schema/link-frame.v1).
    param([Parameter(Mandatory = $true)]$Frame)
    $out = New-Object System.Collections.ArrayList
    try { $null = Test-HordeSchema -Value $null -Schema $Frame }
    catch { return @("the frame schema is not one this validator can read: " + $_.Exception.Message) }
    $limits = Get-HordeLinkLimits $Frame
    foreach ($k in @("frameBytes", "frameBytesCeiling", "summaryBytes", "textBytes", "reasonBytes", "nameBytes", "listItems")) {
        $v = $null
        if ($limits.ContainsKey($k)) { $v = $limits[$k] }
        if (-not ($v -is [int] -or $v -is [long]) -or $v -lt 1) { [void]$out.Add("x-horde-limits has no positive whole $k") }
    }
    if ($out.Count -eq 0) {
        if ($limits["frameBytes"] -gt $limits["frameBytesCeiling"]) { [void]$out.Add("frameBytes is above frameBytesCeiling") }
        if ($limits["frameBytesCeiling"] -gt 4194304) { [void]$out.Add("frameBytesCeiling is above 4 MiB, which the design never allows") }
        if ($limits["summaryBytes"] -ge $limits["frameBytes"] -or $limits["textBytes"] -ge $limits["frameBytes"]) { [void]$out.Add("a summary or a text would not fit in one frame") }
    }
    $props = Get-HordeLinkProp $Frame "properties"
    $kinds = Get-HordeLinkProp $Frame "x-horde-kinds"
    $kindEnum = @(Get-HordeLinkProp (Get-HordeLinkProp $props "kind") "enum")
    foreach ($k in $kindEnum) {
        $rule = Get-HordeLinkProp $kinds "$k"
        if ($null -eq $rule) { [void]$out.Add("kind '$k' has no member rule in x-horde-kinds"); continue }
        foreach ($m in @(@(Get-HordeLinkProp $rule "required") + @(Get-HordeLinkProp $rule "allowed") + @(Get-HordeLinkProp $rule "oneOf") | Where-Object { $null -ne $_ })) {
            if (-not (Test-HordeLinkHasProp $props "$m")) { [void]$out.Add("kind '$k' names member '$m', which the envelope does not have") }
        }
        foreach ($m in @(Get-HordeLinkProp $rule "required")) { if ($null -ne $m -and @(Get-HordeLinkProp $rule "allowed") -cnotcontains $m) { [void]$out.Add("kind '$k' requires '$m' and does not allow it") } }
    }
    foreach ($f in @(Get-HordeLinkSchemaFindings -Node $Frame -Root $Frame -Where '$' -Role "frame" -Limits $limits -Exempt @('$.args', '#/definitions/answer.value'))) { [void]$out.Add($f) }
    return @($out)
}

function Get-HordeLinkContract {
    # The contract in use: the frame schema, the verb table, the limits and the rows by name.
    $frame = Get-HordeSchema -Name "link-frame.v1"
    $verbs = Get-HordeSchema -Name "link-verbs.v1"
    $rows = @{}
    foreach ($r in @(Get-HordeLinkProp $verbs "x-horde-verbs")) { $rows["$($r.name)"] = $r }
    return [pscustomobject]@{ frame = $frame; verbs = $verbs; limits = (Get-HordeLinkLimits $frame); rows = $rows }
}

function Get-HordeLinkNodes {
    # Every (value, schema node, path) pair in Value, walking the schema beside it: $refs are resolved in
    # Root, properties and items followed where the value has them. Used after Test-HordeSchema has
    # passed, so types agree. Returns a flat list - no callback, so nothing here invokes a block.
    param($Value, $Node, $Root, [string]$Path = '$')
    $out = New-Object System.Collections.ArrayList
    $n = $Node
    $guard = 0
    while ($null -ne (Get-HordeLinkProp $n '$ref')) {
        $n = Resolve-HordeLinkRef -Ref "$(Get-HordeLinkProp $n '$ref')" -Root $Root
        $guard++
        if ($guard -gt 64) { throw ("the schema's `$ref chain at " + $Path + " does not end") }
    }
    [void]$out.Add([pscustomobject]@{ value = $Value; node = $n; path = $Path })
    $isObject = ($Value -is [System.Management.Automation.PSCustomObject] -or $Value -is [System.Collections.IDictionary])
    $props = Get-HordeLinkProp $n "properties"
    if ($isObject -and $null -ne $props) {
        foreach ($p in (Get-HordeObjectProps $Value)) {
            $child = Get-HordeLinkProp $props $p.Name
            if ($null -ne $child) { foreach ($x in @(Get-HordeLinkNodes -Value $p.Value -Node $child -Root $Root -Path ($Path + "." + $p.Name))) { [void]$out.Add($x) } }
        }
    }
    $items = Get-HordeLinkProp $n "items"
    if ($Value -is [System.Collections.IList] -and $null -ne $items) {
        $i = 0
        foreach ($item in $Value) { foreach ($x in @(Get-HordeLinkNodes -Value $item -Node $items -Root $Root -Path ($Path + "[" + $i + "]"))) { [void]$out.Add($x) }; $i++ }
    }
    return @($out)
}

function Test-HordeLinkIsAnswerNode {
    # A schema node is an answer when it is an object whose state is exactly core/tristate's three.
    param($Node)
    $state = Get-HordeLinkProp (Get-HordeLinkProp $Node "properties") "state"
    if ($null -eq $state) { return $false }
    $enum = @(Get-HordeLinkProp $state "enum")
    return ($enum.Count -eq 3 -and $enum -ccontains "known" -and $enum -ccontains "absent" -and $enum -ccontains "unknown")
}

function Test-HordeLinkAnswer {
    # core/tristate's rules for one answer, as they travel (schema/link-frame.v1): known carries a value
    # and the time it was observed; absent carries the time and no value; unknown carries no value and a
    # reason that is not blank. A null value or time is left out, never written as null.
    param($Answer, [string]$Path)
    $out = New-Object System.Collections.ArrayList
    $state = "$(Get-HordeLinkProp $Answer 'state')"
    $hasValue = Test-HordeLinkHasProp $Answer "value"
    $hasTime = Test-HordeLinkHasProp $Answer "observedAt"
    if ($hasValue -and $null -eq (Get-HordeLinkProp $Answer "value")) { [void]$out.Add("$Path.value is null; a value that is not there is left out") }
    if ($hasTime -and $null -eq (Get-HordeLinkProp $Answer "observedAt")) { [void]$out.Add("$Path.observedAt is null; a time that is not there is left out") }
    switch ($state) {
        "known" {
            if (-not $hasValue) { [void]$out.Add("$Path is known and carries no value") }
            if (-not $hasTime) { [void]$out.Add("$Path is known and says nothing of when it was observed, so its age cannot be judged") }
        }
        "absent" {
            if ($hasValue) { [void]$out.Add("$Path is absent and carries a value") }
            if (-not $hasTime) { [void]$out.Add("$Path is absent and says nothing of when it was observed, so its age cannot be judged") }
        }
        "unknown" {
            if ($hasValue) { [void]$out.Add("$Path is unknown and carries a value") }
            if ("$(Get-HordeLinkProp $Answer 'reason')".Trim() -eq "") { [void]$out.Add("$Path is unknown and gives no reason") }
        }
    }
    return @($out)
}

function Test-HordeLinkValue {
    # A value against a schema (Schema is what Test-HordeSchema takes; Node and Root are the same schema
    # for the walk), then core/tristate's rules on every answer inside it.
    param($Value, $Schema, $Node, $Root, [string]$Path)
    $found = @(Test-HordeSchema -Value $Value -Schema $Schema -Path $Path)
    if ($found.Count -gt 0) { return $found }
    $out = New-Object System.Collections.ArrayList
    foreach ($x in @(Get-HordeLinkNodes -Value $Value -Node $Node -Root $Root -Path $Path)) {
        if ((Test-HordeLinkIsAnswerNode $x.node) -and ($x.value -is [System.Management.Automation.PSCustomObject] -or $x.value -is [System.Collections.IDictionary])) {
            foreach ($f in @(Test-HordeLinkAnswer -Answer $x.value -Path $x.path)) { [void]$out.Add($f) }
        }
    }
    return @($out)
}

function Test-HordeContractDocument {
    # A whole document against one of the contract schemas by name (node-manifest.v1,
    # overlay-endpoint.v1, transport-capabilities.v1), with the answer rules on every answer in it.
    param($Value, [Parameter(Mandatory = $true)][string]$SchemaName)
    $s = Get-HordeSchema -Name $SchemaName
    return @(Test-HordeLinkValue -Value $Value -Schema $s -Node $s -Root $s -Path '$')
}

function Test-HordeLinkFrame {
    # One parsed frame against the contract. Returns findings; empty means the frame may be acted on.
    param($Frame, $Contract = $null)
    if ($null -eq $Contract) { $Contract = Get-HordeLinkContract }
    $found = @(Test-HordeSchema -Value $Frame -Schema $Contract.frame -Path '$')
    if ($found.Count -gt 0) { return $found }
    $out = New-Object System.Collections.ArrayList
    $kind = "$($Frame.kind)"
    $rule = Get-HordeLinkProp (Get-HordeLinkProp $Contract.frame "x-horde-kinds") $kind
    $members = @((Get-HordeObjectProps $Frame) | ForEach-Object { $_.Name } | Where-Object { @("v", "kind", "id", "seq", "ts") -cnotcontains $_ })
    foreach ($m in @(Get-HordeLinkProp $rule "required")) { if ($null -ne $m -and $members -cnotcontains $m) { [void]$out.Add("a $kind frame has no '$m'") } }
    foreach ($m in $members) { if (@(Get-HordeLinkProp $rule "allowed") -cnotcontains $m) { [void]$out.Add("a $kind frame may not carry '$m'") } }
    $one = @(Get-HordeLinkProp $rule "oneOf" | Where-Object { $null -ne $_ })
    if ($one.Count -gt 0 -and @($one | Where-Object { $members -ccontains $_ }).Count -ne 1) { [void]$out.Add("a $kind frame carries exactly one of " + ($one -join ", ")) }
    if ($out.Count -gt 0) { return @($out) }
    if ($members -cnotcontains "verb") { return @() }
    # A refusal names the verb it refuses, which may be one the table does not have ("exec"), so an
    # error res is not looked up: the error is the whole answer.
    if ($members -ccontains "error") { return @() }
    $row = $null
    if ($Contract.rows.ContainsKey("$($Frame.verb)")) { $row = $Contract.rows["$($Frame.verb)"] }
    if ($null -eq $row) { return @("unsupported-verb: '" + $Frame.verb + "' is not a verb of link-verbs v1") }
    if ($kind -ceq "evt") { return @("no verb of link-verbs v1 streams events: '" + $Frame.verb + "' has none (observe.since and metrics.since bring them, plan steps R12 and R15)") }
    if ($kind -ceq "req") {
        $a = Resolve-HordeLinkTarget -Doc $Contract.verbs -Target "$($row.args)"
        return @(Test-HordeLinkValue -Value $Frame.args -Schema $a.schema -Node $a.node -Root $a.root -Path '$.args')
    }
    if ($members -ccontains "result") {
        $answer = $Frame.result
        $found = @(Test-HordeLinkAnswer -Answer $answer -Path '$.result')
        if ($found.Count -gt 0) { return $found }
        if ("$($answer.state)" -ceq "known") {
            $r = Resolve-HordeLinkTarget -Doc $Contract.verbs -Target "$($row.result)"
            return @(Test-HordeLinkValue -Value $answer.value -Schema $r.schema -Node $r.node -Root $r.root -Path '$.result.value')
        }
    }
    return @()
}
