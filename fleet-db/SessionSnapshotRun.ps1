# fleet-db/SessionSnapshotRun.ps1 - writes the session snapshot that the sessions step of `horde db sync` reads
# (T-0409; the gathering is fleet/SessionSnapshot.ps1, the reading is fleet-db/sessions.mjs).
#
#   SessionSnapshotRun.ps1 -Out <file>
#
# WHY A CHILD OF ITS OWN. fleet-db/Sync.ps1 starts this as a separate process with a time limit and kills THAT process (by its
# own object, never by name) if it overruns: a terminal that does not answer, or a process-table read (CIM) that stalls,
# can then cost the tick its sessions step but never the files step, and never the whole 50 seconds. The terminal calls each
# have a limit of their own as well (the host adapter's Panes block). Reads only: it writes nothing but -Out, whole or not at all
# (a temp file beside it, then one move), and it starts no pane and sends no text.
#
# THE ADAPTERS ARE FOUND BY FOLDER and never by name (fleet/Port.ps1): when none or more than one is loaded the snapshot says
# that fact is unknown, and the sessions step then judges nothing it cannot see. A registry that cannot be read is said the same
# way. Only a failure to write the file fails this script (exit 1, the reason on stderr).
#
# POWERSHELL 5.1 AND 7: no 2>&1 (CONTRIBUTING 12). This is run with -NoProfile, so a person's profile cannot change what is read.
param([Parameter(Mandatory = $true)][string]$Out)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "core\FileAtomic.ps1")
. (Join-Path $root "core\WezfleetState.ps1")
. (Join-Path $root "fleet\Port.ps1")
. (Join-Path $root "fleet\SessionSnapshot.ps1")
foreach ($adapterFile in @(Get-HordeFleetAdapterFiles -Root $root)) { . $adapterFile }

$agentAnswer = Resolve-HordeFleetAdapter -Kind "agent"
$hostAnswer = Resolve-HordeFleetAdapter -Kind "host"
$agentAdapter = $null
$hostAdapter = $null
if ($agentAnswer.state -ceq "known") { $agentAdapter = $agentAnswer.value }
if ($hostAnswer.state -ceq "known") { $hostAdapter = $hostAnswer.value }
$registry = $null
try { $registry = Read-HordeRegistry -Root (Get-HordeWezfleetRoot) } catch { $registry = $null }

$snapshot = New-HordeFleetSessionSnapshot -Registry $registry -HostAdapter $hostAdapter -Agent $agentAdapter
$json = ConvertTo-HordeFleetSessionSnapshotJson -Snapshot $snapshot
$temp = $Out + ".tmp-" + [guid]::NewGuid().ToString("N")
try {
    [System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.ASCIIEncoding))
    Move-HordeFileAtomic -From $temp -To $Out
} finally {
    if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) }
}
