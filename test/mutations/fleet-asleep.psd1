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
        @{ Name = "unreadable-record-stalls-the-watcher"
           Find = 'if ($read.state -cne "known") { [void]$skipped.Add('
           Replace = 'if ($read.state -cne "known") { return (New-HordeUnknown -Reason "a record is unreadable"); [void]$skipped.Add(' }
        @{ Name = "unreadable-record-not-reported"
           Find = 'if ($read.state -cne "known") { [void]$skipped.Add('
           Replace = 'if ($read.state -cne "known") { $null = (' }
        @{ Name = "running-session-still-asleep"
           Find = 'if ("" + (Get-HordeFleetAsleepMember $v "state") -ceq "running") { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "unreadable-liveness-reads-as-asleep"
           Find = 'if ("" + (Get-HordeFleetAsleepMember $v "kind") -ceq "reading") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "older-record-wins"
           Find = 'Where-Object { $_ -cmatch $script:HordeFleetIdPattern } | Sort-Object)'
           Replace = 'Where-Object { $_ -cmatch $script:HordeFleetIdPattern } | Sort-Object -Descending)' }
    )
}
