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
           Find = 'call("POST", "/v1/account/machines", { horde: offer.horde, offer: offer.offer, machine: offer.machine, signPublic: offer.signPublic, expiresAt: offer.expiresAt, grant: offer.grant })'
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
    )
}
