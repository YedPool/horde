# Mutations of the published lists on the decisions page (surfaces/pwa/page/published-lists.js; T-0328). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-published-lists-page.psd1
# surfaces\pwa\test\test-pwa-site.ps1 (its units) must fail for every one. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\published-lists.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-machine-that-sent-none-reads-as-none-published"
           Find = 'if (!Array.isArray(published)) return { words:'
           Replace = 'if (published === undefined) return { words:' }
        @{ Name = "a-linked-item-is-drawn-twice"
           Find = 'const items = l.items.filter((it) => it.question === null || !open.has(it.question));'
           Replace = 'const items = l.items;' }
        @{ Name = "a-closed-question-counts-as-shown"
           Find = 'if (q && Number.isSafeInteger(q.number) && q.state === "open") open.add(q.number);'
           Replace = 'if (q && Number.isSafeInteger(q.number)) open.add(q.number);' }
        @{ Name = "an-empty-list-is-not-said-to-be-empty"
           Find = 'if (l.count === 0 && l.items.length === 0) {'
           Replace = 'if (false) {' }
        @{ Name = "a-lane-that-never-published-is-not-said"
           Find = 'if (lane && chosen.length === 0) return'
           Replace = 'if (false) return' }
        @{ Name = "an-item-with-no-recommendation-blanks-the-questions"
           Find = 'if (it.question !== null && it.recommendation !== null && !rec.has(it.question))'
           Replace = 'if (it.question !== null && !rec.has(it.question))' }
        @{ Name = "a-closed-question-takes-the-recommendation"
           Find = 'rec.has(q.number) && q.state === "open" ? '
           Replace = 'rec.has(q.number) ? ' }
        @{ Name = "the-checked-time-is-the-published-time"
           Find = '" - checked " + fmt(l.checkedAt)'
           Replace = '" - checked " + fmt(l.publishedAt)' }
        @{ Name = "the-thrall-is-not-first"
           Find = 'if (a.lane === THRALL_LANE || b.lane === THRALL_LANE) return a.lane === THRALL_LANE ? -1 : 1;'
           Replace = '' }
        @{ Name = "the-recommendation-line-is-left-out"
           Find = 'if (it.recommendation !== null) row.appendChild('
           Replace = 'if (false) row.appendChild(' }
        @{ Name = "the-blocking-words-are-the-machines"
           Find = 'meta.push(BLOCKS_WORDS[it.blocks] || "blocks " + it.blocks);'
           Replace = 'meta.push("blocks " + it.blocks);' }
        @{ Name = "left-out-items-are-not-said"
           Find = 'if (l.more > 0) box.appendChild('
           Replace = 'if (false) box.appendChild(' }
    )
}
