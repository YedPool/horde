// Builds small SYNTHETIC transcript folders for the reader's tests and for the end-to-end scenario.
// Nothing here is copied from a real transcript: ids are made up, text is invented, and only the
// shape of the records matches what the harness writes (checked against the format notes in
// reader.mjs). Usable as a module, or as a script:  node make-projects.mjs <projects-dir> <registry-dir>
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const SID_ORC = '11111111-aaaa-4aaa-8aaa-000000000001';   // an Orc's main session
export const SID_STUCK = '22222222-bbbb-4bbb-8bbb-000000000002'; // a session that ends at a limit hit
export const SID_THRALL = '33333333-cccc-4ccc-8ccc-000000000003';
export const AGENT_ID = 'a0b1c2d3e4f5a6b7c';
export const TOOL_USE = 'toolu_01SYNTHETICAGENTCALL';

export const iso = (ms) => new Date(ms).toISOString();

// A usage block with a known cost (see test/reader.test.mjs for the sums).
export const USAGE_KNOWN = {
  input_tokens: 1000,
  output_tokens: 2000,
  cache_read_input_tokens: 10000,
  cache_creation_input_tokens: 5000,
  cache_creation: { ephemeral_5m_input_tokens: 4000, ephemeral_1h_input_tokens: 1000 },
};

export function user(uuid, ms, text, extra = {}) {
  return JSON.stringify({ type: 'user', uuid, timestamp: iso(ms), message: { role: 'user', content: text }, ...extra });
}
export function toolResult(uuid, ms, toolUseId) {
  return JSON.stringify({ type: 'user', uuid, timestamp: iso(ms), message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: toolUseId, content: 'ok' }] } });
}
export function assistant(uuid, ms, requestId, { model = 'claude-sonnet-4-5', usage = USAGE_KNOWN, tools = [] } = {}) {
  const content = [{ type: 'text', text: 'working' }, ...tools];
  return JSON.stringify({ type: 'assistant', uuid, timestamp: iso(ms), requestId, message: { id: 'msg_' + requestId, role: 'assistant', model, content, usage } });
}
export function agentCall(id, { subagent_type = 'general-purpose', model = 'haiku', description = '[r:ab12] read the logs' } = {}) {
  return { type: 'tool_use', id, name: 'Agent', input: { subagent_type, model, description, prompt: 'x' } };
}
export function limitHit(uuid, ms, { type = 'five_hour', resetsAtSec = Math.round(ms / 1000) + 3600 } = {}) {
  return JSON.stringify({
    type: 'assistant', uuid, timestamp: iso(ms), requestId: 'req_synthetic_' + uuid, apiError: 'usage_limit_reached', isApiErrorMessage: true,
    apiErrorParams: { rate_limit_info: { status: 'rejected', resetsAt: resetsAtSec, rateLimitType: type } },
    message: { id: 'msg_' + uuid, role: 'assistant', model: '<synthetic>', content: [{ type: 'text', text: 'limit' }], usage: { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 } },
  });
}

export function writeLines(file, lines, { trailingNewline = true } = {}) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, lines.join('\n') + (trailingNewline ? '\n' : ''));
}

// The standard fleet: an Orc session with a duplicate request, a mail-started turn, one subagent
// linked by its sidecar; and a second session that ends at a limit hit at `hitMs`.
export function writeProjects(root, baseMs, hitMs = baseMs + 60000) {
  const proj = path.join(root, 'proj-one');
  writeLines(path.join(proj, SID_ORC + '.jsonl'), [
    user('u1', baseMs, 'please look at the build'),
    assistant('a1', baseMs + 1000, 'req_A', { tools: [agentCall(TOOL_USE)] }),
    assistant('a1b', baseMs + 1100, 'req_A', { tools: [] }), // same request again: counted once
    toolResult('r1', baseMs + 2000, TOOL_USE),
    user('u2', baseMs + 3000, 'wezfleet: a message is waiting from E'),
    assistant('a2', baseMs + 4000, 'req_B'),
  ]);
  const sub = path.join(proj, SID_ORC, 'subagents');
  writeLines(path.join(sub, 'agent-' + AGENT_ID + '.jsonl'), [
    user('s1', baseMs + 1200, 'read the logs'),
    assistant('s2', baseMs + 1500, 'req_SUB', { model: 'claude-haiku-4-5' }),
  ]);
  fs.writeFileSync(path.join(sub, 'agent-' + AGENT_ID + '.meta.json'),
    JSON.stringify({ agentType: 'general-purpose', description: '[r:ab12] read the logs', toolUseId: TOOL_USE, model: 'haiku' }));
  writeLines(path.join(proj, SID_STUCK + '.jsonl'), [
    user('v1', baseMs, 'go'),
    assistant('v2', baseMs + 500, 'req_C'),
    limitHit('hit-1', hitMs),
  ]);
}

// A registry folder in the format the fleet tool writes: UTF-8 WITH a byte-order mark.
export function writeRegistry(dir) {
  fs.mkdirSync(dir, { recursive: true });
  const put = (sid, rec) => fs.writeFileSync(path.join(dir, sid + '.json'), '\u{FEFF}' + JSON.stringify({ claudeSessionId: sid, ...rec }, null, 2), 'utf8');
  put(SID_ORC, { label: 'Q', role: 'orchestrator' });
  put(SID_STUCK, { owner: 'Q', parent: SID_ORC });
  put(SID_THRALL, { role: 'master', label: 'M' });
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const now = Date.now() - 3600 * 1000;
  writeProjects(process.argv[2], now, now + 60000);
  writeRegistry(process.argv[3]);
}
