# Mutations of how the relay run says what its puts met, and tells the warchief once of a full mailbox
# (cli/RelayRun.ps1, A FULL MAILBOX IS SAID PLAINLY; 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-run-full.psd1
# test\test-relay-phone-mailbox.ps1 must fail for every one. Every find string occurs exactly once. The
# loop's other promises are relay-run.psd1's and relay-run-send.psd1's.
@{
    Target = "cli\RelayRun.ps1"
    Suite  = "test\test-relay-phone-mailbox.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "warchief-told-on-every-turn"
           Find = 'if ($mine.told -or -not $Watching.tell -or $Now -lt $mine.nextTry) { continue }'
           Replace = 'if (-not $Watching.tell -or $Now -lt $mine.nextTry) { continue }' }
        @{ Name = "tell-switch-ignored"
           Find = 'if ($mine.told -or -not $Watching.tell -or $Now -lt $mine.nextTry) {'
           Replace = 'if ($mine.told -or $Now -lt $mine.nextTry) {' }
        @{ Name = "failed-notice-tried-again-at-once"
           Find = '$mine.nextTry = $Now.AddSeconds($script:HordeRelayRunTellRetrySeconds)'
           Replace = '$mine.nextTry = $Now' }
        @{ Name = "full-said-on-every-turn"
           Find = 'if (-not $notes.full.ContainsKey($box)) {'
           Replace = 'if ($true) {' }
        @{ Name = "full-never-said"
           Find = '$null = & $Watching.say ("MAILBOX FULL: the relay refuses what this machine sends to "'
           Replace = '$null = ("MAILBOX FULL: the relay refuses what this machine sends to "' }
        @{ Name = "told-claimed-when-not-posted"
           Find = 'if ($sent.told) {'
           Replace = 'if ($true) {' }
        @{ Name = "why-not-told-is-not-said"
           Find = 'if ($sent.problem -cne $mine.problem) { $mine.problem = $sent.problem; $null = & $Watching.say'
           Replace = 'if ($false) { $mine.problem = $sent.problem; $null = & $Watching.say' }
        @{ Name = "why-not-told-said-every-try"
           Find = 'if ($sent.problem -cne $mine.problem) {'
           Replace = 'if ($true) {' }
        @{ Name = "switched-off-is-not-said"
           Find = 'if (-not $Watching.tell) { $null = & $Watching.say ("the warchief is not told of it'
           Replace = 'if ($false) { $null = & $Watching.say ("the warchief is not told of it' }
        @{ Name = "mailbox-no-longer-full-is-not-said"
           Find = '$null = & $Watching.say ("the relay takes mail for " + $box + " again: it is no longer full")'
           Replace = '' }
        @{ Name = "full-again-is-not-said-again"
           Find = '        $notes.full.Remove($box)'
           Replace = '' }
        @{ Name = "untrimmed-said-on-every-look"
           Find = 'if ($notes.untrimmed.ContainsKey($box)) { continue }'
           Replace = '' }
        @{ Name = "untrimmed-never-said"
           Find = '$null = & $Watching.say ("NOT TRIMMED: the relay took what was sent to "'
           Replace = '$null = ("NOT TRIMMED: the relay took what was sent to "' }
        @{ Name = "trimmed-again-is-not-said"
           Find = '$null = & $Watching.say ("the relay now trims " + $box + " as it is asked to")'
           Replace = '' }
        @{ Name = "run-never-looks-at-what-its-puts-met"
           Find = '                Invoke-HordeRelayRunPutNotes -Context $ctx -Watching $watching'
           Replace = '' }
        @{ Name = "run-tells-with-the-setting-ignored"
           Find = '-HordeHome $HordeHome -Tell ([bool]$set.tellWarchief) -FromLabel ("" + $set.fromLabel)'
           Replace = '-HordeHome $HordeHome -Tell $true -FromLabel ("" + $set.fromLabel)'
           Expect = "survives"
           Reason = "A run started by the suite is in a home under the temp folder, which tells nobody whatever the setting says (cli/RelayRunTell.ps1, A TEST'S HOME TELLS NOBODY), so the setting cannot be seen through the run itself; that a look with tell off posts nothing and says so is held on Invoke-HordeRelayRunPutNotes directly (tell-switch-ignored, switched-off-is-not-said)." }
        @{ Name = "send-check-does-not-look-at-what-its-puts-met"
           Find = '        Invoke-HordeRelayRunPutNotes -Context $Context -Watching $Watching'
           Replace = ''
           Expect = "survives"
           Reason = "A put refused as full during a watch is said at the top of the next turn anyway, by the turn's own look (run-never-looks-at-what-its-puts-met): this line only makes it sooner by the rest of that watch, and the suite's full mailbox is met by the turn's own Tick." }
    )
}
