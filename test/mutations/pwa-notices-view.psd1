# Mutations of the notices view and the follow switch (surfaces/pwa/page/notices-view.js). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-notices-view.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its units.mjs, section 10f). Every find string
# occurs exactly once.
@{
    Target = "surfaces\pwa\page\notices-view.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "a-tap-on-the-switch-also-opens-the-card"
           Find = 'if (e) { e.stopPropagation(); e.preventDefault(); }'
           Replace = 'if (e) { e.preventDefault(); }' }
        @{ Name = "a-tap-while-sending-sends-again"
           Find = 'if (!sending && typeof onToggle === "function") onToggle(!held);'
           Replace = 'if (typeof onToggle === "function") onToggle(!held);' }
        @{ Name = "the-switch-asks-for-what-it-holds"
           Find = 'onToggle(!held);'
           Replace = 'onToggle(held);' }
        @{ Name = "a-read-notice-is-marked-unread"
           Find = 'const box = el("button", "notice-item" + (item.read ? "" : " unread"));'
           Replace = 'const box = el("button", "notice-item unread");' }
        @{ Name = "a-notify-line-opens-a-stream"
           Find = 'if (!item || item.kind !== "progress" || !item.lane) return null;'
           Replace = 'if (!item || !item.entry) return null;' }
        @{ Name = "the-tab-count-is-hidden"
           Find = 'return "Notices" + (unread > 0 ? " (" + unread + ")" : "");'
           Replace = 'return "Notices";' }
    )
}
