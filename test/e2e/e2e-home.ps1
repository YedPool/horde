# END TO END: `horde home`, `home set` and `home clear`, driven at the real command line (T-0299).
#
# The user of these verbs is whoever moves the fleet to another Horde home: they read where the home is, point the
# whole fleet at a folder in one step, and take it back. This scenario is that, with the shipped horde.ps1 run as its
# own process (test/lib/Cli.ps1):
#   - with no HORDE_HOME and no pointer, the home is the old default and the source says so;
#   - set refuses a relative path, a missing folder and a folder without fleet.db, and writes nothing;
#   - set writes the pointer ({"v":1,"hordeHome":...}, ASCII, no temp file left), prints the old and the new home;
#   - with HORDE_HOME unset, home and a real db verb follow the pointer; HORDE_HOME set beats it;
#   - a bad pointer is refused by name by home and by db, and clear (or set) mends it;
#   - clear removes the pointer and prints what the home is now; clear again is a no-op;
#   - a flag meant for another verb is refused.
# NOTHING REAL IS READ OR WRITTEN: the home and the user profile every child sees are folders this scenario made and
# removes. The real pointer is never touched (CONTRIBUTING 9).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] no node here: fleet.db cannot run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}

$script:work = Join-Path $env:TEMP ("horde-home-e2e-" + [guid]::NewGuid().ToString("N"))
$fakeProfile = Join-Path $script:work "profile"
$homeA = Join-Path $script:work "homeA"
$homeB = Join-Path $script:work "homeB"
$bare = Join-Path $script:work "bare"
New-Item -ItemType Directory -Path $fakeProfile, $homeA, $homeB, $bare -Force | Out-Null
$pointer = Join-Path $fakeProfile ".horde-home.json"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$noHome = @{ HORDE_HOME = ""; USERPROFILE = $fakeProfile }
function Invoke-Home { param([string[]]$HomeArgs, [hashtable]$Env = $noHome) return (Invoke-HordeCliProcess -Root $root -HordeArgs $HomeArgs -Env $Env) }
function Pointer-Text { return [System.IO.File]::ReadAllText($pointer) }

try {

Write-Host ""
Write-Host "=== no pointer ===" -ForegroundColor Cyan
$r = Invoke-Home @("home")
Check ($r.code -eq 0 -and $r.out -like ("*home:   " + (Join-Path $fakeProfile ".horde") + "*") -and $r.out -like "*source: default*") ("home with nothing set is the default under the profile (" + $r.code + ")")
$r = Invoke-Home @("home") @{ HORDE_HOME = $homeB; USERPROFILE = $fakeProfile }
Check ($r.code -eq 0 -and $r.out -like ("*home:   " + $homeB + "*") -and $r.out -like "*source: HORDE_HOME*") "home with HORDE_HOME set says HORDE_HOME gave it"
$r = Invoke-Home @("db", "status")
Check ($r.code -ne 0 -and $r.out -like "*horde db needs HORDE_HOME set*") "db with no HORDE_HOME and no pointer is still refused (never made in the default folder)"

Write-Host ""
Write-Host "=== set refuses ===" -ForegroundColor Cyan
$r = Invoke-Home @("home", "set", "-Path", "relative\folder")
Check ($r.code -ne 0 -and $r.out -like "*absolute*") "a relative path is refused"
$r = Invoke-Home @("home", "set", "-Path", (Join-Path $script:work "nope"))
Check ($r.code -ne 0 -and $r.out -like "*not an existing folder*") "a folder that is not there is refused"
$r = Invoke-Home @("home", "set", "-Path", $bare)
Check ($r.code -ne 0 -and $r.out -like "*no fleet.db*") "a folder without fleet.db is refused"
$r = Invoke-Home @("home", "set")
Check ($r.code -ne 0 -and $r.out -like "*needs -Path*") "set without -Path is refused"
$r = Invoke-Home @("home", "clear", "-Path", $homeA)
Check ($r.code -ne 0 -and $r.out -like "*-Path belongs to home set*") "-Path on clear is refused, not ignored"
Check (-not (Test-Path -LiteralPath $pointer)) "and no refusal wrote a pointer"

Write-Host ""
Write-Host "=== set, then everything follows ===" -ForegroundColor Cyan
foreach ($h in @($homeA, $homeB)) {
    $i = Invoke-HordeCliProcess -Root $root -HordeArgs @("db", "init") -Env @{ HORDE_HOME = $h; USERPROFILE = $fakeProfile }
    Check ($i.code -eq 0) ("db init made fleet.db in " + (Split-Path -Leaf $h))
}
$r = Invoke-Home @("home", "set", "-Path", $homeA)
Check ($r.code -eq 0 -and $r.out -like ("*old home: " + (Join-Path $fakeProfile ".horde") + "*") -and $r.out -like ("*new home: " + $homeA + "*")) ("set prints the old and the new home (" + $r.code + ")")
Check ($r.out -like ("*effective here: " + $homeA + " (pointer)*")) "set then prints the effective home and its source"
Check (($r.out -like "*tasks: *") -or ($r.out -like "*task *")) "and the task check (a count, a task that names another home, or one line saying why it could not be read)"
Check ($r.out -notlike "*WARNING*") "no warning while HORDE_HOME is not set"
Check ((Pointer-Text) -ceq ('{"v":1,"hordeHome":"' + $homeA.Replace("\", "\\") + '"}')) "the pointer is exactly {v 1, hordeHome}"
Check (@([System.IO.File]::ReadAllBytes($pointer) | Where-Object { $_ -gt 0x7E }).Count -eq 0) "and plain ASCII"
Check (@(Get-ChildItem -LiteralPath $fakeProfile -Force | Where-Object { $_.Name -like "*.tmp" }).Count -eq 0) "and no temp file is left behind"
$r = Invoke-Home @("home")
Check ($r.code -eq 0 -and $r.out -like ("*home:   " + $homeA + "*") -and $r.out -like "*source: pointer*") "home now reads the pointer"
$r = Invoke-Home @("db", "status")
Check ($r.code -eq 0 -and $r.out -like ("*" + (Join-Path $homeA "fleet.db") + "*")) "a db verb, with HORDE_HOME unset, works in the pointer home"
$r = Invoke-Home @("db", "status") @{ HORDE_HOME = $homeB; USERPROFILE = $fakeProfile }
Check ($r.code -eq 0 -and $r.out -like ("*" + (Join-Path $homeB "fleet.db") + "*")) "HORDE_HOME set beats the pointer"
$r = Invoke-Home @("home") @{ HORDE_HOME = $homeB; USERPROFILE = $fakeProfile }
Check ($r.code -eq 0 -and $r.out -like "*WARNING: HORDE_HOME is set in this process*overrides the pointer*") "home with HORDE_HOME set while a pointer exists warns that it overrides the pointer"
$r = Invoke-Home @("home", "set", "-Path", $homeB) @{ HORDE_HOME = $homeA; USERPROFILE = $fakeProfile }
Check ($r.code -eq 0 -and $r.out -like ("*effective here: " + $homeA + " (HORDE_HOME)*") -and $r.out -like "*WARNING: HORDE_HOME is set*") "set run with HORDE_HOME set says the effective home is that one, and warns"
$r = Invoke-Home @("home", "set", "-Path", $homeA)
$r = Invoke-Home @("home", "set", "-Path", $homeB)
Check ($r.code -eq 0 -and $r.out -like ("*old home: " + $homeA + "*") -and $r.out -like ("*new home: " + $homeB + "*")) "set again: the old home is the previous pointer's"
$r = Invoke-Home @("db", "status")
Check ($r.code -eq 0 -and $r.out -like ("*" + (Join-Path $homeB "fleet.db") + "*")) "the next call follows the new pointer"

Write-Host ""
Write-Host "=== a running service blocks set until it is stopped ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Path (Join-Path $homeB "settings"), (Join-Path $homeB "relay") -Force | Out-Null
$svc = [ordered]@{ checkout = $root; hordeHome = $homeB; enabled = $true; start = [ordered]@{ kind = "horde"; words = @("relay", "run") }; stop = [ordered]@{ kind = "horde"; words = @("relay", "stop"); waitSeconds = 30 }; alive = [ordered]@{ heartbeat = "relay/run-heartbeat.json"; tickSeconds = 60 } }
[System.IO.File]::WriteAllText((Join-Path (Join-Path $homeB "settings") "service-definitions.json"), (ConvertTo-Json -Depth 8 -InputObject ([ordered]@{ schemaVersion = 1; settings = [ordered]@{ "relay-runner" = $svc } })), $utf8)
$beat = Join-Path (Join-Path $homeB "relay") "run-heartbeat.json"
[System.IO.File]::WriteAllText($beat, ('{"at":"' + [datetime]::UtcNow.ToString("o") + '","pid":4242,"tickSeconds":60,"pass":1}'), $utf8)
$before = Pointer-Text
$r = Invoke-Home @("home", "set", "-Path", $homeA)
Check ($r.code -ne 0 -and $r.out -like "*home set is refused*relay-runner*horde services stop*") "home set while a horde-kind service runs under the current home is refused, naming it and the order"
Check ((Pointer-Text) -ceq $before) "and the pointer is left as it was"
Remove-Item -LiteralPath $beat -Force
$r = Invoke-Home @("home", "set", "-Path", $homeA)
Check ($r.code -eq 0 -and $r.out -like ("*new home: " + $homeA + "*")) "once the service is stopped (no fresh heartbeat), home set goes through"
$r = Invoke-Home @("home", "set", "-Path", $homeB)

Write-Host ""
Write-Host "=== a bad pointer is refused by name ===" -ForegroundColor Cyan
foreach ($bad in @('{"v":2,"hordeHome":"x"}', 'not json', '{"v":1,"hordeHome":"relative"}', ('{"v":1,"hordeHome":"' + (Join-Path $script:work "gone").Replace("\", "\\") + '"}'))) {
    [System.IO.File]::WriteAllText($pointer, $bad, $utf8)
    $r = Invoke-Home @("home")
    Check ($r.code -ne 0 -and $r.out -like ("*" + $pointer + "*refused*")) ("home refuses " + $bad.Substring(0, [Math]::Min(24, $bad.Length)) + ", naming the file")
    $r = Invoke-Home @("db", "status")
    Check ($r.code -ne 0 -and $r.out -like ("*" + $pointer + "*")) "   and so does db status"
}
$r = Invoke-Home @("home", "set", "-Path", $homeA)
Check ($r.code -eq 0 -and $r.out -like ("*new home: " + $homeA + "*")) "set mends a bad pointer"

Write-Host ""
Write-Host "=== clear ===" -ForegroundColor Cyan
$r = Invoke-Home @("home", "clear")
Check ($r.code -eq 0 -and $r.out -like "*pointer removed*" -and $r.out -like ("*home now: " + (Join-Path $fakeProfile ".horde") + " (default)*")) ("clear removes the pointer and prints the home now (" + $r.code + ")")
Check (-not (Test-Path -LiteralPath $pointer)) "the file is gone"
$r = Invoke-Home @("home", "clear")
Check ($r.code -eq 0 -and $r.out -like "*no pointer to remove*") "clear again is a no-op"
[System.IO.File]::WriteAllText($pointer, "garbage", $utf8)
$r = Invoke-Home @("home", "clear")
Check ($r.code -eq 0 -and $r.out -like "*pointer removed*") "clear removes even a bad pointer"
$r = Invoke-Home @("home", "nonsense")
Check ($r.code -ne 0) "an unknown verb is refused"

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-home-e2e-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}

Complete-HordeSuite -Success "horde home shows where the home is, set points the whole fleet at a folder in one atomic step, and clear takes it back"
