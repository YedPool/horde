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
//   - THE LIVE VIEW (tokens_usage) needs two facts the request rows do not hold: when this file's records
//     begin and end (every assistant or user record is a sign of life), and when the parent's tool result for
//     an Agent call came back (a user record whose tool_result block names the call's tool_use_id). The
//     totals themselves are summed by the store from the request rows, never parsed a second time.
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

// A transcript is data from outside: a count that is missing, negative, fractional or not a number is taken
// as 0 (and the record counted as skipped), because one such value used to be enough to make the store
// throw and stop the collection of every file after it.
const count = (v) => (Number.isInteger(v) && v >= 0 ? v : 0);
const text = (v) => (typeof v === 'string' && v !== '' ? v : null);

function usageRow(o, who, turnUuid, at, requestId) {
  const m = o.message;
  const u = m.usage;
  const cc = u.cache_creation && typeof u.cache_creation === 'object' ? u.cache_creation : {};
  let w5 = count(cc.ephemeral_5m_input_tokens);
  const w1 = count(cc.ephemeral_1h_input_tokens);
  // The harness reports the total written to the cache, and (newer builds) how much of it was 5-minute
  // and 1-hour. When the parts sum to less than the total, the remainder is the default kind, 5 minutes;
  // with no parts at all that is the whole total.
  const total = count(u.cache_creation_input_tokens);
  if (w5 + w1 < total) w5 += total - (w5 + w1);
  const model = text(m.model) || text(o.requestedModel) || '';
  const fam = familyOf(model);
  const n = {
    input: count(u.input_tokens), output: count(u.output_tokens), cache_read: count(u.cache_read_input_tokens),
    cache_write_5m: w5, cache_write_1h: w1,
  };
  const clean = [u.input_tokens, u.output_tokens, u.cache_read_input_tokens].every((v) => v === undefined || v === null || count(v) === v);
  return {
    clean,
    row: {
      at, request_id: requestId, session_id: who.sessionId, agent_id: who.agentId, turn_uuid: turnUuid,
      orc: who.orc, rank: who.rank, model: model || 'unknown', family: fam, ...n,
      context_tokens: n.input + n.cache_read + w5 + w1, cost_usd: costOf(fam, n),
    },
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
  const batch = { tokens_requests: [], tokens_turns: [], tokens_agents: [], tokens_limits: [], limit_resumes: [], tokens_usage: [], agent_returns: [] };
  if (!who) return batch;
  let turn = who.kind === 'main' ? store.latestTurnUuid(who.sessionId, null) : null;
  let openHit = store.hasOpenLimit(who.sessionId, who.agentId);
  let firstModel = null;
  batch.skipped = 0;
  let firstAt = Infinity;
  let lastAt = 0;

  for (const line of lines) {
    let o;
    try { o = JSON.parse(line); } catch { continue; }
    if (!o || typeof o !== 'object') continue;
    // Only these two kinds of record carry anything the meter keeps; the rest are not counted as skipped.
    if (o.type !== 'assistant' && o.type !== 'user') continue;
    const at = Date.parse(o.timestamp);
    if (!Number.isFinite(at)) { batch.skipped++; continue; }
    const m = o.message && typeof o.message === 'object' ? o.message : {};
    if (at < firstAt) firstAt = at;
    if (at > lastAt) lastAt = at;

    if (o.type === 'assistant' || o.type === 'user') {
      if (isLimitHit(o)) {
        const hitUuid = text(o.uuid);
        if (!hitUuid) { batch.skipped++; continue; }
        batch.tokens_limits.push({
          at, session_id: who.sessionId, agent_id: who.agentId, orc: who.orc, hit_uuid: hitUuid, ...limitFields(o),
          stuck_until: null, stuck_ms: null,
        });
        openHit = true;
        continue;
      }
      // Any other record after a hit means the session is moving again.
      if (openHit) { batch.limit_resumes.push({ at, session_id: who.sessionId, agent_id: who.agentId }); openHit = false; }
    }

    if (o.type === 'user' && Array.isArray(m.content)) {
      // Which tool calls just returned. Most are not Agent calls; the store ignores those.
      for (const c of m.content) if (c && c.type === 'tool_result' && text(c.tool_use_id)) batch.agent_returns.push({ at, tool_use_id: c.tool_use_id });
    }

    if (o.type === 'assistant') {
      for (const c of Array.isArray(m.content) ? m.content : []) {
        if (c && c.type === 'tool_use' && (c.name === 'Agent' || c.name === 'Task')) {
          if (!text(c.id)) { batch.skipped++; continue; }
          const inp = c.input && typeof c.input === 'object' ? c.input : {};
          batch.tokens_agents.push({
            at, tool_use_id: c.id, parent_session_id: who.sessionId, agent_id: null, orc: who.orc,
            agent_type: text(inp.subagent_type), model_asked: text(inp.model), model_used: null,
            description: clip(inp.description), route_id: routeOf(inp.description),
          });
        }
      }
      if (m.usage && typeof m.usage === 'object' && m.model !== '<synthetic>') {
        const requestId = text(o.requestId) || text(m.id) || text(o.uuid);
        if (!requestId) { batch.skipped++; continue; }
        const made = usageRow(o, who, turn, at, requestId);
        if (!made.clean) batch.skipped++;
        if (!firstModel) firstModel = made.row.model;
        batch.tokens_requests.push(made.row);
      }
    } else if (o.type === 'user' && who.kind === 'main') {
      const content = m.content;
      if (Array.isArray(content) && content.some((c) => c && c.type === 'tool_result')) continue;
      if (o.isMeta) continue;
      if (!text(o.uuid)) { batch.skipped++; continue; }
      turn = o.uuid;
      batch.tokens_turns.push({ at, session_id: who.sessionId, agent_id: null, turn_uuid: o.uuid, trigger: triggerOf(textOf(content)) });
    }
  }

  if (firstAt !== Infinity) {
    batch.tokens_usage.push({ session_id: who.sessionId, agent_id: who.agentId || '', started_at: firstAt, last_seen_at: lastAt });
  }

  // The sidecar links this file to the parent's Agent call. It is read on every pass over the file.
  if (who.kind === 'sub' && who.meta) {
    try {
      const meta = JSON.parse(fs.readFileSync(who.meta, 'utf8').replace(/^\u{FEFF}/u, ''));
      if (text(meta.toolUseId)) {
        let born = Date.now();
        try { born = Math.round(fs.statSync(who.meta).birthtimeMs); } catch { /* keep now */ }
        batch.tokens_agents.push({
          at: born, tool_use_id: meta.toolUseId, parent_session_id: who.sessionId, agent_id: who.agentId, orc: who.orc,
          agent_type: text(meta.agentType), model_asked: null, model_used: text(meta.model) || firstModel,
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
      if (typeof o.uuid !== 'string' || o.uuid === '') continue; // (the parameter 'text' is the tail here)
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

// The files of ONE session (its own transcript and its subagents'), found without walking every project:
// each project folder is asked for <session>.jsonl and <session>/subagents. Used by the live view.
function sessionFiles(root, sessionId) {
  const out = [];
  let projects = [];
  try { projects = fs.readdirSync(root, { withFileTypes: true }); } catch { return out; }
  for (const p of projects) {
    if (!p.isDirectory()) continue;
    const main = path.join(root, p.name, sessionId + '.jsonl');
    if (fs.existsSync(main)) out.push(main);
    walk(path.join(root, p.name, sessionId, 'subagents'), out);
  }
  return out.filter((f) => describeFile(f) !== null);
}

export default {
  id: 'claude-code',
  roots: (opts) => [projectsFolder(opts)],
  sessionFiles,
  listFiles(root) {
    const all = [];
    walk(root, all);
    return all.filter((f) => describeFile(f) !== null);
  },
  consume,
  inspectTail,
};
