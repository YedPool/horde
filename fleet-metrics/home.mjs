// Where the meter keeps its database. Horde's own rule (core/Home.ps1): HORDE_HOME names the home, and
// a relative one is refused because the same command run from two folders would write two databases.
// UNLIKE the PowerShell side there is NO default here: a scheduled task starts with a thin
// environment, and a silent fallback to a folder under the user's profile would split the data in two
// without anyone being told. The horde command passes its resolved home down explicitly.
import path from 'node:path';

export function resolveHome(env = process.env) {
  const raw = String(env.HORDE_HOME ?? '').trim();
  if (raw === '') {
    return { ok: false, message: 'HORDE_HOME is not set, so the fleet meter has nowhere to keep its data; set it to the Horde home folder and run again.' };
  }
  if (!path.isAbsolute(raw)) {
    return { ok: false, message: 'HORDE_HOME must be an absolute path, not "' + raw + '"; set it to the Horde home folder and run again.' };
  }
  return { ok: true, home: path.resolve(raw) };
}

export function dbPathFor(home) {
  return path.join(home, 'metrics', 'fleet.sqlite');
}
