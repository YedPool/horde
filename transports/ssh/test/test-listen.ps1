# WHAT DOES THE HUB'S LISTENER ADMIT, AND WHAT DOES IT TELL sshd? (pure: no server is started)
#
# Remote plan R17a. transports/ssh/Listen.ps1 decides two things before it starts anything, and both are
# tested here with no sshd, so they run anywhere: which authorized_keys lines it will serve (one
# enrolled device each, forced to exactly the attach Get-HordeSshAttachCommand builds for it, restricted;
# anything else, a bare key above all, makes it refuse to start), and the configuration it writes
# (loopback only, Horde's own files only, no ForceCommand, no forwarding, no terminal, HORDE_HOME passed
# to the session). Also the listener port (transports/Listener.ps1), with a stand-in adapter. The live
# half is test-listen-local.ps1.
# Since issue #123 and issue #144 item 3: a line is served only for a device the hub's register holds
# live with that key, and the listener does not start on a file, or a folder above it, that another
# principal may write (a widened folder, made here in TEMP).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "transports\Listener.ps1")
. (Join-Path $root "transports\ssh\Listen.ps1")

$dev = "0f1e2d3c-4b5a-4968-8776-655443322110"
$other = "11111111-2222-4333-8444-555555555555"
$pub = "ssh-ed25519 " + ("A" * 68)
$attach = Get-HordeSshAttachCommand -HordeRoot $root -DeviceId $dev
$good = 'command="' + $attach + '",restrict ' + $pub + " horde-device-" + $dev
# The hub's register as the listener port hands it over: device id -> the key enrolled for it, live only.
$reg = @{ $dev = $pub; $other = $pub.Replace("AAAA", "BBBB") }
function Keys { param([string[]]$Lines, [hashtable]$Register = $reg) return @(Test-HordeSshListenKeys -Lines $Lines -Root $root -Register $Register) }

Write-Host ""
Write-Host "--- the keys it admits: one enrolled device each, forced to its attach, restricted ---" -ForegroundColor Cyan
Check ((Keys @($good)).Count -eq 0) "CONTROL: a line forced to what Get-HordeSshAttachCommand returns for its device, restricted, is admitted"
Check ((Keys @(('command="' + $attach + '",restrict,expiry-time="20991231" ' + $pub + " horde-device-" + $dev), "", "  ")).Count -eq 0) "and with an expiry, beside blank lines"
Check ((Keys @($good, ('command="' + (Get-HordeSshAttachCommand -HordeRoot $root -DeviceId $other) + '",restrict ' + $pub.Replace("AAAA", "BBBB") + " horde-device-" + $other))).Count -eq 0) "two devices, each forced to its own attach"
$cases = [ordered]@{
    "a bare key, with no command= (it would be a shell)" = ($pub + " horde-device-" + $dev)
    "restrict with no command=" = ("restrict " + $pub + " horde-device-" + $dev)
    "a key with command= but no restrict" = ('command="' + $attach + '" ' + $pub + " horde-device-" + $dev)
    "restrict before command=" = ('restrict,command="' + $attach + '" ' + $pub + " horde-device-" + $dev)
    "a key forced to another device's attach than the one it names" = ('command="' + (Get-HordeSshAttachCommand -HordeRoot $root -DeviceId $other) + '",restrict ' + $pub + " horde-device-" + $dev)
    "a key forced to another Horde's attach" = ('command="' + (Get-HordeSshAttachCommand -HordeRoot (Join-Path $root "elsewhere") -DeviceId $dev) + '",restrict ' + $pub + " horde-device-" + $dev)
    "a key forced to a shell" = ('command="cmd.exe",restrict ' + $pub + " horde-device-" + $dev)
    "a key forced to attach with a command after it" = ('command="' + $attach + ' & cmd.exe",restrict ' + $pub + " horde-device-" + $dev)
    "a key with an option beyond restrict and expiry" = ('command="' + $attach + '",restrict,port-forwarding ' + $pub + " horde-device-" + $dev)
    "a key with an environment= option" = ('command="' + $attach + '",restrict,environment="HORDE_HOME=C:\x" ' + $pub + " horde-device-" + $dev)
    "a key naming no device" = ('command="' + $attach + '",restrict ' + $pub)
    "a key naming its device in capitals" = ('command="' + $attach + '",restrict ' + $pub + " horde-device-" + $dev.ToUpperInvariant())
    "an rsa key" = ('command="' + $attach + '",restrict ssh-rsa ' + ("A" * 68) + " horde-device-" + $dev)
    "a key with text after the device" = ($good + " extra")
}
foreach ($k in $cases.Keys) {
    $f = @(Keys @($good, $cases[$k]))
    Check ($f.Count -eq 1 -and $f[0] -like "line 2 of authorized_keys*" -and -not $f[0].Contains($pub)) ("refused, by line number and never quoted: " + $k)
}
$f = @(Keys @("", " "))
Check ($f.Count -eq 1 -and $f[0] -like "*admits no device*") "a file admitting no device is refused: there is nothing to listen for"
$f = @(Keys @($good, ($pub + " horde-device-" + $other), $good))
Check ($f.Count -eq 1 -and $f[0] -like "line 2 *") "one bad line among good ones is enough to refuse, and it is the one named"

Write-Host ""
Write-Host "--- and only for a device the hub's register holds, live, with that key (issue #144 item 3) ---" -ForegroundColor Cyan
$third = "22222222-3333-4444-8555-666666666666"
$byHand = 'command="' + (Get-HordeSshAttachCommand -HordeRoot $root -DeviceId $third) + '",restrict ' + $pub.Replace("AAAA", "CCCC") + " horde-device-" + $third
Check ((Keys @($byHand) -Register @{ $third = $pub.Replace("AAAA", "CCCC") }).Count -eq 0) "CONTROL: a perfectly shaped line for a device the register holds with that key is admitted"
$f = @(Keys @($good, $byHand))
Check ($f.Count -eq 1 -and $f[0] -like ("line 2 of authorized_keys admits device " + $third + ", which the hub's register does not hold*") -and -not $f[0].Contains("CCCC")) ("a perfectly shaped line added by hand under a device the register does not hold is refused, by number (" + $f[0] + ")")
$f = @(Keys @($good) -Register @{ $dev = $pub.Replace("AAAA", "DDDD") })
Check ($f.Count -eq 1 -and $f[0] -like ("*device " + $dev + " with another key than the one the hub's register enrolled*")) "a line for an enrolled device with another key than the register's is refused"
$f = @(Keys @($good) -Register @{})
Check ($f.Count -eq 1 -and $f[0] -like "*does not hold as enrolled now*") "with the device revoked or expired, so gone from the live register, its line is refused"
$up = @{}; $up[$dev.ToUpperInvariant()] = $pub
Check ((Keys @($good) -Register $up).Count -eq 0) "CONTROL: the register is looked up by the line's own lowercase id"

Write-Host ""
Write-Host "--- the configuration it writes ---" -ForegroundColor Cyan
$hh = "C:\HordeHomeForTest"
$files = Get-HordeSshListenFiles -HordeHome $hh
Check ($files.dir -ceq "C:\HordeHomeForTest\hub\listen" -and $files.authorized -ceq "C:\HordeHomeForTest\hub\listen\authorized_keys" -and $files.hostKey -ceq "C:\HordeHomeForTest\hub\listen\host_ed25519" -and $files.revoked -ceq "C:\HordeHomeForTest\hub\listen\revoked_keys") "its files are enrolment's, under <home>\hub\listen"
$cfg = @(Get-HordeSshListenConfig -Files $files -Port 40123 -HordeHome $hh -User "someone")
function Has { param([string]$Line) return (@($cfg | Where-Object { $_ -ceq $Line }).Count -eq 1) }
Check (Has "Port 40123") "the port it was given"
Check ((Has "ListenAddress 127.0.0.1") -and (Has "AddressFamily inet") -and @($cfg | Where-Object { $_ -like "ListenAddress*" }).Count -eq 1) "with no address named, 127.0.0.1 only"
$cfg4 = @(Get-HordeSshListenConfig -Files $files -Port 2222 -HordeHome $hh -User "someone" -Address "192.168.1.182" -Family "v4")
Check (@($cfg4 | Where-Object { $_ -like "ListenAddress*" }) -join "|" -ceq "ListenAddress 192.168.1.182" -and @($cfg4 | Where-Object { $_ -ceq "AddressFamily inet" }).Count -eq 1) "with the hub's LAN address named (mesh v1), that one address only, IPv4"
$cfg6 = @(Get-HordeSshListenConfig -Files $files -Port 2222 -HordeHome $hh -User "someone" -Address "fd7a:115c:a1e0::1" -Family "v6")
Check (@($cfg6 | Where-Object { $_ -like "ListenAddress*" }) -join "|" -ceq "ListenAddress fd7a:115c:a1e0::1" -and @($cfg6 | Where-Object { $_ -ceq "AddressFamily inet6" }).Count -eq 1) "an IPv6 unique local address, IPv6 only"
Check ((Has "HostKey C:/HordeHomeForTest/hub/listen/host_ed25519") -and (Has "AuthorizedKeysFile C:/HordeHomeForTest/hub/listen/authorized_keys") -and (Has "RevokedKeys C:/HordeHomeForTest/hub/listen/revoked_keys") -and (Has "PidFile C:/HordeHomeForTest/hub/listen/sshd.pid")) "every file it names is Horde's own, under its home"
Check (@($cfg | Where-Object { $_.ToLowerInvariant().Contains("programdata") -or $_.Contains(".ssh") -or $_.Contains("%h") -or $_.Contains("%u") }).Count -eq 0) "and none is ProgramData\ssh, ~/.ssh or a per-user default"
Check (@($cfg | Where-Object { $_ -like "ForceCommand*" -or $_ -like "Match*" -or $_ -like "Include*" }).Count -eq 0) "no ForceCommand (it would replace each key's -Device), no Match, no Include"
Check ((Has "AllowUsers someone") -and (Has "PubkeyAuthentication yes") -and (Has "PasswordAuthentication no") -and (Has "KbdInteractiveAuthentication no")) "keys only, for this user only"
Check ((Has "PermitTTY no") -and (Has "DisableForwarding yes") -and (Has "PermitTunnel no") -and (Has "PermitUserEnvironment no")) "no terminal, no forwarding of any kind, no tunnel, no user environment"
Check (@($cfg | Where-Object { $_ -like "Subsystem*" }).Count -eq 0) "no Subsystem line: none is offered, and every key's command= overrides a subsystem request anyway (issue #147, item 8)"
Check (Has "MaxStartups 4:50:8") "MaxStartups bounds connections still authenticating (issue #147, item 2)"
Check (Has 'SetEnv "HORDE_HOME=C:/HordeHomeForTest"') "HORDE_HOME is passed to the session, so attach finds this hub's device id"
Check (@($cfg | Where-Object { $_ -cnotmatch '\A[\x20-\x7E]+\z' }).Count -eq 0) "every line is printable ASCII"

Write-Host ""
Write-Host "--- what it refuses before it starts anything ---" -ForegroundColor Cyan
$tmp = Join-Path $env:TEMP ("horde-listen-pure-" + [guid]::NewGuid().ToString("N"))
function Req { param([string]$HubId = $dev, $Port = 40123, [string]$HordeHome = $tmp, [string]$Address = "127.0.0.1") return [pscustomobject]@{ hordeHome = $HordeHome; hubId = $HubId; port = $Port; root = $root; register = $reg; address = $Address } }
try {
    # MESH V1, THE FOUNDER'S RULE 4: the port checks the address, and the adapter checks it again where it
    # writes it - a public address, every interface or no address at all is refused before anything else.
    foreach ($bad in @(@{ a = "8.8.8.8"; want = "*public address*" }, @{ a = "0.0.0.0"; want = "*every interface*" }, @{ a = "::"; want = "*every interface*" }, @{ a = ""; want = "*no address*" }, @{ a = "hub.local"; want = "*not an IP address*" })) {
        $r = Start-HordeSshListener -Request (Req -Address $bad.a)
        Check (-not $r.ok -and $r.reason -like ("*will not bind that address*" + $bad.want.TrimStart("*"))) ("the adapter itself refuses to bind '" + $bad.a + "' (" + $r.reason + ")")
    }
    $noReg = Req; $noReg.register = $null
    $r = Start-HordeSshListener -Request $noReg
    Check (-not $r.ok -and $r.reason -like "*no register of enrolled devices*") "no register to hold keys to: it admits none"
    $r = Start-HordeSshListener -Request (Req -HubId "HUB")
    Check (-not $r.ok -and $r.reason -like "*not a hub id*") "a hub id that is not a device id"
    $r = Start-HordeSshListener -Request (Req)
    Check (-not $r.ok -and $r.reason -like "*no listener host key*horde hub init*") "no host key: it says to run horde hub init"
    $lp = Get-HordeSshListenFiles -HordeHome $tmp
    New-Item -ItemType Directory -Path $lp.dir -Force | Out-Null
    [System.IO.File]::WriteAllText($lp.hostKey, "not read")
    $r = Start-HordeSshListener -Request (Req)
    Check (-not $r.ok -and $r.reason -like "*no node is enrolled*horde hub enroll*") "no authorized_keys: it says to run horde hub enroll"
    [System.IO.File]::WriteAllText($lp.authorized, ($good + "`n" + $pub + " horde-device-" + $other + "`n"))
    $r = Start-HordeSshListener -Request (Req)
    Check (-not $r.ok -and $r.reason -like "*line 2 of authorized_keys*") "a bare key: it refuses to start, naming the line"
    Check (-not (Test-Path -LiteralPath $lp.config) -and -not (Test-Path -LiteralPath $lp.revoked)) "and it wrote nothing: no configuration, no revoked_keys"
    [System.IO.File]::WriteAllText($lp.authorized, ($good + "`n"))
    foreach ($bad in @(0, -1, 65536)) {
        $r = Start-HordeSshListener -Request (Req -Port $bad)
        Check (-not $r.ok -and $r.reason -like "*not a TCP port*") ("port " + $bad + " is refused: the port picks a real one before the adapter is asked")
    }

    Write-Host ""
    Write-Host "--- a file, or a folder above it, another principal may write: it does not start (issue #123) ---" -ForegroundColor Cyan
    # A bare key line keeps every case here short of starting sshd: with the files sound, the refusal is
    # that line's; with one widened, the refusal is the widening's, before any key is read.
    [System.IO.File]::WriteAllText($lp.authorized, ($good + "`n" + $pub + " horde-device-" + $other + "`n"))
    $r = Start-HordeSshListener -Request (Req)
    Check (-not $r.ok -and $r.reason -like "*line 2 of authorized_keys*" -and $r.reason -notlike "*another principal*") ("CONTROL: in a home that admits only this user, SYSTEM and Administrators, the files pass and the bare key is what refuses (" + $r.reason + ")")
    $users = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
    function Grant-Users { param([string]$Path, [string]$Rights)
        $a = Get-Acl -LiteralPath $Path
        $inh = [System.Security.AccessControl.InheritanceFlags]::None
        if (Test-Path -LiteralPath $Path -PathType Container) { $inh = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit }
        $a.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($users, $Rights, $inh, [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow)))
        Set-Acl -LiteralPath $Path -AclObject $a }
    function Revoke-Users { param([string]$Path)
        $a = Get-Acl -LiteralPath $Path
        $null = $a.PurgeAccessRules($users)
        Set-Acl -LiteralPath $Path -AclObject $a }
    Grant-Users -Path $lp.dir -Rights "Modify"
    $r = Start-HordeSshListener -Request (Req)
    Check (-not $r.ok -and $r.reason -like "*another principal may write*hub\listen may be written by another principal: S-1-5-32-545*") ("a widened hub\listen folder: it refuses to start, naming the folder and who may write it (" + $r.reason + ")")
    Check (-not (Test-Path -LiteralPath $lp.config) -and -not (Test-Path -LiteralPath $lp.revoked)) "and writes nothing"
    Revoke-Users -Path $lp.dir
    $kids = @(Get-ChildItem -LiteralPath $lp.dir -File)
    foreach ($k in $kids) { Revoke-Users -Path $k.FullName }
    Check ((Start-HordeSshListener -Request (Req)).reason -notlike "*another principal*") "CONTROL: the widening taken back, the files pass again"
    Grant-Users -Path $lp.authorized -Rights "Write"
    $r = Start-HordeSshListener -Request (Req)
    Check (-not $r.ok -and $r.reason -like "*authorized_keys may be written by another principal*") ("a widened authorized_keys alone: refused, naming it (" + $r.reason + ")")
    Revoke-Users -Path $lp.authorized
    Grant-Users -Path $lp.authorized -Rights "Read"
    Check ((Start-HordeSshListener -Request (Req)).reason -notlike "*another principal*") "CONTROL: another principal that may only read is not a writer"
    Revoke-Users -Path $lp.authorized
    $a = Get-Acl -LiteralPath $lp.authorized
    $a.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($users, "Write", [System.Security.AccessControl.AccessControlType]::Deny)))
    Set-Acl -LiteralPath $lp.authorized -AclObject $a
    Check ((Start-HordeSshListener -Request (Req)).reason -notlike "*another principal*") "CONTROL: a rule that denies another principal writing is no writer"
    Revoke-Users -Path $lp.authorized
    Grant-Users -Path $tmp -Rights "Modify"
    $r = Start-HordeSshListener -Request (Req)
    Check (-not $r.ok -and $r.reason -like ("*" + $tmp + " may be written by another principal*")) ("a widened folder higher up, Horde's home itself: refused, naming it (" + $r.reason + ")")
    Revoke-Users -Path $tmp
    foreach ($p in @((Join-Path $tmp "hub"), $lp.dir) + @(Get-ChildItem -LiteralPath $lp.dir -File | ForEach-Object { $_.FullName })) { Revoke-Users -Path $p }
    $a = Get-Acl -LiteralPath $lp.dir
    $a.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($users, "Modify", ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit), [System.Security.AccessControl.PropagationFlags]::InheritOnly, [System.Security.AccessControl.AccessControlType]::Allow)))
    Set-Acl -LiteralPath $lp.dir -AclObject $a
    $w = @(Get-HordeSshOtherWriters -Path $lp.dir)
    Check ($w.Count -eq 0) ("an inherit-only rule grants nothing on the folder that carries it, so the folder itself is not widened (" + ($w -join ", ") + ")")
    Check (@(Get-HordeSshOtherWriters -Path $lp.authorized).Count -ge 1) "but a file under it that inherits takes it up, and is a finding: the rule is judged where it applies"
    $fresh = Join-Path $lp.dir "fresh"
    [System.IO.File]::WriteAllText($fresh, "x")
    Check (@(Get-HordeSshOtherWriters -Path $fresh).Count -ge 1) "CONTROL: a file made after it inherits it, and is a finding"
    Remove-Item -LiteralPath $fresh
    Write-HordeSshLines -Path $lp.revoked -Lines @("ssh-ed25519 " + ("E" * 68))
    Check ((Test-HordeSshKeyAcl -Path $lp.revoked) -eq "" -and @(Get-HordeSshOtherWriters -Path $lp.revoked).Count -eq 0) "the writer makes the file this user's alone even in a folder whose new files inherit a wider rule"
} finally { if ((Split-Path -Leaf $tmp) -like "horde-listen-pure-*") { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } }


Write-Host ""
Write-Host "--- a home sshd's configuration cannot name is refused up front (issue #147, item 3) ---" -ForegroundColor Cyan
foreach ($bad in @("C:\Users\Some One\.horde", "C:\h#1\.horde", "C:\h%u\.horde", 'C:\h"q\.horde', ("C:\tab" + [char]9 + "x"))) {
    $r = Start-HordeSshListener -Request (Req -HordeHome $bad)
    Check (-not $r.ok -and $r.reason -like "*space, #, % or quote*") ("refused, saying why: '" + ($bad -replace "`t", "\t") + "'")
}

Write-Host ""
Write-Host "--- health: sshd running AND every key still held to attach (issue #147, item 4) ---" -ForegroundColor Cyan
$tmp2 = Join-Path $env:TEMP ("horde-listen-health-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp2 | Out-Null
try {
    $ak = Join-Path $tmp2 "authorized_keys"
    [System.IO.File]::WriteAllText($ak, ($good + "`n"))
    $alive = [System.Diagnostics.Process]::GetCurrentProcess()
    $L = [pscustomobject]@{ process = $alive; authorized = $ak; root = $root }
    $h = Test-HordeSshListenerServing -Listener $L -Register $reg
    Check ($h.state -ceq "known" -and $h.value -eq $true) "CONTROL: sshd running and every key held: it serves"
    [System.IO.File]::AppendAllText($ak, ($pub.Replace("AAAA", "CCCC") + " horde-device-" + $other + "`n"))
    $h = Test-HordeSshListenerServing -Listener $L -Register $reg
    Check ($h.state -ceq "unknown" -and $h.reason -like "*changed after the listener started*line 2*") ("a bare key added after start is caught by the next health check (" + $h.reason + ")")
    [System.IO.File]::WriteAllText($ak, ($good + "`n"))
    Check ((Test-HordeSshListenerServing -Listener $L -Register $reg).value -eq $true) "and once the line is gone, it serves again"
    $h = Test-HordeSshListenerServing -Listener $L -Register @{ $other = $reg[$other] }
    Check ($h.state -ceq "unknown" -and $h.reason -like ("*device " + $dev + ", which the hub's register does not hold*")) ("a device revoked while it runs - gone from the register the next check is given - stops it (" + $h.reason + ")")
    Remove-Item -LiteralPath $ak
    $h = $null; try { $h = Test-HordeSshListenerServing -Listener $L -Register $reg } catch { $h = [pscustomobject]@{ state = "threw"; reason = $_.Exception.Message } }
    Check ($h.state -ceq "unknown" -and $h.reason -like "*authorized_keys is gone*") "authorized_keys removed: it stops"
    $h = Test-HordeSshListenerServing -Register $reg -Listener ([pscustomobject]@{ process = [pscustomobject]@{ HasExited = $true }; authorized = $ak; root = $root })
    Check ($h.state -ceq "known" -and $h.value -eq $false) "sshd ended: known not serving"
} finally { if ((Split-Path -Leaf $tmp2) -like "horde-listen-health-*") { Remove-Item -LiteralPath $tmp2 -Recurse -Force -ErrorAction SilentlyContinue } }
Write-Host ""
Write-Host "--- the listener port, with a stand-in adapter ---" -ForegroundColor Cyan
Check (@(Get-HordeListenerFiles | ForEach-Object { Split-Path -Leaf (Split-Path -Parent $_) }) -join "," -ceq "ssh") "CONTROL: the ssh transport is the one with a listener"
$a = Get-HordeListenerAdapter
Check ($a.state -ceq "known" -and $a.value.name -ceq "ssh") "with no name, the one listener there is"
Check ((Get-HordeListenerAdapter -Name "nope").state -ceq "unknown") "a name with no listener is unknown, not a guess"
$threw = $false; try { $null = Register-HordeListener -Folder (Join-Path $root "transports\ssh") -Start { } -Health { } -Stop { } } catch { $threw = $true }
Check $threw "a second registration under a name is refused; the first stands"
$seen = New-Object System.Collections.ArrayList
$healthSaw = New-Object System.Collections.ArrayList
$null = Register-HordeListener -Folder "x:\fake" -Start { param($R) [void]$seen.Add($R); return [pscustomobject]@{ ok = $true; listener = "L"; address = ("127.0.0.1:" + $R.port); reason = "" } } -Health { param($L, $Reg) [void]$healthSaw.Add($Reg); return (New-HordeKnown -Value $true) } -Stop { param($L) return "bye" }
Check ((Get-HordeListenerAdapter).state -ceq "unknown") "with two listeners and no name, the port will not choose"
$fake = (Get-HordeListenerAdapter -Name "fake").value
$regNow = @{ $dev = $pub }
$readings = [hashtable]::Synchronized(@{ n = 0 })
$regBlock = { $readings["n"] = [int]$readings["n"] + 1; return $regNow }
$s = Start-HordeListener -Adapter $fake -HordeHome "C:\h" -HubId $dev -Root $root -Register $regBlock -Port 0
Check ($s.state -ceq "known" -and $seen.Count -eq 1 -and $seen[0].port -gt 0 -and $seen[0].port -le 65535 -and $seen[0].hubId -ceq $dev -and $seen[0].root -ceq $root -and $seen[0].hordeHome -ceq "C:\h") ("-Port 0 is turned into a free port before the adapter is asked, and the request carries the home, hub and root (" + $seen[0].port + ")")
Check ($seen[0].register -is [hashtable] -and $seen[0].register[$dev] -ceq $pub) "and the hub's register, read by the port, as a table of device and key"
Check ($seen[0].address -ceq "127.0.0.1") "and, with no address named, 127.0.0.1"
$n = $seen.Count
$s2 = Start-HordeListener -Adapter $fake -HordeHome "C:\h" -HubId $dev -Root $root -Register $regBlock -Port 2222 -Address "192.168.1.182" -LocalAddresses @("127.0.0.1", "192.168.1.182")
Check ($s2.state -ceq "known" -and $seen.Count -eq $n + 1 -and $seen[-1].address -ceq "192.168.1.182" -and $seen[-1].port -eq 2222) "a private address this machine holds reaches the adapter as the address to bind (mesh v1)"
foreach ($bad in @(@{ a = "8.8.8.8"; want = "*public address*" }, @{ a = "0.0.0.0"; want = "*every interface*" }, @{ a = "192.168.1.183"; want = "*no interface of this machine*" })) {
    $s3 = Start-HordeListener -Adapter $fake -HordeHome "C:\h" -HubId $dev -Root $root -Register $regBlock -Port 2222 -Address $bad.a -LocalAddresses @("127.0.0.1", "192.168.1.182")
    Check ($s3.state -ceq "unknown" -and $s3.reason -like $bad.want -and $seen.Count -eq $n + 1) ("the port refuses '" + $bad.a + "' before the adapter is asked (" + $s3.reason + ")")
}
$fp = Get-HordeListenerFreePort -Address "127.0.0.1"
Check ($fp -gt 0 -and $fp -le 65535) "a free port is picked on the address asked"
$regNow = @{ $other = $pub }
$readings["n"] = 1
Check ((Test-HordeListenerServing -Running $s.value).value -eq $true -and (Stop-HordeListener -Running $s.value) -ceq "bye") "health and stop go to the adapter"
Check ($healthSaw.Count -eq 1 -and $healthSaw[0].ContainsKey($other) -and -not $healthSaw[0].ContainsKey($dev) -and [int]$readings["n"] -eq 2) "and health is given the register read again for that check, never the one read at start"
$h = Test-HordeListenerServing -Running ([pscustomobject]@{ adapter = $fake; listener = "L"; register = { throw "the register folder is locked" } })
Check ($h.state -ceq "unknown" -and $h.reason -like "*register could not be read*" -and $healthSaw.Count -eq 1) "a register that cannot be read stops the listener, and the adapter is not asked"
$h = Test-HordeListenerServing -Running ([pscustomobject]@{ adapter = $fake; listener = "L"; register = { return "not a table" } })
Check ($h.state -ceq "unknown" -and $h.reason -like "*did not read as a table*") "a register that is not a table stops it too"
$s = Start-HordeListener -Adapter $fake -HordeHome "C:\h" -HubId $dev -Root $root -Register { throw "no" } -Port 0
Check ($s.state -ceq "unknown" -and $s.reason -like "*register could not be read*" -and $seen.Count -eq $n + 1) "a register that cannot be read at start: nothing starts, the adapter is not asked"
Check ((Start-HordeListener -Adapter $fake -HordeHome "C:\h" -HubId $dev -Root $root -Register $regBlock -Port 70000).state -ceq "unknown") "a port above 65535 is refused by the port itself"
$null = Register-HordeListener -Folder "x:\failing" -Start { param($R) return [pscustomobject]@{ ok = $false; listener = $null; address = ""; reason = "it would not" } } -Health { param($L) return "not an answer" } -Stop { param($L) return "" }
$failing = (Get-HordeListenerAdapter -Name "failing").value
$s = Start-HordeListener -Adapter $failing -HordeHome "C:\h" -HubId $dev -Root $root -Register $regBlock -Port 1
Check ($s.state -ceq "unknown" -and $s.reason -like "*it would not*") "an adapter's refusal is unknown, with its reason"
$h = Test-HordeListenerServing -Running ([pscustomobject]@{ adapter = $failing; listener = $null; register = $regBlock })
Check ($h.state -ceq "unknown") "an adapter answering health with something that is not an answer is unknown"

Complete-HordeSuite -Success "the listener admits only enrolled keys forced to attach, and configures a loopback sshd from Horde's own files"
