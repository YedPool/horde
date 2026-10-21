# Mutations of the published lists in the phone core's refresh (surfaces/pwa/page/phone-core.js; T-0328). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-published-core.psd1
# surfaces\pwa\test\test-pwa-site.ps1 (its units) must fail for every one. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\phone-core.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-refresh-hands-on-no-lists"
           Find = 'published: v ? v.published : null,'
           Replace = 'published: null,' }
    )
}
