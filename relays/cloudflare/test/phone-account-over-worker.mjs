// relays/cloudflare/test/phone-account-over-worker.mjs - the phone's own account client and relay client
// (the built app's app/account-client.js and app/relay-client.js, byte for byte what ships), SIGNED IN,
// against a local dev of the real Worker: the session cookie the suite's sign-in got, and the page's
// own Origin, which a browser adds to every POST, DELETE and WebSocket and Node's fetch does not - so
// only here are fetch and the socket wrapped to add the two.
//
//   node phone-account-over-worker.mjs <site folder> <origin> <session cookie value>
//
// Prints one [PASS] or [FAIL] line a check, then [DONE] <failures>.
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [, , siteDir, origin, sessionId] = process.argv;
const R = await import(pathToFileURL(join(siteDir, "app/relay-client.js")).href);
const A = await import(pathToFileURL(join(siteDir, "app/account-client.js")).href);
let failures = 0;
function check(ok, name, detail = "") {
  if (!ok) failures++;
  process.stdout.write((ok ? "[PASS] " : "[FAIL] ") + name + (ok || !detail ? "" : " (" + detail + ")") + "\n");
}
const browserHeaders = { Cookie: "__Host-horde-session=" + sessionId, Origin: origin };
const asBrowser = (address, init) => fetch(address, { ...init, headers: { ...(init.headers || {}), ...browserHeaders } });
class BrowserSocket extends WebSocket { constructor(address) { super(address, { headers: browserHeaders }); } }

const account = A.accountClient(asBrowser, origin);
const s = await account.session();
check(s.state === "known" && s.value.signedIn === true && s.value.email === "founder@example.test", "the app sees it is signed in, and as whom", JSON.stringify(s));
const a = await account.account();
check(a.state === "known" && Array.isArray(a.value.machines) && a.value.account.email === "founder@example.test", "the account answers with its machines", JSON.stringify(a));
check(account.signInUrl() === origin + "/auth/google", "sign-in is the relay's own /auth/google");

const c = R.createRelayClient(R.httpTransport(origin, asBrowser, BrowserSocket));
const mb = "work/phone-app";
const p = await c.put(mb, "k-1", "from the phone");
check(p.state === "known" && p.value.seq === 1, "the signed-in phone puts in its account's mailbox", JSON.stringify(p));
const g = await c.get(mb, 0, 10);
check(g.state === "known" && g.value.items.length === 1 && g.value.items[0].text === "from the phone", "and reads it back", JSON.stringify(g));
const later = setTimeout(() => c.put(mb, "k-2", "while watching"), 400);
const w = await c.watch(mb, 1, 10, 5000);
clearTimeout(later);
check(w.state === "known" && w.value.items.length === 1 && w.value.items[0].text === "while watching", "a watch over its socket, with the cookie and the Origin, wakes on a put", JSON.stringify(w));
const k = await c.ack(mb, 2);
check(k.state === "known", "and acks", JSON.stringify(k));

const noOrigin = R.createRelayClient(R.httpTransport(origin, (address, init) => fetch(address, { ...init, headers: { ...(init.headers || {}), Cookie: browserHeaders.Cookie } }), BrowserSocket));
const forged = await noOrigin.put(mb, "k-3", "from another page");
check(forged.state === "unknown" && forged.reason.indexOf("401") >= 0, "a put carrying the cookie but not the page's Origin is refused", JSON.stringify(forged));
const bad = await account.registerMachine({ horde: "work", offer: "0".repeat(32), machine: "0".repeat(32), signPublic: "AA", expiresAt: Date.now() + 60000, grant: "A".repeat(86) });
check(bad.state === "unknown" && bad.status === 400, "a registration that names no real machine key is refused", JSON.stringify(bad));
check((await account.removeMachine("not-a-key")).state === "unknown", "and the client never sends a removal of something that is not a key id");

process.stdout.write("[DONE] " + failures + "\n");
process.exit(failures === 0 ? 0 : 1);
