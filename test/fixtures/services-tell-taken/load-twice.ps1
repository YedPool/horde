# One process, the REAL TellAll and TellTaken blocks of a real command file (cli/commands/services.ps1 or rollout.ps1), run in the order
# given, as one supervisor pass runs them. Prints one line per block: "<command> <order> <step> OK <names>" or "... THREW <message>".
# Run by test/test-services-tell-taken.ps1 on the shell that suite runs under. Plain stdout only: the parent reads it.
param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][ValidateSet("services", "rollout")][string]$Command, [Parameter(Mandatory = $true)][string]$Order, [Parameter(Mandatory = $true)][string]$Home_)
$ErrorActionPreference = "Stop"
$env:HORDE_HOME = $Home_
$env:WEZFLEET_ROOT = Join-Path $Home_ "no-fleet"
foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "Services", "ServicesFiles", "ServiceHostPort")) { . (Join-Path $Root ("core\" + $f + ".ps1")) }
foreach ($f in @("ServicesAct", "ServicesTend", "ServicesTell")) { . (Join-Path $Root ("cli\" + $f + ".ps1")) }
# An awaiting list that cannot be read counts as awaiting (Test-HordeServiceTellAwaiting), so the real TellTaken block goes on to load the port.
$awaitingPath = Get-HordeDecisionNoticeTakenPath -Kind $script:HordeServiceTellTakenKind -HordeHome $Home_
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($awaitingPath))
[System.IO.File]::WriteAllText($awaitingPath, "not json")
# The blocks as the file has them: the right-hand side of $tools["<name>"] = { ... }.
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root ("cli\commands\" + $Command + ".ps1")), [ref]$null, [ref]$null)
$blocks = @{}
foreach ($a in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))) {
    if ($a.Left.Extent.Text -match '\A\$tools\["(TellAll|TellTaken)"\]\z' -and $a.Right.Expression -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { $blocks[$Matches[1]] = $a.Right.Expression.ScriptBlock.GetScriptBlock() }
}
$root = $Root
$pol = [pscustomobject]@{ fromLabel = "SV"; tellWarchief = $true; takenAlarmSeconds = 90; takenAfterAlarmSeconds = 60 }
$steps = @($Order -split ",")
foreach ($step in $steps) {
    if (-not $blocks.ContainsKey($step)) { Write-Output ($Command + " " + $Order + " " + $step + " THREW the file has no such block"); continue }
    try {
        if ($step -ceq "TellAll") { $r = & $blocks[$step] @() $Home_ $pol } else { $r = & $blocks[$step] $Home_ $pol }
        Write-Output ($Command + " " + $Order + " " + $step + " OK")
    } catch { Write-Output ($Command + " " + $Order + " " + $step + " THREW " + $_.Exception.Message) }
}
