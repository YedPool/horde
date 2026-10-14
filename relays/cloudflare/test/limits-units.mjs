// The hosted relay's limits, the pure parts, one behaviour at a time, under Node, for
// relays/cloudflare/test/test-cloudflare-limits.ps1 (part 1): the approved numbers as the one source
// holds them, the test override and where it is honoured, a bucket and a day count at their edges, the
// client address, a limit's refusal, and the retirement record a rotation carries - with keys made here,
// and no network.
//
//   node limits-units.mjs <repository root>
//
// Prints one line per check, "[PASS] name" or "[FAIL] name: detail", then "[DONE] <failures>".
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { readFileSync } from "node:fs";

const [, , repoRoot] = process.argv;
const load = (p) => import(pathToFileURL(join(repoRoot, p)).href);
const P = await load("relay/js/protocol.js");
const L = await load("relays/cloudflare/worker/limits.js");
const T = await load("relays/cloudflare/worker/throttle.js");
const N = await load("relays/cloudflare/worker/answers.js");
const A = await load("relays/cloudflare/worker/client-address.js");
const B = await load("relays/cloudflare/worker/budget.js");
const subtle = globalThis.crypto.subtle;

let failures = 0;
function check(ok, name, detail = "") {
  if (ok) process.stdout.write("[PASS] " + name + "\n");
  else { failures++; process.stdout.write("[FAIL] " + name + (detail ? ": " + String(detail).replace(/[^\x20-\x7e]/g, "?").slice(0, 300) : "") + "\n"); }
}
const throws = (f) => { try { f(); return false; } catch (e) { return true; } };

// --- 1. the approved numbers (the founder, 2026-10-11), in their one place ---
{
  const approved = {
    machinesPerAccount: 10, phonesPerAccount: 5, pairingsPerHour: 10, requestsPerDay: 20000,
    accountMaxMailboxes: 50, accountMaxChars: 100 * 1024 * 1024,
    mailboxMaxItems: 2000, mailboxMaxChars: 20 * 1024 * 1024,
    putsPerMinute: 60, putBurst: 20, readsPerMinute: 120, readBurst: 40,
    signInStartsPerMinute: 10, newAccountsPerDay: 5,
    refusedSignaturesPerMinutePerAddress: 30, refusedSignaturesPerMinutePerKey: 10, noncesPerKey: 1000,
    // The relay-wide numbers (proposed 2026-10-14, the PR that adds them; merged only on the founder's yes).
    relayRequestsPerDay: 80000, relayOwnerReserve: 15000, relayRequestLease: 50,
    relayMaxChars: 2 * 1024 * 1024 * 1024, relayCharsLease: 256 * 1024,
    retentionMs: 30 * 24 * 3600 * 1000
  };
  const d = L.DEFAULTS;
  const names = Object.keys(approved);
  check(Object.keys(d).sort().join(",") === names.slice().sort().join(","), "the limits are exactly the named settings approved, no more and no fewer", Object.keys(d).join(","));
  for (const n of names) check(d[n] === approved[n], "the default of " + n + " is " + approved[n], String(d[n]));
  check(Object.isFrozen(d), "and nothing at run time can change them");
  const caps = JSON.parse(readFileSync(join(repoRoot, "relays/cloudflare/capabilities.json"), "utf8"));
  check(caps.limits.retentionSeconds * 1000 === d.retentionMs, "retention is the relay's declared retentionSeconds (capabilities.json, which the port reads), not a second number", String(caps.limits.retentionSeconds));
  check(caps.limits.maxTextChars === 65536, "and the envelope's 64 KiB cap stays capabilities.json's own (reused, not repeated here)");
}

// --- 2. the test override, and where it is honoured ---
{
  const local = new URL("http://127.0.0.1:8787/v1/x");
  const deployed = new URL("https://relay.example.test/v1/x");
  check(L.limitsOf({}, local) === L.DEFAULTS, "with no test binding, a request is held to the defaults");
  const env = { HORDE_RELAY_TEST_LIMITS: '{"putBurst":3,"retentionMs":2500}' };
  const o = L.limitsOf(env, local);
  check(o.putBurst === 3 && o.retentionMs === 2500 && o.readBurst === L.DEFAULTS.readBurst, "with it, a request to this machine itself is held to its values over the defaults");
  check(L.limitsOf(env, deployed) === L.DEFAULTS, "but a request to any other name is held to the defaults: a deployed Worker never honours it");
  check(L.limitsOf({ HORDE_RELAY_TEST_LIMITS: "{}" }, local).putBurst === L.DEFAULTS.putBurst, "the committed placeholder, {}, changes nothing");
  check(throws(() => L.limitsOf({ HORDE_RELAY_TEST_LIMITS: '{"putBurts":3}' }, local)), "a binding that names no setting fails the request rather than prove nothing");
  check(throws(() => L.limitsOf({ HORDE_RELAY_TEST_LIMITS: '{"putBurst":0}' }, local)) && throws(() => L.limitsOf({ HORDE_RELAY_TEST_LIMITS: '{"putBurst":1.5}' }, local)) && throws(() => L.limitsOf({ HORDE_RELAY_TEST_LIMITS: '{"putBurst":"3"}' }, local)), "and so does a value that is not a whole number from 1");
  check(throws(() => L.limitsOf({ HORDE_RELAY_TEST_LIMITS: "not json" }, local)) && throws(() => L.limitsOf({ HORDE_RELAY_TEST_LIMITS: "[1]" }, local)), "and a binding that is not a JSON object");
  check(throws(() => L.limitsOf({ HORDE_RELAY_TEST_LIMITS: '{"relayRequestsPerDay":6,"relayOwnerReserve":6}' }, local)) && !throws(() => L.limitsOf({ HORDE_RELAY_TEST_LIMITS: '{"relayRequestsPerDay":6,"relayOwnerReserve":5}' }, local)), "a reserve that is not below the relay's day fails the request; one a step below it is taken");
}

// --- 2b. the relay-wide limits, pure (budget.js) ---
{
  const d = L.DEFAULTS;
  check(d.relayRequestsPerDay < 100000 && d.relayRequestsPerDay - d.relayOwnerReserve > 0, "the relay's day is below the free plan's 100,000 Worker requests, and leaves a shared part above the reserve");
  check(d.relayRequestsPerDay >= 4 * d.requestsPerDay, "and holds four accounts at their own whole day");
  check(d.relayRequestLease < d.requestsPerDay && d.relayCharsLease <= d.accountMaxChars, "a lease is smaller than what one account may use");
  const day = 20000;
  const t = day * T.DAY_MS + 3600000;
  const lim = { relayRequestsPerDay: 6, relayOwnerReserve: 3 };
  check(B.requestCapOf(lim, "public") === 3 && B.requestCapOf(lim, "owner") === 6 && B.requestCapOf(lim, "everyone") === 6, "a public account draws on the day less the reserve; an owner, and everyone when no owner is named, on the whole day");
  check(B.requestCapOf(lim, undefined) === 3 && B.requestCapOf(lim, "Owner") === 3, "a tier that is missing or misspelled gets the smaller part");
  let s = B.grantRequests(undefined, t, 2, 3);
  check(s.granted === 2 && s.state.used === 2 && s.state.day === day, "a lease of two is granted from a fresh day");
  const twin = B.grantRequests(s.state, t, 1, 3);
  check(twin.granted === 1 && twin.state.used === 3, "CONTROL: one step below the line, the last of the shared part is granted");
  const over = B.grantRequests(twin.state, t, 1, 3);
  check(over.granted === 0 && over.state.used === 3 && over.retryAfterMs === T.DAY_MS - 3600000, "past it a public account is granted nothing, told the time to midnight UTC", String(over.retryAfterMs));
  const part = B.grantRequests(s.state, t, 50, 3);
  check(part.granted === 1 && part.state.used === 3, "a lease near the line is granted in part: never past the line, never a request more");
  check(B.grantRequests(twin.state, t, 2, 6).granted === 2 && B.grantRequests({ day, used: 6 }, t, 1, 6).granted === 0, "an owner goes on into the reserve, and is refused at the end of it too");
  check(B.grantRequests({ day, used: 6 }, (day + 1) * T.DAY_MS, 1, 3).granted === 1, "at UTC midnight the relay's day starts again");
  check(B.grantRequests({ day, used: "6" }, t, 1, 3).granted === 1 && B.grantRequests({ day, used: 2 }, t, 0, 3).granted === 0, "a stored count that is not a number counts from 0; a lease of nothing grants nothing");
  check(B.grantChars(0, 10, 5, 100).ok && B.grantChars(0, 10, 5, 100).granted === 15 && B.grantChars(90, 10, 5, 100).granted === 10 && B.grantChars(90, 10, 5, 100).total === 100, "characters are granted with up to a lease of room, and only the room there is");
  check(!B.grantChars(91, 10, 5, 100).ok && B.grantChars(91, 10, 5, 100).total === 91, "a put that does not fit under the relay's cap is refused, and nothing is taken");
  check(B.charsToRelease(100, 20, 30) === 50 && B.charsToRelease(40, 20, 30) === 0 && B.charsToRelease(10, 20, 30) === 0, "an account gives back all it holds past one lease of room, and never more than it holds");
  check(B.RELAY_DAY_WORDS.length < 140 && B.RELAY_FULL_WORDS.length < 140 && /^[\x20-\x7e]+$/.test(B.RELAY_DAY_WORDS + B.RELAY_FULL_WORDS), "the relay-wide refusals' words are plain ASCII, short enough for the phone to show whole");
}

// --- 2c. the owners (budget.js, and Owners.ps1 its twin) ---
{
  const bind = (emails, subs) => ({ HORDE_RELAY_OWNER_ACCOUNTS: JSON.stringify({ emails, subs }) });
  check(B.ownersOf({}).state === "none" && B.ownersOf({ HORDE_RELAY_OWNER_ACCOUNTS: "" }).state === "none" && B.ownersOf(bind([], [])).state === "none", "no binding, an empty one, or one naming nobody is no owner");
  const o = B.ownersOf(bind(["founder@example.com"], ["112233", "445566"]));
  check(o.state === "set" && o.subs.join(",") === "112233,445566" && o.emails.join(",") === "founder@example.com", "the binding's emails and Google account ids are the owners");
  check(JSON.stringify(B.ownersOf(bind(["a@example.com"], ["1"]))) === JSON.stringify({ state: "set", emails: ["a@example.com"], subs: ["1"] }), "they are plain arrays, so the value crosses to the account's object as it is");
  check(B.ownersOf({ HORDE_RELAY_OWNER_ACCOUNTS: "112233,445566" }).state === "broken" && B.ownersOf(bind(["Founder@Example.com"], [])).state === "broken" && B.ownersOf(bind([], ["not-a-sub"])).state === "broken" && B.ownersOf({ HORDE_RELAY_OWNER_ACCOUNTS: '{"emails":[],"subs":[],"on":true}' }).state === "broken", "a binding not exactly the allowlist's shape - lower-case emails, digit ids, those two lists - is broken");
  check(B.ownersOf(bind(["a@example.com"], Array(16).fill(0).map((x, i) => String(i)))).state === "broken" && B.ownersOf(bind([], Array(16).fill(0).map((x, i) => String(i)))).state === "set", "seventeen owners are broken; CONTROL: sixteen, the most, are taken");
  check(B.tierOf(o, "google:112233", "") === "owner" && B.tierOf(o, "google:999", "") === "public", "an owner's account id is an owner's tier; another is public");
  check(B.tierOf(o, "112233") === "public" && B.tierOf(o, "test") === "public" && B.tierOf(o, "google:1122334") === "public", "only the whole id behind google: makes an owner");
  check(B.tierOf(o, "google:999", "founder@example.com") === "owner" && B.tierOf(o, "google:999", "Founder@Example.COM") === "owner", "an account whose verified email is an owner's is an owner, in any case of letters");
  check(B.tierOf(o, "google:999", "other@example.com") === "public" && B.tierOf(o, "google:999", "") === "public" && B.tierOf(o, "google:999", undefined) === "public" && B.tierOf(o, "google:999", null) === "public", "another email is public, and no email at all never matches");
  check(B.tierOf({ state: "none" }, "google:999") === "everyone", "with no owner named, every account draws on the whole day");
  check(B.tierOf({ state: "broken" }, "google:112233", "founder@example.com") === "public" && B.tierOf(undefined, "google:112233") === "public", "a broken binding fails closed, and so does none given at all: nobody is an owner, and the reserve is still held back");
  check(JSON.stringify(B.ownersSummary(o)) === '{"owners":3,"reserve":true}' && JSON.stringify(B.ownersSummary({ state: "none" })) === '{"owners":0,"reserve":false}' && JSON.stringify(B.ownersSummary({ state: "broken" })) === '{"owners":0,"reserve":true}', "what anyone may know is how many owners and whether a reserve is held back - never who");
}

// --- 3. a bucket at its edges ---
{
  const t0 = 1760000000000;
  let s;
  let taken = 0;
  for (let i = 0; i < 20; i++) { const r = T.takeToken(s, t0, 60, 60000, 20); s = r.state; if (r.ok) taken++; }
  check(taken === 20, "a fresh bucket of 20 takes exactly 20 at once", String(taken));
  const over = T.takeToken(s, t0, 60, 60000, 20);
  check(!over.ok && over.retryAfterMs === 1000, "the 21st is refused, told to come back in the second its next token takes", String(over.retryAfterMs));
  check(!T.takeToken(over.state, t0 + 999, 60, 60000, 20).ok, "a moment before that second it is still refused");
  check(T.takeToken(over.state, t0 + 1000, 60, 60000, 20).ok, "at that second one more is taken: 60 a minute is one a second");
  const idle = T.takeToken(over.state, t0 + 3600000, 60, 60000, 20);
  check(idle.ok && idle.state.tokens === 19, "an hour idle refills the bucket to its burst, never past it", String(idle.state.tokens));
  const back = T.takeToken({ tokens: 0, at: t0 }, t0 - 5000, 60, 60000, 20);
  check(!back.ok, "a clock that went back refills nothing");
  const hour = T.takeToken({ tokens: 0, at: t0 }, t0 + 359999, 10, 3600000, 10);
  check(!hour.ok && T.takeToken({ tokens: 0, at: t0 }, t0 + 360000, 10, 3600000, 10).ok, "10 an hour gives one back every six minutes, not before");
}

// --- 4. a day count at its edges ---
{
  const day = 20371;
  const t = day * T.DAY_MS + 3600000;
  let s;
  for (let i = 0; i < 3; i++) s = T.countInDay(s, t, 3).state;
  check(s.n === 3 && s.day === day, "three counted in a day of three");
  const over = T.countInDay(s, t, 3);
  check(!over.ok && over.state.n === 3 && over.retryAfterMs === T.DAY_MS - 3600000, "the fourth is refused, not counted, and told the time to the next UTC midnight", String(over.retryAfterMs));
  check(T.countInDay(s, (day + 1) * T.DAY_MS, 3).ok && T.countInDay(s, (day + 1) * T.DAY_MS, 3).state.n === 1, "at UTC midnight the count starts again");
  check(!T.countInDay(s, (day + 1) * T.DAY_MS - 1, 3).ok, "and a millisecond before, it has not");
}

// --- 5. a limit's refusal ---
{
  const r = N.refuseWith(429, N.CODES.rate, "wait", 1200);
  const body = await r.json();
  check(r.status === 429 && body.code === "rate-limited" && body.error === "wait" && Object.keys(body).join(",") === "error,code", "a refusal by a limit is its status, its words and its code word");
  check(r.headers.get("Retry-After") === "2", "and Retry-After in whole seconds, rounded up: never sooner than the limit allows", r.headers.get("Retry-After"));
  check(N.refuseWith(507, N.CODES.mailboxFull, "full").headers.get("Retry-After") === null, "a cap that no wait lifts says no Retry-After");
  check(new Set(Object.values(N.CODES)).size === Object.keys(N.CODES).length, "every code word is its own");
}

// --- 6. the rotation's record, as the relay reads it (relay/Identity.ps1's twin) ---
{
  const N_ORDER = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551n;
  const lowS = (sig) => {
    const s = BigInt("0x" + P.hex(sig.slice(32)));
    if (s <= N_ORDER / 2n) return sig;
    const t = (N_ORDER - s).toString(16).padStart(64, "0");
    return P.cat(sig.slice(0, 32), P.unhex(t));
  };
  const keys = async () => {
    const k = await subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
    const point = new Uint8Array(await subtle.exportKey("raw", k.publicKey));
    return { k, point, id: await P.keyId(point) };
  };
  const sign = async (k, bytes) => lowS(new Uint8Array(await subtle.sign({ name: "ECDSA", hash: "SHA-256" }, k.privateKey, bytes)));
  const oldKey = await keys();
  const newSign = await keys();
  const newAgree = await keys();
  const record = (vouch, over = {}) => {
    const v = { generation: 1, successor: 2, reason: "scheduled", horde: "work", ...over };
    return '{"v":1,"kind":"horde-relay-machine-retired","horde":"' + v.horde + '","generation":' + v.generation + ',"signKeyId":"' + oldKey.id + '","agreeKeyId":"' + "a".repeat(32) +
      '","successor":' + v.successor + ',"successorSignKeyId":"' + newSign.id + '","successorSignPublic":"' + P.b64u(newSign.point) + '","successorAgreeKeyId":"' + newAgree.id +
      '","successorAgreePublic":"' + P.b64u(newAgree.point) + '","reason":"' + v.reason + '","retiredAt":1760000000000,"agreeKeptUntil":1760604800000,"vouch":"' + vouch + '"}';
  };
  const vouchFor = async (over = {}) => P.b64u(await sign(oldKey.k, P.utf8(P.ROTATION_VOUCH_DOMAIN + record("", over))));
  const text = record(await vouchFor());
  const r = P.readRetirement(text);
  check(r.ok && r.value.signKeyId === oldKey.id && r.value.successorSignKeyId === newSign.id && r.value.successorSignPublic === P.b64u(newSign.point) && r.value.horde === "work", "a retirement record is read: the old key, its successor and the horde", r.reason);
  check(r.ok && await P.verifyMachineSignature(oldKey.point, r.value.signed, P.unb64u(r.value.vouch)), "its vouch verifies under the old key over the domain and the record with an empty vouch, as relay/Identity.ps1 signs it");
  check(P.fromUtf8(r.value.signed) === P.ROTATION_VOUCH_DOMAIN + record(""), "those are exactly the bytes signed");
  const forged = P.readRetirement(record(P.b64u(await sign(newSign.k, P.utf8(P.ROTATION_VOUCH_DOMAIN + record(""))))));
  check(forged.ok && !(await P.verifyMachineSignature(oldKey.point, forged.value.signed, P.unb64u(forged.value.vouch))), "a vouch the new key made itself does not verify under the old");
  const swapped = P.readRetirement(record(r.value.vouch, { reason: "scheduledX" }));
  check(swapped.ok && !(await P.verifyMachineSignature(oldKey.point, swapped.value.signed, P.unb64u(swapped.value.vouch))), "a record changed after it was vouched for does not verify");
  check(!P.readRetirement(record("")).ok && P.readRetirement(record("")).reason.indexOf("no vouch") >= 0, "a record with no vouch (a lost key's rotation) is refused: that machine pairs again");
  check(!P.readRetirement(text.replace('"generation":1,', '"generation": 1,')).ok && !P.readRetirement(text.replace('{"v":1,', '{"v":1,"x":0,')).ok && !P.readRetirement(" " + text).ok, "a record not in its one canonical form is refused");
  check(!P.readRetirement(record(r.value.vouch, { generation: 2, successor: 2 })).ok, "and one whose successor does not come after it");
  check(!P.readRetirement(null).ok && !P.readRetirement(text + "x".repeat(16384)).ok, "and anything that is not a short text");
}

// --- 7. the client address ---
{
  const local = new URL("http://127.0.0.1:8787/v1/x");
  const deployed = new URL("https://relay.example.test/v1/x");
  const req = (h) => new Request(local.href, { headers: h });
  const test = { HORDE_RELAY_TEST_LIMITS: "{}" };
  check(A.clientAddressOf(req({ "CF-Connecting-IP": "203.0.113.7" }), {}, deployed) === "203.0.113.7" && A.clientAddressOf(req({ "CF-Connecting-IP": "2001:db8::1" }), {}, deployed) === "2001:db8::1", "the address is the IP Cloudflare reports, v4 or v6");
  check(A.clientAddressOf(req({}), {}, deployed) === "local" && A.clientAddressOf(req({ "CF-Connecting-IP": "not an ip" }), {}, deployed) === "local", "with none, or one that is not an IP, it is local");
  check(A.clientAddressOf(req({ "Horde-Test-Client-Address": "10.0.0.1", "CF-Connecting-IP": "203.0.113.7" }), test, local) === "10.0.0.1", "with the test limits binding, a request to this machine itself may name its address");
  check(A.clientAddressOf(req({ "Horde-Test-Client-Address": "10.0.0.1", "CF-Connecting-IP": "203.0.113.7" }), {}, local) === "203.0.113.7", "but not without the binding");
  check(A.clientAddressOf(req({ "Horde-Test-Client-Address": "10.0.0.1", "CF-Connecting-IP": "203.0.113.7" }), test, deployed) === "203.0.113.7", "nor to any other name: a deployed Worker never takes it");
  check(A.clientAddressOf(req({ "Horde-Test-Client-Address": "10.0.0.1/../x" }), test, local) === "local", "and a named address that is not an IP is not taken");
}

// --- 8. the account grant signs the machine's label ---
{
  const g = { horde: "work", offer: "0123456789abcdef0123456789abcdef", machine: "a".repeat(32), expiresAt: 1760000000000, label: "build-box" };
  check(P.fromUtf8(P.accountGrantBytes(g)) === "horde-relay/pairing/v1 account-grant\nwork\n0123456789abcdef0123456789abcdef\n" + "a".repeat(32) + "\n1760000000000\nbuild-box", "the grant signs the domain, the horde, the offer, the machine, the expiry and the label, one to a line (relay/Pairing.ps1's twin)");
}

process.stdout.write("[DONE] " + failures + "\n");
process.exit(failures === 0 ? 0 : 1);
