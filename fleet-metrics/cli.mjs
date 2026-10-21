// Entry point of the fleet meter:  node cli.mjs collect | live [--session <id>] | latency | watch-limits [--dry-run] | status
// Run by `horde meter ...` and by the two scheduled tasks. Exit codes: 0 done, 1 failed, 2 no home.
//
// Flags beyond the verbs exist for tests and for a moved store:
//   --projects <dir>       where the harness keeps its transcripts (default: the reader's own)
//   --registry <dir>       the fleet's session registry (default: the attribution file's own)
//   --agents <dir>         where to look for readers (default: the repository's agents folder)
//   --horde-script <file>  horde.ps1, used by watch-limits to tell the master session
//   --since-days <n>       collect: skip files not touched for n days (default 14; they get no offset)
//                          latency: only messages with a hop in the last n days (default 7)
//   --max-ms <n>           collect: stop between files after n ms (default 240000) and say partial
//   --session <id>         live: refresh only this session (default: every session changed in the last 10 minutes)
//   --journal <dir>        collect: the relay journal to read hops from (default: <HORDE_HOME>/relay/journal)
import { resolveHome } from './home.mjs';
import { openStore, SCHEMA_VERSION } from './store.mjs';
import { runCollect, runLive, liveLines, summaryLine, mailLine } from './collect.mjs';
import { latencyPairs, latencyLines } from './mail.mjs';
import { runWatch, watchSummary, hordeSender } from './watch-limits.mjs';

function parseArgs(argv) {
  const o = { verb: argv[0], flags: {} };
  for (let i = 1; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') o.flags.dryRun = true;
    else if (['--projects', '--registry', '--agents', '--horde-script', '--since-days', '--max-ms', '--session', '--journal'].includes(a)) o.flags[a.slice(2).replace(/-(\w)/g, (_, c) => c.toUpperCase())] = argv[++i];
    else { o.bad = a; break; }
  }
  return o;
}

const ago = (ms) => {
  const s = Math.max(0, Math.round(ms / 1000));
  if (s < 90) return s + ' s';
  if (s < 5400) return Math.round(s / 60) + ' min';
  if (s < 172800) return (s / 3600).toFixed(1) + ' h';
  return Math.round(s / 86400) + ' days';
};

const SESSION_ID = /^[0-9a-f-]{8,64}$/;
export const DEFAULT_LATENCY_DAYS = 7;

export async function main(argv, env = process.env, out = (s) => process.stdout.write(s + '\n'), err = (s) => process.stderr.write(s + '\n')) {
  const a = parseArgs(argv);
  if (!['collect', 'live', 'latency', 'watch-limits', 'status'].includes(a.verb) || a.bad) {
    err('usage: cli.mjs collect | live [--session <id>] | latency | watch-limits [--dry-run] | status' + (a.bad ? ' (unknown option ' + a.bad + ')' : ''));
    return 1;
  }
  const home = resolveHome(env);
  if (!home.ok) { err(home.message); return 2; }
  const opts = { projects: a.flags.projects, registry: a.flags.registry, agentsDir: a.flags.agents, home: home.home, journal: a.flags.journal };
  for (const k of ['sinceDays', 'maxMs']) {
    if (a.flags[k] === undefined) continue;
    const n = Number(a.flags[k]);
    if (!Number.isFinite(n) || n < 0) { err('--' + (k === 'sinceDays' ? 'since-days' : 'max-ms') + ' must be a number of at least 0'); return 1; }
    opts[k] = n;
  }
  // A session id is hex and dashes: anything else is refused before it can reach a file name match.
  if (a.flags.session !== undefined && !SESSION_ID.test(a.flags.session)) { err('--session must be a session id (8 to 64 hex digits and dashes)'); return 2; }
  let store;
  try {
    store = openStore(home.home);
    if (a.verb === 'collect') {
      const r = await runCollect({ store, opts });
      out(summaryLine(r));
      out(mailLine(r));
      for (const f of r.failures.slice(0, 5)) err('could not read ' + f.file + ': ' + f.message);
      // A file that could not be read is a failure a scheduler's history should show; the rest was still collected.
      if (r.errors > 0) return 1;
    } else if (a.verb === 'live') {
      const r = await runLive({ store, opts, session: a.flags.session || null });
      for (const l of liveLines(r)) out(l);
      for (const f of r.failures.slice(0, 5)) err('could not refresh ' + f.file + ': ' + f.message);
      if (r.errors) return 1;
    } else if (a.verb === 'latency') {
      const days = opts.sinceDays == null ? DEFAULT_LATENCY_DAYS : opts.sinceDays;
      for (const l of latencyLines(latencyPairs(store.hopsSince(Date.now() - days * 86400000)))) out(l);
    } else if (a.verb === 'watch-limits') {
      const r = await runWatch({ store, opts, dryRun: !!a.flags.dryRun, sender: hordeSender(a.flags.hordeScript, env) });
      for (const t of r.would) out('would send: ' + t);
      if (r.lastError) err('could not tell the master session: ' + r.lastError);
      out(watchSummary(r, !!a.flags.dryRun));
      // A message that could not be delivered is retried on the next run, and the history should say so.
      if (r.failed > 0) return 1;
    } else {
      const stats = store.tableStats();
      const now = Date.now();
      out('database: ' + store.file + ' (schema ' + SCHEMA_VERSION + ')');
      let newest = 0;
      for (const [t, s] of Object.entries(stats)) {
        out(t + ': ' + s.rows + ' rows, newest ' + (s.newest ? new Date(s.newest).toISOString() : 'none'));
        newest = Math.max(newest, s.newest || 0);
      }
      out('data age: ' + (newest ? ago(now - newest) + ' since the newest row' : 'no data yet'));
    }
    return 0;
  } catch (e) {
    err('fleet meter: ' + e.message);
    return 1;
  } finally {
    if (store) store.close();
  }
}

import { fileURLToPath } from 'node:url';
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main(process.argv.slice(2)).then((c) => { process.exitCode = c; });
}
