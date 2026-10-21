# Mutations of hooks/horde-turn-duty.mjs, the turn-duty Stop hook. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\turn-duty-hook.psd1
# Each breaks one rule of when the hook blocks, how often, or how it fails; test\test-turn-duty-hook.ps1 must fail a check for every one.
@{
    Target = "hooks\horde-turn-duty.mjs"
    Suite  = "test\test-turn-duty-hook.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "stop-hook-active-ignored"
           Find = 'if (input.stop_hook_active) return 0;'
           Replace = 'if (false) return 0;' }
        @{ Name = "throttle-removed"
           Find = 'if (now - state.lastCheckedAt >= 0 && now - state.lastCheckedAt < THROTTLE_MS) return 0;'
           Replace = 'if (false) return 0;' }
        @{ Name = "future-last-checked-throttles"
           Find = 'if (now - state.lastCheckedAt >= 0 && now - state.lastCheckedAt < THROTTLE_MS) return 0;'
           Replace = 'if (now - state.lastCheckedAt < THROTTLE_MS) return 0;' }
        @{ Name = "throttle-window-changed"
           Find = 'const THROTTLE_MS = 30 * 60 * 1000;'
           Replace = 'const THROTTLE_MS = 300 * 60 * 1000;' }
        @{ Name = "fresh-window-shortened"
           Find = 'const FRESH_MS = 30 * 60 * 1000;'
           Replace = 'const FRESH_MS = 1 * 60 * 1000;' }
        @{ Name = "fresh-window-lengthened"
           Find = 'const FRESH_MS = 30 * 60 * 1000;'
           Replace = 'const FRESH_MS = 300 * 60 * 1000;' }
        @{ Name = "warg-not-excluded"
           Find = 'if (rec.role !== "orchestrator" && rec.role !== "master") return null;'
           Replace = 'if (false) return null;' }
        @{ Name = "thrall-excluded"
           Find = 'if (rec.role !== "orchestrator" && rec.role !== "master") return null;'
           Replace = 'if (rec.role !== "orchestrator") return null;' }
        @{ Name = "fail-open-turned-to-block"
           Find = 'if (!r.ok) return { state: "error", why: r.why };'
           Replace = 'if (!r.ok) return { state: "due", why: r.why };' }
        @{ Name = "bad-json-turned-to-block"
           Find = 'return { state: "error", why: "output was not JSON" };'
           Replace = 'return { state: "due", why: "output was not JSON" };' }
        @{ Name = "block-without-recording-state"
           Find = 'const saved = writeState(sid, next);'
           Replace = 'const saved = true;' }
        @{ Name = "block-when-state-unwritable"
           Find = 'if (reasons.length === 0 || !saved) return 0;'
           Replace = 'if (reasons.length === 0) return 0;' }
        @{ Name = "pass-not-recorded-for-non-fleet-session"
           Find = 'if (letter === null) { writeState(sid, { ...state, lastCheckedAt: now }); return 0; }'
           Replace = 'if (letter === null) { return 0; }' }
        @{ Name = "block-not-recorded-as-blocked"
           Find = 'lastBlockedAt: reasons.length > 0 ? now : state.lastBlockedAt'
           Replace = 'lastBlockedAt: state.lastBlockedAt' }
        @{ Name = "other-orcs-list-counts"
           Find = 'const mine = parsed.lists.filter((l) => l && l.orc === letter);'
           Replace = 'const mine = parsed.lists.filter((l) => l);' }
        @{ Name = "wrong-orc-asked-for"
           Find = '["decisions", "published", "-Orc", letter, "-Json"]'
           Replace = '["decisions", "published", "-Orc", "Q", "-Json"]' }
        @{ Name = "tasklist-check-always-on"
           Find = 'const TASKLIST_WRITER_EXISTS = false;'
           Replace = 'const TASKLIST_WRITER_EXISTS = true;' }
        @{ Name = "only-first-reason-sent"
           Find = 'reason: reasons.join("\n")'
           Replace = 'reason: reasons[0]' }
        @{ Name = "timeout-never-fires"
           Find = '}, TIMEOUT_MS);'
           Replace = '}, 600000);' }
        @{ Name = "home-not-passed-to-horde"
           Find = '{ windowsHide: true, env: { ...process.env, HORDE_HOME: home }, stdio'
           Replace = '{ windowsHide: true, stdio' }
        @{ Name = "home-env-precedence-swapped"
           Find = 'for (const v of [process.env.HORDE_TURN_DUTY_HORDE_HOME, process.env.HORDE_HOME]) {'
           Replace = 'for (const v of [process.env.HORDE_HOME, process.env.HORDE_TURN_DUTY_HORDE_HOME]) {' }
        @{ Name = "home-config-ignored"
           Find = 'const cfg = readJsonFile(join(CONFIG_DIR, "config.json"));'
           Replace = 'const cfg = null;' }
        @{ Name = "home-relative-accepted"
           Find = ' || !/^([A-Za-z]:[\\/]|\\\\[^\\])/.test(h)'
           Replace = '' }
        @{ Name = "home-line-break-accepted"
           Find = '/[\r\n]/.test(h) || '
           Replace = '' }
        @{ Name = "no-home-still-asks"
           Find = 'if (home === null) {'
           Replace = 'if (false) {' }
        @{ Name = "retired-seat-checked"
           Find = 'if (rec.retired === true || rec.retiredAt) return null;'
           Replace = 'if (false) return null;' }
        @{ Name = "reason-claims-never-published"
           Find = '"no published decisions list was found for Orc " + letter'
           Replace = '"your list was never published, Orc " + letter' }
        @{ Name = "home-apostrophe-not-doubled"
           Find = 'home.replace(/[''\u2018\u2019\u201A\u201B]/g, "$&$&")'
           Replace = 'home' }
        @{ Name = "home-curly-quote-not-doubled"
           Find = '[''\u2018\u2019\u201A\u201B]'
           Replace = '['']' }
        @{ Name = "tell-n-line-dropped"
           Find = '    "if publish refuses because fleet.db has no row for your Orc, tell N",'
           Replace = '' }
        @{ Name = "snapshot-quiet-removed"
           Find = 'now - state.lastDecisionsBlockedAt < SNAPSHOT_QUIET_MS;'
           Replace = 'false;' }
        @{ Name = "snapshot-quiet-forever"
           Find = 'now - state.lastDecisionsBlockedAt < SNAPSHOT_QUIET_MS;'
           Replace = 'true;' }
        @{ Name = "snapshot-quiet-window-shortened"
           Find = 'const SNAPSHOT_QUIET_MS = 4 * 60 * 60 * 1000;'
           Replace = 'const SNAPSHOT_QUIET_MS = 20 * 60 * 1000;' }
        @{ Name = "snapshot-quiet-window-lengthened"
           Find = 'const SNAPSHOT_QUIET_MS = 4 * 60 * 60 * 1000;'
           Replace = 'const SNAPSHOT_QUIET_MS = 24 * 60 * 60 * 1000;' }
        @{ Name = "any-snapshot-matches"
           Find = 'r.snapshot === state.lastBlockedSnapshot &&'
           Replace = '' }
        @{ Name = "empty-snapshot-matches"
           Find = 'r.snapshot !== "" && r.snapshot === state.lastBlockedSnapshot'
           Replace = 'r.snapshot === state.lastBlockedSnapshot' }
        @{ Name = "blocked-snapshot-not-recorded"
           Find = 'blockedSnapshot = r.snapshot || ""; decisionsBlockedAt = now;'
           Replace = 'decisionsBlockedAt = now;' }
        @{ Name = "snapshot-not-read-from-state"
           Find = 'lastBlockedSnapshot: snap(s.lastBlockedSnapshot) }'
           Replace = 'lastBlockedSnapshot: "" }' }
        @{ Name = "snapshot-list-field-ignored"
           Find = 'const snapshot = typeof mine[0].snapshot === "string" ? mine[0].snapshot : "";'
           Replace = 'const snapshot = "";' }
        @{ Name = "confirmed-at-ignored"
           Find = 'return confirmed === null ? published : Math.max(published, confirmed);'
           Replace = 'return published;' }
        @{ Name = "confirmed-at-wins-even-if-older"
           Find = 'return confirmed === null ? published : Math.max(published, confirmed);'
           Replace = 'return confirmed === null ? published : confirmed;' }
        @{ Name = "malformed-confirmed-at-trusted"
           Find = 'return Number.isFinite(t) && t <= now + FUTURE_SLACK_MS ? t : null;'
           Replace = 'return Number.isNaN(t) || t <= now + FUTURE_SLACK_MS ? t : null;' }
        @{ Name = "published-at-ignored"
           Find = 'if (published === null) return confirmed;'
           Replace = 'return confirmed;' }
        @{ Name = "confirmed-field-names-emptied"
           Find = 'const CONFIRMED_FIELDS = ["confirmedAt", "checkedAt", "lastConfirmedAt"];'
           Replace = 'const CONFIRMED_FIELDS = [];' }
        @{ Name = "future-time-believed"
           Find = 'Number.isFinite(t) && t <= now + FUTURE_SLACK_MS ? t : null;'
           Replace = 'Number.isFinite(t) ? t : null;' }
        @{ Name = "future-slack-widened"
           Find = 'const FUTURE_SLACK_MS = 2 * 60 * 1000;'
           Replace = 'const FUTURE_SLACK_MS = 20 * 60 * 1000;' }
        @{ Name = "future-slack-removed"
           Find = 'const FUTURE_SLACK_MS = 2 * 60 * 1000;'
           Replace = 'const FUTURE_SLACK_MS = 0;' }
        @{ Name = "loose-date-forms-accepted"
           Find = 'typeof v !== "string" || !ISO_UTC.test(v)'
           Replace = 'typeof v !== "string"' }
        @{ Name = "no-usable-time-is-fresh"
           Find = 'if (at === null) return { state: "due", why: "no usable publish time", snapshot };'
           Replace = 'if (at === null) return { state: "ok", why: "", snapshot };' }
        @{ Name = "future-block-time-counts"
           Find = 'now >= state.lastDecisionsBlockedAt && '
           Replace = '' }
        @{ Name = "quiet-window-read-from-any-block"
           Find = 'now - state.lastDecisionsBlockedAt < SNAPSHOT_QUIET_MS;'
           Replace = 'now - state.lastBlockedAt < SNAPSHOT_QUIET_MS;' }
        @{ Name = "decisions-block-time-not-recorded"
           Find = 'blockedSnapshot = r.snapshot || ""; decisionsBlockedAt = now; }'
           Replace = 'blockedSnapshot = r.snapshot || ""; }' }
        @{ Name = "decisions-block-time-not-read-from-state"
           Find = 'lastDecisionsBlockedAt: num(s.lastDecisionsBlockedAt),'
           Replace = 'lastDecisionsBlockedAt: 0,' }
        @{ Name = "snapshot-kept-when-list-fresh"
           Find = 'if (r.state === "ok" && active[i].snapshotQuiet) blockedSnapshot = "";'
           Replace = 'if (false) blockedSnapshot = "";' }
        @{ Name = "bom-not-stripped"
           Find = 'if (text.charCodeAt(0) === 0xfeff) text = text.slice(1); // PS 5.1 redirected stdin carries a BOM'
           Replace = '' }
    )
}
