# Mutations of the ssh transport's argv that only a live server can show (remote plan R16). Run, from
# a PowerShell-launched session on the machine with OpenSSH Server installed:
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\argv-live.psd1
# transports\ssh\test\test-sshd-local.ps1 must fail for each. It exits 3 when this machine cannot run
# its sshd, and this spec accepts only 0: a run where the live cases were skipped is "not run", never
# a survivor.
@{
    Target = "transports\ssh\Argv.ps1"
    Suite  = "transports\ssh\test\test-sshd-local.ps1"
    Mutations = @(
        @{ Name = "host-key-not-checked-strictly"
           Find = '"-o", "StrictHostKeyChecking=yes",'
           Replace = '"-o", "StrictHostKeyChecking=no",' }
        @{ Name = "host-key-alias-dropped"
           Find = '"-o", ("HostKeyAlias=" + $script:HordeSshHostKeyAliasPrefix + $Endpoint.hubId),'
           Replace = '' }
        @{ Name = "known-hosts-not-horde-s"
           Find = '"-o", (''UserKnownHostsFile="'' + $Paths.knownHosts + ''"''),'
           Replace = '"-o", ''UserKnownHostsFile=NUL'',' }
    )
}
