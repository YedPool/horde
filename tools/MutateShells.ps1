# tools/MutateShells.ps1 - the shells a mutation spec's suite runs in (T-0422).
#
# ONE RULE, TWO READERS: tools\Mutate.ps1 runs a spec by it, and test\test-mutation-specs.ps1 checks
# every spec in the repository against it, so a spec the tool would refuse fails that guard first
# instead of failing a review round.
#
# "pwsh" IS ONE FILE: where the PowerShell 7 MSI puts it (cli/SetupStore.ps1,
# Get-HordeSetupMsiPwshPath) - never the search path, a preview or the Store copy, which auto-updates
# and closes every pwsh.exe it runs (CONTRIBUTING 16).
# No Set-StrictMode here: this file is dot-sourced.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "cli\SetupStore.ps1")

$script:HordeMutateShellNames = @("powershell", "pwsh")

function Get-HordeMutateSpecShells {
    # The shells a spec names: { ok; shells; problem }. A spec that leaves Shells out runs under
    # Windows PowerShell 5.1 alone, as every spec did before Shells existed. An empty list, a name
    # that is not a shell, or a name given twice is refused: each would run something other than
    # what the spec seems to say.
    param([Parameter(Mandatory = $true)][hashtable]$Spec)
    if (-not $Spec.ContainsKey("Shells")) { return [pscustomobject]@{ ok = $true; shells = @("powershell"); problem = "" } }
    $list = @($Spec.Shells | ForEach-Object { "$_" })
    if ($list.Count -eq 0) { return [pscustomobject]@{ ok = $false; shells = @(); problem = "Shells is empty; leave it out to run under Windows PowerShell 5.1 alone" } }
    foreach ($n in $list) {
        if ($script:HordeMutateShellNames -cnotcontains $n) { return [pscustomobject]@{ ok = $false; shells = @(); problem = ("Shells names '" + $n + "'; a shell is ""powershell"" or ""pwsh""") } }
    }
    if (@($list | Select-Object -Unique).Count -ne $list.Count) { return [pscustomobject]@{ ok = $false; shells = @(); problem = ("Shells names a shell twice (" + ($list -join ", ") + ")") } }
    return [pscustomobject]@{ ok = $true; shells = $list; problem = "" }
}

function Get-HordeMutateShellExe {
    # The file to start a suite with under -Shell: { ok; exe; problem }. "powershell" is
    # powershell.exe, as this tool always started it; "pwsh" is the MSI's pwsh.exe, and a missing one
    # is a problem, never a fall back to 5.1.
    param([Parameter(Mandatory = $true)][string]$Shell)
    if ($Shell -ceq "powershell") { return [pscustomobject]@{ ok = $true; exe = "powershell.exe"; problem = "" } }
    $p = Get-HordeSetupMsiPwshPath
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        return [pscustomobject]@{ ok = $false; exe = ""; problem = ("PowerShell 7 is not at " + $p + " (the MSI install; the search path, a preview and the Store copy are never used)") }
    }
    return [pscustomobject]@{ ok = $true; exe = $p; problem = "" }
}
