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
           Find = 'const again = await phone.resend(picked);'
           Replace = 'const again = { problems: [] };' }
    )
}
