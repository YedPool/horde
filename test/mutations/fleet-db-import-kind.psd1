# Mutations of the registry importer's reading of a record's kind (fleet-db/import.mjs, T-0299). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-import-kind.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\import.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "kind-not-read"
           Find = 'if (RECORD_KINDS.includes(rec.kind)) return rec.kind;'
           Replace = '' }
        @{ Name = "warg-kind-not-known"
           Find = 'const RECORD_KINDS = [''thrall'', ''orc'', ''warg''];'
           Replace = 'const RECORD_KINDS = [''thrall'', ''orc''];' }
        @{ Name = "orc-kind-not-known"
           Find = 'const RECORD_KINDS = [''thrall'', ''orc'', ''warg''];'
           Replace = 'const RECORD_KINDS = [''thrall'', ''warg''];' }
        @{ Name = "thrall-kind-not-known"
           Find = 'const RECORD_KINDS = [''thrall'', ''orc'', ''warg''];'
           Replace = 'const RECORD_KINDS = [''orc'', ''warg''];' }
        @{ Name = "kind-loses-to-the-older-words"
           Find = 'if (RECORD_KINDS.includes(rec.kind)) return rec.kind;'
           Replace = 'if (RECORD_KINDS.includes(rec.kind) && !rec.role) return rec.kind;' }
        @{ Name = "other-kind-not-reported"
           Find = 'if (rec.kind !== undefined && rec.kind !== null && !RECORD_KINDS.includes(rec.kind)) rep.unlink('
           Replace = 'if (false) rep.unlink(' }
        @{ Name = "disagreement-not-reported"
           Find = 'if (RECORD_KINDS.includes(rec.kind) && have.rank !== rec.kind) rep.unlink('
           Replace = 'if (false) rep.unlink(' }
        @{ Name = "agreement-reported"
           Find = 'if (RECORD_KINDS.includes(rec.kind) && have.rank !== rec.kind) rep.unlink('
           Replace = 'if (RECORD_KINDS.includes(rec.kind)) rep.unlink(' }
        @{ Name = "disagreeing-row-rewritten"
           Find = 'if (RECORD_KINDS.includes(rec.kind) && have.rank !== rec.kind) rep.unlink('
           Replace = 'if (RECORD_KINDS.includes(rec.kind) && have.rank !== rec.kind) db.prepare(''UPDATE session SET rank = ? WHERE id = ?'').run(rec.kind, row.id); if (RECORD_KINDS.includes(rec.kind) && have.rank !== rec.kind) rep.unlink(' }
    )
}
