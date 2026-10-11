# Mutations of relays/cloudflare/worker/rules.js, where the Worker takes its limits from
# capabilities.json and the port's rules from the phone's relay client. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-rules.psd1
# relays\cloudflare\test\test-cloudflare-worker.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\rules.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-worker.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "text-limit-is-the-port-ceiling"
           Find = 'export const MAX_TEXT_CHARS = capabilities.limits.maxTextChars;'
           Replace = 'export const MAX_TEXT_CHARS = LIMITS.textChars;' }
        @{ Name = "batch-budget-past-a-websocket-message"
           Find = 'export const BATCH_CHARS = 1000000;'
           Replace = 'export const BATCH_CHARS = 16000000;' }
        @{ Name = "cursor-with-leading-zero-taken"
           Find = '!/^(0|[1-9][0-9]{0,15})$/.test(text)'
           Replace = '!/^[0-9]{1,16}$/.test(text)' }
        @{ Name = "body-cap-forgets-escapes"
           Find = 'export const BODY_BYTES = 2 * MAX_TEXT_CHARS + 1024;'
           Replace = 'export const BODY_BYTES = MAX_TEXT_CHARS + 1024;' }
        @{ Name = "cursor-past-the-ceiling-taken"
           Find = 'return Number.isSafeInteger(n) && n <= max ? n : null;'
           Replace = 'return n;' }
    )
}
