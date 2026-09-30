# DOES schema/pane-session.v1 DESCRIBE THE PANE-SESSIONS FILES AS THEY REALLY ARE?
#
# Step 1.1: "document the existing format exactly as it is". A schema that describes reality has
# two duties, and both are tested: every real file must pass it, and a file that breaks what the
# readers rely on must not. Golden fixtures (test/fixtures/pane-session/valid) carry one file for each
# of the 11 distinct key sets the census of 163 real files found (checked below), plus a multi-line
# wezfleet-backfill file and one with an unknown source and field; ids and paths are synthetic. The
# real files on this machine are then checked too, read-only, when they are present.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\Schema.ps1")
. (Join-Path $root "core\ReadShared.ps1")

$schema = Get-HordeSchema -Name "pane-session.v1"
$fx = Join-Path $root "test\fixtures\pane-session"
function Read-Fixture { param([string]$Rel) $t = Read-HordeSharedText -Path (Join-Path $fx $Rel); $v = $t | ConvertFrom-Json; return ,$v }
function Findings { param($Value) return @(Test-HordeSchema -Value $Value -Schema $schema) }
# Does any finding match Like? Findings are asserted by their TEXT, so a check cannot pass on some other
# finding. Like is a wildcard pattern: write a literal [ or ] as `[ and `].
function Has { param($Found, [string]$Like) return (@(@($Found) | Where-Object { $_ -clike $Like }).Count -gt 0) }

Write-Host ""
Write-Host "--- the validator refuses what it does not implement ---" -ForegroundColor Cyan
Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ maximum = 3 }) } "does not implement") "a schema keyword the validator does not implement is refused, never silently skipped"
Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ type = "decimal" }) } "does not know") "an unknown type name is refused"
# A rule the validator cannot apply is refused, never read as "anything goes". Draft-07 allows
# additionalProperties to be a schema and allows a schema to be true or false; this validator does not
# implement either, and the first version accepted everything for both (review of PR #15).
$oneKey = [pscustomobject]@{ a = 1 }
Check (Throws { Test-HordeSchema -Value $oneKey -Schema ([pscustomobject]@{ additionalProperties = [pscustomobject]@{ type = "string" } }) } "additionalProperties at $ must be true or false") "additionalProperties given as a schema is refused"
Check (Throws { Test-HordeSchema -Value $oneKey -Schema ([pscustomobject]@{ additionalProperties = 0 }) } "additionalProperties at $ must be true or false") "additionalProperties 0 is refused, not read as false"
Check (Throws { Test-HordeSchema -Value $oneKey -Schema $false } "the schema at $ is not an object") "a boolean schema is refused"
Check (Throws { Test-HordeSchema -Value $oneKey -Schema ([pscustomobject]@{ properties = [pscustomobject]@{ a = $true } }) } "the schema at #/properties/a is not an object") "a boolean schema under properties is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema "integer" } "the schema at $ is not an object") "a schema that is a string is refused"
# x- keys: the check must FAIL, not crash, when they stop being ignored - a crash is an [ERROR], which
# tools/Mutate.ps1 rightly does not count as caught. So the call is caught here and its result judged.
$xFound = $null; $xThrew = $false
try { $xFound = @(Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ type = "integer"; "x-note" = "anything" })) } catch { $xThrew = $true }
Check ((-not $xThrew) -and $xFound.Count -eq 0) "x- keys are documentation and are ignored"
Check (Has (Test-HordeSchema -Value "a" -Schema ([pscustomobject]@{ enum = @("A") })) "$ is 'a', not one of: A") "enum compares strings case-sensitively"
Check (@(Test-HordeSchema -Value "b" -Schema ([pscustomobject]@{ enum = @("a", "b") })).Count -eq 0) "CONTROL: a string the enum names is accepted"
Check (Has (Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ enum = @("1") })) "$ is '1', not one of: 1") "a number is not the string of its digits"
# ENUM HOLDS STRINGS AND WHOLE NUMBERS ONLY. The first version compared other values as text: $null
# threw, 1 and 1.0 differed, and objects were compared by their string form (review of PR #15). Whole
# numbers are needed for schemaVersion; anything else is refused - even when the value's type already
# failed.
Check (Throws { Test-HordeSchema -Value "x" -Schema ([pscustomobject]@{ enum = @($null) }) } "enum at $ may hold only strings, whole numbers and booleans") "a null in an enum is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ enum = @(1.5) }) } "enum at $ may hold only strings, whole numbers and booleans") "a fraction in an enum is refused"
Check (Throws { Test-HordeSchema -Value "x" -Schema ([pscustomobject]@{ enum = @([pscustomobject]@{ a = 1 }) }) } "enum at $ may hold only strings, whole numbers and booleans") "an object in an enum is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ type = "string"; enum = @($null) }) } "enum at $ may hold only strings, whole numbers and booleans") "a bad enum is refused even when the value fails its type first"
$one = [pscustomobject]@{ enum = @(1) }
Check (@(Test-HordeSchema -Value 1 -Schema $one).Count -eq 0) "a whole-number enum accepts that number"
Check (@(Test-HordeSchema -Value ([decimal]1.0) -Schema $one).Count -eq 0) "and accepts it written as 1.0, which PowerShell reads as a decimal"
Check (Has (Test-HordeSchema -Value "1" -Schema $one) "$ is '1', not one of: 1") "but not the string of its digits"
Check (Has (Test-HordeSchema -Value 2 -Schema $one) "$ is '2', not one of: 1") "and not another number"
$yes = [pscustomobject]@{ enum = @($true) }
# First that the schema is accepted at all: a refused boolean enum would throw, and a throw inside
# the checks below reads as a crashed suite rather than a failed check.
Check (-not (Throws { Test-HordeSchema -Value $true -Schema $yes })) "a boolean enum is a schema the validator accepts"
Check (@(Test-HordeSchema -Value $true -Schema $yes).Count -eq 0) "a boolean enum accepts that boolean"
Check (Has (Test-HordeSchema -Value $false -Schema $yes) "$ is 'False', not one of: True") "but not the other one"
Check (Has (Test-HordeSchema -Value "true" -Schema $yes) "$ is 'true', not one of: True") "and not the word true"
Check (Has (Test-HordeSchema -Value 1 -Schema $yes) "$ is '1', not one of: True") "and not the number one"
$twoKeys = [pscustomobject]@{ a = 1; b = 2 }
$aOnly = [pscustomobject]@{ a = [pscustomobject]@{ type = "integer" } }
Check (Has (Test-HordeSchema -Value $twoKeys -Schema ([pscustomobject]@{ type = "object"; properties = $aOnly; additionalProperties = $false })) "$ has 'b', which the schema does not allow") "additionalProperties false refuses a key the schema does not name"
Check (@(Test-HordeSchema -Value $twoKeys -Schema ([pscustomobject]@{ type = "object"; properties = $aOnly })).Count -eq 0) "with additionalProperties absent, a key the schema does not name is allowed"
Check (@(Test-HordeSchema -Value $twoKeys -Schema ([pscustomobject]@{ type = "object"; properties = $aOnly; additionalProperties = $true })).Count -eq 0) "additionalProperties true allows a key the schema does not name"
Check (Has (Test-HordeSchema -Value @(1, "x") -Schema ([pscustomobject]@{ type = "array"; items = [pscustomobject]@{ type = "integer" } })) '$`[1`] should be integer') "items checks every element of an array"
Check (Has (Test-HordeSchema -Value $twoKeys -Schema ([pscustomobject]@{ properties = [pscustomobject]@{ b = [pscustomobject]@{ type = "string" } } })) '$.b should be string') "properties checks the value under each name"

Write-Host ""
Write-Host "--- every type refuses what is not it ---" -ForegroundColor Cyan
# One wrong value and one right value per type, each finding asserted by its text.
$typeCases = @(
    @{ Type = "string";  Good = "a";   Bad = 1 },
    @{ Type = "boolean"; Good = $true; Bad = "true" },
    @{ Type = "number";  Good = 1.5;   Bad = "1" },
    @{ Type = "integer"; Good = 7;     Bad = "7" },
    @{ Type = "null";    Good = $null; Bad = 0 },
    @{ Type = "array";   Good = @(1);  Bad = "abc" },
    @{ Type = "object";  Good = @{};   Bad = @(1) }
)
foreach ($c in $typeCases) {
    $ts = [pscustomobject]@{ type = $c.Type }
    Check (Has (Test-HordeSchema -Value $c.Bad -Schema $ts) ('$ should be ' + $c.Type)) ($c.Type + ": a wrong value is refused")
    Check (@(Test-HordeSchema -Value $c.Good -Schema $ts).Count -eq 0) ($c.Type + ": CONTROL - a right value is accepted")
}
Check (Has (Test-HordeSchema -Value @{ a = 1 } -Schema ([pscustomobject]@{ type = "array" })) '$ should be array') "array: a hashtable is not an array"
# EVERY INTEGER IS A NUMBER, however PowerShell holds it (issue #23). "integer" accepted Int16 and Byte
# while "number" refused them, so a value built in PowerShell passed the narrower type and failed the
# wider one. Measured 2026-09-30 on 5.1, before the fix: both gave "$ should be number".
foreach ($v in @([int16]1, [byte]1, [single]1.5)) {
    Check (@(Test-HordeSchema -Value $v -Schema ([pscustomobject]@{ type = "number" })).Count -eq 0) ("number: a value held as " + $v.GetType().Name + " is a number")
}

Write-Host ""
Write-Host "--- a schema built as a hashtable means the same ---" -ForegroundColor Cyan
# Read wrongly, a hashtable schema throws (its .NET properties look like unknown keywords); Safely turns
# that into a finding so the check FAILS rather than crashing, and a mutation of it counts as caught.
function Safely { param([scriptblock]$Block) try { return @(& $Block) } catch { return @("THREW: " + $_.Exception.Message) } }
$hashSchema = @{ type = "object"; required = @("a"); properties = @{ a = @{ type = "integer" } } }
Check (Has (Safely { Test-HordeSchema -Value ([pscustomobject]@{ a = "x" }) -Schema $hashSchema }) '$.a should be integer') "a hashtable schema checks its properties"
Check (Has (Safely { Test-HordeSchema -Value ([pscustomobject]@{ b = 1 }) -Schema $hashSchema }) "$ has no 'a'") "a hashtable schema checks required"
Check (@(Safely { Test-HordeSchema -Value @{ a = 1 } -Schema $hashSchema }).Count -eq 0) "CONTROL: a hashtable value that fits a hashtable schema is valid"
Check (Throws { Get-HordeSchema -Name "..\core\Schema" } "not a schema name") "a schema name cannot reach a file outside the schema folder"
# A schema file is UTF-8. Get-Content -Raw on Windows PowerShell 5.1 reads a file with no BOM in the
# ANSI code page, so a non-ASCII character in a schema came back as two (review of PR #15).
$utf8Dir = Join-Path $env:TEMP ("horde-schema-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $utf8Dir | Out-Null
try {
    $eAcute = [string][char]0xE9
    $utf8File = Join-Path $utf8Dir "utf8.v1.json"
    [System.IO.File]::WriteAllText($utf8File, ('{"description":"caf' + $eAcute + '"}'), (New-Object System.Text.UTF8Encoding($false)))
    Check ((Read-HordeSchemaFile -Path $utf8File).description -ceq ("caf" + $eAcute)) "a schema file is read as UTF-8, BOM or not"
} finally { Remove-Item -LiteralPath $utf8Dir -Recurse -Force }
Check (-not (Test-Path -LiteralPath $utf8Dir)) "the UTF-8 test's temporary folder is gone"

Write-Host ""
Write-Host "--- keys are compared exactly, as the readers compare them ---" -ForegroundColor Cyan

# wezterm-resurrect's Lua reads session_id with a case-sensitive table lookup, so a file whose only
# id is SESSION_ID has no id as far as it is concerned. The validator must agree, for the keys of the
# value AND for the names in the schema's properties.
$exactSchema = [pscustomobject]@{ type = "object"; required = @("a"); properties = [pscustomobject]@{ a = [pscustomobject]@{ type = "integer" } }; additionalProperties = $false }
Check (Has (Test-HordeSchema -Value ([pscustomobject]@{ A = 1 }) -Schema $exactSchema) "$ has no 'a'") "a required key is not satisfied by one differing only in case"
Check (Has (Test-HordeSchema -Value ([pscustomobject]@{ A = 1 }) -Schema $exactSchema) "$ has 'A', which the schema does not allow") "a key differing only in case from a property is not that property"
Check (Has (Test-HordeSchema -Value @{ A = 1 } -Schema $exactSchema) "$ has no 'a'") "the same holds for a value built as a hashtable, whose own lookups ignore case"
# MEASURED 2026-09-29 on Windows PowerShell 5.1: ConvertFrom-Json refuses text holding two keys that
# differ only in case ("contains the duplicated keys 'a' and 'A'"), so such a file never reaches the
# validator; the real-file check below reports it as not JSON.
Check (Throws { '{"a":1,"A":2}' | ConvertFrom-Json } "duplicated keys") "CONTROL: ConvertFrom-Json refuses keys differing only in case, so no file can carry both"

Write-Host ""
Write-Host "--- a pattern means what it means in JSON Schema (ECMA-262), not in .NET ---" -ForegroundColor Cyan

# In .NET, $ also matches before a final newline, so "<uuid>`n" matched the session_id pattern; and
# .NET's \d and \w match non-ASCII digits and letters, where ECMA-262's do not. MEASURED 2026-09-29 on
# 5.1: [regex]::IsMatch("ab`n", '^ab$') is True, with '^ab\z' False; '^\d$' matches U+0663 without
# RegexOptions.ECMAScript and not with it.
Check ((ConvertTo-HordeSchemaPattern '^a$') -ceq '^a\z') "an end-of-input dollar becomes \z"
Check ((ConvertTo-HordeSchemaPattern '^a\$$') -ceq '^a\$\z') "an escaped dollar stays a literal dollar"
Check ((ConvertTo-HordeSchemaPattern '^[$\]]$') -ceq '^[$\]]\z') "a dollar inside a character class stays a literal dollar"
$uuidOnly = [pscustomobject]@{ type = "string"; pattern = '^[0-9a-f]+$' }
Check (Has (Test-HordeSchema -Value "abc`n" -Schema $uuidOnly) '$ does not match*') "a trailing newline does not satisfy a pattern ending in $"
Check (Has (Test-HordeSchema -Value "ABC" -Schema $uuidOnly) '$ does not match*') "a pattern is case-sensitive"
Check (Has (Test-HordeSchema -Value ([string][char]0x0663) -Schema ([pscustomobject]@{ pattern = '^\d$' })) '$ does not match*') "\d matches ASCII digits only, as in ECMA-262"
Check (@(Test-HordeSchema -Value "abc" -Schema $uuidOnly).Count -eq 0) "CONTROL: a string the pattern describes still matches"

Write-Host ""
Write-Host "--- an integer or an array is recognised however PowerShell holds it ---" -ForegroundColor Cyan

# MEASURED 2026-09-29, Windows PowerShell 5.1 ConvertFrom-Json: 1.0 gives Decimal, 1e3 gives Double,
# 99999999999999999999 gives Decimal, 1 gives Int32. JSON Schema calls any number with no fractional
# part an integer, so all but 1.5 are integers.
$intSchema = [pscustomobject]@{ type = "integer" }
function Read-JsonNumber { param([string]$Text) return ('{"n":' + $Text + '}' | ConvertFrom-Json).n }
Check ((Read-JsonNumber "1.0") -is [decimal] -and (Read-JsonNumber "1e3") -is [double]) "CONTROL: 5.1 parses 1.0 as Decimal and 1e3 as Double"
foreach ($t in @("1.0", "1e3", "99999999999999999999")) {
    Check (@(Test-HordeSchema -Value (Read-JsonNumber $t) -Schema $intSchema).Count -eq 0) ($t + " is an integer")
}
Check (Has (Test-HordeSchema -Value (Read-JsonNumber "1.5") -Schema $intSchema) '$ should be integer') "1.5 is not an integer"
Check (Has (Test-HordeSchema -Value 1.5 -Schema $intSchema) '$ should be integer') "a Double with a fraction is not an integer"
# A VALUE BEYOND DECIMAL'S RANGE IS A FINDING, NEVER A CRASH. 5.1's ConvertFrom-Json reads 1e30 and
# 79228162514264337593543950336 (2^96, one past Decimal.MaxValue) as whole-number Doubles, and the
# first comparison converted every whole number to Decimal, so both threw instead of being refused
# (second review of PR #16; measured 2026-09-30: [decimal] of either throws). The call is caught
# here so the check FAILS rather than crashes, which tools/Mutate.ps1 would not count as caught.
function Enum-Findings {
    param($Value, $Schema)
    try { return ,@(Test-HordeSchema -Value $Value -Schema $Schema) } catch { return ,@("THREW: " + $_.Exception.Message) }
}
Check ((Read-JsonNumber "1e30") -is [double] -and (Read-JsonNumber "79228162514264337593543950336") -is [double]) "CONTROL: 5.1 parses 1e30 and 2^96 as Double"
foreach ($t in @("1e30", "-1e30", "79228162514264337593543950336")) {
    $found = Enum-Findings (Read-JsonNumber $t) $one
    Check ($found.Count -eq 1 -and $found[0] -clike '$ is ''*'', not one of: 1') ("a whole number beyond Decimal's range, " + $t + ", is refused by enum [1], not thrown on (" + ($found -join "; ") + ")")
}
# THE GUARD IS "IS AN INTEGER", NOT "IS NOT A STRING". PowerShell converts $true to 1, so a looser
# guard accepted $true for enum [1]; a one-element array is not a number at all.
$found = Enum-Findings $true $one
Check ($found.Count -eq 1 -and $found[0] -clike '$ is ''True'', not one of: 1') ("true is not the whole number 1 (" + ($found -join "; ") + ")")
$found = Enum-Findings (,@(1)) $one
Check ($found.Count -eq 1 -and $found[0] -clike '$ is ''*'', not one of: 1') ("a list holding 1 is not the whole number 1 (" + ($found -join "; ") + ")")
# NOR "IS A NUMBER": [decimal] rounds a Double or Single to 15 or 7 significant digits, so the Double
# 1.0000000000000002 and the Single 1.0000001 each became the Decimal 1 and matched enum [1] under that
# guard (measured 2026-09-30; mutant enum-whole-number-guard-as-number survived once "type": "number"
# took Int16 and Byte, issue #23, and nothing else told the two guards apart).
foreach ($v in @([double]1.0000000000000002, [single]1.0000001)) {
    $found = Enum-Findings $v $one
    Check ($found.Count -eq 1 -and $found[0] -clike '$ is ''*'', not one of: 1') ("a " + $v.GetType().Name + " a hair above 1 is not the whole number 1 (" + ($found -join "; ") + ")")
}
# EVERY INTEGER TYPE Test-HordeSchemaType ACCEPTS IS ACCEPTED HERE TOO, including Int16 and Byte,
# which the "number" type also accepts since issue #23.
foreach ($v in @([int16]1, [byte]1, [long]1)) {
    $found = Enum-Findings $v $one
    Check ($found.Count -eq 0) ("a whole-number enum accepts 1 held as " + $v.GetType().Name + " (" + ($found -join "; ") + ")")
}
# AN ENUM MEMBER MAY BE Int32 OR Int64, the two types ConvertFrom-Json gives a whole number in range.
$longOne = [pscustomobject]@{ enum = @([long]1) }
$found = Enum-Findings 1 $longOne
Check ($found.Count -eq 0) ("an Int64 enum member is accepted and matches 1 (" + ($found -join "; ") + ")")
# An Int16 or Byte MEMBER is refused, on purpose: no schema file can produce one, since ConvertFrom-Json
# gives Int32, Int64, Decimal or Double, and a refusal is a loud error at the schema, never a silent
# wrong answer about a value.
Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ enum = @([int16]1) }) } "enum at $ may hold only") "an Int16 enum member is refused: no schema file can hold one"
# A value built in PowerShell may hold a list as an ArrayList rather than an array.
$listSchema = [pscustomobject]@{ type = "object"; properties = [pscustomobject]@{ list = [pscustomobject]@{ type = "array"; items = $intSchema } } }
Check (@(Test-HordeSchema -Value @{ list = [System.Collections.ArrayList]@(1, 2) } -Schema $listSchema).Count -eq 0) "an ArrayList is an array"
Check (Has (Test-HordeSchema -Value @{ list = [System.Collections.ArrayList]@(1, "x") } -Schema $listSchema) '$.list`[1`] should be integer') "items checks every element of an ArrayList"

Write-Host ""
Write-Host "--- local `$ref and definitions, for a recursive shape ---" -ForegroundColor Cyan

# A LAYOUT IS A TREE, so its schema must refer to itself (schema/restore-plan.v1). The validator
# follows "#/definitions/<name>" and nothing else. Each call here turns an error into a finding, so a
# validator that throws where it should validate fails a check rather than only recording an error.
function RefFindings { param($Value, $Schema) try { return @(Test-HordeSchema -Value $Value -Schema $Schema) } catch { return @("THREW: " + $_.Exception.Message) } }
function Obj { param([string]$Json) return ($Json | ConvertFrom-Json) }
$intRef = Obj '{ "definitions": { "n": { "type": "integer" } }, "type": "object", "properties": { "a": { "$ref": "#/definitions/n" } } }'
$f = @(RefFindings (Obj '{ "a": "x" }') $intRef)
Check ($f.Count -eq 1 -and $f[0] -ceq '$.a should be integer') ("a local `$ref applies its definition, at the referring path (" + ($f -join "; ") + ")")
$f = @(RefFindings (Obj '{ "a": 3 }') $intRef)
Check ($f.Count -eq 0) ("CONTROL: a value the definition accepts passes through the `$ref (" + ($f -join "; ") + ")")
$tree = Obj '{ "definitions": { "node": { "type": "object", "properties": { "v": { "type": "integer" }, "kids": { "type": "array", "items": { "$ref": "#/definitions/node" } } }, "additionalProperties": false } }, "$ref": "#/definitions/node" }'
$f = @(RefFindings (Obj '{ "v": 1, "kids": [ { "v": 2, "kids": [ { "v": "deep" } ] }, { "v": 3 } ] }') $tree)
Check ($f.Count -eq 1 -and $f[0] -ceq '$.kids[0].kids[0].v should be integer') ("a definition that refers to itself checks every level of a tree (" + ($f -join "; ") + ")")
$f = @(RefFindings (Obj '{ "v": 1, "kids": [ { "v": 2, "kids": [ { "v": 4, "pane": 7 } ] } ] }') $tree)
Check ($f.Count -eq 1 -and $f[0] -ceq '$.kids[0].kids[0] has ''pane'', which the schema does not allow') ("additionalProperties inside a recursive definition holds at depth (" + ($f -join "; ") + ")")
$f = @(RefFindings (Obj '{ "v": 1, "kids": [ { "v": 2, "kids": [] } ] }') $tree)
Check ($f.Count -eq 0) ("CONTROL: a valid tree passes (" + ($f -join "; ") + ")")
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "$ref": "http://example.com/s.json#/definitions/n" }') } "only local") "a `$ref to another document is refused, never fetched or skipped"
Check (Throws { Test-HordeSchema -Value ([pscustomobject]@{ a = 1 }) -Schema (Obj '{ "definitions": { "n": {} }, "properties": { "a": { "$ref": "#/properties/b" } }, "type": "object" }') } "only local") "a local `$ref that is not #/definitions/<name> is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": { "n": { "type": "integer" } }, "$ref": "#/definitions/m" }') } "names no definition") "a `$ref to a definition that does not exist is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "$ref": "#/definitions/n" }') } "names no definition") "a `$ref in a schema with no definitions at all is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": { "n": { "type": "integer" } }, "$ref": "#/definitions/N" }') } "names no definition") "a `$ref names its definition exactly, case included, as a JSON pointer does"
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": { "n": { "type": "integer" } }, "$ref": "#/definitions/n", "type": "string" }') } "beside") "a `$ref with a validation keyword beside it is refused: draft-07 would ignore that keyword"
Check (Throws { Test-HordeSchema -Value ([pscustomobject]@{ a = 1 }) -Schema (Obj '{ "type": "object", "properties": { "a": { "definitions": { "n": {} } } } }') } "top of a schema") "definitions anywhere but the top of a schema is refused: #/definitions/ would never find them"
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": { "a": { "$ref": "#/definitions/b" }, "b": { "$ref": "#/definitions/a" } }, "$ref": "#/definitions/a" }') } "circular") "a `$ref chain that loops without reaching a value is refused, not followed forever"
# A $ref THAT IS NOT A STRING IS REFUSED. The first version read it as "$($kw['$ref'])", so an array
# holding one pointer became that pointer's text and was followed (review of PR #17): a schema no
# draft-07 validator accepts was given a meaning here.
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": { "n": { "type": "integer" } }, "$ref": ["#/definitions/n"] }') } "is not a string") "a `$ref given as an array is refused, not stringified and followed"
Check (Throws { Test-HordeSchema -Value ([pscustomobject]@{ a = 1 }) -Schema (Obj '{ "definitions": { "n": {} }, "type": "object", "properties": { "a": { "$ref": 7 } } }') } "is not a string") "a `$ref given as a number is refused"
$f = @(RefFindings (Obj '{ "a": 3 }') $intRef)
Check ($f.Count -eq 0) ("CONTROL: a `$ref given as a string is still followed (" + ($f -join "; ") + ")")
Write-Host ""
Write-Host "--- every definition is checked, whether or not anything refers to it ---" -ForegroundColor Cyan
# A DEFINITION NOTHING REFERS TO WAS NEVER READ (review of PR #17), so an unknown keyword, a node that
# is not an object or a dangling $ref sat in a schema file unnoticed until the day something referred
# to it. Each definition is now checked once, as a schema, when the top of the schema is.
$unusedGood = Obj '{ "definitions": { "unused": { "type": "object", "properties": { "a": { "type": "integer" } } } }, "type": "integer" }'
$f = @(RefFindings 1 $unusedGood)
Check ($f.Count -eq 0) ("CONTROL: a valid definition nothing refers to changes nothing (" + ($f -join "; ") + ")")
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": { "unused": { "maximum": 3 } }, "type": "integer" }') } "does not implement") "an unknown keyword in a definition nothing refers to is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": { "unused": true }, "type": "integer" }') } "is not an object") "a definition that is not an object is refused though nothing refers to it"
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": { "unused": { "$ref": "#/definitions/gone" } }, "type": "integer" }') } "names no definition") "a `$ref in a definition nothing refers to must resolve"
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": { "unused": { "type": "object", "properties": { "a": { "type": "array", "items": { "$ref": "#/definitions/gone" } } } } }, "type": "integer" }') } "names no definition") "a dangling `$ref deep inside an unreferenced definition is found"
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": { "unused": { "properties": { "a": { "type": "decimal" } } } }, "type": "integer" }') } "does not know") "an unknown type name inside an unreferenced definition is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": { "a": { "$ref": "#/definitions/b" }, "b": { "$ref": "#/definitions/a" } }, "type": "integer" }') } "circular") "a `$ref loop among definitions nothing refers to is refused"
# A PATTERN IS COMPILED WITH ITS NODE, not when a string first meets it (issue #25). The walk above
# claimed to refuse whatever Test-HordeSchema would, but "(" in a definition passed, and so did "(" at
# the top when the value was not a string (both measured 2026-09-30, before the fix).
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": { "z": { "pattern": "(" } }, "type": "integer" }') } "pattern at #/definitions/z is not a regular expression") "a pattern that does not compile, in a definition nothing refers to, is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "pattern": "(" }') } "pattern at $ is not a regular expression") "a pattern that does not compile is refused though the value is not a string"
$f = @(RefFindings 1 (Obj '{ "definitions": { "z": { "pattern": "^[a-z]+$" } }, "type": "integer" }'))
Check ($f.Count -eq 0) ("CONTROL: a pattern that compiles, in a definition, is accepted (" + ($f -join "; ") + ")")
# A CALLER THAT PASSES -Root CHECKS A PART OF A SCHEMA whose top is not re-checked (core/Projection.ps1
# checks one field's value schema this way), so the loop guard that follows a $ref chain must hold on
# its own. Measured by mutation: with the definitions check above, the old loop check alone was no
# longer tested (circular-ref-followed and ref-chain-forgotten survived).
$loopRoot = Obj '{ "definitions": { "a": { "$ref": "#/definitions/b" }, "b": { "$ref": "#/definitions/a" } } }'
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "$ref": "#/definitions/a" }') -Root $loopRoot } "circular") "a `$ref loop reached below the top, through -Root, is refused rather than followed until the stack overflows"
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": [ { "type": "integer" } ], "type": "integer" }') } "definitions at $ must be an object") "definitions given as an array is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": "n", "type": "integer" }') } "definitions at $ must be an object") "definitions given as a string is refused"
# properties read as an object when it is an array has .NET properties (Length, Rank) and no keys, so
# "properties": ["a"] checked nothing and passed every value.
Check (Throws { Test-HordeSchema -Value ([pscustomobject]@{ a = "x" }) -Schema (Obj '{ "type": "object", "properties": [ { "type": "integer" } ] }') } "properties at $ must be an object") "properties given as an array is refused, not read as no properties"
$f = @(RefFindings 1 (Obj '{ "definitions": {}, "type": "integer" }'))
Check ($f.Count -eq 0) ("CONTROL: an empty definitions object is accepted (" + ($f -join "; ") + ")")

Write-Host ""
Write-Host "--- the root's own subtrees are checked too, whether or not a value reaches them ---" -ForegroundColor Cyan
# ISSUE #25: the reason for checking every definition applies to the root's own properties and items,
# and {"properties": {"q": {"maximum": 3}}} accepted {} because no value reached q (measured 2026-09-30,
# before the fix, with a dangling $ref and an items node the same).
Check (Throws { Test-HordeSchema -Value (Obj '{}') -Schema (Obj '{ "properties": { "q": { "maximum": 3 } } }') } "the schema uses 'maximum' at #/properties/q") "an unknown keyword under a property no value has is refused"
Check (Throws { Test-HordeSchema -Value (Obj '[]') -Schema (Obj '{ "items": { "maximum": 3 } }') } "the schema uses 'maximum' at #/items") "an unknown keyword under the items of an empty array is refused"
Check (Throws { Test-HordeSchema -Value "x" -Schema (Obj '{ "properties": { "q": { "maximum": 3 } } }') } "the schema uses 'maximum' at #/properties/q") "and under a property of a schema whose value is not an object at all"
Check (Throws { Test-HordeSchema -Value (Obj '{}') -Schema (Obj '{ "properties": { "q": { "type": "array", "items": { "$ref": "#/definitions/gone" } } } }') } "names no definition") "a dangling `$ref deep under a property no value has is found"
Check (Throws { Test-HordeSchema -Value (Obj '{}') -Schema (Obj '{ "properties": { "q": { "pattern": "(" } } }') } "pattern at #/properties/q is not a regular expression") "a pattern that does not compile, under a property no value has, is refused"
# A RECURSIVE SCHEMA STILL ENDS: the walk resolves a $ref and never follows it, so a tree whose root
# property refers back to a definition that refers to itself is walked once. A throw or a stack
# overflow here fails the check rather than the suite.
$f = @(RefFindings (Obj '{}') (Obj '{ "definitions": { "node": { "type": "object", "properties": { "kids": { "type": "array", "items": { "$ref": "#/definitions/node" } } } } }, "type": "object", "properties": { "tree": { "$ref": "#/definitions/node" }, "trees": { "type": "array", "items": { "$ref": "#/definitions/node" } } } }'))
Check ($f.Count -eq 0) ("CONTROL: a root whose properties refer to a recursive definition is walked and accepted (" + ($f -join "; ") + ")")
$f = @(RefFindings (Obj '{ "q": 1 }') (Obj '{ "type": "object", "properties": { "q": { "type": "integer" }, "r": { "type": "array", "items": { "type": "string", "pattern": "^a$" } } } }'))
Check ($f.Count -eq 0) ("CONTROL: a valid root with a property no value has is accepted (" + ($f -join "; ") + ")")
# A CALLER PASSING -Root HAS CHECKED THAT ROOT ALREADY, and is not made to pay for the walk again:
# core/Projection.ps1 on feature/core-projection checks one field's value this way, once per field per
# session. So a -Root call walks nothing, and a bad node elsewhere under that root is not its concern.
$checkedElsewhere = Obj '{ "properties": { "elsewhere": { "maximum": 3 } } }'
Check (-not (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "type": "integer" }') -Root $checkedElsewhere })) "a call with -Root does not walk that root again"

# EVERY SHIPPED SCHEMA PASSES THE CHECK OF ITS DEFINITIONS AND ITS ROOT'S SUBTREES: a throw here is the
# check refusing a schema Horde ships. The value is null, so only the schema itself is under test.
$shipped = @(Get-ChildItem -LiteralPath (Join-Path $root "schema") -Filter *.json -File)
Check ($shipped.Count -ge 3) ("CONTROL: the shipped schemas are there (" + $shipped.Count + ")")
foreach ($sf in $shipped) {
    $sName = $sf.BaseName
    Check (-not (Throws { Test-HordeSchema -Value $null -Schema (Get-HordeSchema -Name $sName) })) ("the shipped schema " + $sName + " passes the check of every node, its definitions and its root's subtrees")
}
Write-Host ""
Write-Host "--- what is worked out once per schema object stays with that object ---" -ForegroundColor Cyan
# core/Schema.ps1 caches each root's definitions and walk, and each node's keywords, keyed on the
# schema object (review of PR #31, where validating a view took 85 s). A cache is only right if it can
# never answer for another schema. Each call below turns a throw into a finding, so a wrong answer
# FAILS a check rather than crashing the suite.
$rootInt = Obj '{ "definitions": { "n": { "type": "integer" } }, "$ref": "#/definitions/n" }'
$rootStr = Obj '{ "definitions": { "n": { "type": "string" } }, "$ref": "#/definitions/n" }'
$f = @(RefFindings "x" $rootInt)
Check ($f.Count -eq 1 -and $f[0] -ceq '$ should be integer') ("a root whose n is an integer refuses a string (" + ($f -join "; ") + ")")
$f = @(RefFindings "x" $rootStr)
Check ($f.Count -eq 0) ("then a second root, same shape, whose n is a string, accepts it: its own definitions, not the first root's (" + ($f -join "; ") + ")")
$f = @(RefFindings 1 $rootStr)
Check ($f.Count -eq 1 -and $f[0] -ceq '$ should be string') ("and refuses a number (" + ($f -join "; ") + ")")
$f = @(RefFindings "x" $rootInt)
Check ($f.Count -eq 1 -and $f[0] -ceq '$ should be integer') ("and the first root still answers for itself (" + ($f -join "; ") + ")")
# ONE NODE OBJECT IN TWO SCHEMAS resolves its $ref against whichever root the call is under: the
# node's own keywords are cached, never the definition its $ref leads to.
$sharedNode = Obj '{ "$ref": "#/definitions/n" }'
$shareInt = [pscustomobject]@{ definitions = [pscustomobject]@{ n = (Obj '{ "type": "integer" }') }; properties = [pscustomobject]@{ a = $sharedNode } }
$shareStr = [pscustomobject]@{ definitions = [pscustomobject]@{ n = (Obj '{ "type": "string" }') }; properties = [pscustomobject]@{ a = $sharedNode } }
$f = @(RefFindings (Obj '{ "a": "x" }') $shareInt)
Check ($f.Count -eq 1 -and $f[0] -ceq '$.a should be integer') ("a node shared by two schemas follows the integer root's definition under it (" + ($f -join "; ") + ")")
$f = @(RefFindings (Obj '{ "a": "x" }') $shareStr)
Check ($f.Count -eq 0) ("and the string root's under that one (" + ($f -join "; ") + ")")
# A NEW SCHEMA OBJECT IS WALKED AFRESH. The first is valid; the second, parsed from text that differs
# by one unknown keyword in a definition nothing uses, must be refused though the first was walked.
$walkedGood = Obj '{ "definitions": { "unused": { "type": "integer" } }, "type": "integer" }'
$f = @(RefFindings 1 $walkedGood)
Check ($f.Count -eq 0) ("CONTROL: a valid schema is walked and accepted (" + ($f -join "; ") + ")")
Check (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "definitions": { "unused": { "type": "integer", "maximum": 3 } }, "type": "integer" }') } "does not implement") "a new schema object is walked afresh, though one of the same shape was walked before"
# A SCHEMA THAT FAILS FAILS EVERY TIME: only a walk that passed is remembered, so a $ref loop nothing
# reaches is refused on the second call as on the first.
$loopTwice = Obj '{ "definitions": { "a": { "$ref": "#/definitions/b" }, "b": { "$ref": "#/definitions/a" } }, "type": "integer" }'
Check (Throws { Test-HordeSchema -Value 1 -Schema $loopTwice } "circular") "a `$ref loop is refused on the first call"
Check (Throws { Test-HordeSchema -Value 1 -Schema $loopTwice } "circular") "and on the second call with the same schema object"
# -Root WALKS NOTHING, AND MARKS NOTHING WALKED: a later top-level call on that root still checks it.
$badRoot = Obj '{ "definitions": { "n": { "type": "integer" } }, "properties": { "q": { "maximum": 3 } } }'
Check (-not (Throws { Test-HordeSchema -Value 1 -Schema (Obj '{ "$ref": "#/definitions/n" }') -Root $badRoot })) "a call with -Root resolves against that root without walking it"
Check (Throws { Test-HordeSchema -Value (Obj '{}') -Schema $badRoot } "the schema uses 'maximum' at #/properties/q") "and a top-level call on that root afterwards still walks it"
# DOCUMENTED LIMIT (core/Schema.ps1): a schema edited IN PLACE after its first use is not re-read. The
# check holds the comment to the truth; a new object from the edited text is the supported way.
$edited = Obj '{ "definitions": { "n": { "type": "integer" } }, "$ref": "#/definitions/n" }'
$f = @(RefFindings 1 $edited)
Check ($f.Count -eq 0) ("CONTROL: before the edit, 1 is an integer (" + ($f -join "; ") + ")")
$edited.definitions.n.type = "string"
$f = @(RefFindings 1 $edited)
Check ($f.Count -eq 0) ("DOCUMENTED LIMIT: after an in-place edit the schema object answers as before (" + ($f -join "; ") + ")")
$f = @(RefFindings 1 (Obj '{ "definitions": { "n": { "type": "string" } }, "$ref": "#/definitions/n" }'))
Check ($f.Count -eq 1 -and $f[0] -ceq '$ should be string') ("and a new object from the edited text answers for the edit (" + ($f -join "; ") + ")")

Write-Host ""
Write-Host "--- minimum, compared exactly whatever type holds the number ---" -ForegroundColor Cyan
# Added so schema/session-record.v1 can say labelCycle is never negative, which until now was a
# writer's rule the schema could not state. Inclusive, as draft-07's minimum is.
$min0 = [pscustomobject]@{ minimum = 0 }
# (-1) in brackets: written bare as an argument, -1 is the STRING "-1" (measured 2026-09-30, 5.1).
Check (Has (Test-HordeSchema -Value (-1) -Schema $min0) '$ is -1, below the minimum 0') "a number below the minimum is refused"
Check (@(Test-HordeSchema -Value 0 -Schema $min0).Count -eq 0) "the minimum itself is accepted: minimum is inclusive"
Check (@(Test-HordeSchema -Value 5 -Schema $min0).Count -eq 0) "CONTROL: a number above the minimum is accepted"
Check (Has (Test-HordeSchema -Value (Read-JsonNumber "-0.5") -Schema $min0) '$ is -0.5, below the minimum 0') "a Decimal fraction below the minimum is refused"
Check (Has (Test-HordeSchema -Value ([int16]-1) -Schema $min0) '$ is -1, below the minimum 0') "an Int16, which the integer type accepts, is compared too"
# A VALUE THAT IS NOT A NUMBER IS THE TYPE CHECK'S JOB, never a second finding and never a throw.
Check (@(Test-HordeSchema -Value "-1" -Schema $min0).Count -eq 0) "minimum says nothing about a string"
Check (@(Test-HordeSchema -Value $true -Schema $min0).Count -eq 0) "minimum says nothing about a boolean"
$f = @(RefFindings "-1" ([pscustomobject]@{ type = "integer"; minimum = 0 }))
Check ($f.Count -eq 1 -and $f[0] -ceq '$ should be integer') ("a string under type integer and minimum is one finding, the type's (" + ($f -join "; ") + ")")
# THE MINIMUM ITSELF MUST BE A NUMBER. PowerShell compares "0" and $true with numbers by converting
# them, so a string or boolean minimum would work, wrongly, rather than fail.
Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ minimum = "0" }) } "minimum at $ must be a number") "a minimum given as a string is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ minimum = $true }) } "minimum at $ must be a number") "a minimum given as a boolean is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ minimum = $null }) } "minimum at $ must be a number") "a minimum given as null is refused"
Check (Throws { Test-HordeSchema -Value "x" -Schema ([pscustomobject]@{ type = "integer"; minimum = "0" }) } "minimum at $ must be a number") "a bad minimum is refused even when the value fails its type first"
Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ minimum = [double]::NaN }) } "minimum at $ must be a number") "a minimum that is NaN is refused"
# EXACT ACROSS TYPES. 5.1's ConvertFrom-Json reads 0.99999999999999999999 as a Decimal, and as a Double
# it is 1 (the ratio edge of core/RestorePlan.ps1, from the same review): comparing through [double]
# would call it equal to 1. So a Decimal and a Double are compared as the exact values they hold.
$nines = Read-JsonNumber "0.99999999999999999999"
$justOver = Read-JsonNumber "1.00000000000000000001"
Check ($nines -is [decimal] -and [double]$nines -eq 1 -and $justOver -is [decimal] -and [double]$justOver -eq 1) "CONTROL: 5.1 reads both as Decimal, and each is 1 as a Double"
Check (Has (Test-HordeSchema -Value $nines -Schema ([pscustomobject]@{ minimum = 1 })) '$ is 0.99999999999999999999, below the minimum 1') "a Decimal a hair below a whole-number minimum is refused"
# 1 - 2^-53, the largest Double below 1: it prints as 1 and [decimal] rounds it to 1 (15 significant
# digits), so only an exact comparison refuses it.
$f = @(RefFindings ([double]0.99999999999999989) ([pscustomobject]@{ minimum = 1 }))
Check ($f.Count -eq 1 -and $f[0] -clike '$ is *, below the minimum 1') ("a Double a hair below a whole-number minimum is refused (" + ($f -join "; ") + ")")
Check (@(Test-HordeSchema -Value 1.0e0 -Schema ([pscustomobject]@{ minimum = 1 })).Count -eq 0) "CONTROL: a Double equal to a whole-number minimum is accepted"
# A WHOLE-NUMBER MINIMUM MEANS ONE NUMBER HOWEVER THE JSON WROTE IT: 1, 1.0 (Decimal) and 1e0 (Double).
foreach ($t in @("1", "1.0", "1e0")) {
    $mt = [pscustomobject]@{ minimum = (Read-JsonNumber $t) }
    $f = @(RefFindings $nines $mt)
    Check ($f.Count -eq 1 -and $f[0] -clike '$ is 0.99999999999999999999, below the minimum *') ("minimum written " + $t + " refuses 0.99999999999999999999 (" + ($f -join "; ") + ")")
    $f = @(RefFindings 1 $mt)
    Check ($f.Count -eq 0) ("CONTROL: minimum written " + $t + " accepts 1 (" + ($f -join "; ") + ")")
}

# BEYOND DECIMAL'S RANGE IS A RESULT, NEVER A CRASH (the enum's lesson, second review of PR #16).
$f = @(RefFindings (Read-JsonNumber "1e30") $min0)
Check ($f.Count -eq 0) ("1e30 is above the minimum 0, and nothing throws (" + ($f -join "; ") + ")")
$f = @(RefFindings (Read-JsonNumber "-1e30") $min0)
Check ($f.Count -eq 1 -and $f[0] -clike '$ is *, below the minimum 0') ("-1e30 is below the minimum 0, and nothing throws (" + ($f -join "; ") + ")")
$f = @(RefFindings ([double]::NegativeInfinity) $min0)
Check ($f.Count -eq 1 -and $f[0] -clike '$ is *, below the minimum 0') ("negative infinity is below the minimum 0 (" + ($f -join "; ") + ")")
$f = @(RefFindings ([double]::NaN) $min0)
Check ($f.Count -eq 1 -and $f[0] -ceq '$ is NaN, which is not at or above the minimum 0') ("NaN is refused: it is at or above nothing (" + ($f -join "; ") + ")")

Write-Host ""
Write-Host "--- a minimum means the same number however the JSON wrote it (issue #25) ---" -ForegroundColor Cyan
# 5.1's ConvertFrom-Json reads 0.1 as a Decimal and 1e-1 as a Double, slightly more than one tenth.
# Compared exactly, {"minimum": 1e-1} refused the value 0.1 that {"minimum": 0.1} accepted (measured
# 2026-09-30, before the fix). So a minimum must be a whole number of magnitude at most 2^53 - 1, which every
# type the parser gives holds exactly; a fraction is refused, never normalised (see core/Schema.ps1).
Check ((Read-JsonNumber "0.1") -is [decimal] -and (Read-JsonNumber "1e-1") -is [double]) "CONTROL: 5.1 parses 0.1 as Decimal and 1e-1 as Double"
foreach ($t in @("0.1", "1e-1", "-0.5", "1.00000000000000000001")) {
    Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ minimum = (Read-JsonNumber $t) }) } "minimum at $ must be a whole number") ("a minimum written " + $t + " is refused: a fraction's meaning depends on how it was written")
}
# FROM 2^53 UP A WHOLE NUMBER DEPENDS ON ITS TEXT TOO: 9007199254740995.0 is a Decimal of that value,
# 9.007199254740995e15 the Double 9007199254740996, and 9.007199254740993e15 the Double 2^53. At
# 2^53 - 1 the two readings agree.
$safe = [long]9007199254740991
Check ((Compare-HordeSchemaNumber (Read-JsonNumber "9.007199254740993e15") ([long]9007199254740992)) -eq 0) "CONTROL: 5.1 reads 9.007199254740993e15 as 2^53, one less than it says"
Check ((Compare-HordeSchemaNumber (Read-JsonNumber "9007199254740991.0") (Read-JsonNumber "9.007199254740991e15")) -eq 0 -and (Compare-HordeSchemaNumber (Read-JsonNumber "9007199254740995.0") (Read-JsonNumber "9.007199254740995e15")) -ne 0) "CONTROL: 2^53 - 1 read as Decimal and as Double is one number; 2^53 + 3 is two"
foreach ($t in @("9007199254740995.0", "9.007199254740995e15", "9.007199254740993e15", "9007199254740992", "-9007199254740995.0", "-9007199254740992", "1e30")) {
    Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ minimum = (Read-JsonNumber $t) }) } "minimum at $ must be a whole number") ("a minimum written " + $t + ", beyond 2^53 - 1, is refused")
}
foreach ($m in @($safe, (-$safe), (Read-JsonNumber "9.007199254740991e15"), 0)) {
    Check (-not (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ minimum = $m }) })) ("CONTROL: a whole-number minimum of " + $m + ", within 2^53 - 1, is accepted")
}

Write-Host ""
Write-Host "--- every shape the census found is valid ---" -ForegroundColor Cyan
$valid = @(Get-ChildItem -LiteralPath (Join-Path $fx "valid") -Filter *.json -File)
Check ($valid.Count -ge 13) ("CONTROL: the valid fixtures are there (" + $valid.Count + ")")

# THE 11 KEY SETS OF THE CENSUS (2026-09-29, 163 files; count of files in brackets), each beyond the
# five keys every file has - session_id, transcript_path, cwd, hook_event_name, source. A key set with
# no fixture is a shape the suite never checks.
$censusSets = @(
    "",                                                                                      # [9]
    "model,session_title",                                                                   # [84]
    "model",                                                                                 # [26]
    "session_title",                                                                         # [17]
    "model,prompt_id,scratchpad_dir,session_title",                                          # [6]
    "model,scratchpad_dir",                                                                  # [5]
    "context_tokens,estimated_cache_write_usd,prompt_cache_likely_expired,scratchpad_dir,seconds_since_last_response,session_title", # [5]
    "model,prompt_id,scratchpad_dir",                                                        # [5]
    "context_tokens,estimated_cache_write_usd,prompt_cache_likely_expired,scratchpad_dir,seconds_since_last_response", # [4]
    "model,prompt_id,session_title",                                                         # [1]
    "model,scratchpad_dir,session_title"                                                     # [1]
)
$baseKeys = @("session_id", "transcript_path", "cwd", "hook_event_name", "source")
$fixtureSets = @{}
foreach ($f in $valid) {
    $names = @((Read-Fixture ("valid\" + $f.Name)).PSObject.Properties | ForEach-Object { $_.Name } | Where-Object { $baseKeys -cnotcontains $_ } | Sort-Object)
    $fixtureSets[($names -join ",")] = $f.BaseName
}
foreach ($k in $censusSets) {
    $label = $k; if ($k -eq "") { $label = "(the five keys only)" }
    Check ($fixtureSets.ContainsKey($k)) ("a fixture has the census key set " + $label)
}
# wezfleet writes its backfill records with ConvertTo-Json, so the real ones are multi-line (both on
# this machine, 2026-09-29); the fixture must be too.
$backfillText = Read-HordeSharedText -Path (Join-Path $fx "valid\wezfleet-backfill.json")
Check ($backfillText.Trim().Contains("`n") -and (Read-Fixture "valid\wezfleet-backfill.json").source -ceq "wezfleet-backfill") "the wezfleet-backfill fixture is multi-line, as ConvertTo-Json writes it"
foreach ($f in $valid) {
    $found = Findings (Read-Fixture ("valid\" + $f.Name))
    Check ($found.Count -eq 0) ("valid: " + $f.BaseName + $(if ($found.Count) { " (" + ($found -join "; ") + ")" } else { "" }))
}

Write-Host ""
Write-Host "--- a file that breaks what the readers rely on is not ---" -ForegroundColor Cyan
function Says { param([string]$Rel, [string]$Like) return (@(Findings (Read-Fixture $Rel) | Where-Object { $_ -like $Like }).Count -gt 0) }
Check (Says "invalid\no-session-id.json" '*has no ''session_id''*') "a file with no session id is invalid"
Check (Says "invalid\uppercase-session-id.json" '*has no ''session_id''*') "a file whose only id is SESSION_ID is invalid: resurrect's Lua looks up session_id case-sensitively"
Check (Says "invalid\bad-session-id.json" '*.session_id does not match*') "a session id that is not a UUID is invalid, as wezfleet's reader refuses it"
Check (Says "invalid\session-id-trailing-newline.json" '*.session_id does not match*') "a session id with a trailing newline is invalid"
Check (Says "invalid\wrong-event.json" '*.hook_event_name is*not one of*') "a file from any hook but SessionStart is invalid"
Check (Says "invalid\wrong-type.json" '*.context_tokens should be integer*') "a known field with the wrong type is invalid"
Check (Says "invalid\not-an-object.json" '*should be object*') "a file that is not an object is invalid"

Write-Host ""
Write-Host "--- and every real file on this machine is valid ---" -ForegroundColor Cyan

# THE SCHEMA DESCRIBES REALITY, OR IT IS WRONG. Read-only, through the shared read that never blocks
# a writer. A real file that fails means the schema must change, not the file.
$realDir = Join-Path $env:USERPROFILE ".claude\pane-sessions"
if (Test-Path -LiteralPath $realDir) {
    $real = @(Get-ChildItem -LiteralPath $realDir -File | Where-Object { $_.Extension -eq ".json" })
    $bad = @()
    foreach ($f in $real) {
        $v = $null
        try { $v = (Read-HordeSharedText -Path $f.FullName) | ConvertFrom-Json } catch { $bad += ($f.Name + ": not JSON"); continue }
        $found = @(Test-HordeSchema -Value $v -Schema $schema)
        if ($found.Count) { $bad += ($f.Name + ": " + ($found -join "; ")) }
    }
    Write-Host ("  measured: " + $real.Count + " real files, " + $bad.Count + " invalid") -ForegroundColor DarkGray
    foreach ($b in ($bad | Select-Object -First 5)) { Write-Host ("    " + $b) -ForegroundColor Red }
    Check ($real.Count -gt 0 -and $bad.Count -eq 0) "every real pane-sessions file on this machine passes the schema"
} else {
    Write-Host "  [SKIP] no ~/.claude/pane-sessions on this machine - the reality check did not run" -ForegroundColor Yellow
}

Complete-HordeSuite -Success "the schema describes the pane-sessions files as they are"
