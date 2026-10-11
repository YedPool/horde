# Mutations of cli/HubRegistry.ps1's Get-HordeHubEnrolledDevices, the one list of dialled nodes that
# `horde nodes` and `horde session` read (mesh v1, remote plan R13b). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hub-registry-devices.psd1
# test\test-hub-carry.ps1 must fail for every one.
@{
    Target = "cli\HubRegistry.ps1"
    Suite  = "test\test-hub-carry.ps1"
    Mutations = @(
        @{ Name = "devices-revoked-said-live"
           Find = 'live = ($k.state -ceq "known");'
           Replace = 'live = $true;' }
        @{ Name = "devices-address-dropped"
           Find = '{ $address = "$($e.value.address)" }'
           Replace = '{ }' }
        @{ Name = "devices-reason-dropped"
           Find = '        if ($k.state -cne "known") { $why = "$($k.reason)" }'
           Replace = '' }
    )
}
