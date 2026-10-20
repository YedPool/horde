# Mutations of fleet.db's ids and hashes (fleet-db/ids.mjs): each makes one content hash unstable or one id
# malformed, so a re-import would duplicate rows or a row would fail its CHECK. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-ids.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\ids.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "keys-not-sorted"
           Find = 'filter((k) => value[k] !== undefined).sort();'
           Replace = 'filter((k) => value[k] !== undefined);' }
        @{ Name = "non-ascii-kept"
           Find = "return JSON.stringify(value).replace("
           Replace = "return JSON.stringify(value); (" }
        @{ Name = "floats-allowed"
           Find = "if (!Number.isSafeInteger(value)) throw new Error('canonical: only safe integers, not ' + value);"
           Replace = "" }
        @{ Name = "time-digits-reversed"
           Find = "out = CROCKFORD[t % 32] + out;"
           Replace = "out = out + CROCKFORD[t % 32];" }
        @{ Name = "sparse-hole-dropped"
           Find = "for (let i = 0; i < value.length; i++) parts.push("
           Replace = "for (const i in value) parts.push(" }
        @{ Name = "date-hashed-as-empty"
           Find = "if (proto !== Object.prototype && proto !== null) throw"
           Replace = "if (false) throw" }
    )
}
