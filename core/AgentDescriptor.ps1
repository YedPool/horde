# core/AgentDescriptor - what each agent harness offers, read strictly from agents/<name>/agent.json.
#
# ENGINES PLAN STEP E2 (planning/execution-plan-engines.md). A harness is the command-line program a
# session runs. Every later engines step that picks or launches one asks this file what the harness
# can do: E3 checks a harness against a provider's wire format and the subscription rule (protocols,
# nativeProvider), E4 checks a role's requirements (capabilities), K1 checks session ids
# (sessionIdPattern), E10 scrubs inherited provider variables (ownedEnv), and the lifecycle plan's
# follower translates hook names into Horde's four events (events). So a descriptor that is wrong in
# any way never loads: there is no partial descriptor and no default for a missing field.
#
# ONE VOCABULARY OF STATES: yes, no, declined or unverified, the same four the host port
# (core/HostPort.ps1) and schema/transport-capabilities.v1 use. UNVERIFIED NEVER COUNTS AS YES. A
# capability nobody has measured is answered UNKNOWN, with its evidence as the reason - never yes,
# and never a plain no either, because "nobody looked" and "it cannot" are different answers
# (core/Tristate.ps1; agent-engines research 6.4: a missing capability is unknown with a reason,
# never "none").
#
# WHICH CAPABILITIES. core/capabilities.json is the closed list, and says for each which port can
# satisfy it: agent, host or either. A descriptor declares every capability an agent can satisfy
# (agent or either), and nothing else. The schema lists the same names, so the file reads correctly
# in any JSON Schema tool; test/test-agent-descriptor.ps1 fails when the two lists differ.
#
# STRICT, AND ALL AT ONCE. A refusal names every problem found, so a descriptor wrong in two places
# says so once. Rules the draft-07 subset in core/Schema.ps1 cannot say are checked here: the name is
# its folder's, protocols are distinct and at least one, the session-id pattern compiles and is
# anchored at both ends (an unanchored pattern accepts any id that merely CONTAINS a match), owned
# variable names are distinct ignoring case (Windows environment names are), and an event the harness
# supports names its hook while one it lacks names none. The bytes are plain ASCII with no BOM
# (CONTRIBUTING 13), checked before decoding, and no key may appear twice in one object, because
# ConvertFrom-Json keeps the last silently and a reader would believe the first.
#
# NO HARNESS IS NAMED HERE (CONTRIBUTING 14). Harnesses are found by folder, as core/Price.ps1 finds
# price tables.
#
# PERMISSION LEVELS ARE REMOTE R0'S VOCABULARY (core/permission-levels.json), never this file's. A
# descriptor maps every level to its harness's own flags, or says the harness cannot express it; the
# coverage rule is R0's Test-HordePermissionLevelCoverage, so a vocabulary that gains or loses a level
# fails every descriptor written against the old list.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Schema.ps1")
. (Join-Path $PSScriptRoot "HostPort.ps1")
. (Join-Path $PSScriptRoot "PermissionLevels.ps1")

# THE ONE DUPLICATE-KEY SCANNER is core/JsonText.ps1's Find-HordeJsonDuplicateKey (PR #65). Until it
# merged, core/Ownership.ps1 and core/PermissionLevels.ps1 each defined a scanner under that name, and
# whichever loaded last answered (review of PR #60, F5); test/test-function-names.ps1 now fails on any
# name defined twice. Its answer is still read without assuming its shape
# (Get-HordeJsonDuplicateKeyProblems).
. (Join-Path $PSScriptRoot "JsonText.ps1")

$script:HordeAgentCapabilityStates = @("yes", "no", "declined", "unverified")
$script:HordeCapabilityPorts = @("agent", "host", "either")
# A capability name: dotted or hyphenated words. The host port's names are dotted (text.send), the
# engines plan's are hyphenated (delivery-receipt) and one is both (session.remoteName); the plan's
# later steps quote these names, so they are kept as the plan wrote them.
$script:HordeCapabilityNamePattern = '^[a-z][a-zA-Z0-9]*([.-][a-z][a-zA-Z0-9]*)*$'
# The same flag test core/PermissionLevels.ps1 applies to a level's meaning (remote R0): a hyphen or
# two, or a slash, then a letter, with no letter or digit before it. A capability's meaning says what
# Horde gets, in Horde's words; how a harness spells it belongs in that harness's folder.
$script:HordeCapabilityFlagPattern = '(^|[^A-Za-z0-9])(--?|/)[A-Za-z]'

function Get-HordeAgentProp {
    # A property of a parsed object, or $null when it is not there. Looked up, never dereferenced, so a
    # missing field is one finding and not a strict-mode error that hides the rest.
    param($Object, [string]$Name)
    if ($Object -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    # -NoEnumerate: a plain return unrolls an empty list to nothing, and "protocols": [] would read
    # as a missing field instead of an empty one (measured on this suite, 2026-10-02).
    # Only a list needs it: pwsh 7.6 wraps even a lone string in a list under -NoEnumerate, so a scalar
    # is returned as it is (measured 2026-10-20, 7.6.7; 5.1 returns the string either way).
    if ($p.Value -is [System.Collections.IList]) { Write-Output -NoEnumerate $p.Value } else { $p.Value }
}

function Get-HordeJsonDuplicateKeyProblems {
    # The duplicate-key findings for a JSON text, as refusals. Relies only on what every scan of that
    # name shares: something non-null comes back for a repeat, and nothing when there is none. Each
    # non-null item is a refusal, whatever its type or text.
    param([string]$Text)
    return @(@(Find-HordeJsonDuplicateKey -Text $Text) | Where-Object { $null -ne $_ } | ForEach-Object { "a key appears twice in one object, and only the last would be read: " + $_ })
}

function Read-HordeCapabilityVocabularyText {
    # The capability vocabulary given as JSON text: rows { name; port; host; meaning }, in file order.
    # Throws, naming every problem, when it is not well formed.
    #
    # THE SHAPE IS CLOSED: an object with one key, capabilities, a non-empty list of rows, each with
    # exactly name, port, meaning and - only when a host can satisfy it - host. host must be a name
    # of the host port's own vocabulary ($script:HordeHostCapabilityNames), so that "either" points
    # at a capability a host adapter actually declares.
    param([Parameter(Mandatory = $true)][string]$Text)
    $problems = New-Object System.Collections.ArrayList
    foreach ($p in (Get-HordeJsonDuplicateKeyProblems -Text $Text)) { [void]$problems.Add($p) }
    $table = $null
    try { $table = $Text | ConvertFrom-Json } catch { throw ("the capability vocabulary is not JSON: " + $_.Exception.Message) }
    $rows = Get-HordeAgentProp $table "capabilities"
    if ($table -isnot [System.Management.Automation.PSCustomObject]) { [void]$problems.Add("the vocabulary must be an object with a capabilities key") }
    else { foreach ($k in @($table.PSObject.Properties | ForEach-Object { $_.Name })) { if ($k -cne "capabilities") { [void]$problems.Add("the vocabulary has an extra key '" + $k + "'") } } }
    if ($rows -isnot [System.Array] -or @($rows).Count -eq 0) { [void]$problems.Add("capabilities must be a non-empty list"); $rows = @() }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $out = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($row in @($rows)) {
        $i++
        $at = "capability " + $i
        if ($row -isnot [System.Management.Automation.PSCustomObject]) { [void]$problems.Add($at + " must be an object"); continue }
        foreach ($k in @($row.PSObject.Properties | ForEach-Object { $_.Name })) { if (@("name", "port", "host", "meaning") -cnotcontains $k) { [void]$problems.Add($at + " has an extra key '" + $k + "'") } }
        $name = Get-HordeAgentProp $row "name"
        $port = Get-HordeAgentProp $row "port"
        $hostName = Get-HordeAgentProp $row "host"
        $meaning = Get-HordeAgentProp $row "meaning"
        if ($name -isnot [string] -or $name -cnotmatch $script:HordeCapabilityNamePattern) { [void]$problems.Add($at + " has the name '" + $name + "', which is not a capability name") }
        elseif (-not $seen.Add($name)) { [void]$problems.Add("the capability '" + $name + "' is listed twice") }
        else { $at = "capability '" + $name + "'" }
        if ($port -isnot [string] -or $script:HordeCapabilityPorts -cnotcontains $port) { [void]$problems.Add($at + " has the port '" + $port + "'; it must be agent, host or either") }
        elseif ($port -ceq "agent") { if ($null -ne $hostName) { [void]$problems.Add($at + " is satisfied only by an agent, so it names no host capability") } }
        elseif ($hostName -isnot [string] -or $script:HordeHostCapabilityNames -cnotcontains $hostName) { [void]$problems.Add($at + " names the host capability '" + $hostName + "', which the host port does not have; one of " + ($script:HordeHostCapabilityNames -join ", ")) }
        if ($meaning -isnot [string] -or $meaning.Trim() -eq "") { [void]$problems.Add($at + " has no meaning") }
        elseif ($meaning -cmatch $script:HordeCapabilityFlagPattern) { [void]$problems.Add($at + "'s meaning spells a command-line flag; a harness's flags belong in its own agents folder") }
        [void]$out.Add([pscustomobject]@{ name = $name; port = $port; host = $hostName; meaning = $meaning })
    }
    if ($problems.Count -gt 0) { throw ("the capability vocabulary is malformed: " + ($problems -join "; ")) }
    return $out.ToArray()
}

function Get-HordeCapabilityVocabulary {
    # The vocabulary from core/capabilities.json, or from -Path.
    param([string]$Path = (Join-Path $PSScriptRoot "capabilities.json"))
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    Assert-HordeAsciiBytes -Bytes $bytes -What ("the capability vocabulary at '" + $Path + "'")
    return (Read-HordeCapabilityVocabularyText -Text ([System.Text.Encoding]::ASCII.GetString($bytes)))
}

function Test-HordeAgentDescriptorRules {
    # The rules a draft-07 schema cannot say, as problems. Runs on a value the schema has already
    # read; every field is looked up, so a shape the schema refused adds no strict-mode error here.
    param($Descriptor, [string]$ExpectedName, [object[]]$Vocabulary, [object[]]$Levels)
    $out = New-Object System.Collections.ArrayList
    $name = Get-HordeAgentProp $Descriptor "name"
    if ($ExpectedName -ne "" -and $name -is [string] -and $name -cne $ExpectedName) {
        [void]$out.Add("the descriptor names the harness '" + $name + "', but its folder is '" + $ExpectedName + "'; a descriptor describes the harness whose folder holds it")
    }
    $protocols = Get-HordeAgentProp $Descriptor "protocols"
    if ($protocols -is [System.Array]) {
        if (@($protocols).Count -eq 0) { [void]$out.Add("the descriptor names no protocol; a harness speaks at least one wire format") }
        $seenP = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        foreach ($p in @($protocols)) { if (-not $seenP.Add("$p")) { [void]$out.Add("the protocol '" + $p + "' is listed twice") } }
    }
    $pattern = Get-HordeAgentProp $Descriptor "sessionIdPattern"
    if ($pattern -is [string] -and $pattern.Trim() -ne "") {
        $compiled = $true
        try { $null = New-Object System.Text.RegularExpressions.Regex($pattern) } catch { $compiled = $false; [void]$out.Add("the sessionIdPattern does not compile: " + $_.Exception.InnerException.Message) }
        # Anchored at both ends, so a match is the whole id. \A or ^ first, \z or $ last; $ also
        # matches before a final newline, which an id from a file never ends with once read.
        $startsAnchored = ($pattern.StartsWith("^") -or $pattern.StartsWith("\A"))
        $endsAnchored = (($pattern.EndsWith("$") -and -not $pattern.EndsWith("\$")) -or $pattern.EndsWith("\z"))
        if ($compiled -and -not ($startsAnchored -and $endsAnchored)) { [void]$out.Add("the sessionIdPattern is not anchored at both ends (^ or \A first, $ or \z last), so it would accept any id that merely contains a match") }
    }
    $owned = Get-HordeAgentProp $Descriptor "ownedEnv"
    if ($owned -is [System.Array]) {
        $seenE = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($row in @($owned)) {
            $n = Get-HordeAgentProp $row "name"
            if ($n -is [string] -and -not $seenE.Add($n)) { [void]$out.Add("the owned variable '" + $n + "' is listed twice (environment names ignore case)") }
        }
    }
    $events = Get-HordeAgentProp $Descriptor "events"
    if ($events -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in @($events.PSObject.Properties)) {
            $support = Get-HordeAgentProp $p.Value "support"
            $hook = Get-HordeAgentProp $p.Value "hook"
            if ($support -ceq "no") {
                if ($null -ne $hook) { [void]$out.Add("the event " + $p.Name + " is one the harness lacks (no), so it names no hook") }
            } elseif ($support -is [string] -and $script:HordeAgentCapabilityStates -ccontains $support -and $hook -isnot [string]) {
                [void]$out.Add("the event " + $p.Name + " is " + $support + " but names no hook; say which of the harness's hooks reports it")
            }
        }
    }
    # The schema lists the capabilities; the vocabulary is the source. A name one has and the other
    # lacks is refused here as well, so neither can drift alone.
    $caps = Get-HordeAgentProp $Descriptor "capabilities"
    if ($caps -is [System.Management.Automation.PSCustomObject] -and $null -ne $Vocabulary) {
        $want = @($Vocabulary | Where-Object { $_.port -cne "host" } | ForEach-Object { $_.name })
        $have = @($caps.PSObject.Properties | ForEach-Object { $_.Name })
        foreach ($w in $want) { if ($have -cnotcontains $w) { [void]$out.Add("the capability " + $w + " of core/capabilities.json is not declared") } }
        foreach ($h in $have) { if ($want -cnotcontains $h) { [void]$out.Add("the capability " + $h + " is not one an agent can satisfy in core/capabilities.json") } }
    }
    # Each permission level once: a fragment with evidence, or a reason it is inexpressible.
    $rows = Get-HordeAgentProp $Descriptor "permissionLevels"
    if ($rows -is [System.Array] -and $null -ne $Levels) {
        foreach ($row in @($rows)) {
            $lvl = Get-HordeAgentProp $row "level"
            $argv = Get-HordeAgentProp $row "argv"
            $why = Get-HordeAgentProp $row "inexpressible"
            $ev = Get-HordeAgentProp $row "evidence"
            if ($null -ne $argv -and $null -ne $why) { [void]$out.Add("the permission level " + $lvl + " has both a fragment and a reason it cannot be expressed; it is one or the other") }
            elseif ($null -eq $argv -and $null -eq $why) { [void]$out.Add("the permission level " + $lvl + " has neither a fragment nor a reason it cannot be expressed") }
            elseif ($null -ne $argv) {
                if ($argv -is [System.Array] -and @($argv).Count -eq 0) { [void]$out.Add("the permission level " + $lvl + " has an empty fragment; a level a harness gives by default is still named by its flags, or it is inexpressible") }
                if ($null -eq $ev) { [void]$out.Add("the permission level " + $lvl + " has a fragment with no evidence that its flags were read off the harness's help") }
                # Review of PR #60: the flags alone did not decide the mode. Which start the fragment
                # is for, and what the started harness reported, are part of the mapping.
                $entries = Get-HordeAgentProp $row "entryPoints"
                if ($null -eq $entries -or ($entries -is [System.Array] -and @($entries).Count -eq 0)) { [void]$out.Add("the permission level " + $lvl + " does not say which entry point its fragment is for (interactive, headless)") }
                elseif ($entries -is [System.Array]) {
                    $seenEntry = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
                    foreach ($e in @($entries)) { if (-not $seenEntry.Add("$e")) { [void]$out.Add("the permission level " + $lvl + " lists the entry point " + $e + " twice") } }
                }
                if ($null -eq (Get-HordeAgentProp $row "readback")) { [void]$out.Add("the permission level " + $lvl + " has no readback: what the started harness reported as its mode under this fragment") }
            }
            elseif ($null -ne $ev) { [void]$out.Add("the permission level " + $lvl + " is inexpressible, so it carries a reason and no evidence of a flag") }
            if ($null -ne $why) {
                foreach ($k in @("entryPoints", "readback", "preconditions")) { if ($null -ne (Get-HordeAgentProp $row $k)) { [void]$out.Add("the permission level " + $lvl + " is inexpressible, so it has no " + $k) } }
            }
            $pre = Get-HordeAgentProp $row "preconditions"
            if ($pre -is [System.Array]) {
                $seenPre = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
                foreach ($c in @($pre)) { $cn = Get-HordeAgentProp $c "name"; if ($cn -is [string] -and -not $seenPre.Add($cn)) { [void]$out.Add("the permission level " + $lvl + " lists the precondition " + $cn + " twice") } }
            }
        }
        $cov = Test-HordePermissionLevelCoverage -Mapped @(@($rows) | ForEach-Object { Get-HordeAgentProp $_ "level" }) -Levels $Levels
        foreach ($m in @($cov.missing)) { [void]$out.Add("the permission level " + $m + " of core/permission-levels.json is not mapped") }
        foreach ($u in @($cov.unknown)) { [void]$out.Add("the permission level '" + $u + "' is not in core/permission-levels.json") }
        foreach ($t in @($cov.duplicate)) { [void]$out.Add("the permission level " + $t + " is mapped twice") }
    }
    return $out.ToArray()
}

function Read-HordeAgentDescriptorText {
    # A descriptor given as JSON text, checked whole. Returns the parsed descriptor; throws, naming
    # every problem, when it is not usable. -ExpectedName is the folder it came from ("" skips that
    # one rule, for a caller that has no folder).
    param([Parameter(Mandatory = $true)][string]$Text, [string]$ExpectedName = "", [string]$What = "the agent descriptor", $Vocabulary = $null, $Levels = $null)
    if ($null -eq $Vocabulary) { $Vocabulary = @(Get-HordeCapabilityVocabulary) }
    if ($null -eq $Levels) { $Levels = @(Get-HordePermissionLevels) }
    $problems = New-Object System.Collections.ArrayList
    foreach ($p in (Get-HordeJsonDuplicateKeyProblems -Text $Text)) { [void]$problems.Add($p) }
    $d = $null
    try { $d = $Text | ConvertFrom-Json } catch { throw ($What + " is not JSON: " + $_.Exception.Message) }
    foreach ($p in @(Test-HordeSchema -Value $d -Schema (Get-HordeSchema -Name "agent-descriptor.v1"))) { [void]$problems.Add($p) }
    foreach ($p in @(Test-HordeAgentDescriptorRules -Descriptor $d -ExpectedName $ExpectedName -Vocabulary $Vocabulary -Levels $Levels)) { [void]$problems.Add($p) }
    if ($problems.Count -gt 0) { throw ($What + " is not usable: " + ($problems -join "; ")) }
    return $d
}

function Read-HordeAgentDescriptor {
    # agents/<name>/agent.json from disk; the harness's name is the folder's.
    param([Parameter(Mandatory = $true)][string]$Path, $Vocabulary = $null, $Levels = $null)
    $folder = Split-Path -Leaf (Split-Path -Parent $Path)
    $what = "the agent descriptor of " + $folder
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    Assert-HordeAsciiBytes -Bytes $bytes -What $what
    return (Read-HordeAgentDescriptorText -Text ([System.Text.Encoding]::ASCII.GetString($bytes)) -ExpectedName $folder -What $what -Vocabulary $Vocabulary -Levels $Levels)
}

function Get-HordeAgentDescriptors {
    # Every harness's descriptor, by folder name, in name order, as a Horde answer. EVERY FOLDER UNDER
    # agents/ MUST HAVE ONE: a folder is a harness Horde knows of, and one with no descriptor is a
    # harness whose capabilities nobody declared. Any folder that fails makes the whole answer unknown,
    # naming every failure, rather than returning the ones that loaded - a caller choosing among
    # harnesses must not see a shorter list as the truth. No agents folder at all is ABSENT, never an
    # empty known list (review of PR #60, F6): "there are no harnesses" and "this is not a Horde tree"
    # are different answers.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $agents = Join-Path $Root "agents"
    $out = [ordered]@{}
    if (-not (Test-Path -LiteralPath $agents -PathType Container)) { return (New-HordeAbsent -Note ("there is no agents folder under " + $Root)) }
    $vocab = @(Get-HordeCapabilityVocabulary)
    $levelList = @(Get-HordePermissionLevels)
    $problems = New-Object System.Collections.ArrayList
    foreach ($dir in @(Get-ChildItem -LiteralPath $agents -Directory | Sort-Object Name)) {
        $file = Join-Path $dir.FullName "agent.json"
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { [void]$problems.Add("the harness folder " + $dir.Name + " has no agent.json"); continue }
        try { $out[$dir.Name] = Read-HordeAgentDescriptor -Path $file -Vocabulary $vocab -Levels $levelList } catch { [void]$problems.Add($_.Exception.Message) }
    }
    if ($problems.Count -gt 0) { return (New-HordeUnknown -Reason ("the agent descriptors are not all usable: " + ($problems -join " | "))) }
    return (New-HordeKnown -Value $out)
}

function Get-HordeAgentCapabilityRow {
    # The declared row of one capability, or a throw: asking about a capability the vocabulary does
    # not have is a mistake in the caller, not a fact about the harness.
    param($Descriptor, [string]$Name)
    $caps = Get-HordeAgentProp $Descriptor "capabilities"
    $row = Get-HordeAgentProp $caps $Name
    if ($null -eq $row) { throw ("'" + $Name + "' is not a capability this descriptor declares; ask for one in core/capabilities.json") }
    return $row
}

function Get-HordeAgentCapability {
    # One capability as a Horde answer: known $true for yes; known $false for no and for declined;
    # unknown for unverified, with the evidence as the reason. Callers that must not act on a guess -
    # naming a web session (engines group I), choosing a harness for a role (E4) - get "nobody has
    # measured this" as unknown, never as either answer.
    param([Parameter(Mandatory = $true)]$Descriptor, [Parameter(Mandatory = $true)][string]$Name)
    $row = Get-HordeAgentCapabilityRow -Descriptor $Descriptor -Name $Name
    $support = "$($row.support)"
    $who = "" + (Get-HordeAgentProp $Descriptor "name")
    if ($support -ceq "yes") { return (New-HordeKnown -Value $true) }
    if ($support -ceq "no" -or $support -ceq "declined") { return (New-HordeKnown -Value $false) }
    return (New-HordeUnknown -Reason ($Name + " is unverified for " + $who + ": " + $row.evidence))
}

function Test-HordeAgentCapability {
    # Does the harness satisfy a requirement for this capability? Only yes does. unverified counts as
    # no here, exactly as the host port's Test-HordeHostCapability counts it.
    param([Parameter(Mandatory = $true)]$Descriptor, [Parameter(Mandatory = $true)][string]$Name)
    $row = Get-HordeAgentCapabilityRow -Descriptor $Descriptor -Name $Name
    return [bool]("$($row.support)" -ceq "yes")
}

function Get-HordePermissionArgs {
    # The argv fragment that gives one permission level on this harness, as a Horde answer: known with
    # a fresh copy of the fragment, or unknown with the reason. Pure: the step R9's node takes before a
    # spawn, so a refusal here is a refused spawn.
    #
    # NEVER THE NEAREST LEVEL. A level the harness cannot express is refused with the descriptor's own
    # reason. It is not lowered to the next level down that the harness does have, because a silent
    # lowering is a policy change nobody asked for (engines E2, remote R9). A name that is not a level
    # - "Bypass" is not bypass - is refused by R0's Get-HordePermissionLevelRank.
    #
    # NOR WHERE IT DOES NOT HOLD (review of PR #60). A harness's real permission depends on its
    # environment as well as its flags: measured 2026-10-02, one harness turns its plan, edits and
    # bypass modes into its ask mode in a folder it does not trust, and another turns its edits mode
    # read-only without a sandbox setting. So a fragment names the preconditions it holds under, and
    # the caller passes -Verified, the names it has checked for this target. One not verified makes the
    # answer unknown, naming it and what happens without it: the caller refuses - neither lowers nor
    # raises. A fragment is also for named entry points only (one harness's headless command rejects
    # its interactive approval flag), and -EntryPoint is required, so no caller gets one by default.
    param([Parameter(Mandatory = $true)]$Descriptor, $Level,
        [Parameter(Mandatory = $true)][ValidateSet("interactive", "headless")][string]$EntryPoint,
        [string[]]$Verified = @(), $Levels = $null)
    if ($null -eq $Levels) { $Levels = @(Get-HordePermissionLevels) }
    $rank = Get-HordePermissionLevelRank -Name $Level -Levels $Levels
    if ($rank.state -cne "known") { return (New-HordeUnknown -Reason $rank.reason) }
    $who = "" + (Get-HordeAgentProp $Descriptor "name")
    # Assigned before it is listed: Get-HordeAgentProp emits a list as ONE object, so @(Get-HordeAgentProp ...)
    # would be a list holding the list.
    $rows = Get-HordeAgentProp $Descriptor "permissionLevels"
    $row = @(@($rows) | Where-Object { (Get-HordeAgentProp $_ "level") -ceq $Level })
    if ($row.Count -ne 1) { return (New-HordeUnknown -Reason ("the descriptor of " + $who + " does not map the permission level " + $Level + " exactly once")) }
    $why = Get-HordeAgentProp $row[0] "inexpressible"
    if ($null -ne $why) { return (New-HordeUnknown -Reason ($who + " cannot express the permission level " + $Level + ": " + $why + ". It is refused, never lowered to a level the harness has")) }
    $entries = Get-HordeAgentProp $row[0] "entryPoints"
    if (@($entries) -cnotcontains $EntryPoint) { return (New-HordeUnknown -Reason ("the " + $Level + " fragment of " + $who + " is for " + (@($entries) -join " and ") + " starts, not " + $EntryPoint)) }
    $pre = Get-HordeAgentProp $row[0] "preconditions"
    foreach ($c in @($pre)) {
        if ($null -eq $c) { continue }
        if (@($Verified) -cnotcontains "$($c.name)") { return (New-HordeUnknown -Reason ("the " + $Level + " fragment of " + $who + " holds only where " + $c.name + " is true, and that was not verified for this start: " + $c.evidence + ". It is refused, neither lowered nor raised")) }
    }
    $argv = Get-HordeAgentProp $row[0] "argv"
    return (New-HordeKnown -Value ([string[]]@(@($argv) | ForEach-Object { "$_" })))
}
