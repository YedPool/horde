# Mutations of the decisions document saying what became of an answer the host is still sending
# (decisions/page/list.js, WHAT BECAME OF AN ANSWER, WHEN THE HOST KNOWS; the founder, 2026-10-14).
# Applied by hand, one at a time:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-answer-receipts-page.psd1
# surfaces\pwa\test\test-pwa-browser.ps1 must fail for every one: it is the suite with a page and the
# real machine's receipts. Every find string occurs exactly once.
# NOT HERE, and why: the mark beside an unfolded answer (markOf, refreshPart's words) - the browser
# suite sees a part only once it has folded, and the window, which sends no receipt, is unchanged by it.
@{
    Target = "decisions\page\list.js"
    Suite  = "surfaces\pwa\test\test-pwa-browser.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-folded-answer-hides-that-it-is-on-its-way"
           Find = 'return (r && r !== RECEIPT_DONE) ? WORDS.answered + ", " + r : WORDS.answered;'
           Replace = 'return WORDS.answered;' }
        @{ Name = "an-applied-answer-folds-with-a-state"
           Find = 'return (r && r !== RECEIPT_DONE) ?'
           Replace = 'return (r) ?' }
    )
}
