// SIGN-IN IN A REAL BROWSER, for relays/cloudflare/test/test-cloudflare-accounts.ps1: headless Chrome,
// driven over its debugging protocol (CDP) as surfaces/pwa/test/browser-drive.mjs drives it, opens the
// built app served by a local dev of the real Worker, and signs in through the local fake provider
// (fake-oidc.mjs) - every redirect, cookie and policy is Chrome's own: the sign-in screen, the button,
// the trip to the provider and back, the session cookie as Chrome keeps it (HttpOnly, Secure,
// SameSite=Lax, __Host-), the Account screen, Sign out, and a refused sign-in's word on the screen.
//
//   node browser-signin.mjs <dev origin> <fake provider origin> <chrome.exe> <profile folder> <machine key id>
//
// The machine is one the suite registered to this account beforehand: the Account screen lists it, and
// its Remove button removes it (the suite then sees the machine refused).
//
// Prints one [PASS] or [FAIL] line a check, then [DONE] <failures>. Chrome is ended when it is done.
import { spawn, execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const [, , origin, provider, chromePath, profileDir, machineKeyId] = process.argv;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
function check(ok, name, detail = "") {
  if (!ok) failures++;
  process.stdout.write((ok ? "[PASS] " : "[FAIL] ") + name + (ok || !detail ? "" : " (" + String(detail).replace(/[^\x20-\x7e]/g, "?").slice(0, 300) + ")") + "\n");
}

const chrome = spawn(chromePath, ["--headless=new", "--remote-debugging-port=0", "--user-data-dir=" + profileDir, "--no-first-run", "--no-default-browser-check", "--disable-extensions",
  "--disable-background-networking", "--disable-sync", "--disable-component-update", "--window-size=412,915", "about:blank"], { stdio: "ignore" });
// Set once the page's socket is open: asks Chrome to close itself, as browser-drive.mjs ends it.
let closeBrowser = async () => {};
try {
  const portFile = join(profileDir, "DevToolsActivePort");
  for (let i = 0; i < 200 && !existsSync(portFile); i++) await sleep(100);
  if (!existsSync(portFile)) throw new Error("Chrome did not open its debugging port");
  const debugPort = readFileSync(portFile, "utf8").split(/\r?\n/)[0];
  let targets = [];
  for (let i = 0; i < 50 && !targets.some((t) => t.type === "page"); i++) { try { targets = await (await fetch("http://127.0.0.1:" + debugPort + "/json/list")).json(); } catch (e) { /* not yet */ } if (!targets.some((t) => t.type === "page")) await sleep(100); }
  const ws = new WebSocket(targets.find((t) => t.type === "page").webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let nextId = 1;
  const waiting = new Map();
  const problems = [];
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && waiting.has(m.id)) { const w = waiting.get(m.id); waiting.delete(m.id); if (m.error) w.reject(new Error(m.error.message)); else w.resolve(m.result); return; }
    if (m.method === "Runtime.exceptionThrown") problems.push("exception: " + (m.params.exceptionDetails.exception ? m.params.exceptionDetails.exception.description : m.params.exceptionDetails.text));
    if (m.method === "Log.entryAdded" && /Content Security Policy/i.test(m.params.entry.text)) problems.push("log: " + m.params.entry.text);
  };
  const cdp = (method, params = {}) => new Promise((resolve, reject) => { const id = nextId++; waiting.set(id, { resolve, reject }); ws.send(JSON.stringify({ id, method, params })); });
  closeBrowser = () => cdp("Browser.close");
  await cdp("Page.enable");
  await cdp("Runtime.enable");
  await cdp("Log.enable");
  await cdp("Network.enable");
  const evaluate = async (expression, userGesture = false) => {
    const r = await cdp("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true, userGesture });
    if (r.exceptionDetails) throw new Error("in the page: " + (r.exceptionDetails.exception ? r.exceptionDetails.exception.description : r.exceptionDetails.text));
    return r.result.value;
  };
  const until = async (expression, timeoutMs = 20000) => {
    const end = Date.now() + timeoutMs;
    for (;;) {
      const v = await evaluate(expression).catch(() => null);
      if (v) return v;
      if (Date.now() > end) return null;
      await sleep(100);
    }
  };
  const shown = (id) => "(document.getElementById('" + id + "') && !document.getElementById('" + id + "').hidden)";
  const sessionCookie = async () => (await cdp("Network.getCookies", { urls: [origin + "/"] })).cookies.find((c) => c.name === "__Host-horde-session") || null;

  await fetch(provider + "/scenario", { method: "POST", body: "{}" });
  await cdp("Page.navigate", { url: origin + "/app/index.html" });
  check(!!(await until(shown("signInView"))), "the app opens on the sign-in screen while the browser is not signed in");
  check(await evaluate("document.getElementById('accountBtn').hidden"), "with no Account button");
  await evaluate("document.getElementById('signInBtn').click()", true);
  check(!!(await until("location.pathname === '/app/index.html' && " + shown("emptyView") + " && !" + shown("signInView") + " && !document.getElementById('accountBtn').hidden")), "Sign in with Google goes to the provider and comes back to the app, signed in", await evaluate("location.href").catch((e) => e.message));
  const c = await sessionCookie();
  check(!!c && c.httpOnly === true && c.secure === true && c.sameSite === "Lax" && c.path === "/" && !c.domain.startsWith("."), "Chrome keeps the session as the relay set it: HttpOnly, Secure, SameSite=Lax, Path=/, this host only", JSON.stringify(c));
  check((await evaluate("document.cookie")).indexOf("horde-session") < 0, "and no script of the page can read it");
  await evaluate("document.getElementById('accountBtn').click()", true);
  check(!!(await until(shown("accountView") + " && document.getElementById('accountWho').textContent.indexOf('founder@example.test') >= 0")), "the Account screen says who is signed in", await evaluate("document.getElementById('accountWho').textContent"));
  const listed = await evaluate("Array.from(document.querySelectorAll('#machineList li')).map((li) => li.textContent).join('|')");
  check(listed === "work - machine " + machineKeyId.slice(0, 12) + "Remove" && (await evaluate("document.getElementById('machineEmpty').hidden")), "and lists the machine registered to it, by horde and key id, with a Remove button", listed);
  await evaluate("window.confirm = () => true; document.querySelector('#machineList li button').click()", true);
  check(!!(await until("document.querySelectorAll('#machineList li').length === 0 && !document.getElementById('machineEmpty').hidden")), "Remove takes it off the account, and the screen says no machine is left");
  await evaluate("document.getElementById('signOutBtn').click()", true);
  check(!!(await until(shown("signInView"))) && (await sessionCookie()) === null, "Sign out ends the session and returns to the sign-in screen, the cookie gone");

  await fetch(provider + "/scenario", { method: "POST", body: JSON.stringify({ forge: true }) });
  await evaluate("document.getElementById('signInBtn').click()", true);
  check(!!(await until("location.pathname === '/app/index.html' && location.hash === '' && " + shown("signInView") + " && document.getElementById('notice').textContent.indexOf('Sign-in was refused') >= 0")), "a sign-in whose token is forged comes back refused, said on the screen, still signed out", await evaluate("document.getElementById('notice').textContent + ' ' + location.href").catch((e) => e.message));
  check((await sessionCookie()) === null, "and leaves no session");
  await fetch(provider + "/scenario", { method: "POST", body: "{}" });
  check(problems.length === 0, "nothing in the page threw, and the policy refused nothing", problems.join(" | "));
} catch (e) {
  check(false, "the browser ran the sign-in to its end", e.message);
} finally {
  // Closed, then the tree this script started ended, so the profile folder is free for the suite to
  // delete (browser-drive.mjs, shutdown).
  try { await closeBrowser(); } catch (e) { /* it may be gone */ }
  await sleep(500);
  try { if (chrome.exitCode === null) execFileSync("taskkill", ["/PID", String(chrome.pid), "/T", "/F"], { stdio: "ignore" }); } catch (e) { /* gone */ }
  await sleep(300);
}
process.stdout.write("[DONE] " + failures + "\n");
process.exit(failures === 0 ? 0 : 1);
