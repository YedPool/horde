# WHAT DOES THE HUB'S LISTENER ADMIT, AND WHAT DOES IT TELL sshd? (pure: no server is started)
#
# Remote plan R17a. transports/ssh/Listen.ps1 decides two things before it starts anything, and both are
# tested here with no sshd, so they run anywhere: which authorized_keys lines it will serve (one
# enrolled device each, forced to exactly the attach Get-HordeSshAttachCommand builds for it, restricted;
# anything else, a bare key above all, makes it refuse to start), and the configuration it writes
# (loopback only, Horde's own files only, no ForceCommand, no forwarding, no terminal, HORDE_HOME passed
# to the session). Also the listener port (transports/Listener.ps1), with a stand-in adapter. The live
# half is test-listen-local.ps1.

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
function Keys { param([string[]]$Lines) return @(Test-HordeSshListenKeys -Lines $Lines -Root $root) }

Write-Host ""
Write-Host "--- the keys it admits: one enrolled device each, forced to its attach, restricted ---" -ForegroundColor Cyan
Check ((Keys @($good)).Count -eq 0) "CONTROL: a line forced to what Get-HordeSshAttachCommand returns for its device, restricted, is admitted"
Check ((Keys @(('command="' + $attach + '",restrict,expiry-time="20991231" ' + $pub + " horde-device-" + $dev), "", "  ")).Count -eq 0) "and with an expiry, beside blank lines"
Check ((Keys @($good, ('command="' + (Get-HordeSshAttachCommand -HordeRoot $root -DeviceId $other) + '",restrict ' + $pub.Replace("AAAA", "BBBB") + " horde-device-" + $other))).Count -eq 0) "two devices, each forced to its own attach"
$cases = [ordered]@{
    "a bare key, with no command= (it would be a shell)" = ($pub + " horde-device-" + $dev)
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
Write-Host "--- the configuration it writes ---" -ForegroundColor Cyan
$hh = "C:\HordeHomeForTest"
$files = Get-HordeSshListenFiles -HordeHome $hh
Check ($files.dir -ceq "C:\HordeHomeForTest\hub\listen" -and $files.authorized -ceq "C:\HordeHomeForTest\hub\listen\authorized_keys" -and $files.hostKey -ceq "C:\HordeHomeForTest\hub\listen\host_ed25519" -and $files.revoked -ceq "C:\HordeHomeForTest\hub\listen\revoked_keys") "its files are enrolment's, under <home>\hub\listen"
$cfg = @(Get-HordeSshListenConfig -Files $files -Port 40123 -HordeHome $hh -User "someone")
function Has { param([string]$Line) return (@($cfg | Where-Object { $_ -ceq $Line }).Count -eq 1) }
Check (Has "Port 40123") "the port it was given"
Check ((Has "ListenAddress 127.0.0.1") -and (Has "AddressFamily inet") -and @($cfg | Where-Object { $_ -like "ListenAddress*" }).Count -eq 1) "127.0.0.1 only: a node on another machine arrives through a tunnel, never through the firewall"
Check ((Has "HostKey C:/HordeHomeForTest/hub/listen/host_ed25519") -and (Has "AuthorizedKeysFile C:/HordeHomeForTest/hub/listen/authorized_keys") -and (Has "RevokedKeys C:/HordeHomeForTest/hub/listen/revoked_keys") -and (Has "PidFile C:/HordeHomeForTest/hub/listen/sshd.pid")) "every file it names is Horde's own, under its home"
Check (@($cfg | Where-Object { $_.ToLowerInvariant().Contains("programdata") -or $_.Contains(".ssh") -or $_.Contains("%h") -or $_.Contains("%u") }).Count -eq 0) "and none is ProgramData\ssh, ~/.ssh or a per-user default"
Check (@($cfg | Where-Object { $_ -like "ForceCommand*" -or $_ -like "Match*" -or $_ -like "Include*" }).Count -eq 0) "no ForceCommand (it would replace each key's -Device), no Match, no Include"
Check ((Has "AllowUsers someone") -and (Has "PubkeyAuthentication yes") -and (Has "PasswordAuthentication no") -and (Has "KbdInteractiveAuthentication no")) "keys only, for this user only"
Check ((Has "PermitTTY no") -and (Has "DisableForwarding yes") -and (Has "PermitTunnel no") -and (Has "PermitUserEnvironment no") -and (Has "Subsystem sftp none")) "no terminal, no forwarding of any kind, no tunnel, no user environment, no sftp"
Check (Has 'SetEnv "HORDE_HOME=C:/HordeHomeForTest"') "HORDE_HOME is passed to the session, so attach finds this hub's device id"
Check (@($cfg | Where-Object { $_ -cnotmatch '\A[\x20-\x7E]+\z' }).Count -eq 0) "every line is printable ASCII"

Write-Host ""
Write-Host "--- what it refuses before it starts anything ---" -ForegroundColor Cyan
$tmp = Join-Path $env:TEMP ("horde-listen-pure-" + [guid]::NewGuid().ToString("N"))
try {
    $r = Start-HordeSshListener -Request ([pscustomobject]@{ hordeHome = $tmp; hubId = "HUB"; port = 40123; root = $root })
    Check (-not $r.ok -and $r.reason -like "*not a hub id*") "a hub id that is not a device id"
    $r = Start-HordeSshListener -Request ([pscustomobject]@{ hordeHome = $tmp; hubId = $dev; port = 40123; root = $root })
    Check (-not $r.ok -and $r.reason -like "*no listener host key*horde hub init*") "no host key: it says to run horde hub init"
    $lp = Get-HordeSshListenFiles -HordeHome $tmp
    New-Item -ItemType Directory -Path $lp.dir -Force | Out-Null
    [System.IO.File]::WriteAllText($lp.hostKey, "not read")
    $r = Start-HordeSshListener -Request ([pscustomobject]@{ hordeHome = $tmp; hubId = $dev; port = 40123; root = $root })
    Check (-not $r.ok -and $r.reason -like "*no node is enrolled*horde hub enroll*") "no authorized_keys: it says to run horde hub enroll"
    [System.IO.File]::WriteAllText($lp.authorized, ($good + "`n" + $pub + " horde-device-" + $other + "`n"))
    $r = Start-HordeSshListener -Request ([pscustomobject]@{ hordeHome = $tmp; hubId = $dev; port = 40123; root = $root })
    Check (-not $r.ok -and $r.reason -like "*line 2 of authorized_keys*") "a bare key: it refuses to start, naming the line"
    Check (-not (Test-Path -LiteralPath $lp.config) -and -not (Test-Path -LiteralPath $lp.revoked)) "and it wrote nothing: no configuration, no revoked_keys"
    [System.IO.File]::WriteAllText($lp.authorized, ($good + "`n"))
    foreach ($bad in @(0, -1, 65536)) {
        $r = Start-HordeSshListener -Request ([pscustomobject]@{ hordeHome = $tmp; hubId = $dev; port = $bad; root = $root })
        Check (-not $r.ok -and $r.reason -like "*not a TCP port*") ("port " + $bad + " is refused: the port picks a real one before the adapter is asked")
    }
} finally { if ((Split-Path -Leaf $tmp) -like "horde-listen-pure-*") { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } }

Write-Host ""
Write-Host "--- the listener port, with a stand-in adapter ---" -ForegroundColor Cyan
Check (@(Get-HordeListenerFiles | ForEach-Object { Split-Path -Leaf (Split-Path -Parent $_) }) -join "," -ceq "ssh") "CONTROL: the ssh transport is the one with a listener"
$a = Get-HordeListenerAdapter
Check ($a.state -ceq "known" -and $a.value.name -ceq "ssh") "with no name, the one listener there is"
Check ((Get-HordeListenerAdapter -Name "nope").state -ceq "unknown") "a name with no listener is unknown, not a guess"
$threw = $false; try { $null = Register-HordeListener -Folder (Join-Path $root "transports\ssh") -Start { } -Health { } -Stop { } } catch { $threw = $true }
Check $threw "a second registration under a name is refused; the first stands"
$seen = New-Object System.Collections.ArrayList
$null = Register-HordeListener -Folder "x:\fake" -Start { param($R) [void]$seen.Add($R); return [pscustomobject]@{ ok = $true; listener = "L"; address = ("127.0.0.1:" + $R.port); reason = "" } } -Health { param($L) return (New-HordeKnown -Value $true) } -Stop { param($L) return "bye" }
Check ((Get-HordeListenerAdapter).state -ceq "unknown") "with two listeners and no name, the port will not choose"
$fake = (Get-HordeListenerAdapter -Name "fake").value
$s = Start-HordeListener -Adapter $fake -HordeHome "C:\h" -HubId $dev -Root $root -Port 0
Check ($s.state -ceq "known" -and $seen.Count -eq 1 -and $seen[0].port -gt 0 -and $seen[0].port -le 65535 -and $seen[0].hubId -ceq $dev -and $seen[0].root -ceq $root -and $seen[0].hordeHome -ceq "C:\h") ("-Port 0 is turned into a free port before the adapter is asked, and the request carries the home, hub and root (" + $seen[0].port + ")")
Check ((Test-HordeListenerServing -Running $s.value).value -eq $true -and (Stop-HordeListener -Running $s.value) -ceq "bye") "health and stop go to the adapter"
Check ((Start-HordeListener -Adapter $fake -HordeHome "C:\h" -HubId $dev -Root $root -Port 70000).state -ceq "unknown") "a port above 65535 is refused by the port itself"
$null = Register-HordeListener -Folder "x:\failing" -Start { param($R) return [pscustomobject]@{ ok = $false; listener = $null; address = ""; reason = "it would not" } } -Health { param($L) return "not an answer" } -Stop { param($L) return "" }
$failing = (Get-HordeListenerAdapter -Name "failing").value
$s = Start-HordeListener -Adapter $failing -HordeHome "C:\h" -HubId $dev -Root $root -Port 1
Check ($s.state -ceq "unknown" -and $s.reason -like "*it would not*") "an adapter's refusal is unknown, with its reason"
$h = Test-HordeListenerServing -Running ([pscustomobject]@{ adapter = $failing; listener = $null })
Check ($h.state -ceq "unknown") "an adapter answering health with something that is not an answer is unknown"

Complete-HordeSuite -Success "the listener admits only enrolled keys forced to attach, and configures a loopback sshd from Horde's own files"
