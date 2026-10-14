# Mutations of fleet/line/line.js that its rows' words decide, run without a page. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-line-rows.psd1
# test\test-fleet-status.ps1 must fail for each: it draws the fleet line under Node
# (fleet/line/test/draw-rows.mjs) and reads its rows back. Where there is no Node the suite passes as
# PARTIAL, and these mutants are not caught there. The rest of line.js is test\mutations\fleet-line.psd1,
# held by the scenario that opens a real window.
@{
    Target = "fleet\line\line.js"
    Suite  = "test\test-fleet-status.ps1"
    Mutations = @(
        @{ Name = "the-waiting-on-line-not-shown"
           Find = 'if (typeof r.waitingOn === "string" && r.waitingOn !== "") { words += '
           Replace = 'if (false) { words += ' }
        @{ Name = "the-waiting-on-line-without-its-full-stop-rule"
           Find = 'words += " Waiting on: " + sentence(r.waitingOn);'
           Replace = 'words += " Waiting on: " + r.waitingOn + ".";' }
        @{ Name = "the-waiting-on-line-said-for-every-orc"
           Find = 'if (typeof r.waitingOn === "string" && r.waitingOn !== "") {'
           Replace = 'if (true) {' }
    )
}
