# Mutations of the published lists on their way through the bridge to the page (surfaces/pwa/page/bridge.js; T-0328). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-published-bridge.psd1
# surfaces\pwa\test\test-pwa-site.ps1 (its units) must fail for every one. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\bridge.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-list-record-carries-no-published-lists"
           Find = 'published: Array.isArray(view.published) ? view.published : null,'
           Replace = 'published: null,' }
        @{ Name = "no-lists-read-as-an-empty-list"
           Find = 'published: Array.isArray(view.published) ? view.published : null,'
           Replace = 'published: Array.isArray(view.published) ? view.published : [],' }
    )
}
