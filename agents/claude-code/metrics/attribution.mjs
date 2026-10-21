// Which Orc, and which rank, a session belongs to.
//
// KEPT IN ITS OWN FILE because it is the one part of the reader that depends on the fleet's own
// bookkeeping rather than on the harness's transcript format: it reads the fleet tool's session
// registry. A fleet that keeps its sessions anywhere else replaces this file (or hands another
// function to the reader) and nothing else changes.
//
// The registry is one JSON file per session, <registry>/<session id>.json, written by PowerShell
// 5.1 and so UTF-8 WITH a byte-order mark (measured on 137 records, 2026-10-16). The fields used:
//   role    "master" for the Thrall, "orchestrator" for an Orc; absent on a Warg and on most others
//   label   an Orc's own name (a letter)
//   owner   the Orc that spawned a session (a Warg's Orc)
//   parent  the session that spawned it
// The folder is, in order: the explicit `registry` option (tests), $WEZFLEET_ROOT/registry/sessions,
// then the fleet tool's default place under the user's Documents (the place core/Roles.ps1 uses).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export function registryFolder(opts = {}, env = process.env) {
  if (opts.registry) return opts.registry;
  const root = String(env.WEZFLEET_ROOT || '');
  if (root !== '') return path.join(root, 'registry', 'sessions');
  return path.join(os.homedir(), 'Documents', 'Code', '.wezfleet', 'registry', 'sessions');
}

function loadRegistry(dir) {
  const reg = new Map();
  let names = [];
  try { names = fs.readdirSync(dir); } catch { return reg; }
  for (const n of names) {
    if (!n.endsWith('.json')) continue;
    try {
      const raw = fs.readFileSync(path.join(dir, n), 'utf8').replace(/^\u{FEFF}/u, '');
      const r = JSON.parse(raw);
      reg.set(String(r.claudeSessionId || n.slice(0, -5)), r);
    } catch { /* one unreadable record must not hide the rest */ }
  }
  return reg;
}

// -> { lookup(sessionId) -> { orc, rank } }
export function makeAttribution(opts = {}, env = process.env) {
  const reg = loadRegistry(registryFolder(opts, env));
  const orcOf = (sid, depth = 0) => {
    const r = reg.get(sid);
    if (!r) return null;
    if (r.role === 'master') return r.label || 'master';
    if (r.label && r.role === 'orchestrator') return r.label;
    if (r.owner) return r.owner;
    if (r.parent && depth < 4) return orcOf(r.parent, depth + 1) || r.label || null;
    return r.label || null;
  };
  const rankOf = (r) => {
    if (r.role === 'master') return 'thrall';
    if (r.role === 'orchestrator') return 'orc';
    if (/analyst/i.test(String(r.label || '') + ' ' + String(r.name || ''))) return 'analyst';
    if (r.owner || r.parent) return 'warg';
    return 'unknown';
  };
  return {
    lookup(sessionId) {
      const r = reg.get(sessionId);
      if (!r) return { orc: 'unknown', rank: 'unknown' };
      return { orc: orcOf(sessionId) || 'unknown', rank: rankOf(r) };
    },
  };
}
