# Mutations of relay/js/protocol.js, the phone's side of the relay protocol, shared by the phone app
# and the test phone. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-protocol.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each: its module checks run the protocol of a
# built site against machines made in JavaScript. Every find string occurs exactly once.
#
# NOT HERE, and why: the check that an envelope's sender is the paired machine (a forged sender is
# refused by the signature check under the pinned key all the same, so dropping it is invisible -
# it is the second layer), and the strings the machine alone compares (the pairing fingerprint's
# domain, the vouch's): test\test-relay-phone-e2e.ps1 and surfaces\pwa\test\test-pwa-phone-e2e.ps1
# put those through the real machine.
@{
    Target = "relay\js\protocol.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "machine-signature-not-checked"
           Find = 'if (!verified) return no("the machine''s signature does not verify");'
           Replace = 'if (false) return no("the machine''s signature does not verify");' }
        @{ Name = "non-canonical-envelope-taken"
           Find = '"}}'' !== text) return no("not canonical, or not signed ES256");'
           Replace = '"}}'' !== text && false) return no("not canonical, or not signed ES256");' }
        @{ Name = "base64url-stray-bits-taken"
           Find = 'if (bits > 0 && (acc & ((1 << bits) - 1)) !== 0) throw'
           Replace = 'if (false) throw' }
        @{ Name = "incomplete-snapshot-drawn"
           Find = 'if (g.byNumber.size !== g.pages) continue;'
           Replace = 'if (g.byNumber.size === 0) continue;' }
        @{ Name = "older-snapshot-wins"
           Find = 'if (best && best.seq >= g.seq) continue;'
           Replace = 'if (best && best.seq <= g.seq) continue;' }
        @{ Name = "answer-members-reordered"
           Find = 'JSON.stringify({ v: 1, answerId, machine, snapshot, number, wordingVersion, text })'
           Replace = 'JSON.stringify({ v: 1, machine, answerId, snapshot, number, wordingVersion, text })' }
        @{ Name = "hpke-kem-label-wrong"
           Find = 'labeledExtract(new Uint8Array(0), KEM_ID, "eae_prk", dh)'
           Replace = 'labeledExtract(new Uint8Array(0), KEM_ID, "eae-prk", dh)' }
        @{ Name = "expired-offer-taken"
           Find = 'if (now >= o.expiresAt) return no('
           Replace = 'if (false) return no(' }
    )
}
