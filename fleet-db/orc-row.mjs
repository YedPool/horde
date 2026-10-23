// The ONE rule for "does fleet.db have a row for this Orc, and if not make it". Two callers: the importer
// (import.mjs stepOrcs, for every status card it reads) and `horde status set` (orc-cli.mjs ensure, for the card
// it has just written), so a new Orc has its row from its first card and the two paths cannot drift.
// Call inside inWrite: the find and the insert must be one transaction, or two writers could each make a row.
import { newId } from './write.mjs';

// The longest lane text a row's name column holds (schema.mjs orc.name).
export const NAME_MAX = 120;

// The row an Orc already has, found by lane folder OR letter (the folder match wins when both name rows); a
// Thrall card matches the one live Thrall row first. Returns the id, or null.
export function findOrcId(db, { folder, letter, isThrall = false }) {
  if (isThrall) {
    const t = db.prepare("SELECT id FROM orc WHERE rank = 'thrall' AND retired_at IS NULL").get();
    if (t) return t.id;
  }
  const r = db.prepare('SELECT id FROM orc WHERE lane_dir = ? OR letter = ? ORDER BY letter = ? DESC LIMIT 1').get(folder, letter, letter);
  return r ? r.id : null;
}

// Keeps the row found by folder or letter, never making a second one; only when none exists inserts one
// (lane_dir = the folder name, name = the lane text or else the folder). Returns { id, added, cut }, cut true
// when the lane text was longer than the name column and was shortened (the importer reports it).
export function ensureOrcRow(db, { folder, letter, lane, isThrall = false, createdAt }) {
  const found = findOrcId(db, { folder, letter, isThrall });
  if (found !== null) return { id: found, added: false, cut: false };
  let name = lane === '' || lane === undefined || lane === null ? folder : String(lane);
  const cut = name.length > NAME_MAX;
  if (cut) name = name.slice(0, NAME_MAX);
  const id = newId(createdAt);
  db.prepare('INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, ?, ?, ?, ?, ?)')
    .run(id, letter, folder, name, isThrall ? 'thrall' : 'orc', createdAt);
  return { id, added: true, cut };
}
