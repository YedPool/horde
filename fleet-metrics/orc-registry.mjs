// Which Orc a session belongs to, taken from the Orc registry and from nowhere else.
//
// The founder's data audit (2026-10-19, recommendation 9) says metrics rows carry orc_id and session_id
// from the registry, never a lane guessed from a label. The registry is orcs/Registry.ps1's: a folder
// <HORDE_HOME>\orcs\registry\ of write-once records, one JSON file each (schema/orc-registry-event.v1).
// Today none of its record kinds names a SESSION (they name Orcs: registered, named, ordered, retired,
// tier), so this lookup answers null for every session and orc_id stays NULL. THE ASSUMED CONTRACT, for
// when the registry gains the link: a record whose data holds both "id" (the Orc's registry id) and
// "sessionId" (the harness session id) says that session belongs to that Orc; the highest sequence wins.
// Nothing is ever worked out from a label, a parent chain or a lane name here; that is the guess this
// replaces. A folder that is missing or a record that cannot be read gives no answer, never an error.
import fs from 'node:fs';
import path from 'node:path';

export function registryFolder(home) {
  return path.join(home, 'orcs', 'registry');
}

// -> { orcIdOf(sessionId) -> string | null, records }
export function loadOrcRegistry(home) {
  const bySession = new Map();
  let records = 0;
  let names = [];
  try { names = fs.readdirSync(registryFolder(home)).filter((n) => n.endsWith('.json')).sort(); } catch { names = []; }
  for (const n of names) {
    try {
      const o = JSON.parse(fs.readFileSync(path.join(registryFolder(home), n), 'utf8').replace(/^\u{FEFF}/u, ''));
      records++;
      const d = o && o.data;
      if (d && typeof d.id === 'string' && d.id !== '' && typeof d.sessionId === 'string' && d.sessionId !== '') bySession.set(d.sessionId, d.id);
    } catch { /* one unreadable record must not hide the rest */ }
  }
  return { records, orcIdOf: (sessionId) => bySession.get(String(sessionId || '')) || null };
}
