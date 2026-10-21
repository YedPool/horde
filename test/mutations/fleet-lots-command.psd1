# Mutations of the lot half of cli/commands/fleet.ps1 (T-0216). test/test-fleet-lots.ps1 must fail a check for every one. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-lots-command.psd1
@{
    Target = "cli\commands\fleet.ps1"
    Suite  = "test\test-fleet-lots.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "members-not-handed-to-the-wake"
           Find = '$wakeMembers = @(@($memberList) + @($onlyList))'
           Replace = '$wakeMembers = @($onlyList)' }
        @{ Name = "a-hibernation-id-wake-bypasses-the-lot"
           Find = 'Invoke-HordeFleetWakeLot -Lot $(if ($Lot -ne "") { $Lot } else { $Id })'
           Replace = 'Invoke-HordeFleetWake -Id $(if ($Lot -ne "") { $Lot } else { $Id })' }
    )
}
