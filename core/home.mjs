// core/home.mjs - where Horde's home is, for every node program. The node twin of core/Home.ps1's Get-HordeHome.
//
// ONE RULE, SHARED BY EVERY RESOLVER (fleet-db/store.mjs, fleet-metrics/home.mjs, hooks/horde-turn-duty.mjs and
// core/Home.ps1), so one step moves the whole fleet. The order:
//   1. HORDE_HOME, when set. It must be an absolute path (a relative one is refused). Tests rely on it.
//   2. the POINTER FILE <USERPROFILE>\.horde-home.json, exactly {"v":1,"hordeHome":"<absolute path>"}, ASCII. It sits
//      outside any home on purpose, and it is read on EVERY call: an environment variable set at user level reaches
//      only processes started afterwards, but a file is seen by a running session at its next call.
//   (3. PowerShell only: %USERPROFILE%\.horde. The node side has NO fallback: a silent default would split the data.)
//
// A POINTER THAT IS THERE BUT BAD IS REFUSED, never skipped: unreadable, not JSON, not ASCII, not v 1, no hordeHome,
// a relative path, or a folder that does not exist. Skipping it would send this program to another folder than the
// ones that read the pointer fine, and nothing would say so. The message names the file.
//
// Nothing here makes a folder or writes a file: a reader must not.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const POINTER_NAME = '.horde-home.json';

// A full path: a drive and a separator, or UNC on Windows (a drive-less path depends on the current drive).
export function isRootedPath(p) {
  const s = String(p ?? '');
  return process.platform === 'win32' ? /^([A-Za-z]:[\\/]|\\\\[^\\/])/.test(s) : path.isAbsolute(s);
}

function profileDir(env) {
  const p = String(env.USERPROFILE ?? '').trim();
  return p !== '' ? p : os.homedir();
}

export function pointerPath(env = process.env) {
  return path.join(profileDir(env), POINTER_NAME);
}

// { ok: true, home, source: 'HORDE_HOME' | 'pointer', file? }
// { ok: false, kind: 'unset', message }    neither source names a home
// { ok: false, kind: 'refused', message }  a source names a bad one (never fall through to the next)
export function resolveHordeHome(env = process.env) {
  const raw = String(env.HORDE_HOME ?? '').trim();
  if (raw !== '') {
    if (!isRootedPath(raw)) {
      return { ok: false, kind: 'refused', message: 'HORDE_HOME must be an absolute path, not "' + raw + '"; set it to the Horde home folder and run again.' };
    }
    return { ok: true, home: path.resolve(raw), source: 'HORDE_HOME' };
  }
  const file = pointerPath(env);
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (e) {
    if (e && e.code === 'ENOENT') {
      return { ok: false, kind: 'unset', message: 'HORDE_HOME is not set and there is no pointer file ' + file + ', so there is no Horde home; set HORDE_HOME or run horde home set -Path <folder>.' };
    }
    return { ok: false, kind: 'refused', message: 'the home pointer file ' + file + ' cannot be read (' + (e && e.code ? e.code : 'error') + '); fix it or remove it with horde home clear.' };
  }
  const bad = (why) => ({ ok: false, kind: 'refused', message: 'the home pointer file ' + file + ' is refused: ' + why + '; fix it with horde home set -Path <folder> or remove it with horde home clear.' });
  if (/[^\x20-\x7e\r\n\t]/.test(text)) return bad('it holds a character that is not ASCII');
  let obj;
  try { obj = JSON.parse(text); } catch { return bad('it is not JSON'); }
  if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) return bad('it is not a JSON object');
  if (obj.v !== 1) return bad('v is not 1');
  if (typeof obj.hordeHome !== 'string' || obj.hordeHome.trim() === '') return bad('hordeHome is missing');
  const target = obj.hordeHome.trim();
  if (!isRootedPath(target)) return bad('hordeHome "' + target + '" is not an absolute path');
  let isDir = false;
  try { isDir = fs.statSync(target).isDirectory(); } catch { isDir = false; }
  if (!isDir) return bad('hordeHome "' + target + '" is not an existing folder');
  return { ok: true, home: path.resolve(target), source: 'pointer', file };
}
