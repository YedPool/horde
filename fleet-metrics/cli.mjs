// Entry point of the fleet meter:  node cli.mjs collect | watch-limits [--dry-run] | status
// Run by `horde meter ...` and by the two scheduled tasks. Exit codes: 0 done, 1 failed, 2 no home.
//
// Flags beyond the verbs exist for tests and for a moved store:
//   --projects <dir>       where the harness keeps its transcripts (default: the reader's own)
//   --registry <dir>       the fleet's session registry (default: the attribution file's own)
//   --agents <dir>         where to look for readers (default: the repository's agents folder)
//   --horde-script <file>  horde.ps1, used by watch-limits to tell the master session
import { resolveHome } from './home.mjs';
import { openStore, SCHEMA_VERSION } from './store.mjs';
import { runCollect, summaryLine } from './collect.mjs';
import { runWatch, watchSummary, hordeSender } from './watch-limits.mjs';

function parseArgs(argv) {
  const o = { verb: argv[0], flags: {} };
  for (let i = 1; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') o.flags.dryRun = true;
    else if (['--projects', '--registry', '--agents', '--horde-script'].includes(a)) o.flags[a.slice(2).replace(/-(\w)/g, (_, c) => c.toUpperCase())] = argv[++i];
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

export async function main(argv, env = process.env, out = (s) => process.stdout.write(s + '\n'), err = (s) => process.stderr.write(s + '\n')) {
  const a = parseArgs(argv);
  if (!['collect', 'watch-limits', 'status'].includes(a.verb) || a.bad) {
    err('usage: cli.mjs collect | watch-limits [--dry-run] | status' + (a.bad ? ' (unknown option ' + a.bad + ')' : ''));
    return 1;
  }
  const home = resolveHome(env);
  if (!home.ok) { err(home.message); return 2; }
  const opts = { projects: a.flags.projects, registry: a.flags.registry, agentsDir: a.flags.agents };
  let store;
  try {
    store = openStore(home.home);
    if (a.verb === 'collect') {
      out(summaryLine(await runCollect({ store, opts })));
    } else if (a.verb === 'watch-limits') {
      const r = await runWatch({ store, opts, dryRun: !!a.flags.dryRun, sender: hordeSender(a.flags.hordeScript, env) });
      for (const t of r.would) out('would send: ' + t);
      if (r.lastError) err('could not tell the master session: ' + r.lastError);
      out(watchSummary(r, !!a.flags.dryRun));
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
