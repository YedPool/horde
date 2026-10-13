# Mutations of surfaces/pwa/page/bridge.js, the page's side of the phone app's bridge. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-bridge.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\bridge.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "progress-not-pushed-with-a-refresh"
           Find = 'emit("progress-changed", await progressRecord());'
           Replace = '' }
        @{ Name = "progress-read-with-nothing-named-marks-all"
           Find = 'a.all === true ? "" : String(a.id || "-")'
           Replace = 'String(a.id || "")' }
        @{ Name = "progress-read-ignores-the-entry"
           Find = 'phone.markProgressRead(picked, a.all === true ? "" : String(a.id || "-"))'
           Replace = 'phone.markProgressRead(picked, "")' }
        @{ Name = "requests-not-a-closed-list"
           Find = 'if (REQUESTS.indexOf(name) < 0) return Promise.reject('
           Replace = 'if (!(name in handlers)) return Promise.reject(' }
        @{ Name = "saved-sequence-not-past-the-snapshot"
           Find = 'return { ok: true, sequence: highestSequence() + 1 };'
           Replace = 'return { ok: true, sequence: highestSequence() };' }
        @{ Name = "locked-list-drawn-as-empty"
           Find = 'if (!view) return { state: "unknown", value: null, reason: viewError || "This horde is locked." };'
           Replace = 'if (!view) return { state: "known", reason: "", value: { outcome: "done", questions: [], counts: {}, unreadable: [], notUnderstood: [] } };' }
        @{ Name = "chat-send-ignores-the-page-id"
           Find = 'const id = /^[0-9a-f]{32}$/.test(String(a.id || "")) ? String(a.id) : newLineId();'
           Replace = 'const id = newLineId();' }
        # --- one part's answer (2026-10-12) ---
        @{ Name = "the-bridge-drops-the-part"
           Find = 'answerId: String(a.id), part: typeof a.part === "string" ? a.part : "" });'
           Replace = 'answerId: String(a.id), part: "" });' }
        @{ Name = "the-bridge-hands-on-a-part-that-is-not-text"
           Find = 'answerId: String(a.id), part: typeof a.part === "string" ? a.part : "" });'
           Replace = 'answerId: String(a.id), part: a.part === undefined ? "" : String(a.part) });' }
    )
}
