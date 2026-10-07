# DOES ENROLMENT MAKE, ADMIT, PIN AND REVOKE ONLY WHAT IT SHOULD, UNDER HORDE'S OWN HOME?
#
# Remote plan step R17b. transports/ssh/Enroll.ps1 holds the ssh link's enrolment, and cli/Enroll.ps1
# the `horde node` and `horde hub` verbs that reach it. This suite, in a temporary HORDE_HOME:
#   - a public key line is ed25519 or refused, and its fingerprint is ssh-keygen's own;
#   - the one ssh-keygen start (coordinator's limits, 2026-10-06): an ed25519 pair inside Horde's home,
#     no passphrase, never over an existing key, never outside the home, and the private key's ACL this
#     user alone, read back;
#   - node init and rotate-key, node pin (a changed host key is refused without -Replace), hub init,
#     hub enroll (command=, restrict, expiry-time; a device with another key, a key of another device and
#     a revoked key are refused), hub revoke (the key goes to revoked_keys);
#   - the folder's exec guard admits exactly that second start and nothing like it;
#   - the commands, run as a user would, through the real horde CLI.
# The user's ~/.ssh is compared before and after.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "transports\Port.ps1")
. (Join-Path $root "transports\ssh\Enroll.ps1")
. (Join-Path $here "ExecGuard.ps1")

function Get-SshDirPrint {
    $d = Join-Path $env:USERPROFILE ".ssh"
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { return "(no ~/.ssh)" }
    return ((@(Get-ChildItem -LiteralPath $d -Recurse -File -Force | Sort-Object FullName | ForEach-Object { $_.FullName + " " + $_.Length + " " + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash })) -join "`n")
}
$sshDirBefore = Get-SshDirPrint
$tmp = Join-Path $env:TEMP ("horde-enroll-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$hh = Join-Path $tmp "home"
$dev = "0f8fad5b-d9cb-469f-a165-70867728950e"
$dev2 = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
$hub = "1b4e28ba-2fa1-4d3b-a3f5-ef19b5a7633b"
$hr = "C:\horde"
$ps = Join-Path ([System.Environment]::SystemDirectory) "WindowsPowerShell\v1.0\powershell.exe"
$cmd = $ps + " -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\horde\cli\attach.ps1 -Device " + $dev

try {
    New-Item -ItemType Directory -Path $hh | Out-Null

    Write-Host ""
    Write-Host "--- a public key line: ed25519, and nothing else ---" -ForegroundColor Cyan
    $kgDir = Join-Path $hh "scratch"
    New-Item -ItemType Directory -Path $kgDir | Out-Null
    $made = New-HordeSshKey -Path (Join-Path $kgDir "k1") -Passphrase "" -HordeHome $hh
    Check ($made.ok -and $made.line -cmatch '\Assh-ed25519 [A-Za-z0-9+/]{68} horde\z') ("ssh-keygen makes an ed25519 pair inside the home, comment horde (" + $made.line + $made.reason + ")")
    $p = ConvertFrom-HordeSshKeyLine -Line $made.line
    $psi = New-Object System.Diagnostics.ProcessStartInfo((Join-Path $env:SystemRoot "System32\OpenSSH\ssh-keygen.exe"), ('-l -E sha256 -f "' + (Join-Path $kgDir "k1.pub") + '"'))
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true
    $kg = [System.Diagnostics.Process]::Start($psi); $fp = $kg.StandardOutput.ReadToEnd(); $null = $kg.WaitForExit(20000)
    Check ($p.ok -and $fp.Contains($p.fingerprint)) ("the fingerprint is ssh-keygen's own (" + $p.fingerprint + ")")
    foreach ($bad in @(("ssh-rsa " + ("A" * 68)), "ssh-ed25519 AAAA", ("ssh-ed25519 " + ("A" * 68) + ' com"ment'), ("ssh-ed25519 " + [System.Convert]::ToBase64String((New-Object byte[] 51)).Substring(0, 68)), "", ("  " + $made.line + " x y"))) {
        Check (-not (ConvertFrom-HordeSshKeyLine -Line $bad).ok) ("refused as a key line: '" + $bad.Substring(0, [Math]::Min(40, $bad.Length)) + "...'")
    }
    # The line's own type word must agree with the blob: a good ed25519 blob under another name is refused.
    $renamed = ConvertFrom-HordeSshKeyLine -Line ("ssh-rsa " + $p.b64 + " horde")
    Check (-not $renamed.ok -and $renamed.reason -clike "*not an ssh-ed25519 public key line*") "a good ed25519 blob under the type word ssh-rsa is refused by the line's own shape"

    Write-Host ""
    Write-Host "--- the one ssh-keygen start: inside the home, no passphrase, never over a key, ACL this user alone ---" -ForegroundColor Cyan
    Check ((Test-HordeSshKeyAcl -Path (Join-Path $kgDir "k1")) -eq "") "the private key's ACL is protected and admits this user alone"
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $rules = @((Get-Acl -LiteralPath (Join-Path $kgDir "k1")).Access)
    Check ($rules.Count -eq 1 -and "$($rules[0].IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]))" -ceq "$me") ("CONTROL: read independently, its one rule is this user's (" + @($rules | ForEach-Object { "$($_.IdentityReference)" }) -join ", " + ")")
    $folderRules = @((Get-Acl -LiteralPath $kgDir).Access)
    Check ($folderRules.Count -gt 1) "CONTROL: the folder the key sits in admits more than this user, so the key's own ACL is doing the work"
    Check ((Test-HordeSshKeyAcl -Path (Join-Path $kgDir "k1.pub")) -ne "") "the ACL check refuses a file that inherits its folder's wider access (the public key)"
    # Inheriting is refused even when what is inherited is this user alone: the folder can widen later.
    $mine = Join-Path $hh "only-me"
    New-Item -ItemType Directory -Path $mine | Out-Null
    $fa = New-Object System.Security.AccessControl.DirectorySecurity
    $fa.SetAccessRuleProtection($true, $false)
    $fa.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
    Set-Acl -LiteralPath $mine -AclObject $fa
    $inh = Join-Path $mine "inherits"
    [System.IO.File]::WriteAllText($inh, "x")
    $inhRules = @((Get-Acl -LiteralPath $inh).GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    Check ($inhRules.Count -ge 1 -and @($inhRules | Where-Object { "$($_.IdentityReference)" -cne "$me" }).Count -eq 0 -and @($inhRules | Where-Object { $_.IsInherited }).Count -eq $inhRules.Count) "CONTROL: a file in a folder of this user alone inherits this user's rule and no other"
    Check ((Test-HordeSshKeyAcl -Path $inh) -clike "*inherits access from its folder*") "the ACL check refuses that file all the same: it inherits"
    $r = New-HordeSshKey -Path (Join-Path $kgDir "k2") -Passphrase "secret" -HordeHome $hh
    Check (-not $r.ok -and $r.reason -clike "*no passphrase*" -and -not (Test-Path (Join-Path $kgDir "k2"))) "a passphrase is refused, and no key is made"
    $outside = Join-Path $tmp "outside-key"
    $r = New-HordeSshKey -Path $outside -Passphrase "" -HordeHome $hh
    Check (-not $r.ok -and $r.reason -clike "*outside Horde's home*" -and -not (Test-Path $outside)) "a path outside Horde's home is refused, and nothing is written there"
    $r = New-HordeSshKey -Path (Join-Path $hh "..\climbed-out") -Passphrase "" -HordeHome $hh
    Check (-not $r.ok -and -not (Test-Path (Join-Path $tmp "climbed-out"))) "a path that climbs out of the home with .. is refused"
    $before = [System.IO.File]::ReadAllText((Join-Path $kgDir "k1"))
    $r = New-HordeSshKey -Path (Join-Path $kgDir "k1") -Passphrase "" -HordeHome $hh
    Check (-not $r.ok -and $r.reason -clike "*never overwritten*" -and [System.IO.File]::ReadAllText((Join-Path $kgDir "k1")) -ceq $before) "an existing key is never overwritten"

    Write-Host ""
    Write-Host "--- the node: init, rotate-key, pin ---" -ForegroundColor Cyan
    $init = Initialize-HordeSshNode -HordeHome $hh -DeviceId $dev
    $paths = Get-HordeSshPaths -HordeHome $hh
    Check ($init.ok -and $init.line -cmatch ('\A' + $dev + ' ssh-ed25519 [A-Za-z0-9+/]{68}\z')) "node init makes the link key and returns '<device> <key>' to carry to the hub"
    Check ((Test-Path -LiteralPath $paths.config) -and @(Get-Content -LiteralPath $paths.config | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") }).Count -eq 0) "and an ssh_config that holds no directive"
    Check (-not (Initialize-HordeSshNode -HordeHome $hh -DeviceId $dev).ok) "a second node init is refused: an existing key is rotated, never remade"
    $oldKey = $init.line.Split(" ", 2)[1]
    $rot = Reset-HordeSshNodeKey -HordeHome $hh -DeviceId $dev
    $newKey = $rot.line.Split(" ", 2)[1]
    Check ($rot.ok -and $newKey -cne $oldKey -and (Test-Path ($paths.identity + ".previous")) -and ([System.IO.File]::ReadAllText($paths.identity + ".previous.pub")).Contains($oldKey.Split(" ")[1])) "rotate-key makes a new key and keeps the old one as .previous"
    Check ((Test-HordeSshKeyAcl -Path $paths.identity) -eq "") "and the new key is this user's alone"
    $hk = (New-HordeSshKey -Path (Join-Path $kgDir "hostA") -Passphrase "" -HordeHome $hh).line
    $hk2 = (New-HordeSshKey -Path (Join-Path $kgDir "hostB") -Passphrase "" -HordeHome $hh).line
    $pin = Add-HordeSshPin -HordeHome $hh -HubId $hub -HostKey $hk
    Check ($pin.ok -and @(Get-Content -LiteralPath $paths.knownHosts) -ccontains ("horde-hub-" + $hub + " " + (ConvertTo-HordeSshBareKey $hk))) "node pin writes the hub's host key under its alias in Horde's known_hosts"
    Check ((Add-HordeSshPin -HordeHome $hh -HubId $hub -HostKey $hk).ok -and @(Get-Content -LiteralPath $paths.knownHosts).Count -eq 1) "pinning the same key again changes nothing"
    $chg = Add-HordeSshPin -HordeHome $hh -HubId $hub -HostKey $hk2
    Check (-not $chg.ok -and $chg.reason -clike "*-Replace*" -and @(Get-Content -LiteralPath $paths.knownHosts) -ccontains ("horde-hub-" + $hub + " " + (ConvertTo-HordeSshBareKey $hk))) "a changed host key is refused without -Replace, and the old pin stays"
    $rep = Add-HordeSshPin -HordeHome $hh -HubId $hub -HostKey $hk2 -Replace
    Check ($rep.ok -and @(Get-Content -LiteralPath $paths.knownHosts).Count -eq 1 -and @(Get-Content -LiteralPath $paths.knownHosts)[0].EndsWith((ConvertTo-HordeSshBareKey $hk2).Split(" ")[1])) "with -Replace, the pin is replaced, one line"
    Check (-not (Add-HordeSshPin -HordeHome $hh -HubId "Bad Hub" -HostKey $hk).ok) "a hub id outside the pattern is refused"

    Write-Host ""
    Write-Host "--- the hub: init, enroll, revoke ---" -ForegroundColor Cyan
    $hi = Initialize-HordeSshHub -HordeHome $hh -HubId $hub
    $lp = Get-HordeSshListenPaths -HordeHome $hh
    Check ($hi.ok -and $hi.line -cmatch ('\A' + $hub + ' ssh-ed25519 [A-Za-z0-9+/]{68}\z') -and (Test-HordeSshKeyAcl -Path $lp.hostKey) -eq "") "hub init makes the listener's host key, this user's alone, and returns the line a node pins"
    Check ((Initialize-HordeSshHub -HordeHome $hh -HubId $hub).line -ceq $hi.line) "run again, it returns the same line and makes nothing"
    $now = [datetime]::SpecifyKind([datetime]"2026-10-06T12:00:00", [System.DateTimeKind]::Utc)
    $en = Add-HordeSshEnrolment -HordeHome $hh -DeviceId $dev -Key $newKey -HordeRoot $hr -Days 365 -Now $now
    Check ($en.ok -and $en.line -ceq ('command="' + $cmd + '",restrict,expiry-time="20271006" ' + $newKey + ' horde-device-' + $dev)) ("hub enroll writes one line: the forced command, restrict, and an expiry a year on (" + $en.line + ")")
    Check (@(Get-Content -LiteralPath $lp.authorized).Count -eq 1) "authorized_keys holds that one line"
    Check ((Add-HordeSshEnrolment -HordeHome $hh -DeviceId $dev -Key $newKey -HordeRoot $hr -Now $now).ok -and @(Get-Content -LiteralPath $lp.authorized).Count -eq 1) "enrolling the same device and key again changes nothing"
    $other = (New-HordeSshKey -Path (Join-Path $kgDir "other") -Passphrase "" -HordeHome $hh).line
    $r = Add-HordeSshEnrolment -HordeHome $hh -DeviceId $dev -Key $other -HordeRoot $hr -Now $now
    Check (-not $r.ok -and $r.reason -clike "*already enrolled with another key*") "a device already enrolled with another key is refused"
    $r = Add-HordeSshEnrolment -HordeHome $hh -DeviceId $dev2 -Key $newKey -HordeRoot $hr -Now $now
    Check (-not $r.ok -and $r.reason -clike "*already enrolled for another device*") "a key already enrolled for another device is refused"
    Check (-not (Add-HordeSshEnrolment -HordeHome $hh -DeviceId $dev2 -Key $other -HordeRoot 'C:\ho"rde' -Now $now).ok) "a Horde root holding a double quote is refused"
    $sp = Add-HordeSshEnrolment -HordeHome $hh -DeviceId $dev2 -Key $other -HordeRoot 'C:\Program Files\horde' -Now $now
    Check (-not $sp.ok -and $sp.reason -clike "*cannot carry*") ("a Horde root holding a space is refused, never half-run (" + $sp.reason + ")")
    Check (-not (Add-HordeSshEnrolment -HordeHome $hh -DeviceId $dev2 -Key $other -HordeRoot 'horde' -Now $now).ok) "a Horde root that is not a full path is refused"
    Check (-not (Add-HordeSshEnrolment -HordeHome $hh -DeviceId $dev2 -Key $other -HordeRoot $hr -Days 0 -Now $now).ok -and -not (Add-HordeSshEnrolment -HordeHome $hh -DeviceId $dev2 -Key $other -HordeRoot $hr -Days 400 -Now $now).ok) "an enrolment of 0 days or of more than a year and a day is refused"
    Check (-not (Add-HordeSshEnrolment -HordeHome $hh -DeviceId "not-a-device" -Key $other -HordeRoot $hr -Now $now).ok) "a device id that is not one is refused"
    $rv = Remove-HordeSshEnrolment -HordeHome $hh -DeviceId $dev
    Check ($rv.ok -and @(Read-HordeSshLines -Path $lp.authorized).Count -eq 0 -and @(Read-HordeSshLines -Path $lp.revoked) -ccontains $newKey) "hub revoke removes the line and adds the key to revoked_keys"
    $again = Add-HordeSshEnrolment -HordeHome $hh -DeviceId $dev -Key $newKey -HordeRoot $hr -Now $now
    Check (-not $again.ok -and $again.reason -clike "*was revoked*") "a revoked key is never enrolled again"
    Check ((Add-HordeSshEnrolment -HordeHome $hh -DeviceId $dev -Key $other -HordeRoot $hr -Now $now).ok) "CONTROL: the same device with a new key is enrolled"
    # EVERY LINE CARRIES command= AND restrict (R17a: the listener runs no ForceCommand, which would
    # override each key's command=, so these two are the whole guard).
    $third = (New-HordeSshKey -Path (Join-Path $kgDir "third") -Passphrase "" -HordeHome $hh).line
    $null = Add-HordeSshEnrolment -HordeHome $hh -DeviceId "5d7f3c2a-8e41-4b6a-9c0d-1e2f3a4b5c6d" -Key $third -HordeRoot $hr -Days 30 -Now $now
    $all = @(Read-HordeSshLines -Path $lp.authorized)
    $shaped = @($all | Where-Object { $_ -cmatch ('\Acommand="' + [regex]::Escape($ps) + ' -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\\horde\\cli\\attach\.ps1 -Device (?<d>[0-9a-f-]{36})",restrict,expiry-time="[0-9]{8}" ssh-ed25519 [A-Za-z0-9+/]{68} horde-device-(?<e>[0-9a-f-]{36})\z') -and $Matches["d"] -ceq $Matches["e"] })
    Check ($all.Count -eq 2 -and $shaped.Count -eq 2) ("every enrolled line forces attach.ps1 for its own device and carries restrict (" + ($all -join " | ") + ")")
    Check ((Get-HordeSshAttachCommand -HordeRoot $hr -DeviceId $dev) -ceq $cmd) "the forced command is System32's powershell.exe by full path running cli\attach.ps1 for the device"
    $bad = ""; try { $null = Get-HordeSshAttachCommand -HordeRoot $hr -DeviceId "not-a-device" } catch { $bad = $_.Exception.Message }
    Check ($bad -clike "*not a device id*") "the builder itself refuses a device id that is not one"
    # The builder's allowlist is the one check on what the key line carries: nothing outside it, a
    # non-ASCII letter included, reaches command="...".
    $wide = Add-HordeSshEnrolment -HordeHome $hh -DeviceId $dev2 -Key $other -HordeRoot ("C:\h" + [char]0x00F6 + "rde") -Now $now
    Check (-not $wide.ok -and $wide.reason -clike "*cannot carry*") ("a Horde root outside the builder's characters, a non-ASCII letter, is refused (" + $wide.reason + ")")
    Check (-not (Remove-HordeSshEnrolment -HordeHome $hh -DeviceId $dev2).ok) "revoking a device that is not enrolled is refused"

    Write-Host ""
    Write-Host "--- renewal, Horde's root, and files replaced whole (review of PR #111) ---" -ForegroundColor Cyan
    # B1: the same device and key enrolled again renews its line; it never keeps a past expiry.
    $rdev = "6e8a4b2c-1d3f-4a5b-8c7d-9e0f1a2b3c4d"
    $rkey = (New-HordeSshKey -Path (Join-Path $kgDir "renew") -Passphrase "" -HordeHome $hh).line
    $then = [datetime]::SpecifyKind([datetime]"2024-10-07T12:00:00", [System.DateTimeKind]::Utc)
    $old = Add-HordeSshEnrolment -HordeHome $hh -DeviceId $rdev -Key $rkey -HordeRoot $hr -Days 365 -Now $then
    Check ($old.ok -and $old.line -clike '*expiry-time="20251007"*') ("CONTROL: enrolled two years ago, the line expired on 20251007 (" + $old.line + ")")
    $ren = Add-HordeSshEnrolment -HordeHome $hh -DeviceId $rdev -Key $rkey -HordeRoot $hr -Days 365 -Now $now
    $mineNow = @(Read-HordeSshLines -Path $lp.authorized | Where-Object { $_.EndsWith(" horde-device-" + $rdev) })
    Check ($ren.ok -and $mineNow.Count -eq 1 -and $mineNow[0] -clike '*,restrict,expiry-time="20271006" *' -and $mineNow[0].StartsWith('command="' + (Get-HordeSshAttachCommand -HordeRoot $hr -DeviceId $rdev) + '"')) ("enrolling the same device and key again renews its one line to a year from now (" + "$($mineNow -join ' | ')" + ")")
    Check ($ren.said -clike "*renewed until 20271006*it was until 20251007*") ("and says it was renewed, and from when (" + $ren.said + ")")
    $short = Add-HordeSshEnrolment -HordeHome $hh -DeviceId $rdev -Key $rkey -HordeRoot $hr -Days 30 -Now $now
    Check ($short.ok -and $short.line -clike '*expiry-time="20271006"*' -and $short.said -clike "*already enrolled until 20271006*nothing changed*") ("a shorter enrolment never shortens the expiry (" + $short.said + ")")
    $null = Remove-HordeSshEnrolment -HordeHome $hh -DeviceId $rdev
    $back = Add-HordeSshEnrolment -HordeHome $hh -DeviceId $rdev -Key $rkey -HordeRoot $hr -Now $now
    Check (-not $back.ok -and $back.reason -clike "*was revoked*") "a revoked key is not renewed: it stays refused"
    # N1, N2: the root must be a drive path of plain characters; cmd.exe runs the forced command.
    foreach ($bad in @('C:\R&D\horde', 'C:\x%PATH%y', 'C:\x^y', 'C:\a!b', 'C:\a(b)', 'C:\a|b', 'C:\a<b', 'C:\a>b', 'C:\ho"rde')) {
        $msg = ""; try { $null = Get-HordeSshAttachCommand -HordeRoot $bad -DeviceId $dev } catch { $msg = $_.Exception.Message }
        Check ($msg -clike "*cannot carry*") ("the root '" + $bad + "' is refused by the builder's own reason (" + $msg + ")")
    }
    foreach ($bad in @('C:h', '\h', 'horde', '\\server\share\horde')) {
        $msg = ""; try { $null = Get-HordeSshAttachCommand -HordeRoot $bad -DeviceId $dev } catch { $msg = $_.Exception.Message }
        Check ($msg -clike "*starts with a drive letter*") ("the root '" + $bad + "', not a drive path, is refused (" + $msg + ")")
    }
    Check ((Get-HordeSshAttachCommand -HordeRoot 'C:\Users\a.b\horde-1_0' -DeviceId $dev).EndsWith(' -File C:\Users\a.b\horde-1_0\cli\attach.ps1 -Device ' + $dev)) "CONTROL: a root of letters, digits, dot, underscore and dash is taken as it is"
    # N5: written beside and renamed over, never in place. A hard link made to the old file before the
    # write still holds the old file whole after it: a rename gives the name a new file, while an
    # in-place write would change the one file both names point at. (A reader holding the file open
    # cannot show this: Windows refuses to rename over an open file, delete sharing or not, measured.)
    $authBefore = [System.IO.File]::ReadAllText($lp.authorized)
    $hard = Join-Path $hh "authorized_keys.before"
    $null = New-Item -ItemType HardLink -Path $hard -Target $lp.authorized
    $wkey = (New-HordeSshKey -Path (Join-Path $kgDir "whole") -Passphrase "" -HordeHome $hh).line
    $null = Add-HordeSshEnrolment -HordeHome $hh -DeviceId "7f9b5c3d-2e4a-4b6c-9d8e-0f1a2b3c4d5e" -Key $wkey -HordeRoot $hr -Now $now
    $authAfter = [System.IO.File]::ReadAllText($lp.authorized)
    $seen = [System.IO.File]::ReadAllText($hard)
    Check ($authAfter -cne $authBefore -and $authAfter.Contains("horde-device-7f9b5c3d-2e4a-4b6c-9d8e-0f1a2b3c4d5e")) "CONTROL: the enrolment did change authorized_keys"
    Check ($seen -ceq $authBefore) "a hard link to the old authorized_keys still holds it whole: the file was replaced by a rename, not rewritten in place"
    Check (@(Get-ChildItem -LiteralPath $lp.dir -File -Filter "*.tmp-*").Count -eq 0) "and no temporary file is left beside it"

    Write-Host ""
    Write-Host "--- the exec guard: the second start, exactly as approved, and nothing like it ---" -ForegroundColor Cyan
    $found = @(Get-HordeSshExecFindings -Dir (Join-Path $root "transports\ssh"))
    Check ($found.Count -eq 0) ("the folder, Enroll.ps1 included, passes the guard (" + $found.Count + " finding(s))")
    foreach ($x in $found) { Write-Host ("         finding: " + $x) -ForegroundColor DarkYellow }
    $realEnroll = [System.IO.File]::ReadAllText((Join-Path $root "transports\ssh\Enroll.ps1"))
    function Test-GuardWith { param([string]$EnrollText, [string]$Extra = "")
        $md = Join-Path $tmp ("guard-" + [guid]::NewGuid().ToString("N").Substring(0, 6))
        New-Item -ItemType Directory -Path $md | Out-Null
        foreach ($f in @("Argv.ps1", "Attach.ps1", "Native.ps1", "Transport.ps1")) { Copy-Item -LiteralPath (Join-Path $root ("transports\ssh\" + $f)) -Destination $md }
        [System.IO.File]::WriteAllText((Join-Path $md "Enroll.ps1"), $EnrollText)
        if ($Extra -ne "") { [System.IO.File]::WriteAllText((Join-Path $md "Other.ps1"), $Extra) }
        return @(Get-HordeSshExecFindings -Dir $md) }
    Check ((Test-GuardWith $realEnroll).Count -eq 0) "CONTROL: a copy of the folder as it is passes"
    # Each refusal is checked by its own reason: a guard that admits the start but trips a count elsewhere
    # has lost the rule that names where a start may be.
    $g = @(Test-GuardWith $realEnroll 'function Get-HordeSshZz { [System.Diagnostics.Process]::Start("ssh-keygen.exe") }')
    Check (@($g | Where-Object { $_ -clike "Other.ps1:*a Start other than*" }).Count -eq 1) ("a start added in another file of the folder is refused, at that start (" + ($g -join " | ") + ")")
    $g = @(Test-GuardWith ($realEnroll + "`r`n" + 'function Get-HordeSshZz { $psi = [System.Diagnostics.ProcessStartInfo]::new([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh-keygen.exe"), $keygenArgs); [System.Diagnostics.Process]::Start($psi) }' + "`r`n"))
    Check (@($g | Where-Object { $_ -clike "Enroll.ps1:*a Start other than*" }).Count -eq 1) ("a second ssh-keygen start in another function of Enroll.ps1 is refused, at that start (" + ($g -join " | ") + ")")
    $edits = [ordered]@{
        "a caller's flag in ssh-keygen's argv" = @('"-C", "horde", "-f", $full)', '"-C", "horde", "-f", $full, $Extra)')
        "another key type" = @('"-q", "-t", "ed25519"', '"-q", "-t", "rsa"')
        "a program other than ssh-keygen.exe" = @('"OpenSSH", "ssh-keygen.exe"), $keygenArgs)', '"OpenSSH", "ssh.exe"), $keygenArgs)')
        "a second start inside New-HordeSshKey" = @('$p = [System.Diagnostics.Process]::Start($psi)', '$p = [System.Diagnostics.Process]::Start($psi); $q = [System.Diagnostics.Process]::Start($psi)')
        "the argv assigned a second time" = @('$psi = [System.Diagnostics.ProcessStartInfo]::new(', '$keygenArgs = $keygenArgs + " -O x"; $psi = [System.Diagnostics.ProcessStartInfo]::new(')
    }
    foreach ($k in $edits.Keys) {
        Check ($realEnroll.Contains($edits[$k][0])) ("CONTROL: the text for " + $k + " is in Enroll.ps1")
        Check ((Test-GuardWith ($realEnroll.Replace($edits[$k][0], $edits[$k][1]))).Count -ge 1) ("the guard refuses " + $k)
    }
    $g = @(Test-GuardWith ($realEnroll.Replace($edits["a second start inside New-HordeSshKey"][0], $edits["a second start inside New-HordeSshKey"][1])))
    Check (@($g | Where-Object { $_ -clike "*starts a program 2 times; at most once is allowed*" }).Count -eq 1) ("two starts inside New-HordeSshKey are refused as two, not only as a setup count (" + ($g -join " | ") + ")")

    Write-Host ""
    Write-Host "--- the commands, as a user runs them ---" -ForegroundColor Cyan
    $ch = Join-Path $tmp "cli-home"
    New-Item -ItemType Directory -Path $ch | Out-Null
    $envs = @{ HORDE_HOME = $ch }
    $h = Invoke-HordeCliProcess -Root $root -HordeArgs @("hub", "init") -Env $envs
    $pinCmd = [regex]::Match($h.out, 'horde node pin -Hub (?<hub>\S+) -HostKey "(?<key>[^"]+)"')
    Check ($h.code -eq 0 -and $pinCmd.Success) ("horde hub init prints the node pin to run (exit " + $h.code + ")")
    $n = Invoke-HordeCliProcess -Root $root -HordeArgs @("node", "init") -Env $envs
    $enCmd = [regex]::Match($n.out, 'horde hub enroll -Device (?<dev>\S+) -Key "(?<key>[^"]+)"')
    Check ($n.code -eq 0 -and $enCmd.Success) ("horde node init prints the hub enroll to run (exit " + $n.code + ")")
    $e = Invoke-HordeCliProcess -Root $root -HordeArgs @("hub", "enroll", "-Device", $enCmd.Groups["dev"].Value, "-Key", $enCmd.Groups["key"].Value) -Env $envs
    $auth = ""; if (Test-Path (Join-Path $ch "hub\listen\authorized_keys")) { $auth = [System.IO.File]::ReadAllText((Join-Path $ch "hub\listen\authorized_keys")) }
    $wantCmd = Get-HordeSshAttachCommand -HordeRoot $root -DeviceId $enCmd.Groups["dev"].Value
    Check ($e.code -eq 0 -and $auth.StartsWith('command="' + $wantCmd + '",restrict,expiry-time="') -and $wantCmd.EndsWith("\cli\attach.ps1 -Device " + $enCmd.Groups["dev"].Value)) ("horde hub enroll admits the key, forced to cli\attach.ps1 for that device, with restrict (" + $auth.Trim() + ")")
    $pn = Invoke-HordeCliProcess -Root $root -HordeArgs @("node", "pin", "-Hub", $pinCmd.Groups["hub"].Value, "-HostKey", $pinCmd.Groups["key"].Value) -Env $envs
    Check ($pn.code -eq 0 -and [System.IO.File]::ReadAllText((Join-Path $ch "node\known_hosts")) -clike ("horde-hub-" + $pinCmd.Groups["hub"].Value + " ssh-ed25519 *")) "horde node pin pins the hub's host key"
    $e1 = Invoke-HordeCliProcess -Root $root -HordeArgs @("hub", "enroll", "-Device", $enCmd.Groups["dev"].Value, "-Key", $enCmd.Groups["key"].Value) -Env $envs
    Check ($e1.code -eq 0 -and $e1.out -clike "*already enrolled until*nothing changed*") ("horde hub enroll run again says what it did with the line, not a bare 'enrolled' (" + $e1.out.Trim() + ")")
    $rv = Invoke-HordeCliProcess -Root $root -HordeArgs @("hub", "revoke", "-Device", $enCmd.Groups["dev"].Value) -Env $envs
    $e2 = Invoke-HordeCliProcess -Root $root -HordeArgs @("hub", "enroll", "-Device", $enCmd.Groups["dev"].Value, "-Key", $enCmd.Groups["key"].Value) -Env $envs
    Check ($rv.code -eq 0 -and $e2.code -eq 1 -and $e2.out -clike "*was revoked*") "horde hub revoke, then the same key enrolled again: exit 1, saying it was revoked"
    $wrong = Invoke-HordeCliProcess -Root $root -HordeArgs @("node", "init", "-Hub", "x") -Env $envs
    Check ($wrong.code -ne 0 -and $wrong.out -clike "*does not belong to node init*") "a flag of another verb is refused, never ignored"
} finally {
    if ((Split-Path -Leaf $tmp) -match '^horde-enroll-[0-9a-f]{8}$') { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $tmp)) "the suite's temp folder, keys included, is gone"
Check ((Get-SshDirPrint) -ceq $sshDirBefore) "the user's ~/.ssh is byte for byte as it was"

Complete-HordeSuite -Success "enrolment makes, admits, pins and revokes only what it should, under Horde's own home"
