// Where the meter keeps its database. Horde's own rule (core/home.mjs, the node twin of core/Home.ps1):
// HORDE_HOME names the home, else the pointer file does, and a relative or bad one is refused because the
// same command run from two folders would write two databases.
// UNLIKE the PowerShell side there is NO default here: a scheduled task starts with a thin
// environment, and a silent fallback to a folder under the user's profile would split the data in two
// without anyone being told. The horde command passes its resolved home down explicitly.
import path from 'node:path';
import { resolveHordeHome } from '../core/home.mjs';

export function resolveHome(env = process.env) {
  const r = resolveHordeHome(env);
  if (r.ok) return { ok: true, home: r.home };
  return { ok: false, message: r.message };
}

export function dbPathFor(home) {
  return path.join(home, 'metrics', 'fleet.sqlite');
}
