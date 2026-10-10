// The phone app's logic, run under Node for surfaces/pwa/test/test-pwa-phone-e2e.ps1: the very modules
// of a built site (phone-core.js, keywrap.js, relay-client.js, ../surface/bridge.js and
// ../relay/protocol.js, imported from the site folder New-HordePwaSite wrote), with a software passkey
// for the browser's (test/fixtures/relay/phone/soft-passkey.mjs), a store in memory for IndexedDB, and
// a relay transport that reads and writes the local relay's folders on disk - the folder layout of
// relays/local/Relay.ps1 - so a real `horde relay run` on that relay is the machine at the other end.
//
//   node app-phone.mjs <site folder> <relay root> <origin> <prf: on|off>
//
// ONE PROCESS FOR THE WHOLE SCENARIO, as one open page is: the unlocked key lives in its memory between
// steps, exactly as in the browser. The suite writes one JSON command per line to stdin and reads one
// JSON answer per line from stdout: { ok, value } or { ok: false, reason }. Nothing else is printed.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { createInterface } from "node:readline";
import { softAuthenticator } from "../../../test/fixtures/relay/phone/soft-passkey.mjs";
import { folderTransport } from "./folder-relay.mjs";

const [, , siteDir, relayRoot, origin, prfFlag] = process.argv;
const load = (p) => import(pathToFileURL(join(siteDir, p)).href);
const { createPhone } = await load("app/phone-core.js");
const { createRelayClient } = await load("app/relay-client.js");
const { memoryStore } = await load("app/store.js");
const { createBridge } = await load("surface/bridge.js");

// The page, as one object: a store and an authenticator that outlive a reload, and a phone and a
// bridge that do not (a reload drops every unlocked session).
const store = memoryStore();
const authenticator = softAuthenticator({ origin, prf: prfFlag === "on" });
const relay = createRelayClient(folderTransport(relayRoot));
let phone, bridge;
function reload() {
  phone = createPhone({ store, authenticator, relay, origin });
  bridge = createBridge(phone, { loadKinds: async () => JSON.parse(readFileSync(join(siteDir, "list/question-kinds.json"), "utf8")).kinds });
}
reload();

const commands = {
  pair: (c) => phone.pair({ offerText: c.offer, label: c.label }),
  announce: (c) => phone.announce(c.id),
  unlock: (c) => phone.unlock(c.id),
  recover: (c) => phone.recover(c.id, c.code),
  lock: async (c) => { phone.lock(c.id); return true; },
  forget: async (c) => { await phone.forget(c.id); return true; },
  hordes: () => phone.hordes(),
  refresh: (c) => phone.refresh(c.id, { waitMs: c.waitMs || 0 }),
  answer: (c) => phone.answer(c.id, { number: c.number, wordingVersion: c.wordingVersion, text: c.text, answerId: c.answerId }),
  chat: (c) => phone.chat(c.id),
  line: (c) => phone.sendLine(c.id, { text: c.text, messageId: c.messageId }),
  bridge: (c) => bridge.request(c.name, c.args || {}),
  reload: async () => { reload(); return true; },
  // What a person could read in the store: every value, as JSON (CryptoKeys show as {}), for the
  // suite to look for anything decrypted.
  dump: async () => JSON.stringify(await store.list(""))
};

// Every answer is ASCII: anything past it is a \u escape, which the suite's JSON reader turns back.
const ascii = (v) => JSON.stringify(v).replace(/[^\x20-\x7e]/g, (ch) => "\\u" + ch.charCodeAt(0).toString(16).padStart(4, "0"));
const rl = createInterface({ input: process.stdin });
for await (const line of rl) {
  if (!line.trim()) continue;
  let c;
  try { c = JSON.parse(line); } catch (x) { process.stdout.write(ascii({ ok: false, reason: "not JSON" }) + "\n"); continue; }
  if (c.cmd === "exit") break;
  const fn = commands[c.cmd];
  try {
    if (!fn) throw new Error("no such command: " + c.cmd);
    process.stdout.write(ascii({ ok: true, value: await fn(c) }) + "\n");
  } catch (x) { process.stdout.write(ascii({ ok: false, reason: x && x.message ? x.message : String(x), code: x && x.code ? x.code : "" }) + "\n"); }
}
process.exit(0);
