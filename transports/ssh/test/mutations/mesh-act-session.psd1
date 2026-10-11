# Mutations of cli/commands/session.ps1's wait for a dialled node's answer, against the whole mesh path
# (transports/ssh/test/test-mesh-act-local.ps1: horde listen, horde hub serve -Listen and a node dialling
# over 127.0.0.1). Run, from a PowerShell-launched session on the machine with OpenSSH Server installed:
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\mesh-act-session.psd1
# The suite must fail for each. Exit 3 (no sshd here) is not a pass.
@{
    Target = "cli\commands\session.ps1"
    Suite  = "transports\ssh\test\test-mesh-act-local.ps1"
    Mutations = @(
        @{ Name = "dialled-answer-not-waited-for"
           Find = '$got = Wait-HordeHubCarried -Dir $actDir -RequestId "$($rec.requestId)" -TimeoutMs ($TimeoutSeconds * 1000)'
           Replace = '$got = $rec' }
    )
}
