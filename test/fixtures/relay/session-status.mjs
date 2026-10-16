// The phone's reading of a snapshot's receipts for test/test-relay-sessions.ps1: relay/js/protocol.js's
// own sessionStatus over the receipts text the PC wrote, for each passkey asked about. Nothing here is
// PowerShell's.
//
//   node session-status.mjs <in.json> <out.json>
//
// in   { receipts: <the receipts member, as the PC wrote it>, from: [<passkey key ids>] }
// out  { <key id>: null (a PC from before sessions: sign with the passkey) | { idleMs, vouches, needsPasskey } }
import { readFileSync, writeFileSync } from "node:fs";
import * as P from "../../../relay/js/protocol.js";

const [, , inPath, outPath] = process.argv;
const input = JSON.parse(readFileSync(inPath, "utf8"));
const out = {};
for (const from of input.from) {
  const s = P.sessionStatus(input.receipts, from);
  out[from] = s === null ? null : { idleMs: s.idleMs, vouches: [...s.vouches.entries()].map(([vouchId, state]) => ({ vouchId, state })), needsPasskey: [...s.needsPasskey] };
}
writeFileSync(outPath, JSON.stringify(out));
