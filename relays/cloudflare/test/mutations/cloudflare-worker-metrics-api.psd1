# Mutations of the day's summary (relays/cloudflare/worker/metrics-api.js): only a machine, the relay-wide
# view only for an owner's, its own account's hours for any, a day that is a date. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-metrics-api.psd1
# relays\cloudflare\test\test-cloudflare-metrics.ps1 must fail for every one (part 2, against a dev).
# Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\metrics-api.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-metrics.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-phone-reads-the-metrics"
           Find = '  if (!who || who.kind !== "machine") return refuse(403, "only a registered machine reads the relay''s metrics");'
           Replace = '  if (!who) return refuse(403, "only a registered machine reads the relay''s metrics");' }
        @{ Name = "any-machine-reads-the-relay-wide-view"
           Find = '  if (scope === "relay" && tierOf(ownersOf(env), who.account) !== "owner") return refuse(403,'
           Replace = '  if (scope === "relay" && false) return refuse(403,' }
        @{ Name = "no-scope-is-always-relay-wide"
           Find = '  const scope = asked || (tierOf(ownersOf(env), who.account) === "owner" ? "relay" : "account");'
           Replace = '  const scope = asked || "relay";' }
        @{ Name = "any-day-asked"
           Find = '  if (day === null) return refuse(400, "day must be a date, YYYY-MM-DD");'
           Replace = '' }
        @{ Name = "account-view-is-every-account"
           Find = '  const s = await m.summary({ day, account });'
           Replace = '  const s = await m.summary({ day, account: null });' }
    )
}
