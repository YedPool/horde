# Mutations of surfaces/pwa/page/phone-core.js, the phone app's logic. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-phone-core.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its module checks run the built app against
# machines made in JavaScript). Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\phone-core.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "progress-envelopes-not-read"
           Find = 'if (o.value.header.channel === "progress") { takeProgress(e, s, o.value, item, anomalies); continue; }'
           Replace = 'if (o.value.header.channel === "progress") { continue; }' }
        @{ Name = "progress-dropped-entries-not-said"
           Find = 'if (r.value.dropped) anomalies.push("item " + item.seq + ": " + r.value.dropped + " progress entr"'
           Replace = 'if (false) anomalies.push("item " + item.seq + ": " + r.value.dropped + " progress entr"' }
        @{ Name = "progress-place-moves-back"
           Find = 'if (index > log.readIndex) {'
           Replace = 'if (index !== log.readIndex) {' }
        @{ Name = "progress-place-moved-to-an-entry-never-sent"
           Find = 'if (entryId && index < 0) throw fail("That entry is not in the progress log this phone holds.");'
           Replace = 'if (entryId && index < 0) return { ...log, mode: s.mode };' }
        @{ Name = "progress-place-not-stored"
           Find = 'return { ...x, progressRead: read }; });'
           Replace = 'return { ...x }; });' }
        @{ Name = "progress-place-not-read-back"
           Find = 'return { ...P.progressLog({ ...s.progress, position: e.progressRead }), mode: s.mode, areas: s.cards ? s.cards.value.areas : [] };'
           Replace = 'return { ...P.progressLog({ ...s.progress, position: null }), mode: s.mode, areas: s.cards ? s.cards.value.areas : [] };' }
        @{ Name = "progress-notice-not-read"
           Find = 'g.notices.push({ ...r.value, seq: h.seq });'
           Replace = '' }
        @{ Name = "sent-line-time-not-the-signed-one"
           Find = 's.chat.sent.push({ messageId, text, at: env.ts, session: s.chat.session });'
           Replace = 's.chat.sent.push({ messageId, text, at: now() + 1, session: s.chat.session });' }
        @{ Name = "recovery-session-answers"
           Find = 'if (s.mode !== "passkey") throw fail("Read only:'
           Replace = 'if (false) throw fail("Read only:' }
        @{ Name = "stale-snapshot-drawn-after-reload"
           Find = 'if (best && best.seq < e.lastSnapshotSeq) {'
           Replace = 'if (false) {' }
        @{ Name = "sequence-not-counted-up"
           Find = 'const seq = ((held.seq && held.seq[channel]) || 0) + 1;'
           Replace = 'const seq = 1;' }
        @{ Name = "answer-bound-to-snapshot-hash-not-page"
           Find = 'snapshot: q.pageKey, number, wordingVersion, text: words,'
           Replace = 'snapshot: e.machine + "/decisions/" + v.snapshot, number, wordingVersion, text: words,' }
        # --- one part's answer (2026-10-12) ---
        @{ Name = "a-part-sent-as-version-2-to-a-machine-that-does-not-read-it"
           Find = '      const takesParts = Number(v.answers) >= 2;'
           Replace = '      const takesParts = true;' }
        @{ Name = "a-part-sent-as-words-to-a-machine-that-reads-parts"
           Find = '      const takesParts = Number(v.answers) >= 2;'
           Replace = '      const takesParts = false;' }
        @{ Name = "the-parts-letter-is-not-sent"
           Find = 'text: words, part: takesParts ? part : "" });'
           Replace = 'text: words, part: "" });' }
        @{ Name = "a-part-that-is-not-a-letter-reaches-the-passkey"
           Find = '      if (part !== "" && !/^[a-z]$/.test(part)) throw fail("the part answered is not one of the question''s parts: the answer was not sent.");'
           Replace = '' }
        @{ Name = "offer-for-another-origin-paired"
           Find = 'if (o.origins.indexOf(origin) < 0) throw fail('
           Replace = 'if (false) throw fail(' }
        @{ Name = "no-prf-session-writes-to-the-thrall"
           Find = 'if (s.mode === "read-only") { throw fail(NO_PRF); }'
           Replace = 'if (false) { throw fail(NO_PRF); }' }
        @{ Name = "recovery-session-writes-to-the-thrall"
           Find = 'if (s.mode !== "passkey") { throw fail("Read only:'
           Replace = 'if (false) { throw fail("Read only:' }
        @{ Name = "other-words-under-a-sent-id"
           Find = 'if (s.chat.sent.some((x) => x.messageId === messageId && x.text !== text)) throw fail('
           Replace = 'if (false) throw fail(' }
        @{ Name = "line-without-a-session-sent"
           Find = 'if (!s.chat.session) throw fail('
           Replace = 'if (false) throw fail(' }
        @{ Name = "no-prf-session-answers"
           Find = 'if (s.mode === "read-only") throw fail(NO_PRF);'
           Replace = 'if (false) throw fail(NO_PRF);' }
        @{ Name = "no-prf-passkey-unlocks"
           Find = 'if (!got.prfFirst) throw fail(NO_PRF);'
           Replace = 'if (false) throw fail(NO_PRF);' }
        @{ Name = "relay-numbering-backwards-not-noticed"
           Find = 'if (one && s.seen.get(one.key) !== one.seq) {'
           Replace = 'if (false) {' }
        @{ Name = "relay-words-shown"
           Find = 'if (r.state !== "known") { anomalies.push(RELAY_DOWN);'
           Replace = 'if (r.state !== "known") { anomalies.push(RELAY_DOWN + r.reason);' }
        @{ Name = "another-wording-signed"
           Find = 'if (Number(q.question.wordingVersion) !== wordingVersion) throw fail('
           Replace = 'if (false) throw fail(' }
        @{ Name = "question-not-on-screen-answered"
           Find = 'const q = v && v.questions.find((x) => x.question.number === number);'
           Replace = 'const q = v && (v.questions.find((x) => x.question.number === number) || v.questions[0]);' }
        @{ Name = "pairing-not-sent-through-the-relay"
           Find = 'const relayed = await sendSealed(id);'
           Replace = 'const relayed = false;' }
        @{ Name = "pairing-kept-after-announce"
           Find = '      pairings.delete(id);'
           Replace = '' }
        @{ Name = "machine-not-registered-before-pairing"
           Find = '      if (account) {'
           Replace = '      if (false) {' }
        @{ Name = "relay-words-on-the-screen"
           Find = 'throw fail(reg.status === 401 ? SIGN_IN_FIRST : NOT_REGISTERED);'
           Replace = 'throw fail(reg.reason);' }
        @{ Name = "refused-registration-pairs-anyway"
           Find = 'if (reg.state !== "known") { diagnostics.push(relaySaid(reg.reason)); throw'
           Replace = 'if (false) { diagnostics.push(relaySaid(reg.reason)); throw' }
        # --- the announcement the founder's first live use never sent (2026-10-11)
        @{ Name = "heard-before-any-snapshot"
           Find = 'heard: Number.isSafeInteger(e.lastSnapshotSeq) && e.lastSnapshotSeq >= 0'
           Replace = 'heard: true' }
        @{ Name = "heard-from-the-unset-seq"
           Find = '&& e.lastSnapshotSeq >= 0'
           Replace = '&& e.lastSnapshotSeq >= -1' }
        @{ Name = "passkey-refusal-in-the-browser-words"
           Find = 'catch (x) { throw fail(passkeyDidNotSign(x), "passkey"); }'
           Replace = 'catch (x) { throw x; }' }
        @{ Name = "passkey-error-name-dropped"
           Find = 'return PASSKEY_DID_NOT_SIGN + (name && name !== "Error" ? " (" + name + ")" : "");'
           Replace = 'return PASSKEY_DID_NOT_SIGN;' }
        @{ Name = "passkey-error-message-shown"
           Find = 'const name = x && typeof x.name === "string" && /^[A-Za-z]{1,40}$/.test(x.name) ? x.name : "";'
           Replace = 'const name = x ? x.name + ": " + x.message : "";' }
        @{ Name = "a-cards-envelope-of-a-lower-seq-replaces-the-held-one"
           Find = 'if (s.cards && s.cards.seq >= opened.header.seq) return;'
           Replace = '' }
        @{ Name = "another-machines-cards-not-opened-by-its-pairing"
           Find = 'if (so.ok && so.value.header.channel === "cards") { takeCards(x.e, x.s, so.value, item, anomalies); break; }'
           Replace = '' }
    )
}
