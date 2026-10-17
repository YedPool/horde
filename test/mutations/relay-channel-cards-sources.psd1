# Mutations of the cards channel's settings (channels/cards/Sources.ps1, moved out of
# channels/cards/Channel.ps1 on 2026-10-15 so the Orc registry reads the same lanes folder). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-cards-sources.psd1
# test\test-relay-channel-cards.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "channels\cards\Sources.ps1"
    Suite  = "test\test-relay-channel-cards.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-relative-default-is-not-under-the-home"
           Find = '[System.IO.Path]::Combine($HordeHome, "progress", $Leaf)'
           Replace = '[System.IO.Path]::Combine("progress", $Leaf)' }
    )
}
