# Mutations of decisions/Console.ps1 for the verb ack: which Orc runs it is proven, never typed. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-route-console.psd1
# test\test-decisions-route.ps1 must fail for each.
@{
    Target = "decisions\Console.ps1"
    Suite  = "test\test-decisions-route.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "an-unproven-session-acks"
           Find = 'if ($null -eq $who -or -not [bool]$who.ok) { throw'
           Replace = 'if ($null -eq $who) { throw' }
        @{ Name = "a-session-that-is-no-orc-acks"
           Find = 'if ("$($who.label)" -cnotmatch ''\A[A-Z]\z'') { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "the-orc-is-typed-not-proven"
           Find = '$request["by"] = "$($who.label)"'
           Replace = '$request["by"] = "D"' }
        @{ Name = "a-bad-answer-number-taken"
           Find = 'if ($answerText -cnotmatch ''\A[1-9][0-9]{0,9}\z'') { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "an-orc-seat-is-not-proven"
           Find = 'if ($null -eq $held -or -not [bool]$held.ok) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "the-seat-found-may-be-another-session"
           Find = '-ieq "$($who.sessionId)"'
           Replace = '-ieq "$($seatFound.value.sessionId)"' }
        @{ Name = "an-ack-needs-no-answer-at-the-command-line"
           Find = 'if (-not $have.ContainsKey("Answer")) { throw'
           Replace = 'if ($false) { throw' }
    )
}
