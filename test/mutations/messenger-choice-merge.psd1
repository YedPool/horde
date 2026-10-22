# Mutation of cli/Merge.ps1 for T-0336: the tell must still require receipt.receiver.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\messenger-choice-merge.psd1
# Without it, the tell finds both memory and wezfleet, never chooses, and nothing is sent.
@{
    Target = "cli\Merge.ps1"
    Suite  = "test\test-messenger-choice.ps1"
    Mutations = @(
        @{ Name = "merge-tell-drops-receipt-receiver"
           Find = '$script:HordeMergeTellNeeds = @("body.untyped", "idempotent.post", "receipt.receiver")'
           Replace = '$script:HordeMergeTellNeeds = @("body.untyped", "idempotent.post")' }
    )
}