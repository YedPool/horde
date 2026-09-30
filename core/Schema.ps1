# core/Schema.ps1 - check a parsed JSON value against a Horde schema.
#
# Horde's schemas (schema/*.json) are written as standard JSON Schema (draft-07), so the Lua plugin
# and anything else can read them too. Windows PowerShell 5.1 has no JSON Schema validator, so this
# file implements THE SUBSET HORDE'S SCHEMAS USE, and refuses a schema that uses anything else rather
# than silently skipping a rule it does not understand:
#
#   type (object, array, string, integer, number, boolean, null), required, properties,
#   additionalProperties (true or false), items, enum, pattern
#
# Keys starting "x-", and $schema, $id, title and description, are documentation and are ignored.
#
# Returns a list of findings, each naming the path it is about ("$.session_id"). Empty means valid.

$script:HordeSchemaKeywords = @("type", "required", "properties", "additionalProperties", "items", "enum", "pattern",
                                 '$schema', '$id', "title", "description")

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

function Test-HordeSchema {
    param($Value, $Schema, [string]$Path = '$')
    $findings = New-Object System.Collections.ArrayList
    # A schema node that is not an object is refused. Draft-07 allows true and false as schemas, and
    # read as an object they have no keywords, so the first version accepted everything for both
    # (review of PR #15).
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
    # ENUM HOLDS STRINGS AND WHOLE NUMBERS ONLY, checked before the value is looked at so a bad schema is
    # refused whatever the value. The first version compared other values as text: a null threw, 1 and
    # 1.0 differed, and objects matched by their string form (review of PR #15). A string matches only an
    # identical string; a whole number matches a value that is an integer (as "type": "integer" reads it)
    # of equal value, so 1 and 1.0 are the same and "1" is not. Whole numbers are needed for
    # schemaVersion, which every Horde record pins to 1.
    if ($kw.ContainsKey("enum")) {
        foreach ($e in @($kw["enum"])) {
            $isWhole = ($e -is [int] -or $e -is [long])
            if ($e -isnot [string] -and -not $isWhole) { throw ("enum at " + $Path + " may hold only strings and whole numbers; '" + $e + "' is neither") }
        }
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
            elseif ((Test-HordeSchemaType -Value $Value -Type "integer") -and [Math]::Abs([double]$Value) -lt 1e19 -and [decimal]$Value -eq [decimal]$e) { $ok = $true }
        }
        if (-not $ok) { [void]$findings.Add($Path + " is '" + $Value + "', not one of: " + (@($kw["enum"]) -join ", ")) }
    }
    if ($kw.ContainsKey("pattern") -and $Value -is [string]) {
        $re = ConvertTo-HordeSchemaPattern -Pattern "$($kw['pattern'])"
        if (-not [regex]::IsMatch($Value, $re, [System.Text.RegularExpressions.RegexOptions]::ECMAScript)) { [void]$findings.Add($Path + " does not match " + $kw["pattern"]) }
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
                foreach ($f in @(Test-HordeSchema -Value $have[$name] -Schema $props[$name] -Path ($Path + "." + $name))) { [void]$findings.Add($f) }
            } elseif ($kw.ContainsKey("additionalProperties") -and $kw["additionalProperties"] -eq $false) {
                [void]$findings.Add($Path + " has '" + $name + "', which the schema does not allow")
            }
        }
    }
    if ($Value -is [System.Collections.IList] -and $kw.ContainsKey("items")) {
        $i = 0
        foreach ($item in $Value) { foreach ($f in @(Test-HordeSchema -Value $item -Schema $kw["items"] -Path ($Path + "[" + $i + "]"))) { [void]$findings.Add($f) }; $i++ }
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
