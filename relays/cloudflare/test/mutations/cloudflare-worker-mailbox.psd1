# Mutations of one mailbox, the Durable Object (relays/cloudflare/worker/mailbox.js). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-mailbox.psd1
# Each breaks one promise of the relay port's contract, and test\test-relay-conformance.ps1 must fail
# for every one (its section for this relay, against a local dev). Every find string occurs once.
#
# NOT HERE, and why: the object's own key and text check in put (the Worker refuses the same input
# first, so no request reaches the object with it: it guards a caller the API does not have); shedding a
# socket past its time and grace (a minute and more past a watch's timeout, longer than a suite should
# wait); and the "at least one item" half of the batch budget (an item is at most 64 KiB, so a first
# item can never pass the budget alone).
@{
    Target = "relays\cloudflare\worker\mailbox.js"
    Suite  = "test\test-relay-conformance.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "duplicate-key-stored-again"
           Find = 'if (held !== undefined) {'
           Replace = 'if (false) {' }
        @{ Name = "seq-reused-after-trim"
           Find = '      await storage.put(FLOOR, through);'
           Replace = '      await storage.put({ [FLOOR]: through, [HEAD]: 0 });' }
        @{ Name = "ack-trims-nothing"
           Find = 'for (let i = 0; i < names.length; i += DELETE_BATCH) await storage.delete(names.slice(i, i + DELETE_BATCH));'
           Replace = '' }
        @{ Name = "ack-past-head-accepted"
           Find = 'if (through > head) return { ok: false, head };'
           Replace = '' }
        @{ Name = "batch-ignored"
           Find = 'end: ITEM_END, limit: max });'
           Replace = 'end: ITEM_END });' }
        @{ Name = "read-includes-the-cursor"
           Find = 'start: ITEM + pad(since + 1), end: ITEM_END'
           Replace = 'start: ITEM + pad(since), end: ITEM_END' }
        @{ Name = "watch-misses-items-already-there"
           Find = '    if (now.items.length > 0) {'
           Replace = '    if (false) {' }
        @{ Name = "put-wakes-no-watch"
           Find = '    await this.wake();'
           Replace = '' }
    )
}
