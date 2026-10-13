# Mutations of what relay PR 8c adds to one mailbox (relays/cloudflare/worker/mailbox.js): its caps,
# refused and never evicting; retention by its alarm; one live watch per device; the account's epoch in
# its name; and its wipe when the account is deleted. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-mailbox-limits.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one, except those declared to
# survive, each with its reason. Every find string occurs once.
#
# NOT HERE, and why: clearing the alarm when an ack leaves nothing (an alarm that fires on an empty
# mailbox finds nothing to delete: it costs one wake, which no request can see); the close code after a
# watch's ending message (the message comes first and both clients act on it: the close is the second
# word, held by the close-code checks in watch-limits.mjs and the phone's units); and the tombstone's own
# end an hour later (longer than a suite should wait).
@{
    Target = "relays\cloudflare\worker\mailbox.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "items-cap-ignored"
           Find = 'if (count + 1 > limits.mailboxMaxItems) return'
           Replace = 'if (false) return' }
        @{ Name = "items-cap-off-by-one"
           Find = 'if (count + 1 > limits.mailboxMaxItems) return'
           Replace = 'if (count > limits.mailboxMaxItems) return' }
        @{ Name = "chars-cap-ignored"
           Find = 'if (chars + text.length > limits.mailboxMaxChars) return'
           Replace = 'if (false) return' }
        @{ Name = "chars-cap-off-by-one"
           Find = 'if (chars + text.length > limits.mailboxMaxChars) return'
           Replace = 'if (chars + text.length >= limits.mailboxMaxChars) return' }
        @{ Name = "size-not-kept"
           Find = '[SIZE]: { count: size.count + 1, chars: size.chars + text.length } });'
           Replace = '[SIZE]: size });' }
        @{ Name = "ack-makes-no-room"
           Find = '    await storage.put(SIZE, left);'
           Replace = '' }
        @{ Name = "retention-never-set"
           Find = 'if ((await storage.getAlarm()) === null) await storage.setAlarm(exp);'
           Replace = '' }
        @{ Name = "retention-at-the-put"
           Find = 'const exp = now + limits.retentionMs;'
           Replace = 'const exp = now;' }
        @{ Name = "alarm-deletes-what-has-not-expired"
           Find = 'if (item.exp <= now) { due.push([name, item]); continue; }'
           Replace = 'if (true) { due.push([name, item]); continue; }' }
        @{ Name = "alarm-not-moved-on"
           Find = 'if (next !== null) { await storage.setAlarm(next); return; }'
           Replace = 'if (next !== null) { return; }' }
        @{ Name = "watch-not-replaced"
           Find = 'for (const old of this.ctx.getWebSockets(device)) end(old, REPLACED, CODES.replaced, "replaced by a newer watch of this device");'
           Replace = '' }
        @{ Name = "watch-not-tagged-by-device"
           Find = 'this.ctx.acceptWebSocket(server, device !== "" ? [device] : []);'
           Replace = 'this.ctx.acceptWebSocket(server, []);' }
        @{ Name = "ended-watch-told-nothing"
           Find = 'try { ws.send(JSON.stringify({ error: words, code })); } catch (e) { /* already closed */ }'
           Replace = '' }
        @{ Name = "wipe-ends-no-watch"
           Find = 'for (const ws of this.ctx.getWebSockets()) end(ws, DELETED, CODES.gone, "the account was deleted");'
           Replace = '' }
        @{ Name = "put-not-charged"
           Find = '    if (owner) {'
           Replace = '    if (false) {' }
        @{ Name = "charge-refusal-ignored"
           Find = 'if (!charged.ok) return { ok: false, status: charged.status,'
           Replace = 'if (false) return { ok: false, status: charged.status,' }
        @{ Name = "owner-not-kept"
           Find = 'if ((await storage.get(OWNER)) === undefined) await storage.put(OWNER, owner);'
           Replace = '' }
        @{ Name = "nothing-credited"
           Find = 'if (owner && count > 0) await accountOf('
           Replace = 'if (false) await accountOf(' }
        @{ Name = "never-emptied"
           Find = 'emptied: left.count === 0,'
           Replace = 'emptied: false,' }
        @{ Name = "put-not-serialized"
           Find = 'return this.ctx.blockConcurrencyWhile(() => this.putNow(key, text, now, limits, owner, keepFrom));'
           Replace = 'return this.putNow(key, text, now, limits, owner, keepFrom);'
           Expect = "survives"
           Reason = "Only two puts to one mailbox racing while the first waits on its account's charge can interleave without it - a race no suite here places (the conformance suite's concurrent writers are the test principal, charged to no account, so nothing of theirs waits on another object)." }
        @{ Name = "name-without-the-epoch"
           Find = 'JSON.stringify([account, epoch, mailbox])'
           Replace = 'JSON.stringify([account, "", mailbox])' }
        @{ Name = "wipe-keeps-what-it-held"
           Find = 'await storage.deleteAll(); // everything the mailbox held'
           Replace = ''
           Expect = "survives"
           Reason = "What a deleted account's mailbox held is unreachable by design: the mailbox is named by the account's epoch (name-without-the-epoch, above, is caught), and the account made again has a new one. Nothing a request can do reads the old object, so only its storage bill would show the bytes left behind." }
        @{ Name = "wipe-leaves-no-tombstone"
           Find = 'await storage.put(GONE, true);'
           Replace = ''
           Expect = "survives"
           Reason = "The tombstone refuses a put that was already past the account's gate when the deletion wiped this mailbox - a race no suite can place deterministically; the suite's racing puts show only that every answer is a taken put or a refusal." }
        @{ Name = "put-to-a-deleted-mailbox-taken"
           Find = 'if (await storage.get(GONE)) return { ok: false, status: 410,'
           Replace = 'if (false) return { ok: false, status: 410,'
           Expect = "survives"
           Reason = "As wipe-leaves-no-tombstone: only a put racing the deletion reaches a wiped mailbox." }
    )
}
