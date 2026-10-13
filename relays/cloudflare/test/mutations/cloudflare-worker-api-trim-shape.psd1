# Mutations of what the mailbox API asks of a keepFrom, whoever sends it, and of how it answers one
# (relays/cloudflare/worker/api.js and rules.js's streamOf through it, A SENDER TRIMS ITS OWN STREAM;
# 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-api-trim-shape.psd1
# relays\cloudflare\test\test-cloudflare-worker.ps1 must fail for every one. Every find string occurs
# once. Who may trim is cloudflare-worker-api-trim.psd1's, against the accounts suite.
@{
    Target = "relays\cloudflare\worker\api.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-worker.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "keepfrom-of-zero-or-no-number-is-taken"
           Find = 'if (n === null || n < 1) return refuse(400, "keepFrom must be a whole number from 1 to 2^53-1");'
           Replace = '' }
        @{ Name = "keepfrom-of-zero-is-taken"
           Find = 'if (n === null || n < 1) return refuse(400,'
           Replace = 'if (n === null) return refuse(400,' }
        @{ Name = "trim-with-a-key-that-names-no-stream-is-taken"
           Find = 'if (!stream) return refuse(400,'
           Replace = 'if (false) return refuse(400,' }
        @{ Name = "trim-from-past-its-own-seq-is-taken"
           Find = 'if (keepFrom > stream.seq) return refuse(400, "keepFrom is past'
           Replace = 'if (false) return refuse(400, "keepFrom is past' }
        @{ Name = "trim-is-not-answered"
           Find = 'if (keepFrom > 0) return answer(200, { seq: done.seq, duplicate: done.duplicate, trimmed: done.trimmed });'
           Replace = '' }
        @{ Name = "every-put-is-answered-with-a-trim"
           Find = 'if (keepFrom > 0) return answer(200, { seq: done.seq, duplicate: done.duplicate, trimmed: done.trimmed });'
           Replace = 'if (true) return answer(200, { seq: done.seq, duplicate: done.duplicate, trimmed: done.trimmed });' }
    )
}
