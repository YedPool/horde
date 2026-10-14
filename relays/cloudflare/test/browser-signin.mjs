// SIGN-IN IN A REAL BROWSER, for relays/cloudflare/test/test-cloudflare-accounts.ps1: headless Chrome,
// driven over its debugging protocol (CDP) as surfaces/pwa/test/browser-drive.mjs drives it, opens the
// built app served by a local dev of the real Worker, and signs in through the local fake provider
// (fake-oidc.mjs) - every redirect, cookie and policy is Chrome's own: the sign-in screen, the button,
// the trip to the provider and back, the session cookie as Chrome keeps it (HttpOnly, Secure,
// SameSite=Lax, __Host-), the Account screen (the machine by its own name and when it was last heard
// from, this phone), the PC offline banner (the account's answer five minutes on by the relay's clock), Sign out,
// deleting the account (relay PR 8c), and a refused sign-in's words on the screen - a limit's own too.
//
//   node browser-signin.mjs <dev origin> <fake provider origin> <chrome.exe> <profile folder> <machine label>
//
// The machine is one the suite registered to this account beforehand, under that label: the Account
// screen lists it, and its Remove button removes it (the suite then sees the machine refused).
//
// Prints one [PASS] or [FAIL] line a check, then [DONE] <failures>. Chrome is ended when it is done.
import { spawn, execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const [, , origin, provider, chromePath, profileDir, machineLabel] = process.argv;
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
  // A paused request (CDP Fetch), handed to the suite's own handler while one is set.
  let onPaused = null;
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.method === "Fetch.requestPaused" && onPaused) { onPaused(m.params); return; }
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
  // The machine read the relay just before (the suite's control): heard from it, at a time of the phone's day.
  check(new RegExp("^work - " + machineLabel + " - heard from [0-9]{1,2} [A-Z][a-z]{2} [0-9]{2}:[0-9]{2}Remove$").test(listed) && (await evaluate("document.getElementById('machineEmpty').hidden")), "and lists the machine registered to it, by horde and the name its grant signed, when the relay last heard from it, with a Remove button", listed);
  check(await evaluate("document.getElementById('pcOffline').hidden && document.getElementById('pcOffline').childNodes.length === 0"), "and a machine heard from just now raises no PC offline banner");
  // FIVE MINUTES LATER BY THE RELAY'S CLOCK: the account's answer is passed through Chrome with its now
  // moved on 300 s (CDP Fetch) - the relay's own lastSeenAt untouched, the phone's clock untouched - so the
  // page sees exactly what a relay would send once the machine had been silent that long.
  const fiveMinutesOn = async (p) => {
    const raw = await cdp("Fetch.getResponseBody", { requestId: p.requestId });
    const body = JSON.parse(raw.base64Encoded ? Buffer.from(raw.body, "base64").toString("utf8") : raw.body);
    body.now += 300000;
    await cdp("Fetch.fulfillRequest", { requestId: p.requestId, responseCode: p.responseStatusCode, responseHeaders: p.responseHeaders, body: Buffer.from(JSON.stringify(body), "utf8").toString("base64") });
  };
  onPaused = fiveMinutesOn;
  await cdp("Fetch.enable", { patterns: [{ urlPattern: "*/v1/account", requestStage: "Response" }] });
  await evaluate("document.getElementById('accountBtn').click()", true);
  const banner = await until("(() => { const b = document.getElementById('pcOffline'); return !b.hidden && b.closest('#bar') && b.children.length === 1 ? b.children[0].textContent : ''; })()");
  const head = "PC " + machineLabel + " (work) offline since ", tail = ". Your answers are kept and will be applied when it is back.";
  const when = typeof banner === "string" && banner.startsWith(head) && banner.endsWith(tail) ? banner.slice(head.length, banner.length - tail.length) : "";
  check(/^[0-9]{1,2} [A-Z][a-z]{2} [0-9]{2}:[0-9]{2}$/.test(when),"past two minutes by the relay's clock, the PC offline banner stands in the bar, by the machine's name, with the time in the phone's own day, and says the answers are kept", banner);
  check(/ - offline since [0-9]{1,2} [A-Z][a-z]{2} [0-9]{2}:[0-9]{2}Remove$/.test(await evaluate("document.querySelector('#machineList li').textContent")), "and the Account screen says so of the machine");
  await cdp("Fetch.disable");
  onPaused = null;
  await evaluate("document.getElementById('accountBtn').click()", true);
  check(!!(await until("document.getElementById('pcOffline').hidden && document.getElementById('pcOffline').children.length === 0")), "and it goes by itself at the next answer that has the machine heard again");
  // THE PRODUCTION PATH: on every other screen the banner comes only from the app's own timed read
  // (app.js, checkPresence) - at start-up, on return to the app, then every 30 s. The page is loaded
  // again with the answer five minutes on, and no Account screen is opened at all.
  let reads = 0;
  onPaused = async (p) => { reads++; await fiveMinutesOn(p); };
  await cdp("Fetch.enable", { patterns: [{ urlPattern: "*/v1/account", requestStage: "Response" }] });
  await cdp("Page.reload");
  const booted = await until("(() => { const b = document.getElementById('pcOffline'); return !b.hidden && b.children.length === 1 && document.getElementById('accountView').hidden && !document.getElementById('emptyView').hidden ? b.children[0].textContent : ''; })()");
  check(typeof booted === "string" && booted.startsWith(head) && booted.endsWith(tail), "at start-up the app reads it by itself, and the banner stands over the app's own screen, not the Account screen", booted);
  await evaluate("document.getElementById('pcOffline').children[0].setAttribute('data-drawn', 'once')");
  const readsBefore = reads;
  await evaluate("document.dispatchEvent(new Event('visibilitychange'))");
  for (let i = 0; i < 100 && reads === readsBefore; i++) await sleep(100);
  await sleep(500);
  check(reads > readsBefore && (await evaluate("(() => { const b = document.getElementById('pcOffline'); return !b.hidden && b.children.length === 1 && b.children[0].getAttribute('data-drawn') === 'once'; })()")), "back to the app it reads again, and the same banner is not drawn again - a screen reader is not told it twice", String(reads - readsBefore));
  onPaused = async (p) => { reads++; await cdp("Fetch.fulfillRequest", { requestId: p.requestId, responseCode: 500, responseHeaders: [{ name: "Content-Type", value: "application/json" }], body: Buffer.from('{"error":"down"}', "utf8").toString("base64") }); };
  await evaluate("document.dispatchEvent(new Event('visibilitychange'))");
  check(!!(await until("document.getElementById('pcOffline').hidden && document.getElementById('pcOffline').children.length === 0")), "and a read that fails takes the banner down: it says nothing about the PC, so nothing is guessed");
  await cdp("Fetch.disable");
  onPaused = null;
  await evaluate("document.getElementById('accountBtn').click()", true);
  await until(shown("accountView") + " && document.querySelectorAll('#machineList li').length === 1");
  const phones = await evaluate("Array.from(document.querySelectorAll('#phoneList li')).map((li) => li.textContent + '|' + li.querySelectorAll('button').length).join(';')");
  const rows = phones.split(";");
  check(rows.filter((r) => /^This phone, signed in [^|]+|0$/.test(r)).length === 1 && rows.every((r) => /^This phone, signed in [^|]+|0$/.test(r) || /^A phone, signed in [^|]+Sign out|1$/.test(r)), "and lists its phones: this one once, with no Sign out of its own (the one below signs it out), each other with one", phones);
  await evaluate("window.confirm = () => true; document.querySelector('#machineList li button').click()", true);
  check(!!(await until("document.querySelectorAll('#machineList li').length === 0 && !document.getElementById('machineEmpty').hidden")), "Remove takes it off the account, and the screen says no machine is left");
  await evaluate("document.getElementById('signOutBtn').click()", true);
  check(!!(await until(shown("signInView"))) && (await sessionCookie()) === null, "Sign out ends the session and returns to the sign-in screen, the cookie gone");

  await evaluate("document.getElementById('signInBtn').click()", true);
  check(!!(await until("location.pathname === '/app/index.html' && !" + shown("signInView") + " && !document.getElementById('accountBtn').hidden")), "signed in again", await evaluate("location.href").catch((e) => e.message));
  await evaluate("document.getElementById('accountBtn').click()", true);
  await until(shown("accountView"));
  await evaluate("window.__asked = []; window.confirm = (q) => { window.__asked.push(q); return window.__asked.length < 2; }; document.getElementById('deleteAccountBtn').click()", true);
  await sleep(500);
  const askedOnce = await evaluate("window.__asked.length");
  check(askedOnce === 2 && (await evaluate(shown("accountView"))) && (await (await fetch(origin + "/auth/session", { headers: { Cookie: "__Host-horde-session=" + (await sessionCookie()).value } })).json()).signedIn === true, "Delete asks twice, and a No to the second deletes nothing", String(askedOnce));
  await evaluate("window.__asked = []; window.confirm = (q) => { window.__asked.push(q); return true; }; document.getElementById('deleteAccountBtn').click()", true);
  check(!!(await until(shown("signInView") + " && document.getElementById('notice').textContent.indexOf('The account is deleted') >= 0")), "Delete, confirmed twice in plain words, deletes the account and returns to the sign-in screen", await evaluate("document.getElementById('notice').textContent"));
  const words = await evaluate("window.__asked.join(' | ')");
  check(words.indexOf("Every mailbox") >= 0 && words.indexOf("cannot be undone") >= 0, "and its questions say what is lost, and that it cannot be undone", words);
  check((await sessionCookie()) === null, "and the session cookie is cleared with it");

  await cdp("Page.navigate", { url: origin + "/app/index.html?limit=1#signin-refused:phones" });
  check(!!(await until(shown("signInView") + " && document.getElementById('notice').textContent.indexOf('most phones signed in') >= 0")), "a sign-in refused by a limit says which, in the app's own words", await evaluate("document.getElementById('notice').textContent").catch((e) => e.message));

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
