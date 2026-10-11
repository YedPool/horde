# Mutations of cli/HubAct.ps1's choice of the node a request goes to, and of the records it writes down
# for a dialled node (mesh v1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hub-act-target.psd1
# test\test-hub-carry.ps1 must fail for every one.
@{
    Target = "cli\HubAct.ps1"
    Suite  = "test\test-hub-carry.ps1"
    Mutations = @(
        @{ Name = "target-revoked-accepted"
           Find = 'if (-not $h.live) {'
           Replace = 'if ($false) {' }
        @{ Name = "target-two-picks-one"
           Find = 'if ($hits.Count -gt 1) { return (New-HordeUnknown -Reason ("''" + $Target'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("''" + $Target' }
        @{ Name = "target-name-any-case"
           Find = '$_.deviceName -ne "" -and $_.deviceName -ceq $Target'
           Replace = '$_.deviceName -ne "" -and $_.deviceName -eq $Target' }
        @{ Name = "target-unnamed-matches-empty"
           Find = '($_.deviceName -ne "" -and $_.deviceName -ceq $Target)'
           Replace = '($_.deviceName -ceq $Target)' }
        @{ Name = "record-not-marked-dialled"
           Find = '    if ($Via -ne "") { $rec | Add-Member -NotePropertyName via -NotePropertyValue $Via }'
           Replace = '' }
        @{ Name = "close-expects-another-process"
           Find = 'pid = [long]$ex.pid; procStart = "" + $ex.procStart }; reason = $Reason }'
           Replace = 'pid = [long]$ex.pid + 1; procStart = "" + $ex.procStart }; reason = $Reason }' }
    )
}
