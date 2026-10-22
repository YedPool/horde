# Mutation of cli/RelayRunTell.ps1 for T-0336: the tell must still require receipt.receiver.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\messenger-choice-relay-run-tell.psd1
# Without it, the tell finds both memory and wezfleet, never chooses, and nothing is sent.
@{
    Target = "cli\RelayRunTell.ps1"
    Suite  = "test\test-messenger-choice.ps1"
    Mutations = @(
        @{ Name = "relay-run-tell-tell-drops-receipt-receiver"
           Find = '$script:HordeRelayRunTellNeeds = @("body.untyped", "idempotent.post", "receipt.receiver")'
           Replace = '$script:HordeRelayRunTellNeeds = @("body.untyped", "idempotent.post")' }
    )
}