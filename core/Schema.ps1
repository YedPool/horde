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
# THE MINIMUM ITSELF IS A WHOLE NUMBER FROM -(2^53 - 1) TO 2^53 - 1, and anything else is refused
# (issue #25). 5.1's ConvertFrom-Json reads 0.1 as a Decimal and 1e-1 as a Double, which is slightly
# more than one tenth, so compared exactly, {"minimum": 1e-1} refused the value 0.1 that
# {"minimum": 0.1} accepted (measured 2026-09-30). Whole numbers do the same from 2^53 up:
# 9007199254740995.0 is a Decimal of that number, 9.007199254740995e15 the Double 9007199254740996,
# and 9.007199254740993e15 the Double 2^53. Within the bound - JavaScript's "safe integers" - Int32,
# Int64, Decimal and Double each hold every whole number exactly and no other whole number rounds to
# it, so 1, 1.0 and 1e0 are one minimum.
# Normalising both sides instead - reading a Double as the shortest decimal that parses back to it -
# was rejected: it would change how every Double VALUE compares, not just the minimum; .NET
# Framework's "R" format is not guaranteed to give that shortest text, so it would have to be searched
# for; and it still could not recover a text with more digits than a Double keeps, so it would narrow
# the gap, not close it. Refusing costs nothing today: the one minimum in Horde's schemas is 0.
# WHAT THIS DOES NOT CLOSE: a text with more significant digits than a Double keeps is rounded by the
# parser before this file sees it, and nothing here can tell. For a VALUE: 9.9999999999999999999e-1
# parses as the Double 1 and passes minimum 1, while 0.99999999999999999999 parses as a Decimal and is
# refused (measured 2026-09-30). For a minimum, the same holds of a fraction written with an exponent
# and so many digits that the Double it becomes is whole.
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
# EVERY NODE OF A SCHEMA IS CHECKED ONCE, when Test-HordeSchema is called on the top of it: each
# definition, whether or not anything refers to it, and every node under the root's own properties and
# items, whether or not a value reaches it (issue #25). An unknown keyword, a node that is not an
# object, a pattern that does not compile, or a $ref that does not resolve is refused there, not on the
# day a value first reaches it. definitions and properties that are not objects are refused as well.
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
        # EVERY INTEGER IS A NUMBER. This listed its own types and left out Int16 and Byte, which
        # "integer" accepts (issue #23), so one list now serves both "number" and minimum.
        "number"  { return (Test-HordeSchemaIsNumber $Value) }
    }
    throw ("the schema names a type this validator does not know: '" + $Type + "'")
}

function Test-HordeSchemaIsNumber {
    # Every .NET type a number reaches the validator as: ConvertFrom-Json gives Int32, Int64, Decimal or
    # Double, and a value built in PowerShell may hold Int16, Byte or Single ("type": "integer" also
    # accepts Int16 and Byte). Never a string or a boolean. "type": "number" asks this same question.
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
        # AND A WHOLE NUMBER OF MAGNITUDE AT MOST 2^53 - 1, so it means one number however the JSON wrote
        # it (issue #25; the reasons are in the header).
        $bound = [long]9007199254740991
        $sameHoweverWritten = ((Test-HordeSchemaType -Value $m -Type "integer") -and (Compare-HordeSchemaNumber $m $bound) -le 0 -and (Compare-HordeSchemaNumber $m (-$bound)) -ge 0)
        if (-not $sameHoweverWritten) { throw ("minimum at " + $Path + " must be a whole number from -(2^53 - 1) to 2^53 - 1, which means the same however JSON writes it; '" + $m + "' is not one") }
    }
    # A TYPE NAME IS CHECKED HERE as well as when a value meets it, so a definition nothing refers to
    # cannot carry one this validator does not know.
    if ($kw.ContainsKey("type") -and $script:HordeSchemaTypes -cnotcontains "$($kw['type'])") {
        throw ("the schema names a type this validator does not know: '" + $kw["type"] + "'")
    }
    # A PATTERN IS COMPILED HERE, exactly as Test-HordeSchema will match it, so one that does not compile
    # is refused with its node and not on the day a string first reaches it (issue #25: "(" in a
    # definition passed the definitions walk, and "(" anywhere passed a value that was not a string;
    # measured 2026-09-30). The static [regex] methods share a cache of recent patterns (15 by default,
    # Regex.CacheSize), so the match below usually reuses what this compiles.
    if ($kw.ContainsKey("pattern")) {
        try { [void][regex]::Match("", (ConvertTo-HordeSchemaPattern -Pattern "$($kw['pattern'])"), [System.Text.RegularExpressions.RegexOptions]::ECMAScript) }
        catch { throw ("pattern at " + $Path + " is not a regular expression this validator can compile: " + $_.Exception.Message) }
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
    # refuse on reaching the node is refused here, because both refuse through
    # Get-HordeSchemaNodeKeywords. (A pattern that did not compile was the exception until issue #25:
    # only the match compiled it.) A $ref is resolved, never followed into its definition, which is
    # checked on its own; so a recursive definition is walked once, and the walk ends. Path is a JSON
    # pointer into the schema, "#/definitions/node/properties/children/items".
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
    Assert-HordeSchemaSubtrees -Kw $kw -Path $Path -Root $Root
}

function Assert-HordeSchemaSubtrees {
    # The nodes under one node's properties and items, each checked by Assert-HordeSchemaNode. Kw is
    # the node's keywords, already checked by Get-HordeSchemaNodeKeywords. Used for every definition's
    # subtrees and, from Test-HordeSchema, for the root's own.
    param($Kw, [string]$Path, $Root)
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
        # THE ROOT'S OWN SUBTREES ARE CHECKED ONCE HERE TOO (issue #25), for the reason the definitions
        # are: {"properties": {"q": {"maximum": 3}}} accepted {}, because no value reached q (measured
        # 2026-09-30, before this line). The root node itself was checked just above, by
        # Get-HordeSchemaNodeKeywords. A caller passing -Root is inside a schema whose top it has
        # checked already - core/Projection.ps1 (feature/core-projection) checks one field's value that way,
        # once per field per session - so this runs for a top-level call only.
        Assert-HordeSchemaSubtrees -Kw $kw -Path "#" -Root $Root
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
