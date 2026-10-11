// relays/cloudflare/test/phone-over-worker.mjs - the phone's own relay client and http transport (the
// built app's app/relay-client.js, byte for byte what ships) against a local dev of the real Worker:
// the two sides of the mailbox API checked against each other, not each against a fake.
//
//   node phone-over-worker.mjs <site folder> <origin> <test token>
//
// The test authenticator wants an Authorization header (worker/auth.js); a browser sends none, and
// sign-in (8b) will use the page's cookie instead, so only here are fetch and the socket wrapped to add
// it. Prints one [PASS] or [FAIL] line a check, then [DONE] <failures>.
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [, , siteDir, origin, token] = process.argv;
const R = await import(pathToFileURL(join(siteDir, "app/relay-client.js")).href);
let failures = 0;
function check(ok, name, detail = "") {
  if (!ok) failures++;
  process.stdout.write((ok ? "[PASS] " : "[FAIL] ") + name + (ok || !detail ? "" : " (" + detail + ")") + "\n");
}
const auth = "Bearer " + token;
const fetchWithAuth = (address, init) => fetch(address, { ...init, headers: { ...(init.headers || {}), Authorization: auth } });
class SocketWithAuth extends WebSocket { constructor(address) { super(address, { headers: { Authorization: auth } }); } }

const c = R.createRelayClient(R.httpTransport(origin, fetchWithAuth, SocketWithAuth));
const mb = "phone-test/phone";
const p1 = await c.put(mb, "key-1", "first");
const p2 = await c.put(mb, "key-1", "first again");
check(p1.state === "known" && p1.value.seq === 1 && !p1.value.duplicate && p2.value.duplicate && p2.value.seq === 1, "the phone puts through the Worker, idempotent by key", JSON.stringify([p1, p2]));
const g = await c.get(mb, 0, 10);
check(g.state === "known" && g.value.items.length === 1 && g.value.items[0].text === "first" && g.value.anomalies.length === 0, "and reads back what it put, the first text standing", JSON.stringify(g));
const started = Date.now();
const waiting = c.watch(mb, 1, 10, 15000);
setTimeout(() => { c.put(mb, "key-2", "second"); }, 400);
const w = await waiting;
const took = Date.now() - started;
check(w.state === "known" && w.value.items.length === 1 && w.value.items[0].seq === 2 && took < 1400, "a watch over the Worker's WebSocket returns as the put lands (" + took + " ms)", JSON.stringify(w));
const quietStart = Date.now();
const quiet = await c.watch(mb, 2, 10, 500);
const quietTook = Date.now() - quietStart;
check(quiet.state === "known" && quiet.value.items.length === 0 && quietTook >= 450 && quietTook < 3000, "a watch with nothing to see waits out its time and answers no items (" + quietTook + " ms)", JSON.stringify(quiet));
const k = await c.ack(mb, 1);
const after = await c.get(mb, 0, 10);
check(k.state === "known" && after.value.items.map((i) => i.seq).join(",") === "2", "an ack trims what it covers, read from the phone", JSON.stringify(after));
const past = await c.ack(mb, 9);
check(past.state === "unknown" && past.reason.indexOf("409") >= 0, "an ack past the head is refused, and the phone says why", past.reason);
const nobody = R.createRelayClient(R.httpTransport(origin, fetch, WebSocket));
const refused = await nobody.get(mb, 0, 1);
check(refused.state === "unknown" && refused.reason.indexOf("401") >= 0, "a phone nobody vouched for is refused (401), and reads nothing", refused.reason);
process.stdout.write("[DONE] " + failures + "\n");
process.exit(0);
