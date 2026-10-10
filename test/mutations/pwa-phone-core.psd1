# Mutations of surfaces/pwa/page/phone-core.js, the phone app's logic. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-phone-core.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its module checks run the built app against
# machines made in JavaScript). Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\phone-core.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "recovery-session-answers"
           Find = 'if (s.mode !== "passkey") throw fail("Read only:'
           Replace = 'if (false) throw fail("Read only:' }
        @{ Name = "stale-snapshot-drawn-after-reload"
           Find = 'if (best && best.seq < e.lastSnapshotSeq) {'
           Replace = 'if (false) {' }
        @{ Name = "sequence-not-counted-up"
           Find = 'counts[channel] = (counts[channel] || 0) + 1;'
           Replace = 'counts[channel] = 1;' }
        @{ Name = "answer-bound-to-snapshot-hash-not-page"
           Find = 'snapshot: q.pageKey, number, wordingVersion, text });'
           Replace = 'snapshot: e.machine + "/decisions/" + v.snapshot, number, wordingVersion, text });' }
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
    )
}
