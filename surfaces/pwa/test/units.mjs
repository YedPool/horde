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
const { memoryStore } = await load("app/store.js");
const { createBridge } = await load("surface/bridge.js");
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
function offerText(m, { rpId = "relay.example.test", origins = ["https://relay.example.test"], expiresAt = Date.now() + 300000, mailbox = m.mailbox, agreeKeyId = m.agreeKeyId } = {}) {
  return '{"v":1,"kind":"horde-relay-pairing-offer","horde":"' + m.horde + '","offer":"' + P.hex(P.randomBytes(16)) + '","code":"' + P.b64u(P.randomBytes(16)) + '","machine":"' + m.keyId +
    '","signPublic":"' + P.b64u(m.signPublic) + '","agreeKeyId":"' + agreeKeyId + '","agreePublic":"' + P.b64u(m.agreePublic) + '","mailbox":"' + mailbox + '","rpId":"' + rpId +
    '","origins":[' + origins.map((o) => '"' + o + '"').join(",") + '],"issuedAt":' + (expiresAt - 300000) + ',"expiresAt":' + expiresAt + "}";
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
function snapshotPages(m, questions, { pages = 1, hash = P.hex(P.randomBytes(32)) } = {}) {
  const out = [];
  const per = Math.ceil(questions.length / pages) || 1;
  for (let i = 0; i < pages; i++) {
    const qs = questions.slice(i * per, (i + 1) * per);
    out.push(P.utf8(JSON.stringify({ v: 1, kind: "decisions-snapshot", horde: m.horde, machine: m.keyId, snapshot: hash, page: i + 1, pages, questions: qs, withheld: [], counts: { open: questions.length }, unreadable: 0, notUnderstood: 0 })));
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
  const e = JSON.parse(text);
  const ht = P.headerText(e.header);
  const aad = P.utf8("horde-relay/envelope/v1 aad\n" + ht);
  const r = e.recipients.find((x) => x.kid === m.agreeKeyId);
  const cek = await P.hpkeOpen(m.agree.privateKey, m.agreePublic, P.unb64u(r.enc), P.utf8("horde-relay/envelope/v1 content-key"), aad, P.unb64u(r.key));
  return { header: e.header, sig: e.sig, body: JSON.parse(P.fromUtf8(await P.gcmOpen(cek, P.unhex(e.header.nonce), aad, P.unb64u(e.ct)))) };
}
async function phoneKeyOf(transport, m) {
  // The phone's announcement, as the trust channel reads it: the agreement key it vouched for.
  const r = await transport.get(m.mailbox, 0, 256);
  for (const it of r.value.items) { const o = await machineOpens(m, it.text); if (o.header.channel === "trust") return P.unb64u(o.body.agreePublic); }
  return null;
}

const origin = "https://relay.example.test";
function newApp(transport, { prf = true, store = memoryStore(), authenticator = null } = {}) {
  const auth = authenticator || softAuthenticator({ origin, prf });
  return { store, auth, phone: createPhone({ store, authenticator: auth, relay: R.createRelayClient(transport), origin }) };
}
async function pairedApp(transport, m, opts = {}) {
  const app = newApp(transport, opts);
  const paired = await app.phone.pair({ offerText: offerText(m), label: "Founder phone" });
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
  check((await throwsAsync(() => P.hpkeOpen(skR, P.unhex(v.pkRm), P.unhex(v.enc), P.unhex(v.info), bad, P.unhex(e0.ct)))) !== "", "and refuses other additional data");
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
  check((await P.readOffer(offerText(m))).ok, "a machine's offer reads");
  check(!(await P.readOffer(offerText(m, { expiresAt: Date.now() - 1 }))).ok, "an expired offer is refused");
  check(!(await P.readOffer(offerText(m, { mailbox: "work/other" }))).ok, "an offer whose mailbox is not its horde and machine is refused");
  check(!(await P.readOffer(offerText(m, { agreeKeyId: "0".repeat(32) }))).ok, "an offer whose agreement key is not the one it names is refused");
  check(!(await P.readOffer(offerText(m).replace('{"v":1,', '{"v":1,"extra":1,'))).ok, "an offer with a member added is refused");
  const app = newApp(R.memoryTransport());
  check((await throwsAsync(() => app.phone.pair({ offerText: offerText(m, { origins: ["https://other.example.test"], rpId: "other.example.test" }), label: "x" }))).indexOf("not this app") >= 0, "an offer for another app's origin is refused before a passkey is made");
  check((await throwsAsync(() => app.phone.pair({ offerText: offerText(m), label: 'say "hi"' }))).indexOf("name this phone") >= 0, "a label the machine would refuse is refused first");
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
  const pw = await a.phone.pair({ offerText: offerText(work), label: "Founder phone" });
  await a.phone.announce(pw.id);
  const pp = await a.phone.pair({ offerText: offerText(personal), label: "Founder phone" });
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
  for (const it of (await t.get(m.mailbox, 0, 256)).value.items) seqs.push((await machineOpens(m, it.text)).header);
  check(seqs.filter((h) => h.channel === "decisions").map((h) => h.seq).join(",") === "1,2" && seqs.filter((h) => h.channel === "trust").map((h) => h.seq).join(",") === "1", "each channel counts its own sequence, from 1 and up by one", JSON.stringify(seqs.map((h) => h.channel + h.seq)));
  check((await throwsAsync(() => a.phone.answer(a.paired.id, { number: 5, wordingVersion: 1, text: "x", answerId: id }))).indexOf("not in the snapshot") >= 0, "a question not in the snapshot on screen is not answered");
  // The recovery code: read, never answer.
  const code = a.paired.recoveryCode;
  a.phone.lock(a.paired.id);
  check((await throwsAsync(() => a.phone.answer(a.paired.id, { number: 4, wordingVersion: 2, text: "x", answerId: id }))).indexOf("locked") >= 0, "a locked horde answers nothing");
  await a.phone.recover(a.paired.id, code);
  check((await a.phone.refresh(a.paired.id)).questions.length === 1, "the recovery code unlocks to read");
  const before = (await t.get(m.mailbox, 0, 256)).value.items.length;
  check((await throwsAsync(() => a.phone.answer(a.paired.id, { number: 4, wordingVersion: 2, text: "x", answerId: id }))).indexOf("Read only") >= 0 && (await t.get(m.mailbox, 0, 256)).value.items.length === before, "and refuses to answer, sending nothing");
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
  const why = await throwsAsync(() => a.phone.answer(a.paired.id, { number: 1, wordingVersion: 1, text: "Yes.", answerId: P.hex(P.randomBytes(16)) }));
  check(why.indexOf("no PRF") >= 0 && why.indexOf("Read only") >= 0 && (await t.get(m.mailbox, 0, 256)).value.items.length === before, "an answer is refused in plain words, and nothing is sent", why);
  const b = createPhone({ store: a.store, authenticator: a.auth, relay: R.createRelayClient(t), origin });
  const un = await throwsAsync(() => b.unlock(a.paired.id));
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
  check(r.value.anomalies.some((x) => x.indexOf("gap") >= 0) && r.value.anomalies.length >= 4, "each drop and the gap are reported");
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
  check((await throwsAsync(() => bridge.request("report", {}))).indexOf("not a request") >= 0 && (await throwsAsync(() => bridge.request("__proto__", {}))).indexOf("not a request") >= 0, "a request off the list, a prototype's name included, is refused");
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
  const good = offerText(m);
  const badCode = good.replace(/"code":"[^"]*"/, '"code":"x\\",\\"prf\\":true,\\"label\\":\\"Evil"');
  const badOffer = good.replace(/"offer":"[^"]*"/, '"offer":{"nested":1}');
  const shortOffer = good.replace(/"offer":"[^"]*"/, '"offer":"abc"');
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
  check(v.diagnostics.length === 1 && v.diagnostics[0].indexOf("the relay said: ") === 0 && v.diagnostics[0].length <= 216, "they are kept for diagnosis only, labelled as the relay's and cut short", JSON.stringify(v.diagnostics));
  const why = await throwsAsync(() => b.announce(a.paired.id));
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
  const why = await throwsAsync(() => a.phone.answer(a.paired.id, { number: 4, wordingVersion: 7, text: "Yes.", answerId: P.hex(P.randomBytes(16)) }));
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
  check((await throwsAsync(() => a.phone.sendLine(a.paired.id, { text: "hello", messageId: P.hex(P.randomBytes(16)) }))).indexOf("no session") >= 0, "with no session heard of, a line is refused before anything is signed");
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
  // The receipt, a forged code, and the line coming back as a user turn.
  await sendChat(t, m, a.phoneKey, receiptBody(m, "sess-1", mid, "held", "your-account-expired", "carry on"), "receipt");
  await a.phone.refresh(a.paired.id);
  c = await a.phone.chat(a.paired.id);
  check(c.items.find((x) => x.kind === "line").words === P.CHAT_SENDING, "a receipt with a code the phone does not know is not shown: no word of the machine's reaches the screen");
  await sendChat(t, m, a.phoneKey, receiptBody(m, "sess-1", mid, "accepted", "delivered", "carry on"), "receipt");
  await sendChat(t, m, a.phoneKey, chatBody(m, "sess-1", [turn("t4", "user", "FOUNDER LINE from the phone " + P.lineMarker(mid) + "\n\ncarry on"), turn("t5", "assistant", "on it")]));
  await a.phone.refresh(a.paired.id);
  c = await a.phone.chat(a.paired.id);
  const lines = c.items.filter((x) => x.kind === "line");
  check(lines.length === 1 && lines[0].words === P.CHAT_WORDS.accepted.delivered, "the receipt's code is shown in the phone's own fixed words", JSON.stringify(lines));
  check(!c.items.some((x) => x.kind === "turn" && x.text.indexOf(P.lineMarker(mid)) >= 0) && c.items.some((x) => x.text === "on it"), "his line coming back as a user turn is shown once, as his line; the Thrall's reply is shown");
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
  // Read only: the recovery code reads the chat and never writes to it.
  b.lock(a.paired.id);
  await b.recover(a.paired.id, a.paired.recoveryCode);
  await b.refresh(a.paired.id);
  const headBefore = (await t.get(m.mailbox, 0, 256)).value.items.length;
  const viaCode = await throwsAsync(() => b.sendLine(a.paired.id, { text: "from the recovery code", messageId: P.hex(P.randomBytes(16)) }));
  check(viaCode.indexOf("recovery code") >= 0 && (await t.get(m.mailbox, 0, 256)).value.items.length === headBefore && (await b.chat(a.paired.id)).items.length > 0, "unlocked by the recovery code, the chat is read and a line is refused in words, nothing put", viaCode);
  b.lock(a.paired.id);
  check((await throwsAsync(() => b.chat(a.paired.id))).indexOf("locked") >= 0, "a locked horde shows no chat");
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
  const why = await throwsAsync(() => a.phone.sendLine(a.paired.id, { text: "from a read-only phone", messageId: P.hex(P.randomBytes(16)) }));
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

process.stdout.write("[DONE] " + failures + "\n");
process.exit(0);
