// relays/cloudflare/test/budget-watch.mjs - WHAT A PHONE SHOWS WHEN THE RELAY'S DAY IS SPENT, against a
// local dev of the real Worker whose relay-wide day (worker/limits.js, relayRequestsPerDay) is already
// spent for this phone's account, for relays/cloudflare/test/test-cloudflare-limits.ps1 (part 5). A
// browser is never shown the answer to a refused WebSocket upgrade, so the phone's watch is refused as a
// socket with one message (worker/api.js, refuseWatch); then the phone's own relay client and read
// banner (the built app's files, byte for byte what ships) must carry its code word to the screen as the
// page's own plain words for it, not "cannot reach the relay".
//
//   node budget-watch.mjs <site folder> <origin> <session of a phone whose relay-wide day is spent>
//
// Prints one [PASS] or [FAIL] line a check, then [DONE] <failures>.
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [, , siteDir, origin, session] = process.argv;
const R = await import(pathToFileURL(join(siteDir, "app/relay-client.js")).href);
const RB = await import(pathToFileURL(join(siteDir, "app/read-banner.js")).href);
let failures = 0;
function check(ok, name, detail = "") {
  if (!ok) failures++;
  process.stdout.write((ok ? "[PASS] " : "[FAIL] ") + name + (ok || !detail ? "" : " (" + String(detail).replace(/[^\x20-\x7e]/g, "?").slice(0, 300) + ")") + "\n");
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const headers = { Cookie: "__Host-horde-session=" + session, Origin: origin };

// A raw watch, as a browser opens it: its messages and its close code.
const socket = new WebSocket((origin + "/v1/mailboxes/work/phone/watch?since=0&max=10&timeoutMs=20000").replace(/^http/, "ws"), { headers });
const messages = [];
socket.onmessage = (e) => messages.push(String(e.data));
const closed = new Promise((resolve) => { socket.onclose = (e) => resolve(e.code); });
const code = await Promise.race([closed, sleep(10000).then(() => null)]);
let said = null;
try { said = JSON.parse(messages[0]); } catch (e) { said = null; }
check(messages.length === 1 && said && said.code === "relay-daily-limit" && typeof said.error === "string" && said.error.indexOf("midnight UTC") >= 0, "a phone's watch on a spent relay-wide day is told why in the socket's one message: the code and the relay's plain words", JSON.stringify(messages));
check(code === 4003, "and the socket closes with the code LIMITED (4003)", String(code));

const fetchAs = (a, init) => fetch(a, { ...init, headers: { ...(init.headers || {}), ...headers } });
const client = R.createRelayClient(R.httpTransport(origin, fetchAs, class extends WebSocket { constructor(a) { super(a, { headers }); } }));
const w = await client.watch("work/phone", 0, 10, 15000);
check(w.state === "unknown" && R.refusalCodeOf(w.reason) === "relay-daily-limit" && w.reason.indexOf(said.error) >= 0, "the phone's own relay client reads it as a failed watch that keeps the code word (and the relay's words, for the diagnostics)", JSON.stringify(w));
const g = await client.get("work/phone", 0, 10);
check(g.state === "unknown" && g.reason.indexOf(" with 429 [relay-daily-limit]: ") >= 0 && R.refusalCodeOf(g.reason) === "relay-daily-limit", "a plain read is refused the same, 429 with the code", g.reason);

// The bridge says a failed read as "the relay said: <reason>" (phone-core.js, relaySaid).
const signedIn = { state: "known", status: 200, value: { signedIn: true } };
const read = { locked: false, relayDown: true, said: ["the relay said: " + w.reason.slice(0, 200)], lastGoodAt: 0 };
const kind = RB.readFailure(read, signedIn);
const banner = RB.readBanner(kind, 0, null, read);
check(kind === "limited" && banner === "The relay refused the read: " + RB.LIMIT_WORDS["relay-daily-limit"] + "." && banner.indexOf("midnight UTC") >= 0, "the read banner says the relay's day is spent, in the page's own plain words - not 'Cannot reach the relay'", kind + " | " + banner);
const twin = { locked: false, relayDown: true, said: ["the relay said: the relay's watch failed"], lastGoodAt: 0 };
check(RB.readFailure(twin, signedIn) === "unreachable", "CONTROL: a watch that failed with no refusal is still the relay out of reach");

process.stdout.write("[DONE] " + failures + "\n");
process.exit(failures === 0 ? 0 : 1);
