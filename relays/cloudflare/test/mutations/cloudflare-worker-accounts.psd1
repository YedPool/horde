# Mutations of one account's object (relays/cloudflare/worker/accounts.js, relay PR 8c): its phones and
# their cap, its machines and their cap, its pairings an hour, the gate every request passes (a device's
# rates, the account's day, the mailbox index), and its deletion. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-accounts.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one, except those declared to
# survive, each with its reason. Every find string occurs once.
#
# NOT HERE, and why: pruning a phone whose session has expired (a session lives 30 days, fixed:
# sessions.js; a suite cannot wait for one to end, and the session's own object refuses it all the
# same); a sign-in refused while a deletion is still under way (the deletion's alarm runs at once, so
# no suite can sign in between reliably); and the account's own screen and management held to the
# read bucket (the suite's devices never make that many of them in a minute); and the alarm a deletion
# sets to start its wipe (two lines, so no single find; deletion-wipes-no-mailbox below shows that harm).
@{
    Target = "relays\cloudflare\worker\accounts.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "phones-cap-ignored"
           Find = 'if (live.length >= limits.phonesPerAccount && !live.some((x) => x.id === phone.id)) return'
           Replace = 'if (false) return' }
        @{ Name = "phones-cap-off-by-one"
           Find = 'if (live.length >= limits.phonesPerAccount &&'
           Replace = 'if (live.length > limits.phonesPerAccount &&' }
        @{ Name = "sign-out-keeps-the-phone-place"
           Find = 'async signOut(phoneId) { await this.ctx.storage.delete(PHONE + phoneId); return true; }'
           Replace = 'async signOut(phoneId) { return true; }' }
        @{ Name = "epoch-the-same-every-time"
           Find = 'epoch: b64u(randomBytes(16))'
           Replace = 'epoch: "e"' }
        @{ Name = "device-rate-refusal-ignored"
           Find = 'if (!t.ok) return { ok: false, status: 429, code: CODES.rate, reason: "this " +'
           Replace = 'if (false) return { ok: false, status: 429, code: CODES.rate, reason: "this " +' }
        @{ Name = "device-rates-forgotten"
           Find = 'this.devices.set(device, put ?'
           Replace = 'this.devices.set("x" + device, put ?' }
        @{ Name = "puts-and-reads-one-bucket"
           Find = 'const t = put ? takeToken(held.put, now,'
           Replace = 'const t = put ? takeToken(held.read, now,' }
        @{ Name = "day-refusal-ignored"
           Find = 'if (!c.ok) return dailyRefusal(c);'
           Replace = 'if (false) return dailyRefusal(c);' }
        @{ Name = "day-not-counted"
           Find = 'await storage.put(DAY, { ...c.state, lease: lease - 1 });'
           Replace = '' }
        @{ Name = "day-counts-the-account-screen"
           Find = 'if (MAILBOX_OPS.has(op)) {'
           Replace = 'if (true) {' }
        @{ Name = "mailboxes-cap-ignored"
           Find = 'if (n >= limits.accountMaxMailboxes) return'
           Replace = 'if (false) return' }
        @{ Name = "mailboxes-cap-off-by-one"
           Find = 'if (n >= limits.accountMaxMailboxes) return'
           Replace = 'if (n > limits.accountMaxMailboxes) return' }
        @{ Name = "account-chars-ignored"
           Find = 'if (usage + chars > limits.accountMaxChars) return'
           Replace = 'if (false) return' }
        @{ Name = "account-chars-off-by-one"
           Find = 'if (usage + chars > limits.accountMaxChars) return'
           Replace = 'if (usage + chars >= limits.accountMaxChars) return' }
        @{ Name = "charge-not-kept"
           Find = 'await storage.put({ [BOX + mailbox]: (held || 0) + chars, [USAGE]: usage + chars, [ROOM]: limits.relayCharsLease });'
           Replace = '' }
        @{ Name = "credit-gives-nothing-back"
           Find = 'await storage.put(USAGE, left);'
           Replace = '' }
        @{ Name = "emptied-mailbox-still-counted"
           Find = 'if (emptied) await storage.delete(BOX + mailbox);'
           Replace = 'if (false) await storage.delete(BOX + mailbox);' }
        @{ Name = "pairings-not-counted"
           Find = 'await storage.put(PAIRING, t.state);'
           Replace = '' }
        @{ Name = "pairings-refusal-ignored"
           Find = 'if (!t.ok) return { ok: false, status: 429, code: CODES.rate, reason: "this account tried'
           Replace = 'if (false) return { ok: false, status: 429, code: CODES.rate, reason: "this account tried' }
        @{ Name = "machines-cap-ignored"
           Find = 'if (n >= limits.machinesPerAccount) return'
           Replace = 'if (false) return' }
        @{ Name = "machines-cap-off-by-one"
           Find = 'if (n >= limits.machinesPerAccount) return'
           Replace = 'if (n > limits.machinesPerAccount) return' }
        @{ Name = "rotation-leaves-the-old-key-listed"
           Find = '    await storage.delete(MACHINE + from);'
           Replace = '' }
        @{ Name = "phone-signed-out-keeps-its-session"
           Find = 'if (s !== null) await s.end();'
           Replace = '' }
        @{ Name = "deletion-leaves-the-sessions"
           Find = 'for (const [, ph] of phones) { const s = sessionByObjectId(this.env, ph.id); if (s) await s.end(); }'
           Replace = '' }
        @{ Name = "deletion-leaves-the-keys"
           Find = 'for (const [, m] of machines) await machineKeyOf(this.env, m.keyId).release(account);'
           Replace = '' }
        @{ Name = "deletion-wipes-no-mailbox"
           Find = 'for (const name of boxes.keys()) await mailboxOf(this.env, d.account, d.epoch, name.slice(BOX.length)).wipe();'
           Replace = '' }
        @{ Name = "deletion-stops-after-one-run"
           Find = 'if (boxes.size === WIPE_BATCH) { await storage.setAlarm(Date.now()); return; }'
           Replace = '' }
        @{ Name = "gate-lets-a-deleted-account-in"
           Find = 'if (!p || p.epoch !== epoch) return gone();'
           Replace = 'if (false) return gone();'
           Expect = "survives"
           Reason = "Defence in depth: a deletion ends every session and releases every key BEFORE a later request could reach the gate, so only a request already past its session or key when the account went meets this fence - a race no suite can place deterministically. Each of the two layers it backs is mutated above and caught (deletion-leaves-the-sessions, deletion-leaves-the-keys)." }
        @{ Name = "listing-for-a-deleted-account"
           Find = 'if (p === undefined || p.epoch !== epoch) return gone();'
           Replace = 'if (false) return gone();'
           Expect = "survives"
           Reason = "Defence in depth, as gate-lets-a-deleted-account-in: a registration reaches the listing only through chargePairing, which refuses a deleted account first; only a deletion landing between the two calls of one registration meets it." }
        @{ Name = "deletion-fence-late"
           Find = '    await storage.delete(PROFILE);'
           Replace = ''
           Expect = "survives"
           Reason = "The profile left in place is deleted moments later by the deletion's own alarm (deleteAll), and in between every session is ended and every key released, so no request can see it - but the fence must still be first, so a request racing the deletion is refused by the gate; that race is what no suite can place." }
        @{ Name = "rotation-not-heard"
           Find = 'if (Number.isSafeInteger(now)) await this.heard(entry.keyId, now);'
           Replace = '' }
    )
}
