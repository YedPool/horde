# Mutations of the answer box under every item of a published list (surfaces/pwa/page/published-lists.js; T-0352). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-item-answers-page.psd1
# surfaces\pwa\test\test-pwa-site.ps1 (its units) must fail for every one. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\published-lists.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "shift-enter-sends"
           Find = 'if (e.key === "Enter" && !e.shiftKey && !e.ctrlKey && !e.altKey && !e.isComposing) { e.preventDefault(); go(); }'
           Replace = 'if (e.key === "Enter" && !e.ctrlKey && !e.altKey && !e.isComposing) { e.preventDefault(); go(); }' }
        @{ Name = "blank-words-are-sent"
           Find = 'if (busy || !text.trim()) return;'
           Replace = 'if (busy) return;' }
        @{ Name = "a-refused-send-empties-the-box"
           Find = 'else { box.value = ""; answers.onDraft(key, ""); }'
           Replace = '{ box.value = ""; answers.onDraft(key, ""); }' }
        @{ Name = "a-refused-send-says-nothing"
           Find = 'if (r && r.ok === false) problem.textContent = r.reason || "Not sent.";'
           Replace = 'if (false) problem.textContent = "";' }
        @{ Name = "read-only-draws-the-box"
           Find = 'if (!answers.canSend) return wrap;'
           Replace = '' }
        @{ Name = "a-list-with-no-id-gets-a-box"
           Find = 'const answerable = answers !== null && l.snapshot !== "";'
           Replace = 'const answerable = answers !== null;' }
        @{ Name = "the-box-is-keyed-by-its-place-in-the-shown-list"
           Find = 'export const answerKey = (list, item) => list.snapshot + "/" + item.position;'
           Replace = 'export const answerKey = (list, item) => list.snapshot + "/" + (list.items.indexOf(item) + 1);' }
        @{ Name = "the-draft-is-not-refilled"
           Find = 'box.value = answers.draftOf(key) || "";'
           Replace = 'box.value = "";' }
        @{ Name = "typing-is-not-kept"
           Find = 'box.addEventListener("input", () => answers.onDraft(key, box.value));'
           Replace = '' }
        @{ Name = "the-answer-already-sent-is-not-shown"
           Find = 'for (const a of answers.viewOf(key)) {'
           Replace = 'for (const a of []) {' }
        @{ Name = "the-list-carries-no-snapshot"
           Find = 'snapshot: l.snapshot || "", publishedAt: l.publishedAt'
           Replace = 'snapshot: "", publishedAt: l.publishedAt' }
    )
}
