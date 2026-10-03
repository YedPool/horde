# IS `horde metrics summarize` STILL SAYING, BYTE FOR BYTE, WHAT M1 SAID?
#
# Every fixture case (test/lib/MetricsGolden.ps1) is run through the shipped command, as its own
# process, and compared with the golden file M1's own command wrote at f16e5f6 (tools/MetricsGolden.ps1).
# Plan step M2 changed how a transcript is held in memory and nothing it says; a difference here is a
# change in what summarize says, and needs the golden file changed in the same commit, where a reviewer
# sees it.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\MetricsGolden.ps1")

$work = Join-Path $env:TEMP ("horde-golden-" + [guid]::NewGuid().ToString("N"))
try {
    $cases = @(Get-HordeMetricsGoldenCases -Root $root)
    Check ($cases.Count -ge 10) ("CONTROL: the fixture cases are found (" + $cases.Count + ")")
    Check (@($cases | Where-Object { $_.json }).Count -ge 4 -and @($cases | Where-Object { $_.name -like "folder__*" }).Count -ge 2) "and they include -Json runs and whole-folder runs"
    foreach ($c in $cases) {
        $has = Test-Path -LiteralPath $c.golden -PathType Leaf
        Check $has ("the case " + $c.agent + "/" + $c.name + " has a golden file")
        if (-not $has) { continue }
        # Normalised as well: a fresh checkout with core.autocrlf gives the golden file CRLF endings.
        $want = ConvertTo-HordeMetricsGoldenText ([System.IO.File]::ReadAllText($c.golden))
        $got = Invoke-HordeMetricsGoldenCase -Root $root -Case $c -HordeHome (Join-Path $work "home")
        $same = ($got.code -eq 0 -and $got.text -ceq $want)
        if (-not $same) {
            $wl = $want -split "`n"; $gl = $got.text -split "`n"; $at = 0
            while ($at -lt $wl.Count -and $at -lt $gl.Count -and $wl[$at] -ceq $gl[$at]) { $at++ }
            Write-Host ("    first difference at line " + ($at + 1) + " (exit " + $got.code + ")")
            if ($at -lt $wl.Count) { Write-Host ("    golden: " + $wl[$at]) }
            if ($at -lt $gl.Count) { Write-Host ("    now:    " + $gl[$at]) }
            if ($got.err) { Write-Host ("    stderr: " + $got.err) }
        }
        Check $same ($c.agent + "/" + $c.name + ": the output is byte for byte the golden file")
    }
    Check (-not (Test-Path -LiteralPath (Join-Path $work "home"))) "and with no gate, nothing was written to the home"

    # CONTROL: the comparison can see a difference of one character.
    $first = $cases[0]
    $copy = Join-Path $work "golden-copy.txt"
    [void][System.IO.Directory]::CreateDirectory($work)
    $txt = [System.IO.File]::ReadAllText($first.golden)
    $changed = $txt.Substring(0, $txt.Length - 2) + $(if ($txt[$txt.Length - 2] -ceq "x") { "y" } else { "x" }) + $txt.Substring($txt.Length - 1)
    $got1 = Invoke-HordeMetricsGoldenCase -Root $root -Case $first -HordeHome (Join-Path $work "home")
    Check ($got1.text -cne $changed) "CONTROL: an output one character away from the golden file is not taken as the same"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "summarize says, byte for byte, what M1 said on every fixture"
