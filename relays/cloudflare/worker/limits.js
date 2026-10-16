// relays/cloudflare/worker/limits.js - THE HOSTED RELAY'S ABUSE LIMITS, one named setting each, with the
// default the founder approved (2026-10-11: the relay is PUBLIC, any Google account may sign up). This is
// the one place each number is written; every object and route reads it from here (SSOT).
//
// OVER A LIMIT IS REFUSED, NEVER DROPPED: the request is answered with its status and a code word
// (answers.js, refuseWith) - 429 for a rate, with Retry-After; 409 for an account's cap; 507 for a full
// mailbox - and nothing the relay already holds is evicted to make room. Unacked mail is never thrown
// away for a newer one; it leaves only by its ack, or by retention.
//
// PER ACCOUNT (accounts.js holds each):
//   machinesPerAccount        10     machines registered to one account
//   phonesPerAccount          5      phones signed in to one account at once (live sessions)
//   pairingsPerHour           10     machine registrations an account may attempt in an hour (one a
//                                    pairing): a bucket of 10, refilled at 10 an hour
//   requestsPerDay            20000  mailbox requests one account's phones and machines make in a UTC
//                                    day. Raised from the 5,000 first approved (coordinator, 2026-10-11):
//                                    an always-on machine's runner is 1,440 a day here (its watch is 60 s:
//                                    relays/cloudflare/Relay.ps1, the run watch), so three of them are
//                                    4,320, about a fifth of it, with room for the phone and the puts.
//                                    The free plan allows 100,000 Worker requests a day in all
//   accountMaxMailboxes       50     mailboxes of one account holding unacked mail at once (a mailbox
//                                    whose reader acked everything, or whose mail expired, is not one)
//   accountMaxChars           100 MiB the characters of unacked text across all of one account's
//                                    mailboxes - so an account cannot spread past a mailbox's own caps
//                                    by naming more mailboxes
// PER MAILBOX (mailbox.js):
//   mailboxMaxItems           2000   unacked envelopes one mailbox holds
//   mailboxMaxChars           20 MiB the characters of their texts (texts are ASCII: a character is a byte)
//   the envelope's own cap, 64 KiB, is capabilities.json's maxTextChars (rules.js): reused, not repeated
// PER DEVICE - a phone's session or a machine's key (accounts.js, in memory):
//   putsPerMinute, putBurst   60, 20   puts: 20 at once, then one a second
//   readsPerMinute, readBurst 120, 40  every other request - reads, watches, acks, the account's
//                                      screen: 40 at once, then two a second
//   one live watch per device in a mailbox: a new watch replaces the old (mailbox.js) - a rule, not a
//   number, so it is not a setting here
// PER CLIENT ADDRESS - the caller's IP, as Cloudflare reports it (client-address.js; address.js):
//   signInStartsPerMinute     10     sign-ins started from one address: 10 at once, then one each 6 s
//   newAccountsPerDay         5      accounts made from one address in a UTC day
//   refusedSignaturesPerMinutePerAddress  30  machine requests from one address whose signature, key
//                                             or nonce was refused: past it, that address is refused
//                                             at once, without a signature check, until it refills
// PER MACHINE KEY (machines.js):
//   refusedSignaturesPerMinutePerKey  10    the same, for one key id from one address - so a forger
//                                           who knows a machine's key id (it names its mailbox)
//                                           cannot lock that machine out from elsewhere
//   noncesPerKey              1000   nonces one key may have in its replay window (two minutes) at
//                                    once; past it a request is refused, and no nonce is ever
//                                    forgotten early (forgetting one would let its request replay)
// JOIN REQUESTS - a new phone asking to join one machine of its account (join.js, the section JOIN
// REQUESTS; the account's are kept by accounts.js, the address's by address.js, both in storage, since
// an hour outlives an idle object's eviction):
//   joinRequestsPerHour       6      join requests one account takes in an hour: a bucket of 6, refilled
//                                    at 6 an hour
//   joinRequestsPerHourPerAddress  6 the same for one client address, across every account
//   joinRequestMs             600000 a pending join request's life, 10 minutes: past it the account's one
//                                    pending slot is free again
//   joinBlockMs               3600000 how long an address whose join request was rejected is refused
//                                    join requests: an hour
// RETENTION (mailbox.js): an unacked envelope is deleted retentionMs after its put. Its value is
// capabilities.json's retentionSeconds (30 days), the relay's declared retention the port reads
// (relays/Port.ps1), so it is not repeated here either. An acked envelope is deleted by its ack, at once.
//
// THE TEST OVERRIDE. A suite cannot send 5000 requests or wait 30 days, so test-bindings.json's
// HORDE_RELAY_TEST_LIMITS may hold {"<name>": <whole number>, ...} over any of these (retentionMs
// included). It is honoured ONLY as the test authenticator and the test provider are (auth.js,
// oidc.js): the binding is there - the production config may never name a HORDE_RELAY_TEST_ binding
// (Wrangler.ps1) - AND the request was made to this machine itself, which a deployed Worker never is.
// A binding that names an unknown setting, or a value that is not a whole number from 1, fails the
// request: a suite that thinks it set a limit and did not would prove nothing.
import { isLoopback } from "./site.js";
import capabilities from "../capabilities.json" with { type: "json" };

export const DEFAULTS = Object.freeze({
  machinesPerAccount: 10,
  phonesPerAccount: 5,
  pairingsPerHour: 10,
  requestsPerDay: 20000,
  accountMaxMailboxes: 50,
  accountMaxChars: 100 * 1024 * 1024,
  mailboxMaxItems: 2000,
  mailboxMaxChars: 20 * 1024 * 1024,
  putsPerMinute: 60,
  putBurst: 20,
  readsPerMinute: 120,
  readBurst: 40,
  signInStartsPerMinute: 10,
  newAccountsPerDay: 5,
  refusedSignaturesPerMinutePerAddress: 30,
  refusedSignaturesPerMinutePerKey: 10,
  noncesPerKey: 1000,
  joinRequestsPerHour: 6,
  joinRequestsPerHourPerAddress: 6,
  joinRequestMs: 600000,
  joinBlockMs: 3600000,
  retentionMs: capabilities.limits.retentionSeconds * 1000
});

const TEST_BINDING = "HORDE_RELAY_TEST_LIMITS";

// The limits this request is held to: the defaults, or - for a local test only (the header) - the
// defaults with the test binding's values over them. Throws on a test binding it cannot read.
export function limitsOf(env, url) {
  const t = env && env[TEST_BINDING];
  if (typeof t !== "string" || !isLoopback(url)) return DEFAULTS;
  let o;
  try { o = JSON.parse(t); } catch (e) { throw new Error(TEST_BINDING + " is not JSON"); }
  if (!o || typeof o !== "object" || Array.isArray(o)) throw new Error(TEST_BINDING + " is not a JSON object");
  const out = { ...DEFAULTS };
  for (const name of Object.keys(o)) {
    if (!Object.prototype.hasOwnProperty.call(DEFAULTS, name)) throw new Error(TEST_BINDING + " names no setting " + name);
    if (!Number.isSafeInteger(o[name]) || o[name] < 1) throw new Error(TEST_BINDING + "'s " + name + " is not a whole number from 1");
    out[name] = o[name];
  }
  return Object.freeze(out);
}
