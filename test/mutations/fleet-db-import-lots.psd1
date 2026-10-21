# Mutations of the fleet.db importer's parking-lots source (fleet-db/import.mjs, "Importer (phase 1c part 2b: parking lots)"). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-import-lots.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\import.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "lots-legacy-record-imported"
           Find = 'if (!fs.existsSync(path.join(base, ''parking_lot.json''))) {'
           Replace = 'if (false) {' }
        @{ Name = "lots-wrong-table-accepted"
           Find = 'doc.v !== 1 || doc.table !== table ||'
           Replace = 'doc.v !== 1 ||' }
        @{ Name = "lots-version-not-checked"
           Find = 'Array.isArray(doc) || doc.v !== 1 ||'
           Replace = 'Array.isArray(doc) ||' }
        @{ Name = "lots-refused-lot-still-imported"
           Find = 'if (lot.bad) continue;'
           Replace = 'if (false) continue;' }
        @{ Name = "lots-refused-lot-not-rolled-back"
           Find = 'db.exec(''ROLLBACK TO lot_import'');'
           Replace = 'void 0;' }
        @{ Name = "lots-refusal-not-reported"
           Find = 'rep.unlink(''lots'', ''a row was refused, nothing'
           Replace = 'void (''lots'', ''a row was refused, nothing' }
        @{ Name = "lots-rolled-back-lot-counted"
           Find = 'importLot({ ...ctx, rep: lr }, lot);'
           Replace = 'importLot(ctx, lot);' }
        @{ Name = "lots-member-state-moves-back"
           Find = 'MEMBER_RANK[state] > MEMBER_RANK[have.state]'
           Replace = 'MEMBER_RANK[state] !== MEMBER_RANK[have.state]' }
        @{ Name = "lots-member-state-never-updated"
           Find = 'MEMBER_RANK[state] > MEMBER_RANK[have.state]'
           Replace = 'false' }
        @{ Name = "lots-member-always-inserted"
           Find = 'if (have === undefined) {'
           Replace = 'if (true) {' }
        @{ Name = "lots-member-of-another-lot-accepted"
           Find = 'if (lotText(m, ''lot_id'', mw) !== lotId) refuse('
           Replace = 'if (false) refuse(' }
        @{ Name = "lots-session-twice-accepted"
           Find = 'if (seen.has(sid)) refuse('
           Replace = 'if (false) refuse(' }
        @{ Name = "lots-unknown-session-no-stub"
           Find = 'c.db.prepare("INSERT INTO session (id, node_id, rank, first_seen, last_seen) VALUES (?, ?, ''unknown'', ?, ?)").run(id, c.nodeId, at, at);'
           Replace = 'void 0;' }
        @{ Name = "lots-known-session-stubbed-again"
           Find = 'if (c.db.prepare(''SELECT 1 FROM session WHERE id = ?'').get(id)) return id;'
           Replace = 'if (false) return id;' }
        @{ Name = "lots-orc-label-not-mapped"
           Find = 'const id = orcRef(c, name) ?? labelOrc(c, name);'
           Replace = 'const id = null;' }
        @{ Name = "lots-unknown-orc-not-reported"
           Find = 'if (id === null) c.rep.unlink(''lots'', ''orc '''
           Replace = 'if (false) c.rep.unlink(''lots'', ''orc ''' }
        @{ Name = "lots-keep-visible-dropped"
           Find = 'l.keep_visible ?? 0);'
           Replace = '0);' }
        @{ Name = "lots-wake-member-conflict-unhandled"
           Find = ' ON CONFLICT (wake_id, session_id) DO NOTHING'
           Replace = '' }
        @{ Name = "lots-unfinished-wake-not-skipped"
           Find = 'if (!fs.existsSync(path.join(base, rel, ''wake.json''))) {'
           Replace = 'if (false) {' }
        @{ Name = "lots-unknown-column-silent"
           Find = 'if (!LOT_COLUMNS[table].includes(k)) rep.unlink('
           Replace = 'if (false) rep.unlink(' }
        @{ Name = "lots-merge-loses-report-lines"
           Find = 'mine.count += g.count;'
           Replace = 'mine.count += 0;' }
        @{ Name = "lots-time-not-checked"
           Find = 'if (t === null) refuse(where + '': '' + col + '' is not a UTC time'
           Replace = 'if (false) refuse(where + '': '' + col + '' is not a UTC time' }
        @{ Name = "lots-tier-not-checked"
           Find = 'if (v !== 1 && v !== 2) refuse('
           Replace = 'if (false) refuse(' }
        @{ Name = "lots-wake-member-not-a-lot-member"
           Find = 'if (!seen.has(sid)) refuse(ww'
           Replace = 'if (false) refuse(ww' }
        @{ Name = "lots-wake-member-twice-accepted"
           Find = 'if (wseen.has(sid)) refuse('
           Replace = 'if (false) refuse(' }
        @{ Name = "lots-empty-lot-not-reported"
           Find = 'if (lot.members.length === 0) rep.unlink('
           Replace = 'if (false) rep.unlink(' }
        @{ Name = "lots-lot-mismatch-silent"
           Find = 'if (Object.keys(now).some((k) => was[k] !== now[k])) rep.unlink('
           Replace = 'if (false) rep.unlink(' }
        @{ Name = "lots-wake-mismatch-silent"
           Find = 'was.requested_at !== at ||'
           Replace = 'false ||' }
        @{ Name = "lots-wake-member-mismatch-silent"
           Find = 'was.outcome !== lotText(m, ''outcome'', ww) ||'
           Replace = 'false ||' }
    )
}
