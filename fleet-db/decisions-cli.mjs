// The decisions lists as `horde decisions publish` and `horde decisions published` use them:
//   node decisions-cli.mjs publish <input.json>           publish one Orc's whole live list
//   node decisions-cli.mjs published [--orc X] [--json]   read the live lists back from the views
// Run by decisions/Publish.ps1. Exit codes: 0 done, 1 refused or failed, 2 no home.
//
// WHO PUBLISHES IS NOT DECIDED HERE: the PowerShell side proves the calling session and hands in its Orc
// letter (or "thrall") and session id in the input file; this side only finds that Orc in fleet.db.
// THE LIST ITSELF is written by write.mjs publishDecisions (the one write path); this file adds only the
// question number -> question id step, which needs fleet.db's question table.
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dbPathFor, openStore } from './store.mjs';
import { publishDecisions } from './write.mjs';

export const VERBS = ['publish', 'published'];

const INPUT_KEYS = ['who', 'sessionId', 'items'];
const WHO_KEYS = ['letter', 'thrall'];
const ITEM_KEYS = ['questionNumber', 'text', 'recommendation', 'importance', 'blocks'];

function refuse(message) {
  const e = new Error(message);
  e.refusal = true;
  return e;
}

function onlyKeys(obj, allowed, where) {
  for (const k of Object.keys(obj)) if (!allowed.includes(k)) throw refuse(where + ' has no field ' + k);
}

// The Orc row of the proven publisher: by lane letter, or the standing Thrall.
function findOrc(db, who) {
  if (who === null || typeof who !== 'object' || Array.isArray(who)) throw refuse('the input needs who');
  onlyKeys(who, WHO_KEYS, 'who');
  let row;
  let name;
  if (who.thrall === true) {
    row = db.prepare("SELECT id, letter, retired_at FROM orc WHERE rank = 'thrall' AND retired_at IS NULL").get();
    name = 'the Thrall';
  } else if (typeof who.letter === 'string' && /^[A-Z][A-Z0-9]{0,3}$/.test(who.letter)) {
    row = db.prepare('SELECT id, letter, retired_at FROM orc WHERE letter = ?').get(who.letter);
    name = 'Orc ' + who.letter;
  } else {
    throw refuse('who must be an Orc letter or the Thrall');
  }
  if (!row) throw refuse('fleet.db has no row for ' + name + ', so it has nowhere to publish a list');
  if (row.retired_at !== null) throw refuse(name + ' is retired in fleet.db');
  return row;
}

// Build and publish. input: { who: {letter}|{thrall:true}, sessionId, items: [{questionNumber, text, ...}] }.
export function publishFromInput(db, input, now = Date.now()) {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) throw refuse('the input must be an object');
  onlyKeys(input, INPUT_KEYS, 'the input');
  if (!Array.isArray(input.items)) throw refuse('items must be a list (an empty one is a list)');
  const orc = findOrc(db, input.who);
  // A session fleet.db has not recorded is stored as no session: the column is a foreign key, and a
  // publish must not fail for want of a row another lane writes.
  let sessionId = null;
  if (typeof input.sessionId === 'string' && db.prepare('SELECT 1 FROM session WHERE id = ?').get(input.sessionId)) sessionId = input.sessionId;
  const byNumber = db.prepare('SELECT id FROM question WHERE number = ?');
  const items = input.items.map((it, i) => {
    if (it === null || typeof it !== 'object' || Array.isArray(it)) throw refuse('item ' + (i + 1) + ' must be an object');
    onlyKeys(it, ITEM_KEYS, 'item ' + (i + 1));
    let questionId = null;
    if (it.questionNumber !== undefined && it.questionNumber !== null) {
      if (!Number.isSafeInteger(it.questionNumber) || it.questionNumber < 1) throw refuse('item ' + (i + 1) + ' questionNumber must be a question number');
      const q = byNumber.get(it.questionNumber);
      if (!q) throw refuse('item ' + (i + 1) + ' names question ' + it.questionNumber + ', which is not in the decisions store');
      questionId = q.id;
    }
    return { question_id: questionId, text: it.text, recommendation: it.recommendation ?? null, importance: it.importance ?? null, blocks: it.blocks ?? null };
  });
  try {
    const r = publishDecisions(db, { orcId: orc.id, sessionId, publishedAt: now, items });
    return { ...r, count: items.length };
  } catch (e) {
    throw refuse(String(e.message).replace(/^publishDecisions: /, ''));
  }
}

// The live lists, from the views, with the question number beside each question id.
export function readPublished(db, letter = null) {
  const lives = db.prepare(`SELECT l.id, l.orc_id, l.published_at, l.confirmed_at, l.item_count, o.letter, o.rank FROM decisions_live l
    JOIN orc o ON o.id = l.orc_id ORDER BY o.rank DESC, o.letter`).all();
  const lines = db.prepare(`SELECT i.position, q.number AS question_number, i.text, i.recommendation, i.importance, i.blocks
    FROM decisions_live_item i LEFT JOIN question q ON q.id = i.question_id WHERE i.snapshot_id = ? ORDER BY i.position`);
  return lives.filter((l) => letter === null || l.letter === letter).map((l) => ({
    orc: l.letter, snapshot: l.id, publishedAt: new Date(l.published_at).toISOString(), confirmedAt: new Date(l.confirmed_at).toISOString(), count: l.item_count,
    items: lines.all(l.id).map((r) => ({ position: r.position, questionNumber: r.question_number, text: r.text, recommendation: r.recommendation, importance: r.importance, blocks: r.blocks })),
  }));
}

function ascii(json) {
  return json.replace(/[^\x20-\x7E]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
}

function plural(n) {
  return n + (n === 1 ? ' item' : ' items');
}

export function main(argv, env = process.env, out = (s) => process.stdout.write(s + '\n'), err = (s) => process.stderr.write(s + '\n')) {
  const verb = argv[0];
  if (!VERBS.includes(verb)) {
    err('usage: decisions-cli.mjs publish <input.json> | published [--orc X] [--json]');
    return 1;
  }
  let file;
  try {
    file = dbPathFor(env.HORDE_HOME);
  } catch (e) {
    err('fleet.db: ' + e.message);
    return 2;
  }
  let db;
  try {
    if (verb === 'publish') {
      if (argv.length !== 2) { err('usage: decisions-cli.mjs publish <input.json>'); return 1; }
      const input = JSON.parse(fs.readFileSync(argv[1], 'utf8'));
      db = openStore(file);
      const r = publishFromInput(db, input);
      out(r.unchanged ? 'unchanged, confirmed ' + new Date(r.confirmedAt).toISOString() + ' (snapshot ' + r.id + ')' : 'published ' + plural(r.count) + ' (snapshot ' + r.id + ')');
      return 0;
    }
    let letter = null;
    let asJson = false;
    for (let i = 1; i < argv.length; i++) {
      if (argv[i] === '--json') asJson = true;
      else if (argv[i] === '--orc' && i + 1 < argv.length) letter = argv[++i];
      else { err('usage: decisions-cli.mjs published [--orc X] [--json]'); return 1; }
    }
    if (!fs.existsSync(file)) throw refuse('fleet.db does not exist yet at ' + file + '; run horde db init');
    db = openStore(file, { readOnly: true });
    const lists = readPublished(db, letter);
    if (asJson) { out(ascii(JSON.stringify({ lists }))); return 0; }
    if (lists.length === 0) { out(letter === null ? 'no decisions list has been published' : 'Orc ' + letter + ' has not published a decisions list'); return 0; }
    for (const l of lists) {
      out(l.orc + ': ' + plural(l.count) + ', published ' + l.publishedAt + ', confirmed ' + l.confirmedAt + ' (snapshot ' + l.snapshot + ')');
      for (const it of l.items) {
        const extra = [it.questionNumber === null ? '' : 'question ' + it.questionNumber, it.importance === null ? '' : 'importance ' + it.importance, it.blocks === null ? '' : 'blocks ' + it.blocks].filter((s) => s !== '');
        out('  ' + it.position + '. ' + it.text + (extra.length ? ' [' + extra.join(', ') + ']' : ''));
        if (it.recommendation !== null) out('     recommendation: ' + it.recommendation);
      }
    }
    return 0;
  } catch (e) {
    err(e.refusal ? 'refused: ' + e.message : 'fleet.db: ' + e.message);
    return 1;
  } finally {
    if (db) db.close();
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = main(process.argv.slice(2));
}
