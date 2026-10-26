# Mutations of the answer to a published item on the wire, the phone's side (relay/js/protocol.js; T-0352). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-protocol-item-answers.psd1
# surfaces\pwa\test\test-pwa-site.ps1 (its units) must fail for every one. Every find string occurs exactly once.
@{
    Target = "relay\js\protocol.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-body-may-name-a-recipient"
           Find = 'const ITEM_ANSWER_MEMBERS = ["v", "messageId", "horde", "machine", "lane", "snapshot", "index", "text"];'
           Replace = 'const ITEM_ANSWER_MEMBERS = ["v", "messageId", "horde", "machine", "lane", "snapshot", "index", "text", "to"];' }
        @{ Name = "any-snapshot-text-is-sent"
           Find = 'if (typeof snapshot !== "string" || !PUBLISHED_SNAPSHOT.test(snapshot)) throw new Error("the snapshot is the list''s id");'
           Replace = '' }
        @{ Name = "item-zero-is-sent"
           Find = 'index < 1 || index > ITEM_ANSWER_MOST_INDEX) throw new Error("the index is the item''s place, from 1");'
           Replace = 'index < 0 || index > ITEM_ANSWER_MOST_INDEX) throw new Error("the index is the item''s place, from 1");' }
        @{ Name = "a-receipt-with-a-code-off-the-list-is-shown"
           Find = 'if (!Object.prototype.hasOwnProperty.call(ITEM_ANSWER_WORDS, b.status) || !Object.prototype.hasOwnProperty.call(ITEM_ANSWER_WORDS[b.status], b.code)) return no("the answer receipt''s status or code is not one this phone knows");'
           Replace = '' }
        @{ Name = "a-receipt-of-another-machine-is-shown"
           Find = 'if (b.horde !== horde || b.machine !== machine) return no("the answer receipt names another horde or machine");'
           Replace = '' }
        @{ Name = "the-answers-under-an-item-run-newest-first"
           Find = '.sort((m, n) => m.at - n.at)) {'
           Replace = '.sort((m, n) => n.at - m.at)) {' }
        @{ Name = "an-item-is-placed-by-what-was-kept"
           Find = 'items.push({ text, recommendation, importance, blocks, question, position: at });'
           Replace = 'items.push({ text, recommendation, importance, blocks, question, position: items.length + 1 });' }
        @{ Name = "any-snapshot-text-is-a-list-id"
           Find = 'const snapshot = typeof l.snapshot === "string" && PUBLISHED_SNAPSHOT.test(l.snapshot) ? l.snapshot : "";'
           Replace = 'const snapshot = typeof l.snapshot === "string" ? l.snapshot : "";' }
    )
}
