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
$caught = $false; try { $null = ConvertFrom-HordeJson 'not json' } catch { $caught = $true }
Check ($caught -eq $true) "a caller's try catches the throw from inside the seam"

# THE 7.0 TO 7.4 FALLBACK, IN THIS SHELL: the walk is given what such a shell's parser gives - [datetime]
# values - and must give back the "o" text Horde wrote.
$utc = [datetime]::new(2026, 10, 14, 12, 0, 0, [System.DateTimeKind]::Utc)
$parsedAsDates = [pscustomobject]@{ at = $utc; list = @($utc); deep = [pscustomobject]@{ rows = @([pscustomobject]@{ at = $utc }) }; n = 5; s = "plain" }
$walked = ConvertTo-HordeJsonDateText -Value $parsedAsDates
Check ($walked.at -is [string] -and $walked.at -ceq $stamp) "the fallback turns a UTC [datetime] back into exactly the round-trip text Horde writes"
Check (@($walked.list).Count -eq 1 -and $walked.list[0] -ceq $stamp -and $walked.deep.rows[0].at -ceq $stamp) "the fallback reaches into a one-item list and a nested object's list"
Check ($walked.n -eq 5 -and $walked.s -ceq "plain") "the fallback leaves numbers and plain strings alone"
$offset = [datetimeoffset]::new($utc)
Check ((ConvertTo-HordeJsonDateText -Value $offset) -ceq "2026-10-14T12:00:00.0000000+00:00") "a [datetimeoffset] is written back as round-trip text too"

# EACH SHELL IN ITS OWN PROCESS: a child loads core/JsonText.ps1 and reports what the seam gives - the
# type of a parsed timestamp and the shape of a top-level array. Windows PowerShell 5.1 runs it once;
# pwsh, where the bug lives, runs it through its own -DateKind path and through the fallback path forced
# on. Every shell must give 5.1's array shape. Without pwsh the 7 half is NOT RUN, said loudly, and the
# suite exits 3, not 0.
$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
$partial = $false
$probe = Join-Path $env:TEMP ("horde-json-text-probe-" + [guid]::NewGuid().ToString("N") + ".ps1")
# The JSON goes through a file: 5.1 passing it as an argument to a native program drops its quotes.
$sampleFile = $probe + ".json"
[System.IO.File]::WriteAllText($sampleFile, $sample, (New-Object System.Text.UTF8Encoding($false)))
$probeText = @(
    'param([string]$Root, [string]$TextFile, [string]$Force)'
    '. (Join-Path $Root "core\JsonText.ps1")'
    ('function Get-ShapeSignature {' + ${function:Get-ShapeSignature}.ToString() + '}')
    '$Text = [System.IO.File]::ReadAllText($TextFile)'
    'if ($Force -eq "fallback") { $script:HordeJsonDateKind = $false }'
    '$o = ConvertFrom-HordeJson $Text'
    '$raw = $Text | ConvertFrom-Json'
    'Write-Output ("dates=raw=" + $raw.at.GetType().Name + ";at=" + $o.at.GetType().Name + "|" + $o.at + ";list=" + $o.list[0].GetType().Name + ";deep=" + $o.deep.rows[0].at)'
    'Write-Output ("shape=" + (Get-ShapeSignature))'
) -join "`r`n"
[System.IO.File]::WriteAllText($probe, $probeText, (New-Object System.Text.UTF8Encoding($false)))
function Invoke-Probe {
    # { dates; shape } from the probe run by -Exe with -Force own or fallback.
    param([string]$Exe, [string]$Force)
    $out = @(& $Exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe -Root $root -TextFile $sampleFile -Force $Force)
    $d = "" + (@($out | Where-Object { "$_".StartsWith("dates=") }) | Select-Object -First 1)
    $s = "" + (@($out | Where-Object { "$_".StartsWith("shape=") }) | Select-Object -First 1)
    return [pscustomobject]@{ dates = $d.Trim(); shape = $s.Trim() }
}
try {
    $r = Invoke-Probe -Exe "powershell.exe" -Force "own"
    Check ($r.dates -ceq ("dates=raw=String;at=String|" + $stamp + ";list=String;deep=" + $stamp)) ("under 5.1 in its own process, a timestamp is text from both the cmdlet and the seam (got '" + $r.dates + "')")
    Check ($r.shape -ceq ("shape=" + $wantShape)) ("under 5.1 in its own process, a top-level array is one array (got '" + $r.shape + "')")
    if ($null -eq $pwsh) {
        Write-Host "  [NOT RUN] POWERSHELL 7 IS NOT ON THIS MACHINE (no pwsh.exe): the parse under 7 was NOT checked here." -ForegroundColor Yellow
        $partial = $true
    } else {
        foreach ($force in @("own", "fallback")) {
            $r = Invoke-Probe -Exe $pwsh.Source -Force $force
            Check ($r.dates -ceq ("dates=raw=DateTime;at=String|" + $stamp + ";list=String;deep=" + $stamp)) ("under pwsh, " + $force + " path: ConvertFrom-Json gives a DateTime and the seam gives the text (got '" + $r.dates + "')")
            Check ($r.shape -ceq ("shape=" + $wantShape)) ("under pwsh, " + $force + " path: a top-level array is one array, the same shape as 5.1 (got '" + $r.shape + "')")
        }
    }
} finally { Remove-Item -LiteralPath $probe, $sampleFile -Force -ErrorAction SilentlyContinue }

if ($partial) { Complete-HordeSuite -Success "the scanner and the parse hold in this shell; the parse under PowerShell 7 was NOT RUN (no pwsh)" -PassCode 3 }
Complete-HordeSuite -Success "the one scanner finds every key written twice in one object, and nothing else; the one parse keeps every string a string under both shells"
