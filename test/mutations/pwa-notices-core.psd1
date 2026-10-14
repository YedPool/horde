# Mutations of the phone's own handling of the notices (surfaces/pwa/page/phone-core.js, THE NOTICES): the
# switches of the newest envelope, read kept on the phone, a switch sent like an answer. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-notices-core.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its units.mjs, section 10f). Every find string
# occurs exactly once.
@{
    Target = "surfaces\pwa\page\phone-core.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "an-older-envelopes-switches-stand"
           Find = 'if (opened.header.seq > g.followsSeq) { g.follows = r.value.follows; g.followsSeq = opened.header.seq; }'
           Replace = 'g.follows = r.value.follows; g.followsSeq = opened.header.seq;' }
        @{ Name = "another-machines-notices-are-not-read"
           Find = '              if (so.ok && so.value.header.channel === "notices") { takeNotices(x.e, x.s, so.value, item, anomalies); took = true; break; }'
           Replace = '' }
        @{ Name = "a-recovery-session-sends-a-switch"
           Find = 'if (s.mode !== "passkey") throw fail(s.mode === "read-only" ? NO_PRF :'
           Replace = 'if (s.mode === "read-only") throw fail(s.mode === "read-only" ? NO_PRF :' }
        @{ Name = "a-switch-goes-to-the-picked-machine"
           Find = 'const e = await entryOf(entry);'
           Replace = 'const e = owner;' }
        @{ Name = "read-is-not-kept"
           Find = 'return { ...x, noticesRead: kept.concat(want).slice(-500) };'
           Replace = 'return { ...x };' }
    )
}
