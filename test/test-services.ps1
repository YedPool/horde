# IS A SERVICE READ STRICTLY AS DATA, AND DOES THE ONE DECISION HEAL IT WITHOUT EVER LOOPING, GUESSING
# OR MOVING A CHECKOUT IT SHOULD LEAVE ALONE?
#
# core/Services.ps1 (the definition and the pure decision) and core/ServicesFiles.ps1 (the state, the
# journal, the lock). NOTHING REAL IS TOUCHED: the clock is a value this suite moves by hand, a
# process is a row the suite writes into an observation, a checkout is two revision names, and the
# only files are under a Horde home the suite makes in temp and removes. No process is started, and
# no scheduler, messenger or session is reached.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\Services.ps1")
. (Join-Path $root "core\ServicesFiles.ps1")

$work = Join-Path $env:TEMP ("horde-services-" + [guid]::NewGuid().ToString("N"))
$hh = Join-Path $work "home"
[void][System.IO.Directory]::CreateDirectory($hh)
$t0 = [datetime]::new(2026, 10, 13, 12, 0, 0, [System.DateTimeKind]::Utc)
$policy = (Get-HordeServiceSettings -HordeHome $hh).values
$revA = "a" * 40; $revB = "b" * 40; $revC = "c" * 40

function Defs { param([string]$Body) return (Read-HordeServiceDefinitionsText -Text ('{ "schemaVersion": 1, "settings": { ' + $Body + ' } }')) }
function One { param([string]$Body) $r = Defs ('"svc": { ' + $Body + ' }'); if ($r.state -cne "read") { throw ("the fixture definition is refused: " + ($r.findings -join " | ")) }; return $r.services[0] }
function Refused { param([string]$Body, [string]$Like) $r = Defs $Body; return [bool]($r.state -ceq "refused" -and @($r.services).Count -eq 0 -and (@($r.findings) -join " | ") -like ("*" + $Like + "*")) }
$startHorde = '"start": { "kind": "horde", "words": ["relay", "run"], "named": { "Relay": "local" } }'
$stopHorde = '"stop": { "kind": "horde", "words": ["relay", "stop"], "waitSeconds": 20 }'
$places = '"checkout": "C:\\co", "hordeHome": "C:\\hh"'
$beatDef = '"alive": { "heartbeat": "relay\\run-heartbeat.json", "tickSeconds": 60 }'
$followIdle = '"follow": { "restart": "idle", "idleSeconds": 300 }'
$followAny = '"follow": { "restart": "any" }'
$full = $places + ", " + $startHorde + ", " + $stopHorde + ", " + $beatDef + ", " + $followIdle

function Proc { param([int]$Id, [datetime]$Born) return [pscustomobject]@{ pid = $Id; startedAt = $Born } }
function Beat { param([int]$Id, [datetime]$Born, [datetime]$At, [int]$Tick = 60) return (New-HordeKnown -Value ([pscustomobject]@{ at = $At; pid = $Id; startedAt = $Born; tickSeconds = $Tick; pass = [long]1 }) -ObservedAt $At) }
function Co { param([string]$Head, [bool]$Detached = $true, [bool]$Clean = $true, [string]$Branch = "") return (New-HordeKnown -Value ([pscustomobject]@{ head = $Head; detached = $Detached; clean = $Clean; branch = $Branch })) }
function Want { param([string]$Revision, [bool]$Forward = $true) return (New-HordeKnown -Value ([pscustomobject]@{ revision = $Revision; fastForward = $Forward })) }
$none = New-HordeAbsent -Note "none"
function Obs {
    # An observation. -Running is the state's own process when it is alive; -Beat a heartbeat answer;
    # -Beater the process the heartbeat names when THAT is alive and is not the state's own.
    param($Running = $null, $Beat = $null, $Beater = $null, $Checkout = $null, $Wanted = $null, $Idle = $null, $Started = $null)
    $st = $(if ($null -ne $Started) { $Started } elseif ($null -ne $Running) { New-HordeKnown -Value $Running } else { $none })
    $bt = $(if ($null -ne $Beat) { $Beat } else { $none })
    $br = $(if ($null -ne $Beater) { New-HordeKnown -Value $Beater } elseif ($null -ne $Running -and $null -ne $Beat) { New-HordeKnown -Value $Running } else { $none })
    $co = $(if ($null -ne $Checkout) { $Checkout } else { $none })
    $wa = $(if ($null -ne $Wanted) { $Wanted } else { $none })
    $id = $(if ($null -ne $Idle) { $Idle } else { New-HordeUnknown -Reason "nobody looked" })
    return (New-HordeServiceObserved -Started $st -Heartbeat $bt -Beater $br -Checkout $co -Wanted $wa -IdleSeconds $id)
}
function Decide { param($Def, $State, $Seen, [datetime]$At, [switch]$IgnoreIdle) return (Get-HordeServiceDecision -Definition $Def -State $State -Observed $Seen -Now $At -Policy $policy -IgnoreIdle:$IgnoreIdle) }
function Did { param($Def, $Decision, [bool]$Ok, [datetime]$At, $Process = $null, [string]$Detail = "", [string]$Revision = "") return (Complete-HordeServiceStep -Definition $Def -Decision $Decision -Outcome ([pscustomobject]@{ ok = $Ok; detail = $Detail; process = $Process; revision = $Revision }) -Now $At -Policy $policy) }
function Is { param($Decision, [string]$Action, [string]$Step, [string]$Code) return [bool]($Decision.action -ceq $Action -and $Decision.step -ceq $Step -and $Decision.code -ceq $Code) }

try {
    Write-Host ""
    Write-Host "--- a service is data, read strictly ---" -ForegroundColor Cyan
    $r = Defs ('"relay-runner": { ' + $full + ', "confirmSeconds": 90 }, "throttle": { "start": { "kind": "program", "program": "C:\\tools\\throttle.exe", "arguments": ["-quiet", "a b"] }, "stop": { "kind": "kill" } }')
    Check ($r.state -ceq "read" -and @($r.services).Count -eq 2) "two services are read from one file"
    $d = $r.services[0]
    Check ($d.name -ceq "relay-runner" -and $d.enabled -and $d.checkout -ceq "C:\co" -and $d.hordeHome -ceq "C:\hh" -and $d.confirmSeconds -eq 90) "its name, checkout, home and confirm time"
    Check ($d.start.kind -ceq "horde" -and ($d.start.words -join " ") -ceq "relay run" -and $d.start.named["Relay"] -ceq "local") "how it starts: a horde command, its words and its named values"
    Check ($d.stop.kind -ceq "horde" -and ($d.stop.words -join " ") -ceq "relay stop" -and $d.stop.waitSeconds -eq 20) "how it is asked to stop, and for how long"
    Check ($d.alive.heartbeat -ceq "relay\run-heartbeat.json" -and $d.alive.path -ceq "C:\hh\relay\run-heartbeat.json" -and $d.alive.tickSeconds -eq 60) "its heartbeat is a place under the home it serves"
    Check ($d.follow.remote -ceq "origin" -and $d.follow.branch -ceq "main" -and $d.follow.restart -ceq "idle" -and $d.follow.idleSeconds -eq 300) "it follows origin main unless told otherwise, restarted only when the person is idle"
    $p = $r.services[1]
    Check ($p.start.kind -ceq "program" -and $p.start.program -ceq "C:\tools\throttle.exe" -and ($p.start.arguments -join "|") -ceq "-quiet|a b" -and $p.stop.kind -ceq "kill" -and $null -eq $p.alive -and $null -eq $p.follow -and $p.stop.waitSeconds -eq 30 -and $p.confirmSeconds -eq 120) "a service that is not a horde command fits the same shape: a program and its arguments, no heartbeat, nothing followed"
    Check ((Read-HordeServiceDefinitionsText -Text $null).state -ceq "none" -and @((Read-HordeServiceDefinitionsText -Text $null).services).Count -eq 0) "no file is no services, and not an error"
    Check ((Defs "").state -ceq "read" -and @((Defs "").services).Count -eq 0) "an empty settings object is read, with no services"
    $win = One ($places + ', "start": { "kind": "horde", "words": ["decisions", "open"], "named": { "Report": "C:\\r\\report.json" } }, "stop": { "kind": "window", "report": "C:\\r\\report.json" }')
    Check ($win.stop.kind -ceq "window" -and $win.stop.report -ceq "C:\r\report.json") "a window is stopped by closing it, named by its report file"

    $base = $places + ", " + $startHorde + ", " + $stopHorde
    Check (Refused ('"svc": { ' + $base + ', "secretToken": "x" }') "which is not one of") "a member nobody declared refuses the file"
    Check (Refused ('"svc": { ' + $places + ', "start": { "kind": "horde", "words": ["relay"], "extra": 1 }, ' + $stopHorde + ' }') "start has the member 'extra'") "and so does one inside start"
    Check (Refused ('"svc": { ' + $base + ', "follow": { "remote": "origin", "url": "https://example.invalid/x.git" } }') "follow has the member 'url'") "a definition cannot name a remote by address: only a remote the checkout already has"
    Check (Refused ('"ok": { ' + $base + ' }, "svc": { ' + $base + ', "nope": 1 }') "nope") "one bad service refuses every service: none is handed back"
    Check (Refused ('"svc": { "checkout": "co", "hordeHome": "C:\\hh", ' + $startHorde + ', ' + $stopHorde + ' }') "checkout must be an absolute folder") "a relative checkout is refused"
    Check (Refused ('"svc": { ' + $places + ', "start": { "kind": "horde", "words": ["relay", "-Force"] }, ' + $stopHorde + ' }') "not a plain word") "a word that starts with a dash is refused: it would be read as a flag"
    Check (Refused ('"svc": { ' + $places + ', "start": { "kind": "horde", "words": ["relay"], "named": { "Relay": "-x" } }, ' + $stopHorde + ' }') "does not start with a dash") "and so is a named value that does"
    Check (Refused ('"svc": { ' + $places + ', "start": { "kind": "horde", "words": ["relay"], "named": { "Re lay": "x" } }, ' + $stopHorde + ' }') "not a parameter name") "a parameter name is letters and digits"
    Check (Refused ('"svc": { ' + $places + ', "start": { "kind": "horde", "words": ["relay; calc"] }, ' + $stopHorde + ' }') "not a plain word") "a word holds nothing a shell would read"
    Check (Refused ('"svc": { ' + $places + ', "start": { "kind": "shell", "words": ["x"] }, ' + $stopHorde + ' }') "start.kind must be horde or program") "a start of an unknown kind is refused"
    Check (Refused ('"svc": { ' + $places + ', ' + $stopHorde + ' }') "start is missing") "a service that does not say how it starts is refused"
    Check (Refused ('"svc": { ' + $places + ', ' + $startHorde + ' }') "stop is missing") "and one that does not say how it stops"
    Check (Refused ('"svc": { "hordeHome": "C:\\hh", ' + $startHorde + ', ' + $stopHorde + ' }') "checkout is needed") "a horde command needs a checkout"
    Check (Refused ('"svc": { "checkout": "C:\\co", ' + $startHorde + ', ' + $stopHorde + ' }') "hordeHome is needed") "and a home to serve"
    Check (Refused ('"svc": { ' + $base + ', "alive": { "heartbeat": "..\\..\\x.json" } }') "never rooted and never '..'") "a heartbeat cannot climb out of the home"
    Check (Refused ('"svc": { ' + $base + ', "alive": { "heartbeat": "C:\\x.json" } }') "never rooted") "nor be rooted"
    Check (Refused ('"svc": { ' + $base + ', "alive": { "heartbeat": "a.json", "tickSeconds": 0 } }') "tickSeconds must be a whole number from 1 to 3600") "a tick is a whole number in range"
    Check (Refused ('"svc": { ' + $base + ', "follow": { "branch": "main..evil" } }') "follow.branch") "a branch that is not a plain name is refused"
    Check (Refused ('"svc": { ' + $base + ', "follow": { "remote": "https://x" } }') "follow.remote") "and a remote that is not a plain name"
    Check (Refused ('"svc": { ' + $base + ', "follow": { "restart": "now" } }') "restart must be any or idle") "restart is any or idle"
    Check (Refused ('"svc": { "start": { "kind": "program", "program": "C:\\x.exe" }, "stop": { "kind": "kill" }, "follow": {} }') "checkout is needed") "a service that follows a revision has a checkout to move"
    Check (Refused ('"svc": { ' + $base + ', "confirmSeconds": 5 }') "confirmSeconds") "the confirm time is in range"
    Check (Refused ('"svc": { ' + $places + ', ' + $startHorde + ', "stop": { "kind": "window", "report": "r.json" } }') "report must be the absolute path") "a window's report is an absolute path"
    Check (Refused ('"svc": { ' + $base + ', "enabled": "yes" }') "enabled must be true or false") "enabled is true or false, not a word"
    Check (Refused ('"Svc": { ' + $base + ' }') "is not a service name") "a service name is lower-case"
    Check (Refused ('"svc": { ' + $base + ' }, "svc": { ' + $base + ' }') "twice") "a service defined twice is refused, not silently reduced to one"
    Check ((Read-HordeServiceDefinitionsText -Text '{ "schemaVersion": 1 }').state -ceq "refused" -and (Read-HordeServiceDefinitionsText -Text '{ not json').state -ceq "refused" -and (Read-HordeServiceDefinitionsText -Text "").state -ceq "refused") "a file that is not the envelope, not JSON, or empty is refused"
    $many = @(1..33 | ForEach-Object { '"s' + $_ + '": { ' + $base + ' }' }) -join ", "
    Check (Refused $many "more than the 32") "more than 32 services is refused"
    # No definition may carry a secret. The values below are made here, at run time, so no secret-shaped
    # text is written in this file.
    $planted = "ghp_" + ("A1b2C3d4E5f6G7h8I9j0" * 2).Substring(0, 36)
    $sec = Defs ('"svc": { ' + $places + ', "start": { "kind": "horde", "words": ["relay"], "named": { "Token": "' + $planted + '" } }, ' + $stopHorde + ' }')
    Check ($sec.state -ceq "refused" -and ($sec.findings -join " ") -like "*never carries a secret*" -and -not ($sec.findings -join " ").Contains($planted)) "a definition that holds a credential is refused, and the finding never repeats it"
    $secArg = Defs ('"svc": { "start": { "kind": "program", "program": "C:\\x.exe", "arguments": ["--pass' + 'word=' + $planted.Substring(4, 14) + '"] }, "stop": { "kind": "kill" } }')
    Check ($secArg.state -ceq "refused" -and -not ($secArg.findings -join " ").Contains($planted.Substring(4, 14))) "and so is one in a program's arguments"

    [void][System.IO.Directory]::CreateDirectory((Join-Path $hh "settings"))
    Check ((Get-HordeServiceDefinitions -HordeHome $hh).state -ceq "none") "under a home with no definitions file there are none"
    [System.IO.File]::WriteAllText((Get-HordeServiceDefinitionsPath -HordeHome $hh), ('{ "schemaVersion": 1, "settings": { "svc": { ' + $full + ' } } }'))
    $fromFile = Get-HordeServiceDefinitions -HordeHome $hh
    Check ($fromFile.state -ceq "read" -and $fromFile.services[0].name -ceq "svc" -and $fromFile.path -ceq (Join-Path $hh "settings\service-definitions.json")) "the file under the home is read, and the answer says which file"
    [System.IO.File]::WriteAllBytes((Get-HordeServiceDefinitionsPath -HordeHome $hh), [byte[]]@(0xFF, 0xFE, 0x7B, 0x00))
    Check ((Get-HordeServiceDefinitions -HordeHome $hh).state -ceq "refused") "a file that is not UTF-8 is refused, never read as no services"
    [System.IO.File]::Delete((Get-HordeServiceDefinitionsPath -HordeHome $hh))
    Check ($policy.fetchIntervalSeconds -eq 300 -and $policy.failuresBeforeEscalation -eq 3 -and $policy.tellWarchief -eq $true) "the supervisor's own settings: the remote is asked every five minutes, and telling is on by default"

    Write-Host ""
    Write-Host "--- a pid alone is never the service ---" -ForegroundColor Cyan
    $born = $t0.AddHours(-1)
    $claim = Proc 500 $born
    Check ((Get-HordeServiceProcessVerdict -Claim $claim -Entry (New-HordeKnown -Value (Proc 500 $born))).state -ceq "known") "the pid, started when the claim says: it is that process"
    $reused = Get-HordeServiceProcessVerdict -Claim $claim -Entry (New-HordeKnown -Value (Proc 500 $born.AddMinutes(30)))
    Check ($reused.state -ceq "absent" -and $reused.reason -like "*another process now*") "the same pid started at another time is ANOTHER process: the service is gone"
    Check ((Get-HordeServiceProcessVerdict -Claim $claim -Entry $none).state -ceq "absent") "a pid nothing has is gone"
    Check ((Get-HordeServiceProcessVerdict -Claim $claim -Entry (New-HordeUnknown -Reason "table unreadable")).state -ceq "unknown") "a table that could not be read is unknown, never gone"
    Check ((Get-HordeServiceProcessVerdict -Claim ([pscustomobject]@{ pid = 500; startedAt = $null }) -Entry (New-HordeKnown -Value (Proc 500 $born))).state -ceq "unknown") "a claim with no start time is unknown: the pid alone would be deciding"
    Check ((Get-HordeServiceProcessVerdict -Claim $null -Entry $none).state -ceq "absent") "no claim names no process"

    Write-Host ""
    Write-Host "--- alive, starting, hung, gone, unknown ---" -ForegroundColor Cyan
    $svc = One ($base + ", " + $beatDef)
    $plain = One $base
    $st = New-HordeServiceState -Name "svc"
    $run = Proc 700 $t0.AddMinutes(-30)
    $held = Copy-HordeServiceState -State $st; $held.started = [pscustomobject]@{ pid = 700; startedAt = $run.startedAt; at = $run.startedAt }
    $live = { param($Def, $State, $Seen) return (Get-HordeServiceLiveness -Definition $Def -State $State -Observed $Seen -Now $t0) }
    Check ((& $live $svc $held (Obs -Running $run -Beat (Beat 700 $run.startedAt $t0.AddSeconds(-20)))).alive -ceq "yes") "its own process, with a heartbeat of its own 20 s ago: alive"
    Check ((& $live $svc $held (Obs -Running $run -Beat (Beat 700 $run.startedAt $t0.AddSeconds(-181)))).alive -ceq "hung") "its process running and its heartbeat past three ticks: hung"
    Check ((& $live $svc $held (Obs -Running $run -Beat (Beat 700 $run.startedAt $t0.AddSeconds(-181) 600))).alive -ceq "yes") "the same silence from a writer that promised a 600 s tick is not stale: stale is computed"
    $young = Proc 701 $t0.AddSeconds(-30)
    $heldYoung = Copy-HordeServiceState -State $st; $heldYoung.started = [pscustomobject]@{ pid = 701; startedAt = $young.startedAt; at = $young.startedAt }
    Check ((& $live $svc $heldYoung (Obs -Running $young)).alive -ceq "starting") "a process 30 s old that has not beaten yet is starting, not hung"
    Check ((& $live $svc $heldYoung (Obs -Running $young -Beat (Beat 700 $run.startedAt $t0.AddSeconds(-5)))).alive -ceq "starting") "a FRESH heartbeat written by another process does not make this one alive"
    Check ((& $live $svc $held (Obs -Running $run -Beat (Beat 700 $run.startedAt.AddHours(-5) $t0.AddSeconds(-5)))).alive -ceq "hung") "nor does one that names its pid with another start time"
    Check ((& $live $svc $held (Obs -Beat (Beat 700 $run.startedAt $t0.AddSeconds(-5)))).alive -ceq "no") "a fresh heartbeat whose process has ended is not alive"
    Check ((& $live $svc $st (Obs)).alive -ceq "no") "no process and no heartbeat: not running"
    $adopt = & $live $svc $st (Obs -Beat (Beat 800 $born $t0.AddSeconds(-5)) -Beater (Proc 800 $born))
    Check ($adopt.alive -ceq "yes" -and -not $adopt.ours -and $adopt.process.pid -eq 800) "a running process found by its heartbeat, started by someone else, is alive and adopted"
    Check ((& $live $svc $held (Obs -Started (New-HordeUnknown -Reason "no table"))).alive -ceq "unknown") "a process that cannot be checked is unknown"
    Check ((& $live $svc $held (Obs -Running $run -Beat (New-HordeUnknown -Reason "held"))).alive -ceq "unknown") "a heartbeat that cannot be read is unknown"
    Check ((& $live $plain $held (Obs -Running $run)).alive -ceq "yes" -and (& $live $plain $held (Obs)).alive -ceq "no") "a service with no heartbeat is alive exactly while its process is"

    Write-Host ""
    Write-Host "--- start what is not running; never guess ---" -ForegroundColor Cyan
    $s = New-HordeServiceState -Name "svc"
    $d1 = Decide $svc $s (Obs) $t0
    Check ((Is $d1 "start" "start" "start") -and $d1.notify -eq "") "a service that is not running is started"
    $s = Did $svc $d1 $true $t0 (Proc 900 $t0)
    Check ($s.started.pid -eq 900 -and $s.proving -and $s.failures -eq 0 -and $s.lastAction.outcome -ceq "done") "the start is recorded: its process, and that it has yet to prove it lasts"
    $p900 = Proc 900 $t0
    Check (Is (Decide $svc $s (Obs -Running $p900) $t0.AddSeconds(20)) "wait" "" "starting") "while it has not beaten yet, the pass waits"
    $dOk = Decide $svc $s (Obs -Running $p900 -Beat (Beat 900 $t0 $t0.AddSeconds(55))) $t0.AddSeconds(60)
    Check (Is $dOk "nothing" "" "running") "once it beats, there is nothing to do"
    $dUnknown = Decide $svc $s (Obs -Started (New-HordeUnknown -Reason "the table could not be read")) $t0.AddSeconds(60)
    Check ((Is $dUnknown "wait" "" "cannot-tell") -and $dUnknown.reason -like "*the table could not be read*") "when its process cannot be checked the pass WAITS: an unknown is never read as not running, which would start a second copy"
    $dOff = Decide (One ($base + ', "enabled": false')) (New-HordeServiceState -Name "svc") (Obs) $t0
    Check (Is $dOff "nothing" "" "disabled") "a service whose definition says enabled false is left exactly as it is"
    Check ($d1.state.name -ceq "svc" -and $null -eq (New-HordeServiceState -Name "svc").started) "CONTROL: a decision changes the state it returns, never the one it was handed"

    Write-Host ""
    Write-Host "--- never a restart loop: back off, escalate once, say so once on recovery ---" -ForegroundColor Cyan
    $at = $t0.AddSeconds(120)
    $dDied = Decide $svc $s (Obs) $at
    Check ((Is $dDied "wait" "" "backing-off") -and $dDied.state.failures -eq 1 -and $dDied.state.nextStartAt -eq $at.AddSeconds(30)) "a start that did not last is failure 1, and the next start waits 30 s"
    $s = $dDied.state
    Check (Is (Decide $svc $s (Obs) $at.AddSeconds(29)) "wait" "" "backing-off") "29 s later it still waits"
    $d2 = Decide $svc $s (Obs) $at.AddSeconds(30)
    Check (Is $d2 "start" "start" "start") "at 30 s it is started again"
    $s = Did $svc $d2 $true $at.AddSeconds(30) (Proc 901 $at.AddSeconds(30))
    $at = $at.AddSeconds(50)
    $dDied2 = Decide $svc $s (Obs) $at
    Check ($dDied2.state.failures -eq 2 -and $dDied2.state.nextStartAt -eq $at.AddSeconds(60) -and $dDied2.notify -eq "") "the second failure in a row doubles the wait to 60 s, and nobody is told yet"
    $s = $dDied2.state
    $d3 = Decide $svc $s (Obs) $at.AddSeconds(60)
    $s = Did $svc $d3 $false $at.AddSeconds(60) $null "Windows did not create the process"
    Check ($s.failures -eq 3 -and $null -eq $s.started -and $s.nextStartAt -eq $at.AddSeconds(180) -and $s.lastAction.outcome -ceq "failed") "a start that could not be made at all is a failure too: the third, and the wait is 120 s"
    $at = $at.AddSeconds(61)
    $dTell = Decide $svc $s (Obs) $at
    Check ((Is $dTell "wait" "" "backing-off") -and $dTell.notify -ceq "escalate" -and $dTell.notice -like "service svc:*3 starts in a row*" -and @($dTell.state.told) -ccontains "failing") "after three failures in a row someone is told, once"
    $s = $dTell.state
    $dQuiet = Decide $svc $s (Obs) $at.AddSeconds(10)
    Check ($dQuiet.notify -eq "" -and (Is $dQuiet "wait" "" "backing-off")) "the next pass tells nobody again: the trouble is already told"
    $dSlow = Decide $svc $s (Obs) $at.AddSeconds(119)
    Check ((Is $dSlow "start" "start" "start") -and $dSlow.notify -eq "") "and it is still tried, at the slow pace"
    $s = Did $svc $dSlow $true $at.AddSeconds(119) (Proc 902 $at.AddSeconds(119))
    $p902 = Proc 902 $at.AddSeconds(119)
    $dUp = Decide $svc $s (Obs -Running $p902 -Beat (Beat 902 $p902.startedAt $at.AddSeconds(170))) $at.AddSeconds(180)
    Check ($dUp.notify -eq "" -and $dUp.state.failures -eq 3) "running again, but not yet for long: no recovery is claimed, and the failures stand"
    $dWell = Decide $svc $dUp.state (Obs -Running $p902 -Beat (Beat 902 $p902.startedAt $at.AddSeconds(425))) $at.AddSeconds(430)
    Check ($dWell.notify -ceq "recovered" -and $dWell.notice -like "service svc: recovered*" -and $dWell.state.failures -eq 0 -and @($dWell.state.told).Count -eq 0 -and -not $dWell.state.proving) "after it has stayed up 300 s, one recovery is said and the failures are forgotten"
    Check ((Decide $svc $dWell.state (Obs -Running $p902 -Beat (Beat 902 $p902.startedAt $at.AddSeconds(480))) $at.AddSeconds(490)).notify -eq "") "and it is said once"
    $dAgain = Decide $svc $dWell.state (Obs) $at.AddSeconds(5000)
    Check ((Is $dAgain "start" "start" "start") -and $dAgain.state.failures -eq 0) "a service that had proven itself and then dies is started at once: one death is not a loop"
    $capped = Copy-HordeServiceState -State $s; $capped.failures = 40
    Check ((Get-HordeServiceBackoffSeconds -Failures 40 -Policy $policy) -eq 1800 -and (Get-HordeServiceBackoffSeconds -Failures 0 -Policy $policy) -eq 0 -and (Get-HordeServiceBackoffSeconds -Failures 1 -Policy $policy) -eq 30 -and (Get-HordeServiceBackoffSeconds -Failures 4 -Policy $policy) -eq 240) "the wait doubles from 30 s and is capped at 1800 s"

    Write-Host ""
    Write-Host "--- a hung service is stopped, then ended, then started ---" -ForegroundColor Cyan
    $s = New-HordeServiceState -Name "svc"; $s.started = [pscustomobject]@{ pid = 700; startedAt = $run.startedAt; at = $run.startedAt }
    $stale = Beat 700 $run.startedAt $t0.AddSeconds(-400)
    $dHung = Decide $svc $s (Obs -Running $run -Beat $stale) $t0
    Check ((Is $dHung "start" "stop" "hung") -and $dHung.process.pid -eq 700 -and $dHung.state.phase -ceq "stopping" -and $dHung.state.intent -ceq "heal") "a hung service is asked to stop, and the state says so before anything is done"
    $s = Did $svc $dHung $true $t0 $null "asked with horde relay stop"
    Check (Is (Decide $svc $s (Obs -Running $run -Beat $stale) $t0.AddSeconds(10)) "wait" "" "stopping") "while its stop time has not passed, the pass waits"
    $dKill = Decide $svc $s (Obs -Running $run -Beat $stale) $t0.AddSeconds(20)
    Check ((Is $dKill "start" "kill" "stop-overdue") -and $dKill.process.pid -eq 700) "after its 20 s it is ended"
    $sStuck = Did $svc $dKill $false $t0.AddSeconds(20) $null "access denied"
    $dStuck = Decide $svc $sStuck (Obs -Running $run -Beat $stale) $t0.AddSeconds(80)
    Check ($dStuck.step -ceq "kill" -and $dStuck.notify -ceq "escalate" -and $dStuck.notice -like "*could not be ended (access denied)*") "a process that cannot be ended is told about, and tried again"
    $s = Did $svc $dKill $true $t0.AddSeconds(20)
    $dGone = Decide $svc $s (Obs -Beat $stale) $t0.AddSeconds(21)
    Check ((Is $dGone "start" "start" "start") -and $dGone.state.phase -ceq "steady" -and $null -eq $dGone.state.started) "once it is gone it is started, by the ordinary rule"
    Check ((Is (Decide $svc $s (Obs -Started (New-HordeUnknown -Reason "no table") -Beat $stale) $t0.AddSeconds(21)) "wait" "" "cannot-tell")) "and while that cannot be told, nothing is started"

    Write-Host ""
    Write-Host "--- an update: verify, wait for the person, stop, advance, start, confirm ---" -ForegroundColor Cyan
    $up = One $full
    $s = New-HordeServiceState -Name "svc"; $s.started = [pscustomobject]@{ pid = 700; startedAt = $run.startedAt; at = $run.startedAt }; $s.runningRevision = $revA
    $fresh = { param([datetime]$At) return (Beat 700 $run.startedAt $At.AddSeconds(-5)) }
    $dSame = Decide $up $s (Obs -Running $run -Beat (& $fresh $t0) -Checkout (Co $revA) -Wanted (Want $revA)) $t0
    Check (Is $dSame "nothing" "" "current") "running what the remote wants: nothing to do"
    $dNoWant = Decide $up $s (Obs -Running $run -Beat (& $fresh $t0) -Checkout (Co $revA) -Wanted (New-HordeUnknown -Reason "never fetched")) $t0
    Check ((Is $dNoWant "nothing" "" "running") -and $dNoWant.reason -like "*never fetched*") "when what is wanted is not known, the service is left running and the reason said"
    $dVerify = Decide $up $s (Obs -Running $run -Beat (& $fresh $t0) -Checkout (Co $revA) -Wanted (Want $revB) -Idle (New-HordeKnown -Value ([long]9999))) $t0
    Check ((Is $dVerify "restart-for-update" "verify" "verify") -and $dVerify.revision -ceq $revB -and $dVerify.state.phase -ceq "steady") "a new revision is first checked, while the old one runs - whether or not the person is idle"
    $s = Did $up $dVerify $true $t0
    Check ($s.verifiedRevision -ceq $revB -and $null -eq $s.refused) "a passed check is recorded for that revision"
    $seen = { param([datetime]$At, $Idle) return (Obs -Running $run -Beat (& $fresh $At) -Checkout (Co $revA) -Wanted (Want $revB) -Idle $Idle) }
    $dIdleUnknown = Decide $up $s (& $seen $t0 (New-HordeUnknown -Reason "session 0")) $t0
    Check ((Is $dIdleUnknown "wait" "" "idle-unknown") -and $dIdleUnknown.state.phase -ceq "steady") "when it is not known whether the person is idle, the update WAITS: unknown is never idle"
    Check (Is (Decide $up $s (& $seen $t0 (New-HordeKnown -Value ([long]299))) $t0) "wait" "" "not-idle") "299 s without input is not the 300 s asked for: it waits"
    $dNow = Decide $up $s (& $seen $t0 (New-HordeKnown -Value ([long]5))) $t0 -IgnoreIdle
    Check (Is $dNow "restart-for-update" "stop" "update") "rollout -Now sets the idle rule aside"
    $unverified = Copy-HordeServiceState -State $s; $unverified.verifiedRevision = ""
    Check ((Decide $up $unverified (& $seen $t0 (New-HordeKnown -Value ([long]5))) $t0 -IgnoreIdle).step -ceq "verify") "and sets aside nothing else: an unverified revision is still checked first"
    $dStop = Decide $up $s (& $seen $t0 (New-HordeKnown -Value ([long]300))) $t0
    Check ((Is $dStop "restart-for-update" "stop" "update") -and $dStop.state.phase -ceq "stopping" -and $dStop.state.target -ceq $revB -and $dStop.state.from -ceq $revA -and $dStop.process.pid -eq 700) "idle for 300 s: the old process is asked to stop, and the state names both revisions"
    Check ((Decide (One ($places + ", " + $startHorde + ", " + $stopHorde + ", " + $beatDef + ", " + $followAny)) $s (& $seen $t0 (New-HordeUnknown -Reason "session 0")) $t0).step -ceq "stop") "a service that may restart at any time does not ask whether the person is idle"
    $s = Did $up $dStop $true $t0
    $dAdv = Decide $up $s (Obs -Beat (& $fresh $t0) -Checkout (Co $revA) -Wanted (Want $revB)) $t0.AddSeconds(3)
    Check ((Is $dAdv "restart-for-update" "advance" "advance") -and $dAdv.revision -ceq $revB) "once it has stopped, its checkout moves to the wanted revision"
    $s = Did $up $dAdv $true $t0.AddSeconds(4)
    Check ($s.phase -ceq "launching" -and $s.previousRevision -ceq $revA) "the move is recorded, with the revision that ran before"
    $dStart = Decide $up $s (Obs -Checkout (Co $revB) -Wanted (Want $revB)) $t0.AddSeconds(5)
    Check (Is $dStart "restart-for-update" "start" "start-new") "then the new revision is started"
    $newBorn = $t0.AddSeconds(6)
    $s = Did $up $dStart $true $newBorn (Proc 710 $newBorn)
    Check ($s.phase -ceq "confirming" -and $s.confirmBy -eq $newBorn.AddSeconds(120) -and $s.started.pid -eq 710) "and it has 120 s to prove itself"
    $new = Proc 710 $newBorn
    Check (Is (Decide $up $s (Obs -Running $new -Beat (& $fresh $t0) -Checkout (Co $revB) -Wanted (Want $revB)) $newBorn.AddSeconds(30)) "wait" "" "confirming") "the OLD process's heartbeat, still fresh in the file, proves nothing for the new one"
    $dDone = Decide $up $s (Obs -Running $new -Beat (Beat 710 $newBorn $newBorn.AddSeconds(40)) -Checkout (Co $revB) -Wanted (Want $revB)) $newBorn.AddSeconds(45)
    Check ((Is $dDone "nothing" "" "updated") -and $dDone.state.phase -ceq "steady" -and $dDone.state.runningRevision -ceq $revB -and $dDone.state.previousRevision -ceq $revA -and $dDone.reason -like "*updated to bbbbbbbbb (was aaaaaaaaa)*") "a fresh heartbeat of its own confirms the update: running and previous revision are recorded"

    Write-Host ""
    Write-Host "--- a checkout that must be left alone is left alone, and someone is told ---" -ForegroundColor Cyan
    $s = New-HordeServiceState -Name "svc"; $s.started = [pscustomobject]@{ pid = 700; startedAt = $run.startedAt; at = $run.startedAt }; $s.runningRevision = $revA; $s.verifiedRevision = $revB
    $idle = New-HordeKnown -Value ([long]9999)
    $dDirty = Decide $up $s (Obs -Running $run -Beat (& $fresh $t0) -Checkout (Co $revA $true $false) -Wanted (Want $revB) -Idle $idle) $t0
    Check ((Is $dDirty "wait" "" "dirty") -and $dDirty.notify -ceq "escalate" -and $dDirty.notice -like "*local changes*nothing was touched*" -and $dDirty.state.phase -ceq "steady") "a checkout with local changes: wait, tell, touch nothing"
    Check ((Decide $up $dDirty.state (Obs -Running $run -Beat (& $fresh $t0) -Checkout (Co $revA $true $false) -Wanted (Want $revB) -Idle $idle) $t0.AddSeconds(60)).notify -eq "") "told once, not every pass"
    Check ((Decide $up $s (Obs -Running $run -Beat (& $fresh $t0) -Checkout (Co $revA $true $false) -Wanted (Want $revB) -Idle $idle) $t0 -IgnoreIdle).code -ceq "dirty") "rollout -Now does not set that aside"
    $dDiverged = Decide $up $s (Obs -Running $run -Beat (& $fresh $t0) -Checkout (Co $revA) -Wanted (Want $revB $false) -Idle $idle) $t0
    Check ((Is $dDiverged "wait" "" "diverged") -and $dDiverged.notify -ceq "escalate" -and $dDiverged.notice -like "*diverged*") "a wanted revision that is not a fast-forward: wait and tell"
    $dBranch = Decide $up $s (Obs -Running $run -Beat (& $fresh $t0) -Checkout (Co $revA $false $true "feature/x") -Wanted (Want $revB) -Idle $idle) $t0
    Check ((Is $dBranch "wait" "" "on-a-branch") -and $dBranch.notice -like "*feature/x*") "a checkout on a branch is somebody's work: wait and tell"
    $dMended = Decide $up $dDirty.state (Obs -Running $run -Beat (& $fresh $t0) -Checkout (Co $revA) -Wanted (Want $revA)) $t0.AddSeconds(120)
    Check ($dMended.notify -ceq "recovered" -and @($dMended.state.told).Count -eq 0) "when the trouble is gone and the service is well, that is said once"

    Write-Host ""
    Write-Host "--- a revision that fails its check is not started; it is tried again later ---" -ForegroundColor Cyan
    $s = New-HordeServiceState -Name "svc"; $s.started = [pscustomobject]@{ pid = 700; startedAt = $run.startedAt; at = $run.startedAt }; $s.runningRevision = $revA
    $dV = Decide $up $s (& $seen $t0 $idle) $t0
    $s = Did $up $dV $false $t0 $null "cli/Broken.ps1 does not parse (line 3)"
    Check ($s.refused.kind -ceq "verify" -and $s.refused.revision -ceq $revB -and $s.verifiedRevision -eq "" -and $s.phase -ceq "steady") "a failed check is recorded against that revision, and nothing was stopped"
    $dNot = Decide $up $s (& $seen $t0.AddMinutes(1) $idle) $t0.AddMinutes(1)
    Check ((Is $dNot "wait" "" "not-verified") -and $dNot.notify -ceq "escalate" -and $dNot.notice -like "*failed its check*does not parse*old revision keeps running*") "the update waits as not verified, and someone is told why"
    Check ((Decide $up $dNot.state (& $seen $t0.AddMinutes(29) $idle) $t0.AddMinutes(29)).code -ceq "not-verified") "29 minutes later it still waits"
    Check ((Decide $up $dNot.state (& $seen $t0.AddMinutes(30) $idle) $t0.AddMinutes(30)).step -ceq "verify") "after 30 minutes the check is tried again"
    $dNewer = Decide $up $dNot.state (Obs -Running $run -Beat (& $fresh $t0) -Checkout (Co $revA) -Wanted (Want $revC) -Idle $idle) $t0.AddMinutes(2)
    Check ($dNewer.step -ceq "verify" -and $dNewer.revision -ceq $revC) "a newer revision is checked at once: the refusal was of the other one"

    Write-Host ""
    Write-Host "--- a new revision that does not come up is rolled back, pinned, and told ---" -ForegroundColor Cyan
    $s = New-HordeServiceState -Name "svc"; $s.phase = "confirming"; $s.intent = "update"; $s.phaseSince = $newBorn; $s.target = $revB; $s.from = $revA
    $s.runningRevision = $revA; $s.previousRevision = $revA; $s.verifiedRevision = $revB; $s.confirmBy = $newBorn.AddSeconds(120); $s.started = [pscustomobject]@{ pid = 710; startedAt = $newBorn; at = $newBorn }
    Check (Is (Decide $up $s (Obs -Running $new -Checkout (Co $revB) -Wanted (Want $revB)) $newBorn.AddSeconds(119)) "wait" "" "confirming") "one second before its time is up it is still waited for"
    $dBack = Decide $up $s (Obs -Running $new -Checkout (Co $revB) -Wanted (Want $revB)) $newBorn.AddSeconds(120)
    Check ((Is $dBack "roll-back" "stop" "roll-back") -and $dBack.process.pid -eq 710 -and $dBack.state.intent -ceq "rollback" -and $dBack.notify -ceq "escalate" -and $dBack.notice -like "*bbbbbbbbb did not prove itself*rolled back to aaaaaaaaa*not tried again until a newer one exists*") "no fresh heartbeat in 120 s: it is stopped to be rolled back, and someone is told"
    $s2 = Did $up $dBack $true $newBorn.AddSeconds(120)
    $dRetreat = Decide $up $s2 (Obs -Checkout (Co $revB) -Wanted (Want $revB)) $newBorn.AddSeconds(123)
    Check ((Is $dRetreat "roll-back" "retreat" "retreat") -and $dRetreat.revision -ceq $revA -and $dRetreat.notify -eq "") "once it has stopped, the checkout goes back to the previous revision; nobody is told twice"
    $s2 = Did $up $dRetreat $true $newBorn.AddSeconds(124)
    Check ($s2.pinnedRevision -ceq $revB -and $s2.phase -ceq "launching" -and $s2.verifiedRevision -eq "") "the bad revision is pinned"
    $dPrev = Decide $up $s2 (Obs -Checkout (Co $revA) -Wanted (Want $revB)) $newBorn.AddSeconds(125)
    Check ((Is $dPrev "roll-back" "start" "start-previous") -and $dPrev.revision -ceq $revA) "and the previous revision is started"
    $oldBorn = $newBorn.AddSeconds(126)
    $s2 = Did $up $dPrev $true $oldBorn (Proc 720 $oldBorn)
    Check ($s2.phase -ceq "steady" -and $s2.runningRevision -ceq $revA -and $s2.started.pid -eq 720) "it is running the previous revision again"
    $old = Proc 720 $oldBorn
    $dPinned = Decide $up $s2 (Obs -Running $old -Beat (Beat 720 $oldBorn $oldBorn.AddSeconds(50)) -Checkout (Co $revA) -Wanted (Want $revB) -Idle $idle) $oldBorn.AddSeconds(60)
    Check ((Is $dPinned "wait" "" "pinned") -and $dPinned.notify -eq "") "the pinned revision is not tried again, however idle the person is"
    Check ((Decide $up $s2 (Obs -Running $old -Beat (Beat 720 $oldBorn $oldBorn.AddSeconds(50)) -Checkout (Co $revA) -Wanted (Want $revB) -Idle $idle) $oldBorn.AddSeconds(60) -IgnoreIdle).code -ceq "pinned") "nor by rollout -Now"
    $dNext = Decide $up $s2 (Obs -Running $old -Beat (Beat 720 $oldBorn $oldBorn.AddSeconds(50)) -Checkout (Co $revA) -Wanted (Want $revC) -Idle $idle) $oldBorn.AddSeconds(60)
    Check ($dNext.step -ceq "verify" -and $dNext.revision -ceq $revC) "a NEWER revision is taken up: the pin was of the bad one alone"
    $dDead = Decide $up $s (Obs -Checkout (Co $revB) -Wanted (Want $revB)) $newBorn.AddSeconds(10)
    Check ((Is $dDead "roll-back" "retreat" "retreat") -and $dDead.notify -ceq "escalate") "a new revision whose process ends before it is confirmed is rolled back at once, with no wait"
    $launch = Copy-HordeServiceState -State $s; $launch.phase = "launching"; $launch.started = $null; $launch.confirmBy = $null
    $dL = Decide $up $launch (Obs -Checkout (Co $revB) -Wanted (Want $revB)) $newBorn
    $failed = Did $up $dL $false $newBorn $null "there is no horde entry point"
    Check ($failed.phase -ceq "stopping" -and $failed.intent -ceq "rollback" -and (Decide $up $failed (Obs -Checkout (Co $revB) -Wanted (Want $revB)) $newBorn.AddSeconds(1)).step -ceq "retreat") "a new revision that cannot even be started is rolled back"
    $sBad = Did $up $dRetreat $false $newBorn.AddSeconds(124) $null "its checkout has local changes"
    Check ($sBad.pinnedRevision -ceq $revB -and $sBad.refused.kind -ceq "retreat" -and $sBad.phase -ceq "steady") "a roll-back that could not be done still pins the revision"
    $dBad = Decide $up $sBad (Obs -Checkout (Co $revB) -Wanted (Want $revB)) $newBorn.AddSeconds(200)
    Check ($dBad.notify -ceq "escalate" -and $dBad.notice -like "*roll-back from bbbbbbbbb could not be done*needs a person*" -and $dBad.step -ceq "start") "and says its checkout needs a person, while still starting what is there"
    $dHand = Decide $up $sBad (Obs -Checkout (Co $revA) -Wanted (Want $revB)) $newBorn.AddSeconds(200)
    Check ($null -eq $dHand.state.refused) "once a person has moved the checkout off that revision, that trouble is over"
    $sAdv = New-HordeServiceState -Name "svc"; $sAdv.phase = "stopping"; $sAdv.intent = "update"; $sAdv.phaseSince = $t0; $sAdv.target = $revB; $sAdv.from = $revA; $sAdv.runningRevision = $revA; $sAdv.verifiedRevision = $revB
    $dA = Decide $up $sAdv (Obs -Checkout (Co $revA) -Wanted (Want $revB)) $t0.AddSeconds(2)
    $sNo = Did $up $dA $false $t0.AddSeconds(3) $null "it is no longer what origin/main names"
    $dOld = Decide $up $sNo (Obs -Checkout (Co $revA) -Wanted (Want $revB)) $t0.AddSeconds(4)
    Check ($sNo.phase -ceq "steady" -and $sNo.refused.kind -ceq "apply" -and (Is $dOld "start" "start" "start")) "a checkout that would not move leaves the old revision, which is started as a service that is simply not running"

    Write-Host ""
    Write-Host "--- a service with no heartbeat proves itself by staying up ---" -ForegroundColor Cyan
    $quiet = One ($base + ", " + $followAny + ', "confirmSeconds": 60')
    $s = New-HordeServiceState -Name "svc"; $s.phase = "confirming"; $s.intent = "update"; $s.phaseSince = $t0; $s.target = $revB; $s.from = $revA; $s.confirmBy = $t0.AddSeconds(60); $s.started = [pscustomobject]@{ pid = 730; startedAt = $t0; at = $t0 }
    $p730 = Proc 730 $t0
    Check (Is (Decide $quiet $s (Obs -Running $p730 -Checkout (Co $revB) -Wanted (Want $revB)) $t0.AddSeconds(59)) "wait" "" "confirming") "still running at 59 s is not yet confirmed"
    Check (Is (Decide $quiet $s (Obs -Running $p730 -Checkout (Co $revB) -Wanted (Want $revB)) $t0.AddSeconds(60)) "nothing" "" "updated") "still running at its 60 s is"
    Check ((Decide $quiet $s (Obs -Checkout (Co $revB) -Wanted (Want $revB)) $t0.AddSeconds(30)).step -ceq "retreat") "and one that has ended by then is rolled back"

    Write-Host ""
    Write-Host "--- an adopted service, and a checkout moved by hand ---" -ForegroundColor Cyan
    $s = New-HordeServiceState -Name "svc"
    $dAdopt = Decide $up $s (Obs -Beat (Beat 800 $born $t0.AddSeconds(-5)) -Beater (Proc 800 $born) -Checkout (Co $revA) -Wanted (Want $revA)) $t0
    Check ((Is $dAdopt "nothing" "" "current") -and $dAdopt.state.started.pid -eq 800 -and $dAdopt.state.runningRevision -ceq $revA -and -not $dAdopt.state.proving) "a service somebody else started is adopted by its heartbeat, not started a second time"
    $moved = Copy-HordeServiceState -State $dAdopt.state; $moved.verifiedRevision = $revB
    $dMoved = Decide $up $moved (Obs -Running (Proc 800 $born) -Beat (Beat 800 $born $t0.AddSeconds(-5)) -Checkout (Co $revB) -Wanted (Want $revB) -Idle $idle) $t0
    Check ((Is $dMoved "restart-for-update" "stop" "update") -and $dMoved.state.from -ceq $revA) "a checkout already on the wanted revision, with the service still running the old one, is still a restart"

    Write-Host ""
    Write-Host "--- notices wait in the state until they are told ---" -ForegroundColor Cyan
    $n1 = Add-HordeServiceNotice -State $dTell.state -Decision $dTell -Id "11111111-1111-1111-1111-111111111111" -Now $t0
    Check (@($n1.notices).Count -eq 1 -and $n1.notices[0].kind -ceq "escalate" -and $n1.notices[0].id -ceq "11111111-1111-1111-1111-111111111111" -and @($dTell.state.notices).Count -eq 0) "a decision's notice is added to the state, under the id it will be posted by"
    Check (@((Add-HordeServiceNotice -State $n1 -Decision $dQuiet -Id "22222222-2222-2222-2222-222222222222" -Now $t0).notices).Count -eq 1) "a decision with nothing to tell adds nothing"
    $flood = $n1
    foreach ($i in 1..15) { $flood = Add-HordeServiceNotice -State $flood -Decision $dTell -Id ([guid]::NewGuid().ToString()) -Now $t0 }
    Check (@($flood.notices).Count -eq 10) "at most ten wait: the oldest go first"

    Write-Host ""
    Write-Host "--- the remote is asked at an interval, not every pass ---" -ForegroundColor Cyan
    Check (Test-HordeServiceFetchDue -LastFetchAt $null -Now $t0 -IntervalSeconds 300) "never asked: due"
    Check (-not (Test-HordeServiceFetchDue -LastFetchAt $t0.AddSeconds(-299) -Now $t0 -IntervalSeconds 300)) "asked 299 s ago: not due"
    Check (Test-HordeServiceFetchDue -LastFetchAt $t0.AddSeconds(-300) -Now $t0 -IntervalSeconds 300) "asked 300 s ago: due"
    Check (Test-HordeServiceFetchDue -LastFetchAt $t0.AddSeconds(50) -Now $t0 -IntervalSeconds 300) "asked in the future (a clock set back): due, rather than wait for the clock"

    Write-Host ""
    Write-Host "--- status says what a pass would do, and does nothing ---" -ForegroundColor Cyan
    $s = New-HordeServiceState -Name "svc"; $s.started = [pscustomobject]@{ pid = 700; startedAt = $run.startedAt; at = $run.startedAt }; $s.runningRevision = $revA; $s.failures = 2; $s.told = [string[]]@("checkout:dirty")
    $status = Get-HordeServiceStatus -Definition $up -State $s -Observed (Obs -Running $run -Beat (& $fresh $t0) -Checkout (Co $revA $true $false) -Wanted (Want $revB) -Idle $idle) -Now $t0 -Policy $policy
    Check ($status.alive -ceq "yes" -and $status.pid -eq 700 -and $status.heartbeatAgeSeconds -eq 5 -and $status.runningRevision -ceq $revA -and $status.wantedRevision -ceq $revB -and $status.current -eq $false) "alive, its pid, its heartbeat's age, running against wanted"
    Check ($status.next -ceq "wait" -and $status.nextReason -like "*local changes*" -and $status.failures -eq 2 -and @($status.escalated) -ccontains "checkout:dirty") "what a pass would do and why, the failures in a row, and the escalation outstanding"
    Check (@($s.told).Count -eq 1 -and $s.phase -ceq "steady") "CONTROL: asking for status changed nothing"

    Write-Host ""
    Write-Host "--- the state file ---" -ForegroundColor Cyan
    Check ((Read-HordeServiceState -Name "svc" -HordeHome $hh).state -ceq "absent") "a service the supervisor has never kept state of is absent"
    $keep = Copy-HordeServiceState -State $dBack.state
    $keep.refused = [pscustomobject]@{ revision = $revB; kind = "verify"; reason = ("fetch failed from https://user:" + $planted + "@example.invalid/x.git"); at = $t0 }
    $keep.lastAction = [pscustomobject]@{ at = $t0; action = "roll-back"; step = "stop"; outcome = "done"; reason = "asked" }
    $keep.nextStartAt = $t0.AddSeconds(30); $keep.lastFetchAt = $t0; $keep.failures = 2; $keep.proving = $true; $keep.pinnedRevision = $revC
    $keep = Add-HordeServiceNotice -State $keep -Decision $dBack -Id "33333333-3333-3333-3333-333333333333" -Now $t0
    Write-HordeServiceState -State $keep -HordeHome $hh
    $back = Read-HordeServiceState -Name "svc" -HordeHome $hh
    Check ($back.state -ceq "known" -and $back.value.phase -ceq "stopping" -and $back.value.intent -ceq "rollback" -and $back.value.target -ceq $revB -and $back.value.from -ceq $revA -and $back.value.pinnedRevision -ceq $revC) "phase, intent and revisions come back"
    Check ($back.value.started.pid -eq 710 -and $back.value.started.startedAt.Ticks -eq $newBorn.Ticks -and $back.value.phaseSince -eq $keep.phaseSince -and $back.value.nextStartAt -eq $t0.AddSeconds(30) -and $back.value.failures -eq 2 -and $back.value.proving) "the process, to the tick of its start, and the times and counters"
    Check (@($back.value.told) -ccontains ("rolled-back:" + $revB) -and @($back.value.notices).Count -eq 1 -and $back.value.notices[0].id -ceq "33333333-3333-3333-3333-333333333333" -and $back.value.lastAction.step -ceq "stop") "what was told, what is still to tell, and the last action"
    $onDisk = [System.IO.File]::ReadAllText((Get-HordeServiceStatePath -Name "svc" -HordeHome $hh))
    Check (-not $onDisk.Contains($planted) -and $back.value.refused.reason -like "fetch failed from*") "a reason that quoted a credential is kept without it: nothing secret is written"
    Check (@(Get-ChildItem -LiteralPath (Join-Path $hh "services\state")).Count -eq 1) "the state is one file: its temporary copy became it"
    $statePath = Get-HordeServiceStatePath -Name "svc" -HordeHome $hh
    [System.IO.File]::WriteAllText($statePath, "{ not json")
    $broken = Read-HordeServiceState -Name "svc" -HordeHome $hh
    Check ($broken.state -ceq "unknown" -and $broken.reason -like "*could not be read*") "a state file that cannot be read is UNKNOWN, never a fresh state: that would forget the pin and the failures"
    foreach ($case in @(
        @('{ "schemaVersion": 2, "name": "svc", "phase": "steady" }', "schemaVersion"),
        @('{ "schemaVersion": 1, "name": "other", "phase": "steady" }', "not the state of svc"),
        @('{ "schemaVersion": 1, "name": "svc", "phase": "exploding" }', "phase"),
        @(('{ "schemaVersion": 1, "name": "svc", "phase": "stopping", "intent": "update", "target": "' + $revB + '", "from": "' + $revA + '" }'), "since when"),
        @('{ "schemaVersion": 1, "name": "svc", "phase": "stopping", "phaseSince": "2026-10-13T12:00:00Z" }', "does not say what"),
        @('{ "schemaVersion": 1, "name": "svc", "phase": "launching", "intent": "update", "phaseSince": "2026-10-13T12:00:00Z" }', "between which revisions"),
        @('{ "schemaVersion": 1, "name": "svc", "phase": "steady", "pinnedRevision": "HEAD" }', "pinnedRevision is not a revision"),
        @('{ "schemaVersion": 1, "name": "svc", "phase": "steady", "started": { "pid": 5 } }', "process it names is not whole"),
        @('{ "schemaVersion": 1, "name": "svc", "phase": "steady", "nextStartAt": "soon" }', "nextStartAt is not a time")
    )) {
        [System.IO.File]::WriteAllText($statePath, $case[0])
        $got = Read-HordeServiceState -Name "svc" -HordeHome $hh
        Check ($got.state -ceq "unknown" -and $got.reason -like ("*" + $case[1] + "*")) ("a state file the next pass could not act on safely is unknown: " + $case[1])
    }
    [System.IO.File]::WriteAllText($statePath, '{ "schemaVersion": 1, "name": "svc", "phase": "steady" }')
    Check ((Read-HordeServiceState -Name "svc" -HordeHome $hh).state -ceq "known") "CONTROL: the smallest whole state is read"
    Check (Throws { Get-HordeServiceStatePath -Name "..\x" -HordeHome $hh } "not a service name") "a state path is never made from something that is not a service name"

    Write-Host ""
    Write-Host "--- the journal: a line for what is done, and for a wait when it begins ---" -ForegroundColor Cyan
    Check ((Test-HordeServiceWorthSaying -Decision $d1 -LastSaid (Get-HordeServiceSaidKey -Decision $d1))) "a step is always worth a line, even the same step again"
    Check ((Test-HordeServiceWorthSaying -Decision $dQuiet -LastSaid "") -and -not (Test-HordeServiceWorthSaying -Decision $dQuiet -LastSaid (Get-HordeServiceSaidKey -Decision $dQuiet))) "a wait is worth a line when it begins, and not on every pass while it lasts"
    Check (Test-HordeServiceWorthSaying -Decision $dQuiet -LastSaid (Get-HordeServiceSaidKey -Decision $dIdleUnknown)) "a wait for another reason is a new line"
    $wrote = Write-HordeServiceJournal -HordeHome $hh -Entries @((New-HordeServiceJournalEntry -At $t0 -Service "svc" -Action "start" -Step "start" -Code "start" -Outcome "done" -Reason ("started; token " + $planted)), $null, (New-HordeServiceJournalEntry -At $t0.AddSeconds(1) -Service "svc" -Action "wait" -Code "starting" -Reason "line`ntwo"))
    $tail = @(Read-HordeServiceJournalTail -Count 5 -HordeHome $hh)
    Check ($wrote -eq 2 -and $tail.Count -eq 2 -and ($tail[0] | ConvertFrom-Json).service -ceq "svc" -and ($tail[0] | ConvertFrom-Json).outcome -ceq "done") "each entry is one line of JSON"
    Check (-not ($tail -join "").Contains($planted) -and ($tail[1] | ConvertFrom-Json).reason -ceq "line two") "a reason is one line, with nothing secret in it"
    $null = Write-HordeServiceJournal -HordeHome $hh -MaxBytes 10 -Entries @(New-HordeServiceJournalEntry -At $t0.AddSeconds(2) -Service "svc" -Action "nothing" -Code "running" -Reason "third")
    Check ((Test-Path -LiteralPath (Join-Path $hh "services\journal.1.jsonl")) -and @(Get-Content -LiteralPath (Join-Path $hh "services\journal.jsonl")).Count -eq 1 -and @(Read-HordeServiceJournalTail -Count 2 -HordeHome $hh).Count -eq 2) "a journal at its cap is set aside and a new one begun; the tail reads across both"
    Check ((Write-HordeServiceJournal -HordeHome $hh -Entries @()) -eq 0) "no entries write nothing"

    Write-Host ""
    Write-Host "--- one pass at a time ---" -ForegroundColor Cyan
    $lock = Enter-HordeServiceTendLock -HordeHome $hh
    Check ($null -ne $lock) "the first pass takes the lock"
    Check ($null -eq (Enter-HordeServiceTendLock -HordeHome $hh)) "a second pass on the same home does not"
    $naps = New-Object System.Collections.ArrayList
    Check ($null -eq (Enter-HordeServiceTendLock -HordeHome $hh -WaitSeconds 2 -Sleep { param($Ms) [void]$naps.Add($Ms) }) -and $naps.Count -eq 4) "one that is willing to wait 2 s tries again every half second, then gives up"
    $lock.Dispose()
    $again = Enter-HordeServiceTendLock -HordeHome $hh
    Check ($null -ne $again) "once the first has let go, the lock is free"
    $again.Dispose()
    $log = Step-HordeServiceLog -Name "svc" -HordeHome $hh -MaxBytes 5
    [System.IO.File]::WriteAllText($log, "0123456789")
    $null = Step-HordeServiceLog -Name "svc" -HordeHome $hh -MaxBytes 5
    Check ($log -ceq (Join-Path $hh "services\logs\svc.log") -and -not (Test-Path -LiteralPath $log) -and (Test-Path -LiteralPath (Join-Path $hh "services\logs\svc.1.log"))) "a service's output file at its cap is set aside before the next start"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "a service is strict data, and the one decision starts, heals, updates and rolls back without looping, guessing or touching a checkout it must leave alone"
