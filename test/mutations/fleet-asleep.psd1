# Mutations of fleet/Asleep.ps1 and of the watcher's skip of a sleeping session. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-asleep.psd1
# Each breaks one rule of who the wake watcher leaves alone; test\test-fleet-hibernate.ps1 must fail a
# check for every one.
@{
    Target = "fleet\Asleep.ps1"
    Suite  = "test\test-fleet-hibernate.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "exited-not-asleep"
           Find = 'if ($state -ceq "exited") { return $true }'
           Replace = 'if ($false) { return $true }' }
        @{ Name = "unreadable-record-skipped"
           Find = 'if ($read.state -cne "known") { return (New-HordeUnknown -Reason ("which sessions are asleep cannot be told: " + $read.reason)) }'
           Replace = 'if ($read.state -cne "known") { continue }' }
        @{ Name = "older-record-wins"
           Find = 'Where-Object { $_ -cmatch $script:HordeFleetIdPattern } | Sort-Object)'
           Replace = 'Where-Object { $_ -cmatch $script:HordeFleetIdPattern } | Sort-Object -Descending)' }
    )
}
