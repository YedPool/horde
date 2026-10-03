# DOES HORDE'S ONE DUPLICATE-KEY SCANNER FIND EVERY KEY WRITTEN TWICE IN ONE OBJECT, AND ONLY THOSE?
#
# core/JsonText.ps1. ConvertFrom-Json in Windows PowerShell 5.1 keeps one of two equal keys and says
# nothing, so a file can show its reader one value and give Horde another. The ownership table
# (core/Ownership.ps1) and the permission-level vocabulary (core/PermissionLevels.ps1) both refuse
# such text, through this one scanner. Until 2026-10-02 each had a scanner of its own under the same
# function name, and whichever loaded last would have answered for both.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\JsonText.ps1")

function Dups { param([string]$Text) return @(Find-HordeJsonDuplicateKey -Text $Text) }
function Finds { param([string]$Text, [string]$Like) return (@(Dups $Text | Where-Object { $_ -like $Like }).Count -gt 0) }

Write-Host ""
Write-Host "--- loading the module ---" -ForegroundColor Cyan
$strictKept = & { Set-StrictMode -Version Latest; . (Join-Path $root "core\JsonText.ps1"); try { $null = $hordeNeverAssignedVariable; $false } catch { $true } }
Check ($strictKept -eq $true) "dot-sourcing core/JsonText leaves the caller's strict mode on"

Write-Host ""
Write-Host "--- a key written twice in one object is found ---" -ForegroundColor Cyan
Check (@(Dups '{"a":1,"b":2}').Count -eq 0) "control: distinct keys are not duplicates"
Check (Finds '{"a":1,"a":2}' "key 'a' appears more than once in one object (top level)") "a key written twice at the top level is found, and where"
Check (Finds '{"name":1,"Name":2}' "key 'Name' appears more than once*") "keys that differ only in case are one key, as PowerShell reads properties"
Check (Finds '{"name":1,"\u006eame":2}' "key 'name' appears more than once*") "a key spelled with an escape is decoded before it is compared"
Check (Finds '{"x":{"a":1,"a":2}}' "*(x)") "a duplicate inside a nested object names that object"
Check (Finds '{"l":[{"a":1},{"a":2,"a":3}]}' '*(l`[1`])') "a duplicate inside an array's second object names its index"

Write-Host ""
Write-Host "--- only keys, and only within one object ---" -ForegroundColor Cyan
Check (@(Dups '{"l":[{"a":1},{"a":2}]}').Count -eq 0) "the same key in two objects of a list is not a duplicate"
Check (@(Dups '{"x":{"a":1},"a":2}').Count -eq 0) "the same key in an object and its parent is not a duplicate"
Check (@(Dups '{"a":"a","b":"a"}').Count -eq 0) "a value equal to a key is not a key"
Check (@(Dups '{"a":"say \"b\": 1","b":2}').Count -eq 0) "a key-like text inside a string, with escaped quotes, is not a key"
Check (@(Dups '{"a":[1,2,"a"],"b":{"c":"a"}}').Count -eq 0) "values in lists and nested objects are not keys"
Check (Finds '{"a":"x\"","a":1}' "key 'a' appears more than once*") "a key after a value holding an escaped quote is still checked"
Check (Finds '{"a":[1,2],"b":3,"a":4}' "key 'a' appears more than once*") "a key after a list value is still checked"
Check (Finds '{"a":{"x":1},"b":3,"a":4}' "key 'a' appears more than once*") "a key after an object value is still checked"
function Survives { param([string]$Text) try { $null = @(Dups $Text); return $true } catch { return $false } }
Check ((Survives '{"a\') -and (Survives '{"a":"x\') -and (Survives '{"a') -and @(Dups '{"a\').Count -eq 0) "an unterminated string ends the scan without an error; the parser refuses it"
Check ((Survives '{"\x":1}') -and @(Dups '{"\x":1}').Count -eq 0) "a key with a bad escape is compared as written, without an error"
Check (Finds '{"\x":1,"\x":2}' "*appears more than once*") "a key with a bad escape written twice is still found"
Check ((Survives 'a,b') -and (Survives '{"a":1}}') -and (Survives ']]') -and @(Dups '{"a":1}}').Count -eq 0) "stray commas and closing brackets outside any object are not an error"
Check (@(Dups '').Count -eq 0 -and @(Dups '[1,2]').Count -eq 0 -and @(Dups '"text"').Count -eq 0) "text with no object has no duplicate"

Complete-HordeSuite -Success "the one scanner finds every key written twice in one object, and nothing else"
