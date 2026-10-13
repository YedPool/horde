# Mutation of the phone handing on the line for what a snapshot leaves out (surfaces/pwa/page/phone-core.js,
# notShown; 2026-10-14). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-withheld-line-phone.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for it. The find string occurs exactly once. The phone's
# other promises are pwa-phone-core.psd1's (a spec of its own: CONTRIBUTING 15).
@{
    Target = "surfaces\pwa\page\phone-core.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "phone-reads-no-withheld-list"
           Find = 'notShown: v ? P.withheldWords(v.withheld) : "",'
           Replace = 'notShown: "",' }
    )
}
