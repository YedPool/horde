# Mutations of the one line the phone says for what a snapshot leaves out (relay/js/protocol.js,
# withheldWords; 2026-10-14). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-withheld-line.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its module checks). Every find string occurs
# exactly once. The protocol's other rules are pwa-protocol.psd1's; that the phone and its bridge hand the
# line on is pwa-withheld-line-phone.psd1's and pwa-withheld-line-bridge.psd1's, and that the page shows
# it, pwa-withheld-line-page.psd1's, against the browser suite - specs of their own, so that a review
# round reruns these and not the ones that were there before them (CONTRIBUTING 15).
@{
    Target = "relay\js\protocol.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "shortened-list-says-nothing"
           Find = 'return out.join(" ");'
           Replace = 'return "";' }
        @{ Name = "withheld-questions-not-counted"
           Find = 'counts[at < 0 ? WITHHELD_KINDS.length : at] += 1;'
           Replace = 'counts[at < 0 ? WITHHELD_KINDS.length : at] = 1;' }
        @{ Name = "unknown-reason-read-as-one-it-knows"
           Find = 'counts[at < 0 ? WITHHELD_KINDS.length : at] += 1;'
           Replace = 'counts[at < 0 ? 0 : at] += 1;' }
        @{ Name = "machines-own-words-shown"
           Find = 'out.push(n + (n === 1 ? " question is" : " questions are") + " not shown here: " + (n === 1 ? words.one : words.many) + ".");'
           Replace = 'out.push(n + (n === 1 ? " question is" : " questions are") + " not shown here: " + list.map((w) => (w && w.reason) || "").join(" ") + ".");' }
        @{ Name = "one-and-many-said-alike"
           Find = '(n === 1 ? words.one : words.many)'
           Replace = 'words.many' }
        @{ Name = "entry-that-is-not-one-is-dropped"
           Find = 'for (const w of list) {'
           Replace = 'for (const w of list.filter((x) => x && typeof x === "object" && typeof x.reason === "string")) {' }
    )
}
