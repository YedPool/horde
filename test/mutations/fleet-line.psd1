# Mutations of fleet/line/line.js, the fleet as one folded line. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-line.psd1
# test\e2e\e2e-decisions-window.ps1 must fail for each: a page script runs only inside a page, so the
# suite is the scenario that opens a real window and reads back what it drew (about half a minute a
# mutant; see test\mutations\decisions-page.psd1).
@{
    Target = "fleet\line\line.js"
    Suite  = "test\e2e\e2e-decisions-window.ps1"
    Mutations = @(
        @{ Name = "no-status-is-shown-as-a-guess"
           Find = 'if (!entry.record || !entry.record.written) { words.push("no status written"); }'
           Replace = 'if (!entry.record || !entry.record.written) { words.push("idle"); }' }
        @{ Name = "blocked-is-not-said"
           Find = 'else if (entry.record.blocked) { words.push("blocked"); }'
           Replace = '' }
        @{ Name = "an-orc-nobody-wrote-for-has-no-entry"
           Find = 'if (!seen[key] && key.indexOf("orc:") === 0 && state.counts[key] > 0) { extra.push(key); }'
           Replace = '' }
        @{ Name = "what-blocks-an-orc-is-left-out"
           Find = 'if (r.blocked) { words += " Blocked: " + r.blockedBy + "."; }'
           Replace = '' }
        @{ Name = "a-broken-record-shown-by-its-fields"
           Find = 'if (!r.written) { return ": no status written (" + (r.problems || []).join("; ") + ")"; }'
           Replace = '' }
    )
}
