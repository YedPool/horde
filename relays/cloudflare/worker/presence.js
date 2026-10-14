// relays/cloudflare/worker/presence.js - WHEN A MACHINE WAS LAST HEARD FROM, pure: no storage, no clock of
// its own. The account's object (accounts.js) keeps the state these return and hands in the time.
//
// WHY (the founder, 2026-10-14, fix 2 of six): his phone must say when the PC has not been heard from for
// two minutes, so an answer he sends then is not taken for lost. The phone cannot tell that by itself -
// it never talks to the machine, only to this relay - so the relay records it.
//
// WHAT COUNTS AS HEARD: a machine request whose signature this relay VERIFIED (auth.js, machines.js) and
// whose account is still there under its epoch - recorded in the account's gate (accounts.js, admit),
// the one call every authenticated request of a machine already makes, so it costs no Durable Object
// request of its own. A refused signature, a replayed nonce, a stale clock or an unregistered key never
// reaches the gate, so none of them can make a machine look alive. A request the gate then refuses for a
// rate still counts: the machine was there and signed it.
//
// WHEN IT IS WRITTEN. The time is kept in the object's memory on every request, exactly, and written to
// its storage at most once per SEEN_WRITE_MS per machine: a storage write per request would be a write
// per glance of every runner. An eviction loses only the memory, so what storage holds after one is at
// most SEEN_WRITE_MS old. That is inside the phone's margin: an idle runner's watch is 60 s (Relay.ps1,
// the run watch), so a live machine is heard at least every 60 s, plus at most 30 s of a write held back,
// against the phone's 120 s (account-client.js, OFFLINE_AFTER_MS).
//
// WHAT A PHONE IS SHOWN: lastSeenAt to the second (the precision the founder allowed), and only on its own
// account's Account answer (account-api.js), which only a signed-in phone of that account may read
// (auth.js: a machine may not read the account). Nothing else of a request - its op, its mailbox, its
// address, its count - is kept, so the most a phone can learn is when the machine was last heard.
export const SEEN_WRITE_MS = 30000;

// The machine was heard at now. held is { at, wroteAt } from an earlier call, or undefined after an
// eviction. -> { held, write }: the new state, and whether storage must be written with held.at now.
export function noteSeen(held, now) {
  const at = held && held.at > now ? held.at : now;
  const write = !held || now - held.wroteAt >= SEEN_WRITE_MS;
  return { held: { at, wroteAt: write ? now : held.wroteAt }, write };
}

// lastSeenAt as a phone is shown it: the later of memory and storage, cut to the whole second; null for a
// machine never heard from since this was deployed.
export function lastSeenOf(held, stored) {
  const m = held && Number.isSafeInteger(held.at) ? held.at : 0;
  const s = Number.isSafeInteger(stored) ? stored : 0;
  const at = Math.max(m, s);
  return at > 0 ? at - (at % 1000) : null;
}
