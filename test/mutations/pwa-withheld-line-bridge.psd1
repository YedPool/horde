# Mutation of the bridge handing the page the line for what a snapshot leaves out
# (surfaces/pwa/page/bridge.js, listRecord's notShown; 2026-10-14). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-withheld-line-bridge.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for it. The find string occurs exactly once. The bridge's
# other promises are pwa-bridge.psd1's (a spec of its own: CONTRIBUTING 15).
@{
    Target = "surfaces\pwa\page\bridge.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "list-handed-to-the-page-without-the-line"
           Find = 'notShown: typeof view.notShown === "string" ? view.notShown : "",'
           Replace = 'notShown: "",' }
    )
}
