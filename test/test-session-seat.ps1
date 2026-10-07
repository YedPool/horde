# WHERE DOES THE SESSION THAT HOLDS A ROLE SIT - AND IS THE ANSWER "UNKNOWN" WHENEVER IT IS NOT CERTAIN?
#
# core/SessionSeat.ps1 reads the fleet's session records for the one live session whose record names
# a role, and hands on the pane and the terminal that record gives. core/HostWindow.ps1 then asks each
# terminal adapter which window that is. Both are tested here on registries and finders this suite
# invents in %TEMP%: one holder, none, two, a retired one, an unreadable record, a record with no
# pane; a finder that knows, one that does not, one that throws, one that names no window.
#
# The stored role words are the old fleet's (core/Roles.ps1 translates them); the roles asked for are
# Horde's.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\SessionSeat.ps1")
. (Join-Path $root "core\HostWindow.ps1")

$work = Join-Path $env:TEMP ("horde-seat-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
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
function Keeper { param([hashtable]$With = @{}) $r = @{ id = $ids.keeper; role = "master"; pane = "18"; instance = "zorb-instance-1" }; foreach ($k in @($With.Keys)) { if ($null -eq $With[$k]) { $r.Remove($k) } else { $r[$k] = $With[$k] } }; return $r }
$others = @(@{ id = $ids.orc; role = "orchestrator"; pane = "19"; instance = "zorb-instance-1" }, @{ id = $ids.plain; pane = "20"; instance = "zorb-instance-1" })

try {

Write-Host ""
Write-Host "--- the seat of a role ---" -ForegroundColor Cyan
$one = Get-HordeRoleSeat -Role "warchief" -Root (New-Registry "one" (@(Keeper) + $others))
Check ($one.state -ceq "known" -and $one.value.sessionId -ceq $ids.keeper -and $one.value.pane -ceq "18" -and $one.value.instance -ceq "zorb-instance-1") "one live record names the role: its session, its pane and its terminal, as the record gives them"
$orc = Get-HordeRoleSeat -Role "orc" -Root (Join-Path $work "one")
Check ($orc.state -ceq "known" -and $orc.value.pane -ceq "19") "CONTROL: another role's seat is that role's holder, from the same records"
$roleless = Get-HordeRoleSeat -Role "warchief" -Root (New-Registry "roleless" (@(Keeper) + $others + @(@{ id = "aaaaaaaa-0000-4000-8000-000000000005"; pane = "21"; instance = "zorb-instance-1" })))
Check ($roleless.state -ceq "known" -and $roleless.value.pane -ceq "18") "live sessions that name no role do not make the seat unknown: none of them says it holds the role"
$numberPane = Get-HordeRoleSeat -Role "warchief" -Root (New-Registry "number" @((Keeper @{ pane = 7 })))
Check ($numberPane.state -ceq "known" -and $numberPane.value.pane -ceq "7") "a pane written as a number is handed on as its text"

Write-Host ""
Write-Host "--- nobody, or more than one ---" -ForegroundColor Cyan
$none = Get-HordeRoleSeat -Role "warchief" -Root (New-Registry "none" $others)
Check ($none.state -ceq "absent" -and $none.reason -ceq "no live session's record names the role warchief") "no record names the role: absent"
$retired = Get-HordeRoleSeat -Role "warchief" -Root (New-Registry "retired" (@((Keeper @{ retired = $true })) + $others))
Check ($retired.state -ceq "absent") "a retired holder holds nothing: absent"
$two = Get-HordeRoleSeat -Role "warchief" -Root (New-Registry "two" (@(Keeper) + @(@{ id = $ids.second; role = "master"; pane = "30"; instance = "zorb-instance-1" }) + $others))
Check ($two.state -ceq "unknown" -and $two.reason -like "2 live sessions each say they are the warchief*one is never chosen over another" -and $two.reason.Contains($ids.keeper) -and $two.reason.Contains($ids.second)) "two live records name the role: unknown, both named, neither chosen"
$oneRetired = Get-HordeRoleSeat -Role "warchief" -Root (New-Registry "two-one-retired" (@(Keeper) + @(@{ id = $ids.second; role = "master"; pane = "30"; instance = "zorb-instance-1"; retired = $true })))
Check ($oneRetired.state -ceq "known" -and $oneRetired.value.pane -ceq "18") "CONTROL: of two that name it, the one that is not retired is the seat"

Write-Host ""
Write-Host "--- anything uncertain is unknown ---" -ForegroundColor Cyan
$torn = New-Registry "torn" (@(Keeper) + $others)
[System.IO.File]::WriteAllText((Join-Path $torn ("registry\sessions\" + $ids.second + ".json")), '{"claudeSessionId":"' + $ids.second + '","role":"mas')
$unreadable = Get-HordeRoleSeat -Role "warchief" -Root $torn
Check ($unreadable.state -ceq "unknown" -and $unreadable.reason -like "the session records could not all be read, so which session is the warchief cannot be told:*") "a record that cannot be read may name the role too: unknown, though one readable record names it"
$noDir = Get-HordeRoleSeat -Role "warchief" -Root (Join-Path $work "no-such-registry")
Check ($noDir.state -ceq "unknown" -and $noDir.reason -like "*there is no registry sessions directory*") "no registry at all is unknown, not nobody"
$noPane = Get-HordeRoleSeat -Role "warchief" -Root (New-Registry "nopane" @((Keeper @{ pane = $null })))
Check ($noPane.state -ceq "unknown" -and $noPane.reason -ceq ("the warchief's record (" + $ids.keeper + ") does not say which pane it runs in")) "the holder's record gives no pane: unknown"
$blankPane = Get-HordeRoleSeat -Role "warchief" -Root (New-Registry "blankpane" @((Keeper @{ pane = "  " })))
Check ($blankPane.state -ceq "unknown" -and $blankPane.reason -like "*does not say which pane*") "a pane of only spaces is no pane"
$noInstance = Get-HordeRoleSeat -Role "warchief" -Root (New-Registry "noinstance" @((Keeper @{ instance = $null })))
Check ($noInstance.state -ceq "unknown" -and $noInstance.reason -like "*does not say which terminal it runs in") "the holder's record gives no terminal: unknown"
$listPane = Get-HordeRoleSeat -Role "warchief" -Root (New-Registry "listpane" @((Keeper @{ pane = @("18", "19") })))
Check ($listPane.state -ceq "unknown") "a pane that is a list of two is not a pane"
Check (Throws { Get-HordeRoleSeat -Role "master" -Root (Join-Path $work "one") } "is not a role; the roles are:") "the role asked for is one of Horde's own, never the stored word"

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

} finally {
    if ((Split-Path -Leaf $work) -match '\Ahorde-seat-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "a role's seat and a seat's window are each known only when the records and a terminal prove them"
