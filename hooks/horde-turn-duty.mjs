// horde-turn-duty - Stop hook of the session host. A fleet session (an Orc or the Thrall) must keep its decisions list
// (the questions it waits on the founder for) published; when it has not, this hook blocks the stop ONCE and
// tells the session how to publish it (T-0319, parent T-0216).
//
// WHY. The founder reads each Orc's published list on his phone. A list nobody republishes goes stale, and
// nothing else notices. `horde decisions publish` is the writer (PR 349); this hook is the nudge.
//
// ORDER OF WORK, cheapest first, so most turns cost one file read and no process:
//   1. stop_hook_active true  -> exit 0 at once. A session that is stopping BECAUSE of a block is never blocked
//      again, so the hook can never loop.
//   2. the session's state file (<state dir>\<session id>.json: { lastCheckedAt, lastBlockedAt }) says it was
//      checked less than 30 minutes ago -> exit 0. No process is spawned.
//   3. the session is not an Orc or the Thrall in the wezfleet registry (not there, or a Warg) -> record the
//      check, exit 0.
//   4. run the checks (CHECKS below) for this session's Orc letter, in parallel, each with an 8 s timeout.
//      Any check that finds the duty undone makes ONE block whose reason holds every failed check's text.
//
// ONE BLOCK PER 30 MINUTES. lastCheckedAt is written on every path that ran the checks, a block included, and the
// state file is written (atomically) BEFORE the block is printed: if the write fails the hook does not block,
// since a block it cannot remember would come back every turn.
//
// FAIL OPEN. A check that cannot tell (horde not found, fleet.db missing - "run horde db init" - a timeout, bad
// JSON, anything thrown) logs one line and counts as done; the check is recorded as made, so it is not retried
// every turn. Bad stdin, a state directory that cannot be written: log, exit 0. The hook must never stop a session
// because the hook itself is broken.
//
// KNOWN LIMIT. `horde decisions published` cannot tell "this Orc has never published" from "this Orc has no orc
// row in fleet.db": both read as no list, and both block (once per 30 minutes) with the publish instruction,
// whose own refusal then names the missing row.
//
// THE THRALL is the registry's role "master"; its list is read under its label (M), which is the letter fleet.db
// keeps for it. An Orc is role "orchestrator" with its lane letter as label. Any other role (a Warg) is left alone.
//
// ENVIRONMENT (the tests set these; production sets none):
//   HORDE_TURN_DUTY_STATE_DIR   state folder           (default %USERPROFILE%\.horde\turn-duty)
//   HORDE_TURN_DUTY_REGISTRY    registry sessions dir  (default %USERPROFILE%\Documents\Code\.wezfleet\registry\sessions)
//   HORDE_TURN_DUTY_HORDE       the horde command      (default "horde", found on PATH)
//   HORDE_TURN_DUTY_LOG         log file, full path    (default ...\.wezfleet\accuracy\turn-duty-hook.log)
//   HORDE_TURN_DUTY_TIMEOUT_MS  per-check timeout      (default 8000)
//   HORDE_TURN_DUTY_TEST_TASKLIST=1  switches the disabled task-list check on, for the suite only
//
// NOT INSTALLED BY THIS FILE. The settings.json entry is in the pull request notes; a person installs it.

import { readFileSync, writeFileSync, renameSync, appendFileSync, mkdirSync, existsSync, unlinkSync } from "node:fs";
import { join, dirname } from "node:path";
import { homedir } from "node:os";
import { spawn } from "node:child_process";

const THROTTLE_MS = 30 * 60 * 1000;
const FRESH_MS = 30 * 60 * 1000;
const SESSION_ID = /^[A-Za-z0-9_-]{1,80}$/;
const ORC_LETTER = /^[A-Z][A-Z0-9]{0,3}$/;

const LOG_FILE =
  process.env.HORDE_TURN_DUTY_LOG || join(homedir(), "Documents", "Code", ".wezfleet", "accuracy", "turn-duty-hook.log");
const STATE_DIR = process.env.HORDE_TURN_DUTY_STATE_DIR || join(homedir(), ".horde", "turn-duty");
const REGISTRY_DIR =
  process.env.HORDE_TURN_DUTY_REGISTRY || join(homedir(), "Documents", "Code", ".wezfleet", "registry", "sessions");
const HORDE = process.env.HORDE_TURN_DUTY_HORDE || "horde";
const TIMEOUT_MS = Number(process.env.HORDE_TURN_DUTY_TIMEOUT_MS) > 0 ? Number(process.env.HORDE_TURN_DUTY_TIMEOUT_MS) : 8000;

const DECISIONS_REASON = "publish your decisions list with horde decisions publish -File <list.json> (empty list is valid)";
const DECISIONS_SHAPE =
  'list.json shape: {"items":[{"questionNumber":12,"text":"one line","recommendation":"optional","importance":"high|normal|low","blocks":"all|part|none"}]} (questionNumber, recommendation, importance, blocks may be left out)';

// The task list is NOT checked yet. TASKLIST_WRITER_EXISTS flips to true in the one change that lands N's
// numbered-task-list writer, and TASKLIST_VERB is then the verb N names. Until then the check below is a stub
// that only the suite switches on.
const TASKLIST_WRITER_EXISTS = false;
const TASKLIST_VERB = ["tasklist", "published"]; // PLACEHOLDER: N's task-list reader verb, not yet shipped
const TASKLIST_REASON = "update your numbered task list with horde tasklist publish (it has not been written in the last 30 minutes)";

function logLine(msg) {
  try {
    mkdirSync(dirname(LOG_FILE), { recursive: true });
    appendFileSync(LOG_FILE, new Date().toISOString() + " " + String(msg).replace(/\s+/g, " ").slice(0, 300) + "\n");
  } catch { /* nowhere to log; stay silent */ }
}

function readStdin() {
  let text = readFileSync(0, "utf8");
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1); // PS 5.1 redirected stdin carries a BOM
  return text;
}

function readJsonFile(path) {
  try {
    let text = readFileSync(path, "utf8");
    if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
    return JSON.parse(text);
  } catch { return null; }
}

// ---- state: written atomically (a temp file, then a rename) ------------------------------------------------
function readState(sid) {
  const s = readJsonFile(join(STATE_DIR, sid + ".json"));
  const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
  return s && typeof s === "object" ? { lastCheckedAt: num(s.lastCheckedAt), lastBlockedAt: num(s.lastBlockedAt) } : { lastCheckedAt: 0, lastBlockedAt: 0 };
}

function writeState(sid, state) {
  const file = join(STATE_DIR, sid + ".json");
  const tmp = file + "." + process.pid + ".tmp";
  try {
    mkdirSync(STATE_DIR, { recursive: true });
    writeFileSync(tmp, JSON.stringify(state));
    renameSync(tmp, file);
    return true;
  } catch (e) {
    logLine("state write failed: " + (e && e.message));
    try { if (existsSync(tmp)) unlinkSync(tmp); } catch { /* ignore */ }
    return false;
  }
}

// ---- who is this session? ------------------------------------------------------------------------------------
// Returns the Orc letter to check, or null when the duty does not apply to this session.
function dutyLetter(sid) {
  const rec = readJsonFile(join(REGISTRY_DIR, sid + ".json"));
  if (!rec || typeof rec !== "object") return null; // not in the registry: not a fleet session
  if (rec.role !== "orchestrator" && rec.role !== "master") return null; // a Warg (or anything else) has no list
  const label = typeof rec.label === "string" ? rec.label : "";
  if (!ORC_LETTER.test(label)) {
    logLine("session " + sid + " role " + rec.role + " has no usable lane letter label");
    return null;
  }
  return label;
}

// ---- running horde -------------------------------------------------------------------------------------------
// Resolves { ok, out, why }. Never rejects. A .cmd is found and run through cmd.exe, as the shell would.
function runHorde(args) {
  return new Promise((resolveRun) => {
    let out = "";
    let err = "";
    let done = false;
    let child;
    const finish = (r) => { if (!done) { done = true; clearTimeout(timer); resolveRun(r); } };
    const timer = setTimeout(() => {
      try {
        if (child && child.pid && process.platform === "win32") spawn("taskkill", ["/pid", String(child.pid), "/t", "/f"], { windowsHide: true, stdio: "ignore" });
        else if (child) child.kill();
      } catch { /* ignore */ }
      finish({ ok: false, out: "", why: "timed out after " + TIMEOUT_MS + " ms" });
    }, TIMEOUT_MS);
    try {
      child = process.platform === "win32"
        ? spawn(process.env.ComSpec || "cmd.exe", ["/d", "/c", HORDE, ...args], { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] })
        : spawn(HORDE, args, { stdio: ["ignore", "pipe", "pipe"] });
    } catch (e) { return finish({ ok: false, out: "", why: "could not start horde: " + (e && e.message) }); }
    child.on("error", (e) => finish({ ok: false, out: "", why: "horde error: " + (e && e.code ? e.code : e && e.message) }));
    child.stdout.on("data", (d) => { out += d.toString("utf8"); });
    child.stderr.on("data", (d) => { err += d.toString("utf8"); });
    child.on("close", (code) => {
      if (code !== 0) return finish({ ok: false, out: "", why: "horde exited " + code + ": " + (err.trim() || out.trim()).split(/\r?\n/)[0] });
      finish({ ok: true, out, why: "" });
    });
  });
}

// The newest "publishedAt" of this Orc's list in `-Json` output { lists: [ { orc, publishedAt, ... } ] }.
// Resolves { state: "ok" | "due" | "error", why }.
async function listAgeCheck(args, letter, now) {
  const r = await runHorde(args);
  if (!r.ok) return { state: "error", why: r.why };
  const jsonLine = r.out.split(/\r?\n/).filter((l) => l.trimStart().startsWith("{")).pop();
  let parsed;
  try { parsed = JSON.parse(jsonLine); } catch { return { state: "error", why: "output was not JSON" }; }
  if (!parsed || !Array.isArray(parsed.lists)) return { state: "error", why: "output had no lists" };
  const mine = parsed.lists.filter((l) => l && l.orc === letter);
  if (mine.length === 0) return { state: "due", why: "never published" };
  const at = Date.parse(mine[0].publishedAt);
  if (!Number.isFinite(at)) return { state: "error", why: "publishedAt was not a time" };
  return now - at < FRESH_MS ? { state: "ok", why: "" } : { state: "due", why: "last published more than 30 minutes ago" };
}

// THE CHECKS. Adding a duty is adding one entry: { name, enabled(), run(letter, now) -> {state, why}, reason }.
const CHECKS = [
  {
    name: "decisions",
    enabled: () => true,
    run: (letter, now) => listAgeCheck(["decisions", "published", "-Orc", letter, "-Json"], letter, now),
    reason: DECISIONS_REASON + "\n" + DECISIONS_SHAPE,
  },
  {
    // DISABLED until N's numbered-task-list writer exists: it waits for that verb (TASKLIST_VERB above).
    name: "tasklist",
    enabled: () => TASKLIST_WRITER_EXISTS || process.env.HORDE_TURN_DUTY_TEST_TASKLIST === "1",
    run: (letter, now) => listAgeCheck([...TASKLIST_VERB, "-Orc", letter, "-Json"], letter, now),
    reason: TASKLIST_REASON,
  },
];

async function main() {
  let input;
  try { input = JSON.parse(readStdin()); } catch (e) { logLine("stdin parse failed: " + e.message); return 0; }
  if (!input || typeof input !== "object" || Array.isArray(input)) { logLine("stdin was not a JSON object"); return 0; }
  if (input.stop_hook_active) return 0;
  const sid = input.session_id;
  if (typeof sid !== "string" || !SESSION_ID.test(sid)) { logLine("no usable session_id"); return 0; }

  const now = Date.now();
  const state = readState(sid);
  if (now - state.lastCheckedAt < THROTTLE_MS) return 0;

  const letter = dutyLetter(sid);
  if (letter === null) { writeState(sid, { ...state, lastCheckedAt: now }); return 0; }

  const active = CHECKS.filter((c) => c.enabled());
  const results = await Promise.all(active.map(async (c) => {
    try { return await c.run(letter, now); } catch (e) { return { state: "error", why: "threw: " + (e && e.message) }; }
  }));
  const reasons = [];
  results.forEach((r, i) => {
    if (r.state === "error") logLine("check " + active[i].name + " for " + letter + " could not tell (" + r.why + "); passing");
    else if (r.state === "due") reasons.push(active[i].reason);
  });

  const next = { lastCheckedAt: now, lastBlockedAt: reasons.length > 0 ? now : state.lastBlockedAt };
  const saved = writeState(sid, next); // BEFORE the block is printed
  if (reasons.length === 0 || !saved) return 0;
  process.stdout.write(JSON.stringify({ decision: "block", reason: reasons.join("\n") }));
  return 0;
}

// process.exitCode, not process.exit(): exiting at once can cut off a large stdout write on a pipe.
main().then((c) => { process.exitCode = c; }, (e) => { logLine("internal error: " + (e && e.message)); process.exitCode = 0; });
