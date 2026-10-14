# Mutations of the bridge drawing the kept answers into the list and sending again what is missing
# (surfaces/pwa/page/bridge.js, AN ANSWER THE PC HAS NOT APPLIED STANDS ANSWERED; 2026-10-14). Applied by
# hand, one at a time:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-answer-receipts-bridge.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for every one. Every find string occurs exactly once.
# The bridge's other promises are pwa-bridge.psd1's.
@{
    Target = "surfaces\pwa\page\bridge.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "the-list-is-the-snapshot-alone"
           Find = 'questions: withAnswers(view.questions, answers),'
           Replace = 'questions: view.questions,' }
        @{ Name = "a-refresh-sends-nothing-again"
           Find = 'const again = await withSendLock(picked, (held) => phone.resend(picked, { sign: shown && held }));'
           Replace = 'const again = { problems: [] };' }
        # --- the review of PR 262
        @{ Name = "a-failed-read-empties-the-answers"
           Find = 'catch (e) { /* the answers last read stand */ }'
           Replace = 'catch (e) { answers = []; }' }
        @{ Name = "hidden-or-unlocked-the-page-still-signs"
           Find = '{ sign: shown && held }'
           Replace = '{ sign: true }' }
    )
}
