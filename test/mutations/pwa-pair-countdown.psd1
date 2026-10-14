# Mutations of surfaces/pwa/page/pair-countdown.js, the pairing code's time left on the phone (issue
# #283). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-pair-countdown.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its units.mjs, section 10i). Every find string
# occurs exactly once.
@{
    Target = "surfaces\pwa\page\pair-countdown.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "expired-said-a-moment-late"
           Find = 'if (left <= 0) return EXPIRED_WORDS;'
           Replace = 'if (left < 0) return EXPIRED_WORDS;' }
        @{ Name = "expired-never-said"
           Find = 'if (left <= 0) return EXPIRED_WORDS;'
           Replace = '' }
        @{ Name = "part-second-not-counted"
           Find = 'const s = Math.ceil(left / 1000);'
           Replace = 'const s = Math.floor(left / 1000);' }
        @{ Name = "seconds-not-padded"
           Find = '(r < 10 ? "0" : "") + r'
           Replace = 'r' }
        @{ Name = "another-record-counted"
           Find = ' || o.kind !== "horde-relay-pairing-offer"'
           Replace = '' }
    )
}
