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

# THE VERBS, AND EVERY ARGUMENT EACH MAY TAKE, AS AN ALLOWLIST. The word lists above are a second line:
# the review of PR #40 (2026-10-01) found argument names they miss (url, remoteUrl, uri, flags,
# extraArgs, options, hook, stdin, mcp, plugin, systemPrompt, settings) and verbs they miss
# (node.restart, repo.push, profile.define, auth.login, policy.set, ceiling.raise), and a longer list
# would miss the next spelling. So a verb the table has must be named here, and every argument its args
# schema can carry must be listed here by its path - "worktree.name", "sessions[].sessionId" - so an
# argument cannot be added, or moved under another verb or another parent, without a change to this
# file that a reviewer reads. The table cannot loosen it: it lives here, not in the table.
#
# EACH VERB'S EFFECT CLASS IS PINNED HERE TOO, so a table cannot reclass a verb downwards. The class that
# matters most is drive: session.deliver types into a running session, and the review of PR #40 found
# that classing it write let it drive any session on the node, a bypass-permission one included. Its
# class is drive, gated by the node's permission ceiling exactly like spawn (plan step R9), and it may
# target only a session this hub spawned on that node - hub-owned in the session record (R19, R21).
$script:HordeLinkVerbAllow = @{
    "node.info"       = @{ effect = "read";  args = @() }
    "request.status"  = @{ effect = "read";  args = @("requestId") }
    "handoff.get"     = @{ effect = "read";  args = @("sessionId", "handoffId") }
    "clone.status"    = @{ effect = "read";  args = @("repoId", "worktree") }
    "delivery.status" = @{ effect = "read";  args = @("messageId") }
    "session.spawn"   = @{ effect = "spawn"; args = @("label", "role", "parent", "runId", "fleetSessionId", "profile", "model", "repoId",
                          "worktree", "worktree.name", "worktree.branch", "worktree.base", "prompt", "prompt.text",
                          "prompt.handoffRef", "host", "closeOn") }
    "session.resume"  = @{ effect = "spawn"; args = @("sessionId", "reresolve", "model") }
    "session.deliver" = @{ effect = "drive"; args = @("messageId", "sessionId", "from", "from.deviceId", "from.sessionId", "from.label", "body",
                          "ttlSeconds") }
    "session.close"   = @{ effect = "kill";  args = @("sessionId", "expect", "expect.ns", "expect.ns.device", "expect.ns.space", "expect.pid", "expect.procStart", "reason") }
    "worktree.create" = @{ effect = "write"; args = @("repoId", "name", "branch", "base") }
    "worktree.remove" = @{ effect = "kill";  args = @("repoId", "name") }
    "alert.raise"     = @{ effect = "write"; args = @("alertId", "sessionId", "label", "kind", "summary", "raisedAt") }
    "unowned.report"  = @{ effect = "read";  args = @("sessions", "sessions[].sessionId", "sessions[].harness", "sessions[].startedAt", "observedAt") }
}

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

function Get-HordeLinkPairs {
    # A parsed object's members as name/value pairs, whether it came from JSON or is a hashtable. This
    # file's own, not core's: it used core/Schema.ps1's Get-HordeObjectProps, which the schema cache work
    # removed (34b581b) while this branch was open, and remote/ failed on main once both merged.
    param($Value)
    $out = New-Object System.Collections.ArrayList
    if ($Value -is [System.Collections.IDictionary]) { foreach ($k in @($Value.Keys)) { [void]$out.Add([pscustomobject]@{ Name = "$k"; Value = $Value[$k] }) } }
    else { foreach ($p in @($Value.PSObject.Properties)) { [void]$out.Add([pscustomobject]@{ Name = $p.Name; Value = $p.Value }) } }
    return @($out)
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

function Get-HordeLinkArgPaths {
    # Every property path an args schema can carry: "worktree", "worktree.name", "sessions[].sessionId".
    # $refs are followed in Root; a ref already on the way down stops the walk (a recursive shape is a
    # finding of Get-HordeLinkSchemaFindings, not a path).
    param($Node, $Root, [string]$Prefix = "", [string[]]$Refs = @())
    $out = New-Object System.Collections.ArrayList
    $n = $Node
    while ($null -ne (Get-HordeLinkProp $n '$ref')) {
        $r = "$(Get-HordeLinkProp $n '$ref')"
        if ($Refs -ccontains $r) { return @() }
        $Refs = @($Refs) + $r
        try { $n = Resolve-HordeLinkRef -Ref $r -Root $Root } catch { return @() }
    }
    $props = Get-HordeLinkProp $n "properties"
    if ($null -ne $props) {
        foreach ($p in @($props.PSObject.Properties)) {
            $path = $p.Name
            if ($Prefix -ne "") { $path = $Prefix + "." + $p.Name }
            [void]$out.Add($path)
            foreach ($x in @(Get-HordeLinkArgPaths -Node $p.Value -Root $Root -Prefix $path -Refs $Refs)) { [void]$out.Add($x) }
        }
    }
    $items = Get-HordeLinkProp $n "items"
    if ($null -ne $items) { foreach ($x in @(Get-HordeLinkArgPaths -Node $items -Root $Root -Prefix ($Prefix + "[]") -Refs $Refs)) { [void]$out.Add($x) } }
    return @($out)
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
        $allow = $null
        $effect = "$(Get-HordeLinkProp $row 'effect')"
        if ($script:HordeLinkVerbAllow.ContainsKey($name)) {
            $allow = $script:HordeLinkVerbAllow[$name].args
            $pinned = $script:HordeLinkVerbAllow[$name].effect
            if ($effect -cne $pinned) { [void]$out.Add("$at is classed '" + $effect + "'; remote/Contract.ps1 classes it '" + $pinned + "', and a table cannot reclass a verb") }
        }
        else { [void]$out.Add("$at is not a verb of remote/Contract.ps1's allowlist: a verb is added there, by review, before any table may carry it") }
        $since = Get-HordeLinkProp $row "since"
        if (($since -is [int] -or $since -is [long]) -and ($protocol -is [int] -or $protocol -is [long]) -and $since -gt $protocol) { [void]$out.Add("$at is since protocol $since, after this table's protocol $protocol") }
        # A node never asks the hub to start, drive or end anything: every spawn, drive and kill travels
        # hub to node, where the node's own admission and policy decide (plan steps R9 and R19).
        if ("$(Get-HordeLinkProp $row 'direction')" -ceq "node-to-hub" -and ($effect -ceq "spawn" -or $effect -ceq "drive" -or $effect -ceq "kill")) { [void]$out.Add("$at travels node to hub with effect $effect; a node never asks the hub to spawn, drive or kill") }
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
            if ($part -ceq "args" -and $null -ne $allow) {
                foreach ($path in @(Get-HordeLinkArgPaths -Node $t.node -Root $t.root)) {
                    if (@($allow) -cnotcontains $path) { [void]$out.Add("$at args has '" + $path + "', which is not an argument " + $name + " may take: remote/Contract.ps1 lists every one") }
                }
            }
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
    # walk: the link walk's records for this contract's schemas, read once (Get-HordeLinkWalkTarget).
    return [pscustomobject]@{ frame = $frame; verbs = $verbs; limits = (Get-HordeLinkLimits $frame); rows = $rows; walk = (New-HordeLinkWalkMemo) }
}

# THE LINK WALK (fix/link-writer-speed). Every value a frame carries is checked by walking it beside its
# schema: core/Schema.ps1's rules (Test-HordeSchema), core/tristate's rules on every answer inside it
# (Test-HordeLinkAnswer), and every per-field cap (remote/Protocol.ps1, Test-HordeProtocolLimits). Those
# were three recursive walks, one PowerShell call per node and a dozen helper calls inside each, about
# 2,350 calls per session summary: encoding a 32-session sessions.list took 18 s on the founder's box
# and 256 sessions 200 s (measured 2026-10-02; the profile is in the pull request). A call costs 25 us
# there, 170 us once Windows throttles a busy background process; an inline step costs about 1 us.
#
# So the walk is ONE LOOP over an explicit stack, with each schema node read once into a record
# (Get-HordeLinkWalkRecord) the first time a value reaches it, and kept. Nothing in the loop calls a
# function per node except where the old code did something rare: a type or enum check on a number
# that is not Int32 or Int64, a minimum, a string that needs escaping, an answer's own rules.
#
# EXACTLY THE OLD ANSWERS. The records are read through core/Schema.ps1's own Get-HordeSchemaNode and
# Assert-HordeSchema, so a schema is refused as Test-HordeSchema refuses it and its pattern is the
# Regex Test-HordeSchema matches with; each check below is the old line, inlined. The keywords the walk
# implements are core/Schema.ps1's whole list; a node with any other is refused by Get-HordeSchemaNode,
# and $script:HordeLinkWalkKeywords is compared with that list when this file loads, so the two cannot
# drift apart silently. test/test-link-walk.ps1 runs the code this replaced
# (test/fixtures/link-walk/reference.ps1) beside it, on every input of every link suite, and requires
# the same findings, in the same order.
#
# Two walks in one. The schema check (Test-HordeSchema) stops at a value of the wrong type and matches
# property names exactly; the node walk the caps and answers used (Get-HordeLinkNodes) went on below a
# wrong type and matched names as PowerShell does, without case. Each stack entry carries whether the
# schema check is still live, so one pass answers both, each as before.
#
# A SCHEMA THAT CHANGES MUST BE A NEW OBJECT, as in core/Schema.ps1: records are kept per contract
# (Get-HordeLinkContract makes a new one each call) and read from the schema the first time.

$script:HordeLinkWalkKeywords = @("type", "required", "properties", "additionalProperties", "items", "enum", "pattern", "minimum",
                                  '$schema', '$id', "title", "description", "definitions", '$ref')
$script:HordeLinkWalkKeywordsAgree = ($script:HordeLinkWalkKeywords.Count -eq @($script:HordeSchemaKeywords).Count)
foreach ($hordeLinkWalkKeyword in @($script:HordeSchemaKeywords)) { if ($script:HordeLinkWalkKeywords -cnotcontains $hordeLinkWalkKeyword) { $script:HordeLinkWalkKeywordsAgree = $false } }
if (-not $script:HordeLinkWalkKeywordsAgree) {
    throw ("remote/Contract.ps1's link walk implements the keywords " + ($script:HordeLinkWalkKeywords -join ", ") + ", and core/Schema.ps1 now accepts " + ($script:HordeSchemaKeywords -join ", ") + ": teach the walk the difference before using it")
}

# Each property and items slot is numbered, so two views of a slot can be told to be the same one.
$script:HordeLinkWalkSlots = 0

function New-HordeLinkWalkMemo {
    # Records by definition name, for one schema root: a definition reached through a $ref is read
    # once per root, and a recursive one ends.
    return (New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal))
}

function Get-HordeLinkWalkRecord {
    # The walk's record for one schema node: its chain of $refs followed to the node a value meets, and
    # that node's keywords as core/Schema.ps1 reads them. TopEntry is the top of a schema as
    # Assert-HordeSchema returned it (a top may hold definitions, so it is not read as an inner node).
    # Path is the path of the value that first reached the node: a refusal names it, as
    # Test-HordeSchema's does.
    param($Raw, $Root, [string]$Path, [Parameter(Mandatory = $true)]$Memo, $TopEntry = $null)
    $entry = $TopEntry
    if ($null -eq $entry) { $entry = Get-HordeSchemaNode -Schema $Raw -Path $Path -AtTop $false }
    $chain = New-Object System.Collections.ArrayList
    while ($entry.kw.ContainsKey('$ref')) {
        $ref = $entry.kw['$ref']
        if ($chain -ccontains $ref) { throw ("the schema's `$ref chain at " + $Path + " is circular: it comes back to '" + $ref + "' without reaching a value") }
        [void]$chain.Add($ref)
        if ($Memo.ContainsKey($ref)) {
            $known = $Memo[$ref]
            foreach ($r in $chain) { $Memo[$r] = $known }
            return $known
        }
        $Raw = Resolve-HordeLinkRef -Ref $ref -Root $Root
        $entry = Get-HordeSchemaNode -Schema $Raw -Path $Path -AtTop $false
    }
    $kw = $entry.kw
    $rec = @{ type = $null; required = @(); props = $null; propsAnyCase = $null; addFalse = $false; items = $null
        hasEnum = $false; enum = @(); regex = $null; pattern = $null; hasMin = $false; minimum = $null
        isAnswer = $false; cap = $null; capEnum = $false }
    if ($kw.ContainsKey("type")) { $rec.type = "$($kw['type'])" }
    if ($kw.ContainsKey("required")) { $rec.required = @(@($kw["required"]) | Where-Object { $null -ne $_ } | ForEach-Object { "$_" }) }
    if ($kw.ContainsKey("properties")) {
        # Two views of one set of slots: by exact name for the schema check (core/Schema.ps1 keys an
        # ordinal dictionary), and by name without case for the node walk (Get-HordeLinkProp read
        # .PSObject.Properties, which ignores case; the first match won).
        $rec.props = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
        $rec.propsAnyCase = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in @($entry.props.Keys)) {
            $script:HordeLinkWalkSlots++
            $slot = @{ raw = $entry.props[$name]; rec = $null; id = $script:HordeLinkWalkSlots }
            $rec.props[$name] = $slot
            if (-not $rec.propsAnyCase.ContainsKey($name)) { $rec.propsAnyCase[$name] = $slot }
        }
    }
    $rec.addFalse = ($kw.ContainsKey("additionalProperties") -and $kw["additionalProperties"] -eq $false)
    if ($kw.ContainsKey("items")) { $script:HordeLinkWalkSlots++; $rec.items = @{ raw = $kw["items"]; rec = $null; id = $script:HordeLinkWalkSlots } }
    if ($kw.ContainsKey("enum")) { $rec.hasEnum = $true; $rec.enum = @($kw["enum"]) }
    if ($kw.ContainsKey("pattern")) { $rec.pattern = $kw["pattern"]; $rec.regex = $entry.regex }
    if ($kw.ContainsKey("minimum")) { $rec.hasMin = $true; $rec.minimum = $kw["minimum"] }
    $rec.isAnswer = Test-HordeLinkIsAnswerNode $Raw
    $rec.cap = Get-HordeLinkProp $Raw "x-horde-cap"
    $rec.capEnum = ($null -ne (Get-HordeLinkProp $Raw "enum"))
    foreach ($r in $chain) { $Memo[$r] = $rec }
    return $rec
}

function Get-HordeLinkWalkTarget {
    # The record for a verb row's args or result ("#/definitions/<name>" in the verb table, or a whole
    # schema by name), asserted once as Test-HordeSchema asserts it and kept in the contract. Path is
    # where the value sits in its frame ('$.args', '$.result.value').
    param([Parameter(Mandatory = $true)]$Contract, [Parameter(Mandatory = $true)][string]$Target, [Parameter(Mandatory = $true)][string]$Path)
    $cache = Get-HordeLinkWalkCache $Contract
    $key = "target|" + $Path + "|" + $Target
    if ($cache.ContainsKey($key)) { return $cache[$key] }
    $t = Resolve-HordeLinkTarget -Doc $Contract.verbs -Target $Target
    $top = Assert-HordeSchema -Schema $t.schema -Path $Path
    $memoKey = "memo|verbs"
    if (-not $Target.StartsWith("#")) { $memoKey = "memo|" + $Target }
    if (-not $cache.ContainsKey($memoKey)) { $cache[$memoKey] = New-HordeLinkWalkMemo }
    $rec = Get-HordeLinkWalkRecord -Raw $t.schema -Root $t.root -Path $Path -Memo $cache[$memoKey] -TopEntry $top
    $found = [pscustomobject]@{ rec = $rec; root = $t.root; memo = $cache[$memoKey] }
    $cache[$key] = $found
    return $found
}

function Get-HordeLinkWalkCache {
    # The contract's own table of records; a contract built by hand, without one, gets a table for this
    # call only, so it is read correctly, just not remembered.
    param([Parameter(Mandatory = $true)]$Contract)
    $c = Get-HordeLinkProp $Contract "walk"
    if ($null -ne $c) { return $c }
    return (New-HordeLinkWalkMemo)
}

function Invoke-HordeLinkWalk {
    # One value walked beside its schema record. Returns { schema; answers; caps }:
    #   schema  - Test-HordeSchema's findings, in its order (empty unless -Schema);
    #   answers - the answer objects met, as (value, path) pairs, in Get-HordeLinkNodes' order;
    #   caps    - Test-HordeProtocolLimits' findings for this value (empty unless -Limits is given).
    param($Value, [Parameter(Mandatory = $true)]$Rec, [string]$Path, $Root, [Parameter(Mandatory = $true)]$Memo, [bool]$Schema = $true, $Limits = $null)
    $schemaOut = New-Object System.Collections.ArrayList
    $answers = New-Object System.Collections.ArrayList
    $capOut = New-Object System.Collections.ArrayList
    $caps = ($null -ne $Limits)
    $listCap = $null
    if ($caps) { $listCap = $Limits["listItems"] }
    # An entry is (0, value, record, path, schema check live) to visit, or (1, finding) to write a
    # schema finding in its place among a parent's children.
    $stack = New-Object System.Collections.Stack
    $order = New-Object System.Collections.Stack
    $stack.Push(@(0, $Value, $Rec, $Path, $Schema))
    while ($stack.Count -gt 0) {
        $e = $stack.Pop()
        if ($e[0] -eq 1) { [void]$schemaOut.Add($e[1]); continue }
        $v = $e[1]; $r = $e[2]; $p = $e[3]; $live = $e[4]
        $isObject = ($v -is [System.Management.Automation.PSCustomObject] -or $v -is [System.Collections.IDictionary])
        $isList = ($v -is [System.Collections.IList])
        # THE CAPS, as Test-HordeProtocolLimits checked each node.
        if ($caps) {
            if ($v -is [string]) {
                if ($null -eq $r.cap) {
                    if (-not $r.capEnum) { [void]$capOut.Add($p + " is a string whose schema names no cap") }
                } else {
                    $limit = $Limits["$($r.cap)"]
                    # Measure-HordeWireString's own fast path: a string with nothing to escape is its length.
                    if ([regex]::IsMatch($v, $script:HordeWirePlain)) { $size = $v.Length } else { $size = Measure-HordeWireString $v }
                    if ($size -gt $limit) { [void]$capOut.Add($p + " is " + $size + " bytes on the wire, over its " + $r.cap + " cap of " + $limit) }
                }
            } elseif ($isList) {
                if ($v.Count -gt $listCap) { [void]$capOut.Add($p + " has " + $v.Count + " items, over the listItems cap of " + $listCap) }
            }
        }
        if ($r.isAnswer -and $isObject) { [void]$answers.Add(@($v, $p)) }
        # THE SCHEMA CHECK of this node, as Test-HordeSchema made it: a wrong type ends it here.
        if ($live) {
            if ($null -ne $r.type) {
                $tt = $r.type
                if ($tt -ceq "string") { $ok = ($v -is [string]) }
                elseif ($tt -ceq "object") { $ok = $isObject }
                elseif ($tt -ceq "array") { $ok = $isList }
                elseif ($tt -ceq "boolean") { $ok = ($v -is [bool]) }
                elseif ($tt -ceq "integer" -and ($v -is [int] -or $v -is [long])) { $ok = $true }
                else { $ok = Test-HordeSchemaType -Value $v -Type $tt }
                if (-not $ok) { [void]$schemaOut.Add($p + " should be " + $r.type); $live = $false }
            }
        }
        if ($live) {
            if ($r.hasEnum) {
                $ok = $false
                foreach ($m in $r.enum) {
                    if ($m -is [string]) { if ($v -is [string] -and $v -ceq $m) { $ok = $true } }
                    elseif ($m -is [bool]) { if ($v -is [bool] -and $v -eq $m) { $ok = $true } }
                    elseif ((Test-HordeSchemaType -Value $v -Type "integer") -and [Math]::Abs([double]$v) -lt 1e19 -and [decimal]$v -eq [decimal]$m) { $ok = $true }
                }
                if (-not $ok) { [void]$schemaOut.Add($p + " is '" + $v + "', not one of: " + (@($r.enum) -join ", ")) }
            }
            if ($null -ne $r.regex -and $v -is [string]) {
                if (-not $r.regex.IsMatch($v)) { [void]$schemaOut.Add($p + " does not match " + $r.pattern) }
            }
            if ($r.hasMin -and (Test-HordeSchemaIsNumber $v)) {
                if (($v -is [double] -or $v -is [single]) -and [double]::IsNaN([double]$v)) { [void]$schemaOut.Add($p + " is NaN, which is not at or above the minimum " + $r.minimum) }
                elseif ((Compare-HordeSchemaNumber $v $r.minimum) -lt 0) { [void]$schemaOut.Add($p + " is " + $v + ", below the minimum " + $r.minimum) }
            }
        }
        # THE CHILDREN. Each is pushed onto $order first and then moved onto $stack, which reverses them,
        # so they are visited first to last. No collection is made per node: New-Object costs 100 us and
        # more here, more than the rest of a node's checks together.
        if ($isObject) {
            $isDict = ($v -is [System.Collections.IDictionary])
            # Keys that are not strings can collide once written as text (1 and "1"). The schema check
            # kept the last value under the first position, by exact name (Get-HordeObjectByKey); the
            # node walk visited every pair (Get-HordeLinkPairs). Only such a dictionary is told apart.
            $schemaValue = $null
            if ($isDict -and $live) {
                foreach ($k in @($v.Keys)) {
                    if ($k -isnot [string]) {
                        $schemaValue = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
                        foreach ($k2 in @($v.Keys)) { $schemaValue["$k2"] = $v[$k2] }
                        break
                    }
                }
            }
            if ($live) {
                foreach ($req in $r.required) {
                    $has = $false
                    if ($null -ne $schemaValue) { $has = $schemaValue.ContainsKey($req) }
                    elseif ($isDict) { foreach ($k in @($v.Keys)) { if ("$k" -ceq $req) { $has = $true; break } } }
                    else { $pr = $v.PSObject.Properties[$req]; $has = ($null -ne $pr -and $pr.Name -ceq $req) }
                    if (-not $has) { [void]$schemaOut.Add($p + " has no '" + $req + "'") }
                }
            }
            $seenKeys = $null
            if ($null -ne $schemaValue) { $seenKeys = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal) }
            $members = $null
            if ($isDict) { $members = @($v.Keys) } else { $members = $v.PSObject.Properties }
            foreach ($mem in $members) {
                if ($isDict) { $name = "$mem"; $childValue = $v[$mem] } else { $name = $mem.Name; $childValue = $mem.Value }
                $childPath = $p + "." + $name
                $schemaHere = $live
                if ($null -ne $seenKeys) { if ($seenKeys.ContainsKey($name)) { $schemaHere = $false } else { $seenKeys[$name] = $true } }
                $exact = $null
                if ($null -ne $r.props -and $r.props.ContainsKey($name)) { $exact = $r.props[$name] }
                $anyCase = $null
                if ($null -ne $r.propsAnyCase -and $r.propsAnyCase.ContainsKey($name)) { $anyCase = $r.propsAnyCase[$name] }
                if ($schemaHere -and $null -eq $exact -and $r.addFalse) { $order.Push(@(1, ($p + " has '" + $name + "', which the schema does not allow"))) }
                if ($null -eq $anyCase) { continue }
                if ($null -eq $anyCase.rec) { $anyCase.rec = Get-HordeLinkWalkRecord -Raw $anyCase.raw -Root $Root -Path $childPath -Memo $Memo }
                $childLive = ($schemaHere -and $null -ne $exact)
                # The common case: one slot serves both checks. Otherwise (a schema naming two
                # properties that differ only in case, or colliding dictionary keys) the node pair is
                # walked without the schema check and the schema's own value is checked on its own.
                if ($childLive -and ($exact.id -ne $anyCase.id -or $null -ne $schemaValue)) {
                    $order.Push(@(0, $childValue, $anyCase.rec, $childPath, $false))
                    if ($null -eq $exact.rec) { $exact.rec = Get-HordeLinkWalkRecord -Raw $exact.raw -Root $Root -Path $childPath -Memo $Memo }
                    $own = $childValue
                    if ($null -ne $schemaValue) { $own = $schemaValue[$name] }
                    $sub = Invoke-HordeLinkWalk -Value $own -Rec $exact.rec -Path $childPath -Root $Root -Memo $Memo -Schema $true
                    foreach ($f in $sub.schema) { $order.Push(@(1, $f)) }
                } else {
                    $order.Push(@(0, $childValue, $anyCase.rec, $childPath, $childLive))
                }
            }
        }
        if ($isList -and $null -ne $r.items) {
            if ($null -eq $r.items.rec) { $r.items.rec = Get-HordeLinkWalkRecord -Raw $r.items.raw -Root $Root -Path ($p + "[0]") -Memo $Memo }
            $i = 0
            foreach ($item in $v) { $order.Push(@(0, $item, $r.items.rec, ($p + "[" + $i + "]"), $live)); $i++ }
        }
        while ($order.Count -gt 0) { $stack.Push($order.Pop()) }
    }
    return [pscustomobject]@{ schema = $schemaOut.ToArray(); answers = $answers.ToArray(); caps = $capOut.ToArray() }
}

function Test-HordeLinkIsAnswerNode {
    # A schema node is an answer when it is an object whose state is exactly core/tristate's three.
    param($Node)
    $state = Get-HordeLinkProp (Get-HordeLinkProp $Node "properties") "state"
    if ($null -eq $state) { return $false }
    $enum = @(Get-HordeLinkProp $state "enum")
    return ($enum.Count -eq 3 -and $enum -ccontains "known" -and $enum -ccontains "absent" -and $enum -ccontains "unknown")
}

function Get-HordeLinkReturned {
    # Value as a function returning it hands it back: a list unrolled, so an empty one is nothing and a
    # list of one is its one item. Test-HordeLinkAnswer reads members inline and uses this to keep
    # Get-HordeLinkProp's answer for a member that is a list.
    param($Value)
    return $Value
}

function Test-HordeLinkAnswer {
    # core/tristate's rules for one answer, as they travel (schema/link-frame.v1): known carries a value
    # and the time it was observed; absent carries the time and no value; unknown carries no value and a
    # reason that is not blank. A null value or time is left out, never written as null.
    param($Answer, [string]$Path)
    # Its members are read here, inline, exactly as Get-HordeLinkProp and Test-HordeLinkHasProp read them
    # (a dictionary by Contains, anything else by its members, which ignores case). This runs once per
    # answer in a frame, 3,584 times in a 256-session sessions.list, and the seven helper calls it made
    # cost more than the rules themselves (fix/link-writer-speed). A list is made only for a finding.
    $out = @()
    $state = $null; $hasValue = $false; $value = $null; $hasTime = $false; $time = $null; $reason = $null
    if ($Answer -is [System.Collections.IDictionary]) {
        if ($Answer.Contains("state")) { $state = $Answer["state"] }
        $hasValue = $Answer.Contains("value"); if ($hasValue) { $value = $Answer["value"] }
        $hasTime = $Answer.Contains("observedAt"); if ($hasTime) { $time = $Answer["observedAt"] }
        if ($Answer.Contains("reason")) { $reason = $Answer["reason"] }
    } elseif ($null -ne $Answer) {
        $members = $Answer.PSObject.Properties
        $m = $members["state"]; if ($null -ne $m) { $state = $m.Value }
        $m = $members["value"]; $hasValue = ($null -ne $m); if ($hasValue) { $value = $m.Value }
        $m = $members["observedAt"]; $hasTime = ($null -ne $m); if ($hasTime) { $time = $m.Value }
        $m = $members["reason"]; if ($null -ne $m) { $reason = $m.Value }
    }
    $state = "$state"
    # A QUIRK, KEPT ON PURPOSE, NOT A RULE: Get-HordeLinkProp RETURNED each member, and PowerShell unrolls
    # a list a function returns, so an empty list came back as nothing and a list of one null as null.
    # An answer whose value is an empty list was therefore "null" to these rules. That looks like an
    # accident of the language, not a decision; it is kept here only because fix/link-writer-speed must
    # accept and refuse exactly as before (test/test-link-walk.ps1 found the difference, 2026-10-02).
    # No v1 verb's answer value can be a list, so no verdict turns on it today. The intended meaning is
    # issue #77: decide it there, and change this with the differential reference, never silently.
    if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string] -and $value -isnot [System.Collections.IDictionary]) { $value = Get-HordeLinkReturned $value }
    if ($time -is [System.Collections.IEnumerable] -and $time -isnot [string] -and $time -isnot [System.Collections.IDictionary]) { $time = Get-HordeLinkReturned $time }
    if ($hasValue -and $null -eq $value) { $out += @("$Path.value is null; a value that is not there is left out") }
    if ($hasTime -and $null -eq $time) { $out += @("$Path.observedAt is null; a time that is not there is left out") }
    switch ($state) {
        "known" {
            if (-not $hasValue) { $out += @("$Path is known and carries no value") }
            if (-not $hasTime) { $out += @("$Path is known and says nothing of when it was observed, so its age cannot be judged") }
        }
        "absent" {
            if ($hasValue) { $out += @("$Path is absent and carries a value") }
            if (-not $hasTime) { $out += @("$Path is absent and says nothing of when it was observed, so its age cannot be judged") }
        }
        "unknown" {
            if ($hasValue) { $out += @("$Path is unknown and carries a value") }
            if ("$reason".Trim() -eq "") { $out += @("$Path is unknown and gives no reason") }
        }
    }
    return @($out)
}

function Test-HordeLinkValue {
    # A value against a schema (Schema is what Test-HordeSchema takes; Node and Root are the same schema
    # for the walk), then core/tristate's rules on every answer inside it. -Walk, from
    # Get-HordeLinkWalkTarget, is the schema already read; without it the schema is read for this call.
    # Findings in Test-HordeSchema's order; the answer rules only when the schema passed, as before.
    param($Value, $Schema, $Node, $Root, [string]$Path, $Walk = $null)
    if ($null -eq $Walk) {
        $top = Assert-HordeSchema -Schema $Schema -Path $Path
        $memo = New-HordeLinkWalkMemo
        $Walk = [pscustomobject]@{ rec = (Get-HordeLinkWalkRecord -Raw $Schema -Root $Root -Path $Path -Memo $memo -TopEntry $top); root = $Root; memo = $memo }
    }
    $w = Invoke-HordeLinkWalk -Value $Value -Rec $Walk.rec -Path $Path -Root $Walk.root -Memo $Walk.memo
    if ($w.schema.Count -gt 0) { return @($w.schema) }
    $out = New-Object System.Collections.ArrayList
    foreach ($a in $w.answers) {
        foreach ($f in @(Test-HordeLinkAnswer -Answer $a[0] -Path $a[1])) { [void]$out.Add($f) }
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
    $members = @((Get-HordeLinkPairs $Frame) | ForEach-Object { $_.Name } | Where-Object { @("v", "kind", "id", "seq", "ts") -cnotcontains $_ })
    foreach ($m in @(Get-HordeLinkProp $rule "required")) { if ($null -ne $m -and $members -cnotcontains $m) { [void]$out.Add("a $kind frame has no '$m'") } }
    foreach ($m in $members) { if (@(Get-HordeLinkProp $rule "allowed") -cnotcontains $m) { [void]$out.Add("a $kind frame may not carry '$m'") } }
    $one = @(Get-HordeLinkProp $rule "oneOf" | Where-Object { $null -ne $_ })
    if ($one.Count -gt 0 -and @($one | Where-Object { $members -ccontains $_ }).Count -ne 1) { [void]$out.Add("a $kind frame carries exactly one of " + ($one -join ", ")) }
    if ($out.Count -gt 0) { return @($out) }
    # issuedAt is a REAL instant, not text shaped like one: the schema's pattern passed 2026-09-31 and
    # 24:00 (review of PR #40). Parsed with the one format the pattern allows, so a value that parses
    # is also the one spelling of its instant.
    if ($members -ccontains "issuedAt") {
        $issued = [datetime]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
        if (-not [datetime]::TryParseExact("$($Frame.issuedAt)", "yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$issued)) {
            return @("$.issuedAt '" + $Frame.issuedAt + "' is not a real UTC instant")
        }
    }
    if ($members -cnotcontains "verb") { return @() }
    # A refusal names the verb it refuses, which may be one the table does not have ("exec"), so an
    # error res is not looked up: the error is the whole answer.
    if ($members -ccontains "error") { return @() }
    $row = $null
    if ($Contract.rows.ContainsKey("$($Frame.verb)")) { $row = $Contract.rows["$($Frame.verb)"] }
    if ($null -eq $row) { return @("unsupported-verb: '" + $Frame.verb + "' is not a verb of link-verbs v1") }
    if ($kind -ceq "evt") { return @("no verb of link-verbs v1 streams events: '" + $Frame.verb + "' has none (observe.since and metrics.since bring them, plan steps R12 and R15)") }
    if ($kind -ceq "req") {
        $a = Get-HordeLinkWalkTarget -Contract $Contract -Target "$($row.args)" -Path '$.args'
        return @(Test-HordeLinkValue -Value $Frame.args -Walk $a -Path '$.args')
    }
    if ($members -ccontains "result") {
        $answer = $Frame.result
        $found = @(Test-HordeLinkAnswer -Answer $answer -Path '$.result')
        if ($found.Count -gt 0) { return $found }
        if ("$($answer.state)" -ceq "known") {
            $r = Get-HordeLinkWalkTarget -Contract $Contract -Target "$($row.result)" -Path '$.result.value'
            return @(Test-HordeLinkValue -Value $answer.value -Walk $r -Path '$.result.value')
        }
    }
    return @()
}

function Test-HordeLinkResend {
    # Is Again a resend of the request First? A resend is the same request in a new frame: a new id,
    # and its own seq and ts, with the same requestId, issuedAt, verb and arguments. The node's journal
    # (plan step R3) keys on requestId and judges its replay window by issuedAt, so a "resend" that
    # moved issuedAt would reopen a window the first send closed, and one with other arguments is a
    # different request under a reused id. Both frames must themselves be valid. Returns findings;
    # empty means Again is a resend of First.
    param([Parameter(Mandatory = $true)]$First, [Parameter(Mandatory = $true)]$Again, $Contract = $null)
    if ($null -eq $Contract) { $Contract = Get-HordeLinkContract }
    $out = New-Object System.Collections.ArrayList
    # Every finding is collected, not the first: a resend naming another verb is also invalid for its
    # arguments, and the report says both.
    $notReq = $false
    foreach ($pair in @(@("the first frame", $First), @("the resend", $Again))) {
        if ("$(Get-HordeLinkProp $pair[1] 'kind')" -cne "req") { [void]$out.Add($pair[0] + " is not a req; only a request is resent"); $notReq = $true }
        foreach ($f in @(Test-HordeLinkFrame -Frame $pair[1] -Contract $Contract)) { [void]$out.Add($pair[0] + ": " + $f) }
    }
    if ($notReq) { return @($out) }
    if ("$($Again.id)" -ceq "$($First.id)") { [void]$out.Add("the resend reuses the frame id " + $First.id + "; a resend is a new frame and needs a new frame id") }
    # EVERY COMPARISON HERE IS ORDINAL: code unit by code unit. -ceq and -cne compare by culture, which
    # ignores some characters entirely: the review of PR #40 measured a prompt with a soft hyphen
    # (U+00AD), a NUL or a zero-width space appended passing as the same request.
    foreach ($m in @("requestId", "issuedAt", "verb")) {
        if (-not [string]::Equals("$(Get-HordeLinkProp $Again $m)", "$(Get-HordeLinkProp $First $m)", [System.StringComparison]::Ordinal)) { [void]$out.Add("the resend's " + $m + " is '" + (Get-HordeLinkProp $Again $m) + "', not the first send's '" + (Get-HordeLinkProp $First $m) + "'") }
    }
    # The arguments compared as JSON text, so key order and every value count. Both frames passed the
    # contract above, so both are plain data that serialises fully at this depth. ConvertTo-Json keeps
    # every character of a string (it escapes some, always the same way), so two texts that are equal
    # code unit by code unit hold the same arguments; the reverse can fail - the same arguments in
    # another key order differ - which refuses a resend, the safe side. The journal's argsHash over the
    # link's one canonical spelling (plan steps R2 and R3) is the same rule on the wire.
    $a1 = ConvertTo-Json -InputObject $First.args -Depth 40 -Compress
    $a2 = ConvertTo-Json -InputObject $Again.args -Depth 40 -Compress
    if (-not [string]::Equals($a1, $a2, [System.StringComparison]::Ordinal)) { [void]$out.Add("the resend's args differ from the first send's") }
    return @($out)
}
