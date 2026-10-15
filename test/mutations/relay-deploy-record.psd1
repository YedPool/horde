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
        @{ Name = "unclean-recorded-clean"
           Find = '$clean = [bool]($Revision.clean -eq $true)'
           Replace = '$clean = $true' }
        @{ Name = "failed-deploy-recorded"
           Find = '        if ($done.state -cne "known") { return $done }'
           Replace = '' }
        @{ Name = "record-without-commit-read"
           Find = '-cmatch ''\A([0-9a-f]{40})?\z'''
           Replace = '-cmatch ''\A[0-9a-f]{40}\z''' }
        @{ Name = "lock-ignored"
           Find = 'if ($null -eq $lock) { return (New-HordeUnknown -Reason $script:HordeRelayDeployBusyReason) }'
           Replace = '' }
        @{ Name = "lock-per-home"
           Find = 'return ("Global\HordeRelayDeploy-" + $Relay)'
           Replace = 'return ("Global\HordeRelayDeploy-" + $Relay + "-" + (Get-HordeHome).GetHashCode())' }
        @{ Name = "abandoned-lock-refused"
           Find = 'catch [System.Threading.AbandonedMutexException] { $got = $true }'
           Replace = 'catch [System.Threading.AbandonedMutexException] { $got = $false }' }
        @{ Name = "commit-not-recorded"
           Find = 'Write-HordeRelayDeployed -HordeHome $h -Revision $Revision -Version'
           Replace = 'Write-HordeRelayDeployed -HordeHome $h -Revision $null -Version' }
        @{ Name = "tend-home-not-recorded"
           Find = 'foreach ($h in @(@($HordeHome) + @(@($AlsoRecordIn) | Where-Object { "" + $_ -ne "" -and "" + $_ -ne $HordeHome }))) {'
           Replace = 'foreach ($h in @($HordeHome)) {' }
        @{ Name = "one-deploy-two-ids"
           Find = '-Origin $done.value.origin -At $at -Id $id }'
           Replace = '-Origin $done.value.origin -At $at -Id "" }' }
        @{ Name = "record-without-id"
           Find = 'schemaVersion = $script:HordeRelayDeployedSchemaVersion; id = $Id; commit = $commit;'
           Replace = 'schemaVersion = $script:HordeRelayDeployedSchemaVersion; commit = $commit;' }
    )
}
