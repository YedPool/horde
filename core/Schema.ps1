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
        "array"   { return ($Value -is [array]) }
        "string"  { return ($Value -is [string]) }
        "boolean" { return ($Value -is [bool]) }
        "null"    { return ($null -eq $Value) }
        "integer" { return ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte]) }
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
    $kw = @{}
    foreach ($p in (Get-HordeSchemaProps $Schema)) {
        if ($p.Name -like "x-*") { continue }
        if ($script:HordeSchemaKeywords -cnotcontains $p.Name) { throw ("the schema uses '" + $p.Name + "' at " + $Path + ", which this validator does not implement") }
        $kw[$p.Name] = $p.Value
    }
    if ($kw.ContainsKey("type")) {
        if (-not (Test-HordeSchemaType -Value $Value -Type "$($kw['type'])")) {
            [void]$findings.Add($Path + " should be " + $kw["type"])
            return @($findings)
        }
    }
    if ($kw.ContainsKey("enum")) {
        $ok = $false
        foreach ($e in @($kw["enum"])) { if ($Value -is [string] -and $e -is [string]) { if ($Value -ceq $e) { $ok = $true } } elseif ("$Value" -eq "$e" -and $Value.GetType() -eq $e.GetType()) { $ok = $true } }
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
    if ($Value -is [array] -and $kw.ContainsKey("items")) {
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
    return ((Get-Content -LiteralPath $path -Raw) | ConvertFrom-Json)
}
