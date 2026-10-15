# Mutations of recording each request (relays/cloudflare/worker/metrics-request.js): counted after the
# answer and never at its cost, the answer's size and refusal code read from a copy, and the summary not
# counted among the requests. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-metrics-request.psd1
# relays\cloudflare\test\test-cloudflare-metrics.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "relays\cloudflare\worker\metrics-request.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-metrics.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-failed-flush-thrown"
           Find = '  try { return (await m.add(batch, { failFlush: settings.failFlush })) === true; } catch (e) { return false; }'
           Replace = '  return (await m.add(batch, { failFlush: settings.failFlush })) === true;' }
        @{ Name = "the-request-waits-for-its-counting"
           Find = '    ctx.waitUntil(count(request, env, url, response, started, ended, copy, settings).catch(() => {}));'
           Replace = '    await count(request, env, url, response, started, ended, copy, settings);' }
        @{ Name = "summary-reads-counted"
           Find = '  if (url.pathname === METRICS_SUMMARY_PATH || !ctx || typeof ctx.waitUntil !== "function") return response;'
           Replace = '  if (!ctx || typeof ctx.waitUntil !== "function") return response;' }
        @{ Name = "refusal-code-not-read"
           Find = '  const code = note.code || read.code;'
           Replace = '  const code = note.code || "";' }
        @{ Name = "bytes-in-not-counted"
           Find = '    bytesIn: lengthOf(request.headers.get("Content-Length")),'
           Replace = '    bytesIn: 0,' }
        @{ Name = "no-account-rows"
           Find = '  const account = who && who.kind !== "test" && typeof who.account === "string" ? await accountHashOf(env && env[SALT_BINDING], who.account) : null;'
           Replace = '  const account = null;' }
        @{ Name = "who-not-kept"
           Find = '  n.who = who;'
           Replace = '' }
        @{ Name = "watch-end-not-empty"
           Find = 'counted: false, emptyWatch: empty,'
           Replace = 'counted: false, emptyWatch: false,' }
    )
}
