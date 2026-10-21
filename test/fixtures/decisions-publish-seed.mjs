// Seeds a test Horde home's fleet.db for test/test-decisions-publish.ps1: the Thrall M, Orcs F and G, a task
// and questions 7 and 9. Usage: node decisions-publish-seed.mjs <home>. Only ever run against a folder a
// suite made; it refuses a home that already holds a fleet.db.
import fs from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const { openStore, dbPathFor } = await import(pathToFileURL(path.join(root, 'fleet-db', 'store.mjs')).href);
const { ulid } = await import(pathToFileURL(path.join(root, 'fleet-db', 'ids.mjs')).href);

const file = dbPathFor(process.argv[2]);
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
q.run(id(), 7, task, T0);
q.run(id(), 9, task, T0);
db.close();
