# Mutations of the notices channel (channels/notices/Channel.ps1): notices out sealed with the switches the
# machine holds, the founder's switches in, the progress log followed from where it stood. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-notices.psd1
# test\test-relay-channel-notices.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "channels\notices\Channel.ps1"
    Suite  = "test\test-relay-channel-notices.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "old-entries-become-notices"
           Find = '        if (-not $fresh) { foreach ($e in @($r.entries)) { [void]$entries.Add($e.entry) } }'
           Replace = '        foreach ($e in @($r.entries)) { [void]$entries.Add($e.entry) }' }
        @{ Name = "a-replaced-log-is-read-from-its-start"
           Find = 'elseif ($marks.head -cne $D.head -or $marks.tail -cne $D.tail) { $why = "it was replaced or rewritten" }'
           Replace = 'elseif ($false) { $why = "it was replaced or rewritten" }' }
        @{ Name = "the-area-map-is-not-used"
           Find = 'foreach ($a in @($Areas)) { if ($a.area.Trim().ToLowerInvariant() -ceq $area) { return @($a.lanes) } }'
           Replace = '' }
        @{ Name = "a-switch-for-another-machine-is-taken"
           Find = 'if ($r.value.machine -cne $Context.signKeyId) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-switch-with-a-member-added-is-taken"
           Find = 'if ((@($names | Sort-Object) -join ",") -cne ($script:HordeNoticesChannelFollowMembers -join ",")) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-switches-are-not-sent"
           Find = '$front = ''{"v":1,"kind":"notices","horde":"'' + $Context.horde + ''","machine":"'' + $Context.signKeyId + ''","follows":'' + $FollowsText + '',"notices":['''
           Replace = '$front = ''{"v":1,"kind":"notices","horde":"'' + $Context.horde + ''","machine":"'' + $Context.signKeyId + ''","follows":{},"notices":[''' }
        @{ Name = "a-changed-switch-is-not-sent"
           Find = '($newOnes.Count -gt 0 -or $followsHash -cne $d.follows)'
           Replace = '($newOnes.Count -gt 0)' }
        @{ Name = "a-new-phone-gets-no-backfill"
           Find = 'if ($freshKeys.Count -gt 0) { [void]$batches.Add([pscustomobject]@{ to = $freshKeys; notices = @($all | Select-Object -Last $backfill) }) }'
           Replace = 'if ($freshKeys.Count -gt 0) { [void]$batches.Add([pscustomobject]@{ to = $freshKeys; notices = @() }) }' }
        @{ Name = "notices-pile-up-in-the-phones-mailbox"
           Find = '-KeepFrom (Get-HordeRelayChannelKeepFrom -Key $key -Keep $Keep)'
           Replace = '-KeepFrom 0' }
        @{ Name = "notices-are-sent-again"
           Find = '$newOnes = @($all | Where-Object { $_.n -gt $d.sentN })'
           Replace = '$newOnes = @($all)' }
        @{ Name = "the-glance-never-sees-a-notice"
           Find = '$changed = ($log -cne $mine.logStamp -or $fol -cne $mine.followStamp)'
           Replace = '$changed = $false' }
    )
}
