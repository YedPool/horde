# Mutations of the PC offline banner's box in the phone app's page (surfaces/pwa/page/index.html; review
# of PR 252, 2026-10-14). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-pwa-index-presence.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one: its headless Chrome part
# (browser-signin.mjs) checks the box is never hidden, as a live region must not be. Every find string
# occurs once.
@{
    Target = "surfaces\pwa\page\index.html"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "banner-box-starts-hidden"
           Find = '<div id="pcOffline" role="status"></div>'
           Replace = '<div id="pcOffline" role="status" hidden></div>' }
        @{ Name = "banner-box-not-a-live-region"
           Find = '<div id="pcOffline" role="status"></div>'
           Replace = '<div id="pcOffline"></div>' }
    )
}
