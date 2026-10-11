// relays/cloudflare/test/watch-limits.mjs - ONE LIVE WATCH PER DEVICE IN A MAILBOX, against a local dev of
// the real Worker, for relays/cloudflare/test/test-cloudflare-limits.ps1: two signed-in phones of one
// account (two sessions, so two devices) open watches as a browser would - the cookie and the page's
// Origin, which Node's WebSocket is handed here - and the phone's own relay client (the built app's
// app/relay-client.js, byte for byte what ships) is watched being replaced.
//
//   node watch-limits.mjs <site folder> <origin> <session of phone A> <session of phone B>
//
// Prints one [PASS] or [FAIL] line a check, then [DONE] <failures>.
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [, , siteDir, origin, sessionA, sessionB] = process.argv;
const R = await import(pathToFileURL(join(siteDir, "app/relay-client.js")).href);
let failures = 0;
function check(ok, name, detail = "") {
  if (!ok) failures++;
  process.stdout.write((ok ? "[PASS] " : "[FAIL] ") + name + (ok || !detail ? "" : " (" + String(detail).slice(0, 300) + ")") + "\n");
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const headersOf = (session) => ({ Cookie: "__Host-horde-session=" + session, Origin: origin });
const ws = (origin + "/v1/mailboxes/").replace(/^http/, "ws");

// A raw watch: { socket, closed (a promise of the close code), messages }.
function watch(session, mailbox, since = 0) {
  const socket = new WebSocket(ws + mailbox + "/watch?since=" + since + "&max=10&timeoutMs=20000", { headers: headersOf(session) });
  const messages = [];
  const state = { code: null };
  const closed = new Promise((resolve) => { socket.onclose = (e) => { state.code = e.code; resolve(e.code); }; });
  socket.onmessage = (e) => messages.push(String(e.data));
  const opened = new Promise((resolve) => { socket.onopen = () => resolve(true); socket.onerror = () => resolve(false); });
  return { socket, closed, messages, state, opened };
}
const put = (session, mailbox, key, text) => fetch(origin + "/v1/mailboxes/" + mailbox + "/items", { method: "POST", headers: { ...headersOf(session), "Content-Type": "application/json" }, body: JSON.stringify({ key, text }) });

const w1 = watch(sessionA, "work/watched");
const other = watch(sessionB, "work/watched");
const elsewhere = watch(sessionA, "work/elsewhere");
check(await w1.opened && await other.opened && await elsewhere.opened, "phone A watches a mailbox and another, and phone B the first");
await sleep(300);
const w2 = watch(sessionA, "work/watched");
check(await w2.opened, "phone A opens a second watch of the same mailbox");
for (let i = 0; i < 50 && w1.messages.length === 0; i++) await sleep(100);
let said = null;
try { said = JSON.parse(w1.messages[0]); } catch (e) { said = null; }
check(w1.messages.length === 1 && said && said.code === "watch-replaced" && typeof said.error === "string", "its first watch there is ended at once, its one message saying it was replaced: one live watch per device in a mailbox", JSON.stringify(w1.messages));
await sleep(300);
check(w2.state.code === null && other.state.code === null && elsewhere.state.code === null, "the new watch stays, phone B's watch of that mailbox stays, and phone A's watch of another mailbox stays", JSON.stringify([w2.state.code, other.state.code, elsewhere.state.code]));
const p = await put(sessionA, "work/watched", "w-1", "for the watchers");
await Promise.race([Promise.all([w2.closed, other.closed]), sleep(5000)]);
check(p.status === 200 && w2.messages.length === 1 && other.messages.length === 1 && w2.messages[0].indexOf("for the watchers") >= 0, "a put wakes both live watches, each with the item", JSON.stringify({ status: p.status, w2: w2.messages, other: other.messages }));
elsewhere.socket.close();
const code = await Promise.race([w1.closed, sleep(15000).then(() => null)]);
check(code === 4001, "and its close says it again, with the code REPLACED (4001)", String(code));

const client = R.createRelayClient(R.httpTransport(origin, (a, init) => fetch(a, { ...init, headers: { ...(init.headers || {}), ...headersOf(sessionA) } }), class extends WebSocket { constructor(a) { super(a, { headers: headersOf(sessionA) }); } }));
const pending = client.watch("work/client", 0, 10, 15000);
await sleep(800);
const newer = watch(sessionA, "work/client");
await newer.opened;
const t0 = Date.now();
const r = await pending;
check(r.state === "unknown" && r.reason.indexOf("replaced") >= 0 && Date.now() - t0 < 3000, "the phone's own client reads a replaced watch as a failed one at once, not as nothing come - so the app pauses before it watches again", JSON.stringify(r) + " after " + (Date.now() - t0) + " ms");
newer.socket.close();

process.stdout.write("[DONE] " + failures + "\n");
process.exit(failures === 0 ? 0 : 1);
