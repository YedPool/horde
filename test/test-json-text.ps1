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


Write-Host ""
Write-Host "--- the byte check every data-file reader runs before it decodes ---" -ForegroundColor Cyan
function Refuses { param([byte[]]$B, [string]$Like) try { Assert-HordeAsciiBytes -Bytes $B -What "the file x"; return $false } catch { return ("" + $_.Exception.Message) -like $Like } }
$plain = [System.Text.Encoding]::ASCII.GetBytes("{" + [char]13 + [char]10 + [char]9 + '"a": 1 }')
Check (-not (Refuses $plain "*")) "CONTROL: plain ASCII with tab, CR and LF passes"
Check (Refuses ([byte[]](@(0xEF, 0xBB, 0xBF) + $plain)) "the file x starts with a UTF-8 byte-order mark*") "a byte-order mark is refused, named"
Check (Refuses ([byte[]](@(0x7B, 0xE9, 0x7D))) "the file x holds a byte that is not ASCII*") "a byte above 0x7F is refused, named"
Check (Refuses ([System.Text.Encoding]::Unicode.GetBytes('{"a": 1}')) "*control byte 0x00, as a file saved as UTF-16 does*") "a NUL is refused and named as a UTF-16 file"
Check (Refuses ([byte[]](@(0x7B, 0x07, 0x7D))) "*control byte 0x07;*") "another control byte is refused, named"
Check (-not (Refuses ([byte[]](@(0x7B, 0x09, 0x7D))) "*")) "CONTROL: a tab alone passes"

Write-Host ""
Write-Host "--- the one parse: a string in the text is a string in the result (issue #274) ---" -ForegroundColor Cyan
$stamp = "2026-10-14T12:00:00.0000000Z"
$sample = '{"at":"' + $stamp + '","typed":"2026-10-14T12:00:00Z","list":["' + $stamp + '"],"deep":{"rows":[{"at":"' + $stamp + '"}]},"n":5}'
$here51 = ConvertFrom-HordeJson $sample
Check ($here51.at -is [string] -and $here51.at -ceq $stamp -and $here51.typed -ceq "2026-10-14T12:00:00Z") ("in this shell (" + $PSVersionTable.PSEdition + " " + $PSVersionTable.PSVersion + "), a timestamp comes back as the text it was")
Check (@($here51.list).Count -eq 1 -and $here51.list[0] -ceq $stamp -and $here51.deep.rows[0].at -ceq $stamp -and $here51.n -eq 5) "so does one inside a one-item list and one inside a nested object; a number stays a number"
# A TOP-LEVEL ARRAY IS ONE ARRAY, as 5.1 gives it, in whichever shell runs this suite. The same shape
# from each shell's own process is checked below (Get-ShapeSignature in the probe).
function Get-ShapeSignature {
    $parts = foreach ($t in @('[1,2]', '[7]', '[]')) { $x = ConvertFrom-HordeJson $t; $t + ":" + @(ConvertFrom-HordeJson $t).Count + "/" + ($x -is [array]) + "/" + $(if ($null -eq $x) { "null" } else { $x.Count }) }
    return ($parts -join ";")
}
$wantShape = "[1,2]:1/True/2;[7]:1/True/1;[]:1/True/0"
$shapeHere = Get-ShapeSignature
Check ($shapeHere -ceq $wantShape) ("in this shell a top-level array is one array: @()-wrapped count 1, a one-element array stays an array, an empty one is an empty array (got '" + $shapeHere + "')")
Check (Throws { ConvertFrom-HordeJson '{"a":' }) "text that is not JSON throws, as ConvertFrom-Json does"
$reason = ""; try { $null = ConvertFrom-HordeJson '{ not json' } catch { $reason = $_.Exception.Message }
Check ($reason -clike "not JSON: *") ("the reason is the parser's own words, not wrapped by the method call (" + $reason + ")")
$caught = $false; try { $null = ConvertFrom-HordeJson 'not json' } catch { $caught = $true }
Check ($caught -eq $true) "a caller's try catches the throw from inside the seam"

# THE ONE STRICT PARSER (T-0366, M's option A): every case below has one answer, and each shell gives
# it - this one here, and 5.1 and pwsh each in its own process (the probe below). A case is its name and
# what came back: a type (an array as array[count](types)), or THROW.
function Get-StrictSignature {
    $deep = { param([int]$Levels) return (("[" * $Levels) + ("]" * $Levels)) }
    $cases = [ordered]@{
        "int" = '0'; "list" = '[5]'; "long" = '5000000000'; "fraction" = '1.5'; "written-point-zero" = '520.0'
        "past-long" = '99999999999999999999'; "exponent" = '1e3'; "minus-zero" = '-0'
        "too-large" = '1e400'; "trailing-comma-object" = '{"a":1,}'; "trailing-comma-array" = '[1,]'
        "leading-zero" = '01'; "plus" = '+1'; "bare-point" = '.5'; "point-no-digits" = '1.'; "nan" = 'NaN'
        "infinity" = 'Infinity'; "hex" = '0x10'; "single-quotes" = "{'a':1}"; "bare-key" = '{a:1}'
        "raw-tab" = ('"a' + [char]9 + 'b"'); "bom" = ([char]0xFEFF + '{"a":1}'); "comment" = '{"a":1 /* c */}'
        "nested-100" = (& $deep 100); "nested-101" = (& $deep 101); "spaced" = ' true '; "empty" = ''
        "two-values" = '1 2'; "escape" = '"\u00e9\n"'; "bad-escape" = '"\x"'; "u-escape-space" = '"\u 123"'
        "repeated-key" = '{"a":1,"a":"two"}'; "case-keys" = '{"a":1,"A":2}'; "empty-key" = '{"":1}'; "psobject-key" = '{"PSObject":1}'
    }
    $parts = foreach ($name in $cases.Keys) {
        $got = try {
            $r = ConvertFrom-HordeJson $cases[$name]
            if ($null -eq $r) { "null" }
            elseif ($r -is [array]) { "array[" + $r.Count + "](" + ((@($r) | ForEach-Object { if ($null -eq $_) { "null" } elseif ($_ -is [array]) { "array" } else { $_.GetType().Name } }) -join ",") + ")" }
            elseif ($r -is [System.Management.Automation.PSCustomObject]) { "object(" + ((@($r.PSObject.Properties) | ForEach-Object { $_.Name + "=" + $_.Value.GetType().Name + ":" + $_.Value }) -join ",") + ")" }
            elseif ($r -is [string]) { "String:" + ([int[]][char[]]$r -join ".") }
            else { $r.GetType().Name }
        } catch { "THROW" }
        $name + "=" + $got
    }
    return ($parts -join ";")
}
$wantStrict = (@(
    "int=Int32", "list=array[1](Int32)", "long=Int64", "fraction=Decimal", "written-point-zero=Decimal",
    "past-long=Decimal", "exponent=Double", "minus-zero=Int32",
    "too-large=THROW", "trailing-comma-object=THROW", "trailing-comma-array=THROW",
    "leading-zero=THROW", "plus=THROW", "bare-point=THROW", "point-no-digits=THROW", "nan=THROW",
    "infinity=THROW", "hex=THROW", "single-quotes=THROW", "bare-key=THROW",
    "raw-tab=THROW", "bom=THROW", "comment=THROW",
    "nested-100=array[1](array)", "nested-101=THROW", "spaced=Boolean", "empty=null",
    "two-values=THROW", "escape=String:233.10", "bad-escape=THROW", "u-escape-space=THROW",
    "repeated-key=object(a=String:two)", "case-keys=THROW", "empty-key=THROW", "psobject-key=THROW"
) -join ";")
$strictHere = Get-StrictSignature
$strictMiss = @(Compare-Object @($wantStrict -split ";") @($strictHere -split ";") | ForEach-Object { $_.InputObject + " " + $_.SideIndicator })
Check ($strictMiss.Count -eq 0) ("in this shell every strict case has its one answer (" + $(if ($strictMiss.Count -eq 0) { "all " + @($wantStrict -split ";").Count } else { "differs: " + ($strictMiss -join ", ") }) + ")")
Check ((ConvertFrom-HordeJson '{"at":"2026-10-28T06:00:00Z","n":[1,{"x":2.50}]}').n[1].x -ceq [decimal]"2.50") "CONTROL: a nested fraction keeps the digits it was written with, as 5.1's Decimal did"
Check (@(ConvertFrom-HordeJson @('{"a":', '1}')).Count -eq 1 -and (ConvertFrom-HordeJson @('{"a":', '1}')).a -eq 1) "lines given as a list are one text, as ConvertFrom-Json took them from the pipeline"
Check (Throws { ConvertFrom-HordeJson $null }) "no text at all throws, as ConvertFrom-Json refused it"

# EACH SHELL IN ITS OWN PROCESS: a child loads core/JsonText.ps1 and reports what the seam gives - the
# type of a parsed timestamp, the shape of a top-level array and every strict case. Windows PowerShell 5.1
# and pwsh each run it once, and each must give the one answer. Without pwsh the 7 half is NOT RUN, said loudly, and the
# suite exits 3, not 0.
$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
$partial = $false
$probe = Join-Path $env:TEMP ("horde-json-text-probe-" + [guid]::NewGuid().ToString("N") + ".ps1")
# The JSON goes through a file: 5.1 passing it as an argument to a native program drops its quotes.
$sampleFile = $probe + ".json"
[System.IO.File]::WriteAllText($sampleFile, $sample, (New-Object System.Text.UTF8Encoding($false)))
$probeText = @(
    'param([string]$Root, [string]$TextFile)'
    '. (Join-Path $Root "core\JsonText.ps1")'
    ('function Get-ShapeSignature {' + ${function:Get-ShapeSignature}.ToString() + '}')
    ('function Get-StrictSignature {' + ${function:Get-StrictSignature}.ToString() + '}')
    '$Text = [System.IO.File]::ReadAllText($TextFile)'
    '$o = ConvertFrom-HordeJson $Text'
    '$raw = $Text | ConvertFrom-Json'
    'Write-Output ("dates=raw=" + $raw.at.GetType().Name + ";at=" + $o.at.GetType().Name + "|" + $o.at + ";list=" + $o.list[0].GetType().Name + ";deep=" + $o.deep.rows[0].at)'
    'Write-Output ("shape=" + (Get-ShapeSignature))'
    'Write-Output ("strict=" + (Get-StrictSignature))'
) -join "`r`n"
[System.IO.File]::WriteAllText($probe, $probeText, (New-Object System.Text.UTF8Encoding($false)))
function Invoke-Probe {
    # { dates; shape; strict } from the probe run by -Exe.
    param([string]$Exe)
    $out = @(& $Exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe -Root $root -TextFile $sampleFile)
    $d = "" + (@($out | Where-Object { "$_".StartsWith("dates=") }) | Select-Object -First 1)
    $s = "" + (@($out | Where-Object { "$_".StartsWith("shape=") }) | Select-Object -First 1)
    $t = "" + (@($out | Where-Object { "$_".StartsWith("strict=") }) | Select-Object -First 1)
    return [pscustomobject]@{ dates = $d.Trim(); shape = $s.Trim(); strict = $t.Trim() }
}
try {
    $r = Invoke-Probe -Exe "powershell.exe"
    Check ($r.dates -ceq ("dates=raw=String;at=String|" + $stamp + ";list=String;deep=" + $stamp)) ("under 5.1 in its own process, a timestamp is text from both the cmdlet and the seam (got '" + $r.dates + "')")
    Check ($r.shape -ceq ("shape=" + $wantShape)) ("under 5.1 in its own process, a top-level array is one array (got '" + $r.shape + "')")
    Check ($r.strict -ceq ("strict=" + $wantStrict)) ("under 5.1 in its own process, every strict case has its one answer (got '" + $r.strict + "')")
    if ($null -eq $pwsh) {
        Write-Host "  [NOT RUN] POWERSHELL 7 IS NOT ON THIS MACHINE (no pwsh.exe): the parse under 7 was NOT checked here." -ForegroundColor Yellow
        $partial = $true
    } else {
        $r = Invoke-Probe -Exe $pwsh.Source
        Check ($r.dates -ceq ("dates=raw=DateTime;at=String|" + $stamp + ";list=String;deep=" + $stamp)) ("under pwsh, ConvertFrom-Json gives a DateTime and the seam gives the text (got '" + $r.dates + "')")
        Check ($r.shape -ceq ("shape=" + $wantShape)) ("under pwsh, a top-level array is one array, the same shape as 5.1 (got '" + $r.shape + "')")
        Check ($r.strict -ceq ("strict=" + $wantStrict)) ("under pwsh, every strict case has the same one answer as under 5.1 (got '" + $r.strict + "')")
    }
} finally { Remove-Item -LiteralPath $probe, $sampleFile -Force -ErrorAction SilentlyContinue }

if ($partial) { Complete-HordeSuite -Success "the scanner and the parse hold in this shell; the parse under PowerShell 7 was NOT RUN (no pwsh)" -PassCode 3 }
Complete-HordeSuite -Success "the one scanner finds every key written twice in one object, and nothing else; the one strict parse gives one answer under both shells"
