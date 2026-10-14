# Mutations of the mailbox API's part in the relay-wide limits (relays/cloudflare/worker/api.js): the
# account's tier passed to its gate, and a phone's watch refused by a limit answered as a socket whose
# one message says why. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-api-budget.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one (part 5 and budget-watch.mjs).
# Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\api.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "owners-never-read"
           Find = 'const tier = tierOf(ownersOf(env), who.account);'
           Replace = 'const tier = tierOf(ownersOf({}), who.account);' }
        @{ Name = "phone-watch-refused-by-status"
           Find = 'return op === "watch" && who.kind === "phone" && g.status === 429 ? refuseWatch(request, g) : refusalOf(g);'
           Replace = 'return refusalOf(g);' }
        @{ Name = "watch-refusal-says-no-code"
           Find = 'server.send(JSON.stringify({ error: r.reason, code: r.code }));'
           Replace = 'server.send(JSON.stringify({ error: r.reason }));' }
        @{ Name = "watch-refusal-closes-as-normal"
           Find = 'server.close(LIMITED, r.code);'
           Replace = 'server.close(1000, r.code);' }
    )
}
