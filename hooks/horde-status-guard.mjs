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

function findOrcsRoot(cwd, command) {
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
  const m = /([A-Za-z]:[\\/][^"'*?<>|\r\n]*?[\\/]orcs)[\\/]/i.exec(command || "");
  if (m && isDir(m[1])) return m[1];
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
function runChecker(folders) {
  return new Promise((resolveRun) => {
    const args = ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", CHECKER, "-Folders", folders.join("*")];
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
  if (FILE_TOOLS.has(input.tool_name)) {
    const file = ti.file_path;
    if (typeof file !== "string" || !STATUS_PATH.test(file)) return 0;
    folders = [dirname(resolve(file))];
  } else if (SHELL_TOOLS.has(input.tool_name)) {
    const command = ti.command;
    if (typeof command !== "string" || !/status\.txt/i.test(command)) return 0;
    const root = findOrcsRoot(input.cwd, command);
    if (!root) return 0;
    folders = recentFolders(root);
  } else {
    return 0;
  }
  if (folders.length === 0) return 0;

  const res = await runChecker(folders);
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
      : "  No good copy existed, so the bad file was left as it is.");
  }
  report.push("Fix: write the card with `horde status set -Doing <text> -Finished <text> -Blocked <no|sentence>` (add -WaitingOn <text> if something is awaited); it refuses a bad card and writes nothing.");
  process.stderr.write(report.join("\n") + "\n");
  return 2;
}

main().then((c) => process.exit(c), (e) => { logLine("internal error: " + (e && e.message)); process.exit(0); });
