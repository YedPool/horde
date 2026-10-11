# One mutation of relays/cloudflare/worker/mailbox.js the conformance suite cannot see (no relay is
# required there to forget a trimmed key), so the Worker's own suite holds it. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-keys.psd1
# Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\mailbox.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-worker.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "trimmed-key-remembered"
           Find = 'for (const [name, item] of doomed) names.push(name, KEY + item.key);'
           Replace = 'for (const [name, item] of doomed) names.push(name);' }
    )
}
