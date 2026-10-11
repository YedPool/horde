# Mutations of cli/commands/hub.ps1's serve: with -Listen, the requests written down for dialled nodes
# are carried over their links (mesh v1), proven against the whole mesh path
# (transports/ssh/test/test-mesh-act-local.ps1). Run, from a PowerShell-launched session on the machine
# with OpenSSH Server installed:
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\mesh-act-hub.psd1
# The suite must fail for each. Exit 3 (no sshd here) is not a pass.
@{
    Target = "cli\commands\hub.ps1"
    Suite  = "transports\ssh\test\test-mesh-act-local.ps1"
    Mutations = @(
        @{ Name = "serve-carries-nothing"
           Find = '-Listener $listener -Admit $admit -ActDir $actDir) }'
           Replace = '-Listener $listener -Admit $admit) }' }
    )
}
