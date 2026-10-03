# THE LINK WALK'S REFERENCE: remote/Contract.ps1 and remote/Protocol.ps1 as they were on main at
# 27aaf30, before fix/link-writer-speed, copied whole and renamed with "Reference" so they load beside
# the code that replaced them. test/test-link-walk.ps1 runs both on the same inputs and requires the
# same answer: the same findings in the same order, the same text, the same refusal. Never edited
# except to freeze more of the old code as more of it is replaced: a change to what is here would let
# the new code drift with nothing to show it.
#
# From remote/Contract.ps1: Get-HordeLinkNodesReference, Test-HordeLinkValueReference,
# Test-HordeLinkFrameReference and Test-HordeLinkAnswerReference. From remote/Protocol.ps1:
# Test-HordeProtocolLimitsReference and ConvertTo-HordeWireTextReference. Everything they call that
# was not replaced is the shipped code itself.

function Get-HordeLinkNodesReference {
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
        foreach ($p in (Get-HordeLinkPairs $Value)) {
            $child = Get-HordeLinkProp $props $p.Name
            if ($null -ne $child) { foreach ($x in @(Get-HordeLinkNodesReference -Value $p.Value -Node $child -Root $Root -Path ($Path + "." + $p.Name))) { [void]$out.Add($x) } }
        }
    }
    $items = Get-HordeLinkProp $n "items"
    if ($Value -is [System.Collections.IList] -and $null -ne $items) {
        $i = 0
        foreach ($item in $Value) { foreach ($x in @(Get-HordeLinkNodesReference -Value $item -Node $items -Root $Root -Path ($Path + "[" + $i + "]"))) { [void]$out.Add($x) }; $i++ }
    }
    return @($out)
}

function Test-HordeLinkValueReference {
    # A value against a schema (Schema is what Test-HordeSchema takes; Node and Root are the same schema
    # for the walk), then core/tristate's rules on every answer inside it.
    param($Value, $Schema, $Node, $Root, [string]$Path)
    $found = @(Test-HordeSchema -Value $Value -Schema $Schema -Path $Path)
    if ($found.Count -gt 0) { return $found }
    $out = New-Object System.Collections.ArrayList
    foreach ($x in @(Get-HordeLinkNodesReference -Value $Value -Node $Node -Root $Root -Path $Path)) {
        if ((Test-HordeLinkIsAnswerNode $x.node) -and ($x.value -is [System.Management.Automation.PSCustomObject] -or $x.value -is [System.Collections.IDictionary])) {
            foreach ($f in @(Test-HordeLinkAnswerReference -Answer $x.value -Path $x.path)) { [void]$out.Add($f) }
        }
    }
    return @($out)
}

function Test-HordeLinkFrameReference {
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
        $a = Resolve-HordeLinkTarget -Doc $Contract.verbs -Target "$($row.args)"
        return @(Test-HordeLinkValueReference -Value $Frame.args -Schema $a.schema -Node $a.node -Root $a.root -Path '$.args')
    }
    if ($members -ccontains "result") {
        $answer = $Frame.result
        $found = @(Test-HordeLinkAnswerReference -Answer $answer -Path '$.result')
        if ($found.Count -gt 0) { return $found }
        if ("$($answer.state)" -ceq "known") {
            $r = Resolve-HordeLinkTarget -Doc $Contract.verbs -Target "$($row.result)"
            return @(Test-HordeLinkValueReference -Value $answer.value -Schema $r.schema -Node $r.node -Root $r.root -Path '$.result.value')
        }
    }
    return @()
}

function Test-HordeProtocolLimitsReference {
    # Every per-field cap of x-horde-limits, on a frame that remote/Contract.ps1 has already passed:
    # each string against the cap its schema names, measured as it is on the wire, and each array
    # against listItems. The envelope, the verb's arguments and a known result's value are each walked
    # with their own schema. Returns findings; empty means every field is within its cap.
    param($Frame, $Contract = $null)
    if ($null -eq $Contract) { $Contract = Get-HordeLinkContract }
    $walks = New-Object System.Collections.ArrayList
    [void]$walks.Add(@($Frame, $Contract.frame, $Contract.frame, '$'))
    $verb = Get-HordeLinkProp $Frame "verb"
    $row = $null
    if ($null -ne $verb -and $Contract.rows.ContainsKey("$verb")) { $row = $Contract.rows["$verb"] }
    if ($null -ne $row -and (Test-HordeLinkHasProp $Frame "args")) {
        $t = Resolve-HordeLinkTarget -Doc $Contract.verbs -Target "$($row.args)"
        [void]$walks.Add(@((Get-HordeLinkProp $Frame "args"), $t.node, $t.root, '$.args'))
    }
    $result = Get-HordeLinkProp $Frame "result"
    if ($null -ne $row -and $null -ne $result -and "$(Get-HordeLinkProp $result 'state')" -ceq "known") {
        $t = Resolve-HordeLinkTarget -Doc $Contract.verbs -Target "$($row.result)"
        [void]$walks.Add(@((Get-HordeLinkProp $result "value"), $t.node, $t.root, '$.result.value'))
    }
    $out = New-Object System.Collections.ArrayList
    # A HELLO'S VERSION LISTS are bounded tighter than any list: at most versionItems entries, none above
    # versionMax (review of PR #45). listItems (256) let a hello offer 256 versions, whose bye named all
    # of them in a reason over its cap, and nothing bounded a version's size.
    $hello = Get-HordeLinkProp $Frame "hello"
    if ($null -ne $hello) {
        foreach ($k in @("versionMax", "versionItems")) { if (-not $Contract.limits.ContainsKey($k)) { [void]$out.Add("x-horde-limits has no " + $k + ", so a hello's versions cannot be bounded") } }
        if ($out.Count -gt 0) { return @($out) }
        foreach ($list in @("protocols", "verbsVersions")) {
            $items = @(Get-HordeLinkProp $hello $list)
            if ($items.Count -gt $Contract.limits["versionItems"]) { [void]$out.Add('$.hello.' + $list + " has " + $items.Count + " versions, over the versionItems cap of " + $Contract.limits["versionItems"]) }
            foreach ($x in $items) {
                if (($x -is [int] -or $x -is [long]) -and [long]$x -gt [long]$Contract.limits["versionMax"]) { [void]$out.Add('$.hello.' + $list + " offers version " + $x + ", over the versionMax cap of " + $Contract.limits["versionMax"]) }
            }
        }
    }
    foreach ($w in $walks) {
        foreach ($x in @(Get-HordeLinkNodesReference -Value $w[0] -Node $w[1] -Root $w[2] -Path $w[3])) {
            $cap = Get-HordeLinkProp $x.node "x-horde-cap"
            if ($x.value -is [string]) {
                if ($null -eq $cap) {
                    if ($null -eq (Get-HordeLinkProp $x.node "enum")) { [void]$out.Add($x.path + " is a string whose schema names no cap") }
                    continue
                }
                $limit = $Contract.limits["$cap"]
                $size = Measure-HordeWireString $x.value
                if ($size -gt $limit) { [void]$out.Add($x.path + " is " + $size + " bytes on the wire, over its " + $cap + " cap of " + $limit) }
            } elseif ($x.value -is [System.Collections.IList]) {
                $limit = $Contract.limits["listItems"]
                if ($x.value.Count -gt $limit) { [void]$out.Add($x.path + " has " + $x.value.Count + " items, over the listItems cap of " + $limit) }
            }
        }
    }
    return @($out)
}

function ConvertTo-HordeWireTextReference {
    # A value as JSON text in the one spelling the link uses: keys in ordinal order, whole numbers only,
    # no whitespace. Refused, by throwing: a [datetime] (times cross as ISO text, schema/link-frame.v1),
    # a fractional type ([decimal], [double], [single]), a key that is not a string, anything nested
    # deeper than 64, and any other type.
    param($Value, [int]$Depth = 0)
    if ($Depth -gt $script:HordeWireMaxDepth) { throw ("a value nested more than " + $script:HordeWireMaxDepth + " deep cannot cross the link") }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($null -eq $Value) { return "null" }
    if ($Value -is [string]) { return (ConvertTo-HordeWireString $Value) }
    if ($Value -is [bool]) { if ($Value) { return "true" } else { return "false" } }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64]) {
        return $Value.ToString($inv)
    }
    if ($Value -is [decimal] -or $Value -is [double] -or $Value -is [single]) {
        throw ("a number on the link is a whole number, written as one; " + $Value.ToString($inv) + " (a " + $Value.PSObject.TypeNames[0] + ") is not, and 1.0 would be a second spelling of 1")
    }
    if ($Value -is [datetime]) { throw "a [datetime] does not cross the link; write it as ISO 8601 text in UTC" }
    $parts = New-Object System.Collections.ArrayList
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($k in @($Value.Keys)) { if ($k -isnot [string]) { throw ("an object key must be a string, not " + $k.PSObject.TypeNames[0]) } }
        $keys = [string[]]@($Value.Keys)
        [Array]::Sort($keys, [System.StringComparer]::Ordinal)
        foreach ($k in $keys) {
            [void]$parts.Add((ConvertTo-HordeWireString $k) + ":" + (ConvertTo-HordeWireTextReference -Value $Value[$k] -Depth ($Depth + 1)))
        }
        return ("{" + ($parts -join ",") + "}")
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        # A loop, not the pipeline: this runs for every object of every frame, the fuzz section's
        # thousands included.
        $props = @{}
        $names = New-Object System.Collections.Generic.List[string]
        foreach ($p in @($Value.PSObject.Properties)) { $props[$p.Name] = $p.Value; $names.Add($p.Name) }
        $keys = $names.ToArray()
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        foreach ($k in $keys) {
            [void]$parts.Add((ConvertTo-HordeWireString $k) + ":" + (ConvertTo-HordeWireTextReference -Value $props[$k] -Depth ($Depth + 1)))
        }
        return ("{" + ($parts -join ",") + "}")
    }
    if ($Value -is [System.Collections.IList]) {
        foreach ($item in $Value) { [void]$parts.Add((ConvertTo-HordeWireTextReference -Value $item -Depth ($Depth + 1))) }
        return ("[" + ($parts -join ",") + "]")
    }
    throw ("a " + $Value.PSObject.TypeNames[0] + " cannot cross the link")
}

function Test-HordeLinkAnswerReference {
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
