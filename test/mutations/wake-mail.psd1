# Mutations of core/WakeMail.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-mail.psd1
# How a sender that is not a session posts mail through the messenger port. Each mutant breaks one thing
# it must hold - a held mail is not a posted one, the in-process messenger is never found by itself, no
# messenger is an answer and not a throw, the mail carries its own body and label;
# test\test-restore-source.ps1, whose poster this is, must fail for every one.
@{
    Target = "core\WakeMail.ps1"
    Suite  = "test\test-restore-source.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "held-mail-marked-posted"
           Find = 'if ($script:HordeWakeMailStages -cnotcontains "$($posted.value.stage)") {'
           Replace = 'if ($false) {' }
        @{ Name = "sender-picks-a-messenger-production-may-not"
           Find = '$script:HordeWakeMailMessengerNeeds = @("body.untyped", "idempotent.post", "receipt.receiver")'
           Replace = '$script:HordeWakeMailMessengerNeeds = @("body.untyped", "idempotent.post")' }
        @{ Name = "no-messenger-found-is-a-throw"
           Find = 'if ($found.state -cne "known") { return (New-HordeUnknown -Reason ("there is no messenger to post through: " + $found.reason)) }'
           Replace = '' }
        @{ Name = "mail-wears-no-label-of-its-own"
           Find = 'sessionId = $From; label = $Label }'
           Replace = 'sessionId = $From; label = "RS" }' }
        @{ Name = "mail-carries-another-body"
           Find = 'from = $sender; body = "$($Mail.body)";'
           Replace = 'from = $sender; body = "mail";' }
    )
}
