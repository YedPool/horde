# Mutation of cli/ServicesTell.ps1 for T-0336: the tell must still require receipt.receiver.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\messenger-choice-services.psd1
# Without it, the tell finds both memory and wezfleet, never chooses, and nothing is sent.
@{
    Target = "cli\ServicesTell.ps1"
    Suite  = "test\test-messenger-choice.ps1"
    Mutations = @(
        @{ Name = "services-tell-drops-receipt-receiver"
           Find = '$script:HordeServiceTellNeeds = @("body.untyped", "idempotent.post", "receipt.receiver")'
           Replace = '$script:HordeServiceTellNeeds = @("body.untyped", "idempotent.post")' }
    )
}