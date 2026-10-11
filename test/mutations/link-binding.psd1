# Mutations of remote/LinkBinding.ps1, the binding of a dialled-in link to its enrolled device (remote
# plan R17a). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\link-binding.psd1
# test\test-link-binding.ps1 must fail for each.
@{
    Target = "remote\LinkBinding.ps1"
    Suite  = "test\test-link-binding.ps1"
    Mutations = @(
        @{ Name = "device-id-any-case"
           Find = 'return ($DeviceId -cmatch $script:HordeAttachDevicePattern)'
           Replace = 'return ($DeviceId -match $script:HordeAttachDevicePattern)' }
        @{ Name = "device-id-unanchored"
           Find = "'\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'"
           Replace = "'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'" }
        @{ Name = "preamble-made-from-anything"
           Find = 'if (-not (Test-HordeAttachDeviceId -DeviceId $DeviceId)) {'
           Replace = 'if ($false) {' }
        @{ Name = "preamble-word-not-checked"
           Find = 'if ($parts.Count -ne 3 -or $parts[0] -cne $script:HordeAttachPreambleWord) {'
           Replace = 'if ($parts.Count -ne 3) {' }
        @{ Name = "preamble-version-not-checked"
           Find = 'if ($parts[1] -cne $script:HordeAttachPreambleVersion) {'
           Replace = 'if ($false) {' }
        @{ Name = "preamble-device-not-checked"
           Find = 'if (-not (Test-HordeAttachDeviceId -DeviceId $parts[2])) {'
           Replace = 'if ($false) {' }
        @{ Name = "hello-compared-ignoring-case"
           Find = '[string]::Equals($claimed, $BoundDeviceId, [System.StringComparison]::Ordinal)'
           Replace = '[string]::Equals($claimed, $BoundDeviceId, [System.StringComparison]::OrdinalIgnoreCase)' }
        @{ Name = "hello-not-compared"
           Find = 'if (-not [string]::Equals($claimed, $BoundDeviceId, [System.StringComparison]::Ordinal)) {'
           Replace = 'if ($false) {' }
        @{ Name = "unbound-link-believed"
           Find = 'if (-not (Test-HordeAttachDeviceId -DeviceId $BoundDeviceId)) { return @("the link is bound to no device, so no hello on it can be believed") }'
           Replace = '' }
        @{ Name = "non-hello-passed"
           Find = 'if ($null -eq $hello) { return @("the frame is not a hello") }'
           Replace = '' }
    )
}
