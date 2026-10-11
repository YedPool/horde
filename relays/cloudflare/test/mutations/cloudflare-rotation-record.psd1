# Mutations of the retirement record as the hosted relay reads it (relay/js/protocol.js, readRetirement,
# relay PR 8c): its one canonical form, its vouch, and the bytes the vouch signs. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-rotation-record.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one (limits-units.mjs, and the
# rotation the suite carries to a local dev). Every find string occurs once.
@{
    Target = "relay\js\protocol.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "any-text-read"
           Find = 'if (!m) return no("the retirement record is not in its canonical form");'
           Replace = 'if (!m) return { ok: true, reason: "", value: { horde: "", generation: 0, signKeyId: "", successor: 1, successorSignKeyId: "", successorSignPublic: "", vouch: "", signed: utf8("") } };' }
        @{ Name = "record-without-vouch-read"
           Find = 'if (vouch === "") return no('
           Replace = 'if (false) return no(' }
        @{ Name = "successor-before-it-read"
           Find = '|| successor <= generation) return no('
           Replace = ') return no(' }
        @{ Name = "vouch-over-the-whole-record"
           Find = 'text.slice(0, text.length - vouch.length - 2) + "\"}"'
           Replace = 'text' }
        @{ Name = "vouch-without-its-domain"
           Find = 'const signed = utf8(ROTATION_VOUCH_DOMAIN + text.slice('
           Replace = 'const signed = utf8(text.slice(' }
        @{ Name = "long-text-read"
           Find = 'if (typeof text !== "string" || text.length > 16384) return no("the retirement record'
           Replace = 'if (typeof text !== "string") return no("the retirement record'
           Expect = "survives"
           Reason = "Defence in depth: the canonical form's own bounds (a vouch of at most 8192, a reason of at most 512) keep every record it reads under 16384 characters, so a longer text fails the pattern all the same; the length check only spares the pattern a long input, and the rotation route caps its body at 16384 besides." }
    )
}
