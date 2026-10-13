# Mutations of how the decisions channel keeps the phone's mailbox to one snapshot, and sends a phone
# paired later the snapshot it could not open (channels/decisions/Channel.ps1, THE SNAPSHOT BEFORE IS
# DEAD WEIGHT; 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-decisions-trim.psd1
# test\test-relay-phone-mailbox.ps1 must fail for every one. Every find string occurs exactly once. The
# channel's other promises are relay-channel-decisions.psd1's, against test\test-relay-channels.ps1.
@{
    Target = "channels\decisions\Channel.ps1"
    Suite  = "test\test-relay-phone-mailbox.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "snapshots-pile-up"
           Find = '$put = Send-HordeRelayChannelSaved -Context $Context -Saved $p -Mailbox $p.mailbox -KeepFrom $from'
           Replace = '$put = Send-HordeRelayChannelSaved -Context $Context -Saved $p -Mailbox $p.mailbox' }
        @{ Name = "every-page-trims-the-snapshot-before"
           Find = 'if ($null -ne $lastPage) { $lastPage | Add-Member -NotePropertyName "keepFrom" -NotePropertyValue $firstSeq }'
           Replace = 'foreach ($page in @($mine.pending)) { if ($null -eq $page.PSObject.Properties["keepFrom"]) { $page | Add-Member -NotePropertyName "keepFrom" -NotePropertyValue $firstSeq } }' }
        @{ Name = "last-page-trims-its-own-snapshots-pages"
           Find = '$lastPage | Add-Member -NotePropertyName "keepFrom" -NotePropertyValue $firstSeq }'
           Replace = '$lastPage | Add-Member -NotePropertyName "keepFrom" -NotePropertyValue ([long]$lastPage.seq) }' }
        @{ Name = "first-page-is-the-last-recorded"
           Find = 'if ($firstSeq -eq 0) { $firstSeq = [long]$saved.value.seq }'
           Replace = '$firstSeq = [long]$saved.value.seq' }
        @{ Name = "phone-paired-later-is-sent-nothing"
           Find = '$sentAs = $pages.hash + "|" + (@($keys | ForEach-Object { $_.agreeKeyId }) -join ",")'
           Replace = '$sentAs = $pages.hash' }
        # --- every other page keeps from the last snapshot the relay wholly took (review of PR 232)
        @{ Name = "other-pages-ask-for-nothing"
           Find = '$from = [long]$Mine.whole'
           Replace = '$from = [long]0' }
        @{ Name = "memory-past-the-pages-own-seq-is-sent"
           Find = 'if ($from -gt [long]$p.seq) { $from = [long]0 }'
           Replace = '' }
        @{ Name = "whole-snapshot-not-remembered"
           Find = '$Mine.whole = [long]$p.keepFrom'
           Replace = '$Mine.whole = [long]0' }
        @{ Name = "memory-not-kept-for-the-next-run"
           Find = '$Mine.wholeProblem = Write-HordeDecisionsChannelWhole -Context $Context -Whole $Mine.whole'
           Replace = '$Mine.wholeProblem = ""' }
        @{ Name = "another-keys-memory-is-used"
           Find = 'if ($m.Success -and $m.Groups[1].Value -ceq $Context.signKeyId) {'
           Replace = 'if ($m.Success) {' }
        # --- a full mailbox is emptied by one page sent first
        @{ Name = "full-mailbox-is-never-rescued"
           Find = 'if (-not $Mine.stuckFull -or $Mine.onePageSent) { return $false }'
           Replace = 'if ($true) { return $false }' }
        @{ Name = "one-page-first-for-any-refusal"
           Find = '$Mine.stuckFull = (-not $isLast -and $null -ne $status -and [int]$status.Value -eq 507)'
           Replace = '$Mine.stuckFull = (-not $isLast -and $null -ne $status)' }
        @{ Name = "one-page-first-when-the-last-page-is-refused"
           Find = '$Mine.stuckFull = (-not $isLast -and $null -ne $status -and'
           Replace = '$Mine.stuckFull = ($null -ne $status -and' }
        @{ Name = "the-one-page-is-every-page"
           Find = '-List $list.value -Budget $budget -OnePage:$onePage'
           Replace = '-List $list.value -Budget $budget' }
        @{ Name = "whole-snapshot-never-follows-the-one-page"
           Find = 'if ($onePage) { $mine.fingerprint = "one page"; $mine.onePageNext'
           Replace = 'if ($onePage) { $mine.onePageNext' }
        @{ Name = "one-page-does-not-say-what-it-leaves-out"
           Find = '[void]$withheld.Add([ordered]@{ number = $s.number; reason = "it is in the snapshot that follows'
           Replace = '$null = ([ordered]@{ number = $s.number; reason = "it is in the snapshot that follows' }
        @{ Name = "one-page-takes-a-later-question-in-place-of-one-that-did-not-fit"
           Find = 'if (-not $cut -and ($onOne.Count -eq 0 -or'
           Replace = 'if (($onOne.Count -eq 0 -or'
           Expect = "survives"
           Reason = "The suite's questions that do not fit the one page are all of one size, so none further down fits where an earlier one did not: the order is kept for the founder's reading (a later question shown above a withheld earlier one), and it changes nothing a count can see here." }
    )
}
