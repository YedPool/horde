# Mutations of the node side of `horde decisions publish` (fleet-db/decisions-cli.mjs): the question number
# step, the Orc's row, the one-line answers and the read-back. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-publish-node.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\decisions-cli.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "unknown-question-not-refused"
           Find = 'if (!q) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "retired-orc-publishes"
           Find = 'if (row.retired_at !== null) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "misspelt-item-field-dropped"
           Find = 'onlyKeys(it, ITEM_KEYS, ''item '' + (i + 1));'
           Replace = '' }
        @{ Name = "misspelt-input-field-dropped"
           Find = 'onlyKeys(input, INPUT_KEYS, ''the input'');'
           Replace = '' }
        @{ Name = "unrecorded-session-breaks-publish"
           Find = '&& db.prepare(''SELECT 1 FROM session WHERE id = ?'').get(input.sessionId))'
           Replace = ')' }
        @{ Name = "unchanged-reported-as-published"
           Find = 'r.unchanged ? ''unchanged, confirmed '''
           Replace = 'false ? ''unchanged, confirmed ''' }
        @{ Name = "one-items"
           Find = 'n + (n === 1 ? '' item'' : '' items'')'
           Replace = 'n + '' items''' }
        @{ Name = "every-orc-read-for-one"
           Find = 'letter === null || l.letter === letter'
           Replace = 'true' }
        @{ Name = "lines-out-of-order"
           Find = 'ORDER BY i.position'
           Replace = 'ORDER BY i.text' }
        @{ Name = "read-before-init-unexplained"
           Find = 'if (!fs.existsSync(file)) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "thrall-is-any-orc"
           Find = '"SELECT id, letter, retired_at FROM orc WHERE rank = ''thrall'' AND retired_at IS NULL"'
           Replace = '"SELECT id, letter, retired_at FROM orc WHERE rank = ''orc'' AND retired_at IS NULL"' }
        @{ Name = "question-number-not-turned-into-id"
           Find = 'questionId = q.id;'
           Replace = 'questionId = null;' }
    )
}
