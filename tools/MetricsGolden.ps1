# MetricsGolden.ps1 - write the golden output of `horde metrics summarize` for every fixture case.
#
#   powershell -File tools\MetricsGolden.ps1
#
# Run ONCE, at the commit whose output is to be pinned (M1, f16e5f6, on 2026-10-02), and again only
# when a change to the output is intended - and then the diff of the golden files is what a reviewer
# reads. test/test-metrics-golden.ps1 compares every later commit with these files. The cases and the
# normalisation are in test/lib/MetricsGolden.ps1.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $root "test\lib\MetricsGolden.ps1")
$home2 = Join-Path $env:TEMP ("horde-golden-" + [guid]::NewGuid().ToString("N"))
try {
    foreach ($c in (Get-HordeMetricsGoldenCases -Root $root)) {
        $r = Invoke-HordeMetricsGoldenCase -Root $root -Case $c -HordeHome $home2
        if ($r.code -ne 0) { throw ("the command failed for " + $c.agent + "/" + $c.name + " (exit " + $r.code + "): " + $r.err) }
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $c.golden))
        [System.IO.File]::WriteAllText($c.golden, $r.text, (New-Object System.Text.UTF8Encoding($false)))
        Write-Output ("wrote " + $c.agent + "/" + $c.name)
    }
    if (Test-Path -LiteralPath $home2) { throw ("the golden runs wrote into the home " + $home2 + "; nothing should have been recorded") }
} finally { Remove-Item -LiteralPath $home2 -Recurse -Force -ErrorAction SilentlyContinue }
