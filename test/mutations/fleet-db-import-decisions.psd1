# Mutations of the fleet.db importer's decisions-store source (fleet-db/import.mjs, "Importer (phase 1c part 2a)"). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-import-decisions.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\import.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "decisions-gap-not-refused"
           Find = 'if (found[i].sequence !== i + 1) return refuse('
           Replace = 'if (false) return refuse(' }
        @{ Name = "decisions-duplicate-id-not-refused"
           Find = 'if (ids.has(found[i].id)) return refuse('
           Replace = 'if (false) return refuse(' }
        @{ Name = "decisions-file-name-not-its-sequence"
           Find = 'if (rec.sequence !== Number(m[1])) return refuse('
           Replace = 'if (false) return refuse(' }
        @{ Name = "decisions-schema-version-not-checked"
           Find = 'if (rec.schemaVersion !== 1) return refuse('
           Replace = 'if (false) return refuse(' }
        @{ Name = "decisions-hash-add-number-kept"
           Find = 'number = rec.kind === ''question-added'' ? 0 : data.number;'
           Replace = 'number = data.number;' }
        @{ Name = "decisions-hash-signed-by-hashed"
           Find = '''message-said'': [''evidence'', ''signedBy'']'
           Replace = '''message-said'': [''evidence'']' }
        @{ Name = "decisions-hash-backslash-not-escaped"
           Find = 'v.replace(/\\/g, ''\\\\'').replace('
           Replace = 'v.replace(' }
        @{ Name = "decisions-hash-mismatch-silent"
           Find = 'if (want === null || want !== rec.requestHash) rep.unlink('
           Replace = 'if (false) rep.unlink(' }
        @{ Name = "decisions-signed-by-stored-raw"
           Find = '? sealed(d.signedBy) : null,'
           Replace = '? d.signedBy : null,' }
        @{ Name = "decisions-evidence-flag-lost"
           Find = 'isText(d.evidence) && d.evidence !== '''' ? 1 : 0'
           Replace = 'isText(d.evidence) && d.evidence !== '''' ? 0 : 0' }
        @{ Name = "decisions-arrived-after-closing-not-folded"
           Find = 'const arrived = st.state !== ''open'';'
           Replace = 'const arrived = false;' }
        @{ Name = "decisions-reopen-not-folded"
           Find = 'st.state = ''open'';'
           Replace = 'st.state = ''closed'';' }
        @{ Name = "decisions-wording-never-bumped"
           Find = 'if (reworded) st.wording += 1;'
           Replace = '' }
        @{ Name = "decisions-part-not-upper-cased"
           Find = 'part = rawPart.toUpperCase();'
           Replace = 'part = rawPart;' }
        @{ Name = "decisions-replaces-ignores-part"
           Find = 'b.rawPart !== rawPart'
           Replace = 'false' }
        @{ Name = "decisions-resolved-without-session"
           Find = 'const resolved = claimed && sessionId !== null ? 1 : 0;'
           Replace = 'const resolved = claimed ? 1 : 0;' }
        @{ Name = "decisions-unknown-kind-silent"
           Find = 'rep.unlink(''decisions'', ''kind '' + String(rec.kind).slice(0, 40) + '' has no place in fleet.db (record not imported)'', where); continue;'
           Replace = 'continue;' }
        @{ Name = "decisions-thrall-asker-unmapped"
           Find = '/^(M \(Thrall\)|Thrall)$/.test(asked.trim())'
           Replace = 'false' }
        @{ Name = "decisions-asker-text-dropped"
           Find = 'askedText = isText(f.askedBy) && f.askedBy.trim() !== '''' ? fit(rep, ''decisions'', ''askedBy'', f.askedBy, 4000, where) : null;'
           Replace = 'askedText = null;' }
        @{ Name = "decisions-follows-up-not-linked"
           Find = 'follows = q.get(d.followsUp)?.id ?? known.get(d.followsUp) ?? null;'
           Replace = 'follows = null;' }
        @{ Name = "decisions-read-mark-twice"
           Find = 'VALUES (?, ?, ?, ?, ?) ON CONFLICT (decisions_seq) DO NOTHING'
           Replace = 'VALUES (?, ?, ?, ?, ?)' }
        @{ Name = "decisions-arrival-difference-silent"
           Find = 'const arrivalAgrees = s.open_at_arrival === (m.arrived ? 0 : 1);'
           Replace = 'const arrivalAgrees = true;' }
        @{ Name = "decisions-stray-file-silent"
           Find = 'rep.unlink(''decisions'', ''file is not a record (a .json file named for its sequence); ignored'', ent.name); continue;'
           Replace = 'continue;' }
        @{ Name = "decisions-nit-lane-label-not-resolved"
           Find = 'const o = orcRef(ctx, lane[1]) ?? labelOrc(ctx, lane[1]);'
           Replace = 'const o = orcRef(ctx, lane[1]);' }
        @{ Name = "decisions-nit-first-named-unfiltered"
           Find = 'if (!ledgerLineAccepted(ctx, obj)) continue;'
           Replace = '' }
        @{ Name = "decisions-nit-pr-without-time-is-1970"
           Find = 'checked = firstNamed.get(m.key) ?? mergedAt ?? Date.now();'
           Replace = 'checked = firstNamed.get(m.key) ?? mergedAt ?? 0;' }
        @{ Name = "decisions-fill-overwrites-existing"
           Find = '= ? WHERE id = ? AND '' + col + '' IS NULL'''
           Replace = '= ? WHERE id = ?''' }
        @{ Name = "decisions-existing-question-not-filled"
           Find = 'fillQuestion(ctx, st.id, questionColumns(ctx, new Report(), q, known, rec, where));'
           Replace = 'void 0;' }
        @{ Name = "decisions-unknown-key-silent"
           Find = 'if (!known.includes(k)) rep.unlink('
           Replace = 'if (false) rep.unlink(' }
        @{ Name = "decisions-ack-not-imported"
           Find = 'question-acked on a question already closed (the rules would not apply it)'', where);'
           Replace = 'question-acked on a question already closed (the rules would not apply it)'', where); return;' }
    )
}
