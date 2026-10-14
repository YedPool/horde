# Mutations of the phone's side of the notices (relay/js/protocol.js, the notices channel section): the
# follow switch's body, reading a notices envelope, and the list with its unread count. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-notices.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its units.mjs, section 10f). Every find string
# occurs exactly once.
@{
    Target = "relay\js\protocol.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "a-switch-takes-any-on"
           Find = 'if (on !== true && on !== false) throw new Error("on is true or false");'
           Replace = '' }
        @{ Name = "a-switch-body-has-another-shape"
           Find = 'return utf8(JSON.stringify({ v: 1, setId, machine, lane, on }));'
           Replace = 'return utf8(JSON.stringify({ v: 1, machine, setId, lane, on, at: 0 }));' }
        @{ Name = "another-machines-notices-are-read"
           Find = 'if (b.horde !== horde || b.machine !== machine) return no("the notices body names another horde or machine");'
           Replace = '' }
        @{ Name = "a-notice-of-an-unknown-kind-is-shown"
           Find = 'NOTICE_KINDS.indexOf(x.kind) >= 0 &&'
           Replace = 'true &&' }
        @{ Name = "a-switch-that-is-not-true-or-false-is-kept"
           Find = 'if (NOTICE_LANE.test(k) && (b.follows[k] === true || b.follows[k] === false)) follows[k] = b.follows[k];'
           Replace = 'follows[k] = b.follows[k];' }
        @{ Name = "a-notice-is-shown-twice"
           Find = '    if (seen.has(x.id)) continue;'
           Replace = '' }
        @{ Name = "oldest-first"
           Find = 'items.sort((a, b) => (b.said - a.said) || (b.n - a.n));'
           Replace = 'items.sort((a, b) => (a.said - b.said) || (a.n - b.n));' }
        @{ Name = "read-ones-are-counted-unread"
           Find = 'return { items, unread: items.filter((x) => !x.read).length };'
           Replace = 'return { items, unread: items.length };' }
    )
}
