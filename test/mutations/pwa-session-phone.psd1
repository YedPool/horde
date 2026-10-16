# Mutations of surfaces/pwa/page/phone-core.js's unlocked session (THE UNLOCKED SESSION). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-session-phone.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (units.mjs section 16). Every find string occurs
# exactly once.
@{
    Target = "surfaces\pwa\page\phone-core.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "needs-passkey-question-signed-by-session"
           Find = '{ passkey: q.question.needsPasskey === true }'
           Replace = '{ passkey: false }' }
        @{ Name = "idle-limit-not-kept"
           Find = 'if (t - k.lastUsedAt >= idleOf(status)) { dropSigner(s, "session-idle"); return null; }'
           Replace = '' }
        @{ Name = "phone-keeps-a-length-of-its-own"
           Find = 'if (t - k.lastUsedAt >= idleOf(status))'
           Replace = 'if (t >= k.notAfter || t - k.lastUsedAt >= idleOf(status))' }
        @{ Name = "dead-vouch-not-dropped"
           Find = 'if (said && SESSION_DEAD.indexOf(said) >= 0) { dropSigner(s, said); return null; }'
           Replace = '' }
        @{ Name = "session-unknown-vouch-not-sent-again"
           Find = 'return !status.vouches.has(k.vouchId) || status.vouches.get(k.vouchId) === "session-unknown";'
           Replace = 'return !status.vouches.has(k.vouchId);' }
        @{ Name = "old-ts-resend-signed-by-session"
           Find = 'if (ts !== null && (!k || ts < k.notBefore))'
           Replace = 'if (ts !== null && !k)' }
        @{ Name = "end-session-keeps-key"
           Find = 'endSession(id, why) { dropSigner(sessions.get(id), why); },'
           Replace = 'endSession(id, why) { },' }
        @{ Name = "lock-keeps-key"
           Find = 'lock(id) { const s = sessions.get(id); if (s) { s.signer = null; wipe(s.pkcs8); sessions.delete(id); } },'
           Replace = 'lock(id) { const s = sessions.get(id); if (s) { wipe(s.pkcs8); } },' }
        @{ Name = "needs-passkey-answer-settled-as-refused"
           Find = 'const waiting = { ...st, state: st.state === "refused" ? "sent" : st.state };'
           Replace = 'const waiting = { ...st };' }
        @{ Name = "no-opening-envelope"
           Find = 'if (liveSigner(e, s, status) && status) await sendOpening(e, s, status);'
           Replace = '' }
    )
}
