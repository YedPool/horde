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
// Order: node -> orcs -> sessions -> tasks + events + PRs -> changelog -> orc_status.
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
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { inWrite } from './store.mjs';
import { appendHistory, newId } from './write.mjs';
import { RANKS, TASK_EVENT_KINDS, CHANGELOG_KINDS } from './schema.mjs';

const EXAMPLES = 5;
// What a waiting-on class names when it is not an Orc: things outside the fleet.
const EXTERNAL_WAITS = ['device', 'merge', 'push', 'gate', 'service'];
const PR_REF = /^([\w.-]+\/[\w.-]+)#(\d+)$/;
const TASK_KEY = /^T-\d{4,}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const SHA40 = /^[0-9a-f]{40}$/;
const TABLES = ['node', 'orc', 'session', 'task', 'task_event', 'pr', 'task_pr', 'changelog_entry', 'tag', 'entity_tag', 'orc_status'];

class DryRunDone extends Error {}

// ---------------------------------------------------------------------------------------------------------
// The report

class Report {
  constructor() {
    this.tables = {};
    for (const t of TABLES) this.tables[t] = { added: 0, existing: 0 };
    this.groups = new Map();
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
  const d = { ledger: null, prCache: null, changelog: null, cards: [], thrall: null, sessions: null };
  if (src.ledger) d.ledger = readJsonl(src.ledger, 'ledger', rep);
  if (src.changelog) d.changelog = readJsonl(src.changelog, 'changelog', rep);
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

function readCard(file, folder, rep, isThrall) {
  const buf = fs.readFileSync(file);
  const card = parseCard(buf);
  const source = isThrall ? 'thrall-card' : 'cards';
  if (card.error) {
    rep.unlink(source, 'card is not valid, no Orc row made: ' + card.error, folder);
    return null;
  }
  if (!/^[a-z0-9-]{1,64}$/.test(folder)) {
    rep.unlink(source, 'folder name cannot be a lane_dir (no Orc row made)', folder);
    return null;
  }
  return { ...card, folder, mtime: Math.floor(fs.statSync(file).mtimeMs), isThrall };
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
  const find = db.prepare('SELECT id FROM orc WHERE lane_dir = ? OR letter = ? ORDER BY letter = ? DESC LIMIT 1');
  const findThrall = db.prepare("SELECT id FROM orc WHERE rank = 'thrall' AND retired_at IS NULL");
  for (const c of cards) {
    // An existing row is kept, by lane folder or by letter: never a second row for the same Orc.
    const existing = (c.isThrall ? findThrall.get() : null) ?? find.get(c.folder, c.orc, c.orc);
    if (existing) { rep.count('orc', false); ctx.cardOrc.set(c, existing.id); continue; }
    let name = c.lane === '' ? c.folder : c.lane;
    if (name.length > 120) { rep.unlink('cards', 'lane name longer than 120 characters (cut)', c.folder); name = name.slice(0, 120); }
    const id = newId(c.mtime);
    db.prepare('INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, ?, ?, ?, ?, ?)')
      .run(id, c.orc, c.folder, name, c.isThrall ? 'thrall' : 'orc', c.mtime);
    rep.count('orc', true);
    ctx.cardOrc.set(c, id);
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

function rankOf(rec) {
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
  const exists = db.prepare('SELECT 1 FROM session WHERE id = ?');
  const seat = db.prepare("SELECT id FROM session WHERE orc_id = ? AND node_id = ? AND retired_at IS NULL AND rank IN ('thrall', 'orc')");
  // SEATS ARE DECIDED BEFORE ANY INSERT, freshest session first: the schema allows one live seat per Orc
  // and PC, and the freshest session must hold it. Inserting a parent early (for its child) never claims
  // one, because the claim was made here, by freshness, not by the order the rows happen to be written in.
  const claimed = new Set();
  for (const row of order) {
    if (exists.get(row.id)) continue;
    const rec = row.rec;
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
      checked = firstNamed.get(m.key) ?? mergedAt ?? 0;
      rep.unlink('pr-cache', 'checked is not a time (the first ledger line naming it, else mergedAt, else 0, used)', key);
    }
    const sha = v.mergeSha ?? v.merge_sha ?? null;
    insertPr(ctx, m.key, m.repo, m.number, state, mergedAt, typeof sha === 'string' && SHA40.test(sha) ? sha : null, checked, null);
  }
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
  if (lane) return { kind: 'orc', orc: orcRef(ctx, lane[1]), unlinked: orcRef(ctx, lane[1]) === null };
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

function stepStatus(ctx) {
  const { db, rep } = ctx;
  for (const c of ctx.cards) {
    const orcId = ctx.cardOrc.get(c);
    const doing = c.doing;
    if (doing.length < 1 || doing.length > 120) {
      rep.unlink('cards', 'doing is empty or over 120 characters (no status row)', c.folder);
      continue;
    }
    // 'no' (any case) is "not blocked"; 'none' and every other sentence is kept as the words it is.
    const blocked = /^no$/i.test(c.blocked) || c.blocked === '' ? null : c.blocked;
    if (blocked !== null && blocked.length > 200) {
      rep.unlink('cards', 'blocked is over 200 characters (no status row)', c.folder);
      continue;
    }
    const r = appendHistory(db, 'orc_status', { orc_id: orcId, at: c.mtime, doing, blocked, backfill: 1 });
    rep.count('orc_status', r.inserted);
  }
}
