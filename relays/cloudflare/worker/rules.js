// relays/cloudflare/worker/rules.js - what the Worker holds every request to, each rule taken from the
// one place it is written and none of them copied here (SSOT).
//
//   - THE PORT'S RULES for a mailbox, a key and a text (relays/Port.ps1) come from the phone's relay
//     client, the one copy of them in JavaScript (surfaces/pwa/page/relay-client.js): the same words
//     refuse the same input on the phone, at the machine and here.
//   - THIS RELAY'S LIMITS come from capabilities.json beside this folder, the file relays/Port.ps1 reads
//     when the adapter registers. maxTextChars is 64 KiB (65536): the channels size their envelopes by
//     it (channels/Port.ps1, Get-HordeRelayChannelBodyBudget), so a lower cap here is honoured by every
//     sender, and a Durable Object keeps one value of that size with room to spare.
//
// The relay never opens a text: every rule here is about the outside of an item.
import { mailboxProblem, keyProblem, textProblem, LIMITS } from "../../../surfaces/pwa/page/relay-client.js";
import capabilities from "../capabilities.json";

export { mailboxProblem, keyProblem };
export const MAX_TEXT_CHARS = capabilities.limits.maxTextChars;
export const MAX_BATCH = capabilities.limits.maxBatch;
export const MAX_WATCH_MS = capabilities.limits.maxWatchMs;
export const SEQ_MAX = LIMITS.seqMax;
// THE MOST ITEM TEXT ONE ANSWER CARRIES. A watch answers in one WebSocket message, and a Worker's
// WebSocket message is at most 1 MiB (1048576 bytes); a full batch of 256 items of 64 KiB is 16 MiB.
// So an answer stops before the item that would take its texts past a million characters - leaving
// 48576 for the JSON around them, which is 190 for each of 256 items, more than a seq, a 160-character
// key and the punctuation take - and always carries at least one item, so a reader is never stuck.
// The port takes fewer items than it asked for and reads on from its cursor (relays/Port.ps1). A read
// keeps the same budget, so the two answer alike.
export const BATCH_CHARS = 1000000;
// THE BODY CAP: the longest put body there can be - a text of maxTextChars in which every character is
// a quote or a backslash, so JSON writes each as two - and 1024 for the key and the punctuation. A body
// past it is refused before it is all read (body.js), by the API and by a machine's signature check.
export const BODY_BYTES = 2 * MAX_TEXT_CHARS + 1024;

export function itemTextProblem(text) { return textProblem(text, MAX_TEXT_CHARS); }

// A whole number written in digits only, from 0 to max, or null. "007", "1e3", "-1", " 1" and "" are
// not numbers here: the port never writes them, and a parser that took them would make two spellings
// of one cursor.
export function wholeOf(text, max) {
  if (typeof text !== "string" || !/^(0|[1-9][0-9]{0,15})$/.test(text)) return null;
  const n = Number(text);
  return Number.isSafeInteger(n) && n <= max ? n : null;
}
