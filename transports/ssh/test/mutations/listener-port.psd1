# Mutations of the listener port (transports/Listener.ps1): the hub's register, read by the port at
# start and again for every health check (issue #144 item 3). Run:
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\listener-port.psd1
# transports\ssh\test\test-listen.ps1 must fail for each.
@{
    Target = "transports\Listener.ps1"
    Suite  = "transports\ssh\test\test-listen.ps1"
    Mutations = @(
        @{ Name = "health-not-given-a-fresh-register"
           Find = 'try { $a = & $Running.adapter.health $Running.listener $table.value }'
           Replace = 'try { $a = & $Running.adapter.health $Running.listener @{} }' }
        @{ Name = "unreadable-register-serves"
           Find = 'if ($table.state -cne "known") { return $table }'
           Replace = '' }
        @{ Name = "start-on-unreadable-register"
           Find = 'if ($table.state -cne "known") { return (New-HordeUnknown -Reason ("the listener did not start: "'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the listener did not start: "' }
        @{ Name = "register-of-any-shape"
           Find = 'if ($t -isnot [hashtable]) {'
           Replace = 'if ($false) {' }
        @{ Name = "register-not-handed-to-start"
           Find = 'root = $Root; register = $table.value }'
           Replace = 'root = $Root; register = @{} }' }
    )
}
