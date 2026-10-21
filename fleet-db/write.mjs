// Writing fleet.db: the functions every lane calls instead of writing SQL of its own (the one write path,
// planning/fleet-db-design.md "Rules a writer must keep").
//
// IDS IN ORDER: two rows written in one millisecond (a close and its reopen, two events of one import line)
// must sort in the order they were written, because the views break same-millisecond ties on the id. A
// minter remembers the last id it made in each recent millisecond; another id in that millisecond is the
// last one plus one in its 80 random bits (the monotonic ULID rule), so it sorts after it, even when an
// import goes back to that millisecond after others (5, 6, then 5 again). A millisecond it has not seen
// starts from fresh random bits. The order holds within one process: two processes minting in the same
// millisecond cannot see each other's ids, and their rows sort at random within it.
//
// HISTORY ROWS ARE IDENTIFIED BY THEIR CONTENT: appendHistory hashes the row (without its id) and inserts
// it unless that hash is already there, so importing a line twice, or a double send, writes nothing the
// second time and hands back the first row's id. The conflict clause names sha256 alone: a plain INSERT OR
// IGNORE would also swallow a failed CHECK or NOT NULL, and a row the rules refuse must fail loudly.
import crypto from 'node:crypto';
import { ulid, sha256 } from './ids.mjs';
import { inWrite } from './store.mjs';

// The append-only tables that carry a sha256 of their content (schema.mjs). answer_route_taken has no
// hash: it is keyed by its route and written once.
export const HASHED_HISTORY = ['task_event', 'question_event', 'answer', 'answer_route', 'changelog_entry', 'deploy',
  'orc_status'];

const ULID_TAIL_MAX = (1n << 80n) - 1n;

// How many milliseconds a minter remembers. An import walks a few thousand events; one that comes back to
// a millisecond older than this many others is far outside any real ledger's order.
const REMEMBERED_MS = 4096;

export function makeMinter(randomBytes = (n) => crypto.randomBytes(n)) {
  const last = new Map(); // ms -> the last tail minted in it; a Map keeps insertion order for eviction
  return function newId(atMs = Date.now()) {
    let tail = last.get(atMs);
    if (tail !== undefined) {
      if (tail === ULID_TAIL_MAX) throw new Error('newId: more ids in one millisecond than 80 bits hold');
      tail += 1n;
    } else {
      tail = 0n;
      for (const b of randomBytes(10)) tail = (tail << 8n) | BigInt(b);
      if (last.size >= REMEMBERED_MS) last.delete(last.keys().next().value);
    }
    last.set(atMs, tail);
    const rand = Buffer.alloc(10);
    let t = tail;
    for (let i = 9; i >= 0; i--) { rand[i] = Number(t & 255n); t >>= 8n; }
    return ulid(atMs, rand);
  };
}

export const newId = makeMinter();

// A history row's columns, their declared types and their defaults, read from the table itself, so a
// misspelt key fails instead of being dropped. Only names the schema has can reach the SQL text; every
// value is a bound parameter.
function columnsOf(db, table) {
  const cols = new Map();
  for (const r of db.prepare('SELECT name, type, dflt_value FROM pragma_table_info(?)').all(table)) {
    if (r.name !== 'id' && r.name !== 'sha256') cols.set(r.name, { type: r.type, dflt: r.dflt_value });
  }
  return cols;
}

// THE HASH IS OF THE WHOLE STORED ROW: every column but id and sha256, a column left out taking the value
// the database would give it (its default, else null). So {kind, at} and {kind, at, backfill: 0} are the
// same row with the same hash, and anyone can recompute a row's hash from the row alone (the phase 3 check).
function fullRow(cols, row, table) {
  const full = {};
  for (const [name, { dflt }] of cols) {
    if (row[name] !== undefined) { full[name] = row[name]; continue; }
    if (dflt === null) { full[name] = null; continue; }
    // Every default in schema.mjs is a whole number; any other kind must be passed, not guessed at here.
    if (!/^-?\d+$/.test(dflt)) throw new Error('appendHistory: pass ' + table + '.' + name + '; its default ' + dflt + ' is not read here');
    full[name] = Number(dflt);
  }
  return full;
}

// Insert one history row unless a row with the same content is there. row holds the table's columns
// except id and sha256; `at` must be set (it also mints the id, so ids follow event time on an import).
// Returns { id, inserted }.
export function appendHistory(db, table, row, { mint = newId } = {}) {
  if (!HASHED_HISTORY.includes(table)) throw new Error('appendHistory: ' + table + ' is not a hashed history table');
  if (row === null || typeof row !== 'object' || Array.isArray(row)) throw new Error('appendHistory: the row must be an object');
  const cols = columnsOf(db, table);
  for (const k of Object.keys(row)) {
    if (k === 'id' || k === 'sha256') throw new Error('appendHistory: ' + k + ' is made here, not passed in');
    if (!cols.has(k)) throw new Error('appendHistory: ' + table + ' has no column ' + k);
    // EXACTLY THE DECLARED TYPE: a STRICT table converts '1' to 1 in an INTEGER column and 5 to '5' in a
    // TEXT one, so the hash would be of a value the row does not hold (review of phase 1a).
    const v = row[k];
    if (v === undefined || v === null) continue;
    const type = cols.get(k).type;
    if (type === 'TEXT' && typeof v !== 'string') throw new Error('appendHistory: ' + k + ' is text, not ' + typeof v);
    if (type === 'TEXT' && !v.isWellFormed()) throw new Error('appendHistory: ' + k + ' holds a lone surrogate, which SQLite would store as another character');
    if (type === 'INTEGER' && !Number.isSafeInteger(v)) throw new Error('appendHistory: ' + k + ' must be a whole number, not ' + JSON.stringify(v));
    if (type !== 'TEXT' && type !== 'INTEGER') throw new Error('appendHistory: ' + table + '.' + k + ' is ' + type + ', which is not written here');
  }
  const at = row.at;
  if (!Number.isSafeInteger(at)) throw new Error('appendHistory: the row needs its time, at, in UTC milliseconds');
  const full = fullRow(cols, row, table);
  const keys = [...cols.keys()];
  const hash = sha256(full);
  const run = () => {
    const id = mint(at);
    const names = ['id', 'sha256', ...keys];
    const sql = 'INSERT INTO ' + table + ' (' + names.join(', ') + ') VALUES (' + names.map(() => '?').join(', ') + ') ON CONFLICT (sha256) DO NOTHING';
    const r = db.prepare(sql).run(id, hash, ...keys.map((k) => full[k]));
    if (r.changes === 1) return { id, inserted: true };
    return { id: db.prepare('SELECT id FROM ' + table + ' WHERE sha256 = ?').get(hash).id, inserted: false };
  };
  return db.isTransaction ? run() : inWrite(db, run);
}

// An item as it is stored and hashed: every field present, absent ones null, so {text} and
// {text, blocks: null} are the same list.
const ITEM_KEYS = ['position', 'question_id', 'text', 'recommendation', 'importance', 'blocks'];

function normalItem(item, i) {
  if (item === null || typeof item !== 'object' || Array.isArray(item)) throw new Error('publishDecisions: item ' + (i + 1) + ' must be an object');
  // A misspelt field fails, as in appendHistory: a dropped recommendation would publish without it.
  for (const k of Object.keys(item)) if (!ITEM_KEYS.includes(k)) throw new Error('publishDecisions: item ' + (i + 1) + ' has no field ' + k);
  if (item.position !== undefined && item.position !== i + 1) throw new Error('publishDecisions: item ' + (i + 1) + ' says position ' + item.position);
  const text = (k) => {
    const v = item[k] ?? null;
    if (v !== null && typeof v !== 'string') throw new Error('publishDecisions: item ' + (i + 1) + ' ' + k + ' must be text');
    if (v !== null && !v.isWellFormed()) throw new Error('publishDecisions: item ' + (i + 1) + ' ' + k + ' holds a lone surrogate');
    return v;
  };
  return { position: i + 1, question_id: text('question_id'), text: text('text'), recommendation: text('recommendation'), importance: text('importance'), blocks: text('blocks') };
}

// The hash of a list: what decides that two publishes are the same list.
export function decisionsHash(items) {
  return sha256(items.map(normalItem));
}

// Publish an Orc's whole decisions list. A list equal to its newest one writes nothing and says
// unchanged (the schema's trigger would refuse it anyway) but is recorded as a confirm. Returns { id, unchanged, confirmedAt }.
export function publishDecisions(db, { orcId, sessionId = null, publishedAt = Date.now(), items }, { mint = newId } = {}) {
  if (!Array.isArray(items)) throw new Error('publishDecisions: items must be a list (an empty one is a list)');
  if (!Number.isSafeInteger(publishedAt)) throw new Error('publishDecisions: publishedAt must be UTC milliseconds');
  const list = items.map(normalItem);
  const hash = sha256(list);
  // Every accepted publish leaves a confirm at its time (T-0299); a second at the same millisecond is a no-op.
  const confirm = (snapshotId, at) => {
    db.prepare('INSERT INTO decisions_confirm (id, orc_id, snapshot_id, session_id, confirmed_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (snapshot_id, confirmed_at) DO NOTHING')
      .run(mint(at), orcId, snapshotId, sessionId, at);
    return db.prepare('SELECT confirmed_at FROM decisions_live WHERE orc_id = ?').get(orcId).confirmed_at;
  };
  const publish = () => {
    const live = db.prepare('SELECT id, sha256, published_at FROM decisions_live WHERE orc_id = ?').get(orcId);
    if (live && live.sha256 === hash) {
      // A clock stepped back must not lose the confirm: it is never earlier than the list it confirms.
      const confirmedAt = confirm(live.id, Math.max(publishedAt, live.published_at));
      return { id: live.id, unchanged: true, confirmedAt };
    }
    if (live && db.prepare('SELECT published_at FROM decisions_snapshot WHERE id = ?').get(live.id).published_at >= publishedAt) {
      // Lists are published in time order (an import writes each Orc's lists oldest first): a list older
      // than the live one, or in its millisecond, would be archive the moment it is written.
      throw new Error('publishDecisions: this Orc already has a list published at or after ' + new Date(publishedAt).toISOString());
    }
    const id = mint(publishedAt);
    db.prepare('INSERT INTO decisions_snapshot (id, orc_id, published_at, by_session_id, item_count, sha256) VALUES (?, ?, ?, ?, ?, ?)')
      .run(id, orcId, publishedAt, sessionId, list.length, hash);
    const put = db.prepare('INSERT INTO decisions_snapshot_item (snapshot_id, position, question_id, text, recommendation, importance, blocks) VALUES (?, ?, ?, ?, ?, ?, ?)');
    for (const it of list) put.run(id, it.position, it.question_id, it.text, it.recommendation, it.importance, it.blocks);
    return { id, unchanged: false, confirmedAt: confirm(id, publishedAt) };
  };
  return db.isTransaction ? publish() : inWrite(db, publish);
}
