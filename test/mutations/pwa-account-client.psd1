# Mutations of surfaces/pwa/page/account-client.js, the phone app's side of the relay's accounts (relay
# PR 8b). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-account-client.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its module checks run the built app's client
# against a fake fetch). Every find string occurs exactly once.
#
# NOT HERE, and why: no-store and the JSON content type on a request (a fake fetch cannot tell what a
# cache would have done); both are held against the real Worker by the hosted relay's accounts suite.
@{
    Target = "surfaces\pwa\page\account-client.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "registration-carries-the-whole-offer"
           Find = 'call("POST", "/v1/account/machines", { horde: offer.horde, offer: offer.offer, machine: offer.machine, label: offer.label, signPublic: offer.signPublic, expiresAt: offer.expiresAt, grant: offer.grant })'
           Replace = 'call("POST", "/v1/account/machines", offer)' }
        @{ Name = "any-removal-sent"
           Find = '(/^[0-9a-f]{32}$/.test(String(keyId)) ? call('
           Replace = '(true ? call(' }
        @{ Name = "redirects-followed"
           Find = 'method, credentials: "same-origin", cache: "no-store", redirect: "error",'
           Replace = 'method, credentials: "same-origin", cache: "no-store", redirect: "follow",' }
        @{ Name = "accounts-at-another-origin"
           Find = 'if (!config || config.transport !== "http" || config.relayOrigin ||'
           Replace = 'if (!config || config.transport !== "http" ||' }
        @{ Name = "relay-words-uncut"
           Find = 'j.error.slice(0, 200)'
           Replace = 'j.error' }
        @{ Name = "any-phone-sign-out-sent"
           Find = '(/^[0-9a-f]{64}$/.test(String(phoneId)) ?'
           Replace = '(true ?' }
        @{ Name = "deletion-sent-without-its-words"
           Find = 'call("DELETE", "/v1/account", { confirm: DELETE_CONFIRM })'
           Replace = 'call("DELETE", "/v1/account", {})' }
        @{ Name = "offline-at-two-minutes-exactly"
           Find = 'answer.now - seen > OFFLINE_AFTER_MS ? "offline"'
           Replace = 'answer.now - seen >= OFFLINE_AFTER_MS ? "offline"' }
        @{ Name = "offline-by-the-phones-clock"
           Find = 'answer.now - seen > OFFLINE_AFTER_MS ? "offline"'
           Replace = 'Date.now() - seen > OFFLINE_AFTER_MS ? "offline"' }
        @{ Name = "never-heard-is-offline"
           Find = 'const state = seen === null ? "never" :'
           Replace = 'const state = seen === null ? "offline" :' }
        @{ Name = "judged-without-the-relays-now"
           Find = 'if (!answer || !Number.isSafeInteger(answer.now) || !Array.isArray(answer.machines)) return [];'
           Replace = 'if (!answer || !Array.isArray(answer.machines)) return [];' }
        @{ Name = "banner-without-the-horde"
           Find = '"machine " + m.keyId.slice(0, 12)) + (typeof m.horde === "string" && m.horde ? " (" + m.horde + ")" : "");'
           Replace = '"machine " + m.keyId.slice(0, 12));' }
        @{ Name = "missing-horde-shown-as-undefined"
           Find = '(typeof m.horde === "string" && m.horde ? " (" + m.horde + ")" : "")'
           Replace = '(" (" + String(m.horde) + ")")' }
        @{ Name = "banner-does-not-say-kept"
           Find = '". Your answers are kept and will be applied when it is back."'
           Replace = '". Your answers could not be sent."' }
        @{ Name = "waiting-hook-says-zero"
           Find = 'Number.isSafeInteger(options.waiting) && options.waiting > 0 ?'
           Replace = 'Number.isSafeInteger(options.waiting) && options.waiting >= 0 ?' }
        @{ Name = "no-reserve-never-said"
           Find = 'r.reserve === false ? NO_RESERVE_WORDS : ""'
           Replace = '""' }
        @{ Name = "no-reserve-said-always"
           Find = 'return r && typeof r === "object" && r.reserve === false'
           Replace = 'return true || r && typeof r === "object" && r.reserve === false' }
    )
}
