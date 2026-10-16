// The fleet meter's reader for this harness: turns its transcripts into the meter's neutral rows.
// This folder is the only place that knows the transcript format (CONTRIBUTING 14).
//
// Ported in logic from the fleet analyst's reference token report (2026-10-16), which was measured
// against the live fleet's transcripts; the rules below are its findings:
//   - A REQUEST'S USAGE REPEATS ON EVERY CONTENT BLOCK OF ITS REPLY, so a request is counted once,
//     under its requestId, and the LAST record seen wins (store upsert on request_id does exactly that,
//     including across collect passes).
//   - A TURN starts at a user record that is not a tool result and not meta. What started it is told
//     by its first words (INJECTED): mail, a task notice, a stop hook, a compaction. A plain typed
//     line in a main session is the founder's.
//   - SUBAGENTS are separate files, <session>/subagents/agent-<id>.jsonl, with a sidecar
//     agent-<id>.meta.json {agentType, description, toolUseId, model} that links the file to the
//     parent's Agent tool call (whose input carries subagent_type, model, description).
//   - A USAGE-LIMIT HIT is an assistant record with model "<synthetic>", isApiErrorMessage true and
//     apiError "usage_limit_reached"; the kind of limit is apiErrorParams.rate_limit_info.rateLimitType
//     and the reset is its resetsAt in epoch SECONDS (stored here in ms).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { familyOf, costOf } from '../../../fleet-metrics/prices.mjs';
import { makeAttribution } from './attribution.mjs';

// How a turn nobody typed begins, by its first words. 'timer' is a placeholder for scheduled wake-ups
// and is UNVERIFIED against a real transcript (none was found in the fleet's records on 2026-10-16).
const INJECTED = [
  ['mail', /^wezfleet: (a message|\d+ messages)/],
  ['mail', /^MESSAGE FROM /],
  ['task-notice', /^<task-notification>/],
  ['stop-hook', /^Stop hook feedback/],
  ['compaction', /^This session is being continued/],
  ['timer', /^<scheduled-task/],
];
// The reference also looked for these two inside the first 400 characters, because the harness
// sometimes puts a system reminder before them.
const EARLY = [['task-notice', '<task-notification>'], ['stop-hook', 'Stop hook feedback']];

export function projectsFolder(opts = {}, env = process.env) {
  if (opts.projects) return opts.projects;
  if (env.HORDE_METER_PROJECTS) return env.HORDE_METER_PROJECTS;
  const cfg = env.CLAUDE_CONFIG_DIR ? env.CLAUDE_CONFIG_DIR : path.join(os.homedir(), '.claude');
  return path.join(cfg, 'projects');
}

function walk(dir, out) {
  let ents = [];
  try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of ents) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.jsonl')) out.push(p);
  }
}

// Which file is it: a main session, a subagent's, or neither (then it is not read).
export function describeFile(file) {
  const base = path.basename(file, '.jsonl');
  const dir = path.dirname(file);
  if (path.basename(dir) === 'subagents') {
    if (!base.startsWith('agent-')) return null;
    return { kind: 'sub', sessionId: path.basename(path.dirname(dir)), agentId: base.slice(6), meta: path.join(dir, base + '.meta.json') };
  }
  return { kind: 'main', sessionId: base, agentId: null, meta: null };
}

function textOf(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    for (const c of content) if (c && c.type === 'text') return c.text || '';
  }
  return '';
}

export function triggerOf(txt) {
  const t = txt.trimStart();
  for (const [name, re] of INJECTED) if (re.test(t)) return name;
  for (const [name, s] of EARLY) if (t.slice(0, 400).includes(s)) return name;
  if (t.startsWith('<system-reminder>') && t.slice(0, 2000).includes('<task-notification>')) return 'task-notice';
  return t === '' ? 'other' : 'founder';
}

export function isLimitHit(o) {
  const m = o && o.message;
  return !!m && m.model === '<synthetic>' && o.isApiErrorMessage === true && o.apiError === 'usage_limit_reached';
}

function limitFields(o) {
  const info = (o.apiErrorParams && o.apiErrorParams.rate_limit_info) || {};
  return {
    limit_type: String(info.rateLimitType || 'unknown'),
    resets_at: Number.isFinite(info.resetsAt) ? Math.round(info.resetsAt * 1000) : null,
  };
}

const routeOf = (d) => { const m = /^\[r:([^\]\s]+)\]/.exec(d || ''); return m ? m[1] : null; };
const clip = (d) => (d == null ? null : String(d).replace(/\s+/g, ' ').trim().slice(0, 120));

function usageRow(o, who, turnUuid, at) {
  const m = o.message;
  const u = m.usage;
  const cc = u.cache_creation || {};
  let w5 = cc.ephemeral_5m_input_tokens;
  let w1 = cc.ephemeral_1h_input_tokens;
  if (w5 == null && w1 == null) { w5 = u.cache_creation_input_tokens || 0; w1 = 0; }
  w5 = w5 || 0; w1 = w1 || 0;
  const model = m.model || o.requestedModel || '';
  const fam = familyOf(model);
  const n = {
    input: u.input_tokens || 0, output: u.output_tokens || 0, cache_read: u.cache_read_input_tokens || 0,
    cache_write_5m: w5, cache_write_1h: w1,
  };
  return {
    at, request_id: o.requestId || m.id || o.uuid, session_id: who.sessionId, agent_id: who.agentId, turn_uuid: turnUuid,
    orc: who.orc, rank: who.rank, model: model || 'unknown', family: fam, ...n,
    context_tokens: n.input + n.cache_read + w5 + w1, cost_usd: costOf(fam, n),
  };
}

function whoIs(file, ctx) {
  const d = describeFile(file);
  if (!d) return null;
  if (!ctx.attr) ctx.attr = makeAttribution(ctx.opts || {});
  const a = ctx.attr.lookup(d.sessionId);
  // A subagent is a helper of its parent's Orc; its own rank is warg, however its parent ranks.
  return { ...d, orc: a.orc, rank: d.kind === 'sub' ? 'warg' : a.rank };
}

function consume({ path: file, lines, store, ctx }) {
  const who = whoIs(file, ctx);
  const batch = { tokens_requests: [], tokens_turns: [], tokens_agents: [], tokens_limits: [], limit_resumes: [] };
  if (!who) return batch;
  let turn = who.kind === 'main' ? store.latestTurnUuid(who.sessionId, null) : null;
  let openHit = store.hasOpenLimit(who.sessionId, who.agentId);
  let firstModel = null;

  for (const line of lines) {
    let o;
    try { o = JSON.parse(line); } catch { continue; }
    if (!o || typeof o !== 'object') continue;
    const at = Date.parse(o.timestamp);
    if (!Number.isFinite(at)) continue;
    const m = o.message && typeof o.message === 'object' ? o.message : {};

    if (o.type === 'assistant' || o.type === 'user') {
      if (isLimitHit(o)) {
        batch.tokens_limits.push({
          at, session_id: who.sessionId, agent_id: who.agentId, orc: who.orc, hit_uuid: o.uuid, ...limitFields(o),
          stuck_until: null, stuck_ms: null,
        });
        openHit = true;
        continue;
      }
      // Any other record after a hit means the session is moving again.
      if (openHit) { batch.limit_resumes.push({ at, session_id: who.sessionId, agent_id: who.agentId }); openHit = false; }
    }

    if (o.type === 'assistant') {
      for (const c of Array.isArray(m.content) ? m.content : []) {
        if (c && c.type === 'tool_use' && (c.name === 'Agent' || c.name === 'Task') && c.id) {
          const inp = c.input || {};
          batch.tokens_agents.push({
            at, tool_use_id: c.id, parent_session_id: who.sessionId, agent_id: null, orc: who.orc,
            agent_type: inp.subagent_type || null, model_asked: inp.model || null, model_used: null,
            description: clip(inp.description), route_id: routeOf(inp.description),
          });
        }
      }
      if (m.usage && typeof m.usage === 'object' && m.model !== '<synthetic>') {
        const row = usageRow(o, who, turn, at);
        if (!firstModel) firstModel = row.model;
        batch.tokens_requests.push(row);
      }
    } else if (o.type === 'user' && who.kind === 'main') {
      const content = m.content;
      if (Array.isArray(content) && content.some((c) => c && c.type === 'tool_result')) continue;
      if (o.isMeta || !o.uuid) continue;
      turn = o.uuid;
      batch.tokens_turns.push({ at, session_id: who.sessionId, agent_id: null, turn_uuid: o.uuid, trigger: triggerOf(textOf(content)) });
    }
  }

  // The sidecar links this file to the parent's Agent call. It is read on every pass over the file.
  if (who.kind === 'sub' && who.meta) {
    try {
      const meta = JSON.parse(fs.readFileSync(who.meta, 'utf8').replace(/^﻿/, ''));
      if (meta.toolUseId) {
        let born = Date.now();
        try { born = Math.round(fs.statSync(who.meta).birthtimeMs); } catch { /* keep now */ }
        batch.tokens_agents.push({
          at: born, tool_use_id: meta.toolUseId, parent_session_id: who.sessionId, agent_id: who.agentId, orc: who.orc,
          agent_type: meta.agentType || null, model_asked: null, model_used: meta.model || firstModel,
          description: clip(meta.description), route_id: routeOf(meta.description),
        });
      }
    } catch { /* no sidecar yet: the next pass over this file tries again */ }
  }
  return batch;
}

// What the LAST bytes of a file say about usage-limit hits. `text` is the tail; when the tail begins
// inside the file its first line is cut and is dropped (partialFirst).
function inspectTail({ path: file, text, partialFirst, ctx }) {
  const who = whoIs(file, ctx);
  if (!who) return null;
  let lines = text.split('\n');
  if (partialFirst) lines = lines.slice(1);
  const hits = [];
  let lastIsHit = false;
  let lastAt = null;
  for (const line of lines) {
    if (line.trim() === '') continue;
    let o;
    try { o = JSON.parse(line); } catch { continue; }
    if (!o || (o.type !== 'assistant' && o.type !== 'user')) continue;
    const at = Date.parse(o.timestamp);
    if (!Number.isFinite(at)) continue;
    if (isLimitHit(o)) {
      hits.push({ hit_uuid: o.uuid, at, ...limitFields(o), resumed_at: null });
      lastIsHit = true;
    } else {
      for (const h of hits) if (h.resumed_at == null && at > h.at) h.resumed_at = at;
      lastIsHit = false;
    }
    lastAt = at;
  }
  return { session_id: who.sessionId, agent_id: who.agentId, orc: who.orc, hits, last_is_hit: lastIsHit, last_at: lastAt };
}

export default {
  id: 'claude-code',
  roots: (opts) => [projectsFolder(opts)],
  listFiles(root) {
    const all = [];
    walk(root, all);
    return all.filter((f) => describeFile(f) !== null);
  },
  consume,
  inspectTail,
};
