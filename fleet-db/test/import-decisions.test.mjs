// The decisions-store importer (fleet-db/import.mjs, source `decisions`; "Importer (phase 1c part 2a)" in
// planning/fleet-db-design.md), attacked. Every rule gets a journal that breaks it, written into a folder of
// its own under the temp folder: records of every kind, a parts question answered part by part, a message after
// closing, a message at the millisecond of its close, a gap, a duplicate id, a file named for no sequence, a
// schemaVersion 2, a requestHash that is not the record's, signing material that must not reach any column.
// Nothing real is read: the real store is never named.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { openStore } from '../store.mjs';
import { MIGRATIONS } from '../schema.mjs';
import { importFleet, parseTime, recomputeRequestHash } from '../import.mjs';
import { findProblems, main, parseImportArgs } from '../cli.mjs';
import { publishFromInput } from '../decisions-cli.mjs';

const dirs = [];
const handles = [];
after(() => {
  for (const db of handles) {
    try { db.close(); } catch { /* closed by the test */ }
  }
  for (const d of dirs) fs.rmSync(d, { recursive: true, force: true });
});

function tempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fleet-db-d-'));
  dirs.push(dir);
  return dir;
}

function fresh() {
  const file = path.join(tempDir(), 'fleet.db');
  const db = openStore(file);
  handles.push(db);
  return { db, file };
}

const rows = (db, sql, ...p) => db.prepare(sql).all(...p).map((r) => ({ ...r }));
const one = (db, sql, ...p) => { const r = db.prepare(sql).get(...p); return r ? { ...r } : undefined; };
const count = (db, table) => one(db, 'SELECT count(*) AS n FROM ' + table).n;
const unlinked = (report, reasonPart) => report.unlinked.find((u) => u.source === 'decisions' && u.reason.includes(reasonPart));
const addedOf = (report) => Object.fromEntries(Object.entries(report.tables).map(([k, v]) => [k, v.added]));
const DECISION_TABLES = ['question', 'question_event', 'answer', 'answer_extra', 'answer_route', 'answer_route_extra', 'decisions_read'];

// ---------------------------------------------------------------------------------------------------------
// Fixtures: cards (so the asking Orcs exist) and a journal

function writeCard(dir, folder, orc, lane) {
  fs.mkdirSync(path.join(dir, folder), { recursive: true });
  fs.writeFileSync(path.join(dir, folder, 'status.txt'), ['horde-orc-status 1', 'orc: ' + orc, 'lane: ' + lane, 'doing: working', 'finished: a part', 'blocked: no'].join('\n') + '\n');
}

function cardsOf() {
  const cards = path.join(tempDir(), 'orcs');
  writeCard(cards, 'decisions-page', 'F', 'Decisions page');
  writeCard(cards, 'form-fill', 'C', 'Form fill');
  const root = path.dirname(cards);
  fs.mkdirSync(path.join(root, 'thrall'));
  fs.writeFileSync(path.join(root, 'thrall', 'status.txt'), ['horde-orc-status 1', 'orc: M', 'lane: Thrall', 'doing: running', 'finished: a part', 'blocked: no'].join('\n') + '\n');
  return { cards, thrallCard: path.join(root, 'thrall', 'status.txt') };
}

const SIGNED = 'sig-abcdef0123456789abcdef0123456';
const EVIDENCE = 'ev-0123456789abcdef0123456789abcdef0123456789abcdef012345';
const sha = (s) => crypto.createHash('sha256').update(s, 'utf8').digest('hex');

// A record with the id and requestHash the store would give it; `at` may be a full text to put two records in one millisecond.
function rec(seq, kind, data, { actor = 'warchief', at = null, hash = true } = {}) {
  const sec = String(seq).padStart(2, '0');
  const r = { schemaVersion: 1, sequence: seq, id: seq.toString(16).padStart(32, '0'), kind, at: at ?? '2026-10-07T10:00:' + sec + '.1234567Z', actor, requestHash: '', data };
  r.requestHash = hash ? recomputeRequestHash(r) : 'f'.repeat(64);
  return r;
}

const Q = (title, extra = {}) => ({ title, kind: 'yes-no', options: [], parts: [], whatItIs: 'what it is', yesMeans: 'yes means', recommendation: 'yes.', group: 'G', groupNote: '', askedBy: 'Orc F', waiting: [], files: [], references: [], needsSecret: false, ...extra });

const JOURNAL = () => [
  rec(1, 'question-added', { number: 1, question: Q('Ship it?'), importance: 'high', blocks: 'all' }),
  rec(2, 'question-added', { number: 2, question: Q('Two parts?', { kind: 'parts', parts: ['(A) one?', '(B) two?'], askedBy: 'M (Thrall)' }), followsUp: 1 }),
  rec(3, 'question-added', { number: 3, question: Q('Needs a key?', { askedBy: 'somebody else entirely' }), needsPasskey: true }),
  rec(4, 'message-said', { number: 1, speaker: 'founder', route: 'phone', text: 'yes, ship', wordingVersion: 1, evidence: EVIDENCE, signedBy: SIGNED }, { actor: 'founder' }),
  rec(5, 'message-said', { number: 2, speaker: 'founder', route: 'window', text: 'a: yes', wordingVersion: 1, part: 'a' }, { actor: 'founder' }),
  rec(6, 'message-said', { number: 2, speaker: 'founder', route: 'window', text: 'b: no', wordingVersion: 1, part: 'b' }, { actor: 'founder' }),
  rec(7, 'message-said', { number: 2, speaker: 'founder', route: 'window', text: 'a: no, I changed my mind', wordingVersion: 1, part: 'a' }, { actor: 'founder' }),
  rec(8, 'answer-routed', { number: 1, answer: 4, purpose: 'answer', seat: 'orc', label: 'C', sessionId: '11111111-2222-4333-8444-555555555555', resolved: true, notice: '22222222-3333-4444-8555-666666666666', analyst: 'told it', note: 'seat found' }),
  rec(9, 'question-ranked', { number: 1, importance: 'low' }),
  rec(10, 'question-updated', { number: 2, changes: { group: 'New group' } }),
  rec(11, 'question-updated', { number: 2, changes: { title: 'Two parts, reworded?' } }),
  rec(12, 'message-said', { number: 2, speaker: 'founder', route: 'window', text: 'b: yes, to the old wording', wordingVersion: 1, part: 'b' }, { actor: 'founder' }),
  rec(13, 'question-closed', { number: 1, outcome: 'shipped', closedBySeat: 'warchief' }),
  rec(14, 'message-said', { number: 1, speaker: 'founder', route: 'window', text: 'too late', wordingVersion: 1 }, { actor: 'founder' }),
  rec(15, 'messages-read', { reader: 'warchief', upTo: 4 }),
  rec(16, 'message-said', { number: 3, speaker: 'founder', route: 'chat-recorded', text: 'yes (chat)', wordingVersion: 1 }, { actor: 'warchief' }),
  rec(17, 'question-acked', { number: 2, by: 'F', answer: 12 }, { actor: 'orc' }),
  rec(18, 'question-reopened', { number: 1, reason: 'asked again' }),
  rec(19, 'message-said', { number: 1, speaker: 'founder', route: 'window', text: 'yes again', wordingVersion: 1, asks: false }, { actor: 'founder' }),
  rec(20, 'answer-change-replied', { number: 1, by: 'C', answer: 4, reply: 'not-acted' }, { actor: 'orc' }),
  rec(21, 'question-added', { number: 4, question: Q('Same millisecond?') }),
  rec(22, 'message-said', { number: 4, speaker: 'founder', route: 'window', text: 'said in the millisecond of the close', wordingVersion: 1 }, { actor: 'founder', at: '2026-10-07T10:00:22.1234560Z' }),
  rec(23, 'question-closed', { number: 4, outcome: 'closed' }, { at: '2026-10-07T10:00:22.1234569Z' }),
];

function writeJournal(records, dir = path.join(tempDir(), 'decisions')) {
  fs.mkdirSync(dir, { recursive: true });
  for (const r of records) fs.writeFileSync(path.join(dir, String(r.sequence).padStart(10, '0') + '.json'), JSON.stringify(r));
  return dir;
}

function importAll(db, dir, opts = {}) {
  return importFleet(db, { ...cardsOf(), decisions: dir }, opts);
}

// ---------------------------------------------------------------------------------------------------------

test('the requestHash is recomputed as the store does: known answers from decisions/Rules.ps1 Get-HordeDecisionHash', () => {
  // These four values were made by PowerShell from the store's own function, not by this code.
  const say = { kind: 'message-said', actor: 'founder', data: { number: 3, speaker: 'founder', route: 'phone', text: 'caf\u00e9 "q" \\ x\nline', part: 'a', wordingVersion: 1, evidence: 'zz', signedBy: 'yy' } };
  assert.equal(recomputeRequestHash(say), 'ccecd013c37be8c2bcc493ab78fbd2788458cf7520e4c7e89d38a1c992c02abb', 'evidence and signedBy are not hashed; non-ASCII is hashed as UTF-8');
  const add = { kind: 'question-added', actor: 'warchief', data: { number: 9, question: { title: 'Ship it?', kind: 'yes-no', options: [], parts: [], group: 'G', askedBy: 'Orc F' }, importance: 'high' } };
  assert.equal(recomputeRequestHash(add), '01e4d549ea33344693182a3ae43d0dadc5a60ca794cca8978561c1378c454e33', 'an add hashes number 0: its request names none');
  assert.equal(recomputeRequestHash({ kind: 'messages-read', actor: 'warchief', data: { reader: 'warchief', upTo: 5 } }), 'f9f567be4855e03aac76a0e236405538ff51acbe8d862c5f190bd6f269a0660d');
  assert.equal(recomputeRequestHash({ kind: 'question-closed', actor: 'warchief', data: { number: 2, outcome: 'done', closedBySeat: 'warchief' } }), '6302f290540699478405b5a27d2f1350a7cd04785b52a1c792744380cd098ee8', 'closedBySeat is added after the hash');
  assert.equal(recomputeRequestHash({ kind: 'nonsense', actor: 'x', data: {} }), null);
});

test('times: seven fraction digits read to UTC milliseconds', () => {
  assert.equal(parseTime('2026-10-07T16:26:16.9667002Z'), Date.UTC(2026, 9, 7, 16, 26, 16, 966));
});

test('every kind is imported to the rows the schema has, with the question fields it holds', () => {
  const { db } = fresh();
  const dir = writeJournal(JOURNAL());
  const r = importAll(db, dir);
  assert.deepEqual(DECISION_TABLES.map((t) => [t, r.tables[t].added]), [
    ['question', 4], ['question_event', 8], ['answer', 9], ['answer_extra', 9], ['answer_route', 1], ['answer_route_extra', 1], ['decisions_read', 1],
  ]);
  assert.equal(unlinked(r, 'requestHash'), undefined, 'every fixture hash is the recomputed one');
  const f = one(db, "SELECT id FROM orc WHERE letter = 'F'").id;
  const m = one(db, "SELECT id FROM orc WHERE rank = 'thrall'").id;

  const q1 = one(db, 'SELECT * FROM question WHERE number = 1');
  assert.equal(q1.title, 'Ship it?');
  assert.equal(q1.kind, 'yes-no');
  assert.equal(q1.body, 'what it is', 'whatItIs is the body');
  assert.equal(q1.yes_means, 'yes means');
  assert.equal(q1.recommendation, 'yes.');
  assert.equal(q1.group_name, 'G');
  assert.equal(q1.importance, 'high');
  assert.equal(q1.blocks, 'all');
  assert.equal(q1.asked_by_orc_id, f, 'askedBy Orc F is the Orc row');
  assert.equal(q1.asked_by_text, null, 'and no text beside it');
  assert.equal(q1.task_id, null);
  assert.equal(q1.backfill, 1);
  assert.equal(q1.needs_passkey, 0);
  assert.equal(q1.decisions_seq, 1);
  assert.equal(q1.asked_at, Date.UTC(2026, 9, 7, 10, 0, 1, 123), 'the seven-digit time to milliseconds');
  const q2 = one(db, 'SELECT * FROM question WHERE number = 2');
  assert.equal(q2.asked_by_orc_id, m, 'M (Thrall) is the Thrall row');
  assert.equal(q2.follows_up_id, q1.id, 'followsUp is the earlier question');
  assert.deepEqual(JSON.parse(q2.detail_json).parts, ['(A) one?', '(B) two?']);
  assert.equal(q2.importance, null, 'a question that names no importance has none: the default is said by saying nothing');
  const q3 = one(db, 'SELECT * FROM question WHERE number = 3');
  assert.equal(q3.asked_by_orc_id, null);
  assert.equal(q3.asked_by_text, 'somebody else entirely', 'an asker that names no Orc is kept as text');
  assert.equal(q3.needs_passkey, 1);
  assert.ok(unlinked(r, 'askedBy names no Orc row'));
  assert.equal(unlinked(r, 'question names no task').count, 4);

  const kinds = rows(db, 'SELECT kind, data_json, decisions_seq FROM question_event ORDER BY decisions_seq');
  assert.deepEqual(kinds.map((k) => k.kind), ['ranked', 'updated', 'updated', 'closed', 'acked', 'reopened', 'change-reply', 'closed']);
  assert.deepEqual(JSON.parse(kinds[3].data_json), { actor: 'warchief', outcome: 'shipped', closedBySeat: 'warchief' });
  assert.deepEqual(JSON.parse(kinds[1].data_json).changes, { group: 'New group' });
  assert.equal(JSON.parse(kinds[4].data_json).answer, 12);

  const ans = (seq) => one(db, 'SELECT * FROM answer WHERE decisions_seq = ?', seq);
  assert.equal(ans(4).speaker, 'founder');
  assert.equal(ans(4).route, 'phone');
  assert.equal(ans(4).wording_version, 1);
  assert.equal(ans(4).asks, 1);
  assert.equal(ans(19).asks, 0, 'a note asks nothing');
  assert.equal(ans(5).part, 'A', 'a part letter is kept as the schema writes it: one capital');
  assert.ok(unlinked(r, 'part letter written in lower case'));

  const route = one(db, 'SELECT * FROM answer_route');
  assert.equal(route.answer_id, ans(4).id);
  assert.equal(route.seat, 'orc');
  assert.equal(route.session_id, null, 'a session fleet.db has no row for is no session');
  assert.equal(route.resolved, 0, 'so the route cannot be resolved (the CHECK)');
  const rx = one(db, 'SELECT * FROM answer_route_extra');
  assert.deepEqual([rx.purpose, rx.label, rx.notice, rx.analyst, rx.note, rx.source_resolved], ['answer', 'C', '22222222-3333-4444-8555-666666666666', 'told it', 'seat found', 1]);
  assert.ok(unlinked(r, 'route names a session fleet.db has no row for'));
  assert.ok(unlinked(r, 'route says resolved but its session is not a row'));

  assert.deepEqual(one(db, 'SELECT reader, up_to_seq, decisions_seq FROM decisions_read'), { reader: 'warchief', up_to_seq: 4, decisions_seq: 15 });
  assert.deepEqual(findProblems(db), []);
});

test('a question answered part by part: one answer per part, a changed answer replaces the earlier answer to its part only', () => {
  const { db } = fresh();
  importAll(db, writeJournal(JOURNAL()));
  const ans = (seq) => one(db, 'SELECT id, part, replaces_answer_id FROM answer WHERE decisions_seq = ?', seq);
  assert.deepEqual([ans(5).part, ans(6).part, ans(7).part], ['A', 'B', 'A']);
  assert.equal(ans(5).replaces_answer_id, null);
  assert.equal(ans(6).replaces_answer_id, null, 'part b does not replace part a');
  assert.equal(ans(7).replaces_answer_id, ans(5).id, 'his second answer to part a replaces his first');
  assert.equal(ans(12).replaces_answer_id, ans(6).id, 'and his second answer to part b replaces his first');
  assert.equal(ans(19).replaces_answer_id, null, 'a note replaces nothing');
});

test('a message after closing is reported as the rules fold it, and answer_now agrees with the fold', () => {
  const { db } = fresh();
  const r = importAll(db, writeJournal(JOURNAL()));
  const now = (seq) => one(db, 'SELECT n.open_at_arrival, n.authorizes FROM answer_now n JOIN answer a ON a.id = n.id WHERE a.decisions_seq = ?', seq);
  assert.equal(now(14).open_at_arrival, 0, 'said after the close of question 1: arrived after closing');
  assert.equal(now(19).open_at_arrival, 1, 'said after the reopen: open again');
  assert.equal(now(4).open_at_arrival, 1);
  // The only differences: the message in the millisecond of its close (the schema counts a close in the same
  // millisecond as before it), and the passkey question's chat words (the rules do not count them, the schema
  // does not either) - checked below. Message 14 is NOT among the differences.
  const diff = r.unlinked.filter((u) => u.source === 'decisions' && /answer_now says/.test(u.reason));
  assert.equal(diff.length, 1);
  assert.match(diff[0].reason, /rules say the message arrived while open; answer_now says it arrived after closing/);
  assert.deepEqual(diff[0].examples, ['record 22']);
  assert.equal(now(22).open_at_arrival, 0);
});

test('a message said to an earlier wording is counted, and an ack closes its question with no closed event made up', () => {
  const { db } = fresh();
  const r = importAll(db, writeJournal(JOURNAL()));
  assert.equal(unlinked(r, 'said to an earlier wording').count, 1);
  assert.deepEqual(unlinked(r, 'said to an earlier wording').examples, ['record 12']);
  assert.equal(unlinked(r, 'question-acked closes'), undefined, 'the ack is no longer a reported difference: the views close on it');
  assert.equal(one(db, 'SELECT n.state FROM question_now n WHERE n.number = 2').state, 'closed', 'question 2 has an ack and no closed event, and reads closed');
  assert.equal(one(db, "SELECT count(*) AS n FROM question_event e JOIN question q ON q.id = e.question_id WHERE q.number = 2 AND e.kind = 'closed'").n, 0);
  assert.equal(count(db, 'question_event'), 8);
});

test('a passkey question: chat words are not an answer in the rules, an unsigned message is not in the schema, and the sealed key id is not the key id', () => {
  const { db } = fresh();
  importAll(db, writeJournal(JOURNAL()));
  const a16 = one(db, 'SELECT n.authorizes FROM answer_now n JOIN answer a ON a.id = n.id WHERE a.decisions_seq = 16');
  assert.equal(a16.authorizes, 0);
  const a4 = one(db, 'SELECT signed_by FROM answer WHERE decisions_seq = 4');
  assert.equal(a4.signed_by, sha(SIGNED), 'only the sha256 of the key id is kept');
  assert.equal(one(db, 'SELECT evidence_present FROM answer_extra x JOIN answer a ON a.id = x.answer_id WHERE a.decisions_seq = 4').evidence_present, 1);
  assert.equal(one(db, 'SELECT evidence_present FROM answer_extra x JOIN answer a ON a.id = x.answer_id WHERE a.decisions_seq = 5').evidence_present, 0);
});

test('signing material is in no column of any table, and not in the report', () => {
  const { db } = fresh();
  const r = importAll(db, writeJournal(JOURNAL()));
  const names = rows(db, "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").map((x) => x.name);
  let scanned = 0;
  for (const t of names) {
    for (const c of rows(db, 'SELECT name FROM pragma_table_info(?) WHERE type = ?', t, 'TEXT')) {
      scanned++;
      for (const secret of [SIGNED, EVIDENCE]) {
        const hit = one(db, 'SELECT count(*) AS n FROM "' + t + '" WHERE instr("' + c.name + '", ?) > 0', secret).n;
        assert.equal(hit, 0, t + '.' + c.name + ' holds signing material');
      }
    }
  }
  assert.ok(scanned > 60, 'CONTROL: many text columns were scanned (' + scanned + ')');
  const text = JSON.stringify(r);
  assert.ok(!text.includes(SIGNED) && !text.includes(EVIDENCE));
  // CONTROL: the scan can see a value that is there.
  assert.equal(one(db, 'SELECT count(*) AS n FROM answer WHERE instr(text, ?) > 0', 'yes, ship').n, 1);
});

test('a second import adds 0 rows to every table, and a dry run adds none and says the same as the real run', () => {
  const { db } = fresh();
  const dir = writeJournal(JOURNAL());
  const cards = cardsOf();
  const dry = importFleet(db, { ...cards, decisions: dir }, { dryRun: true });
  for (const t of [...DECISION_TABLES, 'orc']) assert.equal(count(db, t), 0, t + ' after a dry run');
  const real = importFleet(db, { ...cards, decisions: dir });
  assert.deepEqual(addedOf(dry), addedOf(real), 'the dry run reports what the real run adds');
  assert.deepEqual(dry.unlinked, real.unlinked);
  const before = Object.fromEntries(DECISION_TABLES.map((t) => [t, count(db, t)]));
  const again = importFleet(db, { ...cards, decisions: dir });
  for (const [t, c] of Object.entries(again.tables)) assert.equal(c.added, 0, t + ' added on the second import');
  for (const t of DECISION_TABLES) assert.equal(again.tables[t].existing, before[t], t + ' is all already there');
  assert.deepEqual(Object.fromEntries(DECISION_TABLES.map((t) => [t, count(db, t)])), before);
  assert.deepEqual(findProblems(db), []);
});

test('a failure leaves nothing: a record the database refuses undoes every row before it', () => {
  const { db } = fresh();
  const records = JOURNAL();
  records[18].data.text = 'broken \ud800 text';
  const dir = writeJournal(records);
  assert.throws(() => importAll(db, dir), /lone surrogate/);
  for (const t of [...DECISION_TABLES, 'orc', 'node']) assert.equal(count(db, t), 0, t + ' after the failure');
});

test('a gap, a duplicate id, a file named for no sequence and a schemaVersion 2 each refuse the source, whole', () => {
  const refuse = (mutate, reason) => {
    const { db } = fresh();
    const records = JOURNAL();
    const dir = writeJournal(records);
    mutate(dir, records);
    const r = importAll(db, dir);
    for (const t of DECISION_TABLES) assert.equal(count(db, t), 0, reason + ': ' + t + ' stays empty');
    assert.ok(count(db, 'orc') > 0, reason + ': the other sources are still imported');
    const u = unlinked(r, 'source refused, nothing imported from it');
    assert.ok(u && u.reason.includes(reason), reason + ' is named: ' + JSON.stringify(r.unlinked.filter((x) => x.source === 'decisions')));
    assert.equal(u.count, 1);
  };
  refuse((dir) => fs.rmSync(path.join(dir, '0000000007.json')), 'a gap in the sequence: record 7 is not there');
  refuse((dir, records) => {
    const dup = { ...records[4], sequence: 5, id: records[3].id };
    fs.writeFileSync(path.join(dir, '0000000005.json'), JSON.stringify(dup));
  }, 'two records share one id');
  refuse((dir) => fs.renameSync(path.join(dir, '0000000009.json'), path.join(dir, '0000000090.json')), 'a file name is not its record');
  refuse((dir) => fs.renameSync(path.join(dir, '0000000009.json'), path.join(dir, 'nine.json')), 'a file name is not a ten-digit sequence');
  refuse((dir, records) => fs.writeFileSync(path.join(dir, '0000000003.json'), JSON.stringify({ ...records[2], schemaVersion: 2 })), 'a record has a schemaVersion other than 1');
  refuse((dir) => fs.writeFileSync(path.join(dir, '0000000003.json'), '{not json'), 'a record file is not a JSON object');
  refuse((dir, records) => fs.writeFileSync(path.join(dir, '0000000003.json'), JSON.stringify({ ...records[2], id: 'NOT-HEX' })), 'a record id is not 32 lower-case hex');
});

test('a file that is not a record is ignored and said so; an empty store imports nothing', () => {
  const { db } = fresh();
  const dir = writeJournal(JOURNAL());
  fs.writeFileSync(path.join(dir, '0000000024.json.tmp'), 'half written');
  const r = importAll(db, dir);
  assert.equal(count(db, 'question'), 4);
  assert.equal(unlinked(r, 'file is not a record').examples[0], '0000000024.json.tmp');
  const { db: db2 } = fresh();
  const empty = importAll(db2, writeJournal([]));
  assert.equal(count(db2, 'question'), 0);
  assert.equal(empty.unlinked.filter((u) => u.source === 'decisions').length, 0);
});

test('a requestHash that is not the one recomputed is reported by record, and the record is still imported', () => {
  const { db } = fresh();
  const records = JOURNAL();
  records[3] = rec(4, 'message-said', records[3].data, { actor: 'founder', hash: false });
  records[8] = { ...records[8], requestHash: '' };
  const r = importAll(db, writeJournal(records));
  const u = unlinked(r, 'requestHash is not the one recomputed');
  assert.equal(u.count, 2);
  assert.deepEqual(u.examples, ['record 4', 'record 9']);
  assert.equal(count(db, 'answer'), 9);
  assert.equal(count(db, 'question_event'), 8);
});

test('records the schema has no place for are counted, never dropped in silence', () => {
  const { db } = fresh();
  const records = JOURNAL();
  records.push(rec(24, 'question-vanished', { number: 1 }, { hash: false }));
  records.push(rec(25, 'message-said', { number: 99, speaker: 'founder', route: 'window', text: 'about nothing' }, { actor: 'founder' }));
  records.push(rec(26, 'answer-routed', { number: 1, answer: 77, purpose: 'answer', seat: 'orc', resolved: false }));
  const bad = rec(27, 'question-added', { number: 5, question: Q('Bad time') });
  bad.at = 'last tuesday';
  records.push(bad);
  const r = importAll(db, writeJournal(records));
  assert.equal(unlinked(r, 'kind question-vanished has no place').count, 1);
  assert.equal(unlinked(r, 'about a question the journal never added').count, 1);
  assert.equal(unlinked(r, 'names a message the journal does not hold').count, 1);
  assert.equal(unlinked(r, 'record time is not readable').count, 1);
  assert.equal(count(db, 'question'), 4);
});

test('a route to a session fleet.db knows is resolved, with that session', () => {
  const { db } = fresh();
  const sessions = path.join(tempDir(), 'sessions');
  fs.mkdirSync(sessions);
  const sid = '11111111-2222-4333-8444-555555555555';
  fs.writeFileSync(path.join(sessions, sid + '.json'), JSON.stringify({ owner: 'C', label: 'C', role: 'orchestrator', firstSeen: '2026-10-05T10:00:00.0000000Z', lastSeen: '2026-10-06T10:00:00.0000000Z' }));
  const r = importFleet(db, { ...cardsOf(), registry: sessions, decisions: writeJournal(JOURNAL()) });
  const route = one(db, 'SELECT session_id, resolved FROM answer_route');
  assert.deepEqual(route, { session_id: sid, resolved: 1 });
  assert.equal(unlinked(r, 'route names a session'), undefined);
});

test('publish: a list naming an imported open question is accepted, one naming a question that was never imported is refused', () => {
  const { db } = fresh();
  importAll(db, writeJournal(JOURNAL()));
  const input = { who: { letter: 'F' }, sessionId: 'none', items: [{ questionNumber: 3, text: 'Needs a key?', recommendation: 'yes' }, { text: 'a line with no question' }] };
  const ok = publishFromInput(db, input);
  assert.equal(ok.count, 2);
  assert.equal(ok.unchanged, false);
  const line = one(db, 'SELECT q.number FROM decisions_live_item i JOIN question q ON q.id = i.question_id');
  assert.equal(line.number, 3);
  assert.throws(() => publishFromInput(db, { who: { letter: 'F' }, items: [{ questionNumber: 31, text: 'never imported' }] }), /question 31, which is not in the decisions store/);
  assert.deepEqual(findProblems(db), []);
});

test('horde db import --decisions: the flag is read, needs a path, and imports through the command line entry', () => {
  assert.deepEqual(parseImportArgs(['--decisions', 'D:\\x\\decisions']), { sources: { decisions: 'D:\\x\\decisions' }, dryRun: false });
  assert.throws(() => parseImportArgs(['--decisions']), /--decisions needs a path/);
  assert.throws(() => parseImportArgs(['--decisions', 'a', '--decisions', 'b']), /given twice/);
  const home = tempDir();
  const env = { HORDE_HOME: home };
  const lines = [];
  const run = (argv) => { lines.length = 0; return { code: main(argv, env, (s) => lines.push(s), (s) => lines.push('ERR ' + s)), out: lines.join('\n') }; };
  assert.equal(run(['init']).code, 0);
  const cards = cardsOf();
  const dir = writeJournal(JOURNAL());
  const first = run(['import', '--cards', cards.cards, '--thrall-card', cards.thrallCard, '--decisions', dir]);
  assert.equal(first.code, 0, first.out);
  assert.match(first.out, /^question: 4 added, 0 already there$/m);
  assert.match(first.out, /^answer: 9 added, 0 already there$/m);
  assert.match(first.out, /^decisions: question names no task \(task_id empty, backfill\): 4 \(e\.g\. question 1/m);
  const second = run(['import', '--cards', cards.cards, '--thrall-card', cards.thrallCard, '--decisions', dir]);
  assert.match(second.out, /^question: 0 added, 4 already there$/m);
  assert.equal(run(['check']).code, 0);
});

test('migration 4: a version 3 file with a question keeps it, gains the new columns empty, and the new tables refuse an update or a delete', () => {
  const file = path.join(tempDir(), 'fleet.db');
  const raw = new DatabaseSync(file);
  for (let i = 0; i < 3; i++) raw.exec(MIGRATIONS[i]);
  raw.exec('PRAGMA user_version = 3');
  raw.prepare("INSERT INTO question (id, number, kind, title, asked_at, backfill) VALUES ('01J0000000000000000000000Q', 7, 'yes-no', 'old', 5, 1)").run();
  raw.close();
  const db = openStore(file);
  handles.push(db);
  const q = one(db, 'SELECT title, asked_by_text, yes_means, recommendation, group_name, group_note, importance, blocks, detail_json FROM question WHERE number = 7');
  assert.deepEqual(q, { title: 'old', asked_by_text: null, yes_means: null, recommendation: null, group_name: null, group_note: null, importance: null, blocks: null, detail_json: null });
  db.prepare("INSERT INTO decisions_read (id, reader, up_to_seq, at, decisions_seq) VALUES ('01J0000000000000000000000R', 'warchief', 3, 1, 3)").run();
  assert.throws(() => db.prepare("UPDATE decisions_read SET up_to_seq = 4").run(), /append-only/);
  assert.throws(() => db.prepare('DELETE FROM decisions_read').run(), /append-only/);
  assert.deepEqual(findProblems(db), []);
});

test('a message after an ack arrived after closing, in answer_now and in the fold (no difference reported)', () => {
  const { db } = fresh();
  const records = [
    rec(1, 'question-added', { number: 1, question: Q('Acked?') }),
    rec(2, 'message-said', { number: 1, speaker: 'founder', route: 'window', text: 'yes', wordingVersion: 1 }, { actor: 'founder' }),
    rec(3, 'question-acked', { number: 1, by: 'F', answer: 2 }, { actor: 'orc' }),
    rec(4, 'message-said', { number: 1, speaker: 'founder', route: 'window', text: 'after the ack', wordingVersion: 1 }, { actor: 'founder' }),
  ];
  const r = importAll(db, writeJournal(records));
  assert.equal(one(db, 'SELECT state FROM question_now').state, 'closed');
  const at = (seq) => one(db, 'SELECT n.open_at_arrival FROM answer_now n JOIN answer a ON a.id = n.id WHERE a.decisions_seq = ?', seq).open_at_arrival;
  assert.deepEqual([at(2), at(4)], [1, 0]);
  assert.equal(r.unlinked.filter((u) => /answer_now says/.test(u.reason)).length, 0);
  assert.equal(count(db, 'question_event'), 1);
});

test('migration 4 on a version 3 file: a question already there gets only its empty new columns filled, never overwritten', () => {
  const file = path.join(tempDir(), 'fleet.db');
  const raw = new DatabaseSync(file);
  for (let i = 0; i < 3; i++) raw.exec(MIGRATIONS[i]);
  raw.exec('PRAGMA user_version = 3');
  raw.prepare("INSERT INTO question (id, number, kind, title, asked_at, backfill) VALUES ('01J0000000000000000000000Q', 1, 'yes-no', 'old title', 5, 1)").run();
  raw.close();
  const db = openStore(file);
  handles.push(db);
  db.prepare("UPDATE question SET importance = 'kept', yes_means = 'my own words'").run();
  const r = importAll(db, writeJournal(JOURNAL()));
  const q = one(db, 'SELECT title, importance, yes_means, recommendation, group_name, blocks, detail_json, asked_by_text FROM question WHERE number = 1');
  assert.equal(q.title, 'old title', 'columns that existed are left alone');
  assert.equal(q.importance, 'kept', 'a value that is there is not overwritten (the journal says high)');
  assert.equal(q.yes_means, 'my own words');
  assert.equal(q.recommendation, 'yes.', 'an empty column is filled');
  assert.equal(q.group_name, 'G');
  assert.equal(q.blocks, 'all');
  assert.ok(q.detail_json.includes('"parts"'));
  assert.equal(r.tables.question.existing, 1);
  assert.equal(r.tables.question.added, 3);
  assert.equal(unlinked(r, 'question names no task').count, 3, 'and no report for the question that was already there');
  assert.deepEqual(findProblems(db), []);
});

test('a key no importer knows is reported by kind and key, with counts, and the record is still imported', () => {
  const { db } = fresh();
  const records = JOURNAL();
  records[0] = rec(1, 'question-added', { number: 1, question: Q('Ship it?', { colour: 'red' }), importance: 'high', blocks: 'all', mood: 'good' });
  records[3] = rec(4, 'message-said', { ...records[3].data, mood: 'ok' }, { actor: 'founder' });
  records[4] = rec(5, 'message-said', { ...records[4].data, mood: 'ok' }, { actor: 'founder' });
  const bad = rec(8, 'answer-routed', { ...records[7].data });
  bad.extra = 1;
  records[7] = bad;
  const r = importAll(db, writeJournal(records));
  const key = (s) => unlinked(r, s);
  assert.equal(key('unknown key data.mood in message-said records').count, 2);
  assert.deepEqual(key('unknown key data.mood in message-said records').examples, ['record 4', 'record 5']);
  assert.equal(key('unknown key data.mood in question-added records').count, 1);
  assert.equal(key('unknown key data.question.colour in question-added records').count, 1);
  assert.equal(key('unknown key envelope.extra in answer-routed records').count, 1);
  assert.equal(count(db, 'question'), 4);
  // CONTROL: the clean fixture reports none.
  const { db: db2 } = fresh();
  assert.equal(importAll(db2, writeJournal(JOURNAL())).unlinked.filter((u) => u.reason.includes('unknown key')).length, 0);
});
