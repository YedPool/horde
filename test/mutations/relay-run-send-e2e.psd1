# One mutation of the runner (cli/RelayRun.ps1, SENDING DURING THE WATCH, 2026-10-13), against the end
# to end: with the looking during the watch taken out - how the runner was - the real horde relay run,
# as its own process over the disk relay, must fail the phone's end-to-end scenario. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-run-send-e2e.psd1
# test\test-relay-phone-e2e.ps1 must fail for it: its step 5c writes the warchief's reply three seconds
# into a 30 s watch and allows 8 s for it to reach the phone's mailbox, and the old behaviour takes the
# rest of the watch. The same mutant is caught in half a second by test\test-relay-run-send.ps1
# (relay-run-send.psd1); it is here as well so that the suite a user's experience is measured by is
# shown to see it.
@{
    Target = "cli\RelayRun.ps1"
    Suite  = "test\test-relay-phone-e2e.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "nothing-looked-at-during-the-watch"
           Find = '-Between $script:HordeRelayRunBetweenSlices -With $watching'
           Replace = '-With $watching' }
    )
}
