// Seeds and changes the published lists in a test Horde home's fleet.db, for the suites that follow a list to
// the founder's phone (test/test-relay-decisions-published.ps1, surfaces/pwa/test/test-pwa-browser.ps1).
//   node phone-published-seed.mjs seed <home>                      the Thrall M, Orcs F and G, a task and questions 1 to 3
//   node phone-published-seed.mjs publish <home> <thrall|F> <items.json>   publish a list ([{questionNumber, text, ...}])
//   node phone-published-seed.mjs confirm <home> <thrall|F> <items.json>   the same list again: a confirm, no new snapshot
// Only ever run against a folder a suite made; seed refuses a home that already holds a fleet.db. Publishing goes
// through fleet-db/decisions-cli.mjs publishFromInput, the one path `horde decisions publish` uses.
import fs from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const { openStore, dbPathFor } = await import(pathToFileURL(path.join(root, 'fleet-db', 'store.mjs')).href);
const { ulid } = await import(pathToFileURL(path.join(root, 'fleet-db', 'ids.mjs')).href);
const { publishFromInput } = await import(pathToFileURL(path.join(root, 'fleet-db', 'decisions-cli.mjs')).href);

const [, , verb, home, who, itemsFile] = process.argv;
const file = dbPathFor(home);

if (verb === 'seed') {
  if (fs.existsSync(file)) throw new Error('refusing to seed a home that already has a fleet.db');
  const db = openStore(file);
  const T0 = Date.UTC(2026, 9, 20, 12, 0, 0);
  let n = 0;
  const id = () => ulid(T0 + n++);
  const orc = db.prepare('INSERT INTO orc (id, letter, lane_dir, name, rank, created_at) VALUES (?, ?, ?, ?, ?, ?)');
  orc.run(id(), 'M', 'thrall', 'Thrall', 'thrall', T0);
  orc.run(id(), 'F', 'decisions-page', 'Decisions page', 'orc', T0);
  orc.run(id(), 'G', 'other-lane', 'Other lane', 'orc', T0);
  const task = id();
  db.prepare("INSERT INTO task (id, key, title, source, created_at) VALUES (?, 'T-0001', 'a task', 'founder', ?)").run(task, T0);
  const q = db.prepare("INSERT INTO question (id, number, task_id, kind, title, asked_at) VALUES (?, ?, ?, 'yes-no', 'ok?', ?)");
  for (const number of [1, 2, 3]) q.run(id(), number, task, T0);
  db.close();
} else if (verb === 'publish' || verb === 'confirm') {
  const db = openStore(file);
  const items = JSON.parse(fs.readFileSync(itemsFile, 'utf8'));
  const input = { who: who === 'thrall' ? { thrall: true } : { letter: who }, sessionId: null, items };
  const r = publishFromInput(db, input);
  if (verb === 'confirm' && !r.unchanged) throw new Error('confirm: the list was not the live one');
  db.close();
} else {
  throw new Error('usage: seed <home> | publish <home> <thrall|letter> <items.json> | confirm <home> <thrall|letter> <items.json>');
}
