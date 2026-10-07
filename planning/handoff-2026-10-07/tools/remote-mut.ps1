# msg mutations: named specs of one commit on the always-on box.
param([Parameter(Mandatory = $true)][string]$Repo, [Parameter(Mandatory = $true)][string]$Commit, [Parameter(Mandatory = $true)][string]$SpecList, [Parameter(Mandatory = $true)][string]$Label, [int]$Minutes = 120)
$gate = 'C:\Users\yedid\AppData\Local\Temp\claude\C--Users-yedid-bin-wezfleet\38d41f80-e534-4f43-9b23-82b80979b435\scratchpad\remote-gate.ps1'
$specs = [string[]]@($SpecList.Split(';') | Where-Object { $_ })
"SPECS=" + $specs.Count
& $gate -Repo $Repo -Commit $Commit -Mutate $specs -Companion @{ wezfleet = 'C:\Users\yedid\bin\wezfleet@main' } -Env @{ HORDE_WEZFLEET_REPO = '{companion:wezfleet}' } -SuiteTimeoutMinutes $Minutes -Label $Label
exit $LASTEXITCODE
