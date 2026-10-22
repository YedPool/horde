// horde-work-unit - SubagentStart, SubagentStop and SessionEnd hook. It records delegated work in fleet.db, by the
// harness's own events and not by anyone's habit (T-0326; founder ruling 2026-10-21; ranks doc: planning/ranks.md).
//
//   SubagentStart  an AGENT (an Agent-tool helper inside a session) began: `work start -Kind agent`.
//   SubagentStop   it ended: the unit is started again (a repeat changes nothing, and fills a task the first call
//                  could not read) and then `work end`.
//   SessionEnd     a session ended; when the registry says it was a WARG (its own agent session in its own pane,
//                  spawned by an Orc), `work end -Session`. Wargs are STARTED by wezspawn, not here.
//
// THE AGENT ID is the harness's own id, the one in the subagent transcript's file name
// (<project>\<session>\subagents\agent-<id>.jsonl). It is passed through exactly as the payload gives it.
//
// WHAT THE PAYLOAD DOES NOT CARRY is read from the agent's own transcript (its first line is the brief):
//   task       the first T-NNNN on the brief's first non-empty line, else none (fleet.db records no_task);
//   work type  an explicit "work: <type>" (or "work-type: <type>") on one of the brief's first three lines, else
//              Explore and Plan agents are research, else other. NEVER guessed from the brief's words: a guess
//              would put wrong data in the measurement this record exists for;
//   model      the agent's meta file, else the first assistant message's model.
// The transcript may not be on disk yet at SubagentStart, so it is polled for a short, fixed time; when it never
// shows, the unit starts with no task and work type other, and SubagentStop fills the task in.
//   domain     the parent Orc's lane: the lane folder in the parent's registry cwd (...\orcs\<lane>), else its
//              Orc letter.
//
// NEVER BLOCKS, NEVER SLOWS, NEVER FAILS A TOOL CALL. Exit 0 on every path and print nothing (a SubagentStart
// hook's output would reach the model). Every wait is bounded (transcript poll 1 s, fleet.db lock 2 s, a watchdog
// at 8 s). A failure is one line in the log and nothing else. Register it with "async": true as well.
//
// ENVIRONMENT (the tests set these; production sets none):
//   HORDE_WORK_HOOK_REGISTRY  registry sessions dir (default %USERPROFILE%\Documents\Code\.wezfleet\registry\sessions)
//   HORDE_WORK_HOOK_LOG       log file, full path   (default ...\.wezfleet\accuracy\work-unit-hook.log)
//   HORDE_WORK_HOOK_WAIT_MS   transcript poll limit (default 1000)
//   HORDE_HOME                the Horde home; else the home pointer file, as every fleet.db command
//
// NOT INSTALLED BY THIS FILE. The settings.json entries are in the pull request notes; a person installs them.

import { readFileSync, appendFileSync, mkdirSync, existsSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

const REGISTRY_DIR = process.env.HORDE_WORK_HOOK_REGISTRY || join(homedir(), "Documents", "Code", ".wezfleet", "registry", "sessions");
const LOG_FILE = process.env.HORDE_WORK_HOOK_LOG || join(homedir(), "Documents", "Code", ".wezfleet", "accuracy", "work-unit-hook.log");
const WAIT_MS = Number(process.env.HORDE_WORK_HOOK_WAIT_MS) >= 0 && process.env.HORDE_WORK_HOOK_WAIT_MS !== undefined && process.env.HORDE_WORK_HOOK_WAIT_MS !== ""
  ? Number(process.env.HORDE_WORK_HOOK_WAIT_MS) : 1000;
const BUSY_MS = "2000";
const WATCHDOG_MS = 8000;

export const WORK_TYPES = ["build", "review", "verify", "research", "mechanical", "monitor", "other"];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

function logLine(msg) {
  try {
    mkdirSync(dirname(LOG_FILE), { recursive: true });
    appendFileSync(LOG_FILE, new Date().toISOString() + " " + String(msg).replace(/[^\x20-\x7E]/g, "?").slice(0, 300) + "\n");
  } catch { /* nowhere to log; stay silent */ }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function readJson(file) {
  // A registry file is written by PowerShell 5.1 and carries a byte order mark.
  return JSON.parse(readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
}

// The text of the first user message of a subagent transcript, or null.
export function briefOf(file) {
  let text;
  try {
    text = readFileSync(file, "utf8");
  } catch {
    return null;
  }
  for (const raw of text.split("\n")) {
    if (raw.trim() === "") continue;
    let o;
    try { o = JSON.parse(raw); } catch { return null; }
    const c = o && o.message && o.message.content;
    if (typeof c === "string") return c;
    if (Array.isArray(c)) {
      const t = c.filter((b) => b && b.type === "text" && typeof b.text === "string").map((b) => b.text).join("\n");
      return t === "" ? null : t;
    }
    return null;
  }
  return null;
}

export function taskOf(brief) {
  if (typeof brief !== "string") return null;
  const first = brief.split(/\r?\n/).find((l) => l.trim() !== "");
  const m = first === undefined ? null : /\bT-\d{4,}\b/.exec(first);
  return m ? m[0] : null;
}

export function workTypeOf(brief, agentType) {
  if (typeof brief === "string") {
    for (const line of brief.split(/\r?\n/).filter((l) => l.trim() !== "").slice(0, 3)) {
      const m = /\bwork[-_ ]?type\s*[:=]\s*([a-z]+)|\bwork\s*[:=]\s*([a-z]+)/i.exec(line);
      const t = m ? (m[1] || m[2]).toLowerCase() : null;
      if (t !== null && WORK_TYPES.includes(t)) return t;
    }
  }
  return agentType === "Explore" || agentType === "Plan" ? "research" : "other";
}

function modelOf(metaFile, transcriptFile) {
  try {
    const m = readJson(metaFile);
    if (m && typeof m.model === "string" && /^[!-~]{1,80}$/.test(m.model)) return m.model;
  } catch { /* no meta file yet */ }
  try {
    for (const raw of readFileSync(transcriptFile, "utf8").split("\n")) {
      if (!raw.includes('"assistant"')) continue;
      const o = JSON.parse(raw);
      const model = o && o.message && o.message.model;
      if (typeof model === "string" && /^[!-~]{1,80}$/.test(model)) return model;
    }
  } catch { /* not there, or a partial line */ }
  return null;
}

// The parent Orc's lane: the lane folder of its registry cwd, else its Orc letter, else null.
export function domainOf(parentId) {
  try {
    const rec = readJson(join(REGISTRY_DIR, parentId + ".json"));
    for (const cwd of [rec.cwd, rec.firstCwd]) {
      const m = typeof cwd === "string" ? /[\\/]orcs[\\/]([^\\/]+)/.exec(cwd) : null;
      if (m) return m[1];
    }
    const letter = [rec.label, rec.owner].find((v) => typeof v === "string" && /^[A-Z]$/.test(v));
    return letter === undefined ? null : letter;
  } catch {
    return null;
  }
}

// What a registry record says a session is. A record's own kind wins; a record written before kind existed is
// read by its role, and one with no role but a fleet origin and a parent is a Warg (wezspawn made it).
export function kindOfRecord(rec) {
  if (!rec || typeof rec !== "object") return null;
  if (["thrall", "orc", "warg"].includes(rec.kind)) return rec.kind;
  if (rec.role === "master") return "thrall";
  if (rec.role === "orchestrator") return "orc";
  if (!rec.role && rec.origin === "fleet" && typeof rec.parent === "string" && rec.parent !== "") return "warg";
  return null;
}

function asciiArg(v, max) {
  return typeof v === "string" && v.length >= 1 && v.length <= max && !/[^!-~]/.test(v) ? v : null;
}

async function workCli() {
  const mod = await import(new URL("../fleet-db/work-cli.mjs", import.meta.url));
  return mod.main;
}

// Runs one `work` verb in this process. Returns the exit code; every line goes to the log.
async function runWork(argv) {
  let main;
  try {
    main = await workCli();
  } catch (e) {
    logLine("cannot load fleet-db/work-cli.mjs (Node 24 needed): " + e.message);
    return 1;
  }
  const env = { ...process.env, HORDE_WORK_BUSY_MS: BUSY_MS };
  const say = (s) => logLine("work " + argv[0] + ": " + s);
  let code = 1;
  try {
    code = main(argv, env, say, say);
  } catch (e) {
    logLine("work " + argv[0] + " threw: " + e.message);
  }
  if (code !== 0) logLine("work " + argv[0] + " exit " + code);
  return code;
}

async function waitFor(file) {
  const until = Date.now() + WAIT_MS;
  while (!existsSync(file) && Date.now() < until) await sleep(100);
  return existsSync(file);
}

async function onAgent(input, stopping) {
  const parent = typeof input.session_id === "string" ? input.session_id.toLowerCase() : "";
  const agentId = input.agent_id;
  if (!UUID.test(parent) || asciiArg(agentId, 200) === null) {
    logLine("skipped: payload has no usable session_id or agent_id");
    return;
  }
  const tp = typeof input.transcript_path === "string" ? input.transcript_path : "";
  const dir = tp === "" ? "" : join(dirname(tp), basename(tp, ".jsonl"), "subagents");
  const file = typeof input.agent_transcript_path === "string" && input.agent_transcript_path !== ""
    ? input.agent_transcript_path : (dir === "" ? "" : join(dir, "agent-" + agentId + ".jsonl"));
  if (file !== "" && basename(file, ".jsonl") !== "agent-" + agentId) {
    logLine("agent id " + agentId + " differs from its transcript file name " + basename(file));
  }
  let brief = null;
  if (file !== "") {
    if (stopping || await waitFor(file)) brief = briefOf(file);
  }
  const agentType = asciiArg(input.agent_type, 80);
  const argv = ["start", "--kind", "agent", "--parent-session", parent, "--agent-id", agentId, "--work-type", workTypeOf(brief, input.agent_type)];
  if (agentType !== null) argv.push("--agent-type", agentType);
  const task = taskOf(brief);
  if (task !== null) argv.push("--task", task);
  const domain = domainOf(parent);
  if (domain !== null) argv.push("--domain", domain);
  const model = file === "" ? null : modelOf(file.replace(/\.jsonl$/, ".meta.json"), file);
  if (model !== null) argv.push("--model", model);
  await runWork(argv);
  if (stopping) await runWork(["end", "--parent-session", parent, "--agent-id", agentId, "--outcome", "done"]);
}

async function onSessionEnd(input) {
  const sid = typeof input.session_id === "string" ? input.session_id.toLowerCase() : "";
  if (!UUID.test(sid)) return;
  let rec;
  try {
    rec = readJson(join(REGISTRY_DIR, sid + ".json"));
  } catch {
    return; // not in the registry: not a fleet session
  }
  if (kindOfRecord(rec) !== "warg") return;
  await runWork(["end", "--session", sid, "--outcome", "done"]);
}

async function main() {
  const watchdog = setTimeout(() => { logLine("watchdog: gave up after " + WATCHDOG_MS + " ms"); process.exit(0); }, WATCHDOG_MS);
  try {
    let input = null;
    try {
      input = JSON.parse(readFileSync(0, "utf8").replace(/^\uFEFF/, ""));
    } catch {
      logLine("bad or empty stdin");
    }
    if (input && typeof input === "object") {
      const ev = input.hook_event_name;
      if (ev === "SubagentStart") await onAgent(input, false);
      else if (ev === "SubagentStop") await onAgent(input, true);
      else if (ev === "SessionEnd") await onSessionEnd(input);
    }
  } catch (e) {
    logLine("failed: " + (e && e.message));
  }
  clearTimeout(watchdog);
  process.exit(0);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) await main();
