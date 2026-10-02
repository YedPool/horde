# transports/ssh/Argv.ps1 - the ssh transport's argv, built from data and never from a user's config.
#
# Remote plan step R5; remote design 2.4. Pure functions: no file is read, no program is started.
#
# THE ENDPOINT is user@host:port/hubId - the account the hub's sshd forces into the link (8.3), where
# the hub is reached, and the hub's identity, which pins its host key (HostKeyAlias=horde-hub-<hubId>)
# so an overlay address change does not break the pin. Every part is matched against a closed
# pattern, and none may begin with "-": an endpoint can come from a file another program wrote, and
# a field that begins with "-" would reach ssh.exe as an option (ProxyCommand runs a program).
#
# THE OPTIONS are the design's list. Each is there for a measured or documented reason:
#   -F <Horde's config>   a config file Horde owns, which Open requires to hold no directive, so
#                         nothing in the user's ~/.ssh/config applies (ssh_config(5): a -F file is
#                         read instead of the user's). Chosen over -F none at the coordinator's
#                         request of 2026-10-02; both keep the user's config out.
#   IdentityFile, IdentitiesOnly=yes, IdentityAgent=none
#                         only Horde's key is offered. MEASURED 2026-10-02, OpenSSH_for_Windows 9.5p2: a
#                         -i file that does not exist when ssh starts adds nothing, and ssh then fills in
#                         the default ~/.ssh/id_* keys even with -F none and IdentitiesOnly; the review of
#                         PR #68 (F1) showed that this is a race, since Open checks the file before the
#                         spawn. -o IdentityFile adds the path without looking at it, so with the key
#                         gone ssh -G still lists only Horde's path: a vanished key is a failed login and
#                         never the user's own key. Open still refuses to start without the file.
#   PATHS, AS SSH READS THEM (review of PR #68, F2): inside a -o value ssh expands %d and %h, cuts at
#                         #, and fails on a quote (measured with ssh -G), so the known_hosts Open
#                         checked would not be the one ssh reads. It also SPLITS the value at
#                         whitespace: MEASURED 2026-10-02, -o IdentityFile=<a path with a space> is
#                         "extra arguments at end of line", exit 255 - and a profile folder with a
#                         space in it is ordinary. So each path value is written in double quotes,
#                         which ssh's own argument splitter removes (measured: spaces, a tilde, a UNC
#                         path and doubled backslashes all come back byte for byte). The second review
#                         round then found ${VAR} expanded too, the third such surprise; so rather than
#                         list what ssh treats specially, a path is held to an ALLOWLIST: letters,
#                         digits, space and \ / : . _ - and nothing else, and not ending in a backslash
#                         (which would escape the closing quote) (Test-HordeSshSafePath). ssh -G is held
#                         to resolving each path byte for byte (transports/ssh/test/test-ssh.ps1).
#   UserKnownHostsFile=<Horde's>, GlobalKnownHostsFile=none, StrictHostKeyChecking=yes,
#   HostKeyAlias, UpdateHostKeys=no, CheckHostIP=no
#                         the host key is checked against Horde's own file only, by hub identity,
#                         never added or updated. GlobalKnownHostsFile=none is accepted by 9.5p2
#                         (ssh -G, measured 2026-10-02; the design had it unproven).
#   BatchMode=yes         never prompt: a prompt would hang a daemon.
#   ConnectTimeout, ServerAliveInterval, ServerAliveCountMax
#                         a dead hub is noticed in about a minute without a frame being sent.
#   ControlMaster=no, ControlPath=none
#                         never share a connection with another ssh (design finding 5).
#   ForwardAgent=no, ForwardX11=no, ForwardX11Trusted=no, ClearAllForwardings=yes, GatewayPorts=no,
#   Tunnel=no, PermitLocalCommand=no, LocalCommand=none, RemoteCommand=none, RequestTTY=no,
#   ProxyCommand=none, ProxyJump=none, KnownHostsCommand=none, PKCS11Provider=none,
#   SecurityKeyProvider=internal
#                         nothing is forwarded, nothing runs locally or through a proxy, no command
#                         or provider is loaded. Each is already the default with Horde's empty -F
#                         config; pinning them here is defence in depth (review of PR #68, F5), each
#                         accepted by 9.5p2 (ssh -G, measured 2026-10-02; LocalCommand=none reads as
#                         unset, while an empty LocalCommand= is refused).
#   LogLevel=INFO         set, so no config can change it, and INFO rather than ERROR: MEASURED
#                         2026-10-02, 9.5p2 writes the reason for a refused connection ("banner
#                         exchange: Connection to UNKNOWN port -1: Connection refused") at INFO, and
#                         LogLevel=ERROR left stderr empty, so exit 255 would have had no reason.
#   -T                    no pseudo-terminal: the link is bytes, not a screen.
#   attach                ignored by the hub, whose key line forces the command (8.3); sent so a log
#                         reader sees the intent.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced.

$script:HordeSshUserPattern = '\A[a-z_][a-z0-9_-]{0,31}\z'
# A DNS name of lowercase or uppercase labels, or a dotted IPv4 address. No label begins or ends with
# a hyphen, so the host can never begin with "-".
$script:HordeSshHostPattern = '\A(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\z'
$script:HordeSshHubPattern = '\A[a-z0-9][a-z0-9-]{0,62}\z'
$script:HordeSshEndpointPattern = '\A(?<user>[^@]+)@(?<host>[^:/]+):(?<port>[0-9]{1,5})/(?<hub>[^/]+)\z'
$script:HordeSshHostKeyAliasPrefix = "horde-hub-"

function Test-HordeSshEndpointFields {
    # "" when user, host, port and hub id each match their closed pattern; otherwise why not. The one
    # check both the parser and Get-HordeSshArgv use, so an endpoint object made anywhere else is held to
    # the same rules before a field of it reaches argv (review of PR #68, round 3).
    param([string]$User, [string]$HostName, $Port, [string]$HubId)
    if (-not [regex]::IsMatch($User, $script:HordeSshUserPattern)) { return ("the user '" + $User + "' is not a lowercase account name") }
    if (-not [regex]::IsMatch($HostName, $script:HordeSshHostPattern)) { return ("the host '" + $HostName + "' is not a DNS name or IPv4 address") }
    if (-not ($Port -is [int]) -or $Port -lt 1 -or $Port -gt 65535) { return ("the port " + $Port + " is not between 1 and 65535") }
    if (-not [regex]::IsMatch($HubId, $script:HordeSshHubPattern)) { return ("the hub id '" + $HubId + "' is not lowercase letters, digits and hyphens, at most 63") }
    return ""
}

function ConvertFrom-HordeSshEndpoint {
    # "user@host:port/hubId" -> { ok; user; host; port; hubId; reason }.
    param([string]$Endpoint)
    $out = [pscustomobject]@{ ok = $false; user = ""; host = ""; port = 0; hubId = ""; reason = "" }
    $m = [regex]::Match("$Endpoint", $script:HordeSshEndpointPattern)
    if (-not $m.Success) { $out.reason = "'" + $Endpoint + "' is not an ssh endpoint: user@host:port/hubId"; return $out }
    $u = $m.Groups["user"].Value; $h = $m.Groups["host"].Value; $hub = $m.Groups["hub"].Value
    $port = [int]$m.Groups["port"].Value
    $why = Test-HordeSshEndpointFields -User $u -HostName $h -Port $port -HubId $hub
    if ($why -ne "") { $out.reason = $why; return $out }
    $out.ok = $true; $out.user = $u; $out.host = $h; $out.port = $port; $out.hubId = $hub
    return $out
}

function Test-HordeSshSafePath {
    # "" when ssh reads the path exactly as given inside a -o value; otherwise the reason it would not
    # (header, PATHS, AS SSH READS THEM). The reason never repeats the path's unprintable characters.
    param([string]$Path)
    if ($Path -eq "") { return "the path is empty" }
    # The allowlist (header, PATHS, AS SSH READS THEM): anything outside it is refused.
    $m = [regex]::Match($Path, '[^A-Za-z0-9 \\/:._-]')
    if (-not $m.Success) {
        # LOCAL AND ABSOLUTE (review of PR #68, round 3): ssh collapses a doubled backslash inside the
        # quotes, so \\host\share\x would be read as \host\share\x on the current drive.
        if (-not [regex]::IsMatch($Path, '\A[A-Za-z]:[\\/]')) { return ("ssh would not read the path '" + $Path + "' as written: a path ssh is given starts with a drive letter, as Horde's own local paths do") }
        if ($Path.Contains("\\") -or $Path.Contains("//")) { return ("ssh would not read the path '" + $Path + "' as written: it doubles a separator, which ssh collapses") }
        if ($Path.EndsWith("\")) { return ("ssh would not read the path '" + $Path + "' as written: it ends in a backslash, which would escape the quote around it") }
        return ""
    }
    $shown = $Path -replace '[^\x20-\x7E]', '?'
    $what = "'" + $m.Value + "'"
    if ($m.Value -notmatch '[\x20-\x7E]') { $what = "a character that is not printable ASCII" }
    return ("ssh would not read the path '" + $shown + "' as written: it holds " + $what + ", and a path ssh is given holds only letters, digits, space and \ / : . _ - (ssh expands %, `$ and `${}, cuts at #, refuses quotes)")
}

function Get-HordeSshPaths {
    # Horde's own key, known_hosts and config for the link, under <HordeHome>\node (design 2.4). Enrollment
    # (remote plan R17) writes them; this transport only reads them.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $node = Join-Path $HordeHome "node"
    return [pscustomobject]@{
        identity = (Join-Path $node "link_ed25519")
        knownHosts = (Join-Path $node "known_hosts")
        config = (Join-Path $node "ssh_config")
    }
}

function Get-HordeSshArgv {
    # The arguments after ssh.exe, for a parsed endpoint and Horde's paths. The header says why each.
    param([Parameter(Mandatory = $true)]$Endpoint, [Parameter(Mandatory = $true)]$Paths)
    if (-not $Endpoint.ok) { throw ("not an endpoint: " + $Endpoint.reason) }
    # Data in, argv out: the endpoint is re-checked here, whoever made the object (header of ExecGuard).
    $whyEp = Test-HordeSshEndpointFields -User "$($Endpoint.user)" -HostName "$($Endpoint.host)" -Port $Endpoint.port -HubId "$($Endpoint.hubId)"
    if ($whyEp -ne "") { throw ("not an endpoint argv will use: " + $whyEp) }
    foreach ($path in @($Paths.config, $Paths.identity, $Paths.knownHosts)) {
        $why = Test-HordeSshSafePath -Path $path
        if ($why -ne "") { throw $why }
    }
    return @(
        "-F", $Paths.config,
        "-T",
        "-o", ('IdentityFile="' + $Paths.identity + '"'),
        "-o", "IdentitiesOnly=yes",
        "-o", "IdentityAgent=none",
        "-o", ('UserKnownHostsFile="' + $Paths.knownHosts + '"'),
        "-o", "GlobalKnownHostsFile=none",
        "-o", "KnownHostsCommand=none",
        "-o", "StrictHostKeyChecking=yes",
        "-o", ("HostKeyAlias=" + $script:HordeSshHostKeyAliasPrefix + $Endpoint.hubId),
        "-o", "UpdateHostKeys=no",
        "-o", "CheckHostIP=no",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=15",
        "-o", "ServerAliveInterval=15",
        "-o", "ServerAliveCountMax=4",
        "-o", "ControlMaster=no",
        "-o", "ControlPath=none",
        "-o", "ProxyCommand=none",
        "-o", "ProxyJump=none",
        "-o", "ForwardAgent=no",
        "-o", "ForwardX11=no",
        "-o", "ForwardX11Trusted=no",
        "-o", "ClearAllForwardings=yes",
        "-o", "GatewayPorts=no",
        "-o", "Tunnel=no",
        "-o", "PermitLocalCommand=no",
        "-o", "LocalCommand=none",
        "-o", "RemoteCommand=none",
        "-o", "RequestTTY=no",
        "-o", "PKCS11Provider=none",
        "-o", "SecurityKeyProvider=internal",
        "-o", "LogLevel=INFO",
        "-p", ([string]$Endpoint.port),
        ($Endpoint.user + "@" + $Endpoint.host),
        "attach"
    )
}

function Join-HordeSshCommandLine {
    # One Windows command line from an argv, so that a program parsing it the C runtime's way (ssh.exe
    # does) gets each argument back unchanged: an argument with no space, tab or quote passes as it is;
    # any other is quoted, with backslashes doubled only where they precede a quote or the closing quote.
    param([string[]]$Argv)
    $parts = foreach ($a in @($Argv)) {
        if ($a.Length -gt 0 -and $a -notmatch '[\s"]') { $a; continue }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        $slashes = 0
        foreach ($ch in $a.ToCharArray()) {
            # [char] on purpose: '\' alone is a string, and StringBuilder has no Append(string, count).
            if ($ch -eq [char]92) { $slashes++; continue }
            if ($ch -eq [char]34) { [void]$sb.Append([char]92, 2 * $slashes + 1); [void]$sb.Append([char]34); $slashes = 0; continue }
            if ($slashes -gt 0) { [void]$sb.Append([char]92, $slashes); $slashes = 0 }
            [void]$sb.Append($ch)
        }
        if ($slashes -gt 0) { [void]$sb.Append([char]92, 2 * $slashes) }
        [void]$sb.Append('"')
        $sb.ToString()
    }
    return (@($parts) -join " ")
}
