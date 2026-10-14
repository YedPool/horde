# Mutations of cli/RelayDeploy.ps1's lock and record: one deploy at a time, and what was deployed
# written down for the supervisor (cli/RelayPublish.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-deploy-record.psd1
# test\test-relay-publish.ps1 must fail for every one. (The command's other promises are the hosted
# relay's own deploy spec's, in that relay's folder.)
@{
    Target = "cli\RelayDeploy.ps1"
    Suite  = "test\test-relay-publish.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "lock-ignored"
           Find = 'if ($null -eq $lock) { return (New-HordeUnknown -Reason $script:HordeRelayDeployBusyReason) }'
           Replace = 'if ($null -eq $lock) { $lock = New-Object System.IO.MemoryStream }' }
        @{ Name = "lock-shared"
           Find = '([System.IO.FileAccess]::ReadWrite), ([System.IO.FileShare]::None)) }'
           Replace = '([System.IO.FileAccess]::ReadWrite), ([System.IO.FileShare]::ReadWrite)) }' }
        @{ Name = "commit-not-recorded"
           Find = 'Write-HordeRelayDeployed -HordeHome $HordeHome -Revision $Revision -Version'
           Replace = 'Write-HordeRelayDeployed -HordeHome $HordeHome -Revision $null -Version' }
        @{ Name = "unclean-recorded-clean"
           Find = '$clean = [bool]($Revision.clean -eq $true)'
           Replace = '$clean = $true' }
        @{ Name = "failed-deploy-recorded"
           Find = '        if ($done.state -cne "known") { return $done }'
           Replace = '' }
        @{ Name = "record-without-commit-read"
           Find = '-cmatch ''\A([0-9a-f]{40})?\z'''
           Replace = '-cmatch ''\A[0-9a-f]{40}\z''' }
    )
}
