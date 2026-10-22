# Mutations of the page drawing each Orc's published list (surfaces/pwa/page/app.js; T-0328). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-published-app.psd1
# surfaces\pwa\test\test-pwa-browser.ps1 must fail for each: it is the suite that has a page. Every find string
# occurs exactly once. The page's other promises are pwa-app.psd1's (CONTRIBUTING 15).
@{
    Target = "surfaces\pwa\page\app.js"
    Suite  = "surfaces\pwa\test\test-pwa-browser.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-lock-leaves-the-published-lists-on-the-page"
           Find = 'docs[id].pub.remove(); '
           Replace = '' }
        @{ Name = "the-lists-are-not-kept-for-the-drawing"
           Find = 'if (known) d.value = { published: rec.value.published, questions: rec.value.questions };'
           Replace = '' }
        @{ Name = "a-linked-question-keeps-its-own-recommendation"
           Find = 'questions: mergePublished(rec.value.questions, rec.value.published, laneOfQuestion) } } : rec;'
           Replace = 'questions: rec.value.questions } } : rec;' }
        @{ Name = "the-cards-are-not-given-the-published-lists"
           Find = 'published: d.value && d.value.published })) d.cards'
           Replace = 'published: null })) d.cards' }
        @{ Name = "the-document-is-not-asked-what-it-lists"
           Find = 'laneOfQuestion, (q) => d.doc.listed(q)), { fmt: lastTime }'
           Replace = 'laneOfQuestion), { fmt: lastTime }' }
        @{ Name = "the-lists-box-is-never-shown"
           Find = '  d.pub.hidden = false;'
           Replace = '  d.pub.hidden = true;' }
    )
}
