# transports/ssh/Enroll.ps1 - enrolment for the ssh link: the node's key, the hub's host key, and the
# lines that admit, pin and revoke them (remote plan R17b). Dot-sourced by the commands that enrol,
# never by Transport.ps1: dialling needs none of it.
#
# WHAT LIVES WHERE, all under Horde's own home and never under ~/.ssh:
#   <home>\node\link_ed25519(.pub)       the node's link key; link_ed25519.previous after a rotation
#   <home>\node\ssh_config               no directive: Horde's argv is the whole configuration (R5)
#   <home>\node\known_hosts              one pin per hub, under the alias horde-hub-<hubId> (R5)
#   <home>\hub\listen\host_ed25519(.pub) the hub's listener host key (R17a's sshd uses it)
#   <home>\hub\listen\authorized_keys    one line per enrolled device:
#        command="<attach>",restrict,expiry-time="YYYYMMDD" ssh-ed25519 <key> horde-device-<id>
#                                        <attach> is Attach.ps1's, and nothing else: the listener runs
#                                        no ForceCommand, so command= and restrict are the whole guard
#   <home>\hub\listen\revoked_keys       every key revoked, for sshd's RevokedKeys (R17a): a revoked
#                                        key stays refused even if its line is restored by hand
# Enrolment and pinning move strings the founder carries between machines; no host key is ever taken
# from the network (remote plan R17).
#
# ONE PROGRAM, STARTED ONE WAY (coordinator's approval, 2026-10-06). New-HordeSshKey is the folder's
# second sanctioned start (transports/ssh/test/ExecGuard.ps1): the System32 ssh-keygen.exe, by its
# absolute path, checked as a rooted .exe, never found through PATH; a fixed argv - an ed25519 key, the
# passphrase from a parameter that must be empty (keys are unencrypted, protected by their ACL: remote
# design decision 13), and -f a path inside Horde's home, refused anywhere else; no flag from a caller.
# The private key's ACL is then set to this user alone and read back.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Argv.ps1")
. (Join-Path $PSScriptRoot "Attach.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\FileAtomic.ps1")

# A public key line Horde accepts: ed25519 only, base64 of the 51-byte blob (68 characters), and an
# optional comment of plain characters. Anything else is refused, never cleaned.
$script:HordeSshKeyLinePattern = '\Assh-ed25519 (?<b64>[A-Za-z0-9+/]{68})(?: (?<comment>[A-Za-z0-9@._-]{1,64}))?\z'
$script:HordeSshDevicePattern = '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'
# How long an enrolment is valid by default (remote design decision 13: a one-year expiry).
$script:HordeSshEnrolDays = 365

function New-HordeSshEnrolResult {
    # -Key and -Expires: an enrolment's bare key and expiry, for the hub's register (transports/Port.ps1).
    param([bool]$Ok, [string]$Line = "", [string]$Reason = "", [string]$Said = "", [string]$Key = "", [string]$Expires = "")
    return [pscustomobject]@{ ok = $Ok; line = $Line; reason = $Reason; said = $Said; key = $Key; expires = $Expires }
}

function Test-HordeSshInHome {
    # Is -Path, fully resolved, inside -HordeHome? "" when it is; otherwise why not.
    param([string]$Path, [string]$HordeHome)
    if ($Path -eq "" -or $HordeHome -eq "") { return "no path, or no home" }
    $full = [System.IO.Path]::GetFullPath($Path)
    $homeFull = [System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\')
    if (-not $full.StartsWith($homeFull + "\", [System.StringComparison]::OrdinalIgnoreCase)) { return ("'" + $full + "' is not inside Horde's home " + $homeFull) }
    return ""
}

function Set-HordeSshKeyAcl {
    # The file's ACL: this user alone, inheritance cut. Returns "" when it reads back so, or why not.
    param([string]$Path)
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($me)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, "FullControl", "Allow")))
    Set-Acl -LiteralPath $Path -AclObject $acl
    return (Test-HordeSshKeyAcl -Path $Path)
}

function Test-HordeSshKeyAcl {
    # "" when -Path's ACL is protected and admits this user alone; otherwise why not.
    param([string]$Path)
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $read = Get-Acl -LiteralPath $Path
    if (-not $read.AreAccessRulesProtected) { return ("the key " + $Path + " inherits access from its folder") }
    $rules = @($read.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    $others = @($rules | Where-Object { "$($_.IdentityReference)" -cne "$me" })
    if ($rules.Count -lt 1 -or $others.Count -gt 0) { return ("the key " + $Path + " admits someone besides this user: " + (@($others | ForEach-Object { "$($_.IdentityReference)" }) -join ", ")) }
    return ""
}

function New-HordeSshKey {
    # Make an ed25519 key pair at -Path and -Path.pub with the System32 ssh-keygen.exe, then restrict
    # the private key to this user. -Passphrase must be "" (header). -Path must be inside -HordeHome and
    # must not exist yet. Returns { ok; line (the public key line); reason }. THE FOLDER'S SECOND START.
    param([Parameter(Mandatory = $true)][string]$Path, [AllowEmptyString()][string]$Passphrase, [Parameter(Mandatory = $true)][string]$HordeHome)
    if ($Passphrase -cne "") { return (New-HordeSshEnrolResult -Ok $false -Reason "a link key has no passphrase: it is protected by its ACL (remote design decision 13), and a daemon could not type one") }
    $where = Test-HordeSshInHome -Path $Path -HordeHome $HordeHome
    if ($where -ne "") { return (New-HordeSshEnrolResult -Ok $false -Reason ("refused to write a key outside Horde's home: " + $where)) }
    $full = [System.IO.Path]::GetFullPath($Path)
    if ((Test-Path -LiteralPath $full) -or (Test-Path -LiteralPath ($full + ".pub"))) { return (New-HordeSshEnrolResult -Ok $false -Reason ("a key already exists at " + $full + "; it is never overwritten")) }
    $why = Test-HordeSshSafePath -Path $full
    if ($why -ne "") { return (New-HordeSshEnrolResult -Ok $false -Reason $why) }
    $exe = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh-keygen.exe")
    if (-not ([System.IO.Path]::IsPathRooted($exe) -and $exe.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $exe -PathType Leaf))) {
        return (New-HordeSshEnrolResult -Ok $false -Reason ("no ssh-keygen.exe at " + $exe + ": the System32 copy is the only one enrolment runs"))
    }
    $keygenArgs = Join-HordeSshCommandLine -Argv @("-q", "-t", "ed25519", "-N", "", "-C", "horde", "-f", $full)
    $psi = [System.Diagnostics.ProcessStartInfo]::new([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh-keygen.exe"), $keygenArgs)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $p.StandardInput.Close()
        $err = $p.StandardError.ReadToEndAsync()
        $null = $p.StandardOutput.ReadToEndAsync()
        if (-not $p.WaitForExit(30000)) { $p.Kill(); return (New-HordeSshEnrolResult -Ok $false -Reason "ssh-keygen did not finish within 30 s") }
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) { return (New-HordeSshEnrolResult -Ok $false -Reason ("ssh-keygen failed (exit " + $p.ExitCode + "): " + ("" + $err.Result).Trim())) }
    } finally { $p.Dispose() }
    if (-not ((Test-Path -LiteralPath $full -PathType Leaf) -and (Test-Path -LiteralPath ($full + ".pub") -PathType Leaf))) { return (New-HordeSshEnrolResult -Ok $false -Reason ("ssh-keygen wrote no key pair at " + $full)) }
    $acl = Set-HordeSshKeyAcl -Path $full
    if ($acl -ne "") { return (New-HordeSshEnrolResult -Ok $false -Reason ("the new key is not restricted to this user: " + $acl)) }
    return (New-HordeSshEnrolResult -Ok $true -Line ([System.IO.File]::ReadAllText($full + ".pub").Trim()))
}

function ConvertFrom-HordeSshKeyLine {
    # A public key line as Horde accepts it: { ok; type; b64; fingerprint (SHA256:...); reason }.
    param([string]$Line)
    $out = [pscustomobject]@{ ok = $false; type = ""; b64 = ""; fingerprint = ""; reason = "" }
    $m = [regex]::Match("$Line".Trim(), $script:HordeSshKeyLinePattern)
    if (-not $m.Success) { $out.reason = "not an ssh-ed25519 public key line: 'ssh-ed25519 <68 base64 characters> [comment]'"; return $out }
    $blob = $null
    try { $blob = [System.Convert]::FromBase64String($m.Groups["b64"].Value) } catch { $out.reason = "the key's base64 does not decode"; return $out }
    # The blob starts with the string "ssh-ed25519" (length 11) and then the 32-byte key: 4+11+4+32.
    if ($blob.Length -ne 51 -or [System.Text.Encoding]::ASCII.GetString($blob, 4, 11) -cne "ssh-ed25519") { $out.reason = "the key's blob is not an ed25519 key"; return $out }
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($blob)
    $out.ok = $true; $out.type = "ssh-ed25519"; $out.b64 = $m.Groups["b64"].Value
    $out.fingerprint = "SHA256:" + [System.Convert]::ToBase64String($hash).TrimEnd("=")
    return $out
}

function Read-HordeSshLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    return @([System.IO.File]::ReadAllLines($Path) | Where-Object { "$_".Trim() -ne "" })
}

function Write-HordeSshLines {
    # The whole file at once, LF line ends, ASCII: sshd reads these. Written beside it and renamed over
    # it in one step (core/FileAtomic.ps1), never rewritten in place: a kill mid-write of an in-place
    # write left authorized_keys empty, every device locked out (review of PR #111, N5).
    param([string]$Path, [string[]]$Lines)
    $text = ""
    foreach ($l in @($Lines)) { $text = $text + $l + "`n" }
    $tmp = $Path + ".tmp-" + [System.IO.Path]::GetRandomFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $text, [System.Text.Encoding]::ASCII)
        Move-HordeFileAtomic -From $tmp -To $Path
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Initialize-HordeSshNode {
    # The node's link key and empty ssh_config. Refuses when a key is there already (rotate it instead).
    # Returns the line to carry to the hub: "<deviceId> <public key line>".
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$DeviceId)
    if ($DeviceId -cnotmatch $script:HordeSshDevicePattern) { return (New-HordeSshEnrolResult -Ok $false -Reason ("not a device id: '" + $DeviceId + "'")) }
    $paths = Get-HordeSshPaths -HordeHome $HordeHome
    $null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $paths.identity))
    if (-not (Test-Path -LiteralPath $paths.config)) { [System.IO.File]::WriteAllText($paths.config, "# Horde's ssh_config holds no directive: its argv is the whole configuration.`n", [System.Text.Encoding]::ASCII) }
    $k = New-HordeSshKey -Path $paths.identity -Passphrase "" -HordeHome $HordeHome
    if (-not $k.ok) { return $k }
    return (New-HordeSshEnrolResult -Ok $true -Line ($DeviceId + " " + (ConvertTo-HordeSshBareKey $k.line)))
}

function ConvertTo-HordeSshBareKey {
    # "ssh-ed25519 <b64>", the comment dropped.
    param([string]$Line)
    $parts = "$Line".Trim().Split(" ")
    return ($parts[0] + " " + $parts[1])
}

function Reset-HordeSshNodeKey {
    # Rotate: the current key moves to link_ed25519.previous (the one before is removed) and a new key
    # is made. The link fails until the hub enrols the new key; the hub then revokes the old one.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$DeviceId)
    if ($DeviceId -cnotmatch $script:HordeSshDevicePattern) { return (New-HordeSshEnrolResult -Ok $false -Reason ("not a device id: '" + $DeviceId + "'")) }
    $paths = Get-HordeSshPaths -HordeHome $HordeHome
    if (-not (Test-Path -LiteralPath $paths.identity -PathType Leaf)) { return (New-HordeSshEnrolResult -Ok $false -Reason "there is no link key to rotate; make one with node init") }
    $prev = $paths.identity + ".previous"
    foreach ($f in @($prev, ($prev + ".pub"))) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    Move-Item -LiteralPath $paths.identity -Destination $prev
    Move-Item -LiteralPath ($paths.identity + ".pub") -Destination ($prev + ".pub")
    $k = New-HordeSshKey -Path $paths.identity -Passphrase "" -HordeHome $HordeHome
    if (-not $k.ok) { return $k }
    return (New-HordeSshEnrolResult -Ok $true -Line ($DeviceId + " " + (ConvertTo-HordeSshBareKey $k.line)))
}

function Add-HordeSshPin {
    # Pin hub -HubId's host key in the node's known_hosts. A hub already pinned to another key is
    # refused unless -Replace: a changed host key is a reason to stop, not to update (remote plan R17).
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$HubId, [Parameter(Mandatory = $true)][string]$HostKey, [switch]$Replace)
    if ($HubId -cnotmatch $script:HordeSshHubPattern) { return (New-HordeSshEnrolResult -Ok $false -Reason ("not a hub id: '" + $HubId + "'")) }
    $k = ConvertFrom-HordeSshKeyLine -Line $HostKey
    if (-not $k.ok) { return (New-HordeSshEnrolResult -Ok $false -Reason ("the hub's host key: " + $k.reason)) }
    $paths = Get-HordeSshPaths -HordeHome $HordeHome
    $null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $paths.knownHosts))
    $alias = $script:HordeSshHostKeyAliasPrefix + $HubId
    $line = $alias + " " + $k.type + " " + $k.b64
    $kept = New-Object System.Collections.ArrayList
    foreach ($l in @(Read-HordeSshLines -Path $paths.knownHosts)) {
        if ($l.StartsWith($alias + " ", [System.StringComparison]::Ordinal)) {
            if ($l -ceq $line) { return (New-HordeSshEnrolResult -Ok $true -Line $line) }
            if (-not $Replace) { return (New-HordeSshEnrolResult -Ok $false -Reason ("hub " + $HubId + " is already pinned to another host key; pin again with -Replace only if the hub's key really changed")) }
            continue
        }
        [void]$kept.Add($l)
    }
    [void]$kept.Add($line)
    Write-HordeSshLines -Path $paths.knownHosts -Lines $kept.ToArray()
    return (New-HordeSshEnrolResult -Ok $true -Line $line)
}

function Get-HordeSshListenPaths {
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $dir = Join-Path $HordeHome "hub\listen"
    return [pscustomobject]@{ dir = $dir; hostKey = (Join-Path $dir "host_ed25519"); authorized = (Join-Path $dir "authorized_keys"); revoked = (Join-Path $dir "revoked_keys") }
}

function Initialize-HordeSshHub {
    # The hub listener's host key. Returns the line a node pins: "<hubId> <host public key>". Run again,
    # it returns the same line and makes nothing.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$HubId)
    if ($HubId -cnotmatch $script:HordeSshHubPattern) { return (New-HordeSshEnrolResult -Ok $false -Reason ("not a hub id: '" + $HubId + "'")) }
    $lp = Get-HordeSshListenPaths -HordeHome $HordeHome
    $null = [System.IO.Directory]::CreateDirectory($lp.dir)
    if (-not (Test-Path -LiteralPath $lp.hostKey -PathType Leaf)) {
        $k = New-HordeSshKey -Path $lp.hostKey -Passphrase "" -HordeHome $HordeHome
        if (-not $k.ok) { return $k }
    }
    return (New-HordeSshEnrolResult -Ok $true -Line ($HubId + " " + (ConvertTo-HordeSshBareKey ([System.IO.File]::ReadAllText($lp.hostKey + ".pub")))))
}

function Get-HordeSshEnrolment {
    # The authorized_keys line of -DeviceId, parsed: { device; fingerprint; line }, or $null.
    param([string[]]$Lines, [string]$DeviceId)
    foreach ($l in @($Lines)) {
        if ($l.EndsWith(" horde-device-" + $DeviceId, [System.StringComparison]::Ordinal)) { return $l }
    }
    return $null
}

function New-HordeSshEnrolLine {
    # The one shape of an enrolled device's authorized_keys line: command= and restrict always, then
    # the expiry, the key and the device's comment. -Key is ConvertFrom-HordeSshKeyLine's answer.
    param([Parameter(Mandatory = $true)][string]$Command, [Parameter(Mandatory = $true)][string]$Expiry, [Parameter(Mandatory = $true)]$Key, [Parameter(Mandatory = $true)][string]$DeviceId)
    return ('command="' + $Command + '",restrict,expiry-time="' + $Expiry + '" ' + $Key.type + " " + $Key.b64 + " horde-device-" + $DeviceId)
}

function Add-HordeSshEnrolment {
    # Admit device -DeviceId's key: one authorized_keys line with command= (Attach.ps1's attach for
    # this device, Horde at -HordeRoot), restrict and expiry-time, always all three: the listener runs
    # no ForceCommand (Attach.ps1). No caller names the command. Refused: a device already enrolled
    # with another key, a key already enrolled for another device, and a revoked key.
    # ENROLLING AGAIN RENEWS (review of PR #111, B1): the same device and key enrolled again had its old
    # line kept, expiry and all, and was told it was enrolled, so every link died a year on. Its line is
    # now written afresh - this command, restrict, and the later of the old and the new expiry - and
    # said "renewed until"; an expiry is never shortened.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$DeviceId, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][string]$HordeRoot, [int]$Days = $script:HordeSshEnrolDays, $Now = $null)
    if ($DeviceId -cnotmatch $script:HordeSshDevicePattern) { return (New-HordeSshEnrolResult -Ok $false -Reason ("not a device id: '" + $DeviceId + "'")) }
    $Command = ""
    try { $Command = Get-HordeSshAttachCommand -HordeRoot $HordeRoot -DeviceId $DeviceId } catch { return (New-HordeSshEnrolResult -Ok $false -Reason $_.Exception.Message) }
    $k = ConvertFrom-HordeSshKeyLine -Line $Key
    if (-not $k.ok) { return (New-HordeSshEnrolResult -Ok $false -Reason ("the node's key: " + $k.reason)) }
    if ($Days -lt 1 -or $Days -gt 366) { return (New-HordeSshEnrolResult -Ok $false -Reason "an enrolment lasts 1 to 366 days") }
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    $lp = Get-HordeSshListenPaths -HordeHome $HordeHome
    $null = [System.IO.Directory]::CreateDirectory($lp.dir)
    foreach ($r in @(Read-HordeSshLines -Path $lp.revoked)) {
        $rk = ConvertFrom-HordeSshKeyLine -Line $r
        if ($rk.ok -and $rk.b64 -ceq $k.b64) { return (New-HordeSshEnrolResult -Ok $false -Reason ("the key " + $k.fingerprint + " was revoked; a revoked key is never enrolled again")) }
    }
    $lines = @(Read-HordeSshLines -Path $lp.authorized)
    $mine = Get-HordeSshEnrolment -Lines $lines -DeviceId $DeviceId
    $expiry = $Now.AddDays($Days).ToString("yyyyMMdd", [System.Globalization.CultureInfo]::InvariantCulture)
    if ($null -ne $mine) {
        if (-not $mine.Contains(" " + $k.b64 + " ")) { return (New-HordeSshEnrolResult -Ok $false -Reason ("device " + $DeviceId + " is already enrolled with another key; revoke it first")) }
        $was = [regex]::Match($mine, 'expiry-time="([0-9]{8})"').Groups[1].Value
        if ($was -gt $expiry) { $expiry = $was }
        $fresh = New-HordeSshEnrolLine -Command $Command -Expiry $expiry -Key $k -DeviceId $DeviceId
        $bare = $k.type + " " + $k.b64
        if ($fresh -ceq $mine) { return (New-HordeSshEnrolResult -Ok $true -Line $mine -Said ("device " + $DeviceId + " is already enrolled until " + $expiry + "; nothing changed.") -Key $bare -Expires $expiry) }
        Write-HordeSshLines -Path $lp.authorized -Lines @($lines | ForEach-Object { if ($_ -ceq $mine) { $fresh } else { $_ } })
        return (New-HordeSshEnrolResult -Ok $true -Line $fresh -Said ("device " + $DeviceId + " is renewed until " + $expiry + " (it was until " + $was + ").") -Key $bare -Expires $expiry)
    }
    foreach ($l in $lines) { if ($l.Contains(" " + $k.b64 + " ")) { return (New-HordeSshEnrolResult -Ok $false -Reason ("the key " + $k.fingerprint + " is already enrolled for another device")) } }
    $line = New-HordeSshEnrolLine -Command $Command -Expiry $expiry -Key $k -DeviceId $DeviceId
    Write-HordeSshLines -Path $lp.authorized -Lines (@($lines) + @($line))
    return (New-HordeSshEnrolResult -Ok $true -Line $line -Key ($k.type + " " + $k.b64) -Expires $expiry)
}

function Remove-HordeSshEnrolment {
    # Revoke device -DeviceId: its line is removed from authorized_keys and its key is added to
    # revoked_keys, which sshd reads as RevokedKeys (R17a), so restoring the line by hand admits nothing.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$DeviceId)
    if ($DeviceId -cnotmatch $script:HordeSshDevicePattern) { return (New-HordeSshEnrolResult -Ok $false -Reason ("not a device id: '" + $DeviceId + "'")) }
    $lp = Get-HordeSshListenPaths -HordeHome $HordeHome
    $lines = @(Read-HordeSshLines -Path $lp.authorized)
    $mine = Get-HordeSshEnrolment -Lines $lines -DeviceId $DeviceId
    if ($null -eq $mine) { return (New-HordeSshEnrolResult -Ok $false -Reason ("device " + $DeviceId + " is not enrolled")) }
    $m = [regex]::Match($mine, ' (?<key>ssh-ed25519 [A-Za-z0-9+/]{68}) horde-device-')
    if (-not $m.Success) { return (New-HordeSshEnrolResult -Ok $false -Reason ("the enrolment line of device " + $DeviceId + " holds no key Horde wrote")) }
    Write-HordeSshLines -Path $lp.revoked -Lines (@(Read-HordeSshLines -Path $lp.revoked) + @($m.Groups["key"].Value))
    Write-HordeSshLines -Path $lp.authorized -Lines @($lines | Where-Object { $_ -cne $mine })
    return (New-HordeSshEnrolResult -Ok $true -Line $m.Groups["key"].Value)
}

function Test-HordeSshEnrolled {
    # Does the listener still admit device -DeviceId at -Now? The hub's admission of a dialled link asks
    # this beside its own register (cli/HubRegistry.ps1; issue #144, item 3). ok, with the bare key as
    # line, when authorized_keys holds the device's line, its key is not in revoked_keys, and its
    # expiry-time is not reached; otherwise why not. sshd reads expiry-time="YYYYMMDD" as 00:00 of that
    # day, local time (sshd(8)), so a key is over from that moment here too.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$DeviceId, $Now = $null)
    if ($DeviceId -cnotmatch $script:HordeSshDevicePattern) { return (New-HordeSshEnrolResult -Ok $false -Reason ("not a device id: '" + $DeviceId + "'")) }
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    $lp = Get-HordeSshListenPaths -HordeHome $HordeHome
    $mine = Get-HordeSshEnrolment -Lines @(Read-HordeSshLines -Path $lp.authorized) -DeviceId $DeviceId
    if ($null -eq $mine) { return (New-HordeSshEnrolResult -Ok $false -Reason ("authorized_keys holds no line for device " + $DeviceId)) }
    $m = [regex]::Match($mine, ' (?<key>ssh-ed25519 [A-Za-z0-9+/]{68}) horde-device-')
    if (-not $m.Success) { return (New-HordeSshEnrolResult -Ok $false -Reason ("the authorized_keys line of device " + $DeviceId + " holds no key Horde wrote")) }
    $key = $m.Groups["key"].Value
    foreach ($r in @(Read-HordeSshLines -Path $lp.revoked)) {
        if ("$r".Trim() -ceq $key) { return (New-HordeSshEnrolResult -Ok $false -Reason ("the key of device " + $DeviceId + " is in revoked_keys")) }
    }
    $exp = [regex]::Match($mine, 'expiry-time="([0-9]{8})"')
    if (-not $exp.Success) { return (New-HordeSshEnrolResult -Ok $false -Reason ("the authorized_keys line of device " + $DeviceId + " carries no expiry-time; enrolment always writes one")) }
    $d = [datetime]::ParseExact($exp.Groups[1].Value, "yyyyMMdd", [System.Globalization.CultureInfo]::InvariantCulture)
    if ($Now.ToLocalTime().Date -ge $d.Date) { return (New-HordeSshEnrolResult -Ok $false -Reason ("the key of device " + $DeviceId + " expired at the start of " + $exp.Groups[1].Value)) }
    return (New-HordeSshEnrolResult -Ok $true -Line $key -Expires $exp.Groups[1].Value)
}

$null = Register-HordeEnrollment -Folder $PSScriptRoot `
    -NodeInit { param($HordeHome, $DeviceId) Initialize-HordeSshNode -HordeHome $HordeHome -DeviceId $DeviceId } `
    -NodeRotate { param($HordeHome, $DeviceId) Reset-HordeSshNodeKey -HordeHome $HordeHome -DeviceId $DeviceId } `
    -NodePin { param($HordeHome, $HubId, $HostKey, $Replace) Add-HordeSshPin -HordeHome $HordeHome -HubId $HubId -HostKey $HostKey -Replace:$Replace } `
    -HubInit { param($HordeHome, $HubId) Initialize-HordeSshHub -HordeHome $HordeHome -HubId $HubId } `
    -HubEnroll { param($HordeHome, $DeviceId, $Key, $HordeRoot, $Days) Add-HordeSshEnrolment -HordeHome $HordeHome -DeviceId $DeviceId -Key $Key -HordeRoot $HordeRoot -Days $Days } `
    -HubRevoke { param($HordeHome, $DeviceId) Remove-HordeSshEnrolment -HordeHome $HordeHome -DeviceId $DeviceId } `
    -HubEnrolled { param($HordeHome, $DeviceId, $Now) Test-HordeSshEnrolled -HordeHome $HordeHome -DeviceId $DeviceId -Now $Now }
