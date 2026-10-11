# Mutations of what cli/HubRegistry.ps1's Get-HordeHubListedNodes says of each dialled node - its route,
# its expiry and its address - which `horde nodes` shows and `horde session` routes by (mesh v1, remote
# plan R13b: the register is the single source). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hub-registry-devices.psd1
# test\test-hub-carry.ps1 must fail for every one.
@{
    Target = "cli\HubRegistry.ps1"
    Suite  = "test\test-hub-carry.ps1"
    Mutations = @(
        @{ Name = "listed-dialled-not-routed"
           Find = 'deviceName = "(dialled)"; route = "dialled";'
           Replace = 'deviceName = "(dialled)"; route = "pulled";' }
        @{ Name = "listed-address-dropped"
           Find = '{ $address = "$($en.value.address)" }'
           Replace = '{ }' }
        @{ Name = "listed-expiry-dropped"
           Find = '            $expires = "$($en.value.expires)"'
           Replace = '' }
    )
}
