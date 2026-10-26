// horde-merge-guard - PreToolUse hook. Refuses a bare `gh pr merge` (or the merge endpoint of `gh api`)
// against YedPool/horde from a Bash or PowerShell tool call, and says to use `horde merge` (T-0247).
//
// WHY. `horde merge OWNER/REPO#N -Task T-NNNN -State ... -By ...` merges with --merge pinned to the head it
// read, records the task ledger, tells the warchief and the analyst, and queues the merge for the nightly guards
// run (test\guards.txt; with -Guards now it runs them first). A hand-typed `gh pr merge` does none of
// that: on 2026-10-21 four merges skipped the repo-wide guards and one turned main red. The command makes
// the guard run deterministic only if the hand path is closed.
//
// WHAT IT REFUSES. A tool call whose command, read as shell words (not as text), runs
//   gh pr merge ...                     -R YedPool/horde, --repo YedPool/horde, a pull-request URL of
//                                       YedPool/horde, or no repository at all while the working folder's
//                                       git remote is YedPool/horde;
//   gh api .../repos/YedPool/horde/pulls/<n>/merge     (the same merge, by the API).
// Found inside `cd x && ...`, pipes and lists, $( ) and backticks, bash -c / sh -c / cmd /c /
// powershell -Command / pwsh -Command / eval / Invoke-Expression strings, `&` calls, env prefixes, a full path
// or .exe for gh, and Start-Process gh -ArgumentList.
//
// WHAT IT ALLOWS. Everything else: other repositories (-R other/repo, or a folder whose remotes are not
// YedPool/horde), `gh pr view|list|checks|diff|status|create|ready|close|comment`, `gh api` for anything but
// the merge endpoint, `horde merge ...`, and TEXT that merely mentions the command: an echo, a commit message
// or a quoted argument, a comment, a here-document or here-string body.
//
// HORDE MERGE'S OWN gh CALL IS NOT BLOCKED, BECAUSE THIS HOOK NEVER SEES IT. A PreToolUse hook is run by the
// session host for a tool call the model makes; `horde merge` starts gh itself as a child process of that
// one Bash/PowerShell call, and the host does not run hooks for a program's children. The tool call the
// hook does see is `horde merge ...`, whose program is horde. test/test-merge-guard-hook.ps1 holds both.
//
// EXIT. 0 allows. 2 refuses: stderr is shown to the model, and the tool does not run.
// FAIL OPEN. Bad stdin, a missing git, anything thrown: log ONE line and exit 0. A guard must never be why a
// turn hangs. Log: %USERPROFILE%\Documents\Code\.wezfleet\accuracy\merge-guard-hook.log, or
// HORDE_MERGE_GUARD_LOG (a full file path) when set.
//
// NOT INSTALLED BY THIS FILE. A person registers it in settings.json as a PreToolUse hook for Bash and
// PowerShell: {"matcher": "Bash|PowerShell", "hooks": [{"type": "command", "command": "node <repo>/hooks/horde-merge-guard.mjs"}]}.

import { readFileSync, appendFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { homedir } from "node:os";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const SHELL_TOOLS = new Set(["Bash", "PowerShell"]);
const GUARDED = "yedpool/horde";
const MAX_DEPTH = 4;
const GIT_TIMEOUT_MS = 4000;

const LOG_FILE =
  process.env.HORDE_MERGE_GUARD_LOG || join(homedir(), "Documents", "Code", ".wezfleet", "accuracy", "merge-guard-hook.log");

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

// ---- reading a command line as shell words -------------------------------------------------------------

// Splits a command line into simple commands, each an array of words (quotes removed). Anything inside quotes
// is one word's text and never an operator. Returns { commands, nested }: nested are the texts of $( ) and
// backtick substitutions found outside single quotes, to be read as command lines of their own.
export function parseCommandLine(text) {
  const commands = [];
  const nested = [];
  let words = [];
  let cur = "";
  let inWord = false;
  let heredocs = []; // delimiters opened on this line, whose bodies start at the next newline
  const n = text.length;
  let i = 0;

  const endWord = () => { if (inWord) { words.push(cur); cur = ""; inWord = false; } };
  const endCommand = () => { endWord(); if (words.length) commands.push(words); words = []; };

  const closeParen = (from) => {
    // index of the ")" matching an already-open "(" at depth 1, respecting simple quotes; -1 if none.
    let depth = 1;
    let q = "";
    for (let j = from; j < n; j++) {
      const c = text[j];
      if (q) { if (c === q) q = ""; else if (c === "\\" && q === '"') j++; continue; }
      if (c === "'" || c === '"') { q = c; continue; }
      if (c === "(") depth++;
      else if (c === ")") { depth--; if (depth === 0) return j; }
    }
    return -1;
  };

  while (i < n) {
    const c = text[i];
    const next = text[i + 1];

    if (c === "\n" || c === "\r") {
      endCommand();
      i++;
      if (c === "\r" && next === "\n") i++;
      // here-document bodies start now: skip lines until each delimiter alone on a line
      while (heredocs.length) {
        const delim = heredocs.shift();
        let found = false;
        while (i < n) {
          let e = text.indexOf("\n", i);
          if (e < 0) e = n;
          const line = text.slice(i, e).replace(/\r$/, "");
          i = Math.min(e + 1, n);
          if (line.trim() === delim) { found = true; break; }
        }
        if (!found) break;
      }
      continue;
    }
    if (c === " " || c === "\t") { endWord(); i++; continue; }
    // a comment starts at a word start
    if (c === "#" && !inWord) { while (i < n && text[i] !== "\n") i++; continue; }
    // PowerShell here-string @' ... '@  or  @" ... "@
    if (c === "@" && !inWord && (next === "'" || next === '"') && /^[ \t]*\r?\n/.test(text.slice(i + 2))) {
      const close = (next === "'" ? "\n'@" : '\n"@');
      const e = text.indexOf(close, i + 2);
      endWord();
      words.push("");
      inWord = false;
      i = e < 0 ? n : e + close.length;
      continue;
    }
    if (c === "'") {
      inWord = true;
      const e = text.indexOf("'", i + 1);
      if (e < 0) { cur += text.slice(i + 1); i = n; } else { cur += text.slice(i + 1, e); i = e + 1; }
      continue;
    }
    if (c === '"') {
      inWord = true;
      i++;
      while (i < n && text[i] !== '"') {
        if (text[i] === "\\" && (text[i + 1] === '"' || text[i + 1] === "\\")) { cur += text[i + 1]; i += 2; continue; }
        if (text[i] === "`" && text[i + 1] === '"') { cur += '"'; i += 2; continue; }
        if (text[i] === "$" && text[i + 1] === "(") {
          const e = closeParen(i + 2);
          if (e > 0) { nested.push(text.slice(i + 2, e)); cur += " "; i = e + 1; continue; }
        }
        cur += text[i];
        i++;
      }
      i++; // the closing quote
      continue;
    }
    if (c === "$" && next === "(") {
      const e = closeParen(i + 2);
      if (e > 0) { nested.push(text.slice(i + 2, e)); inWord = true; cur += " "; i = e + 1; continue; }
    }
    if (c === "`") {
      // a backtick pair is command substitution in sh; in PowerShell a lone backtick is an escape, so only a pair counts
      const e = text.indexOf("`", i + 1);
      if (e > 0 && !/\s/.test(text[i + 1] || " ")) { nested.push(text.slice(i + 1, e)); inWord = true; cur += " "; i = e + 1; continue; }
      i++;
      continue;
    }
    if (c === "<" && next === "<" && text[i + 2] !== "<") {
      // here-document: remember the delimiter; the body starts at the next newline
      endWord();
      let j = i + 2;
      if (text[j] === "-") j++;
      while (text[j] === " " || text[j] === "\t") j++;
      let d = "";
      const q = text[j] === "'" || text[j] === '"' ? text[j] : "";
      if (q) { j++; while (j < n && text[j] !== q) d += text[j++]; j++; }
      else { while (j < n && !/[\s;&|<>()]/.test(text[j])) d += text[j++]; }
      if (d) heredocs.push(d);
      i = j;
      continue;
    }
    if (c === ";" || c === "|" || c === "&" || c === "(" || c === ")") {
      // a lone & directly after a word start is a call operator (& gh ...), not a separator
      if (c === "&" && !inWord && words.length === 0 && text[i + 1] !== "&") { i++; continue; }
      endCommand();
      i++;
      continue;
    }
    if (c === "\\" && next !== undefined && next !== "\n" && next !== "\r" && /[ "'$`;&|()<>#]/.test(next)) {
      // sh escape of a special character
      inWord = true;
      cur += next;
      i += 2;
      continue;
    }
    inWord = true;
    cur += c;
    i++;
  }
  endCommand();
  return { commands, nested };
}

// ---- deciding whether one simple command is the guarded merge ---------------------------------------------

const PREFIX_WORDS = new Set(["{", "}", "!", "if", "then", "else", "elif", "fi", "do", "done", "while", "until", "time", "exec", "command", "builtin", "sudo", "nohup", "env", "call", "&", ".", "noglob", "nice"]);

function programName(word) {
  const base = String(word).split(/[\\/]/).pop().toLowerCase();
  return base.replace(/\.(exe|cmd|bat|ps1)$/, "");
}

function stripPrefix(words) {
  let k = 0;
  while (k < words.length && (PREFIX_WORDS.has(words[k]) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[k]) || /^\$env:[A-Za-z_]\w*=/i.test(words[k]))) k++;
  return words.slice(k);
}

function repoOf(value) {
  const v = String(value).trim().replace(/^https?:\/\//i, "").replace(/^git@github\.com:/i, "").replace(/^github\.com[/:]/i, "").replace(/\.git$/i, "").replace(/\/+$/, "");
  return v.toLowerCase();
}

function isHordeRepoUrl(word) {
  return /github\.com[/:]yedpool\/horde(?:\.git)?(?:[/#?]|$)/i.test(word);
}

// the working folder's git remotes name YedPool/horde?  null when it cannot be told.
function folderIsHorde(cwd) {
  if (typeof cwd !== "string" || cwd === "") return null;
  const r = spawnSync("git", ["-C", cwd, "remote", "-v"], { encoding: "utf8", timeout: GIT_TIMEOUT_MS, windowsHide: true });
  if (r.error || r.status !== 0) return null;
  return /[:/]yedpool\/horde(?:\.git)?(?:\s|$)/i.test(r.stdout);
}

// words: the command with its prefix stripped (program first). cwd: where it would run.
function ghMergeVerdict(words, cwd) {
  const args = words.slice(1);
  const positional = [];
  let repoFlag = null;
  let url = false;
  for (let k = 0; k < args.length; k++) {
    const a = args[k];
    if (a === "-R" || a === "--repo") { repoFlag = args[k + 1] === undefined ? "" : args[k + 1]; k++; continue; }
    if (/^--repo=/.test(a)) { repoFlag = a.slice(7); continue; }
    if (/^-R./.test(a)) { repoFlag = a.slice(2); continue; }
    if (isHordeRepoUrl(a)) url = true;
    if (a.startsWith("-")) continue;
    positional.push(a);
  }
  if (positional[0] === "api") {
    const hit = args.some((a) => /(?:^|[/])repos\/yedpool\/horde\/pulls\/\d+\/merge(?:[?#]|$)/i.test(a));
    return hit ? "api" : null;
  }
  if (!(positional[0] === "pr" && positional[1] === "merge")) return null;
  if (args.some((a) => a === "--help" || a === "-h")) return null; // help text merges nothing
  if (repoFlag !== null) return repoOf(repoFlag) === GUARDED ? "pr" : null;
  if (url) return "pr";
  const horde = folderIsHorde(cwd);
  if (horde === true) return "pr";
  if (horde === null) logLine("could not read the git remotes of " + cwd + "; a bare gh pr merge there is allowed");
  return null;
}

const SHELL_C = new Set(["bash", "sh", "zsh", "dash", "ksh"]);
const PS_NAMES = new Set(["powershell", "pwsh"]);

function findRefused(text, cwd, depth) {
  if (depth > MAX_DEPTH || typeof text !== "string" || text === "") return null;
  const { commands, nested } = parseCommandLine(text);
  let where = cwd;
  for (const raw of commands) {
    const words = stripPrefix(raw);
    if (words.length === 0) continue;
    const prog = programName(words[0]);
    const rest = words.slice(1);

    if (prog === "cd" || prog === "chdir" || prog === "pushd" || prog === "set-location" || prog === "sl") {
      const target = rest.filter((w) => !w.startsWith("-"))[0];
      if (target) where = resolve(where || process.cwd(), target.replace(/^\/([a-zA-Z])\//, "$1:/"));
      continue;
    }
    if (prog === "gh") {
      const v = ghMergeVerdict(words, where);
      if (v) return v;
      continue;
    }
    // programs that run a command string
    let inner = null;
    if (SHELL_C.has(prog)) {
      const k = rest.findIndex((w) => /^-[a-z]*c$/.test(w));
      if (k >= 0 && rest[k + 1] !== undefined) inner = rest.slice(k + 1).join(" ");
    } else if (PS_NAMES.has(prog)) {
      const k = rest.findIndex((w) => /^-(c|command)$/i.test(w));
      if (k >= 0) inner = rest.slice(k + 1).join(" ");
    } else if (prog === "cmd") {
      const k = rest.findIndex((w) => /^\/[ck]$/i.test(w));
      if (k >= 0) inner = rest.slice(k + 1).join(" ");
    } else if (prog === "eval" || prog === "invoke-expression" || prog === "iex") {
      inner = rest.join(" ");
    } else if (prog === "start-process" || prog === "saps" || prog === "start") {
      const flat = rest.flatMap((w) => w.split(",")).filter((w) => w !== "" && !/^-(wait|nonewwindow|passthru|verb|windowstyle|workingdirectory|filepath|argumentlist|noprofile)$/i.test(w));
      if (flat.length && programName(flat[0]) === "gh") {
        const v = ghMergeVerdict(["gh", ...flat.slice(1)], where);
        if (v) return v;
      }
      continue;
    }
    if (inner !== null) {
      const v = findRefused(inner, where, depth + 1);
      if (v) return v;
    }
  }
  for (const sub of nested) {
    const v = findRefused(sub, where, depth + 1);
    if (v) return v;
  }
  return null;
}

export function judge(toolName, command, cwd) {
  if (!SHELL_TOOLS.has(toolName) || typeof command !== "string") return null;
  return findRefused(command, typeof cwd === "string" && cwd !== "" ? cwd : process.cwd(), 0);
}

const MESSAGE =
  "BLOCKED by the horde merge guard: do not merge a YedPool/horde pull request with `gh pr merge` (or the merge API) by hand.\n" +
  "Use: horde merge OWNER/REPO#N -Task T-NNNN -State done|waiting|progress -By <lane> [-On <who>] [-Reason <text>]\n" +
  "For example: horde merge YedPool/horde#320 -Task T-0247 -State done -By F\n" +
  "It merges with a merge commit pinned to the head it read, records the task ledger, tells the warchief and the analyst, and queues the merge so the nightly guards run (test\\guards.txt, horde merge -RunOwed) can name it if it breaks one. A hand merge skips all of that (2026-10-21: four merges skipped the guards and one turned main red).\n" +
  "If horde merge refuses, fix what it names; do not go round it.\n";

function main() {
  let input;
  try { input = JSON.parse(readStdin()); } catch (e) { logLine("stdin parse failed: " + e.message); return 0; }
  if (!input || typeof input.tool_name !== "string") return 0;
  const ti = input.tool_input || {};
  let verdict = null;
  try { verdict = judge(input.tool_name, ti.command, input.cwd); } catch (e) { logLine("internal error: " + (e && e.message)); return 0; }
  if (!verdict) return 0;
  process.stderr.write(MESSAGE);
  logLine("refused a " + verdict + " merge of YedPool/horde");
  return 2;
}

// run only as a script, not when imported (the suite imports parseCommandLine and judge)
const isMain = process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
if (isMain) {
  let code = 0;
  try { code = main(); } catch (e) { logLine("internal error: " + (e && e.message)); code = 0; }
  // process.exitCode, not process.exit(): exiting at once can cut off a large stderr write on a pipe.
  process.exitCode = code;
}
