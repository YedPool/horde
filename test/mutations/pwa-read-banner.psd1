# Mutations of surfaces/pwa/page/read-banner.js, the banner while the relay's reads fail. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-read-banner.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its units.mjs, section 10h). Every find string
# occurs exactly once.
@{
    Target = "surfaces\pwa\page\read-banner.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "a-401-is-out-of-reach"
           Find = 'if (/ with 40[13]\b/.test(said)) return "signed-out";'
           Replace = '' }
        @{ Name = "a-signed-out-session-not-asked"
           Find = 'if (session && (session.status === 401 || session.status === 403 || (session.state === "known" && session.value && session.value.signedIn !== true))) return "signed-out";'
           Replace = '' }
        @{ Name = "a-locked-horde-not-said"
           Find = 'if (read.locked === true) return "locked";'
           Replace = '' }
        @{ Name = "a-good-read-keeps-a-banner"
           Find = 'if (read.relayDown !== true) return "";'
           Replace = '' }
        @{ Name = "no-last-updated-time"
           Find = 'return words + "." + (when ? " Last updated " + when + "." : "");'
           Replace = 'return words + ".";' }
    )
}
