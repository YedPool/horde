# Mutations of the hosted relay's limits, their one source (relays/cloudflare/worker/limits.js, relay PR
# 8c): every approved number, retention taken from capabilities.json, and the test override honoured
# only for a local test. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-worker-limits.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one (its part 1, limits-units.mjs,
# holds each number to the founder's approval). Every find string occurs once.
#
# NOT HERE, and why: the throw for a binding that is not JSON or not an object (limits-units.mjs provokes
# both, but a mutant that dropped them would only reach JSON.parse's own throw, or read an array's
# members as none - the same refusal or no override, so no request tells them apart).
@{
    Target = "relays\cloudflare\worker\limits.js"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "machines-per-account-changed"; Find = 'machinesPerAccount: 10,'; Replace = 'machinesPerAccount: 11,' }
        @{ Name = "phones-per-account-changed"; Find = 'phonesPerAccount: 5,'; Replace = 'phonesPerAccount: 6,' }
        @{ Name = "pairings-per-hour-changed"; Find = 'pairingsPerHour: 10,'; Replace = 'pairingsPerHour: 11,' }
        @{ Name = "requests-per-day-changed"; Find = 'requestsPerDay: 20000,'; Replace = 'requestsPerDay: 5000,' }
        @{ Name = "account-mailboxes-changed"; Find = 'accountMaxMailboxes: 50,'; Replace = 'accountMaxMailboxes: 51,' }
        @{ Name = "account-chars-changed"; Find = 'accountMaxChars: 100 * 1024 * 1024,'; Replace = 'accountMaxChars: 100 * 1000 * 1000,' }
        @{ Name = "mailbox-items-changed"; Find = 'mailboxMaxItems: 2000,'; Replace = 'mailboxMaxItems: 2001,' }
        @{ Name = "mailbox-chars-changed"; Find = 'mailboxMaxChars: 20 * 1024 * 1024,'; Replace = 'mailboxMaxChars: 20 * 1000 * 1000,' }
        @{ Name = "puts-per-minute-changed"; Find = 'putsPerMinute: 60,'; Replace = 'putsPerMinute: 61,' }
        @{ Name = "put-burst-changed"; Find = 'putBurst: 20,'; Replace = 'putBurst: 21,' }
        @{ Name = "reads-per-minute-changed"; Find = 'readsPerMinute: 120,'; Replace = 'readsPerMinute: 121,' }
        @{ Name = "read-burst-changed"; Find = 'readBurst: 40,'; Replace = 'readBurst: 41,' }
        @{ Name = "sign-in-starts-changed"; Find = 'signInStartsPerMinute: 10,'; Replace = 'signInStartsPerMinute: 11,' }
        @{ Name = "new-accounts-changed"; Find = 'newAccountsPerDay: 5,'; Replace = 'newAccountsPerDay: 6,' }
        @{ Name = "refused-per-address-changed"; Find = 'refusedSignaturesPerMinutePerAddress: 30,'; Replace = 'refusedSignaturesPerMinutePerAddress: 31,' }
        @{ Name = "refused-per-key-changed"; Find = 'refusedSignaturesPerMinutePerKey: 10,'; Replace = 'refusedSignaturesPerMinutePerKey: 11,' }
        @{ Name = "nonces-per-key-changed"; Find = 'noncesPerKey: 1000,'; Replace = 'noncesPerKey: 1001,' }
        @{ Name = "retention-not-the-declared-one"; Find = 'retentionMs: capabilities.limits.retentionSeconds * 1000'; Replace = 'retentionMs: capabilities.limits.retentionSeconds * 100' }
        @{ Name = "a-setting-added"; Find = '  noncesPerKey: 1000,'; Replace = '  noncesPerKey: 1000, watchesPerDevice: 1,' }
        @{ Name = "defaults-changeable"; Find = 'export const DEFAULTS = Object.freeze({'; Replace = 'export const DEFAULTS = ({' }
        @{ Name = "override-honoured-for-a-deployed-worker"
           Find = 'if (typeof t !== "string" || !isLoopback(url)) return DEFAULTS;'
           Replace = 'if (typeof t !== "string") return DEFAULTS;' }
        @{ Name = "override-of-no-setting-taken"
           Find = 'if (!Object.prototype.hasOwnProperty.call(DEFAULTS, name)) throw'
           Replace = 'if (false) throw' }
        @{ Name = "override-of-a-bad-value-taken"
           Find = 'if (!Number.isSafeInteger(o[name]) || o[name] < 1) throw'
           Replace = 'if (false) throw' }
    )
}
