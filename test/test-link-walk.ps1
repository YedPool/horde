# DOES THE LINK WALK GIVE EXACTLY THE ANSWERS THE CODE IT REPLACED GAVE?
#
# fix/link-writer-speed replaced three recursive walks (Test-HordeLinkValue over Get-HordeLinkNodes,
# Test-HordeProtocolLimits) and the recursive writer (ConvertTo-HordeWireText) with one loop each, to
# make a frame of 256 session summaries cheap enough to send. They must refuse and accept exactly what
# the old code did, with the same words in the same order. The old code is kept, renamed, in
# test/fixtures/link-walk/reference.ps1; this suite runs both on the same inputs and compares:
#   - every fixture frame, and a variant of it for every member at every depth: removed, renamed by
#     case, joined by an extra member, and given values of every kind the wire can and cannot carry;
#   - the three contract documents (node manifest, overlay endpoint, transport capabilities), varied
#     the same way, through Test-HordeLinkValue without a kept record;
#   - the answer rules (Test-HordeLinkAnswer) on answers whose members are lists, nothing, or in the
#     wrong case;
#   - values only the writer meets: every nesting depth around its limit of 64, keys that need
#     escaping or are not strings, every number type, surrogate pairs whole and halved.
# test/test-link-walk-suites.ps1 makes the same comparison on every input every link suite uses.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "remote\Protocol.ps1")
. (Join-Path $root "test\fixtures\link-walk\reference.ps1")

$contract = Get-HordeLinkContract

function Outcome {
    # What a call gave, as one comparable text: its findings or text, or the refusal it threw.
    param([scriptblock]$Call)
    try { $r = @(& $Call); return ("ANSWER " + $r.Count + ":`n" + ($r -join "`n")) }
    catch { return ("THROW: " + $_.Exception.Message) }
}
function Copy-Deep { param($Value) return ((ConvertTo-Json -InputObject $Value -Depth 60 -Compress) | ConvertFrom-Json) }

$script:compared = 0
$script:differ = New-Object System.Collections.ArrayList
$script:refused = @{ frame = 0; caps = 0; text = 0; doc = 0; answer = 0; control = 0 }
function Compare-Pair {
    # One input through new and reference; a difference is kept with what produced it.
    param([string]$Kind, [string]$Label, [scriptblock]$New, [scriptblock]$Old)
    $a = Outcome $New
    $b = Outcome $Old
    $script:compared++
    if (-not [string]::Equals($a, $b, [System.StringComparison]::Ordinal)) { [void]$script:differ.Add($Kind + " " + $Label + "`n    new: " + ($a -replace "`n", " | ") + "`n    old: " + ($b -replace "`n", " | ")) }
    elseif (-not $a.StartsWith("ANSWER 0:")) { $script:refused[$Kind]++ }
}
function Compare-Frame {
    param($Frame, [string]$Label)
    $f = $Frame
    Compare-Pair "frame" $Label { Test-HordeLinkFrame -Frame $f -Contract $contract } { Test-HordeLinkFrameReference -Frame $f -Contract $contract }
    Compare-Pair "caps" $Label { Test-HordeProtocolLimits -Frame $f -Contract $contract } { Test-HordeProtocolLimitsReference -Frame $f -Contract $contract }
    Compare-Pair "text" $Label { ConvertTo-HordeWireText $f } { ConvertTo-HordeWireTextReference $f }
}

# Values of every kind a member can be given. Each node gets a rotating handful (all of them would
# take an hour against the reference); over the corpus every one is used many times.
$nul = "a" + [char]0 + "b"
$lone = "a" + [char]0xD800 + "b"
$pair = "a" + [char]0xD83D + [char]0xDE00 + "b"
$values = @(
    @{ n = "null"; v = { $null } }, @{ n = "empty"; v = { "" } }, @{ n = "word"; v = { "x" } },
    @{ n = "long text"; v = { "y" * 1100 } }, @{ n = "NUL"; v = { $nul } }, @{ n = "half pair"; v = { $lone } },
    @{ n = "whole pair"; v = { $pair } }, @{ n = "e-acute"; v = { "caf" + [char]0xE9 } }, @{ n = "quote and slash"; v = { 'a"b\c' } },
    @{ n = "bad time"; v = { "2026-02-30T00:00:00.000Z" } }, @{ n = "zero"; v = { 0 } }, @{ n = "minus one"; v = { -1 } },
    @{ n = "int64"; v = { [long]9007199254740993 } }, @{ n = "double"; v = { 1.5 } }, @{ n = "whole double"; v = { 1e3 } },
    @{ n = "decimal"; v = { [decimal]2.0 } }, @{ n = "true"; v = { $true } }, @{ n = "false"; v = { $false } },
    @{ n = "empty list"; v = { , @() } }, @{ n = "mixed list"; v = { , @(1, "a", $null) } },
    @{ n = "long list"; v = { , @(1..260 | ForEach-Object { "a" }) } }, @{ n = "empty object"; v = { [pscustomobject]@{} } },
    @{ n = "answer object"; v = { [pscustomobject]@{ state = "known" } } }, @{ n = "ordered dictionary"; v = { [ordered]@{ b = 1; a = "x" } } },
    @{ n = "number-keyed hashtable"; v = { @{ 1 = "x" } } }, @{ n = "datetime"; v = { [datetime]::UtcNow } },
    @{ n = "char"; v = { [char]'c' } }, @{ n = "nested objects"; v = { [pscustomobject]@{ a = [pscustomobject]@{ b = @([pscustomobject]@{ c = 1 }) } } } }
)

function Get-Paths {
    # Every member and list item in a parsed value, as steps from the top.
    param($Value, $Steps)
    $out = New-Object System.Collections.ArrayList
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in @($Value.PSObject.Properties)) {
            $s = @($Steps) + @(, @("m", $p.Name))
            [void]$out.Add($s)
            foreach ($x in @(Get-Paths -Value $p.Value -Steps $s)) { [void]$out.Add($x) }
        }
    } elseif ($Value -is [System.Collections.IList]) {
        for ($i = 0; $i -lt $Value.Count; $i++) {
            $s = @($Steps) + @(, @("i", $i))
            [void]$out.Add($s)
            foreach ($x in @(Get-Paths -Value $Value[$i] -Steps $s)) { [void]$out.Add($x) }
        }
    }
    # Each path is written out on its own; a path is itself a list of steps and stays one.
    return $out.ToArray()
}
function Get-Parent {
    param($Top, $Steps)
    $at = $Top
    for ($i = 0; $i -lt $Steps.Count - 1; $i++) { $st = $Steps[$i]; if ($st[0] -ceq "m") { $at = $at.PSObject.Properties[$st[1]].Value } else { $at = $at[$st[1]] } }
    return , $at
}
function Set-At {
    # A copy of Top with the value at Steps replaced (Value), removed (-Remove), renamed by case
    # (-Flip), or given a sibling (-Extra).
    param($Top, $Steps, $Value = $null, [switch]$Remove, [switch]$Flip, [switch]$Extra)
    $copy = Copy-Deep $Top
    $parent = Get-Parent -Top $copy -Steps $Steps
    $last = $Steps[$Steps.Count - 1]
    if ($last[0] -ceq "i") {
        if ($Remove) { $list = New-Object System.Collections.ArrayList; for ($i = 0; $i -lt $parent.Count; $i++) { if ($i -ne $last[1]) { [void]$list.Add($parent[$i]) } }; $parent = $list.ToArray() }
        elseif ($Flip -or $Extra) { return $null }
        else { $parent[$last[1]] = $Value }
        if ($Remove) {
            if ($Steps.Count -eq 1) { return $null }
            $gp = Get-Parent -Top $copy -Steps @($Steps[0..($Steps.Count - 2)])
            $ps = $Steps[$Steps.Count - 2]
            if ($ps[0] -ceq "m") { $gp.PSObject.Properties[$ps[1]].Value = $parent } else { $gp[$ps[1]] = $parent }
        }
        return $copy
    }
    $name = $last[1]
    if ($Extra) { $parent | Add-Member -NotePropertyName "zz" -NotePropertyValue "q" -Force; return $copy }
    if ($Remove) { $parent.PSObject.Properties.Remove($name); return $copy }
    if ($Flip) {
        $flipped = $name.Substring(0, 1).ToUpperInvariant() + $name.Substring(1)
        if ($flipped -ceq $name) { $flipped = $name.Substring(0, 1).ToLowerInvariant() + $name.Substring(1) }
        if ($flipped -ceq $name) { return $null }
        $old = $parent.PSObject.Properties[$name].Value
        $parent.PSObject.Properties.Remove($name)
        $parent | Add-Member -NotePropertyName $flipped -NotePropertyValue $old
        return $copy
    }
    $parent.PSObject.Properties[$name].Value = $Value
    return $copy
}
function Get-StepsText { param($Steps) return ((@($Steps) | ForEach-Object { if ($_[0] -ceq "m") { "." + $_[1] } else { "[" + $_[1] + "]" } }) -join "") }

Write-Host ""
Write-Host "--- every fixture frame, and every member of it varied ---" -ForegroundColor Cyan
$turn = 0
$frames = @(Get-ChildItem (Join-Path $root "test\fixtures\link\frames") -Filter *.json | Sort-Object Name)
foreach ($fx in $frames) {
    $frame = [System.IO.File]::ReadAllText($fx.FullName) | ConvertFrom-Json
    Compare-Frame $frame $fx.Name
    foreach ($steps in @(Get-Paths -Value $frame -Steps @())) {
        $where = $fx.Name + " " + (Get-StepsText $steps)
        foreach ($how in @("Remove", "Flip", "Extra")) {
            $sw = @{}; $sw[$how] = $true
            $v = Set-At -Top $frame -Steps $steps @sw
            if ($null -ne $v) { Compare-Frame $v ($where + " " + $how.ToLowerInvariant()) }
        }
        for ($k = 0; $k -lt 4; $k++) {
            $val = $values[($turn + $k * 7) % $values.Count]
            $v = Set-At -Top $frame -Steps $steps -Value (& $val.v)
            Compare-Frame $v ($where + " = " + $val.n)
        }
        $turn++
    }
}
Check ($frames.Count -ge 15) ("CONTROL: the corpus starts from the " + $frames.Count + " fixture frames")
Check ($script:refused.frame -ge 100 -and $script:refused.caps -ge 20 -and $script:refused.text -ge 20) ("CONTROL: the variants are refused often enough to compare refusals: frame " + $script:refused.frame + ", caps " + $script:refused.caps + ", writer " + $script:refused.text)

Write-Host ""
Write-Host "--- the contract documents, through Test-HordeLinkValue without a kept record ---" -ForegroundColor Cyan
foreach ($doc in @(@("manifest.json", "node-manifest.v1"), @("overlay.json", "overlay-endpoint.v1"), @("transport-local.json", "transport-capabilities.v1"))) {
    $value = [System.IO.File]::ReadAllText((Join-Path $root ("test\fixtures\link\" + $doc[0]))) | ConvertFrom-Json
    $name = $doc[1]
    $variants = New-Object System.Collections.ArrayList
    [void]$variants.Add(@($doc[0], $value))
    foreach ($steps in @(Get-Paths -Value $value -Steps @())) {
        foreach ($how in @("Remove", "Flip", "Extra")) { $sw = @{}; $sw[$how] = $true; $v = Set-At -Top $value -Steps $steps @sw; if ($null -ne $v) { [void]$variants.Add(@(($doc[0] + " " + (Get-StepsText $steps) + " " + $how), $v)) } }
        for ($k = 0; $k -lt 3; $k++) { $val = $values[($turn + $k * 5) % $values.Count]; [void]$variants.Add(@(($doc[0] + " " + (Get-StepsText $steps) + " = " + $val.n), (Set-At -Top $value -Steps $steps -Value (& $val.v)))) }
        $turn++
    }
    foreach ($pv in $variants) {
        $dv = $pv[1]
        Compare-Pair "doc" $pv[0] {
            $s = Get-HordeSchema -Name $name
            Test-HordeLinkValue -Value $dv -Schema $s -Node $s -Root $s -Path '$'
        } {
            $s = Get-HordeSchema -Name $name
            Test-HordeLinkValueReference -Value $dv -Schema $s -Node $s -Root $s -Path '$'
        }
    }
}
Check ($script:refused.doc -ge 10) ("CONTROL: document variants are refused, " + $script:refused.doc + " of them, so refusals are compared")

Write-Host ""
Write-Host "--- answers whose members are lists, nothing or the wrong case ---" -ForegroundColor Cyan
# The old rules read each member through a function, which unrolls a list it returns: an empty list
# was null to them. The corpus found the new rules disagreeing on exactly that (2026-10-02); these are
# the shapes around it, compared one by one.
$answers = @(
    @("an empty list value", [pscustomobject]@{ state = "known"; value = @(); observedAt = "t" }),
    @("a list of one null", [pscustomobject]@{ state = "known"; value = @($null); observedAt = "t" }),
    @("a list of one, and an empty time", [pscustomobject]@{ state = "known"; value = @(5); observedAt = @() }),
    @("a list of two, and a time in a list", [pscustomobject]@{ state = "known"; value = @(1, 2); observedAt = @("t") }),
    @("a dictionary with list members", [ordered]@{ state = "known"; value = @(); observedAt = @($null) }),
    @("an unknown with an empty list reason", [pscustomobject]@{ state = "unknown"; reason = @() }),
    @("a state that is a list", [pscustomobject]@{ state = @("unknown", "x"); reason = " " }),
    @("an absent with a null value", [pscustomobject]@{ state = "absent"; value = $null; observedAt = "t" }),
    @("members in upper case", [pscustomobject]@{ STATE = "KNOWN"; VALUE = 1 }),
    @("nothing", $null), @("text", "text"), @("a hashtable", @{ value = [pscustomobject]@{} })
)
foreach ($a in $answers) { $av = $a[1]; Compare-Pair "answer" $a[0] { Test-HordeLinkAnswer -Answer $av -Path '$.x' } { Test-HordeLinkAnswerReference -Answer $av -Path '$.x' } }

Write-Host ""
Write-Host "--- values only the writer meets ---" -ForegroundColor Cyan
$writer = New-Object System.Collections.ArrayList
foreach ($depth in @(1, 63, 64, 65, 66)) {
    $v = "leaf"; for ($i = 0; $i -lt $depth; $i++) { $v = , @($v) }; [void]$writer.Add(@(("lists " + $depth + " deep"), $v))
    $o = 1; for ($i = 0; $i -lt $depth; $i++) { $o = [pscustomobject]@{ a = $o } }; [void]$writer.Add(@(("objects " + $depth + " deep"), $o))
}
$keyed = [ordered]@{}; $keyed['b'] = 1; $keyed['B'] = 2; $keyed['_'] = 3; $keyed['a"q'] = 4; $keyed[('k' + [char]0xE9)] = 5
[void]$writer.Add(@("keys needing order and escapes", $keyed))
$nulKey = [ordered]@{}; $nulKey['ok'] = 1; $nulKey[$nul] = 2
[void]$writer.Add(@("a key holding a NUL", $nulKey))
[void]$writer.Add(@("a key that is not a string", @{ 1 = "x"; "a" = 2 }))
$early = [ordered]@{}; $early['a'] = 1.5; $early[$nul] = 1
[void]$writer.Add(@("a bad value before a bad key", $early))
$late = [ordered]@{}; $late['z'] = 1.5; $late[$lone] = 1
[void]$writer.Add(@("a bad key before a bad value", $late))
foreach ($t in @([sbyte]1, [byte]2, [int16]3, [uint16]4, [int]5, [uint32]6, [long]7, [uint64]8, [single]1, [double]2, [decimal]3)) { [void]$writer.Add(@(("a " + $t.GetType().Name), [pscustomobject]@{ n = $t })) }
[void]$writer.Add(@("every string kind", @("", "plain", $pair, $lone, $nul, ("tab" + [char]9), ("del" + [char]0x7F), 'q"\', ("e" + [char]0xE9))))
[void]$writer.Add(@("an empty object in an empty list", @(, [pscustomobject]@{})))
[void]$writer.Add(@("a dictionary in an object in a list", @([pscustomobject]@{ d = @{ y = $null; x = $true } })))
[void]$writer.Add(@("a guid", [guid]::NewGuid()))
foreach ($w in $writer) { $wv = $w[1]; Compare-Pair "text" $w[0] { ConvertTo-HordeWireText $wv } { ConvertTo-HordeWireTextReference $wv } }

Write-Host ""
Write-Host "--- the comparison ---" -ForegroundColor Cyan
foreach ($d in @($script:differ | Select-Object -First 15)) { Write-Host ("         " + $d) -ForegroundColor DarkYellow }
Check ($script:differ.Count -eq 0) ("new and old answer the same on all " + $script:compared + " inputs (" + $script:differ.Count + " differ)")
Check ($script:compared -ge 2000) ("CONTROL: " + $script:compared + " comparisons were made, not a handful")
# The comparison itself is checked on a pair known to differ, so a broken Outcome cannot pass it.
$before = $script:differ.Count
Compare-Pair "control" "a planted difference" { @("one finding") } { @("one finding", "and one more") }
Check ($script:differ.Count -eq $before + 1) "CONTROL: two answers that differ by one finding are told apart"
$before = $script:differ.Count
Compare-Pair "control" "a planted refusal" { throw "refused one way" } { throw "refused another way" }
Check ($script:differ.Count -eq $before + 1) "CONTROL: two refusals with different words are told apart"

Complete-HordeSuite -Success "the link walk and the writer answer exactly as the code they replaced, on every fixture frame, every variant of it, and every value only the writer meets"
