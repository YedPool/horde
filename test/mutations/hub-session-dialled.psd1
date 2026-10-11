# Mutations of cli/commands/session.ps1's dialled route (mesh v1): a request for a node that dials in is
# written down for the hub to carry, never sent from the CLI, and refused before anything is written
# when the node is unknown or revoked. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hub-session-dialled.psd1
# test\test-hub-carry.ps1 must fail for every one; the wait itself is test-mesh-act-local's
# (transports\ssh\test\mutations\mesh-act-session.psd1).
@{
    Target = "cli\commands\session.ps1"
    Suite  = "test\test-hub-carry.ps1"
    Mutations = @(
        @{ Name = "dialled-route-ignored"
           Find = 'if ($tg.value.route -ceq "dialled") { $via = $script:HordeHubDialledRoute }'
           Replace = '' }
        @{ Name = "status-written-again"
           Find = '-and ($Node -eq "" -or $Node -ceq "" + $old.deviceId)) { $rec = $old }'
           Replace = '-and ($Node -eq "" -or $Node -ceq "" + $old.deviceId)) { }' }
        @{ Name = "unknown-node-written-down"
           Find = 'if ($tg.state -cne "known") { throw ("session " + $Verb + ": " + $tg.reason) }'
           Replace = '' }
    )
}
