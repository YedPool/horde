# WHERE DOES THE SESSION THAT HOLDS A ROLE SIT - AND IS THE ANSWER "UNKNOWN" WHENEVER IT IS NOT CERTAIN?
#
# core/SessionSeat.ps1 reads the fleet's session records for the one live session whose record names
# a role, and hands on the pane and the terminal that record gives - once the repository's own identity
# reader has verified that the session is still running, and that its record was written by this run
# of it. core/HostWindow.ps1 then asks each terminal adapter which window that is. Both are tested here
# on registries, control files, process tables and finders this suite invents in %TEMP%: one holder,
# none, two, a retired one, an unreadable record, a record with no pane, a holder that has ended, one
# whose record is older than its process, two running sessions in one pane; a finder that knows, one
# that does not, one that throws, one that names no window. Nothing of this machine's is read.
#
# The stored role words are the old fleet's (core/Roles.ps1 translates them); the roles asked for are
# Horde's.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\SessionSeat.ps1")
. (Join-Path $root "core\HostWindow.ps1")
# The repository's identity reader, which this suite hands invented control files and processes.
. (Join-Path $root "core\Identity.ps1")

$work = Join-Path $env:TEMP ("horde-seat-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
# THE OLD FLEET'S STORE IS THIS SUITE'S FOLDER for as long as the suite runs: every reader that is not
# handed a folder looks under it, and finds nothing, instead of under this machine's own.
$env:WEZFLEET_ROOT = $work
$ids = @{ keeper = "aaaaaaaa-0000-4000-8000-000000000001"; second = "aaaaaaaa-0000-4000-8000-000000000002"; orc = "aaaaaaaa-0000-4000-8000-000000000003"; plain = "aaaaaaaa-0000-4000-8000-000000000004" }
function New-Registry {
    # A registry folder holding the given records; each is a table written as <id>.json, with its id.
    param([string]$Name, [hashtable[]]$Records = @())
    $dir = Join-Path $work $Name
    $sessions = Join-Path $dir "registry\sessions"
    New-Item -ItemType Directory -Path $sessions -Force | Out-Null
    foreach ($r in $Records) {
        $r["claudeSessionId"] = $r["id"]
        $copy = @{}; foreach ($k in @($r.Keys)) { if ($k -cne "id") { $copy[$k] = $r[$k] } }
        [System.IO.File]::WriteAllText((Join-Path $sessions ($r["id"] + ".json")), (ConvertTo-Json -InputObject $copy -Compress))
    }
    return $dir
}
# WHO IS RUNNING. Every invented process started at $started; a record last written at $seenAfter was
# written by that process, and one last written at $seenBefore by an earlier run of the session.
$started = New-Object DateTime 2026, 10, 1, 8, 0, 0, ([DateTimeKind]::Utc)
$seenAfter = "2026-10-01T09:00:00.0000000Z"
$seenBefore = "2026-10-01T07:00:00.0000000Z"
$script:identities = 0
function Identity {
    # What the repository's identity reader says of a folder of control files and a process table made
    # here. Each of -Running is @{ id; pid } and may say process = $null (its process is gone) or
    # process = <another start time> (its process id now belongs to another process).
    param([hashtable[]]$Running = @(), $Processes = $null)
    $script:identities++
    $dirs = @{}
    foreach ($kind in @("control", "projects")) { $dirs[$kind] = Join-Path $work ($kind + "-" + $script:identities); New-Item -ItemType Directory -Path $dirs[$kind] | Out-Null }
    $table = @{}
    foreach ($x in $Running) {
        $number = [int]$x["pid"]
        [System.IO.File]::WriteAllText((Join-Path $dirs["control"] ("" + $number + ".json")), (ConvertTo-Json -InputObject ([ordered]@{ pid = $number; sessionId = $x["id"]; cwd = $work; procStart = ("" + $started.ToFileTimeUtc()); status = "idle" }) -Compress))
        $created = $started
        if ($x.ContainsKey("process")) { $created = $x["process"] }
        if ($null -ne $created) { $table[$number] = [pscustomobject]@{ pid = $number; name = "agent.exe"; created = $created } }
    }
    if ($null -eq $Processes) { $Processes = New-HordeKnown -Value $table }
    return (Get-HordeIdentity -ClaudeDir $dirs["control"] -ProjectsDir $dirs["projects"] -Processes $Processes)
}
function Keeper { param([hashtable]$With = @{}) $r = @{ id = $ids.keeper; role = "master"; pane = "18"; instance = "zorb-instance-1"; lastSeen = $seenAfter }; foreach ($k in @($With.Keys)) { if ($null -eq $With[$k]) { $r.Remove($k) } else { $r[$k] = $With[$k] } }; return $r }
$others = @(@{ id = $ids.orc; role = "orchestrator"; pane = "19"; instance = "zorb-instance-1"; lastSeen = $seenAfter }, @{ id = $ids.plain; pane = "20"; instance = "zorb-instance-1"; lastSeen = $seenAfter })

try {

# Every session of the invented fleet running, each as its control file says: what a check gets unless
# it says otherwise.
$allRunning = Identity @(@{ id = $ids.keeper; pid = 501 }, @{ id = $ids.second; pid = 502 }, @{ id = $ids.orc; pid = 503 }, @{ id = $ids.plain; pid = 504 })
function Seat { param([string]$Role, [string]$Root, $Identity = $allRunning) return (Get-HordeRoleSeat -Role $Role -Root $Root -Identity $Identity) }

Write-Host ""
Write-Host "--- the seat of a role ---" -ForegroundColor Cyan
$one = Seat "warchief" (New-Registry "one" (@(Keeper) + $others))
Check ($one.state -ceq "known" -and $one.value.sessionId -ceq $ids.keeper -and $one.value.pane -ceq "18" -and $one.value.instance -ceq "zorb-instance-1") "one live record names the role: its session, its pane and its terminal, as the record gives them"
$orc = Seat "orc" (Join-Path $work "one")
Check ($orc.state -ceq "known" -and $orc.value.pane -ceq "19") "CONTROL: another role's seat is that role's holder, from the same records"
$roleless = Seat "warchief" (New-Registry "roleless" (@(Keeper) + $others + @(@{ id = "aaaaaaaa-0000-4000-8000-000000000005"; pane = "21"; instance = "zorb-instance-1" })))
Check ($roleless.state -ceq "known" -and $roleless.value.pane -ceq "18") "live sessions that name no role do not make the seat unknown: none of them says it holds the role"
$numberPane = Seat "warchief" (New-Registry "number" @((Keeper @{ pane = 7 })))
Check ($numberPane.state -ceq "known" -and $numberPane.value.pane -ceq "7") "a pane written as a number is handed on as its text"

Write-Host ""
Write-Host "--- nobody, or more than one ---" -ForegroundColor Cyan
$none = Seat "warchief" (New-Registry "none" $others)
Check ($none.state -ceq "absent" -and $none.reason -ceq "no live session's record names the role warchief") "no record names the role: absent"
$retired = Seat "warchief" (New-Registry "retired" (@((Keeper @{ retired = $true })) + $others))
Check ($retired.state -ceq "absent") "a retired holder holds nothing: absent"
$two = Seat "warchief" (New-Registry "two" (@(Keeper) + @(@{ id = $ids.second; role = "master"; pane = "30"; instance = "zorb-instance-1" }) + $others))
Check ($two.state -ceq "unknown" -and $two.reason -like "2 live sessions each say they are the warchief*one is never chosen over another" -and $two.reason.Contains($ids.keeper) -and $two.reason.Contains($ids.second)) "two live records name the role: unknown, both named, neither chosen"
$oneRetired = Seat "warchief" (New-Registry "two-one-retired" (@(Keeper) + @(@{ id = $ids.second; role = "master"; pane = "30"; instance = "zorb-instance-1"; retired = $true })))
Check ($oneRetired.state -ceq "known" -and $oneRetired.value.pane -ceq "18") "CONTROL: of two that name it, the one that is not retired is the seat"

Write-Host ""
Write-Host "--- anything uncertain is unknown ---" -ForegroundColor Cyan
$torn = New-Registry "torn" (@(Keeper) + $others)
[System.IO.File]::WriteAllText((Join-Path $torn ("registry\sessions\" + $ids.second + ".json")), '{"claudeSessionId":"' + $ids.second + '","role":"mas')
$unreadable = Seat "warchief" $torn
Check ($unreadable.state -ceq "unknown" -and $unreadable.reason -like "the session records could not all be read, so which session is the warchief cannot be told:*") "a record that cannot be read may name the role too: unknown, though one readable record names it"
$noDir = Seat "warchief" (Join-Path $work "no-such-registry")
Check ($noDir.state -ceq "unknown" -and $noDir.reason -like "*there is no registry sessions directory*") "no registry at all is unknown, not nobody"
$noPane = Seat "warchief" (New-Registry "nopane" @((Keeper @{ pane = $null })))
Check ($noPane.state -ceq "unknown" -and $noPane.reason -ceq ("the warchief's record (" + $ids.keeper + ") does not say which pane it runs in")) "the holder's record gives no pane: unknown"
$blankPane = Seat "warchief" (New-Registry "blankpane" @((Keeper @{ pane = "  " })))
Check ($blankPane.state -ceq "unknown" -and $blankPane.reason -like "*does not say which pane*") "a pane of only spaces is no pane"
$noInstance = Seat "warchief" (New-Registry "noinstance" @((Keeper @{ instance = $null })))
Check ($noInstance.state -ceq "unknown" -and $noInstance.reason -like "*does not say which terminal it runs in") "the holder's record gives no terminal: unknown"
$listPane = Seat "warchief" (New-Registry "listpane" @((Keeper @{ pane = @("18", "19") })))
Check ($listPane.state -ceq "unknown") "a pane that is a list of two is not a pane"
Check (Throws { Seat "master" (Join-Path $work "one") } "is not a role; the roles are:") "the role asked for is one of Horde's own, never the stored word"

Write-Host ""
Write-Host "--- is the session still there: a record is trusted only for a session that is running, in this run of it ---" -ForegroundColor Cyan
# THE REVIEW'S CASE (2026-10-06, finding C5): a session that ended without being retired, in a terminal
# still running. Its record points at whatever is in that pane now.
$oneRoot = Join-Path $work "one"
$ended = Seat "warchief" $oneRoot (Identity @(@{ id = $ids.keeper; pid = 501; process = $null }, @{ id = $ids.orc; pid = 503 }))
Check ($ended.state -ceq "unknown" -and $ended.reason -ceq ("the warchief's session (" + $ids.keeper + ") is not proven to be running, so the pane its record names may hold something else now: process 501 is not running, so this control file is stale")) ("the holder's process has ended and its record was never retired: unknown, and says why (" + $ended.state + ": " + $ended.reason + ")")
$noFile = Seat "warchief" $oneRoot (Identity @(@{ id = $ids.orc; pid = 503 }))
Check ($noFile.state -ceq "unknown" -and $noFile.reason -like "*is not proven to be running*: no running session's control file names it") "nothing says the holder's session is running at all: unknown"
$reused = Seat "warchief" $oneRoot (Identity @(@{ id = $ids.keeper; pid = 501; process = $started.AddHours(3) }))
Check ($reused.state -ceq "unknown" -and $reused.reason -like "*is not proven to be running*pid 501 was reused*") "the holder's process id now belongs to another process: unknown"
$noTable = Seat "warchief" $oneRoot (Identity @(@{ id = $ids.keeper; pid = 501 }) -Processes (New-HordeUnknown -Reason "the query timed out"))
Check ($noTable.state -ceq "unknown" -and $noTable.reason -like "*is not proven to be running*the process table could not be read (the query timed out)*") "the processes could not be listed, so nothing is proven running: unknown, never taken as running"
$twoFiles = Seat "warchief" $oneRoot (Identity @(@{ id = $ids.keeper; pid = 501 }, @{ id = $ids.keeper; pid = 601 }))
Check ($twoFiles.state -ceq "unknown" -and $twoFiles.reason -like "*is not proven to be running*named by more than one control file*") "two running processes each say they are the holder's session: unknown"
Check ((Seat "warchief" $oneRoot (Identity @(@{ id = $ids.keeper; pid = 501 }))).state -ceq "known") "CONTROL: with the holder alone verified running, and nobody else, the seat is known"
# THE RECORD MUST BE THIS RUN'S. A session started again elsewhere keeps its id, and its record says
# where the earlier run sat until the new run first writes it.
$earlier = Seat "warchief" (New-Registry "earlier" @((Keeper @{ lastSeen = $seenBefore })))
Check ($earlier.state -ceq "unknown" -and $earlier.reason -ceq ("the warchief's record (" + $ids.keeper + ") was last written 2026-10-01T07:00:00.0000000Z, before the session's present process started 2026-10-01T08:00:00.0000000Z, so it says where an earlier run of the session sat")) ("a record last written before the session's present process started: unknown (" + $earlier.state + ": " + $earlier.reason + ")")
foreach ($when in @(@{ seen = $null; what = "no time of writing" }, @{ seen = "yesterday"; what = "a time of writing that is not a time" }, @{ seen = "2026-10-01T09:00:00"; what = "a time of writing with no zone" })) {
    $r = Seat "warchief" (New-Registry ("when-" + $script:identities + "-" + [guid]::NewGuid().ToString("N").Substring(0, 6)) @((Keeper @{ lastSeen = $when.seen })))
    Check ($r.state -ceq "unknown" -and $r.reason -ceq ("the warchief's record (" + $ids.keeper + ") does not say when it was last written, so it cannot be told from a record of an earlier run of the session")) ("a record with " + $when.what + ": unknown")
}
# TWO RUNNING SESSIONS, ONE PANE. Only one can be there; neither record is believed over the other.
$shared = New-Registry "shared" (@(Keeper) + @(@{ id = $ids.plain; pane = "18"; instance = "zorb-instance-1"; lastSeen = $seenAfter }))
$both = Seat "warchief" $shared
Check ($both.state -ceq "unknown" -and $both.reason -like "2 running sessions' records name pane 18 of that terminal (*), so which of them it holds now cannot be told" -and $both.reason.Contains($ids.keeper) -and $both.reason.Contains($ids.plain)) ("another running session's record names the same pane of the same terminal: unknown, both named (" + $both.state + ": " + $both.reason + ")")
Check ((Seat "warchief" $shared (Identity @(@{ id = $ids.keeper; pid = 501 }, @{ id = $ids.plain; pid = 504; process = $null }))).state -ceq "known") "CONTROL: when that other session has ended, its stale record does not make the seat unknown"
Check ((Seat "warchief" (New-Registry "elsewhere" (@(Keeper) + @(@{ id = $ids.plain; pane = "18"; instance = "zorb-instance-2"; lastSeen = $seenAfter })))).state -ceq "known") "CONTROL: nor does a running session in the pane of that number in another terminal"
Check ((Seat "warchief" (New-Registry "left" (@(Keeper) + @(@{ id = $ids.plain; pane = "18"; instance = "zorb-instance-1"; lastSeen = $seenAfter; retired = $true })))).state -ceq "known") "CONTROL: nor a retired record of that pane, whatever its session is doing now"
# Without -Identity the repository's own reader is asked, once. It is replaced here so that this
# machine's sessions are never read by a suite.
$script:identityAsked = 0
function Get-HordeIdentity { $script:identityAsked++; return $allRunning }
$byDefault = $null
try { $byDefault = Get-HordeRoleSeat -Role "warchief" -Root $oneRoot } catch { $byDefault = [pscustomobject]@{ state = "threw"; reason = "$($_.Exception.Message)" } }
Check ($byDefault.state -ceq "known" -and $script:identityAsked -eq 1) ("a caller that hands over no reading gets the repository's own identity reader, asked once (" + $script:identityAsked + ")")

Write-Host ""
Write-Host "--- which window: every finder is asked, and none is believed beyond what it proves ---" -ForegroundColor Cyan
$seat = [pscustomobject]@{ pane = "18"; instance = "zorb-instance-1" }
$script:HordeHostWindowFinders.Clear()
$nobody = Find-HordeSessionWindow -Seat $seat
Check ($nobody.state -ceq "unknown" -and $nobody.reason -ceq "no terminal adapter that can find a session's window is loaded") "with no finder loaded the window is unknown"
$script:asked = New-Object System.Collections.ArrayList
Register-HordeHostWindowFinder -Name "alpha" -Find { param($Seat) [void]$script:asked.Add("alpha " + $Seat.pane); return (New-HordeUnknown -Reason "that is not one of this terminal's panes") }
Register-HordeHostWindowFinder -Name "beta" -Find { param($Seat) [void]$script:asked.Add("beta " + $Seat.pane); "noise on the way"; return (New-HordeKnown -Value ([pscustomobject]@{ handle = [long]70022; detail = "its one window" })) }
$found = Find-HordeSessionWindow -Seat $seat
Check ($found.state -ceq "known" -and $found.value.handle -eq 70022 -and $found.value.handle -is [long] -and $found.value.host -ceq "beta" -and $found.value.detail -ceq "its one window") "the first finder that proves a window gives the answer, with which host said so"
Check (($script:asked -join ",") -ceq "alpha 18,beta 18") "each finder was handed the seat as it was read"
Register-HordeHostWindowFinder -Name "beta" -Find { param($Seat) return (New-HordeUnknown -Reason "two windows carry that title") }
$neither = Find-HordeSessionWindow -Seat $seat
Check ($neither.state -ceq "unknown" -and $neither.reason -ceq "alpha: that is not one of this terminal's panes; beta: two windows carry that title") "when none proves a window the answer is unknown, with every finder's reason under its name"
Check ($script:HordeHostWindowFinders.Count -eq 2) "registering a name again replaces its finder; it does not add a second"
foreach ($bad in @(
    @{ find = { param($Seat) throw "the listing could not be parsed" }; says = "beta: its finder failed: the listing could not be parsed"; what = "a finder that throws" }
    @{ find = { param($Seat) return "window 7" }; says = "beta: its finder did not answer"; what = "a finder that answers with text" }
    @{ find = { param($Seat) return (New-HordeKnown -Value ([pscustomobject]@{ handle = 0 })) }; says = "beta: it named a window with no usable handle"; what = "a known answer with handle 0" }
    @{ find = { param($Seat) return (New-HordeKnown -Value ([pscustomobject]@{ handle = "70022" })) }; says = "beta: it named a window with no usable handle"; what = "a handle given as text" }
    @{ find = { param($Seat) return (New-HordeKnown -Value ([pscustomobject]@{ title = "keeper" })) }; says = "beta: it named a window with no usable handle"; what = "a known answer with no handle at all" }
)) {
    Register-HordeHostWindowFinder -Name "beta" -Find $bad.find
    $r = Find-HordeSessionWindow -Seat $seat
    Check ($r.state -ceq "unknown" -and $r.reason -like ("*" + $bad.says)) ($bad.what + " is not a window: unknown, and it says which finder")
}
$script:asked.Clear()
foreach ($empty in @($null, [pscustomobject]@{ pane = ""; instance = "zorb-instance-1" }, [pscustomobject]@{ pane = "18"; instance = " " })) {
    $r = Find-HordeSessionWindow -Seat $empty
    Check ($r.state -ceq "unknown" -and $r.reason -ceq "no pane and terminal were given, so there is no window to look for") "a seat with no pane or no terminal is unknown"
}
Check ($script:asked.Count -eq 0) "and no finder is asked about it"
Check (Throws { Register-HordeHostWindowFinder -Name "Not A Host" -Find { } } "a host name is lowercase") "a finder registers under a host's folder name"

Write-Host ""
Write-Host "--- the finders' own settings: asked through the port, so a caller can refuse before it starts ---" -ForegroundColor Cyan
# A settings answer as core/ModuleSettings.ps1 gives one: { state; values; findings; path }.
function SettingsAnswer { param([string]$State, [string[]]$Findings = @(), [string]$Path = "")
    return [pscustomobject]@{ state = $State; values = $null; findings = [string[]]@($Findings); path = $Path } }
$script:HordeHostWindowFinders.Clear()
Register-HordeHostWindowFinder -Name "alpha" -Find { param($Seat) return (New-HordeUnknown -Reason "not asked here") }
$noSettings = Get-HordeSessionWindowSettingsState -HordeHome "C:\h"
Check ($noSettings.state -ceq "none" -and @($noSettings.findings).Count -eq 0 -and @($noSettings.files).Count -eq 0) ("a finder that declares no settings: none, nothing found, no file (" + $noSettings.state + ")")
$script:homesAsked = New-Object System.Collections.ArrayList
Register-HordeHostWindowFinder -Name "beta" -Find { param($Seat) return (New-HordeUnknown -Reason "not asked here") } -Settings { param($HordeHome) [void]$script:homesAsked.Add($HordeHome); return (SettingsAnswer "defaults" @() ($HordeHome + "\settings\beta-window.json")) }
$defaultsOnly = Get-HordeSessionWindowSettingsState -HordeHome "C:\h"
Check ($defaultsOnly.state -ceq "defaults" -and @($defaultsOnly.findings).Count -eq 0 -and (@($defaultsOnly.files) -join ",") -ceq "C:\h\settings\beta-window.json") ("a finder whose settings are the defaults: defaults, with the file it would read (" + $defaultsOnly.state + ")")
Check (($script:homesAsked -join ",") -ceq "C:\h") "the finder is handed the home the caller named"
Register-HordeHostWindowFinder -Name "gamma" -Find { param($Seat) return (New-HordeUnknown -Reason "not asked here") } -Settings { param($HordeHome) "noise on the way"; return (SettingsAnswer "read" @() ($HordeHome + "\settings\gamma-window.json")) }
$oneRead = Get-HordeSessionWindowSettingsState -HordeHome "C:\h"
Check ($oneRead.state -ceq "read" -and @($oneRead.findings).Count -eq 0 -and (@($oneRead.files) -join ",") -ceq "C:\h\settings\beta-window.json,C:\h\settings\gamma-window.json") ("one finder read a file and the other has the defaults: read, with both files in the order the finders stand (" + $oneRead.state + ")")
Register-HordeHostWindowFinder -Name "gamma" -Find { param($Seat) return (New-HordeUnknown -Reason "not asked here") } -Settings { param($HordeHome) return (SettingsAnswer "refused" @("the settings file 'C:\h\settings\gamma-window.json' of gamma-window is refused: its key 'attempts' must be 1 to 10", "the settings file 'C:\h\settings\gamma-window.json' of gamma-window is refused: it has the key 'retries'") ($HordeHome + "\settings\gamma-window.json")) }
$refusedOne = Get-HordeSessionWindowSettingsState -HordeHome "C:\h"
Check ($refusedOne.state -ceq "refused" -and @($refusedOne.findings).Count -eq 2 -and $refusedOne.findings[0] -clike "the settings file 'C:\h\settings\gamma-window.json' of gamma-window is refused: its key 'attempts'*" -and $refusedOne.findings[1] -clike "*'retries'") ("a finder whose file is refused refuses, with every finding as its settings said it (" + ($refusedOne.findings -join " / ") + ")")
Check ((@($refusedOne.files) -join ",") -ceq "C:\h\settings\beta-window.json,C:\h\settings\gamma-window.json") "and the files are still every finder's"
foreach ($bad in @(
    @{ settings = { param($HordeHome) throw "the declaration is broken" }; says = "gamma: reading its finder's settings failed: the declaration is broken"; what = "a settings reader that throws" }
    @{ settings = { param($HordeHome) return "defaults" }; says = "gamma: its finder's settings did not answer"; what = "a settings reader that answers with text" }
    @{ settings = { param($HordeHome) return (SettingsAnswer "maybe") }; says = "gamma: its finder's settings did not answer"; what = "an answer whose state is none of defaults, read or refused" }
    @{ settings = { param($HordeHome) return (SettingsAnswer "refused") }; says = "gamma: its finder's settings are refused, and say no reason"; what = "a refusal with no finding" }
)) {
    Register-HordeHostWindowFinder -Name "gamma" -Find { param($Seat) return (New-HordeUnknown -Reason "not asked here") } -Settings $bad.settings
    $r = Get-HordeSessionWindowSettingsState -HordeHome "C:\h"
    Check ($r.state -ceq "refused" -and (@($r.findings) -join "|") -ceq $bad.says) ($bad.what + " refuses, under its host's name (" + (@($r.findings) -join "|") + ")")
}
Register-HordeHostWindowFinder -Name "beta" -Find { param($Seat) return (New-HordeUnknown -Reason "not asked here") } -Settings { param($HordeHome) return (SettingsAnswer "refused" @("the settings file 'C:\h\settings\beta-window.json' of beta-window is refused: it is not UTF-8 text")) }
$both = Get-HordeSessionWindowSettingsState -HordeHome "C:\h"
Check ($both.state -ceq "refused" -and @($both.findings).Count -eq 2 -and $both.findings[0] -ceq "gamma: its finder's settings are refused, and say no reason" -and $both.findings[1] -clike "*beta-window*") "two refused finders: every finding of each, in the order the finders stand (beta, registered again, stands last)"
$script:HordeHostWindowFinders.Clear()
$empty = Get-HordeSessionWindowSettingsState -HordeHome "C:\h"
Check ($empty.state -ceq "none" -and @($empty.findings).Count -eq 0) "with no finder loaded there are no settings to refuse"

} finally {
    if ((Split-Path -Leaf $work) -match '\Ahorde-seat-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "a role's seat and a seat's window are each known only when the records and a terminal prove them"
