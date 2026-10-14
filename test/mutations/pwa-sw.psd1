# Mutations of surfaces/pwa/page/sw.js, the phone app's service worker. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-sw.psd1
# surfaces\pwa\test\test-pwa-browser.ps1 (headless Chrome) must fail for each. Every find string occurs
# exactly once.
@{
    Target = "surfaces\pwa\page\sw.js"
    Suite  = "surfaces\pwa\test\test-pwa-browser.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-worker-does-not-say-its-version"
           Find = 'event.ports[0].postMessage({ version: VERSION });'
           Replace = 'event.ports[0].postMessage({ version: "" });' }
    )
}
