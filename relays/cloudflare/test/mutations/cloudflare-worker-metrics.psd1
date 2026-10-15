# Mutations of the request metrics' pure parts (relays/cloudflare/worker/metrics.js): the fixed lists a
# request is counted by, the account hash, an isolate's counts and when they are flushed, and what the
# metrics object takes of a batch. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-metrics.psd1
# relays\cloudflare\test\test-cloudflare-metrics.ps1 must fail for every one (its part 1,
# metrics-units.mjs, catches each before any dev starts). Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\metrics.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-metrics.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-path-of-no-route-is-a-route"
           Find = 'return m[1] === "watch" ? (method === "GET" ? "watch" : "other") : method === "POST" ? "ack" : "other";'
           Replace = 'return m[1] === "watch" ? "watch" : "ack";' }
        @{ Name = "registration-counted-as-a-machine-removal"
           Find = 'if (pathname === "/v1/account/machines") return method === "POST" ? "pair.register" : "other";'
           Replace = 'if (pathname === "/v1/account/machines") return "account.machines";' }
        @{ Name = "test-principal-counted-a-machine"
           Find = '  if (who) return "anonymous";'
           Replace = '  if (who) return "machine";' }
        @{ Name = "any-code-is-an-outcome"
           Find = 'if (typeof code === "string" && OUTCOMES.includes(code) && code !== "ok") return code;'
           Replace = 'if (typeof code === "string" && code !== "") return code;' }
        @{ Name = "a-refused-watch-counted-ok"
           Find = '  if (status < 400 && !refused) return "ok";'
           Replace = '  if (status < 400) return "ok";' }
        @{ Name = "a-refusal-counted-ok"
           Find = '  if (status < 400 && !refused) return "ok";'
           Replace = '  if (status < 500 && !refused) return "ok";' }
        @{ Name = "latency-edge-moved"
           Find = 'const LATENCY_EDGES = [50, 200, 1000, 5000];'
           Replace = 'const LATENCY_EDGES = [51, 200, 1000, 5000];' }
        @{ Name = "watch-attempt-read-for-every-route"
           Find = '  if (route === "watch" && url) {'
           Replace = '  if (url) {' }
        @{ Name = "a-row-key-from-any-route"
           Find = 'if (!isHour(hour) || !ROUTES.includes(route) || !KINDS.includes(kind) || !OUTCOMES.includes(outcome)) return null;'
           Replace = 'if (!isHour(hour) || !KINDS.includes(kind) || !OUTCOMES.includes(outcome)) return null;' }
        @{ Name = "an-unsalted-hash"
           Find = 'if (typeof salt !== "string" || salt.length === 0 || typeof account !== "string" || account.length === 0) return null;'
           Replace = 'if (typeof account !== "string" || account.length === 0) return null; if (typeof salt !== "string") salt = "-";' }
        @{ Name = "hash-of-eight-hex"
           Find = '  for (let i = 0; i < 8; i++) hex += mac[i].toString(16).padStart(2, "0");'
           Replace = '  for (let i = 0; i < 4; i++) hex += mac[i].toString(16).padStart(2, "0");' }
        @{ Name = "flush-only-by-count"
           Find = 'if (this.increments < settings.flushCount && now - this.since < settings.flushMs) return null;'
           Replace = 'if (this.increments < settings.flushCount) return null;' }
        @{ Name = "a-watch-end-counted-a-request"
           Find = '    if (entry.counted !== false) {'
           Replace = '    if (true) {' }
        @{ Name = "retry-never-counted"
           Find = '      add.retries = entry.retry ? 1 : 0;'
           Replace = '      add.retries = 0;' }
        @{ Name = "a-batch-of-any-keys-taken"
           Find = 'for (const r of b.rows) { if (!Array.isArray(r) || r.length !== 2 || rowPartsOf(r[0]) === null) return null; rows.push([r[0], addCounters(null, r[1])]); }'
           Replace = 'for (const r of b.rows) { if (!Array.isArray(r) || r.length !== 2) return null; rows.push([r[0], addCounters(null, r[1])]); }' }
        @{ Name = "test-override-honoured-anywhere"
           Find = 'if (typeof t !== "string" || !url || !LOOPBACK.has(url.hostname)) return METRICS;'
           Replace = 'if (typeof t !== "string") return METRICS;' }
    )
}
