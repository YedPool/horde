// The phone app's modules, one behaviour at a time, under Node, for surfaces/pwa/test/test-pwa-site.ps1:
// the modules of a BUILT site (imported from the folder New-HordePwaSite wrote, so what is checked is
// what ships), against machines made here in JavaScript - each a signing key and an agreement key, the
// envelopes they send written from relay/Envelope.ps1's strings - so each refusal can be provoked on
// purpose. The real machine is test-pwa-phone-e2e.ps1's.
//
//   node units.mjs <site folder> <repository root>
//
// Prints one line per check, "[PASS] name" or "[FAIL] name: detail", and nothing else; the suite turns
// each into a check of its own.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [, , siteDir, repoRoot] = process.argv;
const load = (p) => import(pathToFileURL(join(siteDir, p)).href);
const P = await load("relay/protocol.js");
const K = await load("app/keywrap.js");
const R = await load("app/relay-client.js");
const { createPhone } = await load("app/phone-core.js");
const AC = await load("app/account-client.js");
const { memoryStore } = await load("app/store.js");
const { createBridge } = await load("surface/bridge.js");
const LC = await load("app/lane-card.js");
const DC = await load("app/decision-cards.js");
const NV = await load("app/notices-view.js");
const CW = await load("app/cards-why.js");
const AU = await load("app/app-update.js");
const RB = await load("app/read-banner.js");
const CS = await load("app/chat-scroll.js");
const { softAuthenticator } = await import(pathToFileURL(join(repoRoot, "test/fixtures/relay/phone/soft-passkey.mjs")).href);
const subtle = globalThis.crypto.subtle;

let failures = 0;
function check(ok, name, detail = "") {
  if (ok) process.stdout.write("[PASS] " + name + "\n");
  else { failures++; process.stdout.write("[FAIL] " + name + (detail ? ": " + detail : "") + "\n"); }
}
async function throwsAsync(fn) { try { await fn(); return ""; } catch (e) { return e && e.message ? e.message : String(e); } }

// --- a machine, in JavaScript ---

async function newMachine(horde) {
  const sign = await subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, false, ["sign", "verify"]);
  const agree = await subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]);
  const signPublic = new Uint8Array(await subtle.exportKey("raw", sign.publicKey));
  const agreePublic = new Uint8Array(await subtle.exportKey("raw", agree.publicKey));
  const m = { horde, sign, agree, signPublic, agreePublic, keyId: await P.keyId(signPublic), agreeKeyId: await P.keyId(agreePublic), seq: 0 };
  m.mailbox = horde + "/" + m.keyId;
  return m;
}
// relay/Pairing.ps1's offer, its members in their order.
// Its account grant is signed by the machine's own key, low-S, as relay/Pairing.ps1 signs it: the phone
// verifies it (relay/js/protocol.js, readOffer). grant, when given, stands in for it.
const P256_N = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551n;
async function machineSign(m, bytes) {
  const sig = new Uint8Array(await subtle.sign({ name: "ECDSA", hash: "SHA-256" }, m.sign.privateKey, bytes));
  const s = BigInt("0x" + P.hex(sig.slice(32)));
  if (s > P256_N / 2n) sig.set(P.unhex((P256_N - s).toString(16).padStart(64, "0")), 32);
  return sig;
}
async function offerText(m, { rpId = "relay.example.test", origins = ["https://relay.example.test"], expiresAt = Date.now() + 300000, mailbox = m.mailbox, agreeKeyId = m.agreeKeyId, id = P.hex(P.randomBytes(16)), pairMailbox = null, grant = null, label = "build-box" } = {}) {
  if (grant === null) grant = P.b64u(await machineSign(m, P.accountGrantBytes({ horde: m.horde, offer: id, machine: m.keyId, expiresAt, label })));
  return '{"v":1,"kind":"horde-relay-pairing-offer","horde":"' + m.horde + '","offer":"' + id + '","code":"' + P.b64u(P.randomBytes(16)) + '","machine":"' + m.keyId +
    '","label":"' + label + '","signPublic":"' + P.b64u(m.signPublic) + '","agreeKeyId":"' + agreeKeyId + '","agreePublic":"' + P.b64u(m.agreePublic) + '","mailbox":"' + mailbox +
    '","pairMailbox":"' + (pairMailbox === null ? m.horde + "/pair-" + id : pairMailbox) + '","rpId":"' + rpId +
    '","origins":[' + origins.map((o) => '"' + o + '"').join(",") + '],"issuedAt":' + (expiresAt - 300000) + ',"expiresAt":' + expiresAt + ',"grant":"' + grant + '"}';
}
// A machine's envelope: sealed to each phone key, signed ES256 (P1363), relay/Envelope.ps1's canonical text.
async function machineEnvelope(m, { kind, channel, body, phones, seq = ++m.seq }) {
  const h = { kind, channel, from: m.keyId, to: [], seq, nonce: P.hex(P.randomBytes(12)), ts: Date.now() };
  for (const p of phones) h.to.push(await P.keyId(p));
  const ht = P.headerText(h);
  const aad = P.utf8("horde-relay/envelope/v1 aad\n" + ht);
  const cek = P.randomBytes(32);
  const ct = await P.gcmSeal(cek, P.unhex(h.nonce), aad, body);
  const recips = [];
  for (let i = 0; i < phones.length; i++) { const box = await P.hpkeSeal(phones[i], P.utf8("horde-relay/envelope/v1 content-key"), aad, cek); recips.push({ kid: h.to[i], enc: P.b64u(box.enc), key: P.b64u(box.sealed) }); }
  const rt = P.recipientsText(recips);
  const ctText = P.b64u(ct);
  const sig = new Uint8Array(await subtle.sign({ name: "ECDSA", hash: "SHA-256" }, m.sign.privateKey, P.signedBytes(ht, rt, ctText)));
  return { text: '{"header":' + ht + ',"recipients":' + rt + ',"ct":"' + ctText + '","sig":{"alg":"ES256","value":"' + P.b64u(sig) + '"}}', key: P.replayKey(h), header: h };
}
// answers: what the machine says of the answers it reads ("answers" in the page); left out, the page
// says nothing of them, as every machine's did before a part could be answered by itself.
function snapshotPages(m, questions, { pages = 1, hash = P.hex(P.randomBytes(32)), answers = undefined, withheld = [], receipts = undefined } = {}) {
  const out = [];
  const per = Math.ceil(questions.length / pages) || 1;
  for (let i = 0; i < pages; i++) {
    const qs = questions.slice(i * per, (i + 1) * per);
    out.push(P.utf8(JSON.stringify({ v: 1, kind: "decisions-snapshot", horde: m.horde, machine: m.keyId, snapshot: hash, page: i + 1, pages, questions: qs, withheld, counts: { open: questions.length }, unreadable: 0, notUnderstood: 0, ...(answers === undefined ? {} : { answers }), ...(receipts === undefined ? {} : { receipts }) })));
  }
  return out;
}
const question = (number, title, extra = {}) => ({ number, title, kind: "yes-no", state: "open", group: "g", askedBy: "orc-a", wordingVersion: 1, thread: { count: 0, turn: "founder", messages: [] }, ...extra });
async function sendSnapshot(transport, m, phones, questions, opts = {}) {
  const keys = [];
  for (const body of snapshotPages(m, questions, opts)) {
    const e = await machineEnvelope(m, { kind: "snapshot", channel: "decisions", body, phones });
    await transport.put(m.horde + "/phone", e.key, e.text);
    keys.push(e);
  }
  return keys;
}
// What the machine would open of the phone's answer: the body, by its agreement key.
async function machineOpens(m, text) {
  // The phone's vouch item is no envelope (relay/Trust.ps1, THE VOUCH TRAVELS BY ITSELF): it is on no channel.
  if (text.startsWith('{"v":1,"kind":"horde-relay-phone-vouch",')) return { header: { channel: "", kind: "phone-vouch" }, sig: null, body: JSON.parse(text) };
  const e = JSON.parse(text);
  const ht = P.headerText(e.header);
  const aad = P.utf8("horde-relay/envelope/v1 aad\n" + ht);
  const r = e.recipients.find((x) => x.kid === m.agreeKeyId);
  const cek = await P.hpkeOpen(m.agree.privateKey, m.agreePublic, P.unb64u(r.enc), P.utf8("horde-relay/envelope/v1 content-key"), aad, P.unb64u(r.key));
  return { header: e.header, sig: e.sig, body: JSON.parse(P.fromUtf8(await P.gcmOpen(cek, P.unhex(e.header.nonce), aad, P.unb64u(e.ct)))) };
}
async function phoneKeyOf(transport, m) {
  // The phone's announcement, as the machine reads it: the agreement key it vouched for - from the phone
  // vouch item (relay/Trust.ps1, THE VOUCH TRAVELS BY ITSELF).
  const r = await transport.get(m.mailbox, 0, 256);
  for (const it of r.value.items) { if (it.text.startsWith('{"v":1,"kind":"horde-relay-phone-vouch",')) return P.unb64u(JSON.parse(it.text).agreePublic); }
  return null;
}

const origin = "https://relay.example.test";
function newApp(transport, { prf = true, store = memoryStore(), authenticator = null, account = null } = {}) {
  const auth = authenticator || softAuthenticator({ origin, prf });
  return { store, auth, phone: createPhone({ store, authenticator: auth, relay: R.createRelayClient(transport), account, origin }) };
}
async function pairedApp(transport, m, opts = {}) {
  const app = newApp(transport, opts);
  const paired = await app.phone.pair({ offerText: (await offerText(m)), label: "Founder phone" });
  await app.phone.announce(paired.id);
  const phoneKey = await phoneKeyOf(transport, m);
  return { ...app, paired, phoneKey };
}

// --- 1. HPKE against RFC 9180 (test/fixtures/relay/hpke-p256-sha256-aes256gcm.json) ---
{
  const v = JSON.parse(readFileSync(join(repoRoot, "test/fixtures/relay/hpke-p256-sha256-aes256gcm.json"), "utf8"));
  const jwk = (sk, pk) => { const p = P.unhex(pk); return { kty: "EC", crv: "P-256", d: P.b64u(P.unhex(sk)), x: P.b64u(p.slice(1, 33)), y: P.b64u(p.slice(33, 65)), ext: true }; };
  const eph = { privateKey: await subtle.importKey("jwk", jwk(v.skEm, v.pkEm), { name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]), publicPoint: P.unhex(v.pkEm) };
  const e0 = v.encryptions.find((e) => e.seq === 0);
  const sealed = await P.hpkeSeal(P.unhex(v.pkRm), P.unhex(v.info), P.unhex(e0.aad), P.unhex(e0.pt), eph);
  check(P.hex(sealed.enc) === v.enc && P.hex(sealed.sealed) === e0.ct, "HPKE Seal gives RFC 9180's enc and ciphertext for the suite's own vector (sequence 0)");
  const skR = await subtle.importKey("jwk", jwk(v.skRm, v.pkRm), { name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]);
  const opened = await P.hpkeOpen(skR, P.unhex(v.pkRm), P.unhex(v.enc), P.unhex(v.info), P.unhex(e0.aad), P.unhex(e0.ct));
  check(P.hex(opened) === e0.pt, "HPKE Open gives back RFC 9180's plaintext");
  const bad = P.unhex(e0.aad); bad[0] ^= 1;
  check((await throwsAsync(async () => P.hpkeOpen(skR, P.unhex(v.pkRm), P.unhex(v.enc), P.unhex(v.info), bad, P.unhex(e0.ct)))) !== "", "and refuses other additional data");
}

// --- 2. base64url has one spelling ---
{
  const all = new Uint8Array(256).map((_, i) => i);
  check(P.hex(P.unb64u(P.b64u(all))) === P.hex(all), "base64url round-trips every byte value");
  check((await throwsAsync(async () => P.unb64u("AB=="))) !== "" && (await throwsAsync(async () => P.unb64u("A+B/"))) !== "" && (await throwsAsync(async () => P.unb64u("AA"))) === "" && (await throwsAsync(async () => P.unb64u("AB"))) !== "", "base64url refuses padding, the other alphabet and stray bits in the last character");
}

// --- 3. the offer is read as far as a phone can ---
{
  const m = await newMachine("work");
  check((await P.readOffer((await offerText(m)))).ok, "a machine's offer reads");
  check(!(await P.readOffer((await offerText(m, { expiresAt: Date.now() - 1 })))).ok, "an expired offer is refused");
  check(!(await P.readOffer((await offerText(m, { mailbox: "work/other" })))).ok, "an offer whose mailbox is not its horde and machine is refused");
  check(!(await P.readOffer((await offerText(m, { agreeKeyId: "0".repeat(32) })))).ok, "an offer whose agreement key is not the one it names is refused");
  check(!(await P.readOffer((await offerText(m)).replace('{"v":1,', '{"v":1,"extra":1,'))).ok, "an offer with a member added is refused");
  check(!(await P.readOffer((await offerText(m)).replace(/,"grant":"[^"]*"/, ""))).ok, "an offer with no account grant is refused");
  check((await P.readOffer((await offerText(m)))).value.label === "build-box", "an offer names its machine by the label its grant signs");
  check(!(await P.readOffer((await offerText(m)).replace(/,"label":"[^"]*"/, ""))).ok && !(await P.readOffer((await offerText(m, { label: " padded" })))).ok && !(await P.readOffer((await offerText(m, { label: "x".repeat(65) })))).ok, "and one with no label, or a label a record cannot hold, is refused");
  check(!(await P.readOffer((await offerText(m, { grant: "A".repeat(85) })))).ok && !(await P.readOffer((await offerText(m, { grant: "A".repeat(84) + "+/" })))).ok, "and one whose grant is not 64 bytes of base64url");
  // THE GRANT IS VERIFIED (review of PR 301): a relay that makes an offer naming this machine's keys signs its
  // grant with a key of its own, and a grant of the right shape is not enough.
  const relayKey = await newMachine("work");
  const forgedId = P.hex(P.randomBytes(16));
  const forgedExp = Date.now() + 300000;
  const forged = P.b64u(await machineSign(relayKey, P.accountGrantBytes({ horde: "work", offer: forgedId, machine: m.keyId, expiresAt: forgedExp, label: "build-box" })));
  const fr = await P.readOffer((await offerText(m, { id: forgedId, expiresAt: forgedExp, grant: forged })));
  check(!fr.ok && fr.reason.indexOf("not signed by the machine") >= 0, "A FORGED OFFER - this machine's keys, a grant signed by another key - is refused", fr.reason);
  check(!(await P.readOffer((await offerText(m, { grant: "A".repeat(86) })))).ok, "and so is one whose grant is the right shape and signed by nobody");
  check(!(await P.readOffer((await offerText(m)).replace('"label":"build-box"', '"label":"other-box"'))).ok, "and one whose name was changed after its grant signed it");
  const app = newApp(R.memoryTransport());
  check((await throwsAsync(async () => app.phone.pair({ offerText: (await offerText(m, { origins: ["https://other.example.test"], rpId: "other.example.test" })), label: "x" }))).indexOf("not this app") >= 0, "an offer for another app's origin is refused before a passkey is made");
  check((await throwsAsync(async () => app.phone.pair({ offerText: (await offerText(m)), label: 'say "hi"' }))).indexOf("name this phone") >= 0, "a label the machine would refuse is refused first");
}

// --- 3a. the account grant, and the machine signature check the hosted relay makes (relay/Pairing.ps1) ---
{
  const m = await newMachine("work");
  const g = { horde: "work", offer: "0123456789abcdef0123456789abcdef", machine: m.keyId, expiresAt: 1760000000000, label: "build-box" };
  check(P.fromUtf8(P.accountGrantBytes(g)) === "horde-relay/pairing/v1 account-grant\nwork\n0123456789abcdef0123456789abcdef\n" + m.keyId + "\n1760000000000\nbuild-box", "the grant signs the domain, the horde, the offer, the machine, the expiry and the label, one to a line");
  const sig = new Uint8Array(await subtle.sign({ name: "ECDSA", hash: "SHA-256" }, m.sign.privateKey, P.accountGrantBytes(g)));
  const n = BigInt("0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551");
  const s = BigInt("0x" + P.hex(sig.slice(32)));
  const low = s > n / 2n ? n - s : s;
  const withS = (v) => { const out = sig.slice(); out.set(P.unhex(v.toString(16).padStart(64, "0")), 32); return out; };
  check(await P.verifyMachineSignature(m.signPublic, P.accountGrantBytes(g), withS(low)), "a low-S signature by the machine's key verifies");
  check(!(await P.verifyMachineSignature(m.signPublic, P.accountGrantBytes(g), withS(n - low))), "its high-S twin does not: one message, one signature");
  check(!(await P.verifyMachineSignature(m.signPublic, P.accountGrantBytes({ ...g, expiresAt: g.expiresAt + 1 }), withS(low))), "nor does the signature over another expiry");
  check(!(await P.verifyMachineSignature(m.signPublic, P.accountGrantBytes({ ...g, label: "evil-box" }), withS(low))), "nor over another label");
  const other = await newMachine("work");
  check(!(await P.verifyMachineSignature(other.signPublic, P.accountGrantBytes(g), withS(low))), "nor under another machine's key");
  check(!(await P.verifyMachineSignature(m.signPublic.slice(1), P.accountGrantBytes(g), withS(low))) && !(await P.verifyMachineSignature(m.signPublic, P.accountGrantBytes(g), withS(low).slice(1))), "and a key or a signature of the wrong length is false, not a throw");
}

// --- 3c. accounts: the phone registers the machine with its account before anything else is made ---
{
  const m = await newMachine("work");
  const calls = [];
  const said = (answer) => ({ registerMachine: async (o) => { calls.push(o); return answer; } });
  let made = 0;
  const base = softAuthenticator({ origin, prf: true });
  const counting = { create: async (a) => { made++; return base.create(a); }, get: (a) => base.get(a) };
  const t = R.memoryTransport();
  const outPhone = createPhone({ store: memoryStore(), authenticator: counting, relay: R.createRelayClient(t), account: said({ state: "unknown", value: null, reason: "the relay answered 401: who are you", status: 401 }), origin });
  const text = (await offerText(m));
  const o = (await P.readOffer(text)).value;
  const refused = await throwsAsync(async () => outPhone.pair({ offerText: text, label: "Founder phone" }));
  check(refused.indexOf("Sign in") >= 0 && made === 0 && (await t.get(o.pairMailbox, 0, 10)).value.items.length === 0, "a phone not signed in is told to sign in, before a passkey is made or anything is sent", refused);
  check(refused.indexOf("401") < 0 && refused.indexOf("who are you") < 0, "and the relay's own words are not on the screen", refused);
  const t2 = R.memoryTransport();
  const order = [];
  const watched = { put: async (...a) => { order.push("put"); return t2.put(...a); }, get: (...a) => t2.get(...a), watch: (...a) => t2.watch(...a), ack: (...a) => t2.ack(...a) };
  const acct = { registerMachine: async (x) => { order.push("register"); calls.push(x); return { state: "known", value: { keyId: x.machine, horde: x.horde, duplicate: false }, reason: "", status: 200 }; } };
  const app = newApp(watched, { account: acct });
  const text2 = (await offerText(m));
  const o2 = (await P.readOffer(text2)).value;
  const paired = await app.phone.pair({ offerText: text2, label: "Founder phone" });
  const sent = calls[calls.length - 1];
  check(paired.relayed === true && order.join(",") === "register,put", "signed in, the phone registers the machine first, then sends its response through the relay", order.join(","));
  check(sent.horde === "work" && sent.offer === o2.offer && sent.machine === m.keyId && sent.label === "build-box" && sent.signPublic === o2.signPublic && sent.expiresAt === o2.expiresAt && sent.grant === o2.grant, "with the offer's horde, id, machine, label, signing key, expiry and account grant", JSON.stringify(sent));
  const bad = createPhone({ store: memoryStore(), authenticator: softAuthenticator({ origin, prf: true }), relay: R.createRelayClient(R.memoryTransport()), account: said({ state: "unknown", value: null, reason: "the relay answered 409: this machine's key is registered to another account", status: 409 }), origin });
  const why = await throwsAsync(async () => bad.pair({ offerText: (await offerText(m)), label: "Founder phone" }));
  check(why.indexOf("did not register") >= 0 && why.indexOf("409") < 0, "a registration the relay refuses stops the pairing, in the app's own words", why);
  const plain = newApp(R.memoryTransport());
  check((await plain.phone.pair({ offerText: (await offerText(m)), label: "Founder phone" })).relayed === true, "with no accounts (a memory or binding relay), the phone pairs as it always did");
}
{
  const sent = [];
  const fake = async (url, init) => { sent.push({ url, init }); return new Response(JSON.stringify({ keyId: "k" }), { status: 200 }); };
  const a = AC.accountClient(fake, "");
  const offer = { horde: "work", offer: "0".repeat(32), machine: "1".repeat(32), label: "build-box", signPublic: "AAAA", expiresAt: 5, grant: "G", code: "secret-code", agreePublic: "x", text: "whole" };
  await a.registerMachine(offer);
  const r = sent[0];
  check(r.url === "/v1/account/machines" && r.init.method === "POST" && r.init.credentials === "same-origin" && r.init.redirect === "error", "the account client posts a registration to its own origin with the browser's cookie, and follows no redirect");
  check(Object.keys(JSON.parse(r.init.body)).join(",") === "horde,offer,machine,label,signPublic,expiresAt,grant", "carrying exactly the seven fields the relay takes - never the offer's code", r.init.body);
  check((await a.removeMachine("../../v1/x")).state === "unknown" && sent.length === 1, "a removal of something that is not a key id is never sent");
  await a.removeMachine("2".repeat(32));
  check(sent[1].url === "/v1/account/machines/" + "2".repeat(32) && sent[1].init.method === "DELETE", "and a key id's removal is a DELETE of that machine");
  check((await a.signOutPhone("../x")).state === "unknown" && sent.length === 2, "a phone's sign-out of something that is not a phone's id is never sent");
  await a.signOutPhone("3".repeat(64));
  check(sent[2].url === "/v1/account/phones/" + "3".repeat(64) && sent[2].init.method === "DELETE" && sent[2].init.credentials === "same-origin", "and a phone's id's sign-out is a DELETE of that phone");
  await a.deleteAccount();
  check(sent[3].url === "/v1/account" && sent[3].init.method === "DELETE" && JSON.parse(sent[3].init.body).confirm === AC.DELETE_CONFIRM && Object.keys(JSON.parse(sent[3].init.body)).join(",") === "confirm" && AC.DELETE_CONFIRM === "delete this account", "deleting the account is a DELETE of it carrying the words the relay asks for, and nothing else", sent[3].init.body);
  const no = AC.accountClient(async () => new Response(JSON.stringify({ error: "x".repeat(500) }), { status: 401 }), "");
  const n = await no.session();
  check(n.state === "unknown" && n.status === 401 && n.reason.length < 260, "a refusal comes back unknown with its status, the relay's words cut short");
  const host = { fetch: async () => new Response("{}") };
  check(AC.accountFromConfig({ transport: "http" }, host) !== null && AC.accountFromConfig({ transport: "memory" }, host) === null && AC.accountFromConfig({ transport: "binding" }, host) === null && AC.accountFromConfig({ transport: "http", relayOrigin: "https://other.example.test" }, host) === null, "only a relay that is the app's own site has accounts");
}

// --- 3b. the pairing response goes to the machine through the relay, sealed (relay/Pairing.ps1) ---
{
  const m = await newMachine("work");
  check(!(await P.readOffer((await offerText(m, { pairMailbox: "work/" + m.keyId })))).ok, "an offer whose pairing mailbox is not its horde and offer is refused (it could send the response to the machine's own mailbox)");
  check(!(await P.readOffer((await offerText(m, { pairMailbox: "other/pair-" + "0".repeat(32) })))).ok, "and one naming another horde's");
  const t = R.memoryTransport();
  const app = newApp(t);
  const text = (await offerText(m));
  const o = (await P.readOffer(text)).value;
  const paired = await app.phone.pair({ offerText: text, label: "Founder phone" });
  check(paired.relayed === true && paired.pairMailbox === "work/pair-" + o.offer, "pairing sends the response through the relay, to the offer's own mailbox", JSON.stringify({ relayed: paired.relayed, box: paired.pairMailbox }));
  const items = (await t.get(o.pairMailbox, 0, 256)).value.items;
  check(items.length === 1 && items[0].key === "pairing/" + o.offer, "one item, under the offer's key", JSON.stringify(items.map((i) => i.key)));
  const sealed = items.length ? items[0].text : "";
  check(sealed.indexOf(o.code) < 0 && sealed.indexOf("Founder phone") < 0 && sealed.indexOf("webauthn") < 0, "the relay sees neither the code, the label nor the registration");
  const sv = JSON.parse(sealed || "{}");
  check(Object.keys(sv).join(",") === "v,kind,offer,agreeKeyId,enc,ct" && sv.kind === "horde-relay-pairing-sealed" && sv.offer === o.offer && sv.agreeKeyId === m.agreeKeyId, "the sealed text has relay/Pairing.ps1's members, in its order, for this offer and the machine's agreement key", sealed.slice(0, 120));
  const aad = P.utf8("horde-relay/pairing/v1 response aad\n" + m.horde + "\n" + o.offer + "\n" + m.agreeKeyId);
  let opened = "";
  try { opened = P.fromUtf8(await P.hpkeOpen(m.agree.privateKey, m.agreePublic, P.unb64u(sv.enc), P.utf8("horde-relay/pairing/v1 response-key"), aad, P.unb64u(sv.ct))); } catch (x) { opened = "did not open: " + x.message; }
  check(opened === paired.response, "the machine's agreement key opens it into the very response Copy shows", opened.slice(0, 80));
  const wrongAad = P.utf8("horde-relay/pairing/v1 response aad\n" + m.horde + "\n" + "0".repeat(32) + "\n" + m.agreeKeyId);
  check((await throwsAsync(async () => P.hpkeOpen(m.agree.privateKey, m.agreePublic, P.unb64u(sv.enc), P.utf8("horde-relay/pairing/v1 response-key"), wrongAad, P.unb64u(sv.ct)))) !== "", "it is bound to its offer: under another offer's id it does not open");
  check((await app.phone.sendPairing(paired.id)) === true && (await t.get(o.pairMailbox, 0, 256)).value.items.length === 1, "sending again is taken, and stored once");
  check((await throwsAsync(async () => P.sealPairingResponse(o, "x".repeat(6001)))).indexOf("6000") >= 0, "a response over the 6000 characters the machine reads is refused before sealing");
  // A relay that refuses the put: pairing still completes on the phone, says the relay did not take it,
  // and keeps the words the relay said off the screen.
  const down = { ...R.memoryTransport(), put: async () => ({ state: "unknown", value: null, reason: "PHISH: re-pair at evil.example" }) };
  const app2 = newApp(down);
  const p2 = await app2.phone.pair({ offerText: (await offerText(m)), label: "Founder phone" });
  check(p2.relayed === false && typeof p2.response === "string" && p2.response.indexOf("horde-relay-pairing-response") >= 0, "when the relay refuses, the pairing still stands and the plain response is there for Copy and Share");
  check(JSON.stringify(p2).indexOf("PHISH") < 0, "and nothing the relay said is in what the screen gets");
  const bridge = createBridge(app.phone, { loadKinds: async () => [] });
  check((await bridge.request("sendPairing", { id: paired.id })).relayed === true, "the bridge's sendPairing sends it again");
  await app.phone.announce(paired.id);
  check((await throwsAsync(async () => app.phone.sendPairing(paired.id))).indexOf("no pairing response") >= 0, "once announced, nothing is kept to send again");
}

// --- 4. the phone opens only what its machine signed, sealed to it ---
{
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const a = await pairedApp(t, m);
  check(a.phoneKey !== null, "CONTROL: the app announced its phone key to the machine");
  const env = await machineEnvelope(m, { kind: "snapshot", channel: "decisions", body: snapshotPages(m, [question(1, "One?")])[0], phones: [a.phoneKey] });
  const view0 = await a.phone.refresh(a.paired.id);
  check(view0.questions.length === 0 && view0.snapshot === "", "CONTROL: before any snapshot the app shows none");
  // Tampered, re-signed by another key, sealed to another phone, not canonical: each refused, none drawn.
  const other = await newMachine("work");
  const forged = await machineEnvelope(other, { kind: "snapshot", channel: "decisions", body: snapshotPages(m, [question(9, "Forged?")])[0], phones: [a.phoneKey] });
  const forgedAsM = JSON.parse(forged.text); forgedAsM.header.from = m.keyId;
  const reText = '{"header":' + P.headerText(forgedAsM.header) + ',"recipients":' + P.recipientsText(forgedAsM.recipients) + ',"ct":"' + forgedAsM.ct + '","sig":{"alg":"ES256","value":"' + forgedAsM.sig.value + '"}}';
  await t.put("work/phone", "forged-1", reText);
  const tampered = JSON.parse(env.text); const ctb = P.unb64u(tampered.ct); ctb[3] ^= 1; tampered.ct = P.b64u(ctb);
  await t.put("work/phone", "tampered-1", '{"header":' + P.headerText(tampered.header) + ',"recipients":' + P.recipientsText(tampered.recipients) + ',"ct":"' + tampered.ct + '","sig":{"alg":"ES256","value":"' + tampered.sig.value + '"}}');
  await t.put("work/phone", "spaced-1", env.text.replace('{"header":', '{ "header":'));
  const v1 = await a.phone.refresh(a.paired.id);
  check(v1.questions.length === 0, "a snapshot signed by another key in this machine's name, a tampered one and a non-canonical one are not drawn");
  check(v1.anomalies.some((x) => x.indexOf("signature does not verify") >= 0) && v1.anomalies.some((x) => x.indexOf("not canonical") >= 0), "and each is reported as an anomaly with its reason", JSON.stringify(v1.anomalies));
  await t.put("work/phone", env.key, env.text);
  const v2 = await a.phone.refresh(a.paired.id);
  check(v2.questions.length === 1 && v2.questions[0].title === "One?", "the machine's own snapshot, sealed to the phone, is drawn");
}

// --- 5. pages, freshness, two hordes ---
{
  const t = R.memoryTransport();
  const work = await newMachine("work");
  const personal = await newMachine("personal");
  const a = newApp(t);
  const pw = await a.phone.pair({ offerText: (await offerText(work)), label: "Founder phone" });
  await a.phone.announce(pw.id);
  const pp = await a.phone.pair({ offerText: (await offerText(personal)), label: "Founder phone" });
  await a.phone.announce(pp.id);
  const hs = await a.phone.hordes();
  check(hs.length === 2 && hs.map((h) => h.horde).sort().join(",") === "personal,work", "one app holds two hordes, each its own pairing");
  const kw = await phoneKeyOf(t, work), kp = await phoneKeyOf(t, personal);
  check(kw && kp && P.hex(kw) !== P.hex(kp), "each horde has its own phone identity key");
  // A two-page snapshot with its second page missing is not drawn; with it, it is, in page order.
  const qs = [question(1, "W1?"), question(2, "W2?"), question(3, "W3?")];
  const bodies = snapshotPages(work, qs, { pages: 2 });
  const p1 = await machineEnvelope(work, { kind: "snapshot", channel: "decisions", body: bodies[0], phones: [kw] });
  const p2 = await machineEnvelope(work, { kind: "snapshot", channel: "decisions", body: bodies[1], phones: [kw] });
  await t.put("work/phone", p1.key, p1.text);
  check((await a.phone.refresh(pw.id)).questions.length === 0, "a snapshot with a page missing is not drawn");
  await t.put("work/phone", p2.key, p2.text);
  const v = await a.phone.refresh(pw.id);
  check(v.questions.map((q) => q.number).join(",") === "1,2,3" && v.pageKeyByNumber[1] === p1.key && v.pageKeyByNumber[3] === p2.key, "once whole it is drawn in page order, each question bound to the page that carried it");
  await sendSnapshot(t, personal, [kp], [question(1, "P1?")]);
  const vp = await a.phone.refresh(pp.id);
  check(vp.questions.length === 1 && vp.questions[0].title === "P1?", "the other horde shows its own question 1, not this one's");
  check((await a.phone.refresh(pw.id)).questions.length === 3, "and this one still shows its own three");
  // Freshness: a newer snapshot replaces; an older one served later is not drawn over it.
  const newer = await sendSnapshot(t, work, [kw], [question(1, "W1, reworded?")]);
  check((await a.phone.refresh(pw.id)).questions[0].title === "W1, reworded?", "a newer snapshot replaces the one on screen");
  const old = await machineEnvelope(work, { kind: "snapshot", channel: "decisions", body: snapshotPages(work, [question(1, "Stale?")])[0], phones: [kw], seq: 1 });
  await t.put("work/phone", "stale-1", old.text);
  const after = await a.phone.refresh(pw.id);
  check(after.questions[0].title === "W1, reworded?" && after.seq === newer[0].header.seq, "an older snapshot the relay serves later is not drawn over it");
  // A reload re-reads from where the last snapshot began, and still never goes back.
  const b = { phone: createPhone({ store: a.store, authenticator: a.auth, relay: R.createRelayClient(t), origin }) };
  await b.phone.unlock(pw.id);
  const re = await b.phone.refresh(pw.id);
  check(re.questions.length === 1 && re.questions[0].title === "W1, reworded?", "after a reload the newest snapshot is found again and the stale one is not shown", JSON.stringify(re.questions.map((q) => q.title)));
  // A relay that hides the newest snapshot from a reloaded app and serves only the stale one: the app
  // remembers the seq of what it showed, and draws nothing older.
  const hidden = new Set(newer.map((e) => e.key));
  const hiding = { ...t, get: async (mb, since, max) => { const r = await t.get(mb, since, max); return { ...r, value: { items: r.value.items.filter((i) => !hidden.has(i.key)) } }; } };
  const c = createPhone({ store: a.store, authenticator: a.auth, relay: R.createRelayClient(hiding), origin });
  await c.unlock(pw.id);
  const hid = await c.refresh(pw.id);
  check(hid.questions.length === 0 && hid.stale === true && hid.anomalies.some((x) => x.indexOf("older than one already shown") >= 0), "a relay that hides the newest snapshot cannot make a reloaded app show an older one", JSON.stringify({ q: hid.questions.map((q) => q.title), stale: hid.stale }));
}

// --- 6. answers: bound to machine and page, and only from a passkey session ---
{
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const a = await pairedApp(t, m);
  const sent = await sendSnapshot(t, m, [a.phoneKey], [question(4, "Four?", { wordingVersion: 2 })]);
  await a.phone.refresh(a.paired.id);
  const id = P.hex(P.randomBytes(16));
  await a.phone.answer(a.paired.id, { number: 4, wordingVersion: 2, text: "Yes.", answerId: id });
  const items = (await t.get(m.mailbox, 0, 256)).value.items;
  const ans = await machineOpens(m, items[items.length - 1].text);
  check(ans.header.channel === "decisions" && ans.header.kind === "answer" && ans.sig.alg === "webauthn.get", "the answer is an envelope on channel decisions, kind answer, signed by the passkey");
  check(ans.body.machine === m.keyId && ans.body.snapshot === sent[0].key && ans.body.number === 4 && ans.body.wordingVersion === 2 && ans.body.answerId === id && ans.body.text === "Yes.", "bound to this machine and to the replay key of the page that carried the question");
  check(Object.keys(ans.body).join(",") === "v,answerId,machine,snapshot,number,wordingVersion,text", "with exactly the members channels/decisions reads, in order");
  await a.phone.answer(a.paired.id, { number: 4, wordingVersion: 2, text: "Yes.", answerId: id });
  const seqs = [];
  for (const it of (await t.get(m.mailbox, 0, 256)).value.items) if (it.text.startsWith('{"header":')) seqs.push((await machineOpens(m, it.text)).header);
  check(seqs.filter((h) => h.channel === "decisions").map((h) => h.seq).join(",") === "1,2" && seqs.filter((h) => h.channel === "trust").length === 0, "each channel counts its own sequence, from 1 and up by one; the announcement is a vouch item and spends none", JSON.stringify(seqs.map((h) => h.channel + h.seq)));
  check((await throwsAsync(async () => a.phone.answer(a.paired.id, { number: 5, wordingVersion: 1, text: "x", answerId: id }))).indexOf("not in the snapshot") >= 0, "a question not in the snapshot on screen is not answered");
  // The recovery code: read, never answer.
  const code = a.paired.recoveryCode;
  a.phone.lock(a.paired.id);
  check((await throwsAsync(async () => a.phone.answer(a.paired.id, { number: 4, wordingVersion: 2, text: "x", answerId: id }))).indexOf("locked") >= 0, "a locked horde answers nothing");
  await a.phone.recover(a.paired.id, code);
  check((await a.phone.refresh(a.paired.id)).questions.length === 1, "the recovery code unlocks to read");
  const before = (await t.get(m.mailbox, 0, 256)).value.items.length;
  check((await throwsAsync(async () => a.phone.answer(a.paired.id, { number: 4, wordingVersion: 2, text: "x", answerId: id }))).indexOf("Read only") >= 0 && (await t.get(m.mailbox, 0, 256)).value.items.length === before, "and refuses to answer, sending nothing");
  // A passkey unlock after the recovery code makes the session a signing one again.
  await a.phone.unlock(a.paired.id);
  check((await a.phone.hordes())[0].mode === "passkey", "the passkey unlocks it to answer again");
}

// --- 7. the key wraps ---
{
  const pk = await K.newPhoneKey();
  const kid = await P.keyId(pk.publicPoint);
  const prfA = P.randomBytes(32), prfB = P.randomBytes(32);
  const w = await K.wrapWithPrf(pk.pkcs8, prfA, "work", kid);
  check((await K.unwrap(w, prfA, "work", kid, pk.publicPoint)).ok, "a PRF wrap opens with its PRF output");
  check(!(await K.unwrap(w, prfB, "work", kid, pk.publicPoint)).ok, "and not with another credential's");
  check(!(await K.unwrap(w, prfA, "personal", kid, pk.publicPoint)).ok, "nor moved to another horde's record");
  check(!(await K.unwrap({ ...w, kind: "device" }, prfA, "work", kid, pk.publicPoint)).ok, "nor relabelled as another kind");
  const code = K.newRecoveryCode();
  check(/^[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){5}$/.test(code), "a recovery code is six groups of four Crockford characters", code);
  const rw = await K.wrapWithRecovery(pk.pkcs8, code, "work", kid);
  check(rw.iterations === 600000, "a recovery wrap records its PBKDF2 work factor, 600000");
  const typed = code.toLowerCase().replace(/-/g, " ").replace(/0/g, "o").replace(/1/g, "l");
  check((await K.unwrap(rw, typed, "work", kid, pk.publicPoint)).ok, "the code typed in lower case, with spaces, O for 0 and L for 1, still opens it");
  check((await K.unwrap({ ...rw, iterations: 1000 }, code, "work", kid, pk.publicPoint)).reason.indexOf("work factor") >= 0, "a wrap claiming a feeble work factor is refused before it is tried");
  check((await K.unwrap({ ...w, kind: "device" }, prfA, "work", kid, pk.publicPoint)).reason.indexOf("unknown kind of key wrap") >= 0, "a record of kind device is not a wrap the app knows");
  const other = await K.newPhoneKey();
  check(!(await K.unwrap(w, prfA, "work", kid, other.publicPoint)).ok, "a record unwrapped against another public key is refused");
  // A wrap whose additional data names this key but whose bytes are ANOTHER key: it opens, the ids
  // agree, and only agreeing with the unwrapped key shows it is not the one the record says.
  const swapped = await K.wrapWithPrf(other.pkcs8, prfA, "work", kid);
  const sw = await K.unwrap(swapped, prfA, "work", kid, pk.publicPoint);
  check(!sw.ok && sw.reason.indexOf("not this horde's phone key") >= 0, "a wrap that holds another key under this key's name is refused once unwrapped", sw.reason);
  // Crockford reads O as 0 and I and L as 1: a code with those digits, typed with those letters.
  const fixed = "0123-4567-89AB-CDEF-GHJK-MNP1";
  const fw = await K.wrapWithRecovery(pk.pkcs8, fixed, "work", kid, 100000);
  check((await K.unwrap(fw, "o123-4567-89ab-cdef-ghjk-mnpl", "work", kid, pk.publicPoint)).ok && (await K.unwrap(fw, "OI23 4567 89AB CDEF GHJK MNPI", "work", kid, pk.publicPoint)).ok, "a code typed with O for 0 and I or L for 1 opens what the code wrapped");
}

// --- 8. a passkey without PRF: the horde is READ ONLY (founder decision 2026-10-10, Q3) ---
{
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const a = await pairedApp(t, m, { prf: false });
  const h = (await a.phone.hordes())[0];
  check(a.phoneKey !== null, "CONTROL: a passkey without PRF still announces the phone key, so the horde can be read");
  check(h.prf === false && h.wraps.join(",") === "recovery" && h.mode === "read-only", "with no PRF the key is kept under the recovery code only - no browser device key - and the horde is read only", JSON.stringify(h));
  await sendSnapshot(t, m, [a.phoneKey], [question(1, "One?")]);
  check((await a.phone.refresh(a.paired.id)).questions.length === 1, "it can be read");
  const before = (await t.get(m.mailbox, 0, 256)).value.items.length;
  const why = await throwsAsync(async () => a.phone.answer(a.paired.id, { number: 1, wordingVersion: 1, text: "Yes.", answerId: P.hex(P.randomBytes(16)) }));
  check(why.indexOf("no PRF") >= 0 && why.indexOf("Read only") >= 0 && (await t.get(m.mailbox, 0, 256)).value.items.length === before, "an answer is refused in plain words, and nothing is sent", why);
  const b = createPhone({ store: a.store, authenticator: a.auth, relay: R.createRelayClient(t), origin });
  const un = await throwsAsync(async () => b.unlock(a.paired.id));
  check(un.indexOf("no PRF") >= 0 && un.indexOf("recovery code") >= 0, "after a reload the passkey cannot unlock it, and says the recovery code reads it", un);
  await b.recover(a.paired.id, a.paired.recoveryCode);
  check((await b.refresh(a.paired.id)).questions.length === 1 && (await b.hordes())[0].mode === "recovery", "the recovery code reads it");
  check(!Object.keys(K).some((k) => /device/i.test(k)), "the browser device-key wrap is gone from the app", Object.keys(K).join(","));
}

// --- 9. the relay client distrusts the relay ---
{
  const liar = { get: async () => ({ state: "known", value: { items: [{ seq: 3, key: "c", text: "three" }, { seq: 1, key: "a", text: "one" }, { seq: 3, key: "x", text: "again" }, { seq: 0, key: "z", text: "zero" }, { seq: 5, key: "bad key!", text: "five" }, { seq: 6, key: "f", text: "caf" + String.fromCharCode(0xe9) }] } }) };
  const c = R.createRelayClient(liar);
  const r = await c.get("work/phone", 0, 256);
  check(r.state === "known" && r.value.items.map((i) => i.seq).join(",") === "1,3" && r.value.next === 3, "a batch is rebuilt in seq order, with repeats, malformed items and non-ASCII texts dropped", JSON.stringify(r.value));
  check(r.value.items[1].text === "three" && r.value.anomalies.some((x) => x.indexOf("a second item under seq 3") >= 0), "of two items under one seq the first is kept and the second is reported");
  check(r.value.anomalies.length >= 4 && r.value.gaps.length === 1 && r.value.gaps[0].indexOf("seq 2 to 2") >= 0, "each drop is reported, and the hole between the two delivered items is reported as a gap", JSON.stringify(r.value));
  check(!r.value.anomalies.some((x) => x.indexOf("gap") >= 0), "a gap is reported apart from the anomalies: what a hole means is the caller's to say");
  const later = await c.get("work/phone", 1, 256);
  check(later.value.items.map((i) => i.seq).join(",") === "3" && later.value.anomalies.some((x) => x.indexOf("at or before the cursor") >= 0), "an item at or before the cursor is dropped, and said so");
  const one = await c.get("work/phone", 0, 1);
  check(one.value.items.length === 1 && one.value.next === 1, "a batch is cut to the size asked, and the cursor is the last item delivered");
  check((await c.put("Work/phone", "k", "t")).state === "unknown" && (await c.put("work/con", "k", "t")).state === "unknown", "a mailbox the port would refuse is refused here too");
  const thrower = R.createRelayClient({ put: async () => { throw new Error("down"); } });
  check((await thrower.put("work/phone", "k", "t")).reason.indexOf("down") >= 0, "a transport that throws answers unknown with its reason");
  check(R.transportFromConfig({ transport: "nope" }, {}) === null && R.transportFromConfig({ transport: "memory" }, {}) !== null, "a config's transport is one of the known names, or none");
  const unbound = R.createRelayClient(R.bindingTransport({}, "hordeRelayBinding"));
  check((await unbound.get("work/phone", 0, 1)).reason.indexOf("not bound") >= 0, "the test transport with no host behind it answers unknown");
}

// --- 6b. one part of a question, answered by itself (the founder, 2026-10-12) ---
{
  const partsQuestion = (number, extra = {}) => question(number, "Three things, one by one?", { kind: "parts", parts: ["(a) First?", "(b) Second?", "(c) Third?"], ...extra });
  const lastAnswer = async (t, m) => { const items = (await t.get(m.mailbox, 0, 256)).value.items; return machineOpens(m, items[items.length - 1].text); };
  // A machine that says it reads version 2 answers is sent the part as a member of the answer.
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const a = await pairedApp(t, m);
  const sent = await sendSnapshot(t, m, [a.phoneKey], [partsQuestion(4)], { answers: 2 });
  await a.phone.refresh(a.paired.id);
  const id = P.hex(P.randomBytes(16));
  await a.phone.answer(a.paired.id, { number: 4, wordingVersion: 1, text: "No, keep it.", answerId: id, part: "b" });
  const ans = await lastAnswer(t, m);
  check(ans.body.v === 2 && ans.body.part === "b" && ans.body.text === "No, keep it." && ans.body.number === 4 && ans.body.answerId === id && ans.body.snapshot === sent[0].key && ans.sig.alg === "webauthn.get", "A PART'S ANSWER, to a machine that reads them, is a version 2 answer naming the part - the words untouched - signed by the passkey like any answer", JSON.stringify(ans.body));
  check(Object.keys(ans.body).join(",") === "v,answerId,machine,snapshot,number,wordingVersion,text,part", "with exactly the members channels/decisions reads for version 2, in order");
  const before = (await t.get(m.mailbox, 0, 256)).value.items.length;
  await a.phone.answer(a.paired.id, { number: 4, wordingVersion: 1, text: "To all of it.", answerId: P.hex(P.randomBytes(16)) });
  const whole = await lastAnswer(t, m);
  check(whole.body.v === 1 && !("part" in whole.body) && whole.body.text === "To all of it." && Object.keys(whole.body).join(",") === "v,answerId,machine,snapshot,number,wordingVersion,text", "an answer to the whole question is version 1 with no part, to that machine too: what every machine reads");
  for (const bad of ["B", "ab", "1", " "]) {
    const count = (await t.get(m.mailbox, 0, 256)).value.items.length;
    const why = await throwsAsync(async () => a.phone.answer(a.paired.id, { number: 4, wordingVersion: 1, text: "x", answerId: P.hex(P.randomBytes(16)), part: bad }));
    check(why.indexOf("not one of the question's parts") >= 0 && (await t.get(m.mailbox, 0, 256)).value.items.length === count, "a part of '" + bad + "' is refused in this phone's own words, and nothing is sent", why);
  }
  check(before >= 1, "CONTROL: the mailbox held the part's answer before the whole one");
  // An earlier machine - its snapshot says nothing of answers - is sent the words with the letter before them.
  const t0 = R.memoryTransport();
  const old = await newMachine("work");
  const a0 = await pairedApp(t0, old);
  await sendSnapshot(t0, old, [a0.phoneKey], [partsQuestion(4)]);
  await a0.phone.refresh(a0.paired.id);
  await a0.phone.answer(a0.paired.id, { number: 4, wordingVersion: 1, text: "No, keep it.", answerId: P.hex(P.randomBytes(16)), part: "b" });
  const fallback = await lastAnswer(t0, old);
  check(fallback.body.v === 1 && !("part" in fallback.body) && fallback.body.text === "(b) No, keep it." && Object.keys(fallback.body).join(",") === "v,answerId,machine,snapshot,number,wordingVersion,text", "TO A MACHINE THAT DOES NOT SAY IT READS PARTS the same answer is version 1, the part's letter before the words: an answer it keeps, and its window reads into that part", JSON.stringify(fallback.body));
  // What a snapshot says of answers, read with care.
  for (const [said, want] of [[2, 2], [5, 5], [1, 1], [undefined, 1], [0, 1], [-2, 1], [1.5, 1], ["2", 1], [null, 1], [true, 1]]) {
    const tx = R.memoryTransport();
    const mx = await newMachine("work");
    const ax = await pairedApp(tx, mx);
    await sendSnapshot(tx, mx, [ax.phoneKey], [partsQuestion(4)], said === undefined ? {} : { answers: said });
    await ax.phone.refresh(ax.paired.id);
    await ax.phone.answer(ax.paired.id, { number: 4, wordingVersion: 1, text: "x", answerId: P.hex(P.randomBytes(16)), part: "a" });
    const got = await lastAnswer(tx, mx);
    check(got.body.v === (want >= 2 ? 2 : 1), "a snapshot whose answers is " + JSON.stringify(said) + " is answered with version " + (want >= 2 ? 2 : 1) + ": only a whole number from 2 up says the machine reads a part", JSON.stringify(got.body));
  }
  // The protocol's own body.
  const base = { answerId: id, machine: m.keyId, snapshot: m.keyId + "/decisions/1/" + "0".repeat(24), number: 4, wordingVersion: 1, text: "x" };
  check(JSON.parse(P.fromUtf8(P.answerBody({ ...base, part: "c" }))).v === 2 && JSON.parse(P.fromUtf8(P.answerBody(base))).v === 1 && JSON.parse(P.fromUtf8(P.answerBody({ ...base, part: "" }))).v === 1, "the answer body is version 2 with a part and version 1 with none, or with an empty one");
  for (const bad of ["C", "cc", "3", "-"]) check((await throwsAsync(async () => P.answerBody({ ...base, part: bad }))).indexOf("a part is one lower-case letter") >= 0, "the protocol makes no body for a part of '" + bad + "'");
  // THE SNAPSHOT'S NEW FIELDS REACH THE DOCUMENT AS THE MACHINE SENT THEM, and a snapshot without them
  // - an earlier machine's - is read as it always was.
  const t2 = R.memoryTransport();
  const m2 = await newMachine("work");
  const a2 = await pairedApp(t2, m2);
  await sendSnapshot(t2, m2, [a2.phoneKey], [
    partsQuestion(7, { importance: "high", importanceShown: "Important", blocks: "all", blocksShown: "Blocks all work", addedAt: "2026-10-12T09:00:00.0000000Z", followsUp: { number: 3, state: "open", title: "Earlier?", answer: "Yes.", answerCut: false, outcome: "" }, thread: { count: 1, turn: "founder", parts: [{ letter: "a", answered: true }, { letter: "b", answered: false }, { letter: "c", answered: false }], messages: [{ sequence: 9, speaker: "founder", text: "first", part: "a", partWords: "First?" }] } }),
    question(8, "An old one?")
  ], { answers: 2 });
  const view = await a2.phone.refresh(a2.paired.id);
  const q7 = view.questions.find((x) => x.number === 7);
  const q8 = view.questions.find((x) => x.number === 8);
  check(q7.importance === "high" && q7.blocksShown === "Blocks all work" && q7.followsUp.number === 3 && q7.followsUp.answer === "Yes." && q7.thread.messages[0].part === "a" && q7.thread.parts.length === 3, "how much a question matters and blocks, the question it follows, and which parts are answered reach the document as the machine sent them");
  check(q8.importance === undefined && q8.blocks === undefined && q8.followsUp === undefined && q8.title === "An old one?", "and a question from a machine that sends none of them is the question it always was: nothing is made up for it");
  const bridge = createBridge(a2.phone, { loadKinds: async () => ({}) });
  await bridge.request("pick", { id: a2.paired.id });
  const saidPart = await bridge.request("say", { number: 7, text: "second", wording: 1, id: P.hex(P.randomBytes(16)), part: "b" });
  const viaBridge = await lastAnswer(t2, m2);
  check(saidPart.ok === true && saidPart.sequence === 10 && viaBridge.body.v === 2 && viaBridge.body.part === "b" && viaBridge.body.text === "second", "THE BRIDGE'S say hands the part on: the document's answer to part (b) is sent as part (b)", JSON.stringify(viaBridge.body));
  const saidWhole = await bridge.request("say", { number: 7, text: "all of it", wording: 1, id: P.hex(P.randomBytes(16)) });
  const wholeVia = await lastAnswer(t2, m2);
  check(saidWhole.ok === true && wholeVia.body.v === 1 && !("part" in wholeVia.body), "and with no part it is the answer to the whole question it always was");
  const oddPart = await bridge.request("say", { number: 7, text: "x", wording: 1, id: P.hex(P.randomBytes(16)), part: 7 });
  const oddVia = await lastAnswer(t2, m2);
  check(oddPart.ok === true && oddVia.body.v === 1 && oddVia.body.text === "x", "a part that is not text is no part: the words go as an answer to the whole question, never as a part the page did not name");
}

// --- 10. the bridge ---
{
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const a = await pairedApp(t, m);
  await sendSnapshot(t, m, [a.phoneKey], [question(1, "One?", { thread: { count: 1, turn: "founder", messages: [{ sequence: 7, speaker: "warchief", text: "hi" }] } })]);
  const bridge = createBridge(a.phone, { loadKinds: async () => ({ "yes-no": { label: "yes or no" } }) });
  check(typeof bridge.request === "function" && typeof bridge.on === "function" && bridge.live === true && Object.keys(bridge).sort().join(",") === "live,on,request", "the bridge has the window bridge's three members and no more");
  const events = [];
  bridge.on("list-changed", (r) => events.push(r));
  const rec = await bridge.request("pick", { id: a.paired.id });
  check(rec.state === "known" && rec.value.outcome === "done" && rec.value.questions.length === 1 && events.length === 1, "pick answers the list record and pushes list-changed");
  const said = await bridge.request("say", { number: 1, text: "Yes.", wording: 1, id: P.hex(P.randomBytes(16)) });
  check(said.ok === true && said.sequence === 8, "say answers saved with a sequence one past the highest message in the snapshot", JSON.stringify(said));
  const bad = await bridge.request("say", { number: 1, text: "Yes.", wording: 1, id: "not-hex" });
  check(bad.ok === false && bad.reason.indexOf("answerId") >= 0, "say with an id that is not an answerId is refused in words");
  const act = await bridge.request("act", { number: 1, act: "park", wording: 1, id: P.hex(P.randomBytes(16)) });
  check(act.ok === true && act.local === true, "park is kept on the phone, said to be local");
  check((await throwsAsync(async () => bridge.request("report", {}))).indexOf("not a request") >= 0 && (await throwsAsync(async () => bridge.request("__proto__", {}))).indexOf("not a request") >= 0, "a request off the list, a prototype's name included, is refused");
  await bridge.request("lock", { id: a.paired.id });
  const locked = await bridge.request("list");
  check(locked.state === "unknown" && locked.reason.indexOf("locked") >= 0, "a locked horde's list is unknown, with the reason");
}

// --- 12. review of a8b732d: what a relay or a bad offer must not be able to do ---
{
  // Finding 1: a relay that serves one item under a huge seq poisons no cursor. After a reload the
  // phone reads from the start, and within a session a relay whose numbering goes backwards is
  // noticed, said, and read again from the start.
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const a = await pairedApp(t, m);
  const first = await sendSnapshot(t, m, [a.phoneKey], [question(1, "First?")]);
  let lying = true;
  const evil = { ...t, get: async (mb, since, max) => { const r = await t.get(mb, since, max); if (lying && mb === "work/phone" && since === 0) return { ...r, value: { items: [{ seq: 9007199254740000, key: "replayed", text: first[0].text }] } }; return r; } };
  const b = createPhone({ store: a.store, authenticator: a.auth, relay: R.createRelayClient(evil), origin });
  await b.unlock(a.paired.id);
  check((await b.refresh(a.paired.id)).questions.length === 1, "CONTROL: the lying relay's item opens: it is the machine's own snapshot, under a huge seq");
  lying = false;
  await sendSnapshot(t, m, [a.phoneKey], [question(1, "Second, newer?")]);
  const same = await b.refresh(a.paired.id);
  check(same.questions.length === 1 && same.questions[0].title === "Second, newer?" && same.anomalies.some((x) => x.indexOf("numbering went backwards") >= 0), "in the same session, a relay whose numbering went backwards is said so, and the newer snapshot is still found", JSON.stringify({ q: same.questions.map((q) => q.title), an: same.anomalies }));
  const c = createPhone({ store: a.store, authenticator: a.auth, relay: R.createRelayClient(t), origin });
  await c.unlock(a.paired.id);
  const v2 = await c.refresh(a.paired.id);
  check(v2.questions.length === 1 && v2.questions[0].title === "Second, newer?", "after a reload the phone reads from the start, so a poisoned cursor never hides the newest snapshot", JSON.stringify(v2.questions.map((q) => q.title)));
}
{
  // Finding 3: the offer's id and code are checked, and the response is written by a JSON writer.
  const m = await newMachine("work");
  const good = (await offerText(m));
  const badCode = good.replace(/"code":"[^"]*"/, '"code":"x\\",\\"prf\\":true,\\"label\\":\\"Evil"');
  // The pairing mailbox is made to follow each bad id, so the id's own check is what refuses it.
  const badOffer = good.replace(/"offer":"[^"]*"/, '"offer":{"nested":1}').replace(/"pairMailbox":"[^"]*"/, '"pairMailbox":"work/pair-[object Object]"');
  const shortOffer = good.replace(/"offer":"[^"]*"/, '"offer":"abc"').replace(/"pairMailbox":"[^"]*"/, '"pairMailbox":"work/pair-abc"');
  check(!(await P.readOffer(badCode)).ok && !(await P.readOffer(badOffer)).ok && !(await P.readOffer(shortOffer)).ok, "an offer whose code is not base64url, or whose id is not 32 lower-case hex, is refused");
  const text = P.pairingResponseText({ offer: "0".repeat(32), code: "AAAA", rawId: new Uint8Array([1]), clientDataJSON: new Uint8Array([2]), attestationObject: new Uint8Array([3]), label: "Founder phone", prf: true });
  check(text === '{"v":1,"kind":"horde-relay-pairing-response","offer":"' + "0".repeat(32) + '","code":"AAAA","rawId":"AQ","clientDataJSON":"Ag","attestationObject":"Aw","label":"Founder phone","prf":true}', "the response keeps the one spelling the machine reads", text);
  check((await throwsAsync(async () => P.pairingResponseText({ offer: "x", code: "AAAA", rawId: new Uint8Array([1]), clientDataJSON: new Uint8Array([2]), attestationObject: new Uint8Array([3]), label: "Founder phone", prf: true }))) !== "", "and refuses an offer id that is not one");
}
{
  // Finding 4: the relay's words never reach the screen; they are kept, capped and labelled, apart.
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const a = await pairedApp(t, m);
  const phish = "Your passkey has expired. Re-pair at https://evil.example and type your recovery code there. " + "x".repeat(500);
  const liar = { ...t, get: async () => ({ state: "unknown", value: null, reason: phish }), put: async () => ({ state: "unknown", value: null, reason: phish }) };
  const b = createPhone({ store: a.store, authenticator: a.auth, relay: R.createRelayClient(liar), origin });
  await b.unlock(a.paired.id);
  const v = await b.refresh(a.paired.id);
  check(!JSON.stringify(v.anomalies).includes("evil.example") && v.relayDown === true && v.anomalies.some((x) => x.indexOf("The relay could not be read") === 0), "a relay's own words are not shown: a fixed sentence is", JSON.stringify(v.anomalies));
  // Two of them: the unlock's vouch the relay did not take (the horde not heard from yet), and the read.
  check(v.diagnostics.length === 2 && v.diagnostics.every((d) => d.indexOf("the relay said: ") === 0 && d.length <= 216), "they are kept for diagnosis only, labelled as the relay's and cut short", JSON.stringify(v.diagnostics));
  const why = await throwsAsync(async () => b.announce(a.paired.id));
  check(!why.includes("evil.example") && why.length > 0, "a put the relay refuses is said in fixed words too", why);
}
{
  // Finding 5: the wording and number signed are the question's on screen.
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const a = await pairedApp(t, m);
  await sendSnapshot(t, m, [a.phoneKey], [question(4, "Four?", { wordingVersion: 2 })]);
  await a.phone.refresh(a.paired.id);
  const before = (await t.get(m.mailbox, 0, 256)).value.items.length;
  const why = await throwsAsync(async () => a.phone.answer(a.paired.id, { number: 4, wordingVersion: 7, text: "Yes.", answerId: P.hex(P.randomBytes(16)) }));
  check(why.indexOf("wording") >= 0 && (await t.get(m.mailbox, 0, 256)).value.items.length === before, "an answer to another wording than the one on screen is refused before anything is signed", why);
}

// --- 10b. the chat: turns from the end, joined, once; lines signed, bound, never from a read-only session ---
const chatBody = (m, session, turns, { backfill = false } = {}) => P.utf8(JSON.stringify({ v: 1, kind: "chat-turns", horde: m.horde, machine: m.keyId, session, backfill, turns }));
const receiptBody = (m, session, messageId, status, code, text) => P.utf8(JSON.stringify({ v: 1, kind: "chat-receipt", horde: m.horde, machine: m.keyId, session, messageId, status, code, text }));
async function sendChat(t, m, phone, body, kind = "turns") { const e = await machineEnvelope(m, { kind, channel: "chat", body, phones: [phone] }); await t.put(m.horde + "/phone", e.key, e.text); return e; }
const turn = (id, role, text, extra = {}) => ({ id, role, session: "sess-1", text, time: "2026-10-10T10:00:0" + (id.length % 10) + ".000Z", ...extra });
{
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const a = await pairedApp(t, m);
  const none = await a.phone.chat(a.paired.id);
  check(none.items.length === 0 && none.session === "", "CONTROL: before any turn the chat is empty and names no session");
  check((await throwsAsync(async () => a.phone.sendLine(a.paired.id, { text: "hello", messageId: P.hex(P.randomBytes(16)) }))).indexOf("no session") >= 0, "with no session heard of, a line is refused before anything is signed");
  await sendChat(t, m, a.phoneKey, chatBody(m, "sess-1", [turn("t1", "user", "first"), turn("t2", "assistant", "second")], { backfill: true }));
  // A long turn in two parts, the second arriving later; and the first envelope served again.
  const p1 = await sendChat(t, m, a.phoneKey, chatBody(m, "sess-1", [turn("t3", "assistant", "long ", { part: 1, parts: 2 })]));
  await a.phone.refresh(a.paired.id);
  let c = await a.phone.chat(a.paired.id);
  check(c.items.map((x) => x.text).join("|") === "first|second" && c.session === "sess-1", "the turns are shown in order, and the session is learnt; a turn with a part missing is not shown yet", JSON.stringify(c.items.map((x) => x.text)));
  await sendChat(t, m, a.phoneKey, chatBody(m, "sess-1", [turn("t3", "assistant", "reply", { part: 2, parts: 2 }), turn("t2", "assistant", "second")]));
  await t.put("work/phone", p1.key + "-again", p1.text);
  await a.phone.refresh(a.paired.id);
  c = await a.phone.chat(a.paired.id);
  check(c.items.map((x) => x.text).join("|") === "first|second|long reply", "once whole, the long turn is its parts joined; a turn sent twice and an envelope served twice show once", JSON.stringify(c.items.map((x) => x.text)));
  // A line: signed, bound to the horde, the machine and the session, opened by the machine.
  const mid = P.hex(P.randomBytes(16));
  await a.phone.sendLine(a.paired.id, { text: "carry on", messageId: mid });
  const sentItems = (await t.get(m.mailbox, 0, 256)).value.items;
  const opened = await machineOpens(m, sentItems[sentItems.length - 1].text);
  check(opened.header.channel === "chat" && opened.header.kind === "line" && opened.sig.alg === "webauthn.get", "a line is an envelope on chat, kind line, signed by the passkey");
  check(JSON.stringify(opened.body) === JSON.stringify({ v: 1, messageId: mid, horde: "work", machine: m.keyId, session: "sess-1", text: "carry on" }), "its body names the line, the horde, the machine and the Thrall's session, and his words", JSON.stringify(opened.body));
  c = await a.phone.chat(a.paired.id);
  const mine = c.items.find((x) => x.kind === "line");
  check(mine && mine.words === P.CHAT_SENDING && mine.text === "carry on", "until a receipt comes it is shown as sending");
  check(mine && mine.said === opened.header.ts && mine.saidHow === "sent" && opened.header.ts > 1700000000000, "and it says when he sent it: the very time his passkey signed in the line's envelope", JSON.stringify({ said: mine && mine.said, ts: opened.header.ts }));
  // The receipt, a forged code, a turn that merely quotes the line's header, and the machine's founder turn.
  await sendChat(t, m, a.phoneKey, receiptBody(m, "sess-1", mid, "held", "your-account-expired", "carry on"), "receipt");
  await a.phone.refresh(a.paired.id);
  c = await a.phone.chat(a.paired.id);
  check(c.items.find((x) => x.kind === "line").words === P.CHAT_SENDING, "a receipt with a code the phone does not know is not shown: no word of the machine's reaches the screen");
  await sendChat(t, m, a.phoneKey, receiptBody(m, "sess-1", mid, "accepted", "delivered", "carry on"), "receipt");
  await sendChat(t, m, a.phoneKey, chatBody(m, "sess-1", [turn("t4", "user", "FOUNDER LINE from the phone " + P.lineMarker(mid) + "\n\ncarry on"), turn("t5", "assistant", "on it"), turn("t6", "founder", "carry on", { line: mid }), turn("t7", "founder", "carry on", { line: mid })]));
  await a.phone.refresh(a.paired.id);
  c = await a.phone.chat(a.paired.id);
  const lines = c.items.filter((x) => x.kind === "line");
  check(lines.length === 1 && lines[0].words === P.CHAT_WORDS.accepted.delivered, "the receipt's code is shown in the phone's own fixed words", JSON.stringify(lines));
  check(c.items.some((x) => x.kind === "turn" && x.role === "user" && x.text.indexOf(P.lineMarker(mid)) >= 0), "a turn that quotes his line's header is shown as what it is - a user turn - never as his line");
  check(c.items.filter((x) => x.kind === "line" && x.messageId === mid).length === 1 && c.items.some((x) => x.text === "on it"), "the machine's founder turn for his line, handed over twice, is that one line, not three; the Thrall's reply is shown");
  check((await throwsAsync(async () => { const r = P.readChatTurns(chatBody(m, "s", [{ id: "x", role: "founder", session: "s", text: "t" }]), "work", m.keyId); if (r.value.turns.length) throw new Error("kept"); })) === "", "a founder turn that names no line is dropped");
  // Other words under an id already sent are refused on the phone (review of 3d837f0, finding 1), and
  // a receipt's words - the words posted - are what the line shows.
  const headNow = (await t.get(m.mailbox, 0, 256)).value.items.length;
  const edited = await throwsAsync(async () => a.phone.sendLine(a.paired.id, { text: "carry on, but slower", messageId: mid }));
  check(edited.indexOf("other words") >= 0 && (await t.get(m.mailbox, 0, 256)).value.items.length === headNow, "other words under a line id already sent are refused before anything is signed", edited);
  const tl = P.chatTimeline({ sent: [{ messageId: "f".repeat(32), text: "typed here", at: 1, session: "s" }], receipts: [{ messageId: "f".repeat(32), status: "accepted", code: "delivered", text: "posted words", session: "s", seq: 3, ts: 2 }] });
  check(tl.length === 1 && tl[0].text === "posted words", "a line shows the words its receipt says were posted, not what the phone kept", JSON.stringify(tl));
  // Through the bridge: the page's id for the words is the line's id, so a resend is the same line.
  const brp = createBridge(a.phone, { loadKinds: async () => ({}) });
  await brp.request("pick", { id: a.paired.id });
  const pageId = P.hex(P.randomBytes(16));
  const viaBridge = await brp.request("chat-send", { text: "via the bridge", id: pageId });
  const lastItems = (await t.get(m.mailbox, 0, 256)).value.items;
  const viaBody = (await machineOpens(m, lastItems[lastItems.length - 1].text)).body;
  check(viaBridge.ok === true && viaBridge.id === pageId && viaBody.messageId === pageId, "chat-send signs the line under the page's own id for the words", JSON.stringify(viaBridge));
  // Another phone of his (a reload) holds no sent lines: the receipt still shows his words.
  const b = createPhone({ store: a.store, authenticator: a.auth, relay: R.createRelayClient(t), origin });
  await b.unlock(a.paired.id);
  await b.refresh(a.paired.id);
  const cb = await b.chat(a.paired.id);
  check(cb.items.filter((x) => x.kind === "line" && x.text === "carry on").length === 1, "after a reload the line is shown from its receipt, with his words");
  // Once the relay has dropped the receipts, the founder turn alone still shows his line, delivered.
  const t2 = R.memoryTransport();
  const a2 = await pairedApp(t2, m);
  await sendChat(t2, m, a2.phoneKey, chatBody(m, "sess-1", [turn("u1", "assistant", "earlier"), turn("u2", "founder", "kept in history", { line: "e".repeat(32) })], { backfill: true }));
  await a2.phone.refresh(a2.paired.id);
  const only = (await a2.phone.chat(a2.paired.id)).items.filter((x) => x.kind === "line");
  check(only.length === 1 && only[0].text === "kept in history" && only[0].words === P.CHAT_WORDS.accepted.delivered, "with no receipt left, the machine's founder turn shows his line as delivered", JSON.stringify(only));
  // Read only: the recovery code reads the chat and never writes to it.
  b.lock(a.paired.id);
  await b.recover(a.paired.id, a.paired.recoveryCode);
  await b.refresh(a.paired.id);
  const headBefore = (await t.get(m.mailbox, 0, 256)).value.items.length;
  const viaCode = await throwsAsync(async () => b.sendLine(a.paired.id, { text: "from the recovery code", messageId: P.hex(P.randomBytes(16)) }));
  check(viaCode.indexOf("recovery code") >= 0 && (await t.get(m.mailbox, 0, 256)).value.items.length === headBefore && (await b.chat(a.paired.id)).items.length > 0, "unlocked by the recovery code, the chat is read and a line is refused in words, nothing put", viaCode);
  b.lock(a.paired.id);
  check((await throwsAsync(async () => b.chat(a.paired.id))).indexOf("locked") >= 0, "a locked horde shows no chat");
  const dump = JSON.stringify(await a.store.list(""));
  check(dump.indexOf("carry on") < 0 && dump.indexOf("long reply") < 0 && dump.indexOf("on it") < 0, "nothing of the chat is in the store");
}
{
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const a = await pairedApp(t, m, { prf: false });
  await sendChat(t, m, a.phoneKey, chatBody(m, "sess-1", [turn("t1", "assistant", "readable")], { backfill: true }));
  await a.phone.refresh(a.paired.id);
  check((await a.phone.chat(a.paired.id)).items.length === 1, "CONTROL: a passkey without PRF reads the chat");
  const before = (await t.get(m.mailbox, 0, 256)).value.items.length;
  const why = await throwsAsync(async () => a.phone.sendLine(a.paired.id, { text: "from a read-only phone", messageId: P.hex(P.randomBytes(16)) }));
  check(why.indexOf("gives no PRF") >= 0 && (await t.get(m.mailbox, 0, 256)).value.items.length === before, "and never writes to it: refused in words, nothing put", why);
  const br = createBridge(a.phone, { loadKinds: async () => ({}) });
  await br.request("pick", { id: a.paired.id });
  const rec = await br.request("chat");
  check(rec.state === "known" && rec.value.mode === "read-only" && rec.value.items.length === 1, "the bridge answers chat with the items and the mode the page shuts its composer by");
  const sent = await br.request("chat-send", { text: "no", id: "1".repeat(32) });
  check(sent.ok === false && sent.reason.indexOf("Read only") === 0, "and chat-send is refused in words");
}
{
  check(!P.readChatTurns(P.utf8(JSON.stringify({ v: 1, kind: "chat-turns", horde: "work", machine: "a".repeat(32), session: "s", backfill: false, turns: [] })), "work", "b".repeat(32)).ok, "a turns body of another machine is refused");
  const r = P.readChatTurns(P.utf8(JSON.stringify({ v: 1, kind: "chat-turns", horde: "work", machine: "a".repeat(32), session: "s", backfill: false, turns: [{ id: "x", role: "tool", session: "s", text: "t" }, { id: "y", role: "user", session: "s", text: "ok" }] })), "work", "a".repeat(32));
  check(r.ok && r.value.turns.length === 1 && r.value.dropped === 1, "a turn with a role off the list is dropped and counted");
  check((await throwsAsync(async () => P.lineBody({ messageId: "x", horde: "work", machine: "a".repeat(32), session: "s", text: "t" }))) !== "", "a line body with a bad message id is refused before anything is signed");
}

// --- 10c. when it was said: the turn's own time, the line's signed one, and never a guessed one ---
{
  const at = Date.parse("2026-10-12T21:30:09.000Z");
  // The zone is given as getTimezoneOffset gives it: minutes, positive west of UTC.
  check(P.clockTime(at, -180) === "00:30" && P.clockTime(at, 0) === "21:30" && P.clockTime(at, 270) === "17:00" && P.clockTime(Date.parse("2026-10-12T05:07:00Z"), 0) === "05:07", "a time is shown short, in the phone's own zone, 24-hour, two digits each", [P.clockTime(at, -180), P.clockTime(at, 0), P.clockTime(at, 270)].join(" "));
  check(P.dayKey(at, -180) === "2026-10-13" && P.dayKey(at, 0) === "2026-10-12" && P.dayLabel(at, -180) === "Tue 13 Oct 2026" && P.dayLabel(at, 0) === "Mon 12 Oct 2026" && P.dayLabel(Date.parse("2026-01-04T12:00:00Z"), 0) === "Sun 4 Jan 2026", "the day is the phone's local day: past midnight there, it is the next day", P.dayLabel(at, -180));
  check(P.exactTime(at, -180) === "Tue 13 Oct 2026, 00:30:09 (UTC+3)" && P.exactTime(at, 270) === "Mon 12 Oct 2026, 17:00:09 (UTC-4:30)" && P.exactTime(at, 0) === "Mon 12 Oct 2026, 21:30:09 (UTC)", "the exact time names the day, the second and the zone it is told in", P.exactTime(at, 270));
  check(P.clockTime(0, 0) === "" && P.clockTime(-5, 0) === "" && P.clockTime(undefined, 0) === "" && P.clockTime(1.5, 0) === "" && P.clockTime(8.7e15, 0) === "" && P.exactTime(0, 0) === "" && P.dayKey(0, 0) === "" && P.dayLabel(NaN, 0) === "" && P.localParts("2026", 0) === null, "what is not a time - none, zero, a fraction, past what a date holds - is shown as no time");
  check(P.clockTime(at) === P.clockTime(at, new Date(at).getTimezoneOffset()) && P.clockTime(at).length === 5, "with no zone given, the device's own");
  check(P.timeOf("2026-10-12T21:30:09.000Z") === at && P.timeOf("2026-10-13T00:30:09+03:00") === at && P.timeOf("2026-10-12T21:30:09") === 0 && P.timeOf("2026-10-12") === 0 && P.timeOf("yesterday") === 0 && P.timeOf("") === 0 && P.timeOf(at) === 0, "a turn's time is a time only with a zone: one without cannot be placed, and is none");
  const days = P.withDays([{ id: "a", said: 0 }, { id: "b", said: at - 3600000 }, { id: "c", said: at }, { id: "d", said: 0 }, { id: "e", said: at + 60000 }, { id: "f", said: at + 86400000 }], -180);
  check(days.map((x) => (x.kind === "day" ? "[" + x.label + "]" : x.id)).join(" ") === "a [Mon 12 Oct 2026] b [Tue 13 Oct 2026] c d e [Wed 14 Oct 2026] f", "the day is named once where it changes, and a thing with no time neither gets a divider nor moves one", days.map((x) => (x.kind === "day" ? "[" + x.label + "]" : x.id)).join(" "));
  // The timeline: each item's said.
  const T = (id, role, time, extra = {}) => ({ id, role, session: "s", text: id, time, group: "", part: 0, parts: 0, truncated: false, redactions: 0, line: "", seq: 1, ...extra });
  const tl = P.chatTimeline({ turns: [T("t1", "assistant", "2026-10-12T21:30:09.000Z"), T("t2", "user", ""), T("t3", "assistant", "2026-10-12T21:31:00")] });
  check(tl.find((x) => x.id === "t1").said === at && tl.find((x) => x.id === "t1").saidHow === "turn", "a turn says when it was said: its own time from the conversation");
  check(tl.find((x) => x.id === "t2").said === 0 && tl.find((x) => x.id === "t3").said === 0, "a turn that carries no time, or one with no zone, says none: no stamp, never a guessed one");
  const L = "a".repeat(32), M = "b".repeat(32), N = "c".repeat(32), O = "d".repeat(32);
  const lines = P.chatTimeline({
    sent: [{ messageId: L, text: "mine", at: at + 5, session: "s" }],
    receipts: [
      { messageId: L, status: "accepted", code: "queued", text: "mine", session: "s", seq: 2, ts: at + 9000, sentAt: 0 },
      { messageId: M, status: "accepted", code: "queued", text: "after a reload", session: "s", seq: 3, ts: at + 9000, sentAt: at + 7 },
      { messageId: N, status: "accepted", code: "queued", text: "from an old machine", session: "s", seq: 4, ts: at + 9000, sentAt: 0 },
      { messageId: O, status: "accepted", code: "delivered", text: "old machine, then delivered", session: "s", seq: 5, ts: at + 9000, sentAt: 0 }
    ],
    turns: [T("f1", "founder", "2026-10-12T21:40:00.000Z", { line: O }), T("f2", "founder", "2026-10-12T21:41:00.000Z", { line: "e".repeat(32) }), T("f3", "founder", "2026-10-12T21:42:00.000Z", { line: M })]
  });
  const lineOf = (id) => lines.find((x) => x.kind === "line" && x.messageId === id);
  check(lineOf(L).said === at + 5 && lineOf(L).saidHow === "sent", "a line this phone sent keeps the time it signed, whatever its receipt carries");
  check(lineOf(M).said === at + 7 && lineOf(M).saidHow === "sent" && lineOf(M).at === at + 7, "after a reload a line says when he sent it from its receipt's signed time - and the machine's founder turn does not replace it", JSON.stringify(lineOf(M)));
  check(lineOf(N).said === 0 && lineOf(N).at === at + 9000, "a receipt from a machine that sends no signed time gives the line NO time: the receipt's own envelope time orders it and is never shown as when he said it", JSON.stringify(lineOf(N)));
  check(lineOf(O).said === Date.parse("2026-10-12T21:40:00.000Z") && lineOf(O).saidHow === "delivered" && lineOf("e".repeat(32)).saidHow === "delivered" && lineOf("e".repeat(32)).said === Date.parse("2026-10-12T21:41:00.000Z"), "with no signed time left, the line says when it reached the Thrall - the founder turn's own time - and that this is what it is", JSON.stringify(lineOf(O)));
  const m = await newMachine("work");
  const withTime = P.readChatReceipt(P.utf8(JSON.stringify({ v: 1, kind: "chat-receipt", horde: "work", machine: m.keyId, session: "s", messageId: L, status: "accepted", code: "queued", sentAt: at, text: "t" })), "work", m.keyId);
  const bad = ["soon", -1, 1.5, null, 0].map((v) => P.readChatReceipt(P.utf8(JSON.stringify({ v: 1, kind: "chat-receipt", horde: "work", machine: m.keyId, session: "s", messageId: L, status: "accepted", code: "queued", sentAt: v, text: "t" })), "work", m.keyId));
  const none = P.readChatReceipt(receiptBody(m, "s", L, "accepted", "queued", "t"), "work", m.keyId);
  check(withTime.ok && withTime.value.sentAt === at && none.ok && none.value.sentAt === 0 && bad.every((r) => r.ok && r.value.sentAt === 0), "a receipt's sentAt is read as a whole number of milliseconds; one with none (an older machine), or with something else in its place, is still read, with no time");
}

// --- 10d. the progress log: in the order written, each once, corrections on what they correct, his place kept ---
const entriesBody = (m, entries, { backfill = false } = {}) => P.utf8(JSON.stringify({ v: 1, kind: "progress-entries", horde: m.horde, machine: m.keyId, backfill, entries }));
const noticeBody = (m, code, count = 0) => P.utf8(JSON.stringify({ v: 1, kind: "progress-notice", horde: m.horde, machine: m.keyId, code, count }));
async function sendProgress(t, m, phone, body, kind = "entries") { const e = await machineEnvelope(m, { kind, channel: "progress", body, phones: [phone] }); await t.put(m.horde + "/phone", e.key, e.text); return e; }
const entry = (id, n, extra = {}) => ({ id, n, ts: "2026-10-12T18:15:00.000Z", kind: "progress", title: "title " + id, text: "Happened: " + id, ...extra });
{
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const a = await pairedApp(t, m);
  await sendSnapshot(t, m, [a.phoneKey], [question(1, "One?")]);
  await sendChat(t, m, a.phoneKey, chatBody(m, "sess-1", [turn("t1", "assistant", "a turn")], { backfill: true }));
  await a.phone.refresh(a.paired.id);
  const none = await a.phone.progress(a.paired.id);
  check(none.items.length === 0 && none.unread === 0 && none.readIndex === -1 && none.newest === null && none.stopped === false && none.skipped === 0, "CONTROL: a new app with no progress yet shows an empty log, nothing unread, no place", JSON.stringify(none));
  const mailBefore = (await t.get(m.mailbox, 0, 256)).value.items.length;
  // Two envelopes: the live one arrives before the backfill, and line 3 happened before line 2.
  const four = "Asked: fix the ruled line.\nHappened: PR 1605 merged.\nMeans: text no longer touches ink.\nNext: the box path.";
  await sendProgress(t, m, a.phoneKey, entriesBody(m, [entry("e4", 4, { kind: "merged", area: "Form fill", lane: "F", task: "T-0096", title: "Ruled-line fix merged", text: four }), entry("e5", 5, { kind: "celebration", text: "no label here\nNext: rest" })]));
  await sendProgress(t, m, a.phoneKey, entriesBody(m, [entry("e2", 2, { ts: "2026-10-12T12:00:00.000Z" }), entry("e3", 3, { ts: "2026-10-12T08:00:00.000Z" }), entry("e4", 4, { title: "the same id, sent again with other words" })], { backfill: true }));
  const first = await a.phone.refresh(a.paired.id);
  let g = await a.phone.progress(a.paired.id);
  check(g.items.map((x) => x.id).join(",") === "e2,e3,e4,e5", "the entries are shown oldest to newest in the order they were WRITTEN - not the order they arrived, and not by their times (e3 happened before e2)", g.items.map((x) => x.id).join(","));
  const e4 = g.items.find((x) => x.id === "e4");
  check(g.items.filter((x) => x.id === "e4").length === 1 && e4.title === "Ruled-line fix merged", "an entry that reaches the phone twice - a backfill beside a live batch - is shown once, and the first that came stands");
  check(e4.said === Date.parse("2026-10-12T18:15:00.000Z") && e4.kind === "merged" && e4.kindWord === "Merged" && e4.area === "Form fill" && e4.lane === "F" && e4.task === "T-0096", "an entry carries its time, its kind in the phone's own word, and its area, lane and task", JSON.stringify(e4));
  check(JSON.stringify(e4.paragraphs) === JSON.stringify([{ label: "Asked", text: "fix the ruled line." }, { label: "Happened", text: "PR 1605 merged." }, { label: "Means", text: "text no longer touches ink." }, { label: "Next", text: "the box path." }]), "its text is four short paragraphs, each with its label", JSON.stringify(e4.paragraphs));
  const e5 = g.items.find((x) => x.id === "e5");
  check(e5.kind === "note" && e5.kindWord === "Note" && JSON.stringify(e5.paragraphs) === JSON.stringify([{ label: "", text: "no label here" }, { label: "Next", text: "rest" }]) && e5.area === "" && e5.lane === "", "a kind this phone does not know is a note - the entry is still shown - and a line with no known label is plain words", JSON.stringify(e5));
  check(first.questions.length === 1 && first.anomalies.length === 0 && (await a.phone.chat(a.paired.id)).items.length === 1, "the questions and the chat beside it are as they were: progress envelopes disturb neither, and are no anomaly", JSON.stringify(first.anomalies));
  // An envelope of a channel this app does not know (a later one) is passed over without a word.
  const later = await machineEnvelope(m, { kind: "thing", channel: "future", body: P.utf8("{}"), phones: [a.phoneKey] });
  await t.put("work/phone", later.key, later.text);
  const withLater = await a.phone.refresh(a.paired.id);
  check(withLater.anomalies.length === 0 && withLater.questions.length === 1 && (await a.phone.progress(a.paired.id)).items.length === 4, "an envelope on a channel the app does not know is passed over safely: no anomaly, nothing drawn, nothing lost - as an app from before the progress channel passes over progress", JSON.stringify(withLater.anomalies));
  // Entries that do not hold together are dropped and counted; a body of another machine is refused.
  await sendProgress(t, m, a.phoneKey, entriesBody(m, [
    entry("bad id", 6), entry("b2", 0), entry("b3", 6, { ts: "2026-10-12T18:15:00" }), entry("b4", 6, { title: "t".repeat(101) }), entry("b5", 6, { text: "x".repeat(2001) }),
    entry("b6", 6, { corrects: "has space" }), entry("b7", 6, { title: "" }), { n: 6 }, null, entry("b8", 1.5), entry("ok6", 6, { area: 5, lane: "x".repeat(33) })]));
  const dropped = await a.phone.refresh(a.paired.id);
  g = await a.phone.progress(a.paired.id);
  check(g.items.map((x) => x.id).join(",") === "e2,e3,e4,e5,ok6" && dropped.anomalies.some((x) => x.indexOf("10 progress entries that do not hold together were left out") >= 0), "entries that do not hold together - a bad id, no line number, a time with no zone, a title or text too long, a bad corrects - are left out and counted, and the good one beside them is shown", JSON.stringify(dropped.anomalies));
  check(g.items.find((x) => x.id === "ok6").area === "" && g.items.find((x) => x.id === "ok6").lane === "", "a label that is not a short plain text is shown as no label");
  check(!P.readProgressEntries(entriesBody({ horde: "work", keyId: "b".repeat(32) }, []), "work", m.keyId).ok && !P.readProgressEntries(entriesBody({ horde: "personal", keyId: m.keyId }, []), "work", m.keyId).ok && !P.readProgressEntries(P.utf8("{"), "work", m.keyId).ok && !P.readProgressEntries(P.utf8(JSON.stringify({ v: 1, kind: "progress-entries", horde: "work", machine: m.keyId, backfill: false })), "work", m.keyId).ok, "an entries body of another machine or horde, or with no entries list, is refused");

  // Corrections: on the entry they correct, and in their own place.
  await sendProgress(t, m, a.phoneKey, entriesBody(m, [entry("c7", 7, { corrects: "e4", title: "Not merged yet", text: "Means: it is still open." }), entry("c8", 8, { corrects: "gone-from-this-phone" }), entry("c9", 9, { corrects: "c9" })]));
  await a.phone.refresh(a.paired.id);
  g = await a.phone.progress(a.paired.id);
  const fixed = g.items.find((x) => x.id === "e4"), c7 = g.items.find((x) => x.id === "c7");
  check(fixed.corrections.length === 1 && fixed.corrections[0].id === "c7" && fixed.corrections[0].title === "Not merged yet" && fixed.corrections[0].paragraphs[0].label === "Means", "a correction is shown on the entry it corrects, with its own title and words", JSON.stringify(fixed.corrections));
  check(g.items.map((x) => x.id).join(",") === "e2,e3,e4,e5,ok6,c7,c8,c9" && c7.corrects === "e4" && c7.correctsTitle === "Ruled-line fix merged", "and it keeps its own place in the log, naming what it corrects, so reading on from any point meets it");
  const c8 = g.items.find((x) => x.id === "c8"), c9 = g.items.find((x) => x.id === "c9");
  check(c8.correctsTitle === "" && c8.corrects === "gone-from-this-phone" && c9.corrections.length === 0 && c9.correctsTitle === "" && g.items.every((x) => x.id === "e4" || x.corrections.length === 0), "a correction of an entry this phone does not hold, or of itself, attaches to nothing");

  // His reading position: kept per device, forward only, guarded.
  check(g.unread === 8 && g.readIndex === -1, "before he has read anything, every entry is unread", JSON.stringify({ unread: g.unread, readIndex: g.readIndex }));
  let r = await a.phone.markProgressRead(a.paired.id, "e4");
  check(r.unread === 5 && r.readIndex === 2 && JSON.stringify((await a.store.get("horde/" + a.paired.id)).progressRead) === JSON.stringify({ id: "e4", n: 4 }), "reading as far as an entry is kept on the device as that entry's id and line number, and what comes after it is unread", JSON.stringify(r.unread));
  r = await a.phone.markProgressRead(a.paired.id, "e2");
  check(r.unread === 5 && r.readIndex === 2 && (await a.store.get("horde/" + a.paired.id)).progressRead.id === "e4", "the place only moves forward: an earlier entry seen again does not move it back");
  check((await throwsAsync(async () => a.phone.markProgressRead(a.paired.id, "never-sent"))).indexOf("not in the progress log") >= 0 && (await a.store.get("horde/" + a.paired.id)).progressRead.id === "e4", "and never to an entry the phone was not sent");
  // A reload: nothing of the log was stored, the mailbox is read again, and he is back at his place.
  const b = createPhone({ store: a.store, authenticator: a.auth, relay: R.createRelayClient(t), origin });
  check((await throwsAsync(async () => b.progress(a.paired.id))).indexOf("locked") >= 0, "a locked horde shows no progress");
  await b.unlock(a.paired.id);
  await b.refresh(a.paired.id);
  await sendProgress(t, m, a.phoneKey, entriesBody(m, [entry("e10", 10)]));
  await b.refresh(a.paired.id);
  const back = await b.progress(a.paired.id);
  check(back.readIndex === 2 && back.items[back.readIndex].id === "e4" && back.unread === 6 && back.newest.id === "e10", "after a reload the log opens at his place - the last entry he read - with the count of what is new since", JSON.stringify({ readIndex: back.readIndex, unread: back.unread }));
  const dump = JSON.stringify(await a.store.list(""));
  check(dump.indexOf("Ruled-line") < 0 && dump.indexOf("ruled line") < 0 && dump.indexOf("Not merged yet") < 0 && dump.indexOf("Form fill") < 0 && dump.indexOf('"progressRead":{"id":"e4","n":4}') >= 0, "the store holds his place - an id and a number - and no word of the log: like the chat, the log is kept in memory only");
  // The entry he read is no longer held (the relay kept less): his place is the last one written before it.
  const held = P.progressLog({ entries: [{ ...entry("x3", 3), at: 1, seq: 1 }, { ...entry("x6", 6), at: 1, seq: 1 }, { ...entry("x9", 9), at: 1, seq: 2 }], position: { id: "gone", n: 7 } });
  check(held.readIndex === 1 && held.unread === 1, "when the entry he read is no longer on the phone, his place is the last entry written at or before it - never the start, never the end", JSON.stringify({ readIndex: held.readIndex, unread: held.unread }));
  // A damaged record is no place, and is mended by the next read.
  for (const junk of [{ id: "e4" }, { id: "has space", n: 4 }, { id: "e4", n: 0 }, { id: "e4", n: "4" }, "e4", 7, null, []]) {
    await a.store.update("horde/" + a.paired.id, (x) => ({ ...x, progressRead: junk }));
    const d = await b.progress(a.paired.id);
    if (d.readIndex !== -1 || d.unread !== d.items.length) check(false, "a damaged position record is no position", JSON.stringify(junk));
  }
  check(P.progressPosition({ id: "e4", n: 4 }) !== null && P.progressPosition({ id: "e4", n: 4, extra: 1 }).n === 4, "a position record that does not hold together is no position - everything is unread - and never a throw or a wrong place");
  r = await b.markProgressRead(a.paired.id);
  check(r.unread === 0 && r.readIndex === r.items.length - 1 && (await a.store.get("horde/" + a.paired.id)).progressRead.id === "e10", "mark all read moves his place to the newest entry");
  // Read only (the recovery code): the log is read and his place kept - nothing here is signed or sent.
  b.lock(a.paired.id);
  await b.recover(a.paired.id, a.paired.recoveryCode);
  await b.refresh(a.paired.id);
  await sendProgress(t, m, a.phoneKey, entriesBody(m, [entry("e11", 11)]));
  await b.refresh(a.paired.id);
  const ro = await b.markProgressRead(a.paired.id, "e11");
  check(ro.mode === "recovery" && ro.unread === 0 && ro.items.length === 10, "unlocked by the recovery code, the log is read and his place is kept: reading signs nothing");
  check((await t.get(m.mailbox, 0, 256)).value.items.length === mailBefore, "the phone sends nothing on the progress channel: the machine's mailbox is as it was");

  // Notices: codes only, in the phone's own words.
  await sendProgress(t, m, a.phoneKey, noticeBody(m, "lines-skipped", 2), "notice");
  await sendProgress(t, m, a.phoneKey, noticeBody(m, "file-replaced"), "notice");
  await sendProgress(t, m, a.phoneKey, noticeBody(m, "your-account-expired"), "notice");
  await sendProgress(t, m, a.phoneKey, noticeBody(m, "lines-skipped", 3), "notice");
  const noted = await b.refresh(a.paired.id);
  let n = await b.progress(a.paired.id);
  check(n.stopped === true && n.skipped === 5, "the machine's notices are read: it stopped following the log, and five lines were left out", JSON.stringify({ stopped: n.stopped, skipped: n.skipped }));
  check(noted.anomalies.some((x) => x.indexOf("code is not one this phone knows") >= 0) && Object.keys(P.PROGRESS_WORDS).sort().join(",") === "file-replaced,following,lines-skipped", "a notice with a code the phone does not know is not shown: no word of the machine's reaches the screen");
  await sendProgress(t, m, a.phoneKey, noticeBody(m, "following"), "notice");
  await b.refresh(a.paired.id);
  n = await b.progress(a.paired.id);
  check(n.stopped === false && n.skipped === 5, "a later word that the machine is following again takes the stop off the screen");

  // Through the bridge.
  const br = createBridge(b, { loadKinds: async () => ({}) });
  const events = [];
  br.on("progress-changed", (rec) => events.push(rec));
  await br.request("pick", { id: a.paired.id });
  const rec = await br.request("progress");
  check(rec.state === "known" && rec.value.items.length === 10 && rec.value.unread === 0 && events.length === 1 && events[0].state === "known", "the bridge answers progress with the log, and pushes progress-changed with every refresh");
  await sendProgress(t, m, a.phoneKey, entriesBody(m, [entry("e12", 12), entry("e13", 13)]));
  await br.request("refresh");
  const one = await br.request("progress-read", { id: "e12" });
  const off = await br.request("progress-read", { id: "nope" });
  const allRead = await br.request("progress-read", { all: true });
  check(events[events.length - 1].value.unread === 2 && one.state === "known" && one.value.unread === 1 && off.state === "unknown" && off.reason.indexOf("not in the progress log") >= 0 && allRead.value.unread === 0, "progress-read moves his place to an entry, refuses one the phone does not hold in words, and with all moves it to the newest", JSON.stringify({ one: one.value && one.value.unread, off: off.reason }));
  const missing = await br.request("progress-read", {});
  check(missing.state === "unknown", "progress-read with neither an entry nor all marks nothing read");
  await br.request("lock", { id: a.paired.id });
  const lockedRec = await br.request("progress");
  check(lockedRec.state === "unknown" && lockedRec.reason.indexOf("locked") >= 0, "a locked horde's progress is unknown, with the reason");
}
{
  const at = Date.parse("2026-10-12T21:30:09.000Z");
  check(P.dayTime(at, -180) === "13 Oct 00:30" && P.dayTime(at, 0) === "12 Oct 21:30" && P.dayTime(0, 0) === "", "an entry's time is shown with its day (entries are not in the order of their times), in the phone's own zone", P.dayTime(at, -180));
  check(JSON.stringify(P.progressParagraphs("Asked: a\n\nNext:b\nAsked later: c\nUnknown: d\n: e\n  \nMeans: ")) === JSON.stringify([{ label: "Asked", text: "a" }, { label: "Next", text: "b" }, { label: "", text: "Asked later: c" }, { label: "", text: "Unknown: d" }, { label: "", text: ": e" }, { label: "Means", text: "" }]), "a text's lines are its paragraphs: a known label and a colon open a labelled one, anything else is the line as it stands, and an empty line is none", JSON.stringify(P.progressParagraphs("Asked: a\n\nNext:b\nAsked later: c\nUnknown: d\n: e\n  \nMeans: ")));
  check(Object.keys(P.PROGRESS_KINDS).join(",") === "decision,result,merged,blocked,waiting,started,progress,done,note", "the kinds the phone has a word for are the nine the log is written with");
  const m = { horde: "work", keyId: "a".repeat(32) };
  const k = P.readProgressEntries(entriesBody(m, [entry("p1", 1, { kind: "__proto__" }), entry("p2", 2, { kind: "toString" })]), "work", m.keyId);
  check(k.ok && k.value.entries.length === 2 && k.value.entries.every((e) => e.kind === "note"), "a kind that is the name of something every object has is still not a kind: a note");
  const same = P.progressLog({ entries: [{ ...entry("a", 5), at: 1, seq: 9 }, { ...entry("b", 5), at: 1, seq: 3 }, { ...entry("a", 5, { title: "earlier envelope" }), at: 1, seq: 2 }] });
  check(same.items.map((x) => x.id + ":" + x.title).join(",") === "a:earlier envelope,b:title b", "of two envelopes carrying one id the earlier stands, and entries of one line number keep their envelopes' order", same.items.map((x) => x.id + ":" + x.title).join(","));
}

// --- 10b. the hosted relay's transport speaks its mailbox API, and distrusts it like any other ---
{
  const calls = [];
  const replies = [];
  const fakeFetch = async (address, init) => {
    calls.push({ address, init });
    const r = replies.shift() || { status: 200, body: {} };
    return { status: r.status, json: async () => { if (r.body === undefined) throw new Error("not JSON"); return r.body; } };
  };
  const sockets = [];
  class FakeSocket { constructor(address) { this.address = address; this.closed = false; sockets.push(this); } close() { this.closed = true; } }
  const t = R.httpTransport("https://relay.example.test", fakeFetch, FakeSocket);
  replies.push({ status: 200, body: { seq: 7, duplicate: false } });
  const p = await t.put("work/phone", "k-1", "a \"quoted\" text");
  const c0 = calls[0];
  check(p.state === "known" && p.value.seq === 7 && c0.address === "https://relay.example.test/v1/mailboxes/work/phone/items" && c0.init.method === "POST" && JSON.parse(c0.init.body).text === "a \"quoted\" text" && JSON.parse(c0.init.body).key === "k-1", "a put is a POST of { key, text } to the mailbox's items", JSON.stringify(c0));
  check(c0.init.credentials === "same-origin" && c0.init.cache === "no-store" && c0.init.redirect === "error", "with the page's own credentials, never from a cache, and never followed elsewhere", JSON.stringify(c0.init));
  replies.push({ status: 200, body: { items: [{ seq: 1, key: "a", text: "one" }] } });
  const g = await t.get("work/phone", 0, 5);
  check(g.state === "known" && g.value.items.length === 1 && calls[1].address === "https://relay.example.test/v1/mailboxes/work/phone/items?since=0&max=5" && calls[1].init.method === "GET", "a read is a GET of the items after the cursor", calls[1].address);
  replies.push({ status: 401, body: { error: "x".repeat(500) } });
  const no = await t.get("work/phone", 0, 5);
  check(no.state === "unknown" && no.reason.indexOf("401") >= 0 && no.reason.length < 300, "a refusal is unknown, with its status and the relay's words cut short", no.reason);
  replies.push({ status: 200, body: undefined });
  check((await t.get("work/phone", 0, 5)).state === "unknown", "an answer that is not JSON is unknown");
  replies.push({ status: 200, body: { through: 3 } });
  const k = await t.ack("work/phone", 3);
  check(k.state === "known" && calls[calls.length - 1].address.endsWith("/v1/mailboxes/work/phone/ack") && JSON.parse(calls[calls.length - 1].init.body).through === 3, "an ack is a POST of { through } to the mailbox's ack");
  const w = t.watch("work/phone", 4, 9, 10000);
  const s0 = sockets[0];
  check(s0.address === "wss://relay.example.test/v1/mailboxes/work/phone/watch?since=4&max=9&timeoutMs=10000", "a watch opens a WebSocket on the mailbox's watch, at the same host", s0.address);
  s0.onmessage({ data: JSON.stringify({ items: [{ seq: 5, key: "e", text: "five" }] }) });
  const wv = await w;
  check(wv.state === "known" && wv.value.items[0].seq === 5 && s0.closed, "the relay's one message is the watch's answer, and the socket is closed");
  const quiet = await t.watch("work/phone", 4, 9, 30);
  check(quiet.state === "known" && quiet.value.items.length === 0 && sockets[1].closed, "a watch that hears nothing in its time answers no items and closes its socket");
  const broken = t.watch("work/phone", 4, 9, 10000);
  sockets[2].onerror();
  check((await broken).state === "unknown", "a watch whose socket fails is unknown");
  const ended = t.watch("work/phone", 4, 9, 10000);
  sockets[3].onmessage({ data: JSON.stringify({ error: "replaced by a newer watch of this device", code: "watch-replaced" }) });
  const ev = await ended;
  check(ev.state === "unknown" && ev.reason.indexOf("replaced") >= 0 && sockets[3].closed, "a watch the relay ends in its one message (replaced by a newer one) is a failed watch, never nothing come", JSON.stringify(ev));
  const shut = t.watch("work/phone", 4, 9, 10000);
  sockets[4].onclose({ code: 4001 });
  const sv = await shut;
  check(sv.state === "unknown" && sv.reason.indexOf("replaced") >= 0, "and so is one the relay closes with a code of its own, 4001", JSON.stringify(sv));
  const done = t.watch("work/phone", 4, 9, 10000);
  sockets[5].onclose({ code: 1000 });
  check((await done).state === "known", "CONTROL: a plain close is still nothing come");
  sockets.splice(3, 3);
  const before = calls.length;
  replies.push({ status: 200, body: { items: [] } });
  await t.watch("work/phone", 4, 9, 0);
  check(calls.length === before + 1 && sockets.length === 3 && calls[before].address.indexOf("/items?since=4&max=9") > 0, "a watch of 0 ms is a read, and opens no socket");
  const liar = R.createRelayClient(t);
  replies.push({ status: 200, body: { items: [{ seq: 2, key: "b", text: "two" }, { seq: 2, key: "b", text: "two" }, { seq: 1, key: "a", text: "caf" + String.fromCharCode(0xe9) }] } });
  const lied = await liar.get("work/phone", 0, 5);
  check(lied.state === "known" && lied.value.items.map((i) => i.seq).join(",") === "2" && lied.value.anomalies.length >= 2, "and the relay client distrusts what it answers as it distrusts any transport");
  const host = { location: { origin: "https://relay.example.test" }, fetch: fakeFetch, WebSocket: FakeSocket };
  check(R.transportFromConfig({ transport: "http", relayOrigin: "" }, host) !== null && R.transportFromConfig({ transport: "http", relayOrigin: "" }, {}) === null, "the config's http transport is the page's own origin, and none where the page has no fetch or WebSocket");
  replies.push({ status: 200, body: { items: [] } });
  await R.transportFromConfig({ transport: "http", relayOrigin: "" }, host).get("work/phone", 0, 1);
  check(calls[calls.length - 1].address === "https://relay.example.test/v1/mailboxes/work/phone/items?since=0&max=1", "with no relay origin it speaks to the page's own origin", calls[calls.length - 1].address);
}

// --- 10c. A HUNG REQUEST CANNOT FREEZE THE PHONE (the founder's phone heard nothing new from 02:36 on
// 2026-10-14: a fetch with no timeout that never settles inside the live refresh left the poll loop
// waiting for ever, and every later poll returned at once because one was "still running") ---
{
  // Every wait here is bounded, so the code before the fix FAILS these checks instead of hanging the suite.
  const within = (p, ms) => Promise.race([p, new Promise((r) => setTimeout(() => r("still waiting"), ms))]);
  const signals = [];
  // A fetch that never answers and never hears its abort: the worst a frozen request can do.
  const deaf = (address, init) => { signals.push(init && init.signal); return new Promise(() => {}); };
  class NoSocket { constructor() { throw new Error("no socket in this check"); } }
  const t = R.httpTransport("https://relay.example.test", deaf, NoSocket, { requestMs: 100 });
  const g = await within(t.get("work/phone", 0, 5), 2000);
  check(g !== "still waiting" && g.state === "unknown" && g.reason.indexOf("did not answer") >= 0, "A READ THE RELAY NEVER ANSWERS comes back unknown when its time is up, though the fetch never heard its abort", JSON.stringify(g));
  const p = await within(t.put("work/phone", "k-1", "text"), 2000);
  const k = await within(t.ack("work/phone", 3), 2000);
  const w0 = await within(t.watch("work/phone", 0, 5, 0), 2000);
  check([p, k, w0].every((x) => x !== "still waiting" && x.state === "unknown"), "and so does a put, an ack and a watch of 0 ms (a read): every request the transport makes by fetch", JSON.stringify([p, k, w0]));
  check(signals.length === 4 && signals.every((s) => s && s.aborted === true), "each of them handed fetch a signal, and aborted it, so a real browser lets the request go", String(signals.map((s) => s && s.aborted)));
  // A response whose headers came but whose body never ends is the same freeze, one step later.
  const tb = R.httpTransport("https://relay.example.test", async () => ({ status: 200, json: () => new Promise(() => {}) }), NoSocket, { requestMs: 100 });
  const gb = await within(tb.get("work/phone", 0, 5), 2000);
  check(gb !== "still waiting" && gb.state === "unknown", "a body that never ends is cut by the same time", JSON.stringify(gb));
  const seen = [];
  const prompt = async (address, init) => { seen.push(init.signal); return { status: 200, json: async () => ({ items: [] }) }; };
  const tp = R.httpTransport("https://relay.example.test", prompt, NoSocket, { requestMs: 100 });
  const ok = await tp.get("work/phone", 0, 5);
  await new Promise((r) => setTimeout(r, 250));
  check(ok.state === "known" && seen[0] && seen[0].aborted === false, "a read answered in time is known, and its timer goes with it: nothing is aborted after", JSON.stringify(ok));
  check(R.REQUEST_MS === 20000, "a request is given 20 s, under the 25 s a watch waits", String(R.REQUEST_MS));
  const td = R.httpTransport("https://relay.example.test", prompt, NoSocket);
  await td.get("work/phone", 0, 5);
  check(seen.length === 2 && seen[1] && typeof seen[1].aborted === "boolean", "and the transport a deployment makes (no time given) has the timeout too");

  // THROUGH THE LIVE REFRESH: the bridge's poll loop over the real relay client and phone. Reads go by
  // fetch through the http transport (the shipped path); the rest of the relay is a memory one.
  const mem = R.memoryTransport();
  let hang = false;
  let reads = 0;
  const fetchFn = async (address, init) => {
    reads++;
    if (hang) return new Promise(() => {});
    const u = new URL(address);
    const box = u.pathname.split("/").slice(3, 5).join("/");
    const r = await mem.get(box, Number(u.searchParams.get("since")), Number(u.searchParams.get("max")));
    return { status: 200, json: async () => r.value };
  };
  const ht = R.httpTransport("https://relay.example.test", fetchFn, NoSocket, { requestMs: 100 });
  const mixed = { put: mem.put, ack: mem.ack, watch: mem.watch, get: ht.get };
  const m = await newMachine("work");
  const a = await pairedApp(mixed, m);
  await sendSnapshot(mem, m, [a.phoneKey], [question(1, "One?")]);
  const notices = [];
  const br = createBridge(a.phone, { loadKinds: async () => ({}), waitMs: 50 });
  br.on("notice", (words) => notices.push(words));
  const picked = await within(br.request("pick", { id: a.paired.id }), 3000);
  check(picked !== "still waiting" && picked.state === "known" && reads >= 1, "CONTROL: with a relay that answers, the horde is picked and its list read through fetch", JSON.stringify(picked).slice(0, 200));
  await new Promise((r) => setTimeout(r, 400));
  const healthy = reads;
  check(healthy >= 3, "CONTROL: the live refresh polls again and again while the relay answers (" + healthy + " reads)");
  hang = true;
  const hungAt = reads;
  await new Promise((r) => setTimeout(r, 1500));
  check(reads >= hungAt + 3, "A READ THAT NEVER ANSWERS NO LONGER STOPS THE LIVE REFRESH: it is given up, and the next polls run (" + (reads - hungAt) + " reads after the relay froze)");
  // The error path: a refresh whose first read hangs says the relay could not be read, and returns.
  const r1 = await within(br.request("refresh"), 3000);
  check(r1 !== "still waiting" && notices.some((n) => n.indexOf("could not be read") >= 0), "and a refresh whose read never answers ends, saying the relay could not be read", JSON.stringify(notices.slice(-2)));
  hang = false;
  // A relay that could not be read is asked again after the loop's pause (5 s), not in a busy loop.
  const back = reads;
  for (let i = 0; i < 70 && reads < back + 3; i++) await new Promise((r) => setTimeout(r, 100));
  check(reads >= back + 3, "once the relay answers again the loop carries on reading (" + (reads - back) + " reads)");
  await br.request("lock", { id: a.paired.id });
}

// --- 11. the icons the build draws are whole PNGs ---
{
  const { inflateSync, crc32 } = await import("node:zlib");
  for (const n of [192, 512]) {
    const d = new Uint8Array(readFileSync(join(siteDir, "app/icon-" + n + ".png")));
    const view = new DataView(d.buffer, d.byteOffset, d.byteLength);
    let ok = P.hex(d.slice(0, 8)) === "89504e470d0a1a0a", i = 8, w = 0, raw = null;
    while (ok && i < d.length) {
      const len = view.getUint32(i), type = P.fromUtf8(d.slice(i + 4, i + 8)), body = d.slice(i + 8, i + 8 + len);
      if ((crc32(d.slice(i + 4, i + 8 + len)) >>> 0) !== view.getUint32(i + 8 + len)) ok = false;
      if (type === "IHDR") w = new DataView(body.buffer, body.byteOffset).getUint32(0);
      if (type === "IDAT") raw = inflateSync(body);
      i += 12 + len;
    }
    const rowLen = 1 + 3 * n;
    const centreOfBar = raw ? P.hex(raw.slice(Math.floor(n / 2) * rowLen + 1 + 3 * Math.floor(n / 2), Math.floor(n / 2) * rowLen + 4 + 3 * Math.floor(n / 2))) : "";
    check(ok && w === n && raw && raw.length === rowLen * n && P.hex(raw.slice(1, 4)) === "1f5fae" && centreOfBar === "ffffff", "app/icon-" + n + ".png is a whole PNG, every chunk's CRC right, " + n + " wide, blue with the white bar of the H at its centre");
  }
}

// --- the announcement the founder's first live use never sent (2026-10-11) ---
{
  // Whether the machine has answered this phone yet: false until a snapshot is drawn, so the app can offer
  // "Announce this phone" in the horde's own view, not only on the locked screen.
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const app = newApp(t);
  const paired = await app.phone.pair({ offerText: (await offerText(m)), label: "Founder phone" });
  const h0 = (await app.phone.hordes())[0];
  check(h0.announced === false && h0.heard === false, "a phone just paired is neither announced nor heard from", JSON.stringify(h0));
  await app.phone.announce(paired.id);
  const h1 = (await app.phone.hordes())[0];
  check(h1.announced === true && h1.heard === false, "announced, it is not heard from until the machine sends a snapshot", JSON.stringify(h1));
  const phoneKey = await phoneKeyOf(t, m);
  await app.phone.refresh(paired.id);
  check((await app.phone.hordes())[0].heard === false, "a refresh that finds no snapshot does not make it heard");
  await sendSnapshot(t, m, [phoneKey], [question(1, "One?")]);
  await app.phone.refresh(paired.id);
  check((await app.phone.hordes())[0].heard === true, "a snapshot drawn makes it heard, and the store keeps it");

  // A passkey that does not sign the announcement (cancelled, timed out): the founder is told so in the
  // phone's own words, the browser's error name kept and its message not; nothing is sent.
  const t2 = R.memoryTransport();
  const m2 = await newMachine("work");
  const base = softAuthenticator({ origin, prf: true });
  let refuse = true;
  const auth = { create: (a) => base.create(a), get: async (a) => { if (refuse) { const e = new Error("The operation either timed out or was not allowed. See: https://example.invalid/phish"); e.name = "NotAllowedError"; throw e; } return base.get(a); } };
  const app2 = newApp(t2, { authenticator: auth });
  const p2 = await app2.phone.pair({ offerText: (await offerText(m2)), label: "Founder phone" });
  let err = null;
  try { await app2.phone.announce(p2.id); } catch (e) { err = e; }
  const words = err ? err.message : "";
  check(err !== null && err.code === "passkey" && words.indexOf("did not sign") >= 0 && words.indexOf("NotAllowedError") >= 0 && words.indexOf("example.invalid") < 0, "a passkey that does not sign the announcement is said in the phone's words, with the browser's error name only", words);
  check((await t2.get(m2.mailbox, 0, 256)).value.items.length === 0 && (await app2.phone.hordes())[0].announced === false, "and nothing is sent, and the horde is still not announced");
  refuse = false;
  await app2.phone.announce(p2.id);
  check((await app2.phone.hordes())[0].announced === true && (await phoneKeyOf(t2, m2)) !== null, "announced again once the passkey signs, it goes");
}

// --- THE ANNOUNCEMENT IS NO BUTTON (the founder, 2026-10-14): one passkey prompt, on the unlock ---
{
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const base = softAuthenticator({ origin, prf: true });
  const asked = [];
  const auth = { create: (a) => base.create(a), get: async (a) => { asked.push(a.challenge); return base.get(a); } };
  const app = newApp(t, { authenticator: auth });
  const paired = await app.phone.pair({ offerText: (await offerText(m)), label: "Founder phone" });
  const e0 = await app.store.get("horde/" + paired.id);
  const want = await P.vouchChallenge("work", P.unb64u(e0.phonePublic));
  // Finish pairing: ONE assertion, over the vouch's own challenge, put as the phone vouch item.
  await app.phone.announce(paired.id);
  const items = (await t.get(m.mailbox, 0, 256)).value.items;
  check(asked.length === 1 && P.equalBytes(asked[0], want), "Finish pairing asks the passkey ONCE, over the vouch's challenge", String(asked.length));
  check(items.length === 1 && items[0].key === "vouch/" + e0.deviceKeyId + "/" + e0.phoneKeyId, "and puts one item, under one key per passkey and phone key", JSON.stringify(items.map((i) => i.key)));
  const v = JSON.parse(items[0].text);
  check(items[0].text === P.phoneVouchText({ horde: "work", by: e0.deviceKeyId, agreePublic: P.unb64u(e0.phonePublic), vouch: { authenticatorData: P.unb64u(v.authenticatorData), clientDataJSON: P.unb64u(v.clientDataJSON), signature: P.unb64u(v.signature) } }) &&
    Object.keys(v).join(",") === "v,kind,horde,by,agreePublic,authenticatorData,clientDataJSON,signature", "the item is the vouch in relay/Trust.ps1's canonical form, the members in its order", Object.keys(v).join(","));
  const cd = JSON.parse(P.fromUtf8(P.unb64u(v.clientDataJSON)));
  check(cd.challenge === P.b64u(want) && v.signature.length > 0, "SIGNED: its clientDataJSON carries the vouch challenge, and it has a signature");

  // The unlock while the machine has not answered (not heard): ONE prompt that unlocks AND vouches.
  const t2 = R.memoryTransport();
  const m2 = await newMachine("work");
  const asked2 = [];
  const base2 = softAuthenticator({ origin, prf: true });
  const app2 = newApp(t2, { authenticator: { create: (a) => base2.create(a), get: async (a) => { asked2.push(a); return base2.get(a); } } });
  const p2 = await app2.phone.pair({ offerText: (await offerText(m2)), label: "Founder phone" });
  const e2 = await app2.store.get("horde/" + p2.id);
  app2.phone.lock(p2.id);
  check(e2.wraps.prf !== undefined, "CONTROL: a passkey that gives PRF at creation wraps the key under it at once");
  const u = await app2.phone.unlock(p2.id);
  const items2 = (await t2.get(m2.mailbox, 0, 256)).value.items;
  check(asked2.length === 1 && asked2[0].prfInput && P.equalBytes(asked2[0].challenge, await P.vouchChallenge("work", P.unb64u(e2.phonePublic))), "NOT HEARD, the unlock is one prompt, with PRF, over the vouch's challenge", String(asked2.length));
  check(u.unlocked && u.announced && items2.length === 1 && items2[0].text.startsWith('{"v":1,"kind":"horde-relay-phone-vouch",'), "and that one prompt unlocks and puts the vouch", JSON.stringify(u));
  // Not confirmed at the machine: nothing comes back; the phone does nothing more by itself.
  await app2.phone.refresh(p2.id);
  check(asked2.length === 1 && (await t2.get(m2.mailbox, 0, 256)).value.items.length === 1, "a refresh asks no passkey and puts nothing: the next try is the next unlock, never a loop");
  app2.phone.lock(p2.id);
  await app2.phone.unlock(p2.id);
  check(asked2.length === 2 && (await t2.get(m2.mailbox, 0, 256)).value.items.length === 1, "the next unlock tries again - one prompt - and the same key stores once", String((await t2.get(m2.mailbox, 0, 256)).value.items.length));
  // Heard: a snapshot drawn, an unlock puts nothing and asks over a challenge of its own.
  await sendSnapshot(t2, m2, [P.unb64u(e2.phonePublic)], [question(1, "One?")]);
  await app2.phone.refresh(p2.id);
  app2.phone.lock(p2.id);
  const head = (await t2.get(m2.mailbox, 0, 256)).value.items.length;
  await app2.phone.unlock(p2.id);
  check(asked2.length === 3 && !P.equalBytes(asked2[2].challenge, await P.vouchChallenge("work", P.unb64u(e2.phonePublic))) && (await t2.get(m2.mailbox, 0, 256)).value.items.length === head, "HEARD, an unlock is one prompt and puts no vouch");
  // A relay that refuses the put: the unlock still stands, and what it said is diagnostics only.
  const t3 = R.memoryTransport();
  const m3 = await newMachine("work");
  const app3 = newApp(t3);
  const p3 = await app3.phone.pair({ offerText: (await offerText(m3)), label: "Founder phone" });
  app3.phone.lock(p3.id);
  const refusing = { ...t3, put: async () => ({ state: "unknown", value: null, reason: "down" }) };
  const b3 = createPhone({ store: app3.store, authenticator: app3.auth, relay: R.createRelayClient(refusing), origin });
  const u3 = await b3.unlock(p3.id);
  check(u3.unlocked && !u3.announced, "a vouch the relay does not take leaves the unlock standing, the horde not announced", JSON.stringify(u3));
  // A recovery session never announces.
  const app4 = newApp(R.memoryTransport());
  const m4 = await newMachine("work");
  const p4 = await app4.phone.pair({ offerText: (await offerText(m4)), label: "Founder phone" });
  app4.phone.lock(p4.id);
  await app4.phone.recover(p4.id, p4.recoveryCode);
  check((await throwsAsync(async () => app4.phone.announce(p4.id))).indexOf("reads only") >= 0, "a recovery session cannot announce");
}

// --- ADD THIS PHONE: the new phone's request, and the machine's sealed answer ---
{
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const app = newApp(t);
  const j = await app.phone.join({ horde: "work", machine: m.keyId, label: "Pixel 9", agent: "Safari \"on\" iPhone" });
  const items = (await t.get(m.mailbox, 0, 16)).value.items;
  const q = items.length === 1 ? JSON.parse(items[0].text) : {};
  check(items.length === 1 && items[0].key === "join/" + j.request && Object.keys(q).join(",") === "v,kind,request,horde,machine,label,agent,requestKey,country,requestedAt,expiresAt", "a request to join is one item in the machine's mailbox under join/<request>, its members in relay/Join.ps1's order", items.length ? items[0].key : "");
  check(q.agent === "Safari on iPhone" && q.label === "Pixel 9" && /^[A-Za-z0-9_-]{87}$/.test(q.requestKey) && q.expiresAt - q.requestedAt === 600000, "its browser words lose quotes; it carries a request key and lives 10 minutes", items.length ? items[0].text : "");
  check((await app.phone.joinOffer(j.request)).offerText === "", "before the machine answers there is no offer");
  // The machine's answer, as relay/Join.ps1 seals it: the offer's text to the request key.
  const oText = (await offerText(m));
  const reqPoint = P.unb64u(q.requestKey);
  const kid = await P.keyId(reqPoint);
  const seal = async (to, request) => { const box = await P.hpkeSeal(to, P.utf8("horde-relay/join/v1 offer-key"), P.utf8("horde-relay/join/v1 offer aad\nwork\n" + request + "\n" + kid), P.utf8(oText)); return '{"v":1,"kind":"horde-relay-join-offer","request":"' + request + '","requestKeyId":"' + kid + '","enc":"' + P.b64u(box.enc) + '","ct":"' + P.b64u(box.sealed) + '"}'; };
  const other = await newMachine("work");
  await t.put("work/jr-" + j.request, "offer/x", await seal(other.agreePublic, j.request));
  check((await app.phone.joinOffer(j.request)).offerText === "", "an answer sealed to another key does not open");
  // A RELAY-MADE OFFER: sealed rightly to the request key, naming the machine asked, its grant signed by the
  // relay's own key - the relay cannot sign as the machine, so the phone does not believe it is the PC.
  const relayKey = await newMachine("work");
  const fid = P.hex(P.randomBytes(16));
  const fexp = Date.now() + 300000;
  const fgrant = P.b64u(await machineSign(relayKey, P.accountGrantBytes({ horde: "work", offer: fid, machine: m.keyId, expiresAt: fexp, label: "build-box" })));
  const fakeText = await offerText(m, { id: fid, expiresAt: fexp, grant: fgrant });
  const fbox = await P.hpkeSeal(reqPoint, P.utf8("horde-relay/join/v1 offer-key"), P.utf8("horde-relay/join/v1 offer aad\nwork\n" + j.request + "\n" + kid), P.utf8(fakeText));
  await t.put("work/jr-" + j.request, "offer/fake", '{"v":1,"kind":"horde-relay-join-offer","request":"' + j.request + '","requestKeyId":"' + kid + '","enc":"' + P.b64u(fbox.enc) + '","ct":"' + P.b64u(fbox.sealed) + '"}');
  check((await app.phone.joinOffer(j.request)).offerText === "", "A RELAY-MADE OFFER under the machine's name, its grant not the machine's, is refused: the phone does not believe it is the PC");
  await t.put("work/jr-" + j.request, "offer/" + j.request, await seal(reqPoint, j.request));
  const got = await app.phone.joinOffer(j.request);
  check(got.offerText === oText, "the machine's answer opens with the request key: the offer");
  const p = await app.phone.pair({ offerText: got.offerText, label: "Pixel 9", joined: true });
  check(/^[0-9]{4}-[0-9]{4}-[0-9]{4}$/.test(p.fingerprint), "and pairing with it shows the number, as a scanned offer does");
  // Another machine's offer, sealed rightly, is not the machine this phone asked.
  const t2 = R.memoryTransport();
  const app2 = newApp(t2);
  const j2 = await app2.phone.join({ horde: "work", machine: m.keyId, label: "Pixel 9" });
  const q2 = JSON.parse((await t2.get(m.mailbox, 0, 16)).value.items[0].text);
  const box = await P.hpkeSeal(P.unb64u(q2.requestKey), P.utf8("horde-relay/join/v1 offer-key"), P.utf8("horde-relay/join/v1 offer aad\nwork\n" + j2.request + "\n" + (await P.keyId(P.unb64u(q2.requestKey)))), P.utf8((await offerText(other))));
  await t2.put("work/jr-" + j2.request, "offer/" + j2.request, '{"v":1,"kind":"horde-relay-join-offer","request":"' + j2.request + '","requestKeyId":"' + (await P.keyId(P.unb64u(q2.requestKey))) + '","enc":"' + P.b64u(box.enc) + '","ct":"' + P.b64u(box.sealed) + '"}');
  check((await app2.phone.joinOffer(j2.request)).offerText === "", "an offer of another machine than the one asked is not taken");
}

// --- A NEW PHONE ASKS TO JOIN, on a trusted phone: the number compared here, only the hash signed ---
{
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const a = await pairedApp(t, m);
  const challenge = P.randomBytes(32);
  const cred = P.randomBytes(32);
  const pub = (await subtle.exportKey("raw", (await subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"])).publicKey));
  const request = P.hex(P.randomBytes(16));
  const device = P.hex(P.randomBytes(16));
  const nowMs = Date.now();
  const text = '{"v":1,"kind":"horde-relay-join-transcript","request":"' + request + '","horde":"work","machine":"' + m.keyId + '","offer":"' + P.hex(P.randomBytes(16)) + '","challenge":"' + P.b64u(challenge) +
    '","device":"' + device + '","credentialId":"' + P.b64u(cred) + '","publicKey":"' + P.b64u(new Uint8Array(pub)) + '","rpId":"relay.example.test","label":"Pixel 9","agent":"Safari on iPhone","country":"IL","requestedAt":' + nowMs + ',"expiresAt":' + (nowMs + 600000) + "}";
  const e = await machineEnvelope(m, { kind: "request", channel: "join", body: P.utf8(text), phones: [a.phoneKey] });
  await t.put(m.horde + "/phone", e.key, e.text);
  await a.phone.refresh(a.paired.id);
  const list = await a.phone.joinRequests(a.paired.id);
  check(list.length === 1 && list[0].label === "Pixel 9" && list[0].country === "IL" && JSON.stringify(list).indexOf("challenge") < 0, "the trusted phone lists the request - who, browser, country, time - and no means to the number", JSON.stringify(list));
  const number = await P.pairingFingerprint({ challenge, publicPoint: new Uint8Array(pub), credentialId: cred, rpId: "relay.example.test" });
  const head = (await t.get(m.mailbox, 0, 256)).value.items.length;
  const wrong = number === "0000-0000-0000" ? "1111-1111-1111" : "0000-0000-0000";
  const why = await throwsAsync(async () => a.phone.approveJoin(a.paired.id, { request, number: wrong }));
  check(why.indexOf("does not match") >= 0 && (await t.get(m.mailbox, 0, 256)).value.items.length === head, "A WRONG NUMBER is refused here: nothing is signed, nothing sent", why);
  await a.phone.approveJoin(a.paired.id, { request, number: number.replace(/-/g, " ") });
  const items = (await t.get(m.mailbox, 0, 256)).value.items;
  const ap = await machineOpens(m, items[items.length - 1].text);
  check(ap.header.channel === "join" && ap.header.kind === "approve" && ap.sig.alg === "webauthn.get", "the right number, spaced as typed, sends an approval on channel join, signed by the passkey");
  check(Object.keys(ap.body).join(",") === "v,request,device,transcript" && ap.body.request === request && ap.body.device === device && ap.body.transcript === P.b64u(await P.sha256(P.utf8("horde-relay/join/v1 transcript\n" + text))), "carrying only the request, the device and the transcript's hash", JSON.stringify(ap.body));
  check(JSON.stringify(ap.body).indexOf(number.replace(/-/g, "")) < 0, "never the number");
  await a.phone.rejectJoin(a.paired.id, { request });
  const rj = await machineOpens(m, (await t.get(m.mailbox, 0, 256)).value.items.slice(-1)[0].text);
  check(rj.header.kind === "reject" && Object.keys(rj.body).join(",") === "v,request", "a reject is signed the same way, naming only the request");
  const closed = await machineEnvelope(m, { kind: "closed", channel: "join", body: P.utf8('{"v":1,"request":"' + request + '","outcome":"rejected"}'), phones: [a.phoneKey] });
  await t.put(m.horde + "/phone", closed.key, closed.text);
  await a.phone.refresh(a.paired.id);
  check((await a.phone.joinRequests(a.paired.id)).length === 0, "once the machine says it ended, it is listed no more");
  a.phone.lock(a.paired.id);
  await a.phone.recover(a.paired.id, a.paired.recoveryCode);
  check((await throwsAsync(async () => a.phone.approveJoin(a.paired.id, { request, number }))).indexOf("recovery code") >= 0, "a recovery session approves nothing");
}

// --- the machine's confirmed record: the pairing screen's Finish pairing appears only on the machine's signed word ---
{
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const app = newApp(t);
  const oText = (await offerText(m));
  const paired = await app.phone.pair({ offerText: oText, label: "Founder phone" });
  const e = await app.store.get("horde/" + paired.id);
  const offer = JSON.parse(oText).offer;
  check(e.deviceId === P.hex((await P.sha256(P.unb64u(e.credentialId))).slice(0, 16)) && e.offer === offer && e.pairMailbox === "work/pair-" + offer, "the entry keeps the offer, its pairing mailbox and the device id the machine files the passkey under");
  check((await app.phone.pairConfirmed(paired.id)).confirmed === false, "before the machine's word, not confirmed");
  const record = async ({ signer = m, device = e.deviceId, forOffer = offer, at = Date.now() } = {}) => {
    const sig = new Uint8Array(await subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signer.sign.privateKey, P.confirmedBytes({ horde: "work", offer: forOffer, device, confirmedAt: at })));
    return '{"v":1,"kind":"horde-relay-pairing-confirmed","horde":"work","offer":"' + forOffer + '","device":"' + device + '","confirmedAt":' + at + ',"sig":"' + P.b64u(sig) + '"}';
  };
  const stranger = await newMachine("work");
  // WebCrypto's ECDSA may give a high-S signature, which the phone refuses (one message, one signature).
  const lowS = async (opts) => { for (let i = 0; i < 16; i++) { const r = await record(opts); const s = P.unb64u(JSON.parse(r).sig).slice(32); if (s[0] < 0x7f) return r; } return null; };
  await t.put("work/pair-" + offer, "confirmed/" + offer, await lowS({ signer: stranger }));
  check((await app.phone.pairConfirmed(paired.id)).confirmed === false, "a confirmed record signed by another key is not the machine's word");
  const t2 = R.memoryTransport();
  const b = createPhone({ store: app.store, authenticator: app.auth, relay: R.createRelayClient(t2), origin });
  await t2.put("work/pair-" + offer, "confirmed/" + offer, await lowS({ device: "0".repeat(32) }));
  check((await b.pairConfirmed(paired.id)).confirmed === false, "nor one naming another device");
  const t3 = R.memoryTransport();
  const c = createPhone({ store: app.store, authenticator: app.auth, relay: R.createRelayClient(t3), origin });
  await t3.put("work/pair-" + offer, "confirmed/" + offer, await lowS());
  check((await c.pairConfirmed(paired.id)).confirmed === true, "the machine's own signed word for this offer and device is");
}

// --- the phone's mailbox is trimmed by its senders: a hole there is not an anomaly ---
{
  // A machine deletes its own older snapshots from the mailbox once a newer one is whole there
  // (relays/Port.ps1, A SENDER TRIMS ITS OWN STREAM). trimmed is such a mailbox: the same relay, with
  // the items a machine trimmed no longer handed over.
  const t = R.memoryTransport();
  const gone = new Set();
  const after = async (r) => (r.state === "known" ? { ...r, value: { items: r.value.items.filter((i) => !gone.has(i.seq)) } } : r);
  const trimmed = { ...t, get: async (mb, since, max) => after(await t.get(mb, since, max)), watch: async (mb, since, max, ms) => after(await t.watch(mb, since, max, ms)) };
  const m = await newMachine("work");
  const a = await pairedApp(trimmed, m);
  await sendSnapshot(t, m, [a.phoneKey], [question(1, "First?")]);
  const one = await a.phone.refresh(a.paired.id);
  check(one.questions.length === 1 && one.questions[0].title === "First?" && one.anomalies.length === 0, "CONTROL: the first snapshot is read and drawn", JSON.stringify(one.anomalies));
  await sendSnapshot(t, m, [a.phoneKey], [question(1, "Second?")]);
  await sendSnapshot(t, m, [a.phoneKey], [question(1, "Third?")]);
  await sendSnapshot(t, m, [a.phoneKey], [question(1, "Fourth?")]);
  for (const seq of [1, 2, 3]) gone.add(seq);
  const client = await R.createRelayClient(trimmed).get("work/phone", 1, 256);
  check(client.value.items.map((i) => i.seq).join(",") === "4" && client.value.gaps.length === 1 && client.value.anomalies.length === 0, "CONTROL: the relay client hands over the one item left and reports the hole before it as a gap", JSON.stringify(client.value));
  const next = await a.phone.refresh(a.paired.id);
  check(next.questions.length === 1 && next.questions[0].title === "Fourth?", "a session that had read the first snapshot is shown the newest, across the hole the trimmed ones left");
  check(next.anomalies.length === 0, "and the hole is no anomaly: nothing about it reaches the screen", JSON.stringify(next.anomalies));
  const idle = await a.phone.refresh(a.paired.id);
  check(idle.questions[0].title === "Fourth?" && idle.anomalies.length === 0, "a refresh that finds nothing new does not take a trimmed mailbox for one whose numbering went backwards", JSON.stringify(idle.anomalies));
  const b = createPhone({ store: a.store, authenticator: a.auth, relay: R.createRelayClient(trimmed), origin });
  await b.unlock(a.paired.id);
  const fresh = await b.refresh(a.paired.id);
  check(fresh.questions.length === 1 && fresh.questions[0].title === "Fourth?" && fresh.anomalies.length === 0, "a new session reads a mailbox that begins past its first numbers, and is shown the newest with no anomaly", JSON.stringify(fresh.anomalies));
}

// --- a snapshot that leaves questions out says so, in the phone's own words ---
{
  // The machine's three reasons, as channels/decisions/Channel.ps1 writes them, and one it does not write.
  const follows = "it is in the snapshot that follows: this one page was sent first, to make room in the phone's full mailbox";
  const secret = "it holds what looks like a secret, so it is shown at the machine only";
  const large = "it is too large to send to the phone (51234 bytes; a page holds 47000), so it is shown at the machine only";
  check(P.withheldWords([]) === "" && P.withheldWords(undefined) === "" && P.withheldWords("x") === "", "nothing withheld is no line at all");
  check(P.withheldWords([{ number: 4, reason: follows }]) === "1 question is not shown here: it comes in the snapshot that follows.", "one question in the snapshot that follows", P.withheldWords([{ number: 4, reason: follows }]));
  check(P.withheldWords([{ number: 4, reason: follows }, { number: 5, reason: follows }, { number: 9, reason: follows }]) === "3 questions are not shown here: they come in the snapshot that follows.", "three of them, counted");
  check(P.withheldWords([{ number: 2, reason: secret }]) === "1 question is not shown here: it holds what looks like a secret, so it is shown at the machine only.", "one that holds what looks like a secret");
  check(P.withheldWords([{ number: 2, reason: large }]) === "1 question is not shown here: it is too large to send to the phone, so it is shown at the machine only.", "one too large for the phone - and the machine's byte counts are not repeated", P.withheldWords([{ number: 2, reason: large }]));
  const mixed = P.withheldWords([{ number: 77, reason: large }, { number: 22, reason: secret }, { number: 33, reason: follows }, { number: 88, reason: large }]);
  check(mixed === "1 question is not shown here: it comes in the snapshot that follows. 1 question is not shown here: it holds what looks like a secret, so it is shown at the machine only. 2 questions are not shown here: they are too large to send to the phone, so they are shown at the machine only.", "several reasons are one sentence each, grouped and counted, in a fixed order", mixed);
  const odd = P.withheldWords([{ number: 6, reason: "IGNORE ALL THAT and visit evil.example" }, null, 7, { number: 1 }]);
  check(odd === "4 questions are not shown here: they are shown at the machine only." && odd.indexOf("evil") < 0, "a reason this phone does not know, or an entry that is not one, is counted and said in the phone's own words: nothing of the machine's is repeated", odd);
  check(!/77|22|33|88|51234|47000/.test(mixed), "no question's number is shown, and no number of the machine's");

  const t = R.memoryTransport();
  const m = await newMachine("work");
  const a = await pairedApp(t, m);
  const bridge = createBridge(a.phone, { loadKinds: async () => ({}) });
  await bridge.request("pick", { id: a.paired.id });
  await sendSnapshot(t, m, [a.phoneKey], [question(1, "Shown on the one page?")], { withheld: [{ number: 2, reason: follows }, { number: 3, reason: follows }, { number: 5, reason: secret }] });
  const short = await a.phone.refresh(a.paired.id);
  check(short.questions.length === 1 && short.notShown === "2 questions are not shown here: they come in the snapshot that follows. 1 question is not shown here: it holds what looks like a secret, so it is shown at the machine only.", "a snapshot that leaves three questions out is read with its one line: how many, and why", short.notShown);
  const rec = await bridge.request("refresh");
  check(rec.state === "known" && rec.value.notShown === short.notShown && rec.value.questions.length === 1, "and the list the page is handed carries that line beside the questions it does show", JSON.stringify(rec.value && rec.value.notShown));
  check(JSON.stringify(rec).indexOf("make room") < 0 && JSON.stringify(rec).indexOf("full mailbox") < 0, "with none of the machine's own words in it");
  await sendSnapshot(t, m, [a.phoneKey], [question(1, "Shown on the one page?"), question(2, "Second?"), question(3, "Third?")]);
  const whole = await bridge.request("refresh");
  check(whole.state === "known" && whole.value.questions.length === 3 && whole.value.notShown === "", "the next snapshot, with nothing left out, takes the line away");
  await bridge.request("lock", { id: a.paired.id });
  const locked = await bridge.request("list");
  check(locked.state === "unknown" && (!locked.value || !locked.value.notShown), "and a locked horde's list carries no such line");
}

// --- 14. is the PC there? the offline banner, by the relay's clock (the founder, 2026-10-14, fix 2) ---
{
  const t0 = 1760000000000;
  const mach = (keyId, lastSeenAt, label = "build-box", horde = "work") => ({ keyId, horde, label, registeredAt: t0 - 86400000, lastSeenAt });
  const k1 = "1".repeat(32), k2 = "2".repeat(32), k3 = "3".repeat(32);
  const offline = (answer) => AC.presenceOf(answer).filter((m) => m.state === "offline");
  const at = (age) => ({ now: t0, machines: [mach(k1, t0 - age)] });
  check(AC.OFFLINE_AFTER_MS === 120000, "two minutes is the line");
  check(offline(at(121000)).length === 1 && offline(at(121000))[0].keyId === k1, "the banner appears after 120 s by the relay's clock");
  check(offline(at(119000)).length === 0 && AC.presenceOf(at(119000))[0].state === "online", "not before");
  check(offline(at(120000)).length === 0 && offline(at(120001)).length === 1, "and exactly 120 s is not yet over it: over means over");
  const realNow = Date.now;
  let skewed;
  try {
    Date.now = () => t0 + 3 * 86400000;
    skewed = [AC.presenceOf(at(30000))[0].state, AC.presenceOf(at(121000))[0].state];
    Date.now = () => t0 - 3 * 86400000;
    skewed.push(AC.presenceOf(at(30000))[0].state, AC.presenceOf(at(121000))[0].state);
  } finally { Date.now = realNow; }
  check(skewed.join(",") === "online,offline,online,offline", "a wrong phone clock, days fast or days slow, does not change it: only the relay's now and lastSeenAt count", skewed.join(","));
  check(AC.presenceOf({ now: t0, machines: [mach(k1, t0 - 2000)] })[0].state === "online" && offline({ now: t0 + 300000, machines: [mach(k1, t0 - 2000)] }).length === 1 && offline({ now: t0 + 301000, machines: [mach(k1, t0 + 300000)] }).length === 0, "it clears when heard again: the next answer with a fresh lastSeenAt has no banner");
  const many = AC.presenceOf({ now: t0, machines: [mach(k1, t0 - 600000, "build-box"), mach(k2, t0 - 5000, "laptop"), mach(k3, t0 - 900000, "", "personal")] });
  const off = many.filter((m) => m.state === "offline");
  check(off.length === 2 && off[0].name === "build-box (work)" && off[1].name === "machine " + k3.slice(0, 12) + " (personal)", "one banner per offline machine, by its name: its label and horde, or its key id's start when it has no label", JSON.stringify(off.map((m) => m.name)));
  const bare = AC.presenceOf({ now: t0, machines: [{ keyId: k1, label: "build-box", lastSeenAt: t0 - 600000 }, { keyId: k2, label: "", horde: "", lastSeenAt: t0 - 600000 }] });
  check(bare[0].name === "build-box" && bare[1].name === "machine " + k2.slice(0, 12), "a machine whose answer names no horde is named without one: never '(undefined)'", JSON.stringify(bare.map((m) => m.name)));
  const never = AC.presenceOf({ now: t0, machines: [mach(k1, null)] });
  check(never.length === 1 && never[0].state === "never" && never[0].lastSeenAt === null, "a never-seen machine gets no offline banner: it is 'never', quietly");
  check(AC.presenceOf({ now: t0, machines: [{ keyId: k1, horde: "work", label: "x" }] })[0].state === "never" && AC.presenceOf({ now: t0, machines: [mach(k1, 0)] })[0].state === "never", "and so is one whose answer carries no lastSeenAt at all (a relay from before this), or a zero");
  check(AC.presenceOf({ machines: [mach(k1, t0 - 600000)] }).length === 0 && AC.presenceOf({ now: "1760000000000", machines: [mach(k1, t0 - 600000)] }).length === 0 && AC.presenceOf(null).length === 0 && AC.presenceOf({ now: t0, machines: "x" }).length === 0, "an answer without the relay's own now as a whole number says nothing about anyone: no clock, no banner");
  const m = off[0];
  const words = AC.offlineWords(m, (ms) => "T" + ms);
  check(words === "PC build-box (work) offline since T" + m.lastSeenAt + ". Your answers are kept and will be applied when it is back.", "the banner says the PC's name, the time it was last heard in the phone's own local time, and that the answers are kept", words);
  check(!/lost|deleted|not sent|failed/i.test(words), "and nothing that says an answer is lost");
  check(AC.offlineWords(m, () => "T", { waiting: 3 }).endsWith(" 3 answers are waiting.") && AC.offlineWords(m, () => "T", { waiting: 1 }).endsWith(" 1 answer is waiting.") && AC.offlineWords(m, () => "T", { waiting: 0 }) === AC.offlineWords(m, () => "T"), "the hook for later: a count of answers waiting adds one sentence, and none adds nothing");
}

// --- 10e. the cards: one snapshot per machine, merged by machine name; a card's stream is its lane's part of the log ---
const cardsBody = (m, { name, made = "2026-10-13T20:00:00Z", cards = [], areas = [], thrall = {}, left = 0, areasLeft = undefined, hash = P.hex(P.randomBytes(32)) }) => P.utf8(JSON.stringify({ v: 1, kind: "cards-snapshot", horde: m.horde, machine: m.keyId, snapshot: hash, made, name,
  thrall: { asOf: "", now: "", hasStatus: false, orcs: cards.length, working: cards.length, waitingFounder: 0, blocked: 0, unknown: 0, waitingFounderLanes: [], census: null, refused: [], ...thrall }, cards, cardsLeftOut: left, areas, areasLeftOut: areasLeft }));
const card = (lane, extra = {}) => ({ lane, name: "lane " + lane, form: "standard", asOf: "2026-10-13T19:56:00Z", now: "doing " + lane, lastDone: "did " + lane, waitingOn: "nothing", blocked: "no", blockedText: "", note: "", tasksOpen: 3, doneWeek: 2, refused: [], ...extra });
async function sendCards(t, m, phone, body) { const e = await machineEnvelope(m, { kind: "snapshot", channel: "cards", body, phones: [phone] }); await t.put(m.horde + "/phone", e.key, e.text); return e; }
{
  const t = R.memoryTransport();
  const m1 = await newMachine("work");
  const m2 = await newMachine("work");
  const a = await pairedApp(t, m1);
  const p2 = await a.phone.pair({ offerText: (await offerText(m2, { label: "home-box" })), label: "Founder phone" });
  await a.phone.announce(p2.id);
  const k2 = await phoneKeyOf(t, m2);
  await a.phone.refresh(a.paired.id);
  const none = await a.phone.cards(a.paired.id);
  check(none.machines.length === 0 && none.cards.length === 0 && none.thrall.length === 0, "CONTROL: before any machine sends cards there are none, and the page falls back to the whole log", JSON.stringify(none));
  const areas = [{ area: "Form fill", lanes: ["C"] }, { area: "Horde", lanes: ["C", "E"] }];
  await sendCards(t, m1, a.phoneKey, cardsBody(m1, { name: "office-pc", cards: [card("E"), card("C", { blocked: "yes", blockedText: "waits for a device" })], areas, thrall: { waitingFounderLanes: ["B"] } }));
  await sendCards(t, m2, k2, cardsBody(m2, { name: "home-pc", cards: [card("G")], areas: [] }));
  const first = await a.phone.refresh(a.paired.id);
  let c = await a.phone.cards(a.paired.id);
  check(first.anomalies.length === 0 && c.machines.map((x) => x.name).join(",") === "home-pc,office-pc", "TWO MACHINES MERGED: one refresh of ONE pairing shows the cards of both machines of the horde, the other's opened by its own pairing", JSON.stringify({ an: first.anomalies, m: c.machines.map((x) => x.name) }));
  check(c.cards.map((x) => x.lane + "@" + x.machine).join(",") === "C@office-pc,E@office-pc,G@home-pc" && c.cards.find((x) => x.lane === "G").entry === p2.id && c.cards.find((x) => x.lane === "E").entry === a.paired.id, "each card names its machine and the pairing whose log its stream is, ordered by lane", JSON.stringify(c.cards.map((x) => [x.lane, x.machine, x.entry])));
  check(c.thrall.length === 2 && c.thrall.find((x) => x.machine === "office-pc").waitingFounderLanes.join(",") === "B", "there is a Thrall card per machine, with that machine's fleet");
  const cc = c.cards.find((x) => x.lane === "C");
  check(cc.blocked === "yes" && cc.blockedText === "waits for a device" && cc.tasksOpen === 3 && cc.doneWeek === 2 && cc.asOf === Date.parse("2026-10-13T19:56:00Z"), "a card carries blocked, its words, its task counts and the time its status was written", JSON.stringify(cc));
  // The same machine name from a newer snapshot of the other pairing replaces it; an older replay does not.
  await sendCards(t, m2, k2, cardsBody(m2, { name: "office-pc", made: "2026-10-13T21:00:00Z", cards: [card("H")] }));
  await a.phone.refresh(a.paired.id);
  c = await a.phone.cards(a.paired.id);
  check(c.machines.length === 1 && c.machines[0].name === "office-pc" && c.machines[0].entry === p2.id && c.cards.map((x) => x.lane).join(",") === "H", "MERGED BY NAME: two pairings that report one machine name show it once, the newest snapshot standing", JSON.stringify(c.machines));
  await sendCards(t, m2, k2, cardsBody(m2, { name: "home-pc", made: "2026-10-13T22:00:00Z", cards: [card("G")] }));
  const replay = await machineEnvelope(m1, { kind: "snapshot", channel: "cards", body: cardsBody(m1, { name: "office-pc", made: "2026-10-13T23:00:00Z", cards: [card("OLD")] }), phones: [a.phoneKey], seq: 1 });
  await t.put("work/phone", replay.key, replay.text);
  await a.phone.refresh(a.paired.id);
  c = await a.phone.cards(a.paired.id);
  check(c.cards.every((x) => x.lane !== "OLD"), "a cards envelope of a lower seq than one already held is never shown, whatever time it claims", JSON.stringify(c.cards.map((x) => x.lane)));
  // Streams: the progress log filtered by lane, with the map of its own machine.
  await sendProgress(t, m1, a.phoneKey, entriesBody(m1, [entry("s1", 1, { area: "Form fill" }), entry("s2", 2, { area: "Horde", lane: "E,F" }), entry("s3", 3, { area: "This PC" }), entry("s4", 4, { area: "Form fill", lane: "E" }), entry("s5", 5, { area: "HORDE " }), entry("s6", 6)]));
  await a.phone.refresh(a.paired.id);
  const g = await a.phone.progress(a.paired.id);
  check(JSON.stringify(g.areas) === JSON.stringify(areas), "the log comes with its machine's area-to-lane map", JSON.stringify(g.areas));
  const ids = (lane) => P.laneStream(g.items, lane, g.areas).map((x) => x.id).join(",");
  check(ids("E") === "s2,s4,s5" && ids("F") === "s2", "AN ENTRY TAGGED FOR TWO LANES shows under both (s2: E,F)", ids("E") + " / " + ids("F"));
  check(ids("C") === "s1,s5" && ids("E").indexOf("s1") < 0, "AN ENTRY'S OWN LANE WINS OVER ITS AREA: s4 is Form fill but names E, so it shows under E and not under C; and an area is matched with case and outer spaces aside (s5)", ids("C"));
  check(["B", "C", "E", "F", "G"].every((l) => ids(l).split(",").indexOf("s3") < 0 && ids(l).split(",").indexOf("s6") < 0) && ids("") === "s1,s2,s3,s4,s5,s6", "AN UNTAGGED, UNMAPPED ENTRY shows ONLY in the Thrall's stream, which is the whole log", ids(""));
  check(P.entryLanes({ lane: " E , F ", area: "Form fill" }, areas).join(",") === "E,F" && P.entryLanes({ lane: "", area: "" }, areas).length === 0 && P.entryLanes({ area: "Horde" }, []).length === 0, "a lane list is split on commas and trimmed; no lane and no area, or no map, is no lane");
  // The body, read strictly.
  const other = { horde: "work", keyId: "b".repeat(32) };
  check(!P.readCardsSnapshot(cardsBody(other, { name: "x" }), "work", m1.keyId).ok && !P.readCardsSnapshot(cardsBody({ horde: "personal", keyId: m1.keyId }, { name: "x" }), "work", m1.keyId).ok && !P.readCardsSnapshot(cardsBody(m1, { name: "" }), "work", m1.keyId).ok && !P.readCardsSnapshot(P.utf8("{"), "work", m1.keyId).ok, "a cards body of another machine or horde, with no machine name, or not JSON, is refused");
  const bad = P.readCardsSnapshot(cardsBody(m1, { name: "x", cards: [card("ok"), card("bad lane!"), card("Z", { form: "made-up" }), card("Y", { now: "a\u0007bell", tasksOpen: -1 })] }), "work", m1.keyId);
  check(bad.ok && bad.value.dropped === 2 && bad.value.cards.map((x) => x.lane).join(",") === "ok,Y" && bad.value.cards[1].now === "" && bad.value.cards[1].tasksOpen === null, "a card with a bad lane or form is dropped and counted; a text with a control character is shown as none, a count that is no count as not known", JSON.stringify(bad.value && bad.value.cards));
  check(P.CARD_FORM_WORDS.other.indexOf("not in the standard form") >= 0 && P.readCardsSnapshot(cardsBody(m1, { name: "x", cards: [card("Q", { form: "unreadable", note: "machine words" })] }), "work", m1.keyId).value.cards[0].note === P.CARD_FORM_WORDS.unreadable, "what a card says of its form is the phone's own sentence, never the machine's words");
  check(P.ageWords(Date.parse("2026-10-13T19:56:00Z"), Date.parse("2026-10-13T20:00:30Z")) === "4 min ago" && P.ageWords(1000, 1000 + 3 * 3600000) === "3 h ago" && P.ageWords(1000, 1000 + 72 * 3600000) === "3 days ago" && P.ageWords(0, 5) === "" && P.ageWords(5000, 1000) === "just now", "a card's age is said in plain words");
  check(P.STREAM_LIMIT_WORDS.indexOf("last 100") >= 0, "the stream page says how far back the phone's log goes");
  // Through the bridge: cards, and another machine's log by its pairing.
  const br = createBridge(a.phone, { loadKinds: async () => ({}) });
  const evs = [];
  br.on("cards-changed", (rec) => evs.push(rec));
  await br.request("pick", { id: a.paired.id });
  const rec = await br.request("cards");
  const of = await br.request("progress", { of: p2.id });
  check(rec.state === "known" && rec.value.machines.length === 2 && evs.length === 1 && evs[0].state === "known" && of.state === "known" && Array.isArray(of.value.items), "the bridge answers cards, pushes cards-changed with every refresh, and opens another pairing's log for that machine's card");
  // The machine is sent nothing on this channel.
  const before = (await t.get(m1.mailbox, 0, 256)).value.items.length;
  await a.phone.refresh(a.paired.id);
  check((await t.get(m1.mailbox, 0, 256)).value.items.length === before, "the phone sends nothing on the cards channel");
  // THE ONE CARD (lane-card.js): a pure render of a lane and one slot, the tap the page's.
  const fake = () => {
    // appendChild THROWS on what is not a node, as the page's does ("parameter 1 is not of type 'Node'"): a
    // stand-in that takes anything cannot see a badge handed in as a number (review of PR 244).
    const node = (tag) => ({ tag, className: "", textContent: "", type: "", attrs: {}, kids: [], on: {}, appendChild(k) { if (!k || typeof k !== "object" || typeof k.tag !== "string") throw new TypeError("parameter 1 is not of type 'Node'"); this.kids.push(k); return k; }, setAttribute(n, v) { this.attrs[n] = v; }, addEventListener(n, f) { this.on[n] = f; } });
    return { createElement: node, createTextNode: (t) => ({ tag: "#text", textContent: t, kids: [] }) };
  };
  const dump = (n, skipBadge) => (skipBadge && n.className === "card-badge") ? "<badge>" : n.tag + "." + (n.className || "") + "[" + (n.textContent || "") + "]" + (n.attrs && n.attrs["data-lane"] ? "@" + n.attrs["data-lane"] : "") + "(" + (n.kids || []).map((k) => dump(k, skipBadge)).join("") + ")";
  const lanesDoc = await a.phone.cards(a.paired.id);
  const nowMs = Date.parse("2026-10-13T20:00:00Z");
  const plain = LC.renderLaneCard(fake(), lanesDoc, "G", { nowMs });
  const doc = fake();
  const badge = doc.createElement("span"); badge.textContent = "2 open";
  let opened = null;
  const filled = LC.renderLaneCard(doc, lanesDoc, "G", { nowMs, badge, onOpen: (o) => { opened = o; } });
  const slotOf = (n) => n.kids[0].kids.find((k) => k.className === "card-badge");
  check(plain !== null && filled !== null && dump(plain, true) === dump(filled, true) && slotOf(plain).kids.length === 0 && slotOf(filled).kids[0] === badge, "A PAGE FILLS THE ONE SLOT: the card is the same with and without a badge, and the badge is in its slot", dump(filled, false));
  check(LC.renderLaneCard(fake(), lanesDoc, "G", { nowMs, badge: "3" }) !== null && slotOf(LC.renderLaneCard(fake(), lanesDoc, "G", { nowMs, badge: "3" })).textContent === "3", "a badge may be a short text");
  filled.on.click();
  check(opened && opened.lane === "G" && opened.machine === "home-pc" && opened.entry === p2.id && typeof plain.on.click === "undefined", "the tap does what the page passed in, told the lane, the machine and the pairing; with nothing passed in a tap does nothing", JSON.stringify(opened));
  const th = LC.renderLaneCard(fake(), lanesDoc, LC.THRALL_LANE, { machine: "home-pc", nowMs });
  check(LC.THRALL_LANE === "thrall" && th !== null && th.attrs["data-lane"] === "thrall" && th.className.indexOf("thrall") >= 0 && LC.renderLaneCard(fake(), lanesDoc, "NOPE", { nowMs }) === null, "the Thrall's card is lane thrall; a lane the document does not hold renders nothing");
  const view = LC.laneCardView(lanesDoc, "G", { nowMs });
  check(view.title === "G - lane G" && view.from === "home-pc, 4 min ago" && view.lines.map((l) => l.label).join(",") === "Now,Last done,Waiting on,Blocked" && view.stats === "Tasks open 3 - done this week 2", "the card's words: its lane and name, its machine and age, now, last done, waiting on, blocked and the task counts", JSON.stringify(view));
  // Review of PR 244, the round's additions.
  check((() => { try { fake().createElement("b").appendChild(3); return false; } catch (x) { return true; } })(), "CONTROL: the stand-in document refuses a number where a node goes, as a browser does");
  const badgeOf = (b) => { try { const box = LC.renderLaneCard(fake(), lanesDoc, "G", { nowMs, badge: b }); return slotOf(box).textContent + "/" + slotOf(box).kids.length; } catch (x) { return "threw: " + x.message; } };
  check(badgeOf(3) === "3/0" && badgeOf(0) === "0/0" && badgeOf(null) === "/0" && badgeOf("") === "/0", "A BADGE THAT IS A NUMBER is shown as its digits, 0 too; null and empty text leave the slot empty", [badgeOf(3), badgeOf(0), badgeOf(null), badgeOf("")].join(" | "));
  const bare = { machines: [{ name: "pc", made: 0 }], thrall: [{ machine: "pc", entry: "e", orcs: 2, working: 2, waitingFounder: 0, blocked: 0, unknown: 0, hasStatus: false, census: null }], cards: [] };
  check((() => { try { const tv = LC.laneCardView(bare, LC.THRALL_LANE, { nowMs }); return tv !== null && tv.lines.every((l) => l.label !== "Waiting on the founder"); } catch (x) { return false; } })(), "a Thrall entry with no list of lanes waiting on the founder draws, with no such line");
  const dupes = P.readCardsSnapshot(cardsBody(m1, { name: "x", cards: [card("thrall"), card("A"), card("A", { now: "the second A" }), card("B")] }), "work", m1.keyId);
  check(dupes.ok && dupes.value.dropped === 2 && dupes.value.cards.map((x) => x.lane).join(",") === "A,B" && dupes.value.cards[0].now === "doing A", "ONE ID IS ONE CARD: a lane card with the Thrall's id, and a second card of one id, are dropped and counted; the first stands", JSON.stringify(dupes.value && dupes.value.cards.map((x) => [x.lane, x.now])));
  const why = (extra) => P.readCardsSnapshot(cardsBody(m1, { name: "x", cards: [card("Q", { form: "other", ...extra })] }), "work", m1.keyId).value.cards[0].note;
  check(why({ problems: "its orc is not one capital letter" }).indexOf("not in the standard form") >= 0 && why({ problems: "its orc is not one capital letter" }).indexOf("its orc is not one capital letter") >= 0 && why({ problems: "a\u0007bell" }) === P.CARD_FORM_WORDS.other && why({}) === P.CARD_FORM_WORDS.other && P.readCardsSnapshot(cardsBody(m1, { name: "x", cards: [card("Q", { problems: "has 5 lines" })] }), "work", m1.keyId).value.cards[0].note === "", "A LANE NOT IN THE STANDARD FORM says which rules it breaks, in the status reader's words; words with a control character, or none, leave the phone's own sentence; a standard card says nothing", why({ problems: "its orc is not one capital letter" }));
  const idWords = "Another lane folder here (orc-f-first) gives the same id, F, so this card has its own.";
  const renamed = (extra) => P.readCardsSnapshot(cardsBody(m1, { name: "x", cards: [card("lane-5", extra)] }), "work", m1.keyId).value.cards[0].note;
  check(renamed({ idNote: idWords }) === idWords && renamed({ form: "other", problems: "its orc is not one capital letter", idNote: idWords }) === P.cardFormNote("other", "its orc is not one capital letter") + " " + idWords && renamed({ form: "missing", idNote: idWords }) === P.CARD_FORM_WORDS.missing + " " + idWords && renamed({ idNote: "a\u0007bell" }) === "" && renamed({}) === "", "A CARD WITH AN ID OF ITS OWN says why on the phone, after what its form says; words with a control character, or none, add nothing", renamed({ form: "other", problems: "x", idNote: idWords }));
  const lo = P.readCardsSnapshot(cardsBody(m1, { name: "pc", left: 3, areasLeft: 7 }), "work", m1.keyId);
  const lom = P.mergeCards([{ entry: "e1", seq: 1, value: lo.value }]);
  check(lo.ok && lo.value.cardsLeftOut === 3 && lo.value.areasLeftOut === 7 && lom.machines[0].cardsLeftOut === 3 && lom.machines[0].areasLeftOut === 7 && P.readCardsSnapshot(cardsBody(m1, { name: "pc", areasLeft: -2 }), "work", m1.keyId).value.areasLeftOut === 0, "CARDS AND AREAS LEFT OUT are read from the snapshot and carried per machine for the page to say; a count that is no count is none", JSON.stringify(lom.machines));
  check(P.streamMovesPlace({ entry: "e1", lane: "" }, "e1") && !P.streamMovesPlace({ entry: "e1", lane: "E" }, "e1") && !P.streamMovesPlace({ entry: "e2", lane: "" }, "e1") && !P.streamMovesPlace(null, "e1"), "HIS PLACE MOVES ONLY IN THE WHOLE LOG of the picked pairing: never in a lane's stream, never in another pairing's log, never on the cards page");
  const twin = P.mergeCards([{ entry: "e1", seq: 1, value: { ...lo.value, name: "pc", made: 1 } }, { entry: "e2", seq: 1, value: { ...lo.value, name: "pc", made: 2 } }]);
  check(twin.machines.length === 1 && twin.machines[0].entry === "e2", "KNOWN LIMIT: two machines that send one name are merged as one, the newest standing - machines are told apart by the name each is given (its machineName setting), so two must be named apart");
  a.phone.lock(p2.id);
  c = await a.phone.cards(a.paired.id);
  check(c.machines.every((x) => x.entry !== p2.id), "a locked pairing's cards are not shown");
  a.phone.lock(a.paired.id);
  check((await throwsAsync(async () => a.phone.cards(a.paired.id))).indexOf("locked") >= 0, "a locked horde shows no cards");
}

// --- 10e2. WHY THERE ARE NO CARDS: the one line the Progress tab's fallback shows (cards-why.js) ---
{
  const t = R.memoryTransport();
  const m1 = await newMachine("work");
  const a = await pairedApp(t, m1);
  await a.phone.refresh(a.paired.id);
  const none = await a.phone.cards(a.paired.id);
  check(none.refused === "" && none.unpaired === false && CW.cardsFallbackLine(none) === "No cards from your PC yet.", "NO SNAPSHOT YET: the fallback says no cards have come from the PC", JSON.stringify(none));
  // A snapshot from the paired PC that does not read: the reason, short, in the phone's own words.
  await sendCards(t, m1, a.phoneKey, P.utf8("{"));
  const bad = await a.phone.refresh(a.paired.id);
  const refused = await a.phone.cards(a.paired.id);
  check(bad.anomalies.length === 1 && refused.machines.length === 0 && refused.refused === "the cards body is not JSON" && CW.cardsFallbackLine(refused) === "Cards could not be read: the cards body is not JSON.", "A REFUSED SNAPSHOT: the fallback says the cards could not be read, and why", JSON.stringify(refused));
  // A PC of the horde this phone has no pairing for sends cards: the phone can tell, by who sent them.
  const t2 = R.memoryTransport();
  const p1 = await newMachine("home");
  const stranger = await newMachine("home");
  const b = await pairedApp(t2, p1);
  await sendCards(t2, stranger, b.phoneKey, cardsBody(stranger, { name: "other-pc", cards: [card("E")] }));
  await b.phone.refresh(b.paired.id);
  const unp = await b.phone.cards(b.paired.id);
  check(unp.machines.length === 0 && unp.unpaired === true && unp.refused === "" && CW.cardsFallbackLine(unp) === "This phone is not paired to the PC that sends cards.", "CARDS FROM A PC THIS PHONE IS NOT PAIRED TO: the fallback says so", JSON.stringify(unp));
  // A PC this phone IS paired to, its pairing locked: its cards are not opened, and it is no stranger.
  const m2 = await newMachine("work");
  const p2 = await a.phone.pair({ offerText: (await offerText(m2, { label: "home-box" })), label: "Founder phone" });
  await a.phone.announce(p2.id);
  const k2 = await phoneKeyOf(t, m2);
  a.phone.lock(p2.id);
  await sendCards(t, m2, k2, cardsBody(m2, { name: "home-pc", cards: [card("G")] }));
  await a.phone.refresh(a.paired.id);
  const lockedSib = await a.phone.cards(a.paired.id);
  check(lockedSib.machines.length === 0 && lockedSib.unpaired === false, "CONTROL: cards from a PC this phone is paired to, its pairing locked, are not said to come from a PC it is not paired to", JSON.stringify(lockedSib));
  // CONTROL: cards present, no line at all; and a refusal a later good snapshot replaces is not said.
  await sendCards(t, m1, a.phoneKey, cardsBody(m1, { name: "office-pc", cards: [card("E")] }));
  await a.phone.refresh(a.paired.id);
  const good = await a.phone.cards(a.paired.id);
  check(good.machines.length === 1 && good.refused === "" && CW.cardsFallbackLine(good) === "", "CONTROL: with cards present there is no line", JSON.stringify(good));
  check(CW.cardsFallbackLine({ machines: [], refused: "x".repeat(500) + "\u0007" }).length <= 140 && CW.cardsFallbackLine({ machines: [], refused: "a\u0007bell" }) === "Cards could not be read: abell." && CW.cardsFallbackLine({ machines: [], refused: "ok", unpaired: true }).indexOf("Cards could not be read") === 0 && CW.cardsFallbackLine(null) === "No cards from your PC yet.", "the reason is cut short and plain ASCII; a refusal is said before a stranger PC; nothing known is no cards yet");
}

// --- 10e3. THE DECISIONS PAGE'S CARDS (decision-cards.js, decision 74): the Progress tab's card, its slot the lane's count ---
{
  const node = (tag) => ({ tag, className: "", textContent: "", type: "", attrs: {}, kids: [], on: {}, appendChild(k) { if (!k || typeof k !== "object" || typeof k.tag !== "string") throw new TypeError("parameter 1 is not of type 'Node'"); this.kids.push(k); return k; }, setAttribute(n, v) { this.attrs[n] = v; }, addEventListener(n, f) { this.on[n] = f; } });
  const fake = { createElement: node, createTextNode: (t) => ({ tag: "#text", textContent: t, kids: [] }) };
  const text = (n) => (n.textContent || "") + (n.kids || []).map(text).join("");
  const slotOf = (card) => card.kids[0].kids.find((k) => k.className === "card-badge");
  const nameOf = (card) => card.kids[0].kids.find((k) => k.className === "card-name").textContent;
  const lanesDoc = { machines: [{ name: "pc", made: 0 }], thrall: [{ machine: "pc", entry: "e", orcs: 3, working: 2, waitingFounder: 1, blocked: 0, unknown: 0, hasStatus: true, now: "routing", census: null }],
    cards: [{ lane: "B", name: "lane B", machine: "pc", entry: "e", form: "standard", asOf: "", now: "building", lastDone: "", waitingOn: "", blocked: "no", tasksOpen: 1, doneWeek: 0 }, { lane: "E", name: "E", machine: "pc", entry: "e", form: "standard", asOf: "", now: "reviewing", lastDone: "", waitingOn: "", blocked: "no", tasksOpen: 0, doneWeek: 2 }] };
  const counts = [{ lane: "thrall", open: 2, blocksAll: false }, { lane: "B", open: 3, blocksAll: true }, { lane: "H", open: 1, blocksAll: false }];
  const view = DC.decisionCardsView(lanesDoc, counts, "");
  check(view.map((v) => v.lane + ":" + v.open + (v.blocksAll ? "!" : "")).join(",") === "all:6!,thrall:2,B:3!,E:0,H:1", "ONE CARD PER LANE, ALL QUESTIONS FIRST: All with every lane's count summed and the blocks mark if any lane has it; the Thrall's next; then every lane by name - one the lanes document has and that asks nothing (E) with 0, one that asks and has no card (H) too", JSON.stringify(view));
  check(DC.decisionCardsView(lanesDoc, counts, "").map((v) => v.lane + ":" + v.open).join(",") !== "all:5,thrall:2,B:3,E:0,H:1" && DC.decisionCardsView(null, [], "").map((v) => v.lane + ":" + v.open).join(",") === "all:0", "MUST-FAIL TWIN: a sum that left out a lane would read 5 and is not what is drawn; with no lanes document and nothing to answer there is the All card alone, at 0");
  check(DC.decisionCardsView(null, counts, "").map((v) => v.lane).join(",") === "all,thrall,B,H" && DC.decisionCardsView(lanesDoc, [{ lane: "", open: 9 }, null, { lane: "C", open: "x" }], "").map((v) => v.lane + ":" + v.open).join(",") === "all:0,thrall:0,B:0,C:0,E:0", "with no lanes document the lanes that ask are the cards; a count with no lane is dropped, and one that is no number counts 0");
  let chose = null;
  const cards = DC.renderDecisionCards(fake, lanesDoc, counts, { chosen: "B", onChoose: (l) => { chose = l; }, nowMs: 0 });
  check(cards.length === 5 && cards.map(nameOf).join("|") === "All questions|Thrall|B - lane B|E|Orc H", "THE SAME CARD: a lane of the lanes document is drawn with its own name (lane-card.js), one it lacks by its Orc's name, All questions by that name", cards.map(nameOf).join("|"));
  check(text(slotOf(cards[2])) === "3 open \u26D4 blocks all work" && slotOf(cards[2]).kids[0].kids[0].className === "dq-blocks" && text(slotOf(cards[3])) === "0 open" && cards[2].className.indexOf("dq-blocking") >= 0 && cards[3].className.indexOf("dq-blocking") < 0,
    "THE BLOCKS MARK is words and a sign in the slot beside the count, never a colour alone; a lane that blocks nothing has the count alone", text(slotOf(cards[2])) + " / " + text(slotOf(cards[3])));
  check(cards[2].attrs["aria-pressed"] === "true" && cards[2].className.indexOf("chosen") >= 0 && cards[0].attrs["aria-pressed"] === "false" && cards.filter((c) => c.attrs["aria-pressed"] === "true").length === 1, "the chosen lane's card, and it alone, says it is chosen, to a screen reader as well");
  check(cards[1].kids.some((k) => k.className === "card-line") && cards[4].kids.length === 1, "a card of the lanes document keeps its lines (the Thrall's Now and Fleet); a lane known only by name is its head alone");
  cards[4].on.click(); const h = chose; cards[0].on.click();
  check(h === "H" && chose === "", "a tap on a card chooses its lane; a tap on All questions chooses all (\"\")", JSON.stringify([h, chose]));
  const all = DC.renderDecisionCards(fake, null, [], { nowMs: 0 });
  check(all.length === 1 && all[0].attrs["aria-pressed"] === "true" && typeof all[0].on.click === "undefined", "nothing to answer anywhere: the All card alone, chosen; with no onChoose a tap does nothing");
  check(LC.renderLaneCard(fake, lanesDoc, "Q", { nowMs: 0 }) === null && nameOf(LC.renderLaneCard(fake, lanesDoc, "Q", { nowMs: 0, orName: "Orc Q" })) === "Orc Q" && nameOf(LC.renderLaneCard(fake, lanesDoc, "B", { nowMs: 0, orName: "Orc B" })) === "B - lane B", "lane-card.js: orName draws a lane the document lacks by that name, and never replaces a card the document has; without it such a lane is still no card");
}

// --- 10g. A NEW VERSION OF THE APP (app-update.js): reload once, never on the first install, never over his words ---
{
  const d = (o) => AU.reloadDecision({ hadController: true, reloaded: false, busy: false, ...o });
  check(d({}) === "reload", "a new worker taking over a page that had one reloads it");
  check(d({ hadController: false }) === "none", "THE FIRST INSTALL never reloads: there was no worker before");
  check(d({ reloaded: true }) === "none" && d({ reloaded: true, busy: true }) === "none", "ONCE: a page that has reloaded (or begun to) never reloads again");
  check(d({ busy: true }) === "wait", "WITH UNSENT WORDS it waits, and the page says a new version is ready");
  check(AU.UPDATE_READY_WORDS === "A new version is ready - it loads when you finish.", "the waiting line is the founder's words");
  check(AU.draftsHeld(null) === false && AU.draftsHeld("{}") === false && AU.draftsHeld("not json") === false && AU.draftsHeld('{"3":"half an answer"}') === true && AU.draftsHeld('{"3":""}') === true, "a draft kept by the document counts as unsent words; none, or an empty keeping, does not");
  const T = 1000000000;
  check(AU.updateDue(0, T) === true && AU.updateDue(T, T + 599999) === false && AU.updateDue(T, T + 600000) === true && AU.updateDue(T, T - 5) === true && AU.UPDATE_EVERY_MS === 600000, "THE UPDATE CHECK, at most once in 10 minutes: first time due, again only after 10 minutes, and a clock set back is due");
  const v = "0123456789abcdef", w = "fedcba9876543210";
  check(AU.versionWords(v, v) === "Version " + v + "." && AU.versionWords(v, "") === "Version " + v + "." && AU.versionWords(v, w) === "Version " + v + " - update pending (" + w + ")." && AU.versionWords("", "") === "Version not known." && AU.versionWords("<b>", w) === "Version not known.", "THE ACCOUNT SCREEN SAYS THE VERSION the page was built as; a worker of another says update pending; anything that is not a version is not shown");
}

// --- 10h. A READ THAT FAILS IS SAID, WITH THE TIME OF THE LAST ONE THAT WORKED (read-banner.js, bridge.js read-changed) ---
{
  const base = R.memoryTransport();
  let fault = null; // null: the relay answers; else the reason every read and watch answers with
  const t = { ...base, get: (...x) => (fault ? Promise.resolve({ state: "unknown", value: null, reason: fault }) : base.get(...x)), watch: (...x) => (fault ? Promise.resolve({ state: "unknown", value: null, reason: fault }) : base.watch(...x)) };
  const m = await newMachine("work");
  const a = await pairedApp(t, m);
  let clockNow = Date.parse("2026-10-14T02:36:00Z");
  const br = createBridge(a.phone, { loadKinds: async () => ({}), now: () => clockNow });
  const reads = [];
  br.on("read-changed", (rec) => reads.push(rec));
  const notes = [];
  br.on("notice", (w) => notes.push(w));
  const at = (ms) => (ms === Date.parse("2026-10-14T02:36:00Z") ? "02:36" : "other " + ms);
  const bannerOf = (rec, session = null) => RB.readBanner(RB.readFailure(rec, session), rec.lastGoodAt, at);
  await br.request("pick", { id: a.paired.id });
  const good = reads[reads.length - 1];
  check(reads.length === 1 && good.relayDown === false && good.lastGoodAt === clockNow && bannerOf(good) === "", "CONTROL: a read that works says so, with its time, and there is no banner", JSON.stringify(reads));
  fault = "the relay answered the read with 401: not signed in";
  clockNow += 3 * 3600000;
  await br.request("refresh");
  const r401 = reads[reads.length - 1];
  check(notes[notes.length - 1].indexOf("could not be read") >= 0, "the failed read is said as a notice", JSON.stringify(notes));
  check(r401.relayDown === true && RB.readFailure(r401) === "signed-out" && bannerOf(r401) === "Not signed in to the relay - sign in again. Last updated 02:36.", "A 401 ON THE MAILBOX READ shows the sign-in banner and the last-updated time - the time of the last read that worked, not of the failure", bannerOf(r401));
  fault = "the relay's watch failed";
  await br.request("refresh");
  const rNet = reads[reads.length - 1];
  check(RB.readFailure(rNet) === "unreachable" && bannerOf(rNet) === "Cannot reach the relay. Last updated 02:36." && RB.readFailure(rNet, { state: "unknown", status: 401 }) === "signed-out" && RB.readFailure(rNet, { state: "known", status: 200, value: { signedIn: false } }) === "signed-out" && RB.readFailure(rNet, { state: "known", status: 200, value: { signedIn: true } }) === "unreachable" && RB.readFailure(rNet, { state: "unknown", status: 0 }) === "unreachable", "A WATCH THAT FAILS is the relay out of reach - unless the relay's session says he is signed out (an expired sign-in refused at the socket)");
  fault = null;
  clockNow += 60000;
  await br.request("refresh");
  const back = reads[reads.length - 1];
  check(notes[notes.length - 1] === "", "and a clean read says a notice of nothing, so the page clears the old one only then", JSON.stringify(notes));
  check(back.relayDown === false && back.lastGoodAt === clockNow && bannerOf(back) === "", "A SUCCESSFUL READ CLEARS IT, and is the new last-updated time", JSON.stringify(back));
  await br.request("lock", { id: a.paired.id });
  await br.request("refresh");
  const lk = reads[reads.length - 1];
  check(lk.locked === true && RB.readFailure(lk) === "locked" && bannerOf(lk).indexOf("This horde is locked - unlock to read.") === 0, "a read of a locked horde says it is locked", bannerOf(lk));
  check(RB.readBanner("", 5, at) === "" && RB.readBanner("unreachable", 0, at) === "Cannot reach the relay." && RB.readFailure(null) === "", "no failure is no banner; with no read that ever worked there is no time to say");
}

// --- 10f. the notices: each once, newest first, read kept on the phone; the follow switch sent like an answer ---
const noticeOf = (n, extra = {}) => ({ v: 1, n, id: P.hex(P.randomBytes(16)), ts: "2026-10-14T03:0" + n + ":00.000Z", kind: "notify", from: "E", text: "line " + n, lane: "", entry: "", ...extra });
const noticesBody = (m, { follows = {}, notices = [] }) => P.utf8(JSON.stringify({ v: 1, kind: "notices", horde: m.horde, machine: m.keyId, follows, notices }));
async function sendNotices(t, m, phone, body, seq) { const e = await machineEnvelope(m, { kind: "notices", channel: "notices", body, phones: [phone], ...(seq ? { seq } : {}) }); await t.put(m.horde + "/phone", e.key, e.text); return e; }
{
  const t = R.memoryTransport();
  const m1 = await newMachine("work");
  const m2 = await newMachine("work");
  const a = await pairedApp(t, m1);
  const p2 = await a.phone.pair({ offerText: (await offerText(m2, { label: "home-box" })), label: "Founder phone" });
  await a.phone.announce(p2.id);
  const k2 = await phoneKeyOf(t, m2);
  await a.phone.refresh(a.paired.id);
  let nv = await a.phone.notices(a.paired.id);
  check(nv.items.length === 0 && nv.unread === 0, "CONTROL: before any machine sends notices there are none");
  const n1 = noticeOf(1), n2 = noticeOf(2, { kind: "progress", from: "Orc E", text: "Merged: the cards", lane: "E", entry: "p-1" }), n3 = noticeOf(3);
  await sendNotices(t, m1, a.phoneKey, noticesBody(m1, { follows: { E: true }, notices: [n1, n2] }));
  // The same notice again in a later envelope (a backfill beside a live one) is one notice.
  await sendNotices(t, m1, a.phoneKey, noticesBody(m1, { follows: { E: true }, notices: [n2, n3] }));
  await sendNotices(t, m2, k2, noticesBody(m2, { follows: {}, notices: [noticeOf(4, { from: "G" })] }));
  const r1 = await a.phone.refresh(a.paired.id);
  nv = await a.phone.notices(a.paired.id);
  check(r1.anomalies.length === 0 && nv.items.map((x) => x.text).join("|") === "line 4|line 3|Merged: the cards|line 1" && nv.unread === 4, "NEWEST FIRST, EACH ONCE: the notices of both machines of the horde, a notice carried twice shown once, all unread", JSON.stringify({ an: r1.anomalies, t: nv.items.map((x) => x.text) }));
  check(nv.items.find((x) => x.text === "line 4").entry === p2.id && nv.items.find((x) => x.id === n2.id).entry === a.paired.id && nv.follows[a.paired.id].E === true && Object.keys(nv.follows[p2.id]).length === 0, "each notice names the pairing it came by, and each machine's switches are what it sent", JSON.stringify(nv.follows));
  const read = await a.phone.markNoticesRead(a.paired.id, [n2.id]);
  check(read.unread === 3 && read.items.find((x) => x.id === n2.id).read === true, "a notice marked read is read, and the count goes down");
  const stored = await a.store.get("horde/" + a.paired.id);
  check(Array.isArray(stored.noticesRead) && stored.noticesRead.indexOf(n2.id) >= 0 && JSON.stringify(stored).indexOf("Merged: the cards") < 0, "read is kept on this phone, as ids only: no word of a notice is stored");
  const all = await a.phone.markNoticesRead(a.paired.id);
  check(all.unread === 0, "mark all read reads every notice the phone holds");
  // THE SWITCHES OF THE NEWEST ENVELOPE STAND: an envelope of a lower seq, arriving later, changes nothing.
  await sendNotices(t, m1, a.phoneKey, noticesBody(m1, { follows: { E: false }, notices: [] }), 1);
  await a.phone.refresh(a.paired.id);
  check((await a.phone.notices(a.paired.id)).follows[a.paired.id].E === true, "a switch from an older envelope of the machine never overrules a newer one");
  await sendNotices(t, m1, a.phoneKey, noticesBody(m1, { follows: { E: false, thrall: true }, notices: [] }));
  await a.phone.refresh(a.paired.id);
  nv = await a.phone.notices(a.paired.id);
  check(nv.follows[a.paired.id].E === false && nv.follows[a.paired.id].thrall === true, "THE PHONE SHOWS WHAT THE MACHINE HOLDS: the newest envelope's switches stand");
  // The body, read strictly.
  check(!P.readNotices(noticesBody({ horde: "work", keyId: m2.keyId }, {}), "work", m1.keyId).ok && !P.readNotices(P.utf8('{"v":1,"kind":"notices"}'), "work", m1.keyId).ok && !P.readNotices(P.utf8("{"), "work", m1.keyId).ok, "a notices body of another machine, with no switches or notices, or not JSON, is refused");
  const bad = P.readNotices(noticesBody(m1, { follows: { "E": true, "bad lane!": true, F: "yes" }, notices: [noticeOf(1), noticeOf(2, { kind: "made-up" }), noticeOf(3, { text: "a\u0007bell" }), noticeOf(4, { id: "short" })] }), "work", m1.keyId);
  check(bad.ok && bad.value.dropped === 3 && bad.value.notices.length === 1 && JSON.stringify(bad.value.follows) === '{"E":true}', "a notice of a kind the phone does not know, with a control character, or with no id is dropped and counted; a switch that is not a lane's true or false is left out", JSON.stringify(bad.value));
  // THE FOLLOW SWITCH, sent like an answer.
  const before = (await t.get(m1.mailbox, 0, 256)).value.items.length;
  const sent = await a.phone.follow(a.paired.id, { entry: a.paired.id, lane: "E", on: true });
  const items = (await t.get(m1.mailbox, 0, 256)).value.items;
  const got = await machineOpens(m1, items[items.length - 1].text);
  check(items.length === before + 1 && got.header.channel === "notices" && got.header.kind === "follow" && got.header.from === (await a.store.get("horde/" + a.paired.id)).deviceKeyId && sent.key === P.replayKey(got.header), "a switch goes to the card's machine, on the notices channel, as kind follow, from this phone's passkey", JSON.stringify(got.header));
  check(Object.keys(got.body).join(",") === "v,setId,machine,lane,on" && got.body.machine === m1.keyId && got.body.lane === "E" && got.body.on === true && /^[0-9a-f]{32}$/.test(got.body.setId), "its body is exactly what the machine reads: version, setId, the machine's key id, the lane and on", JSON.stringify(got.body));
  const viaSibling = await a.phone.follow(a.paired.id, { entry: p2.id, lane: "thrall", on: false });
  const items2 = (await t.get(m2.mailbox, 0, 256)).value.items;
  const got2 = await machineOpens(m2, items2[items2.length - 1].text);
  check(!!viaSibling.key && got2.body.machine === m2.keyId && got2.body.lane === "thrall" && got2.body.on === false, "a card of the horde's other machine sends its switch to THAT machine, sealed to it", JSON.stringify(got2.body));
  check((await throwsAsync(async () => a.phone.follow(a.paired.id, { entry: a.paired.id, lane: "bad lane!", on: true }))).indexOf("lane") >= 0, "a lane that is not a card's lane is never sent");
  check((() => { try { P.followBody({ setId: "x", machine: m1.keyId, lane: "E", on: true }); return false; } catch (x) { return true; } })() && (() => { try { P.followBody({ setId: P.hex(P.randomBytes(16)), machine: m1.keyId, lane: "E", on: "yes" }); return false; } catch (x) { return true; } })(), "a switch body with a setId that is no id, or an on that is not true or false, is never made");
  // Through the bridge.
  const br = createBridge(a.phone, { loadKinds: async () => ({}) });
  const evs = [];
  br.on("notices-changed", (rec) => evs.push(rec));
  await br.request("pick", { id: a.paired.id });
  const rec = await br.request("notices");
  const f = await br.request("follow", { entry: a.paired.id, lane: "F", on: true });
  const rr = await br.request("notices-read", { ids: [n1.id] });
  check(rec.state === "known" && rec.value.items.length === 4 && evs.length === 1 && evs[0].state === "known" && f.ok === true && rr.state === "known", "the bridge answers notices, pushes notices-changed with every refresh, sends a switch and marks notices read");
  // A session that cannot sign sends no switch.
  a.phone.lock(a.paired.id);
  await a.phone.recover(a.paired.id, a.paired.recoveryCode);
  check((await throwsAsync(async () => a.phone.follow(a.paired.id, { entry: a.paired.id, lane: "E", on: false }))).indexOf("recovery code") >= 0, "unlocked with the recovery code, a switch is refused in words: only the passkey signs one");
  a.phone.lock(a.paired.id);
  check((await throwsAsync(async () => a.phone.notices(a.paired.id))).indexOf("locked") >= 0, "a locked horde shows no notices");
}
{
  // THE VIEW (notices-view.js), with a stand-in document whose clicks bubble as a browser's do.
  const fake = () => {
    const node = (tag) => ({ tag, className: "", textContent: "", type: "", attrs: {}, kids: [], on: {}, parent: null,
      appendChild(k) { if (!k || typeof k !== "object" || typeof k.tag !== "string") throw new TypeError("parameter 1 is not of type 'Node'"); k.parent = this; this.kids.push(k); return k; },
      setAttribute(a, v) { this.attrs[a] = v; }, addEventListener(a, f) { (this.on[a] = this.on[a] || []).push(f); },
      // A click goes to the node, then up through its parents until a handler stops it.
      click() { const ev = { stopped: false, prevented: false, stopPropagation() { this.stopped = true; }, preventDefault() { this.prevented = true; } }; for (let x = this; x && !ev.stopped; x = x.parent) for (const f of x.on.click || []) f(ev); return ev; } });
    return { createElement: node, createTextNode: (t) => ({ tag: "#text", textContent: t, kids: [] }) };
  };
  const doc = fake();
  const card = doc.createElement("button");
  let cardOpened = 0;
  card.addEventListener("click", () => { cardOpened++; });
  const plainSlot = doc.createElement("span");
  card.appendChild(plainSlot);
  plainSlot.click();
  check(cardOpened === 1, "CONTROL: in the stand-in, a tap on what a card holds opens the card, as in a browser");
  let wanted = null;
  const sw = NV.renderFollowSwitch(doc, { held: false, onToggle: (v) => { wanted = v; } });
  card.appendChild(sw);
  const ev = sw.click();
  check(wanted === true && cardOpened === 1 && ev.stopped && sw.attrs.role === "switch" && sw.attrs["aria-checked"] === "false" && sw.textContent === "Follow", "THE SWITCH'S TAP IS ITS OWN: off, a tap asks for on, and the card it sits in is not opened", JSON.stringify({ wanted, cardOpened }));
  const on = NV.renderFollowSwitch(doc, { held: true, onToggle: (v) => { wanted = v; } });
  on.click();
  check(wanted === false && on.attrs["aria-checked"] === "true" && on.textContent === "Following", "on, it says Following, and a tap asks for off");
  wanted = null;
  const busy = NV.renderFollowSwitch(doc, { held: true, sending: true, onToggle: (v) => { wanted = v; } });
  busy.click();
  check(wanted === null && busy.textContent === "Sending..." && busy.className.indexOf("sending") >= 0, "while a change is on its way it says Sending..., and a tap does nothing");
  const nowMs = Date.parse("2026-10-14T03:10:00Z");
  let openedItem = null;
  const unread = NV.renderNoticeItem(doc, { id: "a".repeat(32), said: Date.parse("2026-10-14T03:06:00Z"), kind: "notify", from: "E", text: "the build <b>is</b> green", read: false }, { nowMs, onOpen: (x) => { openedItem = x; } });
  const head = unread.kids[0];
  check(unread.className.indexOf("unread") >= 0 && head.kids[0].textContent === "E" && head.kids[1].textContent === "Unread" && head.kids[2].textContent === "4 min ago" && !!head.kids[2].attrs.title && unread.kids[1].textContent === "the build <b>is</b> green", "A NOTICE says who it is from, that it is unread, when in plain words with the exact time as its title, and its words as text, never markup", JSON.stringify(head.kids.map((k) => k.textContent)));
  unread.click();
  check(!!openedItem && openedItem.from === "E", "a tap on a notice is the page's");
  const readOne = NV.renderNoticeItem(doc, { id: "b".repeat(32), said: 0, kind: "notify", from: "E", text: "x", read: true }, { nowMs });
  check(readOne.className.indexOf("unread") < 0 && readOne.kids[0].kids.length === 2 && readOne.kids[0].kids[1].textContent === "", "a read notice has no unread mark, and one with no time says no time, never a guess");
  check(JSON.stringify(NV.noticeTarget({ kind: "progress", lane: "E", entry: "e1", machine: "pc" })) === '{"entry":"e1","lane":"E","machine":"pc"}' && NV.noticeTarget({ kind: "notify", lane: "", entry: "e1" }) === null && NV.noticeTarget({ kind: "cutoff", lane: "" }) === null, "a followed lane's notice opens that lane's stream; a notify line and a cut-off open nothing");
  check(NV.noticesTabWords(0) === "Notices" && NV.noticesTabWords(3) === "Notices (3)", "THE UNREAD COUNT on the tab: none says nothing, three says (3)");
  check(P.noticeList([{ entry: "e", machine: "pc", notices: [{ id: "x", said: 5, n: 1 }, { id: "y", said: 5, n: 2 }, { id: "z", said: 9, n: 3 }] }], new Set(["x"])).items.map((i) => i.id + (i.read ? "r" : "")).join(",") === "z,y,xr" && P.noticeList([{ entry: "e", notices: [{ id: "x", said: 1, n: 1 }] }], new Set()).unread === 1, "the list is newest first by time, then by the machine's number; the count is of unread ones");
  // EACH ONCE, IN THE LIST ITSELF: phone-core's takeNotices keeps one per id within one pairing, so the
  // end-to-end check above cannot see this rule (PR 259's after-merge mutation net: a-notice-is-shown-twice
  // survived). Here two held envelopes, of two pairings, carry the same notice.
  const twice = P.noticeList([{ entry: "e1", machine: "pc", notices: [{ id: "x", said: 5, n: 1 }] }, { entry: "e2", machine: "pc", notices: [{ id: "x", said: 5, n: 1 }] }], new Set());
  const twoIds = P.noticeList([{ entry: "e1", machine: "pc", notices: [{ id: "x", said: 5, n: 1 }] }, { entry: "e2", machine: "pc", notices: [{ id: "y", said: 5, n: 1 }] }], new Set());
  check(twice.items.length === 1 && twice.items[0].entry === "e1" && twice.unread === 1, "A NOTICE TWO ENVELOPES CARRY IS SHOWN ONCE, by its id, and counted once", JSON.stringify(twice));
  check(twoIds.items.length === 2 && twoIds.unread === 2, "CONTROL: two notices of two ids are shown twice", JSON.stringify(twoIds));
}

// --- 15. what became of each answer: kept until applied, shown answered while on its way, sent again when missing (the founder, 2026-10-14, relay fixes 3 and 4) ---
{
  // A phone on a clock of the suite's own, beginning at the real time (the machine's snapshots carry the
  // real time, and the phone compares them with its own).
  const clock = { now: Date.now() };
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const store = memoryStore();
  const auth = softAuthenticator({ origin, prf: true });
  const make = () => createPhone({ store, authenticator: auth, relay: R.createRelayClient(t), origin, now: () => clock.now });
  let phone = make();
  const paired = await phone.pair({ offerText: (await offerText(m)), label: "Founder phone" });
  await phone.announce(paired.id);
  const phoneKey = await phoneKeyOf(t, m);
  const from = (await store.get("horde/" + paired.id)).deviceKeyId;
  const receipt = (over = {}) => [{ from, through: 0, checked: 1, missing: [], applied: [], refused: [], ...over }];
  const lastAnswer = async () => { const items = (await t.get(m.mailbox, 0, 256)).value.items; for (let i = items.length - 1; i >= 0; i--) { const o = await machineOpens(m, items[i].text); if (o.header.channel === "decisions") return { ...o, key: items[i].key }; } return null; };
  const kept = async () => { const x = await store.get("outbox/" + paired.id); return x && Array.isArray(x.items) ? x.items : []; };
  const stateOf = async (answerId) => { const a = (await phone.answers(paired.id)).find((x) => x.answerId === answerId); return a ? a.state + (a.warning ? "+warning" : "") : "none"; };

  // A MACHINE FROM BEFORE RECEIPTS: nothing would ever confirm an answer, so none is kept.
  await sendSnapshot(t, m, [phoneKey], [question(1, "One?")], { answers: 2 });
  await phone.refresh(paired.id);
  await phone.answer(paired.id, { number: 1, wordingVersion: 1, text: "Old machine.", answerId: P.hex(P.randomBytes(16)) });
  check((await kept()).length === 0 && (await phone.answers(paired.id)).length === 0, "to a machine whose snapshot has no receipts, an answer is sent as before and nothing is kept");

  // SENT, THEN RECEIVED, THEN APPLIED.
  await sendSnapshot(t, m, [phoneKey], [question(1, "One?"), question(2, "Two?", { kind: "parts", parts: ["(a) A?", "(b) B?"] })], { answers: 2, receipts: receipt() });
  await phone.refresh(paired.id);
  const id1 = P.hex(P.randomBytes(16));
  const sentAt = clock.now;
  await phone.answer(paired.id, { number: 1, wordingVersion: 1, text: "Yes, kept.", answerId: id1 });
  const env1 = await lastAnswer();
  check(env1.body.answerId === id1 && (await stateOf(id1)) === "sent", "AN ANSWER SHOWS SENT once the relay took it", await stateOf(id1));
  const box = await kept();
  check(box.length === 1 && box[0].answerId === id1 && box[0].seqs.join(",") === String(env1.header.seq) && box[0].envelope.key === env1.key && JSON.stringify(box).indexOf("Yes, kept.") < 0, "THE OUTBOX KEEPS IT: its ids, the seq and the envelope the relay took, and its words only sealed to the phone's own key - never as text", JSON.stringify(box[0] && { seqs: box[0].seqs, key: box[0].envelope.key }));
  await sendSnapshot(t, m, [phoneKey], [question(1, "One?"), question(2, "Two?", { kind: "parts", parts: ["(a) A?", "(b) B?"] })], { answers: 2, receipts: receipt({ through: env1.header.seq }) });
  await phone.refresh(paired.id);
  check((await stateOf(id1)) === "received" && (await kept()).length === 1, "THEN RECEIVED BY PC, when the receipt's through reaches its seq - and still kept", await stateOf(id1));

  // A RELOAD: the words come back from the outbox, and the question stands answered, never empty.
  phone = make();
  await phone.unlock(paired.id);
  const bridge = createBridge(phone, { loadKinds: async () => ({}) });
  const rec = await bridge.request("pick", { id: paired.id });
  const q1 = rec.value.questions.find((q) => q.number === 1);
  const mine = q1.thread.messages[q1.thread.messages.length - 1];
  check(rec.state === "known" && mine.speaker === "founder" && mine.text === "Yes, kept." && mine.local === true && mine.receipt === "received by PC" && mine.receiptNote === "", "A PENDING ANSWER SHOWS AS ANSWERED, NEVER EMPTY: after a reload the question carries his words as his last message, marked received by PC", JSON.stringify(mine));
  check(rec.value.questions.find((q) => q.number === 2).thread.messages.length === 0, "CONTROL: a question he did not answer has nothing drawn into it");
  const said = await bridge.request("say", { number: 2, text: "Only a.", wording: 1, id: P.hex(P.randomBytes(16)), part: "a" });
  const after = await bridge.request("list");
  const q2 = after.value.questions.find((q) => q.number === 2);
  const part = q2.thread.messages[q2.thread.messages.length - 1];
  check(said.ok === true && part.part === "a" && part.text === "Only a." && part.receipt === "sent" && Number(part.sequence) >= said.sequence, "a part answered by itself is drawn under its part, marked sent, at the sequence the page waits for", JSON.stringify({ said, part }));

  await sendSnapshot(t, m, [phoneKey], [question(1, "One?", { thread: { count: 1, turn: "warchief", messages: [{ sequence: 3, speaker: "founder", text: "Yes, kept." }] } }), question(2, "Two?", { kind: "parts", parts: ["(a) A?", "(b) B?"] })], { answers: 2, receipts: receipt({ through: env1.header.seq, applied: [id1] }) });
  await bridge.request("refresh");
  const rec2 = await bridge.request("list");
  const msgs = rec2.value.questions.find((q) => q.number === 1).thread.messages;
  check((await stateOf(id1)) === "applied" && msgs.length === 1 && msgs[0].receipt === "applied" && !msgs[0].local, "THEN APPLIED: the receipt lists its answerId, and his message in the snapshot's own thread is marked applied - drawn once, not twice", JSON.stringify(msgs));
  check((await kept()).every((i) => i.answerId !== id1) && (await kept()).length === 1, "THE OUTBOX KEEPS AN ANSWER UNTIL APPLIED, and not after: the applied one is gone from it, the part still on its way is not");

  // MISSING: the PC took a later envelope of this phone, so the journal refuses this seq for good.
  const id3 = P.hex(P.randomBytes(16));
  await phone.answer(paired.id, { number: 1, wordingVersion: 1, text: "Lost on the way.", answerId: id3 });
  const env3 = await lastAnswer();
  const t3 = clock.now;
  await sendSnapshot(t, m, [phoneKey], [question(1, "One?"), question(2, "Two?", { kind: "parts", parts: ["(a) A?", "(b) B?"] })], { answers: 2, receipts: receipt({ through: env3.header.seq + 1, missing: [env3.header.seq], applied: [id1] }) });
  await phone.refresh(paired.id);
  clock.now = t3 + 60 * 1000;
  const early = await phone.resend(paired.id);
  check(early.resent === 0 && (await lastAnswer()).header.seq === env3.header.seq, "a missing answer is not sent again before the interval since it was sent", JSON.stringify(early));
  clock.now = t3 + P.ANSWER_RESEND_MS + 1000;
  const first = await phone.resend(paired.id);
  const env3b = await lastAnswer();
  const k3 = (await kept()).find((i) => i.answerId === id3);
  check(first.resent === 1 && env3b.header.seq > env3.header.seq && env3b.body.answerId === id3 && env3b.body.text === "Lost on the way." && env3b.body.snapshot === env3.body.snapshot && k3.seqs.join(",") === env3.header.seq + "," + env3b.header.seq, "A REPORTED-MISSING ANSWER IS RESENT: a NEW envelope, under a new seq, signed again, with the same answerId and words - the machine applies it once", JSON.stringify({ first, seqs: k3 && k3.seqs }));
  const again = await phone.resend(paired.id);
  check(again.resent === 0, "and not again at once");
  await sendSnapshot(t, m, [phoneKey], [question(1, "One?")], { answers: 2, receipts: receipt({ through: env3b.header.seq + 1, missing: [env3.header.seq, env3b.header.seq], applied: [id1] }) });
  await phone.refresh(paired.id);
  clock.now = t3 + P.ANSWER_RESEND_MS + 2 * 60 * 1000;
  const tooSoon = await phone.resend(paired.id);
  clock.now = t3 + 2 * P.ANSWER_RESEND_MS + 2000;
  const seqBefore = (await lastAnswer()).header.seq;
  await bridge.request("refresh");
  const second = { resent: (await lastAnswer()).header.seq > seqBefore ? 1 : 0 };
  check(tooSoon.resent === 0 && second.resent === 1, "missing again, it is resent ONCE PER INTERVAL: not two minutes after the last, and again once the interval is out - by the bridge's own refresh", JSON.stringify({ tooSoon, second }));

  // A WARNING after an hour unconfirmed; none before.
  clock.now = t3 + P.ANSWER_WARN_MS - 1000;
  const before = await stateOf(id3);
  clock.now = t3 + P.ANSWER_WARN_MS + 1000;
  const pastHour = await stateOf(id3);
  const warned = (await bridge.request("refresh")).value.questions.find((q) => q.number === 1).thread.messages.slice(-1)[0];
  check(before.indexOf("+warning") < 0 && pastHour.endsWith("+warning") && warned.receiptNote === P.ANSWER_WARNING && warned.text === "Lost on the way.", "AN ANSWER PENDING PAST AN HOUR SHOWS A WARNING, under his words; a minute before the hour it does not", before + " / " + pastHour + " / " + JSON.stringify(warned));

  // LOST AT THE END OF THE STREAM: the PC spoke well after the put and has nothing as late; the same
  // envelope is put again, and no seq is spent.
  const id4 = P.hex(P.randomBytes(16));
  clock.now = Date.now() - 30 * 60 * 1000;
  await phone.answer(paired.id, { number: 1, wordingVersion: 1, text: "Lost at the tail.", answerId: id4 });
  const env4 = await lastAnswer();
  await t.ack(m.mailbox, (await t.get(m.mailbox, 0, 256)).value.items.slice(-1)[0].seq);
  await sendSnapshot(t, m, [phoneKey], [question(1, "One?")], { answers: 2, receipts: receipt({ through: env3b.header.seq + 1, missing: [env3.header.seq, env3b.header.seq], applied: [id1] }) });
  await phone.refresh(paired.id);
  clock.now = Date.now();
  const tail = await phone.resend(paired.id);
  const back = (await t.get(m.mailbox, 0, 256)).value.items.find((i) => i.key === env4.key);
  check(tail.resent >= 1 && !!back && back.text === (await kept()).find((i) => i.answerId === id4).envelope.text, "an answer the PC never saw though it spoke well after is put again as the very envelope it was", JSON.stringify(tail));
  check((await phone.resend(paired.id)).resent === 0, "and not again within the interval, though no new envelope was made for it");

  // REFUSED: never sent again, and gone from the outbox once shown.
  await sendSnapshot(t, m, [phoneKey], [question(1, "One?")], { answers: 2, receipts: receipt({ through: env4.header.seq, applied: [id1], refused: [id4] }) });
  await phone.refresh(paired.id);
  check((await stateOf(id4)) === "refused" && (await kept()).every((i) => i.answerId !== id4), "an answer the PC refused says so, and leaves the outbox: it is never sent again");

  // A SESSION THAT CANNOT SIGN sends nothing that needs a new signature; the passkey's session does.
  const id5 = P.hex(P.randomBytes(16));
  await phone.answer(paired.id, { number: 1, wordingVersion: 1, text: "Needs a signature.", answerId: id5 });
  const env5 = await lastAnswer();
  await sendSnapshot(t, m, [phoneKey], [question(1, "One?")], { answers: 2, receipts: receipt({ through: env5.header.seq + 1, missing: [env5.header.seq], applied: [id1], refused: [id4] }) });
  phone.lock(paired.id);
  await phone.recover(paired.id, paired.recoveryCode);
  await phone.refresh(paired.id);
  clock.now += P.ANSWER_RESEND_MS + 1000;
  const unsigned = await phone.resend(paired.id);
  const stillHead = (await lastAnswer()).header.seq;
  await phone.unlock(paired.id);
  await phone.refresh(paired.id);
  const signed = await phone.resend(paired.id);
  check(unsigned.resent === 0 && stillHead === env5.header.seq && signed.resent === 1 && (await lastAnswer()).header.seq > env5.header.seq, "a missing answer is not sent again from a recovery session, which cannot sign; the passkey's session sends it", JSON.stringify({ unsigned, signed }));
  check((await kept()).length > 0, "CONTROL: an answer is still kept");
  await phone.forget(paired.id);
  check((await store.get("outbox/" + paired.id)) === undefined, "forgetting the horde forgets what it kept to send");

  // THE STATE BY ITSELF.
  const item = { answerId: id1, seqs: [5], sentAt: 0, lastSentAt: 0, lastResendAt: 0 };
  const rc = (o) => P.receiptFor([{ from, through: 0, missing: [], applied: [], refused: [], ...o }], from);
  check(P.answerState(item, rc({ through: 4 }), 0, 1).state === "sent" && P.answerState(item, rc({ through: 5 }), 0, 1).state === "received" && P.answerState(item, rc({ through: 6, missing: [5] }), 0, 1).state === "sent" && P.answerState(item, rc({ through: 6, applied: [id1] }), 0, 1).state === "applied", "answerState: sent below through, received at it, not received when its seq is missing, applied by its id");
  check(P.answerState(item, rc({ through: 6, missing: [5] }), 0, P.ANSWER_RESEND_MS).resend === "resign" && P.answerState(item, rc({ through: 4 }), P.ANSWER_TAIL_GRACE_MS + 1, P.ANSWER_RESEND_MS).resend === "reput" && P.answerState(item, rc({ through: 4 }), P.ANSWER_TAIL_GRACE_MS - 1, P.ANSWER_RESEND_MS).resend === "", "missing is signed again; unseen past the grace is put again; unseen within it is waited for");
  const others = P.receiptFor([{ from: "b".repeat(32), through: 9, missing: [], applied: [id1], refused: [] }, { from, through: 1, missing: [], applied: [], refused: [] }], from);
  check(others.through === 1 && !others.applied.has(id1), "receiptFor reads this passkey's receipt only, never another phone's");
  check(P.receiptFor(undefined, from) === null && P.receiptFor([{ from, through: -1, missing: [], applied: [], refused: [] }], from) === null && P.receiptFor([{ from, through: 1, missing: [], applied: ["not hex"], refused: [] }], from) === null && P.receiptFor([], from).through === 0, "receiptFor: none from a machine before receipts, none from one that does not hold together, nothing yet from one with no stream for this passkey");
}

// --- 15b. the review of PR 262: a hole below the list is lost, a stale answer is never sent, one prompt, nothing dropped ---
{
  const clock = { now: Date.now() };
  const t = R.memoryTransport();
  const m = await newMachine("work");
  const mem = memoryStore();
  // A store whose reads of the outbox can be made to fail (S3), and a passkey that can be made to refuse (M1b).
  const fails = { outbox: false };
  const store = { ...mem, get: async (k) => { if (fails.outbox && k.startsWith("outbox/")) throw new Error("the store could not be read"); return mem.get(k); } };
  const soft = softAuthenticator({ origin, prf: true });
  const refuse = { next: 0 };
  let prompts = 0;
  const auth = { create: (o) => soft.create(o), get: async (o) => { if (!o.prfInput) prompts += 1; if (refuse.next > 0) { refuse.next -= 1; const x = new Error("The operation either timed out or was not allowed."); x.name = "NotAllowedError"; throw x; } return soft.get(o); } };
  const make = () => createPhone({ store, authenticator: auth, relay: R.createRelayClient(t), origin, now: () => clock.now });
  const phone = make();
  const paired = await phone.pair({ offerText: (await offerText(m)), label: "Founder phone" });
  await phone.announce(paired.id);
  const phoneKey = await phoneKeyOf(t, m);
  const from = (await mem.get("horde/" + paired.id)).deviceKeyId;
  const receipt = (over = {}) => [{ from, through: 0, checked: 1, missing: [], applied: [], refused: [], ...over }];
  const qs = [question(1, "One?"), question(2, "Two?"), question(3, "Three?")];
  const snap = (over) => sendSnapshot(t, m, [phoneKey], qs, { answers: 2, receipts: receipt(over) });
  const lastAnswer = async () => { const items = (await t.get(m.mailbox, 0, 256)).value.items; for (let i = items.length - 1; i >= 0; i--) { const o = await machineOpens(m, items[i].text); if (o.header.channel === "decisions") return o; } return null; };
  const kept = async () => { const x = await mem.get("outbox/" + paired.id); return x && Array.isArray(x.items) ? x.items : []; };
  const seqNow = async () => ((await mem.get("horde/" + paired.id)).seq || {}).decisions || 0;
  await snap({});
  await phone.refresh(paired.id);

  // M1b, ATTACKED: a prompt that never signs spends no seq.
  const before = await seqNow();
  refuse.next = 1;
  const why = await throwsAsync(async () => phone.answer(paired.id, { number: 1, wordingVersion: 1, text: "Never signed.", answerId: P.hex(P.randomBytes(16)) }));
  const after = await seqNow();
  await phone.answer(paired.id, { number: 3, wordingVersion: 1, text: "Signed.", answerId: P.hex(P.randomBytes(16)) });
  check(why !== "" && after === before && (await lastAnswer()).header.seq === before + 1, "A PROMPT THAT NEVER SIGNS SPENDS NO SEQ: the next answer goes under the very next number, so a cancelled prompt leaves no hole", JSON.stringify({ before, after, sent: (await lastAnswer()).header.seq }));

  // M1, ATTACKED (probe P1): 16 lost, 18..49 holes, 50 arrived; the list holds the newest 32 and checked is 18.
  const holes = []; for (let s = 18; s <= 49; s++) holes.push(s);
  const lostItem = { answerId: P.hex(P.randomBytes(16)), seqs: [16], sentAt: 0, lastSentAt: 0, lastResendAt: 0 };
  const cut = P.receiptFor([{ from, through: 50, checked: 18, missing: holes, applied: [], refused: [] }], from);
  const st16 = P.answerState(lostItem, cut, 1, P.ANSWER_RESEND_MS);
  check(st16.state === "sent" && st16.resend === "resign" && st16.due, "A SEQ BELOW THE RECEIPT'S CHECKED IS MISSING, NOT RECEIVED: 16, under a list cut at the newest 32, is signed again", JSON.stringify(st16));
  check(P.answerState({ ...lostItem, seqs: [20] }, P.receiptFor([{ from, through: 50, checked: 18, missing: holes.filter((x) => x !== 20), applied: [], refused: [] }], from), 1, 1).state === "received", "CONTROL: a seq from checked up, not missing, is received");
  check(P.answerState(lostItem, P.receiptFor([{ from, through: 50, missing: [], applied: [], refused: [] }], from), 1, P.ANSWER_RESEND_MS).resend === "resign", "a receipt that does not say how far down it looked vouches for nothing below through");

  // M2, ATTACKED (probe P2): A "deploy now" is lost; B "do NOT deploy" to the same question replaces it.
  const idA = P.hex(P.randomBytes(16));
  await phone.answer(paired.id, { number: 1, wordingVersion: 1, text: "A: deploy now", answerId: idA });
  const envA = await lastAnswer();
  clock.now += 60 * 1000;
  const idB = P.hex(P.randomBytes(16));
  await phone.answer(paired.id, { number: 1, wordingVersion: 1, text: "B: do NOT deploy", answerId: idB });
  const envB = await lastAnswer();
  check((await kept()).every((i) => i.answerId !== idA) && (await kept()).some((i) => i.answerId === idB), "A NEW ANSWER TO A QUESTION DROPS THE OLDER ONE STILL WAITING THERE: A is no longer kept, B is");
  check((await kept()).some((i) => i.number === 3), "CONTROL: an answer to another question is kept beside it");
  await snap({ through: envB.header.seq, checked: 1, missing: [envA.header.seq], applied: [idB] });
  await phone.refresh(paired.id);
  clock.now += P.ANSWER_RESEND_MS + 1000;
  const r2 = await phone.resend(paired.id);
  const after2 = await lastAnswer();
  check(after2.body.answerId !== idA && after2.header.seq === envB.header.seq, "A STALE ANSWER IS NEVER SENT AGAIN: with A reported missing and B applied, nothing of A goes out", JSON.stringify({ r2, last: after2.body.text }));

  // THE RE-SIGN KEEPS THE FIRST SIGNING TIME, so the PC can tell an older answer from a newer one.
  const idC = P.hex(P.randomBytes(16));
  await phone.answer(paired.id, { number: 2, wordingVersion: 1, text: "C: lost once.", answerId: idC });
  const envC = await lastAnswer();
  await snap({ through: envC.header.seq + 1, checked: 1, missing: [envC.header.seq], applied: [idB] });
  await phone.refresh(paired.id);
  clock.now += 2 * P.ANSWER_RESEND_MS;
  await phone.resend(paired.id);
  const envC2 = await lastAnswer();
  check(envC2.body.answerId === idC && envC2.header.seq > envC.header.seq && envC2.header.ts === envC.header.ts, "AN ANSWER SIGNED AGAIN CARRIES THE TIME IT WAS FIRST SIGNED: a new envelope, a new seq, the old time", JSON.stringify({ first: envC.header.ts, again: envC2.header.ts }));

  // S4: one prompt a refresh; none while hidden; none without the lock; recovery says why.
  const idD = P.hex(P.randomBytes(16));
  const idE = P.hex(P.randomBytes(16));
  await phone.answer(paired.id, { number: 1, wordingVersion: 1, text: "D: lost.", answerId: idD });
  const envD = await lastAnswer();
  await phone.answer(paired.id, { number: 3, wordingVersion: 1, text: "E: lost.", answerId: idE });
  const envE = await lastAnswer();
  await snap({ through: envE.header.seq + 1, checked: 1, missing: [envD.header.seq, envE.header.seq], applied: [idB, idC] });
  clock.now += 2 * P.ANSWER_RESEND_MS;
  let visible = false;
  let held = true;
  const bridge = createBridge(phone, { loadKinds: async () => ({}), visible: () => visible, lock: (name, fn) => fn(held) });
  await bridge.request("pick", { id: paired.id });
  const p0 = prompts;
  await bridge.request("refresh");
  check(prompts === p0 && (await lastAnswer()).header.seq === envE.header.seq + 0, "HIDDEN, THE PAGE SIGNS NOTHING AGAIN: no passkey prompt while he cannot see it", String(prompts - p0));
  visible = true; held = false;
  await bridge.request("refresh");
  check(prompts === p0, "nor while another window of the app holds the lock");
  held = true;
  await bridge.request("refresh");
  const one = prompts - p0;
  await bridge.request("refresh");
  const two = prompts - p0;
  check(one === 1 && two === 2, "two answers missing at once cost ONE prompt a refresh, never two at once", JSON.stringify({ one, two }));
  const idF = P.hex(P.randomBytes(16));
  await phone.answer(paired.id, { number: 2, wordingVersion: 1, text: "F: lost.", answerId: idF });
  const envF = await lastAnswer();
  await snap({ through: envF.header.seq + 1, checked: 1, missing: [envF.header.seq], applied: [idB, idC, idD, idE] });
  phone.lock(paired.id);
  await phone.recover(paired.id, paired.recoveryCode);
  await phone.refresh(paired.id);
  clock.now += 2 * P.ANSWER_RESEND_MS;
  const ro = await phone.resend(paired.id);
  check(ro.resent === 0 && ro.problems.some((x) => x.indexOf("recovery code") >= 0 && x.indexOf("cannot sign") >= 0), "A RECOVERY SESSION SAYS IT CANNOT SEND AGAIN what the PC is missing", JSON.stringify(ro));
  await phone.unlock(paired.id);
  await phone.refresh(paired.id);

  // S1: received for hours and never listed: signed again once, and only once.
  const idG = P.hex(P.randomBytes(16));
  await phone.answer(paired.id, { number: 3, wordingVersion: 1, text: "G: received, never listed.", answerId: idG });
  const envG = await lastAnswer();
  await snap({ through: envG.header.seq, checked: 1, missing: [], applied: [idB, idC, idD, idE, idF] });
  await phone.refresh(paired.id);
  clock.now += P.ANSWER_STUCK_MS + P.ANSWER_RESEND_MS;
  const s1 = await phone.resend(paired.id);
  const envG2 = await lastAnswer();
  clock.now += 2 * P.ANSWER_RESEND_MS;
  const s1b = await phone.resend(paired.id);
  check(s1.resent === 1 && envG2.body.answerId === idG && envG2.header.seq > envG.header.seq && s1b.resent === 0, "AN ANSWER RECEIVED FOR HOURS AND NEVER LISTED IS SIGNED AGAIN ONCE - the PC answers it as its record and lists it again - and only once", JSON.stringify({ s1, s1b }));

  // S3: words that cannot be read, and a store that cannot be read, still show the question answered.
  const xs = await kept();
  await mem.put("outbox/" + paired.id, { v: 1, items: xs.map((i) => (i.answerId === idG ? { ...i, sealed: { enc: i.sealed.enc, box: P.b64u(P.randomBytes(40)) } } : i)) });
  const phone2 = make();
  await phone2.unlock(paired.id);
  const bridge2 = createBridge(phone2, { loadKinds: async () => ({}) });
  const rec = await bridge2.request("pick", { id: paired.id });
  const q3 = rec.value.questions.find((q) => q.number === 3).thread.messages.slice(-1)[0];
  check(!!q3 && q3.speaker === "founder" && q3.text === P.ANSWER_UNREADABLE && q3.local === true, "AN ANSWER WHOSE WORDS CANNOT BE READ STILL STANDS: the question shows answered, pending, saying its words cannot be read here", JSON.stringify(q3));
  fails.outbox = true;
  const rec2 = await bridge2.request("refresh");
  fails.outbox = false;
  const q3b = rec2.value.questions.find((q) => q.number === 3).thread.messages.slice(-1)[0];
  check(!!q3b && q3b.speaker === "founder" && q3b.local === true, "A READ OF THE OUTBOX THAT FAILS KEEPS WHAT WAS LAST READ: the question is not emptied", JSON.stringify(q3b));

  // TWO ANSWERS SENT AT ONCE (two windows, or two parts in a row) never share a seq: the one that loses
  // the claim signs again under the next.
  await Promise.all([
    phone.answer(paired.id, { number: 1, wordingVersion: 1, text: "At once, one.", answerId: P.hex(P.randomBytes(16)) }),
    phone.answer(paired.id, { number: 2, wordingVersion: 1, text: "At once, two.", answerId: P.hex(P.randomBytes(16)) })
  ]);
  const both = [];
  for (const it of (await t.get(m.mailbox, 0, 256)).value.items) { const o = await machineOpens(m, it.text); if (o.header.channel === "decisions" && o.body.text.startsWith("At once")) both.push(o.header.seq); }
  check(both.length === 2 && both[0] !== both[1], "two answers signed at the same moment go under two seqs, never one", JSON.stringify(both));
  // AN OUTBOX THAT HOLDS TWO ANSWERS TO ONE QUESTION (kept by an earlier build) sends the older one never.
  await mem.put("outbox/" + paired.id, { v: 1, items: [
    { answerId: P.hex(P.randomBytes(16)), number: 2, part: "", wordingVersion: 1, snapshot: "x", sealed: { enc: "", box: "" }, seqs: [900], envelope: { key: "old", text: "old" }, signedAt: 1, sentAt: 1, lastSentAt: 1, lastResendAt: 0 },
    { answerId: P.hex(P.randomBytes(16)), number: 2, part: "", wordingVersion: 1, snapshot: "x", sealed: { enc: "", box: "" }, seqs: [901], envelope: { key: "new", text: "new" }, signedAt: 2, sentAt: clock.now, lastSentAt: clock.now, lastResendAt: 0 }
  ] });
  await snap({ through: 901, checked: 1, missing: [900] });
  await phone.refresh(paired.id);
  const legacy = await phone.resend(paired.id);
  check(legacy.resent === 0 && legacy.problems.length === 0, "an older answer to a question that has a newer one waiting is never sent again, even from an outbox that holds both", JSON.stringify(legacy));

  // THE OUTBOX NEVER DROPS AN UNCONFIRMED ANSWER TO MAKE ROOM: full, a new answer is not sent.
  const filler = []; for (let i = 0; i < 200; i++) filler.push({ answerId: P.hex(P.randomBytes(16)), number: 1000 + i, part: "", wordingVersion: 1, snapshot: "x", sealed: { enc: "", box: "" }, seqs: [1], envelope: { key: "k" + i, text: "t" }, signedAt: 1, sentAt: clock.now, lastSentAt: clock.now, lastResendAt: 0 });
  await mem.put("outbox/" + paired.id, { v: 1, items: filler });
  const headBefore = (await t.get(m.mailbox, 0, 256)).value.items.length;
  const full = await throwsAsync(async () => phone.answer(paired.id, { number: 2, wordingVersion: 1, text: "One too many.", answerId: P.hex(P.randomBytes(16)) }));
  check(full.indexOf("Not sent") >= 0 && (await t.get(m.mailbox, 0, 256)).value.items.length === headBefore && (await kept()).length === 200, "A FULL OUTBOX REFUSES THE NEW ANSWER, saying why, and drops none of the 200 still waiting", full);
}

// --- 10i. THE CHAT OPENS AT ITS NEWEST MESSAGE, AND JUMP TO LATEST (chat-scroll.js; the founder, 2026-10-15) ---
{
  const at = (scrollTop) => ({ scrollTop, viewHeight: 800, scrollHeight: 5000 });
  check(CS.distanceFromBottom(at(4200)) === 0 && CS.distanceFromBottom(at(4100)) === 100 && CS.distanceFromBottom({ scrollTop: 0, viewHeight: 800, scrollHeight: 300 }) === 0, "how far the window stands above the bottom; a page shorter than the screen is at its bottom");
  check(CS.STICK_PX === 48, "the stick threshold is 48 px", String(CS.STICK_PX));
  check(CS.nearBottom(at(4200)) && CS.nearBottom(at(4200 - 48)) && !CS.nearBottom(at(4200 - 49)), "AT THE BOTTOM means within 48 px of it, and 49 px up is away", JSON.stringify([CS.nearBottom(at(4152)), CS.nearBottom(at(4151))]));
  check(!CS.showJump(at(4200)) && !CS.showJump(at(4152)) && CS.showJump(at(4151)) && CS.showJump(at(0)), "JUMP TO LATEST HIDES AT THE BOTTOM, and shows away from it");
  check(CS.placeAfterDraw({ opening: true, near: false }) === "bottom", "AN OPENING GOES TO THE NEWEST MESSAGE, wherever the window stood");
  check(CS.placeAfterDraw({ opening: false, near: true }) === "bottom", "A REFRESH AT THE BOTTOM STICKS TO THE BOTTOM");
  check(CS.placeAfterDraw({ opening: false, near: false }) === "keep", "A REFRESH WHILE HE READS BACK KEEPS HIS PLACE");
  check(CS.keptTop(1000, 120, 120) === 1000 && CS.keptTop(1000, 120, 220) === 1100 && CS.keptTop(1000, 120, 70) === 950 && CS.keptTop(10, 120, 0) === 0, "his place kept: the window moves by what the first message on his screen moved, never above the top");
  const seen = new Set(["a", "b", "c"]);
  check(CS.unseenCount(seen, ["a", "b", "c"]) === 0 && CS.unseenCount(seen, ["a", "b", "c", "d", "e"]) === 2 && CS.unseenCount(new Set(), []) === 0, "the new messages are the ones not seen at the bottom");
  check(CS.jumpWords(0) === "Jump to latest" && CS.jumpWords(2) === "Jump to latest (2 new)" && CS.jumpWords(1) === "Jump to latest (1 new)", "the button's words, with the count of new messages when there are any");
  check(CS.newsWords(0, 2) === "2 new messages below. Jump to latest to read them." && CS.newsWords(2, 3) === "3 new messages below. Jump to latest to read them." && CS.newsWords(0, 1) === "1 new message below. Jump to latest to read it.", "the live region says the count when it grows");
  check(CS.newsWords(2, 2) === null && CS.newsWords(3, 0) === null && CS.newsWords(0, 0) === null, "A REFRESH THAT BRINGS NOTHING SAYS NOTHING: the live region is left as it is");
}

process.stdout.write("[DONE] " + failures + "\n");
process.exit(0);
