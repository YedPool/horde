# Mutations of the notice the relay run posts to the warchief when a mailbox is full
# (cli/RelayRunTell.ps1; 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-run-tell.psd1
# test\test-relay-phone-mailbox.ps1 must fail for every one. Every find string occurs exactly once.
#
# NOT HERE, and why: the device id that cannot be had and a messenger that answers a stage other than
# accepted (the suite's stand-in always accepts, as the fixture of test\test-decisions-notify.ps1 does
# when asked; decisions\Notify.ps1's own spec holds the same lines of the path this one was copied
# from), and the two-messengers case (Find-HordeMessenger's, held by test\test-messenger-port.ps1).
@{
    Target = "cli\RelayRunTell.ps1"
    Suite  = "test\test-relay-phone-mailbox.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-tests-home-tells"
           Find = 'if (Test-HordeRelayRunHomeIsATests -HordeHome $HordeHome -TempRoot $TempRoot) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "home-under-temp-not-seen"
           Find = 'return [bool]$full.StartsWith($under, [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = 'return $false' }
        @{ Name = "any-text-repeated-as-a-mailbox"
           Find = 'if ($Mailbox -cmatch $script:HordeRelayRunTellMailboxPattern) {'
           Replace = 'if ($true) {' }
        @{ Name = "notice-does-not-name-the-mailbox"
           Find = 'if ($Mailbox -cmatch $script:HordeRelayRunTellMailboxPattern) { $where = "the mailbox " + $Mailbox }'
           Replace = '' }
        @{ Name = "notice-id-the-same-for-every-fill"
           Find = '+ "`n" + $Mailbox + "`n" + $Fill))'
           Replace = '+ "`n" + $Mailbox + "`n"))' }
        @{ Name = "notice-id-the-same-for-every-mailbox"
           Find = '.ToLowerInvariant() + "`n" + $Mailbox + "`n" + $Fill'
           Replace = '.ToLowerInvariant() + "`n" + "`n" + $Fill' }
        @{ Name = "no-seat-is-told-all-the-same"
           Find = 'if ($null -eq $where -or "$($where.state)" -ceq "absent") { return (& $done $false'
           Replace = 'if ($null -eq $where -or "$($where.state)" -ceq "absent") { return (& $done $true' }
        @{ Name = "no-messenger-is-told-all-the-same"
           Find = 'if ($found.state -ceq "absent") { return (& $done $false'
           Replace = 'if ($found.state -ceq "absent") { return (& $done $true' }
        @{ Name = "notice-goes-to-no-session"
           Find = 'sessionId = "" + $where.value.sessionId'
           Replace = 'sessionId = ""' }
        @{ Name = "notice-wears-no-label"
           Find = 'sessionId = $script:HordeRelayRunTellFrom; label = $FromLabel }'
           Replace = 'sessionId = $script:HordeRelayRunTellFrom; label = "" }' }
        @{ Name = "accepted-post-without-a-reason-throws"
           Find = '(Get-HordeMessengerMember $posted.value ''reason'').value)" -clike "already-posted*"'
           Replace = '$posted.value.reason)" -clike "already-posted*"' }
    )
}
