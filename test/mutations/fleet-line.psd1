# Mutations of fleet/line/line.js, the fleet as one folded line. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-line.psd1
# test\e2e\e2e-decisions-window.ps1 must fail for each: a page script runs only inside a page, so the
# suite is the scenario that opens a real window and reads back what it drew (about half a minute a
# mutant; see test\mutations\decisions-page.psd1).
@{
    Target = "fleet\line\line.js"
    Suite  = "test\e2e\e2e-decisions-window.ps1"
    Mutations = @(
        @{ Name = "an-orc-without-status-is-named-in-the-folded-line"
           Find = 'if (!entries[i].record || !entries[i].record.written) { without += 1; continue; }'
           Replace = 'if (!entries[i].record || !entries[i].record.written) { without += 1; }' }
        @{ Name = "the-orcs-without-status-are-not-counted"
           Find = 'if (without > 0) { head.appendChild(document.createTextNode((said ? ", " : " ") + without + " without status")); }'
           Replace = '' }
        @{ Name = "the-line-count-sees-every-box-as-one-line"
           Find = 'for (i = 0; i < mids.length; i += 1) { if (mids[i] - last > least / 2) { lines += 1; last = mids[i]; } }'
           Replace = 'for (i = 0; i < mids.length; i += 1) { if (lines === 0) { lines += 1; last = mids[i]; } }' }
        @{ Name = "blocked-is-not-said"
           Find = 'if (entry.record.blocked) { words.push("blocked"); }'
           Replace = '' }
        @{ Name = "an-orc-nobody-wrote-for-has-no-entry"
           Find = 'if (!seen[key] && key.indexOf("orc:") === 0 && state.counts[key] > 0) { extra.push(key); }'
           Replace = '' }
        @{ Name = "what-blocks-an-orc-is-left-out"
           Find = 'if (r.blocked) { words += " Blocked: " + sentence(r.blockedBy); }'
           Replace = '' }
        @{ Name = "a-sentence-is-ended-twice"
           Find = 'return /[.!?]$/.test(words) ? words : words + ".";'
           Replace = 'return words + ".";' }
        @{ Name = "a-sentence-is-left-without-its-end"
           Find = 'return /[.!?]$/.test(words) ? words : words + ".";'
           Replace = 'return words;' }
        @{ Name = "a-broken-record-shown-by-its-fields"
           Find = 'if (!r.written) { return ": no status written (" + (r.problems || []).join("; ") + ")"; }'
           Replace = '' }
    )
}
