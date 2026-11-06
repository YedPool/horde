# DOES THE PORT SIDE OF THE FLEET.DB SESSIONS STEP HAND OVER ONLY WHAT IT KNOWS, AND SAY WHAT IT DOES NOT?
#
# fleet/SessionSnapshot.ps1 gathers three facts through the ports - the registry's records, the live panes of every terminal
# instance, the sessions whose process runs - into the one JSON file that fleet-db/sessions.mjs reads. The stand-in adapters go
# through nothing real: no terminal is asked, no process table is read, no registry is opened. What this suite holds the file to:
#   - a record carries only the fields the importer reads, and a time PowerShell 7 parsed into a [datetime] is written back as UTC text;
#   - the JSON is ASCII (a non-ASCII character is a \u escape), compact, and a pane list of one is still a list;
#   - a fact that cannot be read is said so with the reason (no adapter, an adapter that throws, an answer that is unknown, a process
#     listing that was partly unreadable) and is NEVER an empty list: the node side calls nothing dead on an unknown;
#   - a registry read whole says complete, and one that could not be read, or was partial, says why not;
#   - the process-table read happens once per snapshot.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "fleet\SessionSnapshot.ps1")

function Section { param([string]$Title) Write-Host ""; Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan }

$at = [datetime]::new(2026, 11, 2, 12, 0, 0, [System.DateTimeKind]::Utc)
$id1 = "11111111-0000-4000-8000-000000000001"
$id2 = "11111111-0000-4000-8000-000000000002"

function New-FakeRegistry {
    param($Records, $Complete)
    $d = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $Records.Keys) { $d[$k] = [pscustomobject]@{ id = $k; path = "x"; record = $Records[$k] } }
    return [pscustomobject]@{ records = $d; unreadable = @(); misnamed = @(); complete = $Complete }
}
function New-FakeHost { param([scriptblock]$Panes) return [pscustomobject]@{ name = "stand-in"; panes = $Panes } }
function New-FakeAgent {
    param($Running = @(), $Resumed = @{}, [string]$Failure = "", [string]$ResumedFailure = "")
    $snap = [pscustomobject]@{ sessions = @{}; records = @(); error = $Failure; resumed = $Resumed; resumedError = $ResumedFailure }
    $r = $Running
    return [pscustomobject]@{ name = "stand-in"; snapshot = { $snap }.GetNewClosure(); running = { param($s) @($r) }.GetNewClosure() }
}

$rec1 = [pscustomobject]@{ kind = "warg"; owner = "F"; instance = "term-100"; pane = "3"; cwd = "C:\w"; transcriptPath = "C:\t\a.jsonl"; firstSeen = "2026-11-02T10:00:00.0000000Z"; lastSeen = [datetime]::new(2026, 11, 2, 11, 0, 0, [System.DateTimeKind]::Utc); lastTool = "Write"; label = ("F" + [char]0x00E9) }
$rec2 = [pscustomobject]@{ kind = "orc"; owner = "F"; retired = $true; retiredAt = "2026-11-02T09:00:00Z"; pid = 4242 }
$registry = New-FakeRegistry -Records @{ $id1 = $rec1; $id2 = $rec2 } -Complete (New-HordeKnown -Value $true)
$panesOk = { New-HordeKnown -Value @([pscustomobject]@{ instance = "term-100"; state = "listed"; panes = @(3); reason = "" }, [pscustomobject]@{ instance = "term-200"; state = "closed"; panes = @(); reason = "gone" }, [pscustomobject]@{ instance = "term-300"; state = "unknown"; panes = @(); reason = "timed out" }) }

Section "the snapshot of a healthy machine"
$s = New-HordeFleetSessionSnapshot -Registry $registry -HostAdapter (New-FakeHost $panesOk) -Agent (New-FakeAgent -Running @([pscustomobject]@{ sessionId = $id1.ToUpperInvariant(); pid = "77" })) -At $at
Check ($s.v -eq 1 -and $s.at -eq ([DateTimeOffset]$at).ToUnixTimeMilliseconds()) "version 1 and the tick's time in milliseconds"
Check ($s.registry.complete -eq $true -and @($s.registry.sessions).Count -eq 2) "the registry was read whole: both records"
$r1 = @($s.registry.sessions | Where-Object { $_.id -ceq $id1 })[0].rec
Check ($null -ne $r1 -and $r1.PSObject.Properties["lastTool"] -eq $null -and $r1.instance -ceq "term-100" -and $r1.pane -ceq "3") "a record carries the fields the importer reads and not the rest (lastTool is dropped)"
Check ($r1.lastSeen -ceq "2026-11-02T11:00:00.0000000Z") ("a [datetime] is written back as UTC text (" + $r1.lastSeen + ")")
$r2 = @($s.registry.sessions | Where-Object { $_.id -ceq $id2 })[0].rec
Check ($r2.retired -eq $true -and $r2.pid -eq 4242) "a boolean and a number stay what they are"
Check ($s.panes.state -ceq "known" -and @($s.panes.sockets).Count -eq 3) "the panes fact is known, one entry per terminal instance"
Check ((@($s.panes.sockets | ForEach-Object { $_.instance + "=" + $_.state }) -join ",") -ceq "term-100=listed,term-200=closed,term-300=unknown") "each instance keeps its own state: listed, closed or unknown"
Check ($s.processes.state -ceq "known" -and @($s.processes.running).Count -eq 1 -and $s.processes.running[0].sessionId -ceq $id1) "the running sessions, ids lower-cased"

Section "the JSON file"
$json = ConvertTo-HordeFleetSessionSnapshotJson -Snapshot $s
Check ($json -cnotmatch '[^\x20-\x7E]') "ASCII only: no character past 126 and no line break"
Check ($json -clike '*\u00e9*') "the non-ASCII character in a label is a \u escape"
$back = $json | ConvertFrom-Json
Check ($back.v -eq 1 -and $back.registry.sessions.Count -eq 2 -and $back.panes.sockets[0].panes.Count -eq 1) "it reads back"
Check ($json.Contains('"panes":[3]')) "a list of one pane is still a list"
Check ($json.Contains('"panes":[]')) "and an empty one is an empty list"

Section "a fact that cannot be read is said so, never an empty list"
$noHost = New-HordeFleetSessionSnapshot -Registry $registry -HostAdapter $null -Agent (New-FakeAgent) -At $at
Check ($noHost.panes.state -ceq "unknown" -and $noHost.panes.reason -like "*no terminal adapter*" -and @($noHost.panes.sockets).Count -eq 0) "no terminal adapter: panes unknown, with the reason"
$offers = New-HordeFleetSessionSnapshot -Registry $registry -HostAdapter ([pscustomobject]@{ name = "bare"; panes = $null }) -Agent (New-FakeAgent) -At $at
Check ($offers.panes.state -ceq "unknown" -and $offers.panes.reason -like "*offers no pane list*") "an adapter with no pane list: unknown"
$throws = New-HordeFleetSessionSnapshot -Registry $registry -HostAdapter (New-FakeHost { throw "boom" }) -Agent (New-FakeAgent) -At $at
Check ($throws.panes.state -ceq "unknown" -and $throws.panes.reason -like "*boom*") "an adapter that throws: unknown, with what it said"
$unk = New-HordeFleetSessionSnapshot -Registry $registry -HostAdapter (New-FakeHost { New-HordeUnknown -Reason "no socket folder" }) -Agent (New-FakeAgent) -At $at
Check ($unk.panes.state -ceq "unknown" -and $unk.panes.reason -ceq "no socket folder") "an unknown answer is passed on with its reason"
$junk = New-HordeFleetSessionSnapshot -Registry $registry -HostAdapter (New-FakeHost { "not an answer" }) -Agent (New-FakeAgent) -At $at
Check ($junk.panes.state -ceq "unknown") "something that is not an answer is unknown"
$noAgent = New-HordeFleetSessionSnapshot -Registry $registry -HostAdapter (New-FakeHost $panesOk) -Agent $null -At $at
Check ($noAgent.processes.state -ceq "unknown" -and $noAgent.processes.reason -like "*no agent adapter*") "no agent adapter: processes unknown"
$bad = New-HordeFleetSessionSnapshot -Registry $registry -HostAdapter (New-FakeHost $panesOk) -Agent (New-FakeAgent -Failure "control directory not found") -At $at
Check ($bad.processes.state -ceq "unknown" -and $bad.processes.reason -ceq "control directory not found") "an unreadable control directory: processes unknown"
$blind = New-HordeFleetSessionSnapshot -Registry $registry -HostAdapter (New-FakeHost $panesOk) -Agent (New-FakeAgent -ResumedFailure "no command line for process 9") -At $at
Check ($blind.processes.state -ceq "unknown" -and $blind.processes.reason -like "*no command line*") "a process listing that was partly unreadable may hide a running session: unknown, not an empty list"
$boom = New-HordeFleetSessionSnapshot -Registry $registry -HostAdapter (New-FakeHost $panesOk) -Agent ([pscustomobject]@{ name = "x"; snapshot = { throw "cim down" }; running = { @() } }) -At $at
Check ($boom.processes.state -ceq "unknown" -and $boom.processes.reason -like "*cim down*") "an agent adapter that throws: unknown"

Section "a process started to resume a session by hand counts as running; the process table is read once"
$resumedMap = @{ $id2 = "88" }
$withResume = New-HordeFleetSessionSnapshot -Registry $registry -HostAdapter (New-FakeHost $panesOk) -Agent (New-FakeAgent -Running @([pscustomobject]@{ sessionId = $id1; pid = "77" }) -Resumed $resumedMap) -At $at
Check ((@($withResume.processes.running | ForEach-Object { $_.sessionId }) -join ",") -ceq ($id1 + "," + $id2)) "the resumed id is added after the control-file ones, once each"
$reads = New-Object System.Collections.ArrayList
$agentCount = New-FakeAgent
$agentCount.snapshot = { [void]$reads.Add(1); [pscustomobject]@{ sessions = @{}; records = @(); error = ""; resumed = @{}; resumedError = "" } }.GetNewClosure()
[void](New-HordeFleetSessionSnapshot -Registry $registry -HostAdapter (New-FakeHost $panesOk) -Agent $agentCount -At $at)
Check ($reads.Count -eq 1) "the agent's reading (its one process-table read) happens exactly once per snapshot"

Section "the registry"
$partial = New-HordeFleetSessionSnapshot -Registry (New-FakeRegistry -Records @{ $id1 = $rec1 } -Complete (New-HordeUnknown -Reason "a record could not be read")) -HostAdapter (New-FakeHost $panesOk) -Agent (New-FakeAgent) -At $at
Check ($partial.registry.complete -eq $false -and $partial.registry.reason -ceq "a record could not be read" -and @($partial.registry.sessions).Count -eq 1) "a partial registry keeps what was read and says it is not complete"
$none = New-HordeFleetSessionSnapshot -Registry $null -HostAdapter (New-FakeHost $panesOk) -Agent (New-FakeAgent) -At $at
Check ($none.registry.complete -eq $false -and @($none.registry.sessions).Count -eq 0 -and $none.registry.reason -like "*could not be read*") "no registry at all: not complete, no sessions, the reason"
Check ((ConvertTo-HordeFleetSessionSnapshotJson -Snapshot $none).Contains('"sessions":[]')) "and an empty session list is still a list in the file"

Complete-HordeSuite -Success "the sessions step's port side hands over only the fields the importer reads, ASCII, and names every fact it could not read"
