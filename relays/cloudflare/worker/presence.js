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
// its storage at most once per SEEN_WRITE_MS per machine. WHAT THAT SAVES, honestly: an idle runner asks
// the relay once per watch, every 60 s or a little more (Relay.ps1, the run watch; a runner's glances
// during the watch are local reads and reach no relay), so each of its requests is past the 30 s and IS
// written - about 58 rows an hour, about 1,400 a day per machine, the same as with no throttle. The
// throttle bounds a BUSY machine, whose puts come seconds apart, to two rows a minute (2,880 a day at
// most) instead of one a request. The reckoning against the account's other writes is in accounts.js.
// THE MARGIN against the phone's 120 s (account-client.js, OFFLINE_AFTER_MS): a live machine is heard
// at least every 60 s when well, and every 105 s at worst while its run backs off (cli/RelayRun.ps1,
// BACKOFF: the watch plus a backoff capped at 45 s). The memory answers exactly; only an eviction
// leaves storage to answer, and what it holds is then at most SEEN_WRITE_MS behind - and for an idle
// runner, 0 behind, every request being written. So a false banner needs a busy machine, then an
// eviction, then a run backing off, all at once; it lasts until the machine's next request.
//
// WHAT A PHONE IS SHOWN: lastSeenAt to the second (the precision the founder allowed), and only on its own
// account's Account answer (account-api.js), which only a signed-in phone of that account may read
// (auth.js: a machine may not read the account). Nothing else of a request - its op, its mailbox, its
// address, its count - is kept, so the most a phone can learn is when the machine was last heard.
export const SEEN_WRITE_MS = 30000;

// The machine was heard at now. held is { at, wroteAt } from an earlier call, or undefined after an
// eviction; stored is what storage holds, read only then. -> { held, write }: the new state, and whether
// storage must be written with held.at now. held.at is never before held's or stored's own time, so
// neither memory nor storage ever moves back.
export function noteSeen(held, now, stored) {
  const before = Math.max(held && Number.isSafeInteger(held.at) ? held.at : 0, Number.isSafeInteger(stored) ? stored : 0);
  const at = before > now ? before : now;
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
