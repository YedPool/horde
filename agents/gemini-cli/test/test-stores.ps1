# IS THIS HARNESS'S FOLDER PROTECTED, THOUGH IT HAS NO TRANSCRIPT ADAPTER?
#
# Review of PR #50, F7: the write guard was built from the loaded adapters, and this harness has none,
# so a probe with HORDE_HOME set inside a fake profile's .gemini folder wrote two summaries there. The
# guard now reads agents/<name>/stores.json for every engine folder. This suite points USERPROFILE at a
# folder it creates and removes; the real profile is never touched.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "ReadShared", "Home", "Transcript", "MetricsStore")) { . (Join-Path $root ("core\" + $f + ".ps1")) }

$work = Join-Path $env:TEMP ("horde-gemini-stores-" + [guid]::NewGuid().ToString("N"))
$origProfile = $env:USERPROFILE
$origHome = $env:HORDE_HOME
try {
    $env:USERPROFILE = Join-Path $work "profile"
    $roots = Get-HordeAgentStoreRoots -Root $root
    $mine = Join-Path $env:USERPROFILE ".gemini"
    Check ($roots.state -eq "known" -and @($roots.value) -contains $mine) "the repository's own stores.json protects this harness's folder in the user profile"
    $gate = New-HordeKnown -Value ([pscustomobject]@{ level = "usage"; enabledAt = (ConvertTo-HordeUtcTime "2026-09-30T00:00:00Z") })
    $first = New-HordeKnown -Value (ConvertTo-HordeUtcTime "2026-10-01T00:00:00Z")
    $env:HORDE_HOME = Join-Path $mine "home"
    $d = Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt $first -RepoRoot $root
    Check ($d.write -eq $false -and $d.reason -like "*inside a harness*") "a Horde home inside it is refused, though no adapter for this harness is loaded"
    $env:HORDE_HOME = Join-Path $work "home"
    Check ((Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt $first -RepoRoot $root).write -eq $true) "CONTROL: a Horde home outside every engine's folder is allowed"
} finally {
    $env:USERPROFILE = $origProfile
    $env:HORDE_HOME = $origHome
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "this harness's folder is guarded from its stores.json, adapter or none"
