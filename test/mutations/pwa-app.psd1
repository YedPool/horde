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
        @{ Name = "progress-tab-shows-the-questions"
           Find = 'show(PANES[pane].view);'
           Replace = 'show(pane === "chat" ? "chat" : "doc");' }
        @{ Name = "progress-no-line-where-the-new-begin"
           Find = 'if (i === progressMark + 1 && progressMark >= 0) {'
           Replace = 'if (false) {' }
        @{ Name = "progress-not-opened-at-his-place"
           Find = 'if (mark) window.scrollTo(0, Math.max(0, window.scrollY + mark.getBoundingClientRect().top - $("bar").getBoundingClientRect().bottom - 8));'
           Replace = 'if (mark) window.scrollTo(0, 0);' }
        @{ Name = "progress-jump-marks-everything-read"
           Find = 'if (!seenEntries.has(v.items[i].id)) break;'
           Replace = 'if (!seenEntries.has(v.items[i].id)) continue;' }
        @{ Name = "progress-seen-is-not-read"
           Find = 'if (upTo) bridge.request("progress-read", { id: upTo })'
           Replace = 'if (false) bridge.request("progress-read", { id: upTo })' }
        @{ Name = "progress-jump-goes-nowhere"
           Find = '$("progressNewest").addEventListener("click", () => window.scrollTo(0, document.documentElement.scrollHeight));'
           Replace = '$("progressNewest").addEventListener("click", () => window.scrollTo(0, window.scrollY));' }
        @{ Name = "progress-mark-all-marks-nothing"
           Find = 'bridge.request("progress-read", { all: true })'
           Replace = 'bridge.request("progress")' }
        @{ Name = "progress-no-count-on-the-tab"
           Find = '$("tabProgress").textContent = "Progress" + (n > 0 ? " (" + n + ")" : "");'
           Replace = '$("tabProgress").textContent = "Progress";' }
        @{ Name = "progress-left-on-a-locked-page"
           Find = 'clearChat(); clearProgress(); showProgressCount(null); clearCards(); openStamps.clear();'
           Replace = 'clearChat(); showProgressCount(null); clearCards(); openStamps.clear();' }
        @{ Name = "progress-labels-not-bold"
           Find = 'if (p.label) { const b = document.createElement("b"); b.textContent = p.label + ": "; line.appendChild(b); }'
           Replace = 'if (p.label) { line.appendChild(document.createTextNode(p.label + ": ")); }' }
        @{ Name = "progress-correction-not-drawn-on-its-entry"
           Find = 'for (const c of it.corrections) {'
           Replace = 'for (const c of []) {' }
        @{ Name = "progress-area-not-the-first-chip"
           Find = 'if (it.area) head.appendChild(chip(it.area, "area"));'
           Replace = '' }
        @{ Name = "progress-lane-and-task-not-shown"
           Find = 'if (it.lane) head.appendChild(chip("Lane " + it.lane, "lane"));'
           Replace = '' }
        @{ Name = "progress-entry-without-its-time"
           Find = 'if (stamp) head.appendChild(stamp);'
           Replace = '' }
        @{ Name = "progress-tab-not-reached-by-back"
           Find = 'pickPane(Object.prototype.hasOwnProperty.call(PANES, p) ? p : "decisions", true);'
           Replace = 'pickPane("progress", true);' }
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
        # --- one part's answer (2026-10-12) ---
        @{ Name = "the-app-sends-a-part-as-words-to-the-whole-question"
           Find = '    sayPart: (number, letter, text, wording, answerId) => inFlight(bridge.request("say", { number, text, wording, id: answerId, part: letter })),'
           Replace = '' }
        @{ Name = "new-version-reloads-on-the-first-install"
           Find = 'const had = hadController; hadController = true; tryReload(had);'
           Replace = 'hadController = true; tryReload(true);' }
        @{ Name = "new-version-reloads-over-a-chat-draft"
           Find = 'if (sending || sendsInFlight > 0 || $("chatText").value.trim() !== "") return true;'
           Replace = 'if (sending || sendsInFlight > 0) return true;' }
        @{ Name = "new-version-never-loads-after-the-draft"
           Find = 'function settleUpdate() { if (updateWaiting) tryReload(true); }'
           Replace = 'function settleUpdate() { }' }
        @{ Name = "new-version-never-reloads"
           Find = 'if (d === "reload") { reloaded = true; window.location.reload(); }'
           Replace = 'if (d === "reload") { reloaded = true; }' }
        @{ Name = "new-version-ready-not-said"
           Find = 'say("update", updateWaiting ? UPDATE_READY_WORDS : "");'
           Replace = 'say("update", "");' }
        @{ Name = "relay-notice-cleared-by-every-drawing"
           Find = '  say("view", did === "unread" ? (rec && rec.reason ? rec.reason : "") : "");'
           Replace = '  say("view", did === "unread" ? (rec && rec.reason ? rec.reason : "") : ""); say("relay", "");' }
        @{ Name = "read-banner-never-shown"
           Find = 'say("read", kind === "locked" && !$("lockedView").hidden ? "" : readBanner(kind, readLast ? readLast.lastGoodAt : 0, lastTime, readLast));'
           Replace = 'say("read", "");' }
        @{ Name = "cards-fallback-line-not-written"
           Find = '$("cardsWhy").textContent = cardsFallbackLine(v);'
           Replace = '' }
        @{ Name = "cards-fallback-line-never-shown"
           Find = '$("cardsWhy").hidden = !stream || !stream.fallback;'
           Replace = '$("cardsWhy").hidden = true;' }
        # A stream's entries folded to one line (the founder asked, 2026-10-14; test-pwa-browser section 12b).
        @{ Name = "progress-entries-start-open"
           Find = 'foldEntry(box, openEntries.has(it.id));'
           Replace = 'foldEntry(box, true);' }
        @{ Name = "progress-open-entry-folded-by-a-redraw"
           Find = 'progressDrawn = sig;'
           Replace = 'progressDrawn = sig; openEntries.clear();' }
        @{ Name = "progress-open-entry-kept-across-streams"
           Find = 'if (opening) { progressMark = v.readIndex; openEntries.clear(); }'
           Replace = 'if (opening) { progressMark = v.readIndex; }' }
        @{ Name = "progress-button-in-an-entry-folds-it"
           Find = 't.closest("button, a") || '
           Replace = '' }
        @{ Name = "progress-tap-on-text-folds-it"
           Find = ' || !t.closest(".progress-head, .progress-line")'
           Replace = '' }
        @{ Name = "progress-line-deaf-to-keys"
           Find = 'if (e.key === "Enter" || e.key === " ")'
           Replace = 'if (e.key === "Enter")' }
        @{ Name = "progress-aria-expanded-stuck"
           Find = 'setAttribute("aria-expanded", open ? "true" : "false")'
           Replace = 'setAttribute("aria-expanded", "false")' }
        @{ Name = "progress-line-not-a-control"
           Find = 'line.setAttribute("role", "button"); line.tabIndex = 0;'
           Replace = '' }
        @{ Name = "progress-folded-line-has-no-time"
           Find = 'if (when) { const w'
           Replace = 'if (false) { const w' }
    )
}
