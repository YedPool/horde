// horde-status-guard - PostToolUse hook. After a session writes an Orc's status card any way other than
// `horde status set`, it checks the card with the panel's own reader and, when the card would not be
// read, puts the last good copy back and hands the exact problems to the session.
//
// WHY. The founder's phone shows each Orc's card from <lane folder>\status.txt. Hand-written cards broke
// a rule now and then (a bare "PR 68", a path, 121 characters, a byte-order mark) and the card then read
// "no status written". `horde status set` is the one writer that cannot write such a card; this hook is
// the net under every other way of writing one (T-0246).
//
// FIRES ON
//   Write, Edit, MultiEdit whose file_path is <...>\orcs\<one folder>\status.txt (/ or \, any case).
//   Bash, PowerShell whose command mentions status.txt: then every <orcs root>\*\status.txt written in
//     the last 120 s is checked (a shell command does not say which file it touched).
// Everything else exits 0 at once, before anything is spawned. status.retired.txt is never looked at.
//
// ORCS ROOT for a shell command: the nearest ancestor of the payload's cwd named "orcs" (or an "orcs"
// folder directly under the cwd), else an ...\orcs\ path written in the command, else the folder named
// by the environment variable HORDE_STATUS_ORCS_ROOT (the tests set it), else nothing: exit 0.
//
// FEEDBACK. Exit 2 with the report on stderr: for a PostToolUse hook the session host shows stderr to the model (the
// tool already ran, so it cannot block, but the model reads the message and fixes the card). The report
// names the file, every problem, whether the last good copy was put back, and the fix.
//
// FAIL OPEN. Any internal error (bad stdin JSON, pwsh missing, the checker past 8 s, anything thrown)
// logs ONE line and exits 0. A guard must never be why a turn hangs or a file cannot be written.
// Log: %USERPROFILE%\Documents\Code\.wezfleet\accuracy\status-guard-hook.log, or HORDE_STATUS_GUARD_LOG
// (a full file path) when set.
//
// NOT INSTALLED BY THIS FILE. The settings.json entry is in the pull request notes; a person installs it.

import { readFileSync, appendFileSync, mkdirSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { homedir } from "node:os";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const CHECKER = join(HERE, "horde-status-guard-check.ps1");
const FILE_TOOLS = new Set(["Write", "Edit", "MultiEdit"]);
const SHELL_TOOLS = new Set(["Bash", "PowerShell"]);
const RECENT_MS = 120 * 1000;
const CHILD_TIMEOUT_MS = 8000;
const STATUS_PATH = /[\\/]orcs[\\/][^\\/]+[\\/]status\.txt$/i;
// A path in a shell command that ends in status.txt: no space, quote or shell punctuation inside it, so
// an absolute, relative, drive-letter or UNC (\\host\share\...) spelling is all one token.
const STATUS_TOKEN = /"([^"]*status\.txt)"|'([^']*status\.txt)'|[^\s"'<>|;&()*?]*status\.txt/gi;

const LOG_FILE =
  process.env.HORDE_STATUS_GUARD_LOG || join(homedir(), "Documents", "Code", ".wezfleet", "accuracy", "status-guard-hook.log");

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

// WHICH pwsh. The fleet never relies on the Microsoft Store build (a Store auto-update of PowerShell 7
// killed every pane on 2026-10-16): the MSI install under <ProgramFiles>\PowerShell\7 when it exists,
// "pwsh.exe" on PATH only as the fallback. HORDE_STATUS_GUARD_PWSH names another (the tests use it).
function pwshExe() {
  if (process.env.HORDE_STATUS_GUARD_PWSH) return process.env.HORDE_STATUS_GUARD_PWSH;
  const root = process.env.ProgramW6432 || process.env.ProgramFiles;
  if (root) {
    const msi = join(root, "PowerShell", "7", "pwsh.exe");
    if (existsSync(msi)) return msi;
  }
  return "pwsh.exe";
}

function isDir(p) {
  try { return statSync(p).isDirectory(); } catch { return false; }
}

function absolute(p, cwd) {
  return resolve(typeof cwd === "string" && cwd !== "" ? cwd : process.cwd(), p);
}

function samePath(a, b) {
  return resolve(a).replace(/[\\/]+$/, "").toLowerCase() === resolve(b).replace(/[\\/]+$/, "").toLowerCase();
}

// The lane folder the working folder is in: the ancestor (or itself) whose parent is the orcs root.
function cwdLane(cwd, root) {
  if (typeof cwd !== "string" || cwd === "" || !root) return null;
  let dir = resolve(cwd);
  for (;;) {
    const up = dirname(dir);
    if (up === dir) return null;
    if (samePath(up, root)) return dir;
    dir = up;
  }
}

function findOrcsRoot(cwd, namedFiles) {
  if (typeof cwd === "string" && cwd !== "") {
    let dir = resolve(cwd);
    for (;;) {
      if (/^orcs$/i.test(dir.split(/[\\/]/).pop() || "") && isDir(dir)) return dir;
      const up = dirname(dir);
      if (up === dir) break;
      dir = up;
    }
    const below = join(resolve(cwd), "orcs");
    if (isDir(below)) return below;
  }
  // an orcs path the command itself names (a drive-letter, relative or UNC spelling alike)
  for (const f of namedFiles) {
    const root = dirname(dirname(f));
    if (isDir(root)) return root;
  }
  const env = process.env.HORDE_STATUS_ORCS_ROOT;
  if (env && isDir(env)) return env;
  return null;
}

function recentFolders(orcsRoot) {
  const out = [];
  const now = Date.now();
  let names;
  try { names = readdirSync(orcsRoot); } catch { return out; }
  for (const n of names) {
    const dir = join(orcsRoot, n);
    try {
      const st = statSync(join(dir, "status.txt"));
      if (st.isFile() && now - st.mtimeMs <= RECENT_MS) out.push(dir);
    } catch { /* no status.txt here */ }
  }
  return out;
}

// Runs the checker. Resolves { ok, lines } or { ok: false } after logging why.
function runChecker(folders, restorable) {
  return new Promise((resolveRun) => {
    const args = ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", CHECKER, "-Folders", folders.join("*"), "-RestoreFolders", restorable.join("*") || "-"];
    let out = "";
    let done = false;
    let child;
    const finish = (r) => { if (!done) { done = true; clearTimeout(timer); resolveRun(r); } };
    const timer = setTimeout(() => {
      try { child && child.kill(); } catch { /* ignore */ }
      logLine("checker timed out after " + CHILD_TIMEOUT_MS + " ms");
      finish({ ok: false, lines: [] });
    }, CHILD_TIMEOUT_MS);
    try {
      child = spawn(pwshExe(), args, { windowsHide: true, stdio: ["ignore", "pipe", "ignore"] });
    } catch (e) {
      logLine("could not start pwsh: " + (e && e.message));
      return finish({ ok: false, lines: [] });
    }
    child.on("error", (e) => { logLine("pwsh error: " + (e && e.code ? e.code : e && e.message)); finish({ ok: false, lines: [] }); });
    child.stdout.on("data", (d) => { out += d.toString("utf8"); });
    child.on("close", (code) => {
      if (done) return; // an error event already settled this run and logged it
      if (code !== 0 && code !== 3) { logLine("checker exited " + code); return finish({ ok: false, lines: [] }); }
      const lines = out.split(/\r?\n/).filter((l) => l.startsWith("rejected\t"));
      if (code === 3 && lines.length === 0) { logLine("checker exited 3 with no report"); return finish({ ok: false, lines: [] }); }
      finish({ ok: true, lines });
    });
  });
}

async function main() {
  let input;
  try { input = JSON.parse(readStdin()); } catch (e) { logLine("stdin parse failed: " + e.message); return 0; }
  if (!input || typeof input.tool_name !== "string") return 0;
  const ti = input.tool_input || {};

  let folders = [];
  let restorable = [];
  if (FILE_TOOLS.has(input.tool_name)) {
    const file = ti.file_path;
    if (typeof file !== "string" || file === "") return 0;
    if (!STATUS_PATH.test(absolute(file, input.cwd))) return 0;
    folders = [dirname(absolute(file, input.cwd))];
    restorable = folders;
  } else if (SHELL_TOOLS.has(input.tool_name)) {
    const command = ti.command;
    if (typeof command !== "string" || !/status\.txt/i.test(command)) return 0;
    // A quoted path may hold spaces, so quoted strings are tokens of their own.
    const named = [...command.matchAll(STATUS_TOKEN)].map((m) => absolute(m[1] || m[2] || m[0], input.cwd)).filter((p) => STATUS_PATH.test(p));
    const root = findOrcsRoot(input.cwd, named);
    if (!root) return 0;
    // Only the cards the command names, or its own lane, are looked at: another Orc's bad card is its own
    // Orc's hook's business, and is neither reported nor restored here.
    const mine = [];
    for (const f of named.map((p) => dirname(p))) if (samePath(dirname(f), root)) mine.push(f);
    const own = cwdLane(input.cwd, root);
    if (own) mine.push(own);
    folders = recentFolders(root).filter((d) => mine.some((m) => samePath(m, d)));
    restorable = folders;
  } else {
    return 0;
  }
  if (folders.length === 0) return 0;

  const res = await runChecker(folders, restorable);
  if (!res.ok || res.lines.length === 0) return 0;

  const report = [];
  for (const line of res.lines) {
    const p = line.split("\t");
    const idx = Number(p[1]);
    const where = join(folders[idx] || "?", "status.txt");
    report.push("status-guard: " + where + " would not be read by the phone panel (it would show \"no status written\"):");
    for (const problem of p.slice(3)) report.push("  - " + problem);
    report.push(p[2] === "restored"
      ? "  The last good copy (.status.last-good.txt) was put back, so the card on the phone is the previous one, not this edit."
      : p[2] === "reported"
        ? "  NOT restored: this command did not name this card, so it may be another Orc's edit in progress. Its Orc should fix it."
        : "  No good copy existed, so the bad file was left as it is.");
  }
  report.push("Fix: write the card with `horde status set -Doing <text> -Finished <text> -Blocked <no|sentence>` (add -WaitingOn <text> if something is awaited); it refuses a bad card and writes nothing.");
  process.stderr.write(report.join("\n") + "\n");
  return 2;
}

// process.exitCode, not process.exit(): exiting at once can cut off a large stderr write on a pipe.
main().then((c) => { process.exitCode = c; }, (e) => { logLine("internal error: " + (e && e.message)); process.exitCode = 0; });
