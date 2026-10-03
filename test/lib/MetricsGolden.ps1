# test/lib/MetricsGolden.ps1 - the cases of `horde metrics summarize` whose output is pinned.
#
# WHY. Plan step M2 rewrote how summarize holds a transcript in memory (running totals instead of one
# record per line), and the coordinator's condition was that its output stay byte for byte what M1's
# was (2026-10-02). These golden files were written by M1's own command, at f16e5f6, before any M2
# change (tools/MetricsGolden.ps1), so every later change is compared with what M1 shipped, not with a
# reconstruction of it (CONTRIBUTING 6).
#
# THE CASES are found, never named (CONTRIBUTING 14): every .jsonl under agents/<name>/test/fixtures/metrics,
# summarised alone, as the table and as -Json; and every folder directly under that, summarised whole.
# The golden file of a case is agents/<name>/test/golden/metrics/<case>.txt.
#
# WHAT IS NORMALISED, and only this: line endings; the value of writtenAt, which is the clock at the
# moment of writing; and the engine folder in a price table's path, agents/<engine>/prices.json,
# because the table's cost line names every engine's table and a golden file lives in one engine's
# folder (CONTRIBUTING 14). Nothing is recorded (the home has no gate), so no path to the home appears.

function Get-HordeMetricsGoldenCases {
    param([Parameter(Mandatory = $true)][string]$Root)
    $cases = New-Object System.Collections.ArrayList
    foreach ($agent in @(Get-ChildItem -LiteralPath (Join-Path $Root "agents") -Directory | Sort-Object Name)) {
        $fx = Join-Path $agent.FullName "test\fixtures\metrics"
        if (-not (Test-Path -LiteralPath $fx -PathType Container)) { continue }
        $golden = Join-Path $agent.FullName "test\golden\metrics"
        foreach ($f in @(Get-ChildItem -LiteralPath $fx -File -Recurse | Where-Object { $_.Extension -ieq ".jsonl" } | Sort-Object FullName)) {
            $rel = $f.FullName.Substring($fx.Length + 1)
            $key = ($rel -replace '[\x5C/]', '__')
            foreach ($json in @($false, $true)) {
                $name = $key + $(if ($json) { ".json" } else { ".table" })
                [void]$cases.Add([pscustomobject]@{ agent = $agent.Name; name = $name; path = $f.FullName; json = $json; golden = (Join-Path $golden ($name + ".txt")) })
            }
        }
        foreach ($d in @(Get-ChildItem -LiteralPath $fx -Directory | Sort-Object Name)) {
            $name = "folder__" + $d.Name + ".table"
            [void]$cases.Add([pscustomobject]@{ agent = $agent.Name; name = $name; path = $d.FullName; json = $false; golden = (Join-Path $golden ($name + ".txt")) })
        }
    }
    return @($cases)
}

function Invoke-HordeMetricsGoldenCase {
    # Run the shipped command for one case, as its own process, under a home with no gate; returns the
    # normalised output and the exit code.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)]$Case, [Parameter(Mandatory = $true)][string]$HordeHome)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $Root "horde.ps1") + "`" metrics summarize `"" + $Case.path + "`"" + $(if ($Case.json) { " -Json" } else { "" })
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_HOME"] = $HordeHome
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $code = $p.ExitCode
    $p.Dispose()
    return [pscustomobject]@{ code = $code; text = (ConvertTo-HordeMetricsGoldenText $out); err = $errTask.Result }
}

function ConvertTo-HordeMetricsGoldenText {
    param([string]$Text)
    $t = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    $t = $t -replace '"writtenAt":\s+"[^"]*"', '"writtenAt": "<writtenAt>"'
    # The table's cost line names every engine's price table, so a golden file in one engine's folder
    # would name the others (CONTRIBUTING 14). The folder is replaced; the file and version are kept.
    return ($t -replace 'agents/[a-z0-9-]+/prices\.json', 'agents/<engine>/prices.json')
}
