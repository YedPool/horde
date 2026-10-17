# Mutations of the phone's photos (surfaces/pwa/page/phone-core.js, THE PHOTOS; shape B, 2026-10-14).
# Applied by hand, one at a time:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-photos.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for every one. Every find string occurs exactly once.
# The shrink and the heuristic are pwa-photo-shrink.psd1's; the bytes on the wire pwa-photo-protocol.psd1's.
@{
    Target = "surfaces\pwa\page\phone-core.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "photo-sent-to-a-machine-that-offers-none"
           Find = '      if (!s.chat.photoBytes) throw fail(P.PHOTO_PC_OLD);'
           Replace = '' }
        @{ Name = "photo-not-an-image-sent"
           Find = '      if (!P.sniffImage(bytes)) throw fail(P.PHOTO_NOT_IMAGE);'
           Replace = '' }
        @{ Name = "photo-over-the-machines-size-sent"
           Find = '      if (bytes.length > s.chat.photoBytes) throw fail('
           Replace = '      if (false) throw fail(' }
        @{ Name = "photo-sent-from-the-recovery-code"
           Find = '      if (s.mode !== "passkey") { throw fail(s.mode === "read-only" ? NO_PRF : "Read only: this horde was unlocked with the recovery code, which cannot sign. Unlock with the passkey to send a photo."); }'
           Replace = '' }
        @{ Name = "photo-parts-not-paced"
           Find = '        if (puts >= PHOTO_BURST) await sleep(PHOTO_PACE_MS);'
           Replace = '' }
        @{ Name = "photo-a-tap-a-part"
           Find = '          const r = await relay.put(e.machineMailbox, p.key, p.text);'
           Replace = '          await assertWith(e)(new Uint8Array(32)); const r = await relay.put(e.machineMailbox, p.key, p.text);' }
        @{ Name = "photo-offer-not-learnt"
           Find = 'c.sessionSeq = h.seq; c.photoBytes = r.value.photoBytes; c.photoWindowMs = r.value.photoWindowMs; }'
           Replace = 'c.sessionSeq = h.seq; }' }
        @{ Name = "photo-receipts-not-read"
           Find = '      c.photoReceipts.push({ ...r.value, seq: h.seq, ts: h.ts });'
           Replace = '' }
        # THE HOUR (the founder's choice, 2026-10-16): a photo put whole waits for the PC, and past its
        # window says it was not delivered.
        @{ Name = "photo-never-marked-sent"
           Find = '      mine.sent = true;'
           Replace = '' }
        @{ Name = "photo-window-not-kept"
           Find = 'expiresAt: env.ts + windowMs, sent: false };'
           Replace = 'sent: false };' }
        # Review of PR 285: the machine's window is the photo's, and at most 3 photos wait for a word.
        @{ Name = "photo-window-ignores-the-machine"
           Find = 'const windowMs = P.photoWindowFor(s.chat.photoWindowMs);'
           Replace = 'const windowMs = P.PHOTO_WINDOW_MS;' }
        @{ Name = "photo-window-not-learnt"
           Find = 'c.photoBytes = r.value.photoBytes; c.photoWindowMs = r.value.photoWindowMs; }'
           Replace = 'c.photoBytes = r.value.photoBytes; }' }
        @{ Name = "photos-waiting-not-capped"
           Find = '      if (P.photosUnanswered(waitingOf(e, s), s.chat.photoReceipts, now()) >= P.PHOTO_MOST_UNANSWERED) throw fail(P.PHOTO_TOO_MANY_UNANSWERED);'
           Replace = '' }
        # Second review of PR 285: the cap of waiting photos is kept on the stored entry, so it survives a lock and a restart.
        @{ Name = "photos-waiting-forgotten-on-lock"
           Find = 'P.photosUnanswered(waitingOf(e, s), '
           Replace = 'P.photosUnanswered(s.chat.photos, ' }
        @{ Name = "photos-waiting-not-stored"
           Find = 'return { ...held, photosWaiting: kept.concat([{ photoId, expiresAt: mine.expiresAt }]).slice(-50) };'
           Replace = 'return held;' }
        # Review 3 of PR 285: a receipt read ends the wait for good (the stored list forgets it); a broken stored entry is not counted.
        @{ Name = "photos-waiting-kept-after-its-receipt"
           Find = '          await store.update(ENTRY + id, (x) => (x && x.photosWaiting ? { ...x, photosWaiting: x.photosWaiting.filter((w) => !gone.has(w.photoId)) } : x));'
           Replace = '' }
        @{ Name = "photos-waiting-broken-entry-counted"
           Find = 'if (w && typeof w.photoId === "string" && /^[0-9a-f]{32}$/.test(w.photoId) && Number.isSafeInteger(w.expiresAt)) byId.set('
           Replace = 'if (w) byId.set(' }
        @{ Name = "chat-read-without-the-clock"
           Find = 'items: P.chatTimeline(s.chat, now()), mode'
           Replace = 'items: P.chatTimeline(s.chat), mode' }
    )
}
