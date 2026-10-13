# Mutations of what the channels' port does to keep the phone's mailbox small and to tell the run what
# a put met (channels/Port.ps1: WHAT GOES TO THE PHONE IS TRIMMED BY ITS SENDER, and WHAT A PUT TELLS
# THE RUN; 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channels-port-trim.psd1
# test\test-relay-phone-mailbox.ps1 must fail for every one. Every find string occurs exactly once. The
# port's other rules are relay-channels-port.psd1's and relay-channels-port-send.psd1's.
@{
    Target = "channels\Port.ps1"
    Suite  = "test\test-relay-phone-mailbox.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "keep-from-never-reaches-the-relay"
           Find = '-Text $Saved.text -Key $Saved.key -KeepFrom $KeepFrom'
           Replace = '-Text $Saved.text -Key $Saved.key' }
        @{ Name = "keeps-one-envelope-too-many"
           Find = 'return [long][System.Math]::Max([long]0, $named.seq - $Keep + 1)'
           Replace = 'return [long][System.Math]::Max([long]0, $named.seq - $Keep)' }
        @{ Name = "keep-under-one-trims-everything"
           Find = 'if ($null -eq $named -or $Keep -lt 1) { return [long]0 }'
           Replace = 'if ($null -eq $named) { return [long]0 }' }
        @{ Name = "full-mailbox-is-one-more-failure"
           Find = 'if ([int]$status.Value -eq 507) { $Context.full[$Mailbox] ='
           Replace = 'if ($false) { $Context.full[$Mailbox] =' }
        @{ Name = "every-refusal-is-a-full-mailbox"
           Find = 'if ([int]$status.Value -eq 507) {'
           Replace = 'if ($true) {' }
        @{ Name = "full-is-never-over"
           Find = 'if ($Context.full.ContainsKey($Mailbox)) { $Context.full.Remove($Mailbox) }'
           Replace = '' }
        @{ Name = "untrimmed-put-not-told"
           Find = 'if ($put.value.trimmed -lt 0) { $Context.untrimmed[$Mailbox] = $true }'
           Replace = 'if ($false) { $Context.untrimmed[$Mailbox] = $true }' }
        @{ Name = "untrimmed-is-never-over"
           Find = 'elseif ($Context.untrimmed.ContainsKey($Mailbox)) { $Context.untrimmed.Remove($Mailbox) }'
           Replace = '' }
        @{ Name = "reopened-context-forgets-what-the-puts-told-it"
           Find = '$made.value.full = $Context.full; $made.value.untrimmed = $Context.untrimmed'
           Replace = ''
           Expect = "survives"
           Reason = "The run's context is opened again once an hour, and no suite here waits an hour or reopens a context while a mailbox is full: what would be lost is one repeat of a line already said and, for a full mailbox, nothing - the next refused put records it again." }
    )
}
