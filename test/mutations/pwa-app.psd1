# Mutations of surfaces/pwa/page/app.js, the phone app's frame: the announcement made obvious and the way
# between Decisions and Chat (the founder's first live use, 2026-10-11). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-app.psd1
# surfaces\pwa\test\test-pwa-browser.ps1 (headless Chrome) must fail for every one. Every find string
# occurs once.
@{
    Target = "surfaces\pwa\page\app.js"
    Suite  = "surfaces\pwa\test\test-pwa-browser.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "no-time-on-a-message"
           Find = 'if (stamp) who.appendChild(stamp);'
           Replace = '' }
        @{ Name = "no-day-divider"
           Find = 'for (const it of withDays(v.items)) {'
           Replace = 'for (const it of v.items) {' }
        @{ Name = "touch-does-not-open-the-exact-time"
           Find = 'if (openStamps.has(key)) openStamps.delete(key); else openStamps.add(key);'
           Replace = '' }
        @{ Name = "exact-time-not-the-title"
           Find = 't.title = exact;'
           Replace = 't.title = short;' }
        @{ Name = "open-time-lost-on-redraw"
           Find = 't.setAttribute("aria-label", exact); show();'
           Replace = 't.setAttribute("aria-label", exact); t.textContent = short;' }
        @{ Name = "why-left-after-the-tick"
           Find = '$("announceWhy").hidden = $("wroteCode").checked;'
           Replace = '' }
        @{ Name = "announce-failure-only-in-the-notice"
           Find = '} catch (e) { announceSaid("announceStatus", messageOf(e)); }'
           Replace = '} catch (e) { say("action", messageOf(e)); }' }
        @{ Name = "announce-box-never-shown"
           Find = '$("announceBox").hidden = !waiting;'
           Replace = '$("announceBox").hidden = true;' }
        @{ Name = "announce-box-kept-after-a-snapshot"
           Find = 'if (rec && rec.state === "known") heard.add(h.id);'
           Replace = '' }
        @{ Name = "announce-now-sends-nothing"
           Find = 'await bridge.request("announce", { id: current });'
           Replace = 'await Promise.resolve();' }
        @{ Name = "pane-switch-not-a-history-entry"
           Find = 'if (!fromHistory && which !== pane) { try { history.pushState('
           Replace = 'if (false) { try { history.pushState(' }
        @{ Name = "back-not-followed"
           Find = 'window.addEventListener("popstate",'
           Replace = 'window.addEventListener("popstate-unheard",' }
    )
}
