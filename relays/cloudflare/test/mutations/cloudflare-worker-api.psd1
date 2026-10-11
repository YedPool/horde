# Mutations of the hosted relay's mailbox API (relays/cloudflare/worker/api.js). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-api.psd1
# Each loosens one check the Worker makes of a request, and relays\cloudflare\test\test-cloudflare-worker.ps1
# must fail for every one. Every find string occurs exactly once.
#
# NOT HERE, and why: the declared-length check in readCapped (a body that states a length past the cap
# is also stopped by the chunk-by-chunk count after it, so dropping it changes when a refusal comes,
# not whether - the chunked case holds the count itself to account); and authorize() before an
# operation (the only principal in 8a, the test one, may do everything, so no request can tell; 8b's
# principals are the first that refuse anything).
@{
    Target = "relays\cloudflare\worker\api.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-worker.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "nobody-vouched-is-let-in"
           Find = 'if (!who) return refuse(401,'
           Replace = 'if (false) return refuse(401,' }
        @{ Name = "body-cap-forgets-escapes"
           Find = 'const BODY_BYTES = 2 * MAX_TEXT_CHARS + 1024;'
           Replace = 'const BODY_BYTES = MAX_TEXT_CHARS + 1024;' }
        @{ Name = "chunked-body-read-whole"
           Find = 'if (size > cap) { await reader.cancel(); return null; }'
           Replace = '' }
        @{ Name = "oversize-text-is-not-413"
           Find = 'body.text.length > MAX_TEXT_CHARS) return refuse(413,'
           Replace = 'body.text.length > MAX_TEXT_CHARS * 2) return refuse(413,' }
        @{ Name = "extra-members-allowed"
           Find = 'if (names !== members.slice().sort().join(",")) return'
           Replace = 'if (false) return' }
        @{ Name = "bad-key-stored"
           Find = 'if (keyProblem(body.key)) return refuse(400,'
           Replace = 'if (typeof body.key !== "string") return refuse(400,' }
        @{ Name = "batch-of-zero-allowed"
           Find = 'if (max === null || max < 1) return'
           Replace = 'if (max === null) return' }
        @{ Name = "watch-needs-no-upgrade"
           Find = '.toLowerCase() !== "websocket") return refuse(426,'
           Replace = '.toLowerCase() === "never") return refuse(426,' }
        @{ Name = "method-not-checked-for-ack"
           Find = 'const op = OPS[m[3] + " " + request.method];'
           Replace = 'const op = OPS[m[3] + " " + (m[3] === "ack" ? "POST" : request.method)];' }
        @{ Name = "device-named-mailbox-taken"
           Find = 'if (mailboxProblem(mailbox)) return refuse(400,'
           Replace = 'if (false) return refuse(400,' }
        @{ Name = "negative-ack-taken"
           Find = 'if (!Number.isSafeInteger(body.through) || body.through < 0) return'
           Replace = 'if (typeof body.through !== "number") return' }
        @{ Name = "ack-past-head-is-not-409"
           Find = 'if (!done.ok) return refuse(409,'
           Replace = 'if (!done.ok) return refuse(400,' }
    )
}
