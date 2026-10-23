# Mutations of hooks/horde-work-unit.mjs, the SubagentStart / SubagentStop / SessionEnd hook that records agents and wargs
# in fleet.db (T-0326). Each breaks one rule of what is recorded or how the hook fails; test\test-work-unit-hook.ps1 must fail
# a check for every one. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\work-unit-hook.psd1
@{
    Target = "hooks\horde-work-unit.mjs"
    Suite  = "test\test-work-unit-hook.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "task-read-from-any-line"
           Find = 'const first = brief.split(/\r?\n/).find((l) => l.trim() !== "");'
           Replace = 'const first = brief;' }
        @{ Name = "work-type-guessed-from-words"
           Find = 'return agentType === "Explore" || agentType === "Plan" ? "research" : "other";'
           Replace = 'return /review/i.test(String(brief)) ? "review" : (agentType === "Explore" || agentType === "Plan" ? "research" : "other");' }
        @{ Name = "marker-read-past-line-three"
           Find = '.slice(0, 3)) {'
           Replace = '.slice(0, 9)) {' }
        @{ Name = "agent-id-lowercased"
           Find = 'const argv = ["start", "--kind", "agent", "--parent-session", parent, "--agent-id", agentId,'
           Replace = 'const argv = ["start", "--kind", "agent", "--parent-session", parent, "--agent-id", String(agentId).toLowerCase(),' }
        @{ Name = "stop-does-not-end"
           Find = 'if (stopping) await runWork(["end",'
           Replace = 'if (false) await runWork(["end",' }
        @{ Name = "stop-does-not-read-brief"
           Find = 'if (stopping || await waitFor(file)) brief = briefOf(file);'
           Replace = 'if (!stopping && await waitFor(file)) brief = briefOf(file);' }
        @{ Name = "domain-dropped"
           Find = 'if (domain !== null) argv.push("--domain", domain);'
           Replace = 'if (false) argv.push("--domain", domain);' }
        @{ Name = "model-dropped"
           Find = 'if (model !== null) argv.push("--model", model);'
           Replace = 'if (false) argv.push("--model", model);' }
        @{ Name = "kind-ignored-for-role"
           Find = 'if (["thrall", "orc", "warg"].includes(rec.kind)) return rec.kind;'
           Replace = 'if (false) return rec.kind;' }
        @{ Name = "orc-ended-as-warg"
           Find = 'if (kindOfRecord(rec) !== "warg") return;'
           Replace = 'if (kindOfRecord(rec) === null) return;' }
        @{ Name = "any-fleet-record-is-a-warg"
           Find = 'if (!rec.role && rec.origin === "fleet" && typeof rec.parent === "string" && rec.parent !== "") return "warg";'
           Replace = 'if (rec.origin === "fleet") return "warg";' }
        @{ Name = "failure-exits-nonzero"
           Find = '  clearTimeout(watchdog);'
           Replace = '  clearTimeout(watchdog); process.exit(1);' }
        @{ Name = "output-printed"
           Find = '      const ev = input.hook_event_name;'
           Replace = '      const ev = input.hook_event_name; console.log("recorded");' }
        @{ Name = "no-wait-bound-on-the-lock"
           Find = 'const BUSY_MS = "2000";'
           Replace = 'const BUSY_MS = "60000";' }
        @{ Name = "payload-without-agent-id-not-skipped"
           Find = 'if (!UUID.test(parent) || asciiArg(agentId, 200) === null) {'
           Replace = 'if (false) {' }
        @{ Name = "bom-not-stripped-from-registry"
           Find = 'return JSON.parse(readFileSync(file, "utf8").replace(/^\uFEFF/, ""));'
           Replace = 'return JSON.parse(readFileSync(file, "utf8"));' }
        @{ Name = "clear-ends-the-unit"
           Find = 'if (typeof input.reason === "string" && CONTINUING_END_REASONS.includes(input.reason.toLowerCase())) return;'
           Replace = 'void 0;' }
        @{ Name = "marker-matches-prose"
           Find = '/^\s*(?:work[-_ ]?type|work)\s*[:=]\s*([a-z]+)\s*$/i.exec(line)'
           Replace = '/(?:work[-_ ]?type|work)\s*[:=]\s*([a-z]+)/i.exec(line)' }
    )
}
