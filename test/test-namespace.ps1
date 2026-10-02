# DOES EVERY PID, PROCSTART AND PATH SAY WHICH MACHINE AND WHICH PROCESS SPACE IT BELONGS TO?
#
# Remote plan step R11 (planning/execution-plan-remote.md). On top of the HostPort's space (hosts
# decision 5), a pid, procStart or path that leaves a node carries ns { device, space }: the device id
# of core/Device.ps1 (R7) and the process space of core/Platform.ps1. core/Namespace.ps1 holds the
# four rules R11 names, each tested here:
#   (a) a pid is looked up only on its own device, in its own space - never in this machine's table
#       when it is another's;
#   (b) two pids are one process only when device, space, pid and procStart all match;
#   (c) a path from another device is displayed and never opened here;
#   (d) the agent's pidDomain is its own claim and never stands in for the device: two devices whose
#       sessions share one pidDomain stay two devices.
# Everything is pure: no process table and no file is touched.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\Namespace.ps1")

$devA = "0f8fad5b-d9cb-469f-a165-70867728950e"
$devB = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
$here_ = New-HordeNamespace -Device $devA -Space "windows"
function Proc { param($Device, $Space, $ProcId, $ProcStart, $PidDomain = "win32:tester") return [pscustomobject]@{ ns = (New-HordeNamespace -Device $Device -Space $Space); pid = $ProcId; procStart = $ProcStart; pidDomain = $PidDomain } }
function IsKnown { param($A, $V) return ($A.state -ceq "known" -and $A.value -eq $V) }

Write-Host ""
Write-Host "--- loading the module ---" -ForegroundColor Cyan
$strictKept = & { Set-StrictMode -Version Latest; . (Join-Path $root "core\Namespace.ps1"); try { $null = $hordeNeverAssignedVariable; $false } catch { $true } }
Check ($strictKept -eq $true) "dot-sourcing core/Namespace leaves the caller's strict mode on"

Write-Host ""
Write-Host "--- a namespace is a device and a space, both checked ---" -ForegroundColor Cyan
Check ("$($here_.device)" -ceq $devA -and "$($here_.space)" -ceq "windows") "a namespace holds the device id and the process space"
Check (Throws { New-HordeNamespace -Device "DESKTOP-01" -Space "windows" } "device") "a device that is not a device id (a host name) is refused"
Check (Throws { New-HordeNamespace -Device $devA.ToUpperInvariant() -Space "windows" } "device") "a device id in upper case is refused: one spelling, as R7 writes it"
Check (Throws { New-HordeNamespace -Device $devA -Space "win32" } "space") "a space core does not know (win32) is refused"
Check (Throws { New-HordeNamespace -Device $devA -Space "wsl" } "space") "a wsl space must name its distro"
Check ("$((New-HordeNamespace -Device $devA -Space 'wsl:ubuntu').space)" -ceq "wsl:ubuntu") "control: a wsl space with its distro is accepted"
Check (Throws { New-HordeNamespace -Device "" -Space "windows" } "device") "an empty device is refused"
Check ((Get-Command New-HordeNamespace).Parameters.Keys -notcontains "PidDomain") "(d) a namespace cannot be built from a pidDomain: the function has no such input"
$ln = Get-HordeLocalNamespace -DeviceId $devA -Platform ([pscustomobject]@{ PSTypeName = "Horde.Platform"; name = "test"; processSpace = "wsl:ubuntu"; processTable = { } })
Check ("$($ln.device)" -ceq $devA -and "$($ln.space)" -ceq "wsl:ubuntu") "the local namespace is this device and its platform's space"

Write-Host ""
Write-Host "--- (a) a pid is looked up only on its own device, in its own space ---" -ForegroundColor Cyan
$a = Test-HordeNamespaceLocal -Namespace $here_ -Local $here_
Check (IsKnown $a $true) "a pid of this device and space may be looked up here"
$a = Test-HordeNamespaceLocal -Namespace (New-HordeNamespace -Device $devB -Space "windows") -Local $here_
Check ((IsKnown $a $false) -and $a.reason -clike "*$devB*" -and $a.reason -clike "*never looked up here*") "a pid of another device is never looked up here, and the reason names the device"
$a = Test-HordeNamespaceLocal -Namespace (New-HordeNamespace -Device $devA -Space "wsl:ubuntu") -Local $here_
Check ((IsKnown $a $false) -and $a.reason -clike "*wsl:ubuntu*") "a pid of this device in another space is not looked up in this space's table"
$a = Test-HordeNamespaceLocal -Namespace $null -Local $here_
Check ($a.state -ceq "unknown") "a pid with no namespace is unknown, never assumed local"
$a = Test-HordeNamespaceLocal -Namespace ([pscustomobject]@{ device = $devA }) -Local $here_
Check ($a.state -ceq "unknown") "a namespace without its space is unknown"
$a = Test-HordeNamespaceLocal -Namespace ([pscustomobject]@{ device = "DESKTOP-01"; space = "windows" }) -Local $here_
Check ($a.state -ceq "unknown") "a namespace whose device is not a device id is unknown, never compared"
$a = Test-HordeNamespaceLocal -Namespace ([pscustomobject]@{ device = $devA; space = "win32" }) -Local $here_
Check ($a.state -ceq "unknown") "a hand-built namespace whose space core does not know is unknown, never compared"
$a = Test-HordeNamespaceLocal -Namespace ([pscustomobject]@{ device = ($devA + "`n"); space = "windows" }) -Local $here_
Check ($a.state -ceq "unknown") "a device with a trailing newline is not a device id: the pattern ends at the end of the text"
$a = Test-HordeNamespaceLocal -Namespace ([pscustomobject]@{ device = $devA; space = "windows`n" }) -Local $here_
Check ($a.state -ceq "unknown") "a space with a trailing newline is not a space"
Check (Throws { New-HordeNamespace -Device ($devA + "`n") -Space "windows" } "device") "a namespace cannot be built from a device with a trailing newline"

Write-Host ""
Write-Host "--- (b) two pids are one process only when all four match ---" -ForegroundColor Cyan
$p1 = Proc $devA "windows" 1234 "133420000000000000"
Check (IsKnown (Test-HordeSameProcess -A $p1 -B (Proc $devA "windows" 1234 "133420000000000000")) $true) "same device, space, pid and procStart are one process"
Check (IsKnown (Test-HordeSameProcess -A $p1 -B (Proc $devB "windows" 1234 "133420000000000000")) $false) "the same pid and procStart on another device are another process"
Check (IsKnown (Test-HordeSameProcess -A $p1 -B (Proc $devA "wsl:ubuntu" 1234 "133420000000000000")) $false) "the same pid and procStart in another space are another process"
Check (IsKnown (Test-HordeSameProcess -A $p1 -B (Proc $devA "windows" 1235 "133420000000000000")) $false) "another pid is another process"
Check (IsKnown (Test-HordeSameProcess -A $p1 -B (Proc $devA "windows" 1234 "133420000000000001")) $false) "the same pid started at another time is another process: the pid was reused"
Check (IsKnown (Test-HordeSameProcess -A $p1 -B (Proc $devA "windows" 1234 "0133420000000000000")) $true) "procStart is compared as integer ticks, so a leading zero is the same time"
Check ((Test-HordeSameProcess -A $p1 -B (Proc $devA "windows" 1234 $null)).state -ceq "unknown") "a missing procStart is unknown, never a match on pid alone"
Check ((Test-HordeSameProcess -A $p1 -B (Proc $devA "windows" 1234 "yesterday")).state -ceq "unknown") "a procStart that is not ticks is unknown"
Check ((Test-HordeSameProcess -A $p1 -B ([pscustomobject]@{ ns = $null; pid = 1234; procStart = "133420000000000000" })).state -ceq "unknown") "a pid with no namespace is unknown, never a match on pid and procStart alone"
Check ((Test-HordeSameProcess -A $p1 -B (Proc $devA "windows" $null "133420000000000000")).state -ceq "unknown") "a missing pid is unknown"
$bad = [pscustomobject]@{ ns = [pscustomobject]@{ device = $devA; space = "win32" }; pid = 1234; procStart = "133420000000000000" }
Check ((Test-HordeSameProcess -A $bad -B $bad).state -ceq "unknown") "two processes in a space core does not know are unknown, even when everything else matches"
Check ((Test-HordeSameProcess -A $p1 -B (Proc $devA "windows" "99999999999999999999" "133420000000000000")).state -ceq "unknown") "an oversized pid is unknown, not an error"
Check ((Test-HordeSameProcess -A (Proc $devA "windows" 0 "133420000000000000") -B (Proc $devA "windows" 0 "133420000000000000")).state -ceq "unknown") "pid 0 is not a pid"
Check ((Test-HordeSameProcess -A $p1 -B (Proc $devA "windows" @(1234) "133420000000000000")).state -ceq "unknown") "a list is not a pid, even a list of the same number"
Check (IsKnown (Test-HordeSameProcess -A $p1 -B (Proc $devA "windows" "1234" ([long]133420000000000000))) $true) "a pid given as digits and a procStart given as a number compare as the same values"

Write-Host ""
Write-Host "--- (c) a path from another device is displayed, never opened ---" -ForegroundColor Cyan
$o = Test-HordePathOpenable -Namespace $here_ -Local $here_
Check (IsKnown $o $true) "a path of this device and space may be opened here"
$o = Test-HordePathOpenable -Namespace (New-HordeNamespace -Device $devB -Space "windows") -Local $here_
Check ((IsKnown $o $false) -and $o.reason -clike "*displayed*" -and $o.reason -clike "*$devB*") "a path of another device is displayed, never opened, and the reason says so"
$o = Test-HordePathOpenable -Namespace (New-HordeNamespace -Device $devA -Space "wsl:ubuntu") -Local $here_
Check (IsKnown $o $false) "a path of this device in another space is not opened as if it were this space's: C:\x and /x are not one folder"
$o = Test-HordePathOpenable -Namespace $null -Local $here_
Check ($o.state -ceq "unknown") "a path with no namespace is unknown, never opened"

Write-Host ""
Write-Host "--- (d) pidDomain is the agent's claim and never the device ---" -ForegroundColor Cyan
# Measured (remote design M-01): the agent writes pidDomain "win32:<user>" in every control file, so two
# machines with one user name write the same value.
$x = Proc $devA "windows" 1234 "133420000000000000" "win32:tester"
$y = Proc $devB "windows" 1234 "133420000000000000" "win32:tester"
Check ("$($x.pidDomain)" -ceq "$($y.pidDomain)") "CONTROL: the two fixture sessions share one pidDomain"
Check (IsKnown (Test-HordeSameProcess -A $x -B $y) $false) "two devices sharing one pidDomain stay two devices: same pid and procStart are two processes"
Check (IsKnown (Test-HordeNamespaceLocal -Namespace $y.ns -Local $x.ns) $false) "a session on another device is not local because its pidDomain matches"
$z = Proc $devA "windows" 1234 "133420000000000000" "win32:someone-else"
Check (IsKnown (Test-HordeSameProcess -A $x -B $z) $true) "a different pidDomain on one device does not split one process: pidDomain is not compared at all"

Write-Host ""
Write-Host "--- (a) in core/Identity: the process check never looks up another device's pid ---" -ForegroundColor Cyan
. (Join-Path $root "core\Identity.ps1")
# A process table that records every lookup made in it, so "never looked up" is measured, not assumed.
$script:lookups = 0
$created = [DateTime]::FromFileTimeUtc([long]"133420000000000000")
$trip = [pscustomobject]@{}
$trip | Add-Member -MemberType ScriptMethod -Name ContainsKey -Value { param($k) $script:lookups++; return $false }
$table = New-HordeKnown -Value @{ 1234 = [pscustomobject]@{ pid = 1234; name = "x"; created = $created; commandLine = "" } }
$v = Get-HordeProcessVerdict -ProcId 1234 -ProcStart "133420000000000000" -Processes $table -Namespace $here_ -Local $here_
Check ($v.same -eq $true -and "$($v.kind)" -ceq "verified") "control: a pid of this device and space is checked against the table as before"
$v = Get-HordeProcessVerdict -ProcId 1234 -ProcStart "133420000000000000" -Processes $table
Check ($v.same -eq $true -and "$($v.kind)" -ceq "verified") "a caller that names no namespace checks this machine's own pid, as every caller on main does"
$v = Get-HordeProcessVerdict -ProcId 1234 -ProcStart "133420000000000000" -Processes (New-HordeKnown -Value $trip) -Namespace (New-HordeNamespace -Device $devB -Space "windows") -Local $here_
Check ($v.same -eq $false -and "$($v.kind)" -ceq "remote" -and $script:lookups -eq 0) "a pid of another device is never looked up in this machine's table"
$v = Get-HordeProcessVerdict -ProcId 1234 -ProcStart "133420000000000000" -Processes (New-HordeKnown -Value $trip) -Namespace (New-HordeNamespace -Device $devA -Space "wsl:ubuntu") -Local $here_
Check ($v.same -eq $false -and "$($v.kind)" -ceq "remote" -and $script:lookups -eq 0) "a pid of another space on this device is never looked up in this space's table"
$v = Get-HordeProcessVerdict -ProcId 1234 -ProcStart "133420000000000000" -Processes (New-HordeKnown -Value $trip) -Namespace (New-HordeNamespace -Device $devB -Space "windows")
Check ($v.same -eq $false -and "$($v.kind)" -ceq "uncheckable" -and $script:lookups -eq 0) "a namespace given without this machine's is uncheckable, never looked up"
$v = Get-HordeProcessVerdict -ProcId 1234 -ProcStart "133420000000000000" -Processes (New-HordeKnown -Value $trip) -Namespace $here_ -Local $here_
Check ($script:lookups -gt 0) "CONTROL: the recording table does record a lookup when one is made"

Complete-HordeSuite -Success "every pid, procStart and path is placed by device and space, and pidDomain never stands in for a device"
