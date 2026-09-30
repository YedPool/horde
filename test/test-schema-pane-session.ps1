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
Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ minimum = 3 }) } "does not implement") "a schema keyword the validator does not implement is refused, never silently skipped"
Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ type = "decimal" }) } "does not know") "an unknown type name is refused"
# A rule the validator cannot apply is refused, never read as "anything goes". Draft-07 allows
# additionalProperties to be a schema and allows a schema to be true or false; this validator does not
# implement either, and the first version accepted everything for both (review of PR #15).
$oneKey = [pscustomobject]@{ a = 1 }
Check (Throws { Test-HordeSchema -Value $oneKey -Schema ([pscustomobject]@{ additionalProperties = [pscustomobject]@{ type = "string" } }) } "additionalProperties at $ must be true or false") "additionalProperties given as a schema is refused"
Check (Throws { Test-HordeSchema -Value $oneKey -Schema ([pscustomobject]@{ additionalProperties = 0 }) } "additionalProperties at $ must be true or false") "additionalProperties 0 is refused, not read as false"
Check (Throws { Test-HordeSchema -Value $oneKey -Schema $false } "the schema at $ is not an object") "a boolean schema is refused"
Check (Throws { Test-HordeSchema -Value $oneKey -Schema ([pscustomobject]@{ properties = [pscustomobject]@{ a = $true } }) } "the schema at $.a is not an object") "a boolean schema under properties is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema "integer" } "the schema at $ is not an object") "a schema that is a string is refused"
# x- keys: the check must FAIL, not crash, when they stop being ignored - a crash is an [ERROR], which
# tools/Mutate.ps1 rightly does not count as caught. So the call is caught here and its result judged.
$xFound = $null; $xThrew = $false
try { $xFound = @(Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ type = "integer"; "x-note" = "anything" })) } catch { $xThrew = $true }
Check ((-not $xThrew) -and $xFound.Count -eq 0) "x- keys are documentation and are ignored"
Check (Has (Test-HordeSchema -Value "a" -Schema ([pscustomobject]@{ enum = @("A") })) "$ is 'a', not one of: A") "enum compares strings case-sensitively"
Check (@(Test-HordeSchema -Value "b" -Schema ([pscustomobject]@{ enum = @("a", "b") })).Count -eq 0) "CONTROL: a string the enum names is accepted"
Check (Has (Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ enum = @("1") })) "$ is '1', not one of: 1") "a number is not the string of its digits"
# ENUM HOLDS STRINGS ONLY. The first version compared other values as text: $null threw, 1 and 1.0
# differed, and objects were compared by their string form (review of PR #15). Horde's schemas need
# only string enums, so anything else is refused - even when the value's type already failed.
Check (Throws { Test-HordeSchema -Value "x" -Schema ([pscustomobject]@{ enum = @($null) }) } "enum at $ may hold only strings") "a null in an enum is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ enum = @(1) }) } "enum at $ may hold only strings") "a number in an enum is refused"
Check (Throws { Test-HordeSchema -Value "x" -Schema ([pscustomobject]@{ enum = @([pscustomobject]@{ a = 1 }) }) } "enum at $ may hold only strings") "an object in an enum is refused"
Check (Throws { Test-HordeSchema -Value 1 -Schema ([pscustomobject]@{ type = "string"; enum = @(1) }) } "enum at $ may hold only strings") "a bad enum is refused even when the value fails its type first"
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
# A value built in PowerShell may hold a list as an ArrayList rather than an array.
$listSchema = [pscustomobject]@{ type = "object"; properties = [pscustomobject]@{ list = [pscustomobject]@{ type = "array"; items = $intSchema } } }
Check (@(Test-HordeSchema -Value @{ list = [System.Collections.ArrayList]@(1, 2) } -Schema $listSchema).Count -eq 0) "an ArrayList is an array"
Check (Has (Test-HordeSchema -Value @{ list = [System.Collections.ArrayList]@(1, "x") } -Schema $listSchema) '$.list`[1`] should be integer') "items checks every element of an ArrayList"

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
