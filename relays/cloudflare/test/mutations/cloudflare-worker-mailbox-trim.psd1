# Mutations of a mailbox's trim of a sender's stream (relays/cloudflare/worker/mailbox.js, A SENDER TRIMS
# ITS OWN STREAM; 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-mailbox-trim.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one, except those declared to
# survive, each with its reason. Every find string occurs once. That exactly the stream's older items go
# and no other's, and that no number is reused, is the conformance suite's to hold of this relay as of
# every other (test\test-relay-conformance.ps1).
#
# NOT HERE, and why: the item written BEFORE the deletes (only a kill between the two shows it, and no
# suite can place one inside a Durable Object's request).
@{
    Target = "relays\cloudflare\worker\mailbox.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "trim-never-happens"
           Find = 'const older = keepFrom > 0 ? await this.olderOf(key, keepFrom) : [];'
           Replace = 'const older = [];' }
        @{ Name = "trim-takes-the-seq-it-was-told-to-keep-from"
           Find = 'if (k && k.prefix === stream.prefix && k.seq < keepFrom) names.push(ITEM + pad(seq));'
           Replace = 'if (k && k.prefix === stream.prefix && k.seq <= keepFrom) names.push(ITEM + pad(seq));' }
        @{ Name = "full-mailbox-refuses-the-put-that-would-empty-it"
           Find = 'const count = Math.max(0, size.count - older.length);'
           Replace = 'const count = size.count;' }
        @{ Name = "freed-characters-not-counted"
           Find = 'const chars = Math.max(0, size.chars - freed);'
           Replace = 'const chars = size.chars;' }
        @{ Name = "refused-put-trims-all-the-same"
           Find = 'let freed = 0;'
           Replace = 'if (older.length > 0) await this.drop(older); let freed = 0;' }
        @{ Name = "duplicate-put-does-not-trim"
           Find = '      if (older.length > 0) await this.drop(older);'
           Replace = '' }
        @{ Name = "duplicate-put-says-nothing-of-its-trim"
           Find = 'return { ok: true, seq: held, duplicate: true, trimmed: older.length };'
           Replace = 'return { ok: true, seq: held, duplicate: true };' }
        @{ Name = "stream-read-from-every-key"
           Find = 'for (const [name, seq] of await storage.list({ prefix: KEY + stream.prefix })) {'
           Replace = 'for (const [name, seq] of await storage.list({ prefix: KEY })) {'
           Expect = "survives"
           Reason = "Each listed name is read as a key again and held to the put's own stream on the next line, so listing more names changes only how many rows are read: the prefix is there for the cost (one stream's rows, not the mailbox's), which no request can see." }
    )
}
