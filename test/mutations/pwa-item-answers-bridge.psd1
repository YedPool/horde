# Mutations of the answer to a published item on its way through the bridge (surfaces/pwa/page/bridge.js; T-0352). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-item-answers-bridge.psd1
# surfaces\pwa\test\test-pwa-site.ps1 (its units) must fail for every one. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\bridge.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "answer-item-ignores-the-page-id"
           Find = 'index: Number(a.index), text: String(a.text || ""), messageId: id });'
           Replace = 'index: Number(a.index), text: String(a.text || ""), messageId: newLineId() });' }
        @{ Name = "the-list-record-carries-no-item-answers"
           Find = 'itemAnswers: Array.isArray(view.itemAnswers) ? view.itemAnswers : [],'
           Replace = 'itemAnswers: [],' }
        @{ Name = "a-sent-answer-is-not-drawn-at-once"
           Find = 'if (view) view = { ...view, itemAnswers: phone.itemAnswers(picked) };'
           Replace = '' }
        @{ Name = "answer-item-is-not-a-request"
           Find = '"chat-send", "answer-item", "chat-photo",'
           Replace = '"chat-send", "chat-photo",' }
    )
}
