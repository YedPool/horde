# Mutations of fleet.db's migration 2 (fleet-db/schema.mjs): keep_visible, parked_now and the decisions
# lists. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-schema-v2.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\schema.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "keep-visible-any-number"
           Find = 'DEFAULT 0 ${flag(''keep_visible'')};'
           Replace = 'DEFAULT 0;' }
        @{ Name = "keep-visible-default-on"
           Find = 'keep_visible INTEGER NOT NULL DEFAULT 0'
           Replace = 'keep_visible INTEGER NOT NULL DEFAULT 1' }
        @{ Name = "parked-now-shows-woken"
           Find = 'WHERE m.state = ''parked'';'
           Replace = 'WHERE m.state <> ''dropped'';' }
        @{ Name = "parked-now-no-session-orc"
           Find = 'coalesce(m.orc_id, s.orc_id) AS orc_id'
           Replace = 'm.orc_id AS orc_id' }
        @{ Name = "same-list-accepted"
           Find = 'BEGIN SELECT RAISE(ABORT, ''decisions_snapshot: same as the live list''); END;'
           Replace = 'BEGIN SELECT 1; END;' }
        @{ Name = "same-list-compared-across-orcs"
           Find = 'FROM decisions_snapshot s WHERE s.orc_id = NEW.orc_id'
           Replace = 'FROM decisions_snapshot s WHERE 1' }
        @{ Name = "same-list-compared-with-oldest"
           Find = '    ORDER BY s.published_at DESC, s.id DESC LIMIT 1)'
           Replace = '    ORDER BY s.published_at ASC, s.id DESC LIMIT 1)' }
        @{ Name = "two-publishes-one-ms"
           Find = '    UNIQUE (orc_id, published_at)'
           Replace = '    CHECK (1)' }
        @{ Name = "item-past-count"
           Find = 'WHEN NEW.position > (SELECT s.item_count'
           Replace = 'WHEN NEW.position > 1 + (SELECT s.item_count' }
        @{ Name = "item-into-older-list"
           Find = 'BEGIN SELECT RAISE(ABORT, ''decisions_snapshot_item: lines go only into the newest list of its Orc''); END;'
           Replace = 'BEGIN SELECT 1; END;' }
        @{ Name = "item-position-zero"
           Find = 'position INTEGER NOT NULL CHECK (position >= 1),'
           Replace = 'position INTEGER NOT NULL,' }
        @{ Name = "item-text-empty"
           Find = 'text TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 400),'
           Replace = 'text TEXT NOT NULL CHECK (length(text) <= 400),' }
        @{ Name = "snapshot-editable"
           Find = '  ${appendOnly(''decisions_snapshot'')}'
           Replace = '' }
        @{ Name = "item-editable"
           Find = '  ${appendOnly(''decisions_snapshot_item'')}'
           Replace = '' }
        @{ Name = "live-is-oldest"
           Find = 'PARTITION BY x.orc_id ORDER BY x.published_at DESC'
           Replace = 'PARTITION BY x.orc_id ORDER BY x.published_at ASC' }
        @{ Name = "live-across-orcs"
           Find = 'row_number() OVER (PARTITION BY x.orc_id ORDER BY'
           Replace = 'row_number() OVER (ORDER BY' }
    )
}
