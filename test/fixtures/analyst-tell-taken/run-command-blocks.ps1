# One process: the statement of cli/commands/analyst.ps1 that LOADS the messenger port and sets the real tools (cut out of the file with the parser,
# so the load comes from the command itself, not from this script), then the REAL Tell and TellTaken blocks it set, run in the order given, as one
# pass runs them. Prints "LOADED <messengers>" and then one line per block with what the block ANSWERED: "<order> <step> ..." or
# "<order> <step> THREW <message>". The home is not a test's here (the temp folder is pointed elsewhere), so the blocks go past the guard to
# the warchief's seat, which is not there (no fleet): nothing is ever posted. Run by test/test-analyst-tell-taken.ps1 on the shell it runs under.
param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Order, [Parameter(Mandatory = $true)][string]$Home_, [Parameter(Mandatory = $true)][string]$TempAway)
$ErrorActionPreference = "Stop"
$env:HORDE_HOME = $Home_
$env:WEZFLEET_ROOT = Join-Path $Home_ "no-fleet"
$env:TEMP = $TempAway
$env:TMP = $TempAway
# What the command loads before this statement (its lines 20 and 21).
foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "AnalystRounds", "AnalystSession")) { . (Join-Path $Root ("core\" + $f + ".ps1")) }
. (Join-Path $Root "cli\AnalystTend.ps1")
$root = $Root
$hordeHome = $Home_
$tools = New-HordeAnalystTools
# An awaiting list that cannot be read counts as awaiting (Test-HordeAnalystTellAwaiting), so the real TellTaken block goes on to ask.
$awaitingPath = Get-HordeDecisionNoticeTakenPath -Kind $script:HordeAnalystTellTakenKind -HordeHome $Home_
[void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($awaitingPath))
[System.IO.File]::WriteAllText($awaitingPath, "not json")
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root "cli\commands\analyst.ps1"), [ref]$null, [ref]$null)
$guard = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -match '\A-not \(Test-HordeAnalystHomeIsATests' }, $true))
if ($guard.Count -ne 1) { Write-Output ($Order + " THREW the file has no one statement that loads the tools"); exit 0 }
try { . ([scriptblock]::Create($guard[0].Extent.Text)) } catch { Write-Output ($Order + " THREW the command's own load: " + $_.Exception.Message); exit 0 }
Write-Output ("LOADED " + (@(Get-HordeMessengerNames) -join ","))
$values = [pscustomobject]@{ fromLabel = "AS"; tellWarchief = $true; takenAlarmSeconds = 90; takenAfterAlarmSeconds = 60 }
foreach ($step in @($Order -split ",")) {
    if ($null -eq $tools[$step]) { Write-Output ($Order + " " + $step + " THREW the command set no such tool"); continue }
    try {
        if ($step -ceq "Tell") { $r = & $tools[$step] "relay-x" "body" $values 0; Write-Output ($Order + " Tell ok=" + $r.ok + " detail=" + $r.detail) }
        else { $r = @(& $tools[$step] $values); Write-Output ($Order + " TellTaken lines=" + ($r -join " | ")) }
    } catch { Write-Output ($Order + " " + $step + " THREW " + $_.Exception.Message) }
}
