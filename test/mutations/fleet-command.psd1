# Mutations of cli/commands/fleet.ps1, the fleet command's wiring. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-command.psd1
# Each breaks one thing the command chooses; test\test-fleet-wake.ps1 must fail a check for every one.
@{
    Target = "cli\commands\fleet.ps1"
    Suite  = "test\test-fleet-wake.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "wake-sender-made-up-from-the-verb"
           Find = '$from = New-HordeFleetWakeSender -DeviceId (Get-HordeDeviceId) -SelfSessionId (Get-HordeSelfSessionId)'
           Replace = '$from = [pscustomobject]@{ deviceId = (Get-HordeDeviceId); sessionId = $sender }' }
        @{ Name = "wake-sender-ignores-the-running-session"
           Find = '-SelfSessionId (Get-HordeSelfSessionId)'
           Replace = '-SelfSessionId (New-HordeAbsent -Note "none")' }
    )
}
