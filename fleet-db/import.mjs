// Importing the fleet's old files into fleet.db (phase 1c, part 1 of planning/fleet-db-design.md "Importer").
//
//   importFleet(db, sources, { dryRun, onStep }) -> report
//
// Sources, each optional (only the ones given are read; paths are always passed in, never defaulted):
//   ledger      tasks.jsonl            -> task, task_event, pr (named by a line), task_pr
//   prCache     pr-cache.json          -> pr
//   changelog   changelog.jsonl        -> changelog_entry (+ lane tags)
//   cards       the _home/orcs folder  -> orc (one per valid <folder>/status.txt), orc_status
//   thrallCard  _home/thrall/status.txt-> orc (rank thrall), orc_status
//   registry    the registry sessions folder (one <session id>.json per session) -> session
//   decisions   the decisions store folder (storedecisions, one record per file) -> question, question_event,
//               answer, answer_route and their side tables, decisions_read
//   lots        the hibernations folder (<hid>\parking_lot.json, parking_lot_member.json, wakes\<id>\wake.json and
//               wake_member.json, lane K's one-file-per-table form) -> parking_lot, parking_lot_member, wake, wake_member
// Order: node -> orcs -> sessions -> tasks + events + PRs -> changelog -> decisions -> lots -> orc_status.
//
// THE WHOLE IMPORT IS ONE inWrite TRANSACTION: a failure leaves the database as it was, and a dry run runs
// the same code and rolls it back, so its report is exactly what a real run would have added.
//
// IDEMPOTENT: state rows (node, orc, session, task, pr) are found by their label and kept; history rows go
// through appendHistory, whose content hash makes a second import of the same sources write nothing. Ids of
// history rows are minted from the row's own time, so an import in any order sorts by event time.
//
// NOTHING IS DROPPED IN SILENCE: every line, card or file that could not be linked or read is counted in the
// report under its source and reason (report.unlinked), with the first few examples.
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { inWrite } from './store.mjs';
import { appendHistory, newId } from './write.mjs';
import { ensureOrcRow } from './orc-row.mjs';
import { RANKS, TASK_EVENT_KINDS, CHANGELOG_KINDS } from './schema.mjs';
import { canonical } from './ids.mjs';

const EXAMPLES = 5;
// What a waiting-on class names when it is not an Orc: things outside the fleet.
const EXTERNAL_WAITS = ['device', 'merge', 'push', 'gate', 'service'];
const PR_REF = /^([\w.-]+\/[\w.-]+)#(\d+)$/;
const TASK_KEY = /^T-\d{4,}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const SHA40 = /^[0-9a-f]{40}$/;
const TABLES = ['node', 'orc', 'session', 'task', 'task_event', 'pr', 'task_pr', 'changelog_entry', 'tag', 'entity_tag', 'orc_status',
  'question', 'question_event', 'answer', 'answer_extra', 'answer_route', 'answer_route_extra', 'decisions_read',
  'parking_lot', 'parking_lot_member', 'wake', 'wake_member'];

class DryRunDone extends Error {}

// ---------------------------------------------------------------------------------------------------------
// The report

class Report {
  constructor() {
    this.tables = {};
    for (const t of TABLES) this.tables[t] = { added: 0, existing: 0 };
    this.groups = new Map();
    // A state table that a re-import moves forward says how many rows it moved.
    this.tables.parking_lot_member.updated = 0;
  }

  // A lot's own report folded into the run's, once the lot has been kept (a lot that is rolled back adds none).
  merge(other) {
    for (const t of TABLES) {
      for (const k of Object.keys(other.tables[t])) this.tables[t][k] += other.tables[t][k];
    }
    for (const g of other.groups.values()) {
      const key = g.source + '\n' + g.reason;
      let mine = this.groups.get(key);
      if (!mine) { mine = { source: g.source, reason: g.reason, count: 0, examples: [] }; this.groups.set(key, mine); }
      mine.count += g.count;
      for (const e of g.examples) if (mine.examples.length < EXAMPLES && !mine.examples.includes(e)) mine.examples.push(e);
    }
  }

  updated(table) {
    this.tables[table].updated += 1;
  }

  count(table, inserted) {
    this.tables[table][inserted ? 'added' : 'existing'] += 1;
  }

  unlink(source, reason, example) {
    const key = source + '\n' + reason;
    let g = this.groups.get(key);
    if (!g) { g = { source, reason, count: 0, examples: [] }; this.groups.set(key, g); }
    g.count += 1;
    if (example !== undefined && g.examples.length < EXAMPLES && !g.examples.includes(String(example))) g.examples.push(String(example));
  }

  result(dryRun) {
    const unlinked = [...this.groups.values()].sort((a, b) => (a.source + a.reason < b.source + b.reason ? -1 : 1));
    return { dryRun, tables: this.tables, unlinked };
  }
}

// ---------------------------------------------------------------------------------------------------------
// Reading

function readText(file) {
  const buf = fs.readFileSync(file);
  // PowerShell writes a UTF-8 byte order mark; JSON.parse would refuse it.
  const body = buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf ? buf.subarray(3) : buf;
  return body.toString('utf8');
}

// Lines of a .jsonl file: CRLF or LF, blank lines ignored, each line with its number. A line that is not a
// JSON object is reported, not fatal.
function readJsonl(file, source, rep) {
  const out = [];
  const lines = readText(file).split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line === '') continue;
    let obj;
    try { obj = JSON.parse(line); } catch { obj = null; }
    if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) { rep.unlink(source, 'line is not a JSON object (not imported)', 'line ' + (i + 1)); continue; }
    out.push({ n: i, obj });
  }
  return out;
}

function readJsonFile(file) {
  return JSON.parse(readText(file));
}

// A UTC time in milliseconds from an ISO text with Z or an offset (+00:00), any number of fraction digits
// (PowerShell writes seven), or the US-locale 'MM/DD/YYYY HH:MM:SS' one registry file holds (taken as UTC).
// null when it is not a real time.
export function parseTime(s) {
  if (typeof s !== 'string') return null;
  const t = s.trim();
  let m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})$/.exec(t);
  let offsetMin = 0;
  let parts;
  if (m) {
    parts = [m[1], m[2], m[3], m[4], m[5], m[6]].map(Number);
    if (m[8] !== 'Z') {
      const digits = m[8].replace(':', '');
      offsetMin = (m[8][0] === '-' ? -1 : 1) * (Number(digits.slice(1, 3)) * 60 + Number(digits.slice(3, 5)));
    }
  } else {
    m = /^(\d{1,2})\/(\d{1,2})\/(\d{4}) (\d{1,2}):(\d{2}):(\d{2})$/.exec(t);
    if (!m) return null;
    parts = [m[3], m[1], m[2], m[4], m[5], m[6]].map(Number);
  }
  const [y, mo, d, h, mi, sec] = parts;
  const ms = Date.UTC(y, mo - 1, d, h, mi, sec);
  const back = new Date(ms);
  // Date.UTC rolls 02-31 into March; a time that does not read back the same was not a real one.
  if (back.getUTCFullYear() !== y || back.getUTCMonth() !== mo - 1 || back.getUTCDate() !== d || h > 23 || mi > 59 || sec > 59) return null;
  const frac = m[7] ? Number((m[7] + '000').slice(0, 3)) : 0;
  return ms + frac - offsetMin * 60000;
}

function isUsLocale(s) {
  return typeof s === 'string' && /^\d{1,2}\/\d{1,2}\/\d{4} /.test(s.trim());
}

const nz = (v) => (typeof v === 'string' && v.trim() !== '' ? v : null);
const str = (v, max) => (v === undefined || v === null ? null : String(v).slice(0, max));

// ---------------------------------------------------------------------------------------------------------
// Status cards (the reader is fleet/StatusPanel.ps1 ConvertFrom-HordeFleetStatusBytes; this one keeps its
// shape rules for what decides whether a card names an Orc)

const CARD_KEYS = ['orc', 'lane', 'doing', 'finished', 'blocked'];

export function parseCard(buf) {
  if (buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf) return { error: 'starts with a byte order mark' };
  for (const b of buf) {
    if (b > 126 || (b < 32 && b !== 10 && b !== 13)) return { error: 'holds a non-ASCII or control character' };
  }
  const lines = buf.toString('latin1').split(/\r?\n/);
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
  if (lines.length < 6 || lines.length > 7) return { error: 'has ' + lines.length + ' lines, not 6 or 7' };
  if (lines[0] !== 'horde-orc-status 1') return { error: 'does not start with horde-orc-status 1' };
  const card = {};
  for (let i = 0; i < CARD_KEYS.length; i++) {
    const prefix = CARD_KEYS[i] + ':';
    if (!lines[i + 1].startsWith(prefix)) return { error: 'line ' + (i + 2) + ' is not ' + prefix };
    card[CARD_KEYS[i]] = lines[i + 1].slice(prefix.length).trim();
  }
  if (lines.length === 7 && !lines[6].startsWith('waiting on:')) return { error: 'line 7 is not waiting on:' };
  if (!/^[A-Z]$/.test(card.orc)) return { error: "orc line '" + card.orc + "' is not one capital letter" };
  return card;
}

// ---------------------------------------------------------------------------------------------------------
// The import

export function importFleet(db, sources, { dryRun = false, onStep = () => {} } = {}) {
  const src = sources ?? {};
  const rep = new Report();
  const data = loadSources(src, rep);
  try {
    inWrite(db, () => {
      const ctx = { db, rep, seen: new Set() };
      ctx.nodeId = stepNode(ctx);
      onStep('node');
      stepOrcs(ctx, data);
      // Event hashes hold Orc ids: a ledger or changelog imported before any Orc row exists would be
      // written again, as other rows, by the next import that has the cards. So it is refused, whole.
      if ((data.ledger !== null || data.changelog !== null) && db.prepare('SELECT count(*) AS n FROM orc').get().n === 0) {
        throw new Error('the ledger and the changelog name Orcs, and fleet.db has no Orc rows: give the status cards (--cards, --thrall-card) in the same run, or import them first');
      }
      onStep('orcs');
      stepSessions(ctx, data);
      onStep('sessions');
      stepPrCache(ctx, data);
      stepLedger(ctx, data);
      onStep('tasks');
      stepChangelog(ctx, data);
      onStep('changelog');
      stepDecisions(ctx, data);
      onStep('decisions');
      stepLots(ctx, data);
      onStep('lots');
      stepStatus(ctx);
      onStep('status');
      if (dryRun) throw new DryRunDone();
    });
  } catch (e) {
    if (!(e instanceof DryRunDone)) throw e;
  }
  return rep.result(dryRun);
}

// Every file is read before the transaction opens, so a missing or unreadable file fails before a write.
function loadSources(src, rep) {
  const d = { ledger: null, prCache: null, changelog: null, cards: [], thrall: null, sessions: null, decisions: null, lots: null };
  if (src.ledger) d.ledger = readJsonl(src.ledger, 'ledger', rep);
  if (src.changelog) d.changelog = readJsonl(src.changelog, 'changelog', rep);
  if (src.decisions) d.decisions = readDecisions(src.decisions, rep);
  if (src.lots) d.lots = readLots(src.lots, rep);
  if (src.prCache) {
    const cache = readJsonFile(src.prCache);
    if (cache === null || typeof cache !== 'object' || Array.isArray(cache)) throw new Error('the PR cache is not a JSON object');
    d.prCache = cache;
  }
  if (src.cards) {
    for (const ent of fs.readdirSync(src.cards, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
      if (!ent.isDirectory()) continue;
      const file = path.join(src.cards, ent.name, 'status.txt');
      if (!fs.existsSync(file)) { rep.unlink('cards', 'folder has no status.txt (no Orc row made)', ent.name); continue; }
      d.cards.push(readCard(file, ent.name, rep, false));
    }
  }
  if (src.thrallCard) d.thrall = readCard(src.thrallCard, 'thrall', rep, true);
  if (src.registry) {
    d.sessions = [];
    for (const name of fs.readdirSync(src.registry).sort()) {
      if (!/\.json$/i.test(name)) continue;
      let rec;
      try { rec = JSON.parse(readText(path.join(src.registry, name))); } catch { rec = null; }
      if (rec === null || typeof rec !== 'object' || Array.isArray(rec)) { rep.unlink('registry', 'file is not a JSON object (not imported)', name); continue; }
      d.sessions.push({ file: name, rec });
    }
  }
  return d;
}

// THE ONE READER OF A STATUS CARD FILE, shared by the importer (readCard) and `horde status set` (orc-cli.mjs --card),
// so a card is parsed, and its folder and its time judged, by the same code on both paths. Returns { card } or
// { error }, the error being the reason in the importer's own words. mtime is the file's modified time in whole
// milliseconds, which is the status row's `at`.
export function readStatusCard(file, folder, isThrall) {
  const card = parseCard(fs.readFileSync(file));
  if (card.error) return { error: 'card is not valid, no Orc row made: ' + card.error };
  if (!/^[a-z0-9-]{1,64}$/.test(folder)) return { error: 'folder name cannot be a lane_dir (no Orc row made)' };
  return { card: { ...card, folder, mtime: Math.floor(fs.statSync(file).mtimeMs), isThrall } };
}

function readCard(file, folder, rep, isThrall) {
  const r = readStatusCard(file, folder, isThrall);
  if (r.error) {
    rep.unlink(isThrall ? 'thrall-card' : 'cards', r.error, folder);
    return null;
  }
  return r.card;
}

// ---------------------------------------------------------------------------------------------------------
// node

function stepNode(ctx) {
  const { db, rep } = ctx;
  const have = db.prepare('SELECT id FROM node ORDER BY is_authority DESC, created_at, id LIMIT 1').get();
  if (have) { rep.count('node', false); return have.id; }
  const now = Date.now();
  const id = newId(now);
  const name = (os.hostname() || 'this-pc').slice(0, 64);
  db.prepare('INSERT INTO node (id, name, is_authority, created_at) VALUES (?, ?, 1, ?)').run(id, name, now);
  rep.count('node', true);
  return id;
}

// ---------------------------------------------------------------------------------------------------------
// orc

function stepOrcs(ctx, data) {
  const { db, rep } = ctx;
  const all = [...data.cards, ...(data.thrall ? [data.thrall] : [])].filter(Boolean);
  // Two cards naming one Orc (a stale copy under another folder): only the newer card is imported, so one
  // Orc has one status history from one place. The tie goes to the card read first.
  const newest = new Map();
  for (const c of all) {
    const prev = newest.get(c.orc);
    if (prev === undefined) { newest.set(c.orc, c); continue; }
    const drop = c.mtime > prev.mtime ? prev : c;
    newest.set(c.orc, c.mtime > prev.mtime ? c : prev);
    rep.unlink('cards', 'two cards name orc ' + c.orc + ' (only the newer card is imported)', drop.folder);
  }
  const cards = all.filter((c) => newest.get(c.orc) === c);
  ctx.cards = cards;
  ctx.cardOrc = new Map(); // card -> orc id
  for (const c of cards) {
    // An existing row is kept, by lane folder or by letter: never a second row for the same Orc (orc-row.mjs, the
    // one rule, shared with `horde status set`).
    const r = ensureOrcRow(db, { folder: c.folder, letter: c.orc, lane: c.lane, isThrall: c.isThrall, createdAt: c.mtime });
    if (r.cut) rep.unlink('cards', 'lane name longer than 120 characters (cut)', c.folder);
    rep.count('orc', r.added);
    ctx.cardOrc.set(c, r.id);
  }
  loadOrcMaps(ctx);
}

// The names an Orc goes by in the old files, resolved against the rows now in the database.
function loadOrcMaps(ctx) {
  ctx.byLetter = new Map();
  ctx.byDir = new Map();
  ctx.thrallId = null;
  for (const o of ctx.db.prepare('SELECT id, letter, lane_dir, rank FROM orc').all()) {
    if (o.letter) ctx.byLetter.set(o.letter, o.id);
    ctx.byDir.set(o.lane_dir, o.id);
    if (o.rank === 'thrall') ctx.thrallId = o.id;
  }
}

// A sub-session label (a letter and digits: C1, C13, M2) to the Orc of its lead letter, else null.
function labelOrc(ctx, name) {
  const m = typeof name === 'string' ? /^([A-Z])\d+$/.exec(name) : null;
  return m ? (ctx.byLetter.get(m[1]) ?? null) : null;
}

// Text cut to what its column holds is reported, per field, never cut in silence.
function fit(rep, source, field, value, max, example) {
  const v = String(value);
  if (v.length <= max) return v;
  rep.unlink(source, field + ' longer than ' + max + ' characters (cut)', example);
  return v.slice(0, max);
}

// A letter (C) or a lane folder (form-fill) to an Orc id, else null.
const orcRef = (ctx, name) => (typeof name === 'string' ? (ctx.byLetter.get(name) ?? ctx.byDir.get(name) ?? null) : null);

// ---------------------------------------------------------------------------------------------------------
// session

function sessionOrc(ctx, rec, rank, rep) {
  const owner = nz(rec.owner);
  const label = nz(rec.label);
  const single = (v) => (v !== null && /^[A-Z]$/.test(v) ? v : null);
  const lead = (v) => (v !== null && /^([A-Z])\d*$/.test(v) ? v[0] : null);
  // An Orc's own session is owned by the Thrall that spawned it and labelled with the Orc's letter; a
  // Warg is owned by its Orc. So the label decides for an Orc's seat and the owner for everything else.
  const letter = rank === 'orc' || rank === 'thrall' ? (single(label) ?? single(owner)) : (single(owner) ?? lead(label));
  if (letter === null) return null;
  const id = ctx.byLetter.get(letter) ?? null;
  if (id === null) rep.unlink('registry', 'owner/label ' + letter + ' names no Orc row (session kept without one)', letter);
  return id;
}

// The kind a registry record names (written by wezspawn and the seats): the three ranks a record can be.
// RANKS (schema.mjs) covers all three, so session.rank takes each as it is.
const RECORD_KINDS = ['thrall', 'orc', 'warg'];

function rankOf(rec) {
  if (RECORD_KINDS.includes(rec.kind)) return rec.kind;
  if (RANKS.includes(rec.rank)) return rec.rank;
  if (rec.role === 'master') return 'thrall';
  if (rec.role === 'orchestrator') return 'orc';
  if (RANKS.includes(rec.role)) return rec.role;
  return 'unknown';
}

function stepSessions(ctx, data) {
  if (data.sessions === null) return;
  const { db, rep } = ctx;
  const rows = new Map();
  for (const { file, rec } of data.sessions) {
    // The registry names each file after its session id, so the name is the id.
    const id = path.basename(file, path.extname(file)).toLowerCase();
    if (!UUID.test(id)) { rep.unlink('registry', 'session id is not a uuid (not imported)', file); continue; }
    if (rows.has(id)) { rep.unlink('registry', 'two files for one session id (the first kept)', id); continue; }
    let first = parseTime(rec.firstSeen);
    let last = parseTime(rec.lastSeen);
    if (first === null && last === null) { rep.unlink('registry', 'firstSeen and lastSeen are not times (not imported)', id); continue; }
    if (isUsLocale(rec.firstSeen) && first !== null) rep.unlink('registry', 'firstSeen was in US-locale form (read as MM/DD/YYYY, UTC)', id);
    if (first === null) { rep.unlink('registry', 'firstSeen is not a time (lastSeen used)', id); first = last; }
    if (last === null) { rep.unlink('registry', 'lastSeen is not a time (firstSeen used)', id); last = first; }
    if (last < first) { rep.unlink('registry', 'lastSeen is before firstSeen (lastSeen set to firstSeen)', id); last = first; }
    rows.set(id, { id, rec, first, last });
  }
  const order = [...rows.values()].sort((a, b) => b.last - a.last || (a.id < b.id ? -1 : 1));
  const done = new Set();
  const visiting = new Set();
  const exists = db.prepare('SELECT rank, orc_id FROM session WHERE id = ?');
  const seat = db.prepare("SELECT id FROM session WHERE orc_id = ? AND node_id = ? AND retired_at IS NULL AND rank IN ('thrall', 'orc')");
  // SEATS ARE DECIDED BEFORE ANY INSERT, freshest session first: the schema allows one live seat per Orc
  // and PC, and the freshest session must hold it. Inserting a parent early (for its child) never claims
  // one, because the claim was made here, by freshness, not by the order the rows happen to be written in.
  const claimed = new Set();
  for (const row of order) {
    const rec = row.rec;
    // A record's kind is read into rank when the session is new. A row already there keeps its rank; a kind
    // that disagrees is reported, never written over it. A kind that is none of the three is reported too.
    if (rec.kind !== undefined && rec.kind !== null && !RECORD_KINDS.includes(rec.kind)) rep.unlink('registry', 'kind is not thrall, orc or warg (the older rule decides the rank)', row.id);
    const have = exists.get(row.id);
    // A STUB (rank unknown, no Orc) is what horde work start writes for a session the importer has not seen
    // yet: the record upgrades it, and is not a disagreement with it.
    const stub = have !== undefined && have.rank === 'unknown' && have.orc_id === null;
    if (have && !stub) {
      if (RECORD_KINDS.includes(rec.kind) && have.rank !== rec.kind) rep.unlink('registry', 'kind ' + rec.kind + ' disagrees with the stored rank ' + have.rank + ' (rank kept)', row.id);
      continue;
    }
    row.rank = rankOf(rec);
    row.orcId = sessionOrc(ctx, rec, row.rank, rep);
    if ((row.rank === 'orc' || row.rank === 'thrall') && row.orcId === null) {
      rep.unlink('registry', 'a ' + row.rank + ' session names no Orc row (rank unknown)', row.id);
      row.rank = 'unknown';
    }
    row.retired = rec.retired === true;
    row.retiredAt = null;
    if (row.retired) {
      row.retiredAt = parseTime(rec.retiredAt);
      if (row.retiredAt === null) { rep.unlink('registry', 'retiredAt is not a time (lastSeen used)', row.id); row.retiredAt = row.last; }
    }
    if ((row.rank === 'orc' || row.rank === 'thrall') && !row.retired) {
      if (claimed.has(row.orcId) || seat.get(row.orcId, ctx.nodeId)) {
        rep.unlink('registry', 'a second live seat for one Orc (rank unknown)', row.id);
        row.rank = 'unknown';
      } else claimed.add(row.orcId);
    }
    if (stub && (row.rank !== 'unknown' || row.orcId !== null)) {
      db.prepare('UPDATE session SET rank = ?, orc_id = ?, retired_at = COALESCE(retired_at, ?) WHERE id = ?').run(row.rank, row.orcId, row.retiredAt, row.id);
      // The units this session spawned before the importer knew its Orc take it now (orc_id is not identity).
      if (row.orcId !== null) db.prepare('UPDATE work_unit SET orc_id = ? WHERE orc_id IS NULL AND parent_session_id = ?').run(row.orcId, row.id);
    }
  }
  const link = (child, field, parentId) => {
    if (parentId === null || parentId === undefined || parentId === '') return null;
    const p = String(parentId).toLowerCase();
    if (!UUID.test(p)) { rep.unlink('registry', field + ' is not a uuid (link dropped)', p); return null; }
    if (p === child.id) { rep.unlink('registry', field + ' is the session itself (link dropped)', p); return null; }
    if (done.has(p) || exists.get(p)) return p;
    if (rows.has(p)) {
      if (visiting.has(p)) { rep.unlink('registry', field + ' makes a loop (link dropped)', p); return null; }
      put(rows.get(p));
      return p;
    }
    // The old registry has no row for it: a stub, so the foreign key holds.
    db.prepare("INSERT INTO session (id, node_id, rank, first_seen, last_seen) VALUES (?, ?, 'unknown', ?, ?)").run(p, ctx.nodeId, child.first, child.first);
    rep.count('session', true);
    rep.unlink('registry', field + ' is not in the registry (stub row made)', p);
    done.add(p);
    return p;
  };
  const put = (row) => {
    if (done.has(row.id)) return;
    if (exists.get(row.id)) { rep.count('session', false); done.add(row.id); return; }
    visiting.add(row.id);
    const rec = row.rec;
    const parent = link(row, 'parent', rec.parent);
    const resumed = link(row, 'resumed-from', rec.resumedFrom ?? rec.resumedFromId);
    // A process is recorded only when both its id and its start time are there (the schema needs both).
    const pid = Number.isSafeInteger(rec.pid) && rec.pid > 0 ? rec.pid : null;
    const started = parseTime(rec.processStartedAt);
    const hasProc = pid !== null && started !== null;
    db.prepare(`INSERT INTO session (id, node_id, orc_id, rank, parent_session_id, resumed_from_id, pid, process_started_at, start_cwd, cwd,
      transcript_path, origin, fleet_session_id, fleet_run_dir, first_seen, last_seen, retired_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(row.id, ctx.nodeId, row.orcId, row.rank, parent, resumed,
      hasProc ? pid : null, hasProc ? started : null, nz(rec.firstCwd), nz(rec.cwd), nz(rec.transcriptPath),
      str(nz(rec.origin), 40), str(nz(rec.fleetSessionId), 120), nz(rec.fleetRunDir), row.first, row.last, row.retiredAt);
    rep.count('session', true);
    visiting.delete(row.id);
    done.add(row.id);
  };
  for (const row of order) put(row);
}

// ---------------------------------------------------------------------------------------------------------
// pr

function stepPrCache(ctx, data) {
  const { db, rep } = ctx;
  ctx.prIds = new Map(); // 'repo#number' -> id
  for (const r of db.prepare('SELECT id, repo, number FROM pr').all()) ctx.prIds.set(r.repo.toLowerCase() + '#' + r.number, r.id);
  if (data.prCache === null) return;
  // The first ledger line that names each PR: the time a PR with no checked time of its own takes.
  const firstNamed = new Map();
  for (const { obj } of data.ledger ?? []) {
    if (!ledgerLineAccepted(ctx, obj)) continue;
    const ref = typeof obj.pr === 'string' ? prKey(obj.pr) : null;
    const t = parseTime(obj.ts);
    if (ref && t !== null && !(firstNamed.get(ref.key) <= t)) firstNamed.set(ref.key, t);
  }
  for (const key of Object.keys(data.prCache).sort()) {
    const m = prKey(key);
    const v = data.prCache[key];
    if (!m || v === null || typeof v !== 'object') { rep.unlink('pr-cache', 'key is not OWNER/REPO#N or its value is not an object (not imported)', key); continue; }
    if (ctx.prIds.has(m.key)) { rep.count('pr', false); continue; }
    let checked = parseTime(v.checked);
    let state = String(v.state ?? '').toLowerCase();
    if (!['open', 'closed', 'merged'].includes(state)) { rep.unlink('pr-cache', 'state ' + state + ' is not known (kept open)', key); state = 'open'; }
    let mergedAt = parseTime(v.mergedAt);
    if (state === 'merged' && mergedAt === null) { rep.unlink('pr-cache', 'merged with no mergedAt time (kept open)', key); state = 'open'; }
    if (state !== 'merged' && mergedAt !== null) { rep.unlink('pr-cache', 'mergedAt on a PR that is not merged (time ignored)', key); mergedAt = null; }
    if (checked === null) {
      checked = firstNamed.get(m.key) ?? mergedAt ?? Date.now();
      rep.unlink('pr-cache', 'checked is not a time (the first imported ledger line naming it, else mergedAt, else the time of this import, used)', key);
    }
    const sha = v.mergeSha ?? v.merge_sha ?? null;
    insertPr(ctx, m.key, m.repo, m.number, state, mergedAt, typeof sha === 'string' && SHA40.test(sha) ? sha : null, checked, null);
  }
}

// Whether stepLedger will import this line: a usable ts, task and known event, a priority line with a priority, a
// handed line with a target. A line it drops names no PR in the database, so it must not date one.
function ledgerLineAccepted(ctx, obj) {
  if (parseTime(obj.ts) === null || typeof obj.task !== 'string' || !TASK_KEY.test(obj.task) || !TASK_EVENT_KINDS.includes(obj.event)) return false;
  if (obj.event === 'priority' && !(Number.isInteger(obj.prio) && obj.prio >= 0 && obj.prio <= 9)) return false;
  if (obj.event === 'handed') {
    const to = nz(obj.to);
    const target = to === null ? null : orcRef(ctx, to) ?? labelOrc(ctx, to);
    if (target === null) return false;
  }
  return true;
}

// OWNER/REPO#N to its parts; GitHub names are not case-sensitive, so the repo is lower-cased and one PR is one row.
function prKey(ref) {
  const m = PR_REF.exec(ref);
  if (!m) return null;
  const repo = m[1].toLowerCase();
  return { key: repo + '#' + m[2], repo, number: Number(m[2]) };
}

function insertPr(ctx, key, repo, number, state, mergedAt, mergeSha, checkedAt, title) {
  const id = newId(checkedAt);
  ctx.db.prepare('INSERT INTO pr (id, repo, number, title, state, merged_at, merge_sha, checked_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
    .run(id, repo, number, title, state, mergedAt, mergeSha, checkedAt);
  ctx.rep.count('pr', true);
  ctx.prIds.set(key, id);
  return id;
}

// ---------------------------------------------------------------------------------------------------------
// task + task_event

function stepLedger(ctx, data) {
  ctx.taskIds = new Map();
  for (const r of ctx.db.prepare('SELECT id, key FROM task').all()) ctx.taskIds.set(r.key, r.id);
  if (data.ledger === null) return;
  const { rep } = ctx;
  const events = [];
  for (const { n, obj } of data.ledger) {
    const at = parseTime(obj.ts);
    if (at === null || typeof obj.task !== 'string' || !TASK_KEY.test(obj.task) || typeof obj.event !== 'string') {
      rep.unlink('ledger', 'line lacks a usable ts, task or event (not imported)', 'line ' + (n + 1));
      continue;
    }
    if (!TASK_EVENT_KINDS.includes(obj.event)) { rep.unlink('ledger', 'event kind ' + obj.event + ' is not known (not imported)', 'line ' + (n + 1)); continue; }
    events.push({ n, at, ev: obj });
  }
  // By time; two lines of one time keep file order. The file itself is not in time order (backfills).
  events.sort((a, b) => a.at - b.at || a.n - b.n);
  makeTasks(ctx, events);
  for (const e of events) putEvent(ctx, e);
}

function makeTasks(ctx, events) {
  const { db, rep } = ctx;
  const plans = new Map(); // key -> { title, source, parentKey, at }
  for (const e of events) {
    if (plans.has(e.ev.task) || ctx.taskIds.has(e.ev.task)) continue;
    if (e.ev.event === 'opened') {
      plans.set(e.ev.task, { key: e.ev.task, title: nz(e.ev.title) ?? e.ev.task + ' (no title)', source: nz(e.ev.source) ?? 'unknown', parentKey: nz(e.ev.parent), at: e.at });
    }
  }
  for (const e of events) {
    if (plans.has(e.ev.task) || ctx.taskIds.has(e.ev.task)) continue;
    rep.unlink('ledger', 'task has no opened line (task made from its first line)', e.ev.task);
    plans.set(e.ev.task, { key: e.ev.task, title: e.ev.task + ' (no opened line)', source: 'unknown', parentKey: null, at: e.at });
  }
  const visiting = new Set();
  const put = (p) => {
    if (ctx.taskIds.has(p.key)) return;
    visiting.add(p.key);
    let parentId = null;
    if (p.parentKey !== null) {
      if (p.parentKey === p.key) rep.unlink('ledger', 'parent is the task itself (link dropped)', p.key);
      else if (ctx.taskIds.has(p.parentKey)) parentId = ctx.taskIds.get(p.parentKey);
      else if (plans.has(p.parentKey)) {
        if (visiting.has(p.parentKey)) rep.unlink('ledger', 'parent makes a loop (link dropped)', p.key + ' -> ' + p.parentKey);
        else { put(plans.get(p.parentKey)); parentId = ctx.taskIds.get(p.parentKey); }
      } else rep.unlink('ledger', 'parent ' + p.parentKey + ' is not a task (link dropped)', p.key);
    }
    const id = newId(p.at);
    db.prepare('INSERT INTO task (id, key, title, source, parent_id, created_at) VALUES (?, ?, ?, ?, ?, ?)')
      .run(id, p.key, fit(rep, 'ledger', 'title', p.title, 400, p.key), fit(rep, 'ledger', 'source', p.source, 40, p.key), parentId, p.at);
    ctx.taskIds.set(p.key, id);
    rep.count('task', true);
    visiting.delete(p.key);
  };
  for (const p of [...plans.values()].sort((a, b) => a.at - b.at || (a.key < b.key ? -1 : 1))) put(p);
  // Tasks the database already had.
  const had = new Set(events.map((e) => e.ev.task).filter((k) => !plans.has(k)));
  for (let i = 0; i < had.size; i++) rep.count('task', false);
}

// What a waiting-on says: its class, and the Orc when it names one.
function classifyOn(ctx, raw) {
  if (raw === 'founder') return { kind: 'founder', orc: null };
  const lane = /^lane:(.+)$/.exec(raw);
  if (lane) { const o = orcRef(ctx, lane[1]) ?? labelOrc(ctx, lane[1]); return { kind: 'orc', orc: o, unlinked: o === null }; }
  if (/^[A-Z]$/.test(raw)) return { kind: 'orc', orc: orcRef(ctx, raw), unlinked: orcRef(ctx, raw) === null };
  if (/^[A-Z]\d+$/.test(raw)) return { kind: 'orc', orc: labelOrc(ctx, raw), unlinked: labelOrc(ctx, raw) === null };
  if (EXTERNAL_WAITS.includes(raw)) return { kind: 'external', orc: null };
  return { kind: 'other', orc: null };
}

function prFor(ctx, ev, at) {
  if (ev.pr === undefined || ev.pr === null) return null;
  const m = typeof ev.pr === 'string' ? prKey(ev.pr) : null;
  if (!m) { ctx.rep.unlink('ledger', 'pr value is not OWNER/REPO#N (no PR linked)', ev.pr); return null; }
  const known = ctx.prIds.get(m.key);
  if (known) return known;
  // A PR the cache does not know: open until the cache says merged, and said so in the report.
  ctx.rep.unlink('ledger', 'pr is not in the PR cache (row made open, merge time unknown)', ev.pr);
  return insertPr(ctx, m.key, m.repo, m.number, 'open', null, null, at, null);
}

function putEvent(ctx, e) {
  const { db, rep } = ctx;
  const ev = e.ev;
  const where = ev.task + ' ' + ev.event;
  const row = { task_id: ctx.taskIds.get(ev.task), at: e.at, kind: ev.event, backfill: 1 };

  // Who wrote it: an Orc row when it is a known letter, else the words as written.
  const by = nz(ev.by);
  if (by === null) rep.unlink('ledger', 'line has no by', where);
  else if (ctx.byLetter.has(by)) row.by_orc_id = ctx.byLetter.get(by);
  else {
    // The full label stays in by_text; a sub-session label (C13) also gives its lead letter's Orc.
    row.by_text = fit(rep, 'ledger', 'by', by, 64, ev.task);
    const lead = labelOrc(ctx, by);
    if (lead !== null) row.by_orc_id = lead;
    else rep.unlink('ledger', 'by ' + by + ' names no Orc row (kept as by_text)', ev.task);
  }

  if (ev.event === 'opened' || ev.event === 'priority') {
    const prio = Number.isInteger(ev.prio) && ev.prio >= 0 && ev.prio <= 9 ? ev.prio : null;
    if (prio === null) {
      if (ev.event === 'priority') { rep.unlink('ledger', 'priority line has no usable prio (not imported)', ev.task); return; }
      rep.unlink('ledger', 'opened has no usable prio (set to 2)', ev.task);
    }
    row.prio = prio ?? 2;
  }
  if (ev.event === 'opened') {
    const lane = nz(ev.lane);
    row.to_orc_id = lane === null ? null : orcRef(ctx, lane);
    if (row.to_orc_id === null) rep.unlink('ledger', 'lane ' + (lane ?? '(none)') + ' names no Orc row (opened without an owner)', ev.task);
  }
  if (ev.event === 'handed') {
    const to = nz(ev.to);
    const target = to === null ? null : (orcRef(ctx, to) ?? labelOrc(ctx, to));
    if (target === null) {
      rep.unlink('ledger', to === null ? 'handed has no to (event not imported; needs a person to say who took it)' : 'handed to ' + to + ' names no Orc row (event not imported; needs a person)', ev.task);
      return;
    }
    row.to_orc_id = target;
  }
  if (ev.event === 'superseded') {
    const to = nz(ev.to);
    if (to !== null && ctx.taskIds.has(to)) row.superseded_by_id = ctx.taskIds.get(to);
    else rep.unlink('ledger', 'superseded by ' + (to ?? '(none)') + ' is not a task (no replacement linked)', ev.task);
  }
  const on = nz(ev.on);
  if (on !== null) {
    row.on_text = fit(rep, 'ledger', 'on', on, 400, ev.task);
    if (ev.event === 'waiting') {
      const c = classifyOn(ctx, on);
      row.on_kind = c.kind;
      if (c.orc) row.on_orc_id = c.orc;
      if (c.unlinked) rep.unlink('ledger', 'on ' + on + ' names no Orc row (kept as on_text)', ev.task);
    }
  } else if (ev.event === 'waiting') {
    rep.unlink('ledger', 'waiting has no on', ev.task);
  }
  if (nz(ev.proof)) row.proof = fit(rep, 'ledger', 'proof', ev.proof, 4000, ev.task);
  if (nz(ev.reason)) row.reason = fit(rep, 'ledger', 'reason', ev.reason, 4000, ev.task);
  const prId = prFor(ctx, ev, e.at);
  if (prId) row.pr_id = prId;

  const r = appendHistory(db, 'task_event', row);
  if (!r.inserted && ctx.seen.has(r.id)) rep.unlink('ledger', 'line is identical to an earlier line (one event)', where);
  else rep.count('task_event', r.inserted);
  ctx.seen.add(r.id);
  if (prId) {
    const l = db.prepare("INSERT INTO task_pr (task_id, pr_id, linked_at, linked_by) VALUES (?, ?, ?, 'backfill') ON CONFLICT DO NOTHING").run(row.task_id, prId, e.at);
    // A link made earlier in this run (a second event naming the same PR) is not "already there".
    const lk = row.task_id + prId;
    if (l.changes === 1) { rep.count('task_pr', true); ctx.seen.add(lk); } else if (!ctx.seen.has(lk)) { rep.count('task_pr', false); ctx.seen.add(lk); }
  }
}

// ---------------------------------------------------------------------------------------------------------
// changelog_entry

const LANES_OK = /^[A-Za-z0-9-]+$/;

function stepChangelog(ctx, data) {
  if (data.changelog === null) return;
  const { db, rep } = ctx;
  const entries = [];
  for (const { n, obj } of data.changelog) {
    const at = parseTime(obj.ts);
    if (at === null || nz(obj.id) === null) { rep.unlink('changelog', 'line lacks a usable id or ts (not imported)', 'line ' + (n + 1)); continue; }
    entries.push({ n, at, e: obj, legacy: obj.id });
  }
  entries.sort((a, b) => a.at - b.at || a.n - b.n);
  const byLegacy = new Map();
  for (const x of entries) if (!byLegacy.has(x.legacy)) byLegacy.set(x.legacy, x);
  const ids = new Map(); // legacy id -> entry id, for rows in the database and rows written now
  for (const r of db.prepare('SELECT id, legacy_id FROM changelog_entry WHERE legacy_id IS NOT NULL').all()) ids.set(r.legacy_id, r.id);
  const visiting = new Set();
  const doneNow = new Set();
  const put = (x) => {
    if (doneNow.has(x.legacy)) return;
    doneNow.add(x.legacy);
    if (ids.has(x.legacy)) { rep.count('changelog_entry', false); return; }
    visiting.add(x.legacy);
    const e = x.e;
    const row = { legacy_id: x.legacy, at: x.at, backfill: 1, fleet_wide: 0 };
    if (CHANGELOG_KINDS.includes(e.kind)) row.kind = e.kind;
    else { row.kind = 'note'; rep.unlink('changelog', 'kind ' + e.kind + ' is not known (kept as note)', x.legacy); }
    // Lane: one letter, a comma list (the first is the owner, every one is tagged), Thrall, or fleet-wide.
    const tokens = nz(e.lane) === null ? [] : String(e.lane).split(',').map((t) => t.trim()).filter((t) => t !== '');
    row.orc_id = null;
    if (tokens.length === 0) rep.unlink('changelog', 'entry has no lane (no Orc linked)', x.legacy);
    for (const t of tokens) if (t === 'fleet-wide') row.fleet_wide = 1;
    const first = tokens[0];
    if (first !== undefined && first !== 'fleet-wide') {
      row.orc_id = first === 'Thrall' ? ctx.thrallId : orcRef(ctx, first);
      if (row.orc_id === null) rep.unlink('changelog', 'lane ' + first + ' names no Orc row (no Orc linked)', x.legacy);
    }
    row.task_id = null;
    const key = nz(e.task) === null ? null : /^(T-\d{4,})/.exec(String(e.task).trim());
    if (key) {
      row.task_id = ctx.taskIds.get(key[1]) ?? null;
      if (row.task_id === null) rep.unlink('changelog', 'task ' + key[1] + ' is not an imported task (no task linked)', x.legacy);
    } else if (nz(e.task) !== null) rep.unlink('changelog', 'task text names no T-NNNN (no task linked)', x.legacy);
    row.corrects_id = null;
    if (nz(e.corrects) !== null) {
      const target = byLegacy.get(e.corrects);
      if (target && !visiting.has(target.legacy) && target.legacy !== x.legacy) put(target);
      row.corrects_id = ids.get(e.corrects) ?? null;
      if (row.corrects_id === null) rep.unlink('changelog', 'corrects ' + e.corrects + ' is not an imported entry (no link)', x.legacy);
    }
    row.title = fit(rep, 'changelog', 'title', nz(e.title) ?? '(no title)', 400, x.legacy);
    if (nz(e.title) === null) rep.unlink('changelog', 'entry has no title (set to (no title))', x.legacy);
    row.text = String(e.text ?? '');
    const r = appendHistory(db, 'changelog_entry', row);
    rep.count('changelog_entry', r.inserted);
    ids.set(x.legacy, r.id);
    visiting.delete(x.legacy);
    if (tokens.length > 1) for (const t of tokens) tagEntry(ctx, r.id, t, x.at, x.legacy);
  };
  for (const x of entries) {
    if (x !== byLegacy.get(x.legacy)) { rep.unlink('changelog', 'two lines share one id (the first kept)', x.legacy); continue; }
    put(x);
  }
}

function tagEntry(ctx, entryId, lane, at, legacy) {
  const { db, rep } = ctx;
  if (!LANES_OK.test(lane)) { rep.unlink('changelog', 'lane ' + lane + ' cannot be a tag name (not tagged)', legacy); return; }
  const name = 'lane:' + lane.toLowerCase();
  let tag = db.prepare('SELECT id FROM tag WHERE name = ?').get(name);
  if (!tag) {
    tag = { id: newId(at) };
    db.prepare('INSERT INTO tag (id, name, created_at) VALUES (?, ?, ?)').run(tag.id, name, at);
    rep.count('tag', true);
  } else if (!ctx.seen.has(name)) rep.count('tag', false);
  ctx.seen.add(name);
  const r = db.prepare('INSERT INTO entity_tag (entity_id, tag_id, at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING').run(entryId, tag.id, at);
  rep.count('entity_tag', r.changes === 1);
}

// ---------------------------------------------------------------------------------------------------------
// orc_status

// THE ONE RULE FOR A CARD'S STATUS ROW, shared by the importer (stepStatus) and `horde status set` (orc-cli.mjs --card).
// Returns { row: { at, doing, blocked } } or { skip } with the reason in the importer's words (the card then has no
// status row; its Orc row is still made).
export function statusRowFor(c) {
  const doing = c.doing;
  if (doing.length < 1 || doing.length > 120) return { skip: 'doing is empty or over 120 characters (no status row)' };
  // 'no' (any case) is "not blocked"; 'none' and every other sentence is kept as the words it is.
  const blocked = /^no$/i.test(c.blocked) || c.blocked === '' ? null : c.blocked;
  if (blocked !== null && blocked.length > 200) return { skip: 'blocked is over 200 characters (no status row)' };
  return { row: { at: c.mtime, doing, blocked } };
}

// A card whose Orc already has a status row at the card's own time is counted as there and not written again,
// WHATEVER that row's backfill. WHY: `horde status set` now writes the same status live, with backfill 0 and the
// card's mtime as `at`, and the content hash includes backfill, so a backfill 1 row for the same card is a different
// hash: without this skip the sync (which re-reads every card every few minutes) would add a duplicate of every
// live row. orc-cli.mjs checks the same thing the other way round, so whichever path sees a card first wins.
function stepStatus(ctx) {
  const { db, rep } = ctx;
  const there = db.prepare('SELECT 1 FROM orc_status WHERE orc_id = ? AND at = ? LIMIT 1');
  for (const c of ctx.cards) {
    const orcId = ctx.cardOrc.get(c);
    const s = statusRowFor(c);
    if (s.skip) {
      rep.unlink('cards', s.skip, c.folder);
      continue;
    }
    if (there.get(orcId, s.row.at)) { rep.count('orc_status', false); continue; }
    const r = appendHistory(db, 'orc_status', { orc_id: orcId, at: s.row.at, doing: s.row.doing, blocked: s.row.blocked, backfill: 1 });
    rep.count('orc_status', r.inserted);
  }
}

// ---------------------------------------------------------------------------------------------------------
// The decisions store (phase 1c part 2a): store\decisions\0000000001.json ... one record per file, written once.
//
// The journal is READ WHOLE FIRST and checked as a whole: a gap in the sequence, a duplicate record id, a
// file whose name is not its sequence or a schemaVersion other than 1 refuses the SOURCE (nothing from it is
// imported; the other sources go on), because a journal with a hole is not the journal the rules fold.
// It is then FOLDED IN ORDER, as decisions\Rules.ps1 folds it, to work out what the store never writes down:
// whether a message arrived after its question was closed (arrivedAfterClosing), whether it was said to an
// earlier wording (saidToEarlierWording) and whether it replaces his earlier answer. What the schema derives
// itself (answer_now) is compared with the fold afterwards and every difference is reported.

const DECISION_KINDS = ['question-added', 'message-said', 'answer-routed', 'question-closed', 'question-ranked',
  'question-updated', 'question-reopened', 'question-acked', 'answer-change-replied', 'messages-read'];
// The operation each kind is written by: the first word of what its requestHash hashes (decisions/Operations.ps1).
const DECISION_OPERATION = {
  'question-added': 'add', 'question-updated': 'update', 'question-closed': 'close', 'question-reopened': 'reopen',
  'question-ranked': 'rank', 'answer-routed': 'route', 'question-acked': 'ack', 'answer-change-replied': 'change-reply',
  'message-said': 'say', 'messages-read': 'mark-read',
};
const DECISION_EVENT_KIND = {
  'question-updated': 'updated', 'question-closed': 'closed', 'question-reopened': 'reopened', 'question-ranked': 'ranked',
  'question-acked': 'acked', 'answer-change-replied': 'change-reply',
};
// The members of a say that are not part of what makes two requests the same (decisions/Operations.ps1 unhashed),
// and the one member the store adds to a close after the request was hashed.
const DECISION_UNHASHED = { 'message-said': ['evidence', 'signedBy'], 'question-closed': ['closedBySeat'] };
// Fields of a question whose change is a new wording (decisions/Rules.ps1 HordeDecisionFields, wording = true).
const WORDING_FIELDS = ['title', 'options', 'parts', 'whatItIs', 'yesMeans'];
const SEAT_OF = { orc: 'orc', warchief: 'thrall', analyst: 'analyst' };
const SEQ_NAME = /^(\d{10})\.json$/;
const RECORD_ID = /^[0-9a-f]{32}$/;

// The text the store hashes (decisions/Rules.ps1 ConvertTo-HordeDecisionCanonicalText): keys in ordinal order, a
// string escaping only the backslash and the quote, whole numbers only. Not ids.mjs canonical(), which escapes
// every non-ASCII character: the store hashes the characters themselves, as UTF-8.
function storeText(v) {
  if (v === null) return 'null';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'string') return '"' + v.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
  if (typeof v === 'number') {
    if (!Number.isSafeInteger(v)) throw new Error('only whole numbers are decisions data');
    return String(v);
  }
  if (Array.isArray(v)) return '[' + v.map(storeText).join(',') + ']';
  if (typeof v === 'object') return '{' + Object.keys(v).sort().map((k) => storeText(k) + ':' + storeText(v[k])).join(',') + '}';
  throw new Error('cannot hash a ' + typeof v);
}

// The requestHash the store would have written for this record, or null when its kind or shape is not one it writes.
export function recomputeRequestHash(rec) {
  const op = DECISION_OPERATION[rec.kind];
  const data = rec.data;
  if (op === undefined || data === null || typeof data !== 'object' || Array.isArray(data)) return null;
  const body = {};
  let number = 0;
  if (rec.kind === 'messages-read') {
    // A marking has no question number; what it hashes is the record it marks up to.
    body.upTo = data.upTo;
  } else {
    // An add names no number in its request (the list gives it one when it is written), so it hashes 0.
    number = rec.kind === 'question-added' ? 0 : data.number;
    for (const k of Object.keys(data)) if (k !== 'number' && !(DECISION_UNHASHED[rec.kind] ?? []).includes(k)) body[k] = data[k];
  }
  try {
    return crypto.createHash('sha256').update(storeText({ operation: op, actor: rec.actor, number, body }), 'utf8').digest('hex');
  } catch {
    return null;
  }
}

// Every record file, read and checked as a whole. Returns the records in sequence order, or null (refused).
function readDecisions(dir, rep) {
  const refuse = (why, example) => {
    rep.unlink('decisions', 'source refused, nothing imported from it: ' + why, example);
    return null;
  };
  const found = [];
  for (const ent of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
    if (!ent.isFile()) continue;
    if (!/\.json$/i.test(ent.name)) { rep.unlink('decisions', 'file is not a record (a .json file named for its sequence); ignored', ent.name); continue; }
    const m = SEQ_NAME.exec(ent.name);
    if (!m) return refuse('a file name is not a ten-digit sequence', ent.name);
    let rec;
    try { rec = JSON.parse(readText(path.join(dir, ent.name))); } catch { rec = null; }
    if (rec === null || typeof rec !== 'object' || Array.isArray(rec)) return refuse('a record file is not a JSON object', ent.name);
    if (rec.schemaVersion !== 1) return refuse('a record has a schemaVersion other than 1', ent.name);
    if (rec.sequence !== Number(m[1])) return refuse('a file name is not its record\'s sequence', ent.name);
    if (typeof rec.id !== 'string' || !RECORD_ID.test(rec.id)) return refuse('a record id is not 32 lower-case hex characters', ent.name);
    found.push(rec);
  }
  found.sort((a, b) => a.sequence - b.sequence);
  const ids = new Set();
  for (let i = 0; i < found.length; i++) {
    if (found[i].sequence !== i + 1) return refuse('a gap in the sequence: record ' + (i + 1) + ' is not there', 'record ' + (i + 1));
    if (ids.has(found[i].id)) return refuse('two records share one id', 'record ' + found[i].sequence);
    ids.add(found[i].id);
  }
  return found;
}

// The keys each kind of record is known to carry. A key outside the set is not stored anywhere; it is reported
// by kind and key, so a field a later version of the store adds is seen the day it appears.
const KNOWN_ENVELOPE = ['schemaVersion', 'sequence', 'id', 'kind', 'at', 'actor', 'requestHash', 'data'];
const KNOWN_QUESTION = ['title', 'kind', 'options', 'parts', 'whatItIs', 'yesMeans', 'recommendation', 'group', 'groupNote', 'askedBy', 'waiting', 'files', 'references', 'needsSecret'];
const KNOWN_DATA = {
  'question-added': ['number', 'question', 'importance', 'blocks', 'followsUp', 'needsPasskey'],
  'message-said': ['number', 'speaker', 'route', 'text', 'wordingVersion', 'evidence', 'signedBy', 'part', 'asks', 'act'],
  'answer-routed': ['number', 'answer', 'purpose', 'seat', 'label', 'sessionId', 'resolved', 'notice', 'analyst', 'note'],
  'question-closed': ['number', 'outcome', 'closedBySeat'],
  'question-ranked': ['number', 'importance', 'blocks'],
  'question-updated': ['number', 'changes'],
  'question-reopened': ['number', 'reason'],
  'question-acked': ['number', 'by', 'answer'],
  'answer-change-replied': ['number', 'by', 'answer', 'reply', 'why'],
  'messages-read': ['reader', 'upTo'],
};
function reportUnknownKeys(rep, rec) {
  const extra = (obj, known, label) => {
    if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) return;
    for (const k of Object.keys(obj)) if (!known.includes(k)) rep.unlink('decisions', 'unknown key ' + label + '.' + k.slice(0, 40) + ' in ' + String(rec.kind).slice(0, 40) + ' records (not stored)', 'record ' + rec.sequence);
  };
  extra(rec, KNOWN_ENVELOPE, 'envelope');
  if (KNOWN_DATA[rec.kind] === undefined) return;
  extra(rec.data, KNOWN_DATA[rec.kind], 'data');
  if (rec.kind === 'question-added' && rec.data !== null && typeof rec.data === 'object') extra(rec.data.question, KNOWN_QUESTION, 'data.question');
}

const isText = (v) => typeof v === 'string';
const asList = (v) => (Array.isArray(v) ? v : []);

function stepDecisions(ctx, data) {
  if (data.decisions === null) return;
  const { db, rep } = ctx;
  const q = new Map(); // number -> { id, state, wording, passkey, fields, thread: [] }
  const msg = new Map(); // sequence -> { answerId, arrived, authorizes, earlier }
  ctx.answerBySeq = new Map();
  for (const r of db.prepare('SELECT id, decisions_seq FROM answer WHERE decisions_seq IS NOT NULL').all()) ctx.answerBySeq.set(r.decisions_seq, r.id);
  const known = new Map(); // number -> id of a question the database already holds
  for (const r of db.prepare('SELECT id, number FROM question').all()) known.set(r.number, r.id);

  for (const rec of data.decisions) {
    const seq = rec.sequence;
    const where = 'record ' + seq;
    const at = parseTime(rec.at);
    if (at === null) { rep.unlink('decisions', 'record time is not readable (record not imported)', where); continue; }
    if (!DECISION_KINDS.includes(rec.kind)) { rep.unlink('decisions', 'kind ' + String(rec.kind).slice(0, 40) + ' has no place in fleet.db (record not imported)', where); continue; }
    const d = rec.data;
    if (d === null || typeof d !== 'object' || Array.isArray(d)) { rep.unlink('decisions', 'record has no data object (record not imported)', where); continue; }
    reportUnknownKeys(rep, rec);
    const want = recomputeRequestHash(rec);
    if (want === null || want !== rec.requestHash) rep.unlink('decisions', 'requestHash is not the one recomputed from the record (record imported as it stands)', where);
    const actor = isText(rec.actor) ? rec.actor.slice(0, 40) : 'unknown';

    if (rec.kind === 'messages-read') {
      if (!isText(d.reader) || !Number.isSafeInteger(d.upTo) || d.upTo < 1) { rep.unlink('decisions', 'messages-read has no reader or upTo (record not imported)', where); continue; }
      const r = db.prepare('INSERT INTO decisions_read (id, reader, up_to_seq, at, decisions_seq) VALUES (?, ?, ?, ?, ?) ON CONFLICT (decisions_seq) DO NOTHING')
        .run(newId(at), fit(rep, 'decisions', 'reader', d.reader, 40, where), d.upTo, at, seq);
      rep.count('decisions_read', r.changes === 1);
      continue;
    }
    if (!Number.isSafeInteger(d.number) || d.number < 1) { rep.unlink('decisions', rec.kind + ' has no question number (record not imported)', where); continue; }

    if (rec.kind === 'question-added') { addQuestion(ctx, q, known, rec, at, where); continue; }
    const st = q.get(d.number);
    if (st === undefined) { rep.unlink('decisions', rec.kind + ' is about a question the journal never added (record not imported)', where); continue; }

    if (rec.kind === 'message-said') { sayMessage(ctx, st, msg, rec, at, where); continue; }
    if (rec.kind === 'answer-routed') { routeAnswer(ctx, rec, at, where); continue; }

    // Everything else is an event of the question: closed, reopened, ranked, updated, acked, change-reply.
    if (rec.kind === 'question-closed') {
      if (st.state === 'closed') rep.unlink('decisions', 'question-closed on a question already closed (the rules would not apply it)', where);
      st.state = 'closed';
    } else if (rec.kind === 'question-reopened') {
      if (st.state === 'open') rep.unlink('decisions', 'question-reopened on a question that is open (the rules would not apply it)', where);
      st.state = 'open';
    } else if (rec.kind === 'question-updated') {
      foldUpdate(st, d.changes);
    } else if (rec.kind === 'question-acked') {
      // An acknowledgement closes an open question in the rules (Step-HordeDecisionAcked), and in fleet.db's
      // views (migration 4): the store writes an ack only when it applied.
      if (st.state === 'closed') rep.unlink('decisions', 'question-acked on a question already closed (the rules would not apply it)', where);
      st.state = 'closed';
    }
    const kind = DECISION_EVENT_KIND[rec.kind];
    const json = {};
    for (const k of Object.keys(d)) if (k !== 'number') json[k] = d[k];
    json.actor = actor;
    let text;
    try { text = canonical(json); } catch (e) { rep.unlink('decisions', rec.kind + ' holds data that cannot be stored (' + e.message + '; record not imported)', where); continue; }
    const r = appendHistory(db, 'question_event', { question_id: st.id, at, kind, data_json: text, decisions_seq: seq });
    rep.count('question_event', r.inserted);
  }
  compareFold(ctx, msg);
}

// A question-updated's changes folded into the question as the rules fold them: a reworded field raises the
// wording version, a changed group does not.
function foldUpdate(st, changes) {
  if (changes === null || typeof changes !== 'object' || Array.isArray(changes)) return;
  let reworded = false;
  for (const name of Object.keys(changes)) {
    let same;
    try { same = storeText(st.fields[name] ?? null) === storeText(changes[name]); } catch { same = false; }
    if (same) continue;
    st.fields[name] = changes[name];
    if (WORDING_FIELDS.includes(name)) reworded = true;
  }
  if (reworded) st.wording += 1;
}

function askerOf(ctx, asked) {
  if (!isText(asked)) return { orcId: null };
  const m = /^Orc ([A-Z])$/.exec(asked.trim());
  if (m) return { orcId: ctx.byLetter.get(m[1]) ?? null };
  if (/^(M \(Thrall\)|Thrall)$/.test(asked.trim())) return { orcId: ctx.thrallId };
  return { orcId: null };
}

function addQuestion(ctx, q, known, rec, at, where) {
  const { db, rep } = ctx;
  const d = rec.data;
  const f = d.question;
  if (f === null || typeof f !== 'object' || Array.isArray(f) || !isText(f.title) || f.title.trim() === '' || !isText(f.kind) || f.kind.trim() === '') {
    rep.unlink('decisions', 'question-added has no title or kind (record not imported)', where);
    return;
  }
  if (q.has(d.number)) { rep.unlink('decisions', 'a second question-added for one number (the first kept)', where); return; }
  const st = { id: null, state: 'open', wording: 1, passkey: d.needsPasskey === true, fields: { ...f }, thread: [] };
  q.set(d.number, st);
  if (known.has(d.number)) {
    st.id = known.get(d.number);
    rep.count('question', false);
    fillQuestion(ctx, st.id, questionColumns(ctx, new Report(), q, known, rec, where));
    return;
  }
  const c = questionColumns(ctx, rep, q, known, rec, where);
  rep.unlink('decisions', 'question names no task (task_id empty, backfill)', 'question ' + d.number);
  const id = newId(at);
  db.prepare(`INSERT INTO question (id, number, task_id, asked_by_orc_id, follows_up_id, kind, title, body, needs_passkey, asked_at, decisions_seq, backfill,
      asked_by_text, yes_means, recommendation, group_name, group_note, importance, blocks, detail_json)
    VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?)`).run(id, d.number, c.asked_by_orc_id, c.follows_up_id,
    c.kind, c.title, c.body, st.passkey ? 1 : 0, at, rec.sequence,
    c.asked_by_text, c.yes_means, c.recommendation, c.group_name, c.group_note, c.importance, c.blocks, c.detail_json);
  st.id = id;
  known.set(d.number, id);
  rep.count('question', true);
}

// The columns migration 4 added, on a question a version-3 database already holds: only a column that is NULL
// is filled, and a value that is there is never overwritten.
const FILLED_LATER = ['asked_by_text', 'yes_means', 'recommendation', 'group_name', 'group_note', 'importance', 'blocks', 'detail_json'];
function fillQuestion(ctx, id, c) {
  for (const col of FILLED_LATER) {
    if (c[col] === null) continue;
    ctx.db.prepare('UPDATE question SET ' + col + ' = ? WHERE id = ? AND ' + col + ' IS NULL').run(c[col], id);
  }
}

// What a question-added record says, as the columns it fills. rep gets the reports (a throwaway for a question
// that is already there).
function questionColumns(ctx, rep, q, known, rec, where) {
  const d = rec.data;
  const f = d.question;
  const asker = askerOf(ctx, f.askedBy);
  let askedText = null;
  if (asker.orcId === null) {
    askedText = isText(f.askedBy) && f.askedBy.trim() !== '' ? fit(rep, 'decisions', 'askedBy', f.askedBy, 4000, where) : null;
    rep.unlink('decisions', 'askedBy names no Orc row (kept as text on the question)', isText(f.askedBy) ? f.askedBy.slice(0, 50) : '(none)');
  }
  let follows = null;
  if (d.followsUp !== undefined) {
    follows = q.get(d.followsUp)?.id ?? known.get(d.followsUp) ?? null;
    if (follows === null) rep.unlink('decisions', 'followsUp names a question that is not earlier in the journal (no link)', where);
  }
  const detail = canonical({ options: asList(f.options), parts: asList(f.parts), waiting: asList(f.waiting), files: asList(f.files), references: asList(f.references), needsSecret: f.needsSecret === true });
  const text = (v, max, field) => (isText(v) ? fit(rep, 'decisions', field, v, max, where) : null);
  return {
    asked_by_orc_id: asker.orcId, follows_up_id: follows, kind: text(f.kind, 40, 'kind'), title: text(f.title, 400, 'title'),
    body: isText(f.whatItIs) && f.whatItIs !== '' ? f.whatItIs : null, asked_by_text: askedText,
    yes_means: isText(f.yesMeans) && f.yesMeans !== '' ? f.yesMeans : null, recommendation: isText(f.recommendation) && f.recommendation !== '' ? f.recommendation : null,
    group_name: isText(f.group) && f.group !== '' ? text(f.group, 400, 'group') : null, group_note: isText(f.groupNote) && f.groupNote !== '' ? f.groupNote : null,
    importance: isText(d.importance) ? text(d.importance, 40, 'importance') : null, blocks: isText(d.blocks) ? text(d.blocks, 40, 'blocks') : null, detail_json: detail,
  };
}

// SHA-256 of a signing value, so the row says a key signed without saying which key.
const sealed = (v) => crypto.createHash('sha256').update(v, 'utf8').digest('hex');

function sayMessage(ctx, st, msg, rec, at, where) {
  const { db, rep } = ctx;
  const d = rec.data;
  if (!isText(d.speaker) || d.speaker === '' || !isText(d.text)) { rep.unlink('decisions', 'message-said has no speaker or text (record not imported)', where); return; }
  const arrived = st.state !== 'open';
  const stated = Number.isSafeInteger(d.wordingVersion) && d.wordingVersion >= 1;
  const earlier = stated && d.wordingVersion < st.wording;
  if (stated && d.wordingVersion > st.wording) rep.unlink('decisions', 'message says a wording the question had not reached (imported as said)', where);
  const act = isText(d.act) ? d.act : '';
  const asks = d.asks !== false;
  const founder = d.speaker === 'founder';
  const route = isText(d.route) && d.route !== '' ? fit(rep, 'decisions', 'route', d.route, 40, where) : null;
  const authorizes = !(founder && route === 'chat-recorded' && st.passkey);
  const rawPart = isText(d.part) ? d.part : '';
  let part = null;
  if (rawPart !== '') {
    if (/^[A-Za-z]$/.test(rawPart)) {
      part = rawPart.toUpperCase();
      if (rawPart !== part) rep.unlink('decisions', 'part letter written in lower case (stored upper case, the schema\'s rule)', where);
    } else rep.unlink('decisions', 'part is not one letter (answer kept without a part)', where);
    const letters = asList(st.fields.parts).map((p) => (isText(p) ? /^\(([A-Za-z])\)/.exec(p.trim()) : null)).filter(Boolean).map((m) => m[1].toLowerCase());
    if (!earlier && letters.length > 0 && !letters.includes(rawPart.toLowerCase())) rep.unlink('decisions', 'answers a part the question does not list (imported as said)', where);
  }
  // His change of his own answer: his answer that counts, when answers of his to the same part already count.
  let replaces = null;
  if (act === '' && asks && founder && authorizes && !arrived) {
    for (let i = st.thread.length - 1; i >= 0; i--) {
      const b = st.thread[i];
      if (!b.founder || b.act !== '' || !b.asks || !b.counts || b.rawPart !== rawPart) continue;
      replaces = b.answerId;
      break;
    }
  }
  const row = {
    question_id: st.id, at, speaker: fit(rep, 'decisions', 'speaker', d.speaker, 40, where), route, text: d.text, part,
    signed_by: isText(d.signedBy) && d.signedBy !== '' ? sealed(d.signedBy) : null,
    wording_version: stated ? d.wordingVersion : null, asks: asks ? 1 : 0, replaces_answer_id: replaces, decisions_seq: rec.sequence,
  };
  const r = appendHistory(db, 'answer', row);
  rep.count('answer', r.inserted);
  const x = db.prepare('INSERT INTO answer_extra (answer_id, evidence_present, act, recorded_by) VALUES (?, ?, ?, ?) ON CONFLICT (answer_id) DO NOTHING')
    .run(r.id, isText(d.evidence) && d.evidence !== '' ? 1 : 0, act === '' ? null : fit(rep, 'decisions', 'act', act, 200, where), isText(rec.actor) && rec.actor !== '' ? rec.actor.slice(0, 40) : 'unknown');
  rep.count('answer_extra', x.changes === 1);
  ctx.answerBySeq.set(rec.sequence, r.id);
  const counts = authorizes && !arrived;
  st.thread.push({ answerId: r.id, founder, act, asks, counts, rawPart });
  msg.set(rec.sequence, { answerId: r.id, arrived, authorizes, earlier, founderAnswer: founder && act === '' && counts });
  if (earlier) rep.unlink('decisions', 'message was said to an earlier wording of its question (kept as an answer; fleet.db has no flag for it)', where);
}

function routeAnswer(ctx, rec, at, where) {
  const { db, rep } = ctx;
  const d = rec.data;
  const answerId = Number.isSafeInteger(d.answer) ? ctx.answerBySeq.get(d.answer) : undefined;
  if (answerId === undefined) { rep.unlink('decisions', 'answer-routed names a message the journal does not hold (record not imported)', where); return; }
  let seat = SEAT_OF[d.seat];
  if (seat === undefined) { seat = 'none'; rep.unlink('decisions', 'route seat ' + String(d.seat).slice(0, 20) + ' is not a seat fleet.db knows (stored as none)', where); }
  const given = isText(d.sessionId) && d.sessionId !== '' ? d.sessionId.toLowerCase() : null;
  let sessionId = null;
  if (given !== null) {
    if (db.prepare('SELECT 1 FROM session WHERE id = ?').get(given)) sessionId = given;
    else rep.unlink('decisions', 'route names a session fleet.db has no row for (session left empty)', where);
  }
  const claimed = d.resolved === true;
  const resolved = claimed && sessionId !== null ? 1 : 0;
  if (claimed && resolved === 0) rep.unlink('decisions', 'route says resolved but its session is not a row (stored unresolved)', where);
  const r = appendHistory(db, 'answer_route', { answer_id: answerId, at, seat, session_id: sessionId, resolved, decisions_seq: rec.sequence });
  rep.count('answer_route', r.inserted);
  const t = (v, max, field) => (isText(v) && v !== '' ? fit(rep, 'decisions', field, v, max, where) : null);
  const x = db.prepare(`INSERT INTO answer_route_extra (route_id, purpose, label, notice, analyst, note, source_resolved) VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (route_id) DO NOTHING`).run(r.id, isText(d.purpose) && d.purpose !== '' ? fit(rep, 'decisions', 'purpose', d.purpose, 40, where) : 'answer',
    t(d.label, 40, 'label'), t(d.notice, 80, 'notice'), t(d.analyst, 4000, 'analyst'), t(d.note, 4000, 'note'), claimed ? 1 : 0);
  rep.count('answer_route_extra', x.changes === 1);
}

// What the schema derives (answer_now), against what the fold of the journal says, message by message.
function compareFold(ctx, msg) {
  const { db, rep } = ctx;
  const now = db.prepare('SELECT open_at_arrival, authorizes FROM answer_now WHERE id = ?');
  for (const [seq, m] of msg) {
    const s = now.get(m.answerId);
    if (s === undefined) continue;
    const where = 'record ' + seq;
    const arrivalAgrees = s.open_at_arrival === (m.arrived ? 0 : 1);
    if (!arrivalAgrees) {
      rep.unlink('decisions', m.arrived ? 'rules say the message arrived after closing; answer_now says it was open' : 'rules say the message arrived while open; answer_now says it arrived after closing', where);
    }
    // Authorization includes arrival, so it is compared only when arrival agrees: one cause is one line.
    if (arrivalAgrees && s.authorizes !== (m.authorizes && !m.arrived ? 1 : 0)) {
      rep.unlink('decisions', m.authorizes && !m.arrived ? 'rules say the message authorizes; answer_now says it does not (unsigned on a passkey question)' : 'rules say the message does not authorize; answer_now says it does', where);
    }
  }
}

// ---------------------------------------------------------------------------------------------------------
// parking lots (phase 1c part 2b). Lane K writes one JSON file per table, {"v":1,"table":...,"rows":[...]}:
//   <hid>\parking_lot.json, parking_lot_member.json, wakes\<wake id>\wake.json, wake_member.json
// (fleet/LotTables.ps1). A row has exactly the table's columns and a column K did not know is left out, so a
// missing column is NULL here. Ids are K's ULIDs and are kept.

const LOT_COLUMNS = {
  parking_lot: ['id', 'created_at', 'created_by_session_id', 'created_by_orc_id', 'reason', 'selection_kind', 'keep_visible'],
  parking_lot_member: ['lot_id', 'session_id', 'orc_id', 'tier', 'state', 'note'],
  wake: ['id', 'lot_id', 'requested_at', 'requested_by_session_id'],
  wake_member: ['wake_id', 'session_id', 'new_session_id', 'outcome'],
};
// How far a member has got. A park is the start; a wake (woken) or a leave (dropped, it never slept) ends it.
// A member row carries no time, so "newer" is "further along": a file may move a parked member on, never back.
const MEMBER_RANK = { parked: 0, woken: 1, dropped: 1 };

// A file or row the lot cannot be imported with: the lot is rolled back whole and the reason reported.
class LotRefused extends Error {}
const refuse = (msg) => { throw new LotRefused(msg); };

// The rows of one table file, or a sentence saying why the file is refused.
function readLotTable(file, table) {
  let doc;
  try { doc = JSON.parse(readText(file)); } catch { return { error: 'is not JSON' }; }
  if (doc === null || typeof doc !== 'object' || Array.isArray(doc) || doc.v !== 1 || doc.table !== table || !Array.isArray(doc.rows)) {
    return { error: 'is not version 1 of table ' + table };
  }
  if (doc.rows.some((r) => r === null || typeof r !== 'object' || Array.isArray(r))) return { error: 'holds a row that is not an object' };
  return { rows: doc.rows };
}

function readLots(dir, rep) {
  const out = [];
  const dirs = (p) => fs.readdirSync(p, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name).sort();
  for (const hid of dirs(dir)) {
    const base = path.join(dir, hid);
    if (!fs.existsSync(path.join(base, 'parking_lot.json'))) {
      if (fs.existsSync(path.join(base, 'record.json'))) rep.unlink('lots', "legacy record, run K's lot backfill first (not imported)", hid);
      else rep.unlink('lots', 'folder holds neither parking_lot.json nor record.json (ignored)', hid);
      continue;
    }
    const lot = { hid, bad: null, lot: null, members: [], wakes: [] };
    const take = (rel, table) => {
      const full = path.join(base, rel);
      if (!fs.existsSync(full)) { lot.bad = lot.bad ?? (rel + ' is missing'); return null; }
      const r = readLotTable(full, table);
      if (r.error) { lot.bad = lot.bad ?? (rel + ' ' + r.error); return null; }
      return r.rows;
    };
    const lotRows = take('parking_lot.json', 'parking_lot');
    lot.members = take('parking_lot_member.json', 'parking_lot_member') ?? [];
    if (lotRows !== null && lotRows.length !== 1) lot.bad = lot.bad ?? ('parking_lot.json holds ' + lotRows.length + ' rows, not one');
    lot.lot = lotRows === null ? null : lotRows[0];
    const wroot = path.join(base, 'wakes');
    if (fs.existsSync(wroot) && fs.statSync(wroot).isDirectory()) {
      for (const wid of dirs(wroot)) {
        const rel = path.join('wakes', wid);
        if (!fs.existsSync(path.join(base, rel, 'wake.json'))) { rep.unlink('lots', 'wake folder has no wake.json (an unfinished write, not imported)', hid + '/' + wid); continue; }
        const w = take(path.join(rel, 'wake.json'), 'wake');
        const wm = take(path.join(rel, 'wake_member.json'), 'wake_member');
        if (w !== null && w.length !== 1) lot.bad = lot.bad ?? (rel + ' wake.json holds ' + w.length + ' rows, not one');
        lot.wakes.push({ wid, wake: w === null ? null : w[0], members: wm ?? [] });
      }
    }
    if (lot.bad) rep.unlink('lots', 'a file is missing or is not version 1 of its table (nothing imported from this lot)', hid + ': ' + lot.bad);
    out.push(lot);
  }
  return out;
}

// Each lot is its own savepoint: a row the schema refuses (a broken key, a bad state) rolls that lot back and
// is reported, so a lot is whole or absent, and the other lots go on.
function stepLots(ctx, data) {
  if (data.lots === null) return;
  const { db, rep } = ctx;
  for (const lot of data.lots) {
    if (lot.bad) continue;
    const lr = new Report();
    db.exec('SAVEPOINT lot_import');
    try {
      importLot({ ...ctx, rep: lr }, lot);
      db.exec('RELEASE lot_import');
      rep.merge(lr);
    } catch (e) {
      db.exec('ROLLBACK TO lot_import');
      db.exec('RELEASE lot_import');
      if (!(e instanceof LotRefused) && e.code !== 'ERR_SQLITE_ERROR') throw e;
      rep.unlink('lots', 'a row was refused, nothing imported from this lot: ' + String(e.message).slice(0, 160), lot.hid);
    }
  }
}

function unknownColumns(rep, table, row, hid) {
  for (const k of Object.keys(row)) if (!LOT_COLUMNS[table].includes(k)) rep.unlink('lots', table + ' column ' + k.slice(0, 40) + ' is not known (not stored)', hid);
}

// A text column: a string, or NULL when the file left it out. Anything else is refused.
function lotText(row, col, where) {
  const v = row[col];
  if (v === undefined || v === null) return null;
  if (typeof v !== 'string') refuse(where + ': ' + col + ' is not text');
  return v;
}

// A tier is the whole number 1 or 2 (or left out). Anything else would reach the driver unchecked.
function lotTier(row, where) {
  const v = row.tier;
  if (v === undefined || v === null) return null;
  if (v !== 1 && v !== 2) refuse(where + ': tier is not 1 or 2');
  return v;
}

function lotTime(row, col, where) {
  const t = typeof row[col] === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(row[col]) ? parseTime(row[col]) : null;
  if (t === null) refuse(where + ': ' + col + ' is not a UTC time like 2026-10-14T09:00:00Z');
  return t;
}

// A session id from a lot file, made a stub row if fleet.db does not know it (as part 1 does for a parent).
function lotSession(c, id, at, where) {
  if (id === null) return null;
  if (!UUID.test(id)) refuse(where + ': ' + id.slice(0, 40) + ' is not a session uuid');
  if (c.db.prepare('SELECT 1 FROM session WHERE id = ?').get(id)) return id;
  c.db.prepare("INSERT INTO session (id, node_id, rank, first_seen, last_seen) VALUES (?, ?, 'unknown', ?, ?)").run(id, c.nodeId, at, at);
  c.rep.count('session', true);
  c.rep.unlink('lots', 'session is not in fleet.db (stub row made)', id);
  return id;
}

// An Orc named in a lot file: the orc table's own id, else a letter, a lane folder or a sub-session label.
function lotOrc(c, name, hid) {
  if (name === null) return null;
  if (c.db.prepare('SELECT 1 FROM orc WHERE id = ?').get(name)) return name;
  const id = orcRef(c, name) ?? labelOrc(c, name);
  if (id === null) c.rep.unlink('lots', 'orc ' + name.slice(0, 40) + ' names no Orc row (left empty)', hid);
  return id;
}

function importLot(c, lot) {
  const { db, rep } = c;
  const hid = lot.hid;
  unknownColumns(rep, 'parking_lot', lot.lot, hid);
  for (const m of lot.members) unknownColumns(rep, 'parking_lot_member', m, hid);
  const l = lot.lot;
  const where = 'lot ' + hid;
  const created = lotTime(l, 'created_at', where);
  const lotId = lotText(l, 'id', where);
  if (lotId === null) refuse(where + ': id is missing');
  const byOrc = lotOrc(c, lotText(l, 'created_by_orc_id', where), hid);
  const bySession = lotSession(c, lotText(l, 'created_by_session_id', where), created, where);
  if (l.keep_visible !== undefined && l.keep_visible !== 0 && l.keep_visible !== 1) refuse(where + ': keep_visible is not 0 or 1');
  const r = db.prepare(`INSERT INTO parking_lot (id, created_at, created_by_session_id, created_by_orc_id, reason, selection_kind, keep_visible)
    VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (id) DO NOTHING`).run(lotId, created, bySession, byOrc, lotText(l, 'reason', where), lotText(l, 'selection_kind', where), l.keep_visible ?? 0);
  rep.count('parking_lot', r.changes === 1);
  if (r.changes !== 1) {
    const was = db.prepare('SELECT created_at, created_by_session_id, created_by_orc_id, reason, selection_kind, keep_visible FROM parking_lot WHERE id = ?').get(lotId);
    const now = { created_at: created, created_by_session_id: bySession, created_by_orc_id: byOrc, reason: lotText(l, 'reason', where), selection_kind: lotText(l, 'selection_kind', where), keep_visible: l.keep_visible ?? 0 };
    if (Object.keys(now).some((k) => was[k] !== now[k])) rep.unlink('lots', 'lot already in fleet.db with other content (kept as fleet.db has it)', lotId);
  }
  if (lot.members.length === 0) rep.unlink('lots', 'lot holds no member (K never writes one)', hid);

  const seen = new Set();
  for (const m of lot.members) {
    const mw = where + ' member';
    const sid = lotText(m, 'session_id', mw);
    if (sid === null) refuse(mw + ': session_id is missing');
    if (lotText(m, 'lot_id', mw) !== lotId) refuse(mw + ' ' + sid.slice(0, 36) + ': lot_id is not this lot');
    if (seen.has(sid)) refuse(mw + ' ' + sid.slice(0, 36) + ': the session is in the lot twice');
    seen.add(sid);
    lotSession(c, sid, created, mw);
    const state = lotText(m, 'state', mw);
    lotTier(m, mw);
    if (!Object.hasOwn(MEMBER_RANK, state)) refuse(mw + ' ' + sid + ': state ' + String(state).slice(0, 20) + ' is not parked, woken or dropped');
    const have = db.prepare('SELECT state, orc_id, tier, note FROM parking_lot_member WHERE lot_id = ? AND session_id = ?').get(lotId, sid);
    const orc = lotOrc(c, lotText(m, 'orc_id', mw), hid);
    const tier = lotTier(m, mw);
    const note = lotText(m, 'note', mw);
    if (have !== undefined && (have.orc_id !== orc || have.tier !== tier || have.note !== note)) {
      rep.unlink('lots', 'member already in fleet.db with another orc_id, tier or note (kept as fleet.db has it)', sid);
    }
    if (have === undefined) {
      db.prepare('INSERT INTO parking_lot_member (lot_id, session_id, orc_id, tier, state, note) VALUES (?, ?, ?, ?, ?, ?)')
        .run(lotId, sid, orc, tier, state, note);
      rep.count('parking_lot_member', true);
    } else if (MEMBER_RANK[state] > MEMBER_RANK[have.state]) {
      db.prepare('UPDATE parking_lot_member SET state = ? WHERE lot_id = ? AND session_id = ?').run(state, lotId, sid);
      rep.count('parking_lot_member', false);
      rep.updated('parking_lot_member');
    } else {
      rep.count('parking_lot_member', false);
      if (state !== have.state) rep.unlink('lots', 'member state in the file is not further along than the one in fleet.db (kept as fleet.db has it)', sid);
    }
  }

  for (const w of lot.wakes) {
    const ww = where + ' wake ' + w.wid;
    unknownColumns(rep, 'wake', w.wake, hid);
    for (const m of w.members) unknownColumns(rep, 'wake_member', m, hid);
    const wid = lotText(w.wake, 'id', ww);
    if (wid === null) refuse(ww + ': id is missing');
    if (lotText(w.wake, 'lot_id', ww) !== lotId) refuse(ww + ': lot_id is not this lot');
    const at = lotTime(w.wake, 'requested_at', ww);
    const by = lotSession(c, lotText(w.wake, 'requested_by_session_id', ww), at, ww);
    const wr = db.prepare('INSERT INTO wake (id, lot_id, requested_at, requested_by_session_id) VALUES (?, ?, ?, ?) ON CONFLICT (id) DO NOTHING').run(wid, lotId, at, by);
    rep.count('wake', wr.changes === 1);
    if (wr.changes !== 1) {
      const was = db.prepare('SELECT lot_id, requested_at, requested_by_session_id FROM wake WHERE id = ?').get(wid);
      if (was.lot_id !== lotId) refuse(ww + ': the wake id is already in fleet.db under another lot');
      if (was.requested_at !== at || was.requested_by_session_id !== by) rep.unlink('lots', 'wake already in fleet.db with other content (kept as fleet.db has it)', wid);
    }
    const wseen = new Set();
    for (const m of w.members) {
      const sid = lotText(m, 'session_id', ww + ' member');
      if (sid === null) refuse(ww + ' member: session_id is missing');
      if (lotText(m, 'wake_id', ww + ' member') !== wid) refuse(ww + ' member ' + sid.slice(0, 36) + ': wake_id is not this wake');
      if (!seen.has(sid)) refuse(ww + ' member ' + sid.slice(0, 36) + ': the session is not a member of the lot');
      if (wseen.has(sid)) refuse(ww + ' member ' + sid.slice(0, 36) + ': the session is in the wake twice');
      wseen.add(sid);
      lotSession(c, sid, at, ww);
      const fresh = lotSession(c, lotText(m, 'new_session_id', ww), at, ww);
      const mr = db.prepare('INSERT INTO wake_member (wake_id, session_id, outcome, new_session_id) VALUES (?, ?, ?, ?) ON CONFLICT (wake_id, session_id) DO NOTHING')
        .run(wid, sid, lotText(m, 'outcome', ww), fresh);
      rep.count('wake_member', mr.changes === 1);
      if (mr.changes !== 1) {
        const was = db.prepare('SELECT outcome, new_session_id FROM wake_member WHERE wake_id = ? AND session_id = ?').get(wid, sid);
        if (was.outcome !== lotText(m, 'outcome', ww) || was.new_session_id !== fresh) rep.unlink('lots', 'wake member already in fleet.db with other content (kept as fleet.db has it)', sid);
      }
    }
  }
}
