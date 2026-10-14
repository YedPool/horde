# Mutations of the phone app's PC offline banner (surfaces/pwa/page/app.js, drawPresence and
# checkPresence; the founder's fix 2 of 2026-10-14). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-pwa-app-presence.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one: its headless Chrome part
# (browser-signin.mjs) is the one run of the app against a relay with accounts, where the banner lives;
# the local test transport of test-pwa-browser.ps1 has none. Every find string occurs once.
#
# The interval stays 30 s, not 60 (review of PR 252): with 60 s the banner could come up to 3 minutes
# after the PC was last heard, past the 2.5 minutes the PR states.
#
# NOT HERE, and why: the 30 s timer and the read skipped while the page is hidden (no suite waits 30 s on
# a page; a skipped read only spares the relay); the decision of offline itself is account-client.js's,
# mutated in pwa-account-client.psd1.
@{
    Target = "surfaces\pwa\page\app.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "banner-never-drawn"
           Find = 'if (m.state !== "offline") continue;'
           Replace = 'continue;' }
        @{ Name = "banner-for-every-machine"
           Find = 'if (m.state !== "offline") continue;'
           Replace = 'if (false) continue;' }
        @{ Name = "banner-box-always-shown"
           Find = 'box.hidden = lines.length === 0;'
           Replace = 'box.hidden = false;' }
        @{ Name = "account-read-does-not-refresh-the-banner"
           Find = '  presence = presenceOf(a.value);'
           Replace = '' }
        @{ Name = "no-read-at-start-up"
           Find = '  checkPresence(); // at start-up: the banner from the first moment'
           Replace = '' }
        @{ Name = "no-read-on-return"
           Find = '  checkPresence(); // back to the app: read at once, not 30 s on'
           Replace = '' }
        @{ Name = "timed-read-ignores-the-answer"
           Find = 'presence = a.state === "known" ? presenceOf(a.value) : [];'
           Replace = 'presence = [];' }
        @{ Name = "failed-read-keeps-the-banner"
           Find = 'presence = a.state === "known" ? presenceOf(a.value) : [];'
           Replace = 'presence = a.state === "known" ? presenceOf(a.value) : presence;' }
        @{ Name = "banner-redrawn-on-every-read"
           Find = 'if (key === presenceDrawn) return;'
           Replace = '' }
        @{ Name = "offline-said-as-heard"
           Find = 'heardOf.state === "offline" ? " - offline since " + dayTime(heardOf.lastSeenAt) : " - heard from "'
           Replace = 'heardOf.state === "offline" ? " - heard from " + dayTime(heardOf.lastSeenAt) : " - heard from "' }
    )
}
