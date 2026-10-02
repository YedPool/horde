# Mutations of the ssh transport's argv. Run: powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\argv.psd1
# Each weakens one option or one endpoint rule in transports\ssh\Argv.ps1; transports\ssh\test\test-ssh.ps1
# must fail for every one - by its exact argv check, and where ssh.exe is in System32, by ssh -G.
@{
    Target = "transports\ssh\Argv.ps1"
    Suite  = "transports\ssh\test\test-ssh.ps1"
    Mutations = @(
        @{ Name = "user-config-read"
           Find = '"-F", $Paths.config,'
           Replace = '' }
        @{ Name = "agent-asked"
           Find = '"-o", "IdentityAgent=none",'
           Replace = '' }
        @{ Name = "other-identities-tried"
           Find = '"-o", "IdentitiesOnly=yes",'
           Replace = '' }
        @{ Name = "user-known-hosts-read"
           Find = '"-o", ("UserKnownHostsFile=" + $Paths.knownHosts),'
           Replace = '' }
        @{ Name = "global-known-hosts-read"
           Find = '"-o", "GlobalKnownHostsFile=none",'
           Replace = '' }
        @{ Name = "unknown-host-key-accepted"
           Find = '"-o", "StrictHostKeyChecking=yes",'
           Replace = '"-o", "StrictHostKeyChecking=accept-new",' }
        @{ Name = "pinned-by-address"
           Find = '"-o", ("HostKeyAlias=" + $script:HordeSshHostKeyAliasPrefix + $Endpoint.hubId),'
           Replace = '' }
        @{ Name = "prompting-allowed"
           Find = '"-o", "BatchMode=yes",'
           Replace = '"-o", "BatchMode=no",' }
        @{ Name = "connection-shared"
           Find = '"-o", "ControlMaster=no",'
           Replace = '"-o", "ControlMaster=auto",' }
        @{ Name = "agent-forwarded"
           Find = '"-o", "ForwardAgent=no",'
           Replace = '"-o", "ForwardAgent=yes",' }
        @{ Name = "pty-asked"
           Find = '"-T",'
           Replace = '' }
        @{ Name = "user-may-start-with-hyphen"
           Find = "'\A[a-z_][a-z0-9_-]{0,31}\z'"
           Replace = "'\A[-a-z_][a-z0-9_-]{0,31}\z'" }
        @{ Name = "host-may-start-with-hyphen"
           Find = "'\A(?:[A-Za-z0-9](?:"
           Replace = "'\A(?:[-A-Za-z0-9](?:" }
        @{ Name = "port-unbounded"
           Find = 'if ($port -lt 1 -or $port -gt 65535) {'
           Replace = 'if ($false) {' }
        @{ Name = "hub-id-too-long"
           Find = "'\A[a-z0-9][a-z0-9-]{0,62}\z'"
           Replace = "'\A[a-z0-9][a-z0-9-]{0,63}\z'" }
        @{ Name = "quote-backslashes-not-doubled"
           Find = '[void]$sb.Append([char]92, 2 * $slashes + 1)'
           Replace = '[void]$sb.Append([char]92, $slashes + 1)' }
        @{ Name = "trailing-backslashes-not-doubled"
           Find = 'if ($slashes -gt 0) { [void]$sb.Append([char]92, 2 * $slashes) }'
           Replace = 'if ($slashes -gt 0) { [void]$sb.Append([char]92, $slashes) }' }
        @{ Name = "empty-argument-dropped"
           Find = 'if ($a.Length -gt 0 -and $a -notmatch'
           Replace = 'if ($a -notmatch' }
    )
}
