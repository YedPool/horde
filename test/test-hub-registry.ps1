# DOES THE HUB'S REGISTER ADMIT ONLY A DEVICE IT ENROLLED, LIVE, WITH THE KEY ITS TRANSPORT STILL HOLDS?
#
# Issue #144, item 3, and issue #124. cli/HubRegistry.ps1 keeps one entry per enrolled device under
# <home>\hub\nodes, written by `horde hub enroll` and `horde hub revoke`; `horde hub serve` binds a dialled
# link only when Test-HordeHubAdmits says both records agree, and `horde listen` serves a key line only for
# a device whose entry is live with that key. This suite, in a temporary home:
#   - an entry is written whole, checked by schema/hub-enrolment.v1, this user's alone, renamed into place;
#   - read back, an entry that names another device, fails the schema or is not JSON is unknown, never
#     a guessed enrolment; a device with no entry is absent;
#   - a live entry gives its key; a revoked one, or one past its expiry (the transport's rule: from 00:00 of that
#     day), gives the reason;
#   - Test-HordeHubAdmits admits only when the register and a stand-in transport agree, and a transport
#     that refuses, holds another key or throws refuses the link.
# The transport's own half and the commands that write the register are in that transport's
# enrolment suite.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Schema", "ReadShared", "FileAtomic")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "cli\HubRegistry.ps1")

$tmp = Join-Path $env:TEMP ("horde-hub-registry-" + [guid]::NewGuid().ToString("N"))
$hh = Join-Path $tmp "home"
$dev = "0f8fad5b-d9cb-469f-a165-70867728950e"
$other = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
$key = "key-type " + ("A" * 68)
$key2 = "key-type " + ("B" * 68)
# Noon UTC, so the local date is the same day in every time zone this box is set to.
$now = [datetime]::SpecifyKind([datetime]"2026-10-11T12:00:00", [System.DateTimeKind]::Utc)
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User

try {
    New-Item -ItemType Directory -Path $hh | Out-Null

    Write-Host ""
    Write-Host "--- an entry: written whole, checked, this user's alone ---" -ForegroundColor Cyan
    $path = Add-HordeHubEnrolment -HordeHome $hh -DeviceId $dev -Transport "fake" -Key $key -Expires "20271011" -Now $now
    Check ($path -ceq (Join-Path $hh ("hub\nodes\" + $dev + ".json")) -and (Test-Path -LiteralPath $path -PathType Leaf)) ("an entry is <home>\hub\nodes\<device>.json (" + $path + ")")
    $e = Read-HordeHubEnrolment -HordeHome $hh -DeviceId $dev
    Check ($e.state -ceq "known" -and $e.value.key -ceq $key -and $e.value.transport -ceq "fake" -and $e.value.expires -ceq "20271011" -and $e.value.enrolledAt -ceq "2026-10-11T12:00:00Z" -and $null -eq $e.value.PSObject.Properties["revokedAt"]) "read back, it is the device, its transport, its key, its expiry and when it was enrolled, not revoked"
    $acl = Get-Acl -LiteralPath $path
    $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    Check ($acl.AreAccessRulesProtected -and $rules.Count -eq 1 -and "$($rules[0].IdentityReference)" -ceq "$me") ("it is this user's alone, inheritance cut (" + @($rules | ForEach-Object { "$($_.IdentityReference)" }) -join ", " + ")")
    $folderRules = @((Get-Acl -LiteralPath (Split-Path -Parent $path)).Access)
    Check ($folderRules.Count -gt 1) "CONTROL: its folder admits more than this user, so the file's own ACL is doing the work"
    Check (@(Get-ChildItem -LiteralPath (Split-Path -Parent $path) -File -Filter "*.tmp").Count -eq 0) "no temporary file is left beside it"
    $threw = ""
    try { $null = Write-HordeHubEnrolment -HordeHome $hh -Entry ([pscustomobject]@{ schemaVersion = 1; deviceId = $dev; transport = "fake"; key = $key; expires = "2027-10-11"; enrolledAt = "2026-10-11T12:00:00Z" }) } catch { $threw = $_.Exception.Message }
    Check ($threw -clike "*not one to write*" -and (Read-HordeHubEnrolment -HordeHome $hh -DeviceId $dev).value.expires -ceq "20271011") ("an entry that fails the schema is never written, and the old one stands (" + $threw + ")")
    $threw = ""
    try { $null = Get-HordeHubEnrolmentPath -HordeHome $hh -DeviceId ("..\" + $dev) } catch { $threw = $_.Exception.Message }
    Check ($threw -clike "*not a device id*") "only a device id names an entry: no '..', nothing else"

    Write-Host ""
    Write-Host "--- an entry that cannot be trusted is unknown, never a guess ---" -ForegroundColor Cyan
    Check ((Read-HordeHubEnrolment -HordeHome $hh -DeviceId $other).state -ceq "absent") "a device with no entry is absent"
    $op = Get-HordeHubEnrolmentPath -HordeHome $hh -DeviceId $other
    [System.IO.File]::WriteAllText($op, ([System.IO.File]::ReadAllText($path)))
    $r = Read-HordeHubEnrolment -HordeHome $hh -DeviceId $other
    Check ($r.state -ceq "unknown" -and $r.reason -clike ("*names device " + $dev + ", not " + $other + "*")) ("an entry copied under another device's name is refused, naming both (" + $r.reason + ")")
    $k = Get-HordeHubEnrolledKey -HordeHome $hh -DeviceId $other -Now $now
    Check ($k.state -ceq "unknown") "and gives no key"
    [System.IO.File]::WriteAllText($op, ([System.IO.File]::ReadAllText($path)).Replace($dev, $other).Replace('"schemaVersion":1', '"schemaVersion":1,"admin":true'))
    Check ((Read-HordeHubEnrolment -HordeHome $hh -DeviceId $other).state -ceq "unknown") "an entry with a field the schema does not have is refused"
    [System.IO.File]::WriteAllText($op, "not json")
    Check ((Read-HordeHubEnrolment -HordeHome $hh -DeviceId $other).state -ceq "unknown") "an entry that is not JSON is refused"
    Remove-Item -LiteralPath $op

    Write-Host ""
    Write-Host "--- live: not revoked, not past its expiry ---" -ForegroundColor Cyan
    $k = Get-HordeHubEnrolledKey -HordeHome $hh -DeviceId $dev -Now $now
    Check ($k.state -ceq "known" -and $k.value -ceq $key) "CONTROL: a live entry gives its key"
    $dayBefore = [datetime]::SpecifyKind([datetime]"2027-10-10T23:59:00", [System.DateTimeKind]::Local).ToUniversalTime()
    $midnight = [datetime]::SpecifyKind([datetime]"2027-10-11T00:00:00", [System.DateTimeKind]::Local).ToUniversalTime()
    Check ((Get-HordeHubEnrolledKey -HordeHome $hh -DeviceId $dev -Now $dayBefore).state -ceq "known") "a minute before 00:00 of its expiry day, local time, it is live"
    $k = Get-HordeHubEnrolledKey -HordeHome $hh -DeviceId $dev -Now $midnight
    Check ($k.state -ceq "unknown" -and $k.reason -clike "*ran to 20271011 and is over*horde hub enroll*") ("from 00:00 of that day it is over, as the transport reads its expiry (" + $k.reason + ")")
    Check ((Test-HordeHubExpired -Expires "2027101" -Now $now) -and (Test-HordeHubExpired -Expires "" -Now $now)) "an expiry that is not a date is over, never forever"
    Check ((Get-HordeHubEnrolledKey -HordeHome $hh -DeviceId "NOT-A-DEVICE" -Now $now).state -ceq "unknown") "a device id that is not one gives no key"

    Write-Host ""
    Write-Host "--- revoked: never live again, until enrolled afresh ---" -ForegroundColor Cyan
    Check ((Set-HordeHubEnrolmentRevoked -HordeHome $hh -DeviceId $dev -Now $now) -ceq "") "revoking an entry answers nothing to fix"
    $k = Get-HordeHubEnrolledKey -HordeHome $hh -DeviceId $dev -Now $now
    Check ($k.state -ceq "unknown" -and $k.reason -clike "*was revoked at 2026-10-11T12:00:00Z*") ("a revoked entry gives no key, and says when (" + $k.reason + ")")
    $later = $now.AddHours(1)
    Check ((Set-HordeHubEnrolmentRevoked -HordeHome $hh -DeviceId $dev -Now $later) -ceq "" -and (Read-HordeHubEnrolment -HordeHome $hh -DeviceId $dev).value.revokedAt -ceq "2026-10-11T12:00:00Z") "revoking again changes nothing: the first revoke's time stands"
    Check ((Set-HordeHubEnrolmentRevoked -HordeHome $hh -DeviceId $other -Now $now) -ceq "" -and (Read-HordeHubEnrolment -HordeHome $hh -DeviceId $other).state -ceq "absent") "revoking a device the register never held writes nothing: it is refused anyway"
    [System.IO.File]::WriteAllText($op, "not json")
    Check ((Set-HordeHubEnrolmentRevoked -HordeHome $hh -DeviceId $other -Now $now) -clike "*cannot be read, so it cannot be marked revoked*") "an entry that cannot be read is said, never silently passed over"
    Remove-Item -LiteralPath $op
    $null = Add-HordeHubEnrolment -HordeHome $hh -DeviceId $dev -Transport "fake" -Key $key2 -Expires "20271011" -Now $later
    $k = Get-HordeHubEnrolledKey -HordeHome $hh -DeviceId $dev -Now $later
    Check ($k.state -ceq "known" -and $k.value -ceq $key2) "enrolled afresh with a new key, the device is live again with that key"

    Write-Host ""
    Write-Host "--- admission: the register and the transport must agree ---" -ForegroundColor Cyan
    $said = @{ ok = $true; line = $key2; reason = "" }
    $seen = New-Object System.Collections.ArrayList
    $fake = [pscustomobject]@{ name = "fake"; hubEnrolled = { param($HordeHome, $DeviceId, $Now) [void]$seen.Add(@($HordeHome, $DeviceId, $Now)); return [pscustomobject]$said } }
    Check ((Test-HordeHubAdmits -HordeHome $hh -DeviceId $dev -Enrollment $fake -Now $later) -ceq "") "CONTROL: both hold the device live, with one key: admitted"
    Check ($seen.Count -eq 1 -and $seen[0][0] -ceq $hh -and $seen[0][1] -ceq $dev -and $seen[0][2] -eq $later) "the transport is asked about that device, in that home, at that time"
    $said = @{ ok = $false; line = ""; reason = "the transport holds no line for it" }
    $w = Test-HordeHubAdmits -HordeHome $hh -DeviceId $dev -Enrollment $fake -Now $later
    Check ($w -clike "*not enrolled with the fake transport*holds no line*") ("a transport that no longer holds the device refuses it, with the transport's reason (" + $w + ")")
    $said = @{ ok = $true; line = $key; reason = "" }
    $w = Test-HordeHubAdmits -HordeHome $hh -DeviceId $dev -Enrollment $fake -Now $later
    Check ($w -clike "*holds another key*than the one the hub's register enrolled*") ("a transport holding another key than the register's refuses it (" + $w + ")")
    $said = @{ ok = $true; line = $key2; reason = "" }
    $null = Set-HordeHubEnrolmentRevoked -HordeHome $hh -DeviceId $dev -Now $later
    $seen.Clear()
    $w = Test-HordeHubAdmits -HordeHome $hh -DeviceId $dev -Enrollment $fake -Now $later
    Check ($w -clike "*is not enrolled*was revoked*" -and $seen.Count -eq 0) ("a device the register revoked is refused though the transport still holds it, and the transport is not even asked (" + $w + ")")
    Check ((Test-HordeHubAdmits -HordeHome $hh -DeviceId $other -Enrollment $fake -Now $later) -clike "*is not enrolled*not in the hub's register*") "a device the register never held is refused"
    $null = Add-HordeHubEnrolment -HordeHome $hh -DeviceId $other -Transport "fake" -Key $key -Expires "20271011" -Now $later
    $throws = [pscustomobject]@{ name = "fake"; hubEnrolled = { param($HordeHome, $DeviceId, $Now) throw "the key file is locked" } }
    Check ((Test-HordeHubAdmits -HordeHome $hh -DeviceId $other -Enrollment $throws -Now $later) -clike "*could not be checked*the key file is locked*") "a transport check that throws refuses, with its reason"
    $null = Add-HordeHubEnrolment -HordeHome $hh -DeviceId $other -Transport "fake" -Key $key -Expires "20261011" -Now $later
    $said = @{ ok = $true; line = $key; reason = "" }
    Check ((Test-HordeHubAdmits -HordeHome $hh -DeviceId $other -Enrollment $fake -Now $later) -clike "*is not enrolled*is over*") "an entry past its expiry is refused though the transport still holds it"

    Write-Host ""
    Write-Host "--- the live register, as the listener is handed it: live devices and their keys only ---" -ForegroundColor Cyan
    # Now: $dev revoked, $other past its expiry. A third, live; a fourth, unreadable; a stray file.
    $third = "22222222-3333-4444-8555-666666666666"
    $fourth = "33333333-4444-4555-8666-777777777777"
    $null = Add-HordeHubEnrolment -HordeHome $hh -DeviceId $third -Transport "fake" -Key $key2 -Expires "20991231" -Now $later
    [System.IO.File]::WriteAllText((Get-HordeHubEnrolmentPath -HordeHome $hh -DeviceId $fourth), "not json")
    [System.IO.File]::WriteAllText((Join-Path (Get-HordeHubRegistryRoot -HordeHome $hh) "notes.json"), "{}")
    $live = Get-HordeHubLiveKeys -HordeHome $hh -Now $later
    Check ($live -is [hashtable] -and $live.Count -eq 1 -and $live[$third] -ceq $key2) ("only the live device is in it, with its key; revoked, expired, unreadable and stray files are not (" + (@($live.Keys) -join ", ") + ")")
    Check ((Get-HordeHubLiveKeys -HordeHome (Join-Path $tmp "no-such-home") -Now $later).Count -eq 0) "a home with no register gives an empty table, never an error"
} finally {
    if ((Split-Path -Leaf $tmp) -match '^horde-hub-registry-[0-9a-f]{32}$') { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "the hub's register admits only a device it enrolled, live, with the key its transport still holds"
