# Mutations of who may trim a stream, and what a trim may ask (relays/cloudflare/worker/api.js, A SENDER
# TRIMS ITS OWN STREAM; 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-api-trim.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one: it is the suite with a
# signed-in phone and machines that sign their requests, and these rules are about who is asking. Every
# find string occurs once. The rules a caller with no account can provoke - a keepFrom that is no
# number, a key that names no stream - are cloudflare-worker-api-trim-shape.psd1's, against the faster
# test-cloudflare-worker.ps1.
@{
    Target = "relays\cloudflare\worker\api.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "machine-trims-another-machines-stream"
           Find = 'if (who.kind === "machine") return stream.sender === who.keyId;'
           Replace = 'if (who.kind === "machine") return true;' }
        @{ Name = "phone-trims-a-stream"
           Find = 'return who.kind === "test";'
           Replace = 'return true;'
           Expect = "survives"
           Reason = "A phone that names keepFrom is refused before this is asked, by the line above it in put (phone-naming-keepfrom-is-not-refused-at-once holds that one): two refusals stand between a phone and a trim on purpose, so removing either alone changes no answer." }
        @{ Name = "phone-naming-keepfrom-is-not-refused-at-once"
           Find = 'if (who.kind !== "machine" && who.kind !== "test") return refuse(403, "only the machine that wrote a stream may trim it");'
           Replace = '' }
        @{ Name = "nobody-is-asked-whether-they-may-trim"
           Find = 'if (!mayTrim(who, stream)) return refuse(403,'
           Replace = 'if (false) return refuse(403,' }
        @{ Name = "machines-trim-from-past-its-own-seq-is-taken"
           Find = 'if (keepFrom > stream.seq) return refuse(400,'
           Replace = 'if (false) return refuse(400,' }
        @{ Name = "keepfrom-is-read-and-dropped"
           Find = 'const done = await box.put(body.key, body.text, { now: Date.now(), limits, owner, keepFrom });'
           Replace = 'const done = await box.put(body.key, body.text, { now: Date.now(), limits, owner });' }
    )
}
