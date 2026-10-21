# Mutations of the page drawing each Orc's published list (surfaces/pwa/page/app.js; T-0328). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-published-app.psd1
# surfaces\pwa\test\test-pwa-browser.ps1 must fail for each: it is the suite that has a page. Every find string
# occurs exactly once. The page's other promises are pwa-app.psd1's (CONTRIBUTING 15).
@{
    Target = "surfaces\pwa\page\app.js"
    Suite  = "surfaces\pwa\test\test-pwa-browser.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-lists-are-never-drawn-on-a-list-that-arrives"
           Find = '  drawPublishedLists(h.id);'
           Replace = '' }
        @{ Name = "the-lists-are-not-kept-for-the-drawing"
           Find = 'd.value = known ? { published: rec.value.published, questions: rec.value.questions } : null;'
           Replace = 'd.value = null;' }
        @{ Name = "a-linked-question-keeps-its-own-recommendation"
           Find = 'questions: mergePublished(rec.value.questions, rec.value.published) } } : rec;'
           Replace = 'questions: rec.value.questions } } : rec;' }
        @{ Name = "the-lists-box-is-never-shown"
           Find = '  d.pub.hidden = false;'
           Replace = '  d.pub.hidden = true;' }
    )
}
