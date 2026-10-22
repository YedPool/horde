// The phone's own reader on the EXACT body bytes the PC wrote for one chat receipt (T-0340 round 2).
// Usage: node phone-reads-receipt.mjs <body file> <horde> <machine key id> <kept line text or ->
// Prints one JSON line: { read: readChatReceipt's answer, held: the line chatTimeline draws when the phone
// still holds the line it sent, bare: the line it draws when the phone holds nothing of it }.
import { readFileSync } from "node:fs";
import { readChatReceipt, chatTimeline, utf8 } from "../../../relay/js/protocol.js";

const [file, horde, machine, kept] = process.argv.slice(2);
const bytes = utf8(readFileSync(file, "utf8"));
const read = readChatReceipt(bytes, horde, machine);
const out = { read, held: null, bare: null };
if (read.ok) {
  const r = { ...read.value, seq: 5, ts: 9 };
  const line = (tl) => { const l = tl.find((x) => x.kind === "line"); return l ? { text: l.text, status: l.status, code: l.code, words: l.words, session: l.session, count: tl.length } : null; };
  out.held = line(chatTimeline({ sent: [{ messageId: r.messageId, text: kept, at: 1, session: "kept-session" }], receipts: [r] }));
  out.bare = line(chatTimeline({ receipts: [r] }));
}
process.stdout.write(JSON.stringify(out) + "\n");
