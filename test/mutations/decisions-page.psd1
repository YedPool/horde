# Mutations of decisions/page/list.js, the list of questions drawn as a document. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-page.psd1
# test\e2e\e2e-decisions-window.ps1 must fail for each.
#
# THE SUITE IS A SCENARIO, on purpose. A page script runs only inside a page: nothing but a real
# window can draw it, and the scenario is what reads back what it drew. It opens real windows
# (hidden, and one where no screen is) and takes about half a minute a mutant, so this spec is short:
# the faults a reader would meet - a question lost to its group's name, a redraw that folds what was
# unfolded or forgets the dimming, a wrong sub-number, a suffix that lost its words. NOT MUTATED,
# because nothing can click or scroll the page: a click on a line, and the scroll place kept across
# a redraw.
@{
    Target = "decisions\page\list.js"
    Suite  = "test\e2e\e2e-decisions-window.ps1"
    Mutations = @(
        @{ Name = "groups-kept-in-an-ordinary-object"
           Find = 'var byKey = Object.create(null);'
           Replace = 'var byKey = {};'
           Expect = "survives"
           Reason = "a heading's key is the group's name after the word group: or state:, so a group named __proto__ is not the bare key that an ordinary object trips on, and the scenario's two such groups are drawn whole either way (run 2026-10-07). The map with no prototype is the second layer, kept so that the guard does not rest on how a key happens to be spelt; what the fault looked like - such a group's questions drawn under another heading - is the mutant below." }
        @{ Name = "a-group-named-like-a-built-in-member-loses-its-heading"
           Find = 'key = (listed ? "group:" : "state:") + (listed ? textOf(q.group) : textOf(q.state));'
           Replace = 'key = (listed ? "group:" : "state:") + (listed ? textOf(q.group) : textOf(q.state)); if (key === "group:__proto__") { key = "group:constructor"; }' }
        @{ Name = "a-redraw-folds-what-was-unfolded"
           Find = 'questions = record.value.questions;'
           Replace = 'questions = record.value.questions; unfolded = Object.create(null);' }
        @{ Name = "a-redraw-forgets-the-dimming"
           Find = '(open ? " open" : "") + (dim && dim(q) ? " dim" : ""));'
           Replace = '(open ? " open" : ""));' }
        @{ Name = "sub-lines-numbered-without-their-question"
           Find = 'q.number + "." + (i + 1));'
           Replace = '"" + (i + 1));' }
        @{ Name = "the-suffix-does-not-say-recommended"
           Find = 'bits.push("Recommended: " + rec);'
           Replace = 'bits.push(rec);' }
        @{ Name = "the-suffix-carries-the-reason-in-brackets"
           Find = 'bits.push(listOf(q.waiting).map(whoOf).join(", ") + " waiting");'
           Replace = 'bits.push(listOf(q.waiting).join(", ") + " waiting");' }
        @{ Name = "the-number-drawn-is-the-line-position"
           Find = 'var num = make("span", "hd-num", q.number);'
           Replace = 'var num = make("span", "hd-num", drawnLines.length + 1);' }
        @{ Name = "the-text-reported-is-the-data-not-the-page"
           Find = 't: cut(line.txt.textContent, limits.lineChars), s: cut(line.suf.textContent, limits.lineChars)'
           Replace = 't: cut(line.txt.textContent.toUpperCase(), limits.lineChars), s: cut(line.suf.textContent, limits.lineChars)' }
    )
}
