# One process, the REAL Tell and TellTaken blocks of cli/commands/analyst.ps1, run in the order given, as one pass runs them, with the messenger
# port loaded ONCE at this scope, as the command loads it. Prints one line per block: "<order> <step> OK" or "<order> <step> THREW <message>".
# Run by test/test-analyst-tell-taken.ps1 on the shell that suite runs under. Plain stdout only: the parent reads it.
param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Order, [Parameter(Mandatory = $true)][string]$Home_)
$ErrorActionPreference = "Stop"
$env:HORDE_HOME = $Home_
$env:WEZFLEET_ROOT = Join-Path $Home_ "no-fleet"
foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "AnalystRounds", "AnalystSession", "SessionSeat", "Device")) { . (Join-Path $Root ("core\" + $f + ".ps1")) }
. (Join-Path $Root "messengers\Port.ps1")
foreach ($f in @(Get-HordeMessengerFiles)) { . $f }
. (Join-Path $Root "cli\AnalystTend.ps1")
$hordeHome = $Home_
# An awaiting list that cannot be read counts as awaiting (Test-HordeAnalystTellAwaiting), so the real TellTaken block goes on to ask.
$awaitingPath = Get-HordeDecisionNoticeTakenPath -Kind $script:HordeAnalystTellTakenKind -HordeHome $Home_
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($awaitingPath))
[System.IO.File]::WriteAllText($awaitingPath, "not json")
# The blocks as the file has them: the right-hand side of $tools["<name>"] = { ... }.
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root "cli\commands\analyst.ps1"), [ref]$null, [ref]$null)
$blocks = @{}
foreach ($a in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))) {
    if ($a.Left.Extent.Text -match '\A\$tools\["(Tell|TellTaken)"\]\z' -and $a.Right.Expression -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { $blocks[$Matches[1]] = $a.Right.Expression.ScriptBlock.GetScriptBlock() }
}
$values = [pscustomobject]@{ fromLabel = "AS"; tellWarchief = $true; takenAlarmSeconds = 90; takenAfterAlarmSeconds = 60 }
foreach ($step in @($Order -split ",")) {
    if (-not $blocks.ContainsKey($step)) { Write-Output ($Order + " " + $step + " THREW the file has no such block"); continue }
    try {
        # The home here is under the temp folder, so the real teller refuses before it looks for a seat: the block still ran.
        if ($step -ceq "Tell") { $r = & $blocks[$step] "relay-x" "body" $values 0 } else { $r = & $blocks[$step] $values }
        Write-Output ($Order + " " + $step + " OK")
    } catch { Write-Output ($Order + " " + $step + " THREW " + $_.Exception.Message) }
}
