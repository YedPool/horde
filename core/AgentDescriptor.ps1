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
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). core/Ownership.ps1 is
# loaded for Find-HordeJsonDuplicateKey, the repository's one duplicate-key scan; it sets strict mode
# off for its caller, as it always has.
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Schema.ps1")
. (Join-Path $PSScriptRoot "HostPort.ps1")
. (Join-Path $PSScriptRoot "Ownership.ps1")

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
    Write-Output -NoEnumerate $p.Value
}

function Assert-HordeAsciiBytes {
    # Throw unless the bytes are plain ASCII with no byte-order mark. Checked before decoding: a
    # decoder turns a stray byte into a character, or a replacement mark, and either reads as text.
    param([byte[]]$Bytes, [string]$What)
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { throw ($What + " starts with a UTF-8 byte-order mark; save it as plain ASCII (CONTRIBUTING 13)") }
    foreach ($b in $Bytes) { if ($b -gt 0x7F) { throw ($What + " holds a byte that is not ASCII (CONTRIBUTING 13)") } }
}

function Get-HordeJsonDuplicateKeyProblems {
    # The duplicate-key findings for a JSON text, as refusals. Filtered to non-empty strings, so the
    # answer is the same whichever of the repository's duplicate-key scans is loaded: core/Ownership's
    # returns every finding, and remote R0's core/PermissionLevels one returns the first key or $null.
    param([string]$Text)
    return @(@(Find-HordeJsonDuplicateKey -Text $Text) | Where-Object { $_ -is [string] -and $_ -ne "" } | ForEach-Object { "a key appears twice in one object, and only the last would be read: " + $_ })
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
    param($Descriptor, [string]$ExpectedName, [object[]]$Vocabulary)
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
    return $out.ToArray()
}

function Read-HordeAgentDescriptorText {
    # A descriptor given as JSON text, checked whole. Returns the parsed descriptor; throws, naming
    # every problem, when it is not usable. -ExpectedName is the folder it came from ("" skips that
    # one rule, for a caller that has no folder).
    param([Parameter(Mandatory = $true)][string]$Text, [string]$ExpectedName = "", [string]$What = "the agent descriptor", $Vocabulary = $null)
    if ($null -eq $Vocabulary) { $Vocabulary = @(Get-HordeCapabilityVocabulary) }
    $problems = New-Object System.Collections.ArrayList
    foreach ($p in (Get-HordeJsonDuplicateKeyProblems -Text $Text)) { [void]$problems.Add($p) }
    $d = $null
    try { $d = $Text | ConvertFrom-Json } catch { throw ($What + " is not JSON: " + $_.Exception.Message) }
    foreach ($p in @(Test-HordeSchema -Value $d -Schema (Get-HordeSchema -Name "agent-descriptor.v1"))) { [void]$problems.Add($p) }
    foreach ($p in @(Test-HordeAgentDescriptorRules -Descriptor $d -ExpectedName $ExpectedName -Vocabulary $Vocabulary)) { [void]$problems.Add($p) }
    if ($problems.Count -gt 0) { throw ($What + " is not usable: " + ($problems -join "; ")) }
    return $d
}

function Read-HordeAgentDescriptor {
    # agents/<name>/agent.json from disk; the harness's name is the folder's.
    param([Parameter(Mandatory = $true)][string]$Path, $Vocabulary = $null)
    $folder = Split-Path -Leaf (Split-Path -Parent $Path)
    $what = "the agent descriptor of " + $folder
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    Assert-HordeAsciiBytes -Bytes $bytes -What $what
    return (Read-HordeAgentDescriptorText -Text ([System.Text.Encoding]::ASCII.GetString($bytes)) -ExpectedName $folder -What $what -Vocabulary $Vocabulary)
}

function Get-HordeAgentDescriptors {
    # Every harness's descriptor, by folder name, in name order. EVERY FOLDER UNDER agents/ MUST HAVE
    # ONE: a folder is a harness Horde knows of, and one with no descriptor is a harness whose
    # capabilities nobody declared. Throws, naming every folder that fails, rather than returning the
    # ones that loaded - a caller choosing among harnesses must not see a shorter list as the truth.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $agents = Join-Path $Root "agents"
    $out = [ordered]@{}
    if (-not (Test-Path -LiteralPath $agents -PathType Container)) { return $out }
    $vocab = @(Get-HordeCapabilityVocabulary)
    $problems = New-Object System.Collections.ArrayList
    foreach ($dir in @(Get-ChildItem -LiteralPath $agents -Directory | Sort-Object Name)) {
        $file = Join-Path $dir.FullName "agent.json"
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { [void]$problems.Add("the harness folder " + $dir.Name + " has no agent.json"); continue }
        try { $out[$dir.Name] = Read-HordeAgentDescriptor -Path $file -Vocabulary $vocab } catch { [void]$problems.Add($_.Exception.Message) }
    }
    if ($problems.Count -gt 0) { throw ("the agent descriptors are not all usable: " + ($problems -join " | ")) }
    return $out
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
