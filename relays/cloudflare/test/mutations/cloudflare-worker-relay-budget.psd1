# Mutations of the relay-wide object's pins (relays/cloudflare/worker/relay-budget.js, THE PINS): an owner
# email is one account's - the first to match it - and naming it no more drops the pin. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-relay-budget.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one (part 5). Every find string
# occurs once.
@{
    Target = "relays\cloudflare\worker\relay-budget.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "an-owner-email-any-accounts"
           Find = 'return held === account;'
           Replace = 'return true;' }
        @{ Name = "pins-never-dropped"
           Find = 'if (gone.length > 0) await storage.delete(gone);'
           Replace = '' }
        @{ Name = "an-owner-email-never-an-owner"
           Find = 'const as = pin && typeof pin.email === "string"'
           Replace = 'const as = false && pin && typeof pin.email === "string"' }
    )
}
