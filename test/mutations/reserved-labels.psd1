# Mutations of the reservation of labels. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\reserved-labels.psd1
# core/ReservedLabels.ps1 lists the labels no session may be given; test\test-agent-launch.ps1 must fail
# when the list is emptied or matched loosely.
@{
    Target = "core\ReservedLabels.ps1"
    Suite  = "test\test-agent-launch.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "nothing-reserved"
           Find = 'return @("RS", "WW")'
           Replace = 'return @()' }
        @{ Name = "the-tell-senders-label-not-reserved"
           Find = 'return @("RS", "WW")'
           Replace = 'return @("RS")' }
        @{ Name = "reserved-ignoring-case"
           Find = '(Get-HordeReservedLabels) -ccontains $Label)'
           Replace = '(Get-HordeReservedLabels) -contains $Label)' }
        @{ Name = "another-label-reserved-in-its-place"
           Find = 'return @("RS", "WW")'
           Replace = 'return @("R", "WW")' }
    )
}
