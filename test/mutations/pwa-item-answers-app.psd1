# Mutations of the answer box's use in the page (surfaces/pwa/page/app.js; T-0352, review of PR 382). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-item-answers-app.psd1
# surfaces\pwa\test\test-pwa-browser.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\app.js"
    Suite  = "surfaces\pwa\test\test-pwa-browser.ps1"
    Mutations = @(
        @{ Name = "the-box-refills-with-the-words-just-sent"
           Find = 'x.problem = "";'
           Replace = 'x.problem = ""; x.text = keep;' }
        @{ Name = "the-answer-is-not-kept-across-a-reload"
           Find = 'addPending(id, { messageId: r.id, key, text, at: Date.now() });'
           Replace = '' }
    )
}
