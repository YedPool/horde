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
    )
}
