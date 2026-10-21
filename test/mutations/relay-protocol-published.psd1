# Mutations of how the phone reads a snapshot's published lists (relay/js/protocol.js, readPublishedLists; T-0328). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-protocol-published.psd1
# surfaces\pwa\test\test-pwa-site.ps1 (its units) must fail for every one. Every find string occurs exactly once.
@{
    Target = "relay\js\protocol.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "any-lane-name-is-a-lane"
           Find = 'const PUBLISHED_LANE = /^(thrall|[A-Z][A-Z0-9]{0,3})$/;'
           Replace = 'const PUBLISHED_LANE = /^.*$/;' }
        @{ Name = "a-list-with-no-time-is-kept"
           Find = 'if (!Number.isFinite(publishedAt) || !Number.isFinite(confirmedAt)) continue;'
           Replace = '' }
        @{ Name = "any-number-of-lists-is-read"
           Find = 'for (const l of raw.slice(0, PUBLISHED_MOST_LISTS)) {'
           Replace = 'for (const l of raw) {' }
        @{ Name = "question-zero-is-a-question"
           Find = 'Number.isSafeInteger(it.question) && it.question >= 1 ? it.question : undefined'
           Replace = 'Number.isSafeInteger(it.question) && it.question >= 0 ? it.question : undefined' }
        @{ Name = "an-overlong-text-is-kept"
           Find = 'return typeof v === "string" && v.length <= PUBLISHED_MOST_TEXT && (!required || v.length > 0) ? v : undefined;'
           Replace = 'return typeof v === "string" && (!required || v.length > 0) ? v : undefined;' }
        @{ Name = "an-empty-text-is-kept"
           Find = '(!required || v.length > 0) ? v : undefined;'
           Replace = 'true ? v : undefined;' }
        @{ Name = "the-checked-time-is-the-published-time"
           Find = 'checkedAt: Math.max(publishedAt, confirmedAt)'
           Replace = 'checkedAt: publishedAt' }
        @{ Name = "no-member-reads-as-none-published"
           Find = 'if (!Array.isArray(raw)) return null;'
           Replace = 'if (!Array.isArray(raw)) return [];' }
        @{ Name = "the-snapshot-does-not-hand-the-lists-on"
           Find = 'published: readPublishedLists(first.published),'
           Replace = 'published: null,' }
    )
}
