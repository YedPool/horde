# tools/nightly/pytest-wrap.ps1 - pytest and flake8 for a Python repo, for the nightly net (T-0331).
# HeavySlot starts this under Windows PowerShell 5.1. Modes:
#   -Mode all    the whole suite from the tree's root; the failing node ids (one per line, FAILED or ERROR) go to -NodesFile,
#                and the exit code is 0 when nothing failed, 1 when something did. A repo with a failing baseline is
#                judged by DIFFERENCE between nights, never by this exit code alone (the night's report does that).
#                Any other outcome exits 70 (pytest crashed, was interrupted, found nothing, or exited 1 without naming a failing
#                node) or 71 (python is missing) and writes NO nodes file: the net reads that as the run not done, never green.
#   -Mode nodes  only the node ids listed in -NodesFile (one per line), the way a bisect asks; exit 0 green, 1 red,
#                and 4 or 5 (pytest found nothing to run: the test is not in this commit) is passed on for the caller to read.
#   -Mode flake8 the critical flake8 classes (E9, F63, F7, F82) over the whole tree; exit 0 clean, 1 findings.
# python is run WITHOUT -I (isolated mode hides pytest's plugins from the path, found 2026-10-15).
param(
    [Parameter(Mandatory = $true)][string]$Tree,
    [Parameter(Mandatory = $true)][ValidateSet("all", "nodes", "flake8")][string]$Mode,
    [string]$NodesFile = "",
    [string]$Ignore = "backend"
)
Set-Location -LiteralPath $Tree
if ($null -eq (Get-Command python -ErrorAction SilentlyContinue)) { Write-Output "pytest-wrap: python is not on the PATH"; exit 71 }
if ($Mode -ceq "flake8") {
    & python -m flake8 --select=E9,F63,F7,F82 --exclude=.git,node_modules,venv,.venv .
    exit $(if ($LASTEXITCODE -eq 0) { 0 } else { 1 })
}
if ($Mode -ceq "nodes") {
    $nodes = @(Get-Content -LiteralPath $NodesFile | Where-Object { $_.Trim() -ne "" })
    & python -m pytest -q -p no:cacheprovider @nodes
    exit $LASTEXITCODE
}
$lines = @(& python -m pytest -q -p no:cacheprovider --ignore=$Ignore --continue-on-collection-errors -rfE)
$code = $LASTEXITCODE
$lines | ForEach-Object { Write-Output $_ }
$failed = @($lines | Where-Object { $_ -match '^(FAILED|ERROR) ' } | ForEach-Object { ($_ -replace '^(FAILED|ERROR) ', '') -replace ' - .*$', '' } | Sort-Object -Unique)
if ($code -eq 0) { [System.IO.File]::WriteAllText($NodesFile, "`n"); exit 0 }
if ($code -eq 1 -and $failed.Count -gt 0) { [System.IO.File]::WriteAllText($NodesFile, (($failed -join "`n") + "`n")); exit 1 }
Write-Output ("pytest-wrap: pytest exited " + $code + " with " + $failed.Count + " failing nodes named: not a verdict")
exit 70
