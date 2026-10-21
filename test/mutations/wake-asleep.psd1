# Mutations of core/Wake.ps1's skip of a session asleep in a hibernation (fleet/Asleep.ps1 says why). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-asleep.psd1
# The rest of core/Wake.ps1 is test\mutations\wake.psd1's; test\test-fleet-hibernate.ps1 must fail a
# check for every one of these.
@{
    Target = "core\Wake.ps1"
    Suite  = "test\test-fleet-hibernate.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "asleep-knocked"
           Find = 'if ($null -ne $Asleep -and $Asleep.ContainsKey("$(Get-HordeWakeEntryValue $Target "id")")) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "unknown-sleepers-knocked"
           Find = 'if ($AsleepUnknown -cne "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "asleep-mail-not-said"
           Find = 'elseif ($a.value.unreadCount -gt 0 -and $null -ne $Asleep -and $Asleep.ContainsKey("$($t.id)")) {'
           Replace = 'elseif ($false) {' }
    )
}
