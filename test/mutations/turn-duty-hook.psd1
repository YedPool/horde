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
           Find = 'if (now - state.lastCheckedAt < THROTTLE_MS) return 0;'
           Replace = 'if (false) return 0;' }
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
        @{ Name = "bom-not-stripped"
           Find = 'if (text.charCodeAt(0) === 0xfeff) text = text.slice(1); // PS 5.1 redirected stdin carries a BOM'
           Replace = '' }
    )
}
