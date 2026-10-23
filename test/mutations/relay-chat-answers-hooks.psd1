# Mutations of how the chat channel hands an answer to an item of a published list to Answer.ps1 (channels/chat/Channel.ps1; T-0352). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-chat-answers-hooks.psd1
# test\test-relay-chat-answers.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "channels\chat\Channel.ps1"
    Suite  = "test\test-relay-chat-answers.ps1"
    Mutations = @(
        @{ Name = "the-channel-does-not-take-the-kind-answer"
           Find = '-Kinds @("line", "photo", "answer")'
           Replace = '-Kinds @("line", "photo")' }
        @{ Name = "an-answer-is-read-as-a-line"
           Find = 'if ("$($Item.kind)" -ceq "answer") { return (Invoke-HordeChatAnswerAccept -Context $Context -Item $Item) }'
           Replace = '' }
        @{ Name = "the-tick-never-asks-after-answers"
           Find = 'try { $answers = Invoke-HordeChatAnswerTick -Context $Context -Mine $m.mine -Settings $set.value }'
           Replace = 'try { $answers = [pscustomobject]@{ lines = @(); failed = $false } }' }
        @{ Name = "the-glance-ignores-answers"
           Find = 'if (Test-HordeChatAnswerDue -Mine $mine) { return $true }'
           Replace = '' }
    )
}
