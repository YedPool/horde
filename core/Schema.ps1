# core/Schema.ps1 - check a parsed JSON value against a Horde schema.
#
# Horde's schemas (schema/*.json) are written as standard JSON Schema (draft-07), so the Lua plugin
# and anything else can read them too. Windows PowerShell 5.1 has no JSON Schema validator, so this
# file implements THE SUBSET HORDE'S SCHEMAS USE, and refuses a schema that uses anything else rather
# than silently skipping a rule it does not understand:
#
#   type (object, array, string, integer, number, boolean, null), required, properties,
#   additionalProperties (true or false), items, enum, pattern, minimum, definitions, $ref
#
# minimum is draft-07's, inclusive, and applies to numbers only: a value that is not a number is the
# type keyword's to refuse. It is compared EXACTLY, whatever .NET type holds either side (see
# Compare-HordeSchemaNumber), because 5.1's ConvertFrom-Json reads 0.99999999999999999999 as a
# Decimal that is 1 as a Double. It exists so schema/session-record.v1 can say labelCycle >= 0.
#
# $ref IS LOCAL ONLY, "#/definitions/<name>", resolved against the top of the schema being checked.
# It exists so a recursive shape - the layout tree of schema/restore-plan.v1 - can be described. A
# $ref to another document, to any other part of this one, or to a definition that is not there is
# refused (thrown), exactly as an unknown keyword is: fetching or skipping it would change what
# "valid" means without saying so. Also refused: a validation keyword beside a $ref, which draft-07
# IGNORES, so a reader would believe a rule that no conforming validator applies; definitions
# anywhere but the top, where "#/definitions/" would never find them; and a chain of $refs that
# comes back to itself without reaching a value, which would otherwise recurse until the call stack
# overflows.
# A $ref that is not a string - an array holding a pointer, say - is refused too, never converted.
#
# EVERY DEFINITION IS CHECKED ONCE, when Test-HordeSchema is called on the top of a schema, whether or
# not anything refers to it: an unknown keyword, a node that is not an object, or a $ref that does
# not resolve is refused there, not on the day a value first reaches it. definitions and properties
# that are not objects are refused as well.
#
# HOW DEEP A VALUE CAN BE. Measured 2026-09-30 on Windows PowerShell 5.1.26100.9444, by bisection, on
# this file as of this comment:
#   - ConvertFrom-Json stops first, for anything read from a file. Its RecursionLimit refuses JSON
#     nested more than 102 deep (103 nested arrays throw "RecursionLimit exceeded"). A restore plan's
#     tab root is its 9th level of nesting and each layout container adds 2, so a plan FILE parses
#     with a root 46 containers deep (deepest leaf at level 101) and not 47 (level 103).
#   - A value built in PowerShell never meets that limit, and the call stack is what stops it:
#     Test-HordeSchema throws "call depth overflow" on a layout tree 127 containers deep checked
#     against restore-plan.v1's node definition (126 passes), Test-HordeRestorePlan on a whole plan
#     built so at 125 (124 returns), and on plain nested properties with no $ref at 383 levels (382
#     pass). The same layout tree, measured on this file before 2026-09-30's changes, failed at 110.
#   A value past either limit is a thrown error, never a wrong finding.
#
# Keys starting "x-", and $schema, $id, title and description, are documentation and are ignored.
#
# Returns a list of findings, each naming the path it is about ("$.session_id"). Empty means valid.

$script:HordeSchemaKeywords = @("type", "required", "properties", "additionalProperties", "items", "enum", "pattern", "minimum",
                                 '$schema', '$id', "title", "description", "definitions", '$ref')
$script:HordeSchemaTypes = @("object", "array", "string", "integer", "number", "boolean", "null")
# The keywords that may sit beside a $ref: they say nothing about the value.
$script:HordeSchemaInertKeywords = @('$schema', '$id', "title", "description", "definitions")

function Test-HordeSchemaType {
    param($Value, [string]$Type)
    switch ($Type) {
        "object"  { return ($Value -is [System.Management.Automation.PSCustomObject] -or $Value -is [System.Collections.IDictionary]) }
        # A value built in PowerShell may hold a list as an ArrayList or other IList, not an array.
        "array"   { return ($Value -is [System.Collections.IList]) }
        "string"  { return ($Value -is [string]) }
        "boolean" { return ($Value -is [bool]) }
        "null"    { return ($null -eq $Value) }
        "integer" {
            if ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte]) { return $true }
            # JSON Schema calls any number with no fractional part an integer. MEASURED 2026-09-29, 5.1
            # ConvertFrom-Json: 1.0 gives Decimal, 1e3 gives Double, a number beyond Int64 gives Decimal.
            if ($Value -is [decimal]) { return ($Value -eq [decimal]::Truncate($Value)) }
            if ($Value -is [double] -or $Value -is [single]) {
                $d = [double]$Value
                return ((-not [double]::IsNaN($d)) -and (-not [double]::IsInfinity($d)) -and $d -eq [Math]::Truncate($d))
            }
            return $false
        }
        "number"  { return ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] -or $Value -is [single]) }
    }
    throw ("the schema names a type this validator does not know: '" + $Type + "'")
}

function Test-HordeSchemaIsNumber {
    # Every .NET type a number reaches the validator as: ConvertFrom-Json gives Int32, Int64, Decimal or
    # Double, and a value built in PowerShell may hold Int16, Byte or Single ("type": "integer" already
    # accepts Int16 and Byte). Never a string or a boolean.
    param($Value)
    return ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte] -or
            $Value -is [double] -or $Value -is [single] -or $Value -is [decimal])
}

function ConvertTo-HordeSchemaFraction {
    # A finite number as the exact fraction it holds, numerator over a positive denominator, both
    # BigInteger. A Decimal's invariant text is exact (it has no exponent form); a Double is its
    # mantissa times a power of two, read from its bits, so 0.1 as a Double is
    # 3602879701896397 / 36028797018963968, slightly more than one tenth.
    param($N)
    $one = [System.Numerics.BigInteger]::One
    if ($N -is [decimal]) {
        $text = $N.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $point = $text.IndexOf('.')
        $scale = 0
        if ($point -ge 0) { $scale = $text.Length - $point - 1; $text = $text.Remove($point, 1) }
        return @([System.Numerics.BigInteger]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture), [System.Numerics.BigInteger]::Pow(10, $scale))
    }
    if ($N -is [double] -or $N -is [single]) {
        # IEEE 754 binary64: 1 sign bit, 11 exponent bits (bias 1023), 52 mantissa bits with an implied
        # leading 1 unless the exponent field is 0. [double] of a Single is exact.
        $bits = [BitConverter]::DoubleToInt64Bits([double]$N)
        $expField = [int](($bits -shr 52) -band 0x7FF)
        $mantissa = [System.Numerics.BigInteger]($bits -band 0xFFFFFFFFFFFFF)
        if ($expField -eq 0) { $exp = -1074 } else { $mantissa = [System.Numerics.BigInteger]::Add($mantissa, [System.Numerics.BigInteger]::Pow(2, 52)); $exp = $expField - 1075 }
        if ($bits -lt 0) { $mantissa = [System.Numerics.BigInteger]::Negate($mantissa) }
        if ($exp -ge 0) { return @([System.Numerics.BigInteger]::Multiply($mantissa, [System.Numerics.BigInteger]::Pow(2, $exp)), $one) }
        return @($mantissa, [System.Numerics.BigInteger]::Pow(2, -$exp))
    }
    return @([System.Numerics.BigInteger][long]$N, $one)
}

function Compare-HordeSchemaNumber {
    # -1, 0 or 1 as A is below, equal to or above B, EXACTLY. Neither may be NaN. Comparing through
    # [double] called the Decimal 0.99999999999999999999 equal to 1; comparing through [decimal]
    # throws past Decimal's range (1e30 - the enum's lesson, second review of PR #16) and rounds a
    # Double to 15 significant digits. As exact fractions, neither happens. An infinity is above or
    # below every finite number, and equal only to itself.
    param($A, $B)
    $aInf = (($A -is [double] -or $A -is [single]) -and [double]::IsInfinity([double]$A))
    $bInf = (($B -is [double] -or $B -is [single]) -and [double]::IsInfinity([double]$B))
    if ($aInf -or $bInf) {
        $ad = 0.0; $bd = 0.0
        if ($aInf) { $ad = [double]$A } elseif ($A -lt 0) { $ad = -1.0 } elseif ($A -gt 0) { $ad = 1.0 }
        if ($bInf) { $bd = [double]$B } elseif ($B -lt 0) { $bd = -1.0 } elseif ($B -gt 0) { $bd = 1.0 }
        if ($aInf -and -not $bInf) { if ($ad -gt 0) { return 1 } else { return -1 } }
        if ($bInf -and -not $aInf) { if ($bd -gt 0) { return -1 } else { return 1 } }
        return $ad.CompareTo($bd)
    }
    $fa = ConvertTo-HordeSchemaFraction $A
    $fb = ConvertTo-HordeSchemaFraction $B
    return [System.Numerics.BigInteger]::Compare([System.Numerics.BigInteger]::Multiply($fa[0], $fb[1]), [System.Numerics.BigInteger]::Multiply($fb[0], $fa[1]))
}

function Get-HordeSchemaProps {
    # A schema node's keywords as name/value pairs, whether the schema was parsed from JSON or built
    # as a hashtable.
    param($Node)
    if ($Node -is [System.Collections.IDictionary]) { return @($Node.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Name = "$($_.Key)"; Value = $_.Value } }) }
    return @($Node.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } })
}

function Get-HordeObjectProps {
    param($Value)
    if ($Value -is [System.Collections.IDictionary]) { return @($Value.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Name = "$($_.Key)"; Value = $_.Value } }) }
    return @($Value.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } })
}

function ConvertTo-HordeSchemaPattern {
    # A JSON Schema pattern is an ECMA-262 regular expression; .NET's dialect differs where it matters
    # here. .NET's $ also matches just before a final newline, so "<uuid>`n" matched the session_id
    # pattern (review of PR #15; measured on 5.1: [regex]::IsMatch("ab`n", '^ab$') is True). An
    # unescaped $ outside a character class is rewritten to \z, end of input only. The caller also
    # passes RegexOptions.ECMAScript, which makes \d and \w ASCII-only as ECMA-262 has them.
    param([string]$Pattern)
    $sb = New-Object System.Text.StringBuilder
    $inClass = $false
    for ($i = 0; $i -lt $Pattern.Length; $i++) {
        $c = $Pattern[$i]
        if ($c -ceq '\') {
            [void]$sb.Append($c)
            if ($i + 1 -lt $Pattern.Length) { $i++; [void]$sb.Append($Pattern[$i]) }
            continue
        }
        if ($inClass) { if ($c -ceq ']') { $inClass = $false } }
        elseif ($c -ceq '[') { $inClass = $true }
        elseif ($c -ceq '$') { [void]$sb.Append('\z'); continue }
        [void]$sb.Append($c)
    }
    return $sb.ToString()
}

function Resolve-HordeSchemaRef {
    # The definition a local $ref names, from the top of the schema.
    param([string]$Ref, $Root)
    $m = [regex]::Match($Ref, '\A#/definitions/([A-Za-z0-9_-]+)\z')
    if (-not $m.Success) { throw ("the schema's `$ref '" + $Ref + "' is not one this validator follows: only local ones, #/definitions/<name>") }
    $name = $m.Groups[1].Value
    foreach ($p in (Get-HordeSchemaProps $Root)) {
        if ($p.Name -cne "definitions") { continue }
        foreach ($d in (Get-HordeSchemaProps $p.Value)) { if ($d.Name -ceq $name) { return $d.Value } }
    }
    throw ("the schema's `$ref '" + $Ref + "' names no definition")
}

function Get-HordeSchemaNodeKeywords {
    # One schema node's keywords, after refusing everything about the node itself that this validator
    # cannot honour. Nothing here looks at a value, so the same checks serve Test-HordeSchema, which
    # then applies the keywords to one, and Assert-HordeSchemaNode, which checks definitions that no
    # value may ever reach.
    param($Schema, [string]$Path, [bool]$AtTop)
    # A schema node that is not an object is refused. Draft-07 allows true and false as schemas, and
    # read as an object they have no keywords, so the first version accepted everything for both
    # (review of PR #15). This covers a definition a $ref reaches, too.
    if (-not ($Schema -is [System.Management.Automation.PSCustomObject] -or $Schema -is [System.Collections.IDictionary])) {
        throw ("the schema at " + $Path + " is not an object; boolean and other schemas are not implemented")
    }
    $kw = @{}
    foreach ($p in (Get-HordeSchemaProps $Schema)) {
        if ($p.Name -like "x-*") { continue }
        if ($script:HordeSchemaKeywords -cnotcontains $p.Name) { throw ("the schema uses '" + $p.Name + "' at " + $Path + ", which this validator does not implement") }
        $kw[$p.Name] = $p.Value
    }
    # additionalProperties may also be a schema in draft-07; that is not implemented, and 0 or "false"
    # must not be read as false either. Only a real boolean is accepted.
    if ($kw.ContainsKey("additionalProperties") -and $kw["additionalProperties"] -isnot [bool]) {
        throw ("additionalProperties at " + $Path + " must be true or false; a schema there is not implemented")
    }
    # ENUM HOLDS STRINGS, WHOLE NUMBERS AND BOOLEANS ONLY, checked before the value is looked at so a bad
    # schema is refused whatever the value. The first version compared other values as text: a null
    # threw, 1 and 1.0 differed, and objects matched by their string form (review of PR #15). A string
    # matches only an identical string; a boolean only the same boolean (never "true" or 1); a whole
    # number a value that is an integer (as "type": "integer" reads it) of equal value, so 1 and 1.0 are
    # the same and "1" is not. Whole numbers pin schemaVersion to 1 in every Horde record; a boolean
    # pins the restore plan's layout to advisory.
    if ($kw.ContainsKey("enum")) {
        foreach ($e in @($kw["enum"])) {
            $isWhole = ($e -is [int] -or $e -is [long])
            if ($e -isnot [string] -and $e -isnot [bool] -and -not $isWhole) { throw ("enum at " + $Path + " may hold only strings, whole numbers and booleans; '" + $e + "' is none of them") }
        }
    }
    # minimum IS A FINITE NUMBER, never a string, a boolean or null. PowerShell compares "0" or $true
    # with a number by converting it, so a bad minimum would work, wrongly, instead of failing.
    if ($kw.ContainsKey("minimum")) {
        $m = $kw["minimum"]
        $finite = ((Test-HordeSchemaIsNumber $m) -and -not (($m -is [double] -or $m -is [single]) -and ([double]::IsNaN([double]$m) -or [double]::IsInfinity([double]$m))))
        if (-not $finite) { throw ("minimum at " + $Path + " must be a number; '" + $m + "' is not one") }
    }
    # A TYPE NAME IS CHECKED HERE as well as when a value meets it, so a definition nothing refers to
    # cannot carry one this validator does not know.
    if ($kw.ContainsKey("type") -and $script:HordeSchemaTypes -cnotcontains "$($kw['type'])") {
        throw ("the schema names a type this validator does not know: '" + $kw["type"] + "'")
    }
    # properties AND definitions ARE OBJECTS. Read as one, an array or a string has .NET properties
    # (Length, Rank) instead of keys, so "properties": ["a"] checked nothing and passed every value.
    if ($kw.ContainsKey("properties") -and -not (Test-HordeSchemaType -Value $kw["properties"] -Type "object")) {
        throw ("properties at " + $Path + " must be an object")
    }
    if ($kw.ContainsKey("definitions") -and -not $atTop) { throw ("the schema has definitions below the top of a schema, at " + $Path + "; #/definitions/ would never find them") }
    if ($kw.ContainsKey("definitions") -and -not (Test-HordeSchemaType -Value $kw["definitions"] -Type "object")) {
        throw ("definitions at " + $Path + " must be an object, one schema per name")
    }
    if ($kw.ContainsKey('$ref')) {
        $beside = @($kw.Keys | Where-Object { $_ -cne '$ref' -and $script:HordeSchemaInertKeywords -cnotcontains $_ })
        if ($beside.Count -gt 0) { throw ("the schema has " + ($beside -join ", ") + " beside a `$ref at " + $Path + ", which draft-07 ignores") }
        # A $ref IS A STRING OR IT IS REFUSED. Read as "$($kw['$ref'])", an array holding one pointer
        # became that pointer's text and was followed (review of PR #17): a schema no draft-07 validator
        # accepts was given a meaning. Nothing is converted, so nothing is guessed.
        if ($kw['$ref'] -isnot [string]) { throw ("the schema's `$ref at " + $Path + " is not a string") }
    }
    return $kw
}

function Assert-HordeSchemaDefinitions {
    # EVERY DEFINITION IS CHECKED ONCE, whether or not anything refers to it. Before, a definition was
    # read only when a $ref reached it (review of PR #17), so an unknown keyword, a node that is not an
    # object or a dangling $ref could sit in a schema file until the day something referred to it -
    # and then fail a caller that had changed nothing. Test-HordeSchema calls this at the top of a
    # schema, before any value is looked at.
    param($Root)
    foreach ($p in (Get-HordeSchemaProps $Root)) {
        if ($p.Name -cne "definitions") { continue }
        foreach ($d in (Get-HordeSchemaProps $p.Value)) { Assert-HordeSchemaNode -Schema $d.Value -Path ("#/definitions/" + $d.Name) -Root $Root }
    }
}

function Assert-HordeSchemaNode {
    # A schema node and every node inside it, checked with no value: whatever Test-HordeSchema would
    # refuse on reaching the node is refused here. A $ref is resolved, never followed into its
    # definition, which is checked on its own; so a recursive definition is walked once, and the walk
    # ends. Path is a JSON pointer into the schema, "#/definitions/node/properties/children/items".
    param($Schema, [string]$Path, $Root)
    $kw = Get-HordeSchemaNodeKeywords -Schema $Schema -Path $Path -AtTop $false
    if ($kw.ContainsKey('$ref')) {
        # A chain of bare $refs that comes back to itself would make Test-HordeSchema throw on the
        # first value to reach it, so it is refused now, as that throw would say.
        $chain = @()
        $ref = $kw['$ref']
        while ($true) {
            if ($chain -ccontains $ref) { throw ("the schema's `$ref chain at " + $Path + " is circular: it comes back to '" + $ref + "' without reaching a value") }
            $chain += $ref
            $target = Resolve-HordeSchemaRef -Ref $ref -Root $Root
            $targetKw = Get-HordeSchemaNodeKeywords -Schema $target -Path $ref -AtTop $false
            if (-not $targetKw.ContainsKey('$ref')) { break }
            $ref = $targetKw['$ref']
        }
        return
    }
    if ($kw.ContainsKey("properties")) {
        foreach ($p in (Get-HordeSchemaProps $kw["properties"])) { Assert-HordeSchemaNode -Schema $p.Value -Path ($Path + "/properties/" + $p.Name) -Root $Root }
    }
    if ($kw.ContainsKey("items")) { Assert-HordeSchemaNode -Schema $kw["items"] -Path ($Path + "/items") -Root $Root }
}

function Test-HordeSchema {
    # Root and RefsHere are for the validator's own recursion; a caller passes Value and Schema.
    param($Value, $Schema, [string]$Path = '$', $Root = $null, [string[]]$RefsHere = @())
    $findings = New-Object System.Collections.ArrayList
    $atTop = ($null -eq $Root)
    $kw = Get-HordeSchemaNodeKeywords -Schema $Schema -Path $Path -AtTop $atTop
    if ($atTop) {
        $Root = $Schema
        Assert-HordeSchemaDefinitions -Root $Root
    }
    if ($kw.ContainsKey('$ref')) {
        $ref = $kw['$ref']
        if ($RefsHere -ccontains $ref) { throw ("the schema's `$ref chain at " + $Path + " is circular: it comes back to '" + $ref + "' without reaching a value") }
        $target = Resolve-HordeSchemaRef -Ref $ref -Root $Root
        return @(Test-HordeSchema -Value $Value -Schema $target -Path $Path -Root $Root -RefsHere (@($RefsHere) + $ref))
    }
    if ($kw.ContainsKey("type")) {
        if (-not (Test-HordeSchemaType -Value $Value -Type "$($kw['type'])")) {
            [void]$findings.Add($Path + " should be " + $kw["type"])
            return @($findings)
        }
    }
    if ($kw.ContainsKey("enum")) {
    # A WHOLE-NUMBER MEMBER IS AN Int32 OR Int64, checked above, so it is smaller than 1e19 (Int64's
    # maximum is about 9.22e18). A value at or beyond 1e19 cannot equal one, and is not converted:
    # [decimal] throws past Decimal's range, so 1e30 - a whole-number Double to 5.1's ConvertFrom-Json -
    # made this function throw instead of returning a finding (second review of PR #16). A guard at
    # Decimal's own limit is not enough: 2^96, one past Decimal.MaxValue, is the same Double as
    # [double][decimal]::MaxValue, and converting either throws (measured 2026-09-30).
    # An Int16 or Byte VALUE matches, as "type": "integer" accepts it; an Int16 or Byte MEMBER is refused
    # above, because no schema file can hold one - ConvertFrom-Json gives Int32, Int64, Decimal or
    # Double - and refusing it is a loud error about the schema, never a wrong answer about a value.
        $ok = $false
        foreach ($e in @($kw["enum"])) {
            if ($e -is [string]) { if ($Value -is [string] -and $Value -ceq $e) { $ok = $true } }
            elseif ($e -is [bool]) { if ($Value -is [bool] -and $Value -eq $e) { $ok = $true } }
            elseif ((Test-HordeSchemaType -Value $Value -Type "integer") -and [Math]::Abs([double]$Value) -lt 1e19 -and [decimal]$Value -eq [decimal]$e) { $ok = $true }
        }
        if (-not $ok) { [void]$findings.Add($Path + " is '" + $Value + "', not one of: " + (@($kw["enum"]) -join ", ")) }
    }
    if ($kw.ContainsKey("pattern") -and $Value -is [string]) {
        $re = ConvertTo-HordeSchemaPattern -Pattern "$($kw['pattern'])"
        if (-not [regex]::IsMatch($Value, $re, [System.Text.RegularExpressions.RegexOptions]::ECMAScript)) { [void]$findings.Add($Path + " does not match " + $kw["pattern"]) }
    }
    if ($kw.ContainsKey("minimum") -and (Test-HordeSchemaIsNumber $Value)) {
        # NaN is at or above nothing, so it is refused, by name: "below" would not be true of it either.
        if (($Value -is [double] -or $Value -is [single]) -and [double]::IsNaN([double]$Value)) { [void]$findings.Add($Path + " is NaN, which is not at or above the minimum " + $kw["minimum"]) }
        elseif ((Compare-HordeSchemaNumber $Value $kw["minimum"]) -lt 0) { [void]$findings.Add($Path + " is " + $Value + ", below the minimum " + $kw["minimum"]) }
    }
    $isObject = ($Value -is [System.Management.Automation.PSCustomObject] -or $Value -is [System.Collections.IDictionary])
    if ($isObject) {
        # KEYS ARE COMPARED EXACTLY, like JSON Schema and like wezterm-resurrect's Lua, which reads
        # session_id with a case-sensitive lookup. A PowerShell hashtable ignores case, so with @{} here
        # a file holding SESSION_ID and no session_id passed (review of PR #15). Both the value's keys
        # and the schema's property names go into ordinal dictionaries.
        $have = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
        foreach ($p in (Get-HordeObjectProps $Value)) { $have[$p.Name] = $p.Value }
        foreach ($r in @($kw["required"])) { if ($null -ne $r -and -not $have.ContainsKey("$r")) { [void]$findings.Add($Path + " has no '" + $r + "'") } }
        $props = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
        if ($kw.ContainsKey("properties")) { foreach ($p in (Get-HordeSchemaProps $kw["properties"])) { $props[$p.Name] = $p.Value } }
        foreach ($name in @($have.Keys)) {
            if ($props.ContainsKey($name)) {
                foreach ($f in @(Test-HordeSchema -Value $have[$name] -Schema $props[$name] -Path ($Path + "." + $name) -Root $Root)) { [void]$findings.Add($f) }
            } elseif ($kw.ContainsKey("additionalProperties") -and $kw["additionalProperties"] -eq $false) {
                [void]$findings.Add($Path + " has '" + $name + "', which the schema does not allow")
            }
        }
    }
    if ($Value -is [System.Collections.IList] -and $kw.ContainsKey("items")) {
        $i = 0
        foreach ($item in $Value) { foreach ($f in @(Test-HordeSchema -Value $item -Schema $kw["items"] -Path ($Path + "[" + $i + "]") -Root $Root)) { [void]$findings.Add($f) }; $i++ }
    }
    return @($findings)
}

function Get-HordeSchema {
    # A schema by name from the schema folder, e.g. "pane-session.v1".
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($Name -cnotmatch '\A[a-z][a-z0-9-]*\.v[0-9]+\z') { throw ("not a schema name: '" + $Name + "'") }
    $path = Join-Path (Split-Path -Parent $PSScriptRoot) ("schema\" + $Name + ".json")
    return (Read-HordeSchemaFile -Path $path)
}

function Read-HordeSchemaFile {
    # A schema file is UTF-8. Get-Content -Raw on Windows PowerShell 5.1 reads a file with no BOM in the
    # ANSI code page, so a non-ASCII character came back as two (review of PR #15). ReadAllText with
    # UTF-8 still honours a BOM if there is one. Schemas are Horde's own files, which no other system
    # is writing, so the shared read of core/ReadShared.ps1 is not needed here.
    param([Parameter(Mandatory = $true)][string]$Path)
    return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}
