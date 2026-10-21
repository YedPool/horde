# Mutations of fleet.db's write layer (fleet-db/write.mjs): ids in order, history rows by content, and
# decisions lists. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-write.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\write.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "same-ms-not-incremented"
           Find = 'tail += 1n;'
           Replace = 'tail += 0n;' }
        @{ Name = "same-ms-fresh-random"
           Find = 'if (tail !== undefined) {'
           Replace = 'if (false) {' }
        @{ Name = "overflow-wraps"
           Find = 'if (tail === ULID_TAIL_MAX) throw'
           Replace = 'if (false) throw' }
        @{ Name = "conflict-swallows-every-unique"
           Find = 'ON CONFLICT (sha256) DO NOTHING'
           Replace = 'ON CONFLICT DO NOTHING' }
        @{ Name = "insert-or-ignore"
           Find = 'const sql = ''INSERT INTO '' + table'
           Replace = 'const sql = ''INSERT OR IGNORE INTO '' + table' }
        @{ Name = "defaults-not-filled"
           Find = 'full[name] = Number(dflt);'
           Replace = 'full[name] = undefined;' }
        @{ Name = "unknown-column-dropped"
           Find = 'if (!cols.has(k)) throw'
           Replace = 'if (false) throw' }
        @{ Name = "any-table-appended"
           Find = 'if (!HASHED_HISTORY.includes(table)) throw'
           Replace = 'if (false) throw' }
        @{ Name = "float-accepted"
           Find = 'if (type === ''INTEGER'' && !Number.isSafeInteger(v)) throw'
           Replace = 'if (false) throw' }
        @{ Name = "number-in-text-accepted"
           Find = 'if (type === ''TEXT'' && typeof v !== ''string'') throw'
           Replace = 'if (false) throw' }
        @{ Name = "millisecond-forgotten"
           Find = 'last.set(atMs, tail);'
           Replace = 'last.clear(); last.set(atMs, tail);' }
        @{ Name = "surrogate-in-history"
           Find = 'if (type === ''TEXT'' && !v.isWellFormed()) throw'
           Replace = 'if (false) throw' }
        @{ Name = "surrogate-in-list"
           Find = 'if (v !== null && !v.isWellFormed()) throw'
           Replace = 'if (false) throw' }
        @{ Name = "misspelt-item-field-dropped"
           Find = 'if (!ITEM_KEYS.includes(k)) throw'
           Replace = 'if (false) throw' }
        @{ Name = "backdated-list-raw-error"
           Find = '.published_at >= publishedAt) {'
           Replace = '.published_at > 9e15) {' }
        @{ Name = "list-outer-write-split"
           Find = 'return db.isTransaction ? publish() : inWrite(db, publish);'
           Replace = 'if (db.isTransaction) db.exec(''COMMIT''); return inWrite(db, publish);' }
        @{ Name = "id-minted-now"
           Find = 'const id = mint(at);'
           Replace = 'const id = mint(Date.now());' }
        @{ Name = "duplicate-gives-new-id"
           Find = 'return { id: db.prepare(''SELECT id FROM '' + table'
           Replace = 'return { id, x: db.prepare(''SELECT id FROM '' + table' }
        @{ Name = "outer-write-split"
           Find = 'return db.isTransaction ? run() : inWrite(db, run);'
           Replace = 'if (db.isTransaction) db.exec(''COMMIT''); return inWrite(db, run);' }
        @{ Name = "unchanged-list-written"
           Find = 'if (live && live.sha256 === hash) {'
           Replace = 'if (false) {' }
        @{ Name = "null-field-not-normalised"
           Find = 'const v = item[k] ?? null;'
           Replace = 'const v = item[k];' }
        @{ Name = "position-not-checked"
           Find = 'item.position !== i + 1) throw'
           Replace = 'false) throw' }
        @{ Name = "first-item-dropped"
           Find = 'for (const it of list) put.run('
           Replace = 'for (const it of list.slice(1)) put.run(' }
        @{ Name = "count-off"
           Find = '.run(id, orcId, publishedAt, sessionId, list.length, hash);'
           Replace = '.run(id, orcId, publishedAt, sessionId, list.length + 1, hash);' }
        @{ Name = "new-list-confirm-not-written"
           Find = 'confirmedAt: confirm(id) }'
           Replace = 'confirmedAt: publishedAt }' }
        @{ Name = "equal-list-confirm-not-written"
           Find = 'const confirmedAt = confirm(live.id);'
           Replace = 'const confirmedAt = publishedAt;' }
        @{ Name = "confirm-loses-session"
           Find = 'snapshotId, sessionId, publishedAt)'
           Replace = 'snapshotId, null, publishedAt)' }
        @{ Name = "confirm-time-off"
           Find = 'snapshotId, sessionId, publishedAt)'
           Replace = 'snapshotId, sessionId, publishedAt + 1)' }
        @{ Name = "confirm-conflict-unnamed"
           Find = ' ON CONFLICT (snapshot_id, confirmed_at) DO NOTHING'
           Replace = '' }
        @{ Name = "confirmed-at-returns-published"
           Find = '.get(orcId).confirmed_at;'
           Replace = '.get(orcId).published_at;' }
    )
}
