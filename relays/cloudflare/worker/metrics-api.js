// relays/cloudflare/worker/metrics-api.js - THE DAY'S SUMMARY, read by a machine once a day:
//
//   GET /v1/metrics/summary?day=YYYY-MM-DD[&scope=relay|account]
//     scope relay    -> 200 { day, scope, requests, accounts, own }   owner machines only
//     scope account  -> 200 { day, scope, account, accounts }         any machine, its own
//     no scope       -> the most the machine may read: relay for an owner's machine, account for any other
//
// WHO MAY READ WHAT. Only a MACHINE, by its signed request (auth.js): a phone, the test principal and
// anyone else are refused 403. THE RELAY-WIDE VIEW - every route, every account's hours, the metrics
// object's own line - only for a machine of an OWNER ACCOUNT, by the relay-wide budget's own rule
// (budget.js, THE OWNERS): an owner by account id (tierOf), or by email when that email is already
// PINNED to this account (relay-budget.js, THE PINS - asked read only, pinnedOwner: a summary pins
// nothing and moves no count; an email not yet pinned to anyone gives its account the account view
// until its first mailbox request pins it). With no owner named,
// nobody is an owner here: the relay-wide view is refused to everyone (the budget's tier "everyone" is
// a share of requests, not a right to read every account's counts). ITS OWN ACCOUNT'S HOURS - count,
// bytes in and out, under its account hash - for any machine.
//
// A SUMMARY CALL IS A REQUEST LIKE ANY OTHER OF THE ACCOUNT'S (review of PR 300, Orc E): with sign-up
// open, any account's machine may ask, so each call goes through the account's gate (accounts.js, admit,
// as a read) and is counted in the account's day and the relay-wide day (budget.js) - a machine cannot
// loop it for free. What metrics never touch is the budget's counts from their OWN calls: the flushes and
// the alarm (metrics-request.js, metrics-book.js). A call is not counted among the request rows
// (metrics-request.js); the object counts the reads that reach it on its own line (summaryReads).
// THE BRAKE: one device asks at most once a summaryEveryMs (a minute) from one isolate - the PC asks once
// a day. It is checked and SET FIRST, before anything is awaited, for every call after authentication,
// whatever then becomes of the call: calls in parallel see the first one's mark, and a refused call
// brakes the next as an answered one does.
//
// WHAT A SUMMARY CAN HOLD is only what metrics.js lets a row hold: an hour, a route, a kind and an outcome
// from their fixed lists, a 16-hex account hash, and whole numbers. The day asked for is a date, checked.
import { answer, refuse, refuseWith, refusalOf, CODES } from "./answers.js";
import { accountOf } from "./accounts.js";
import { ownersOf, tierOf, ownerEmailsOf } from "./budget.js";
import { relayBudgetOf } from "./relay-budget.js";
import { metricsSettingsOf, dayOrNull, accountHashOf, SALT_BINDING } from "./metrics.js";
import { metricsObjectOf, METRICS_SUMMARY_PATH } from "./metrics-request.js";

export { METRICS_SUMMARY_PATH };
// When each device last asked for a summary in this isolate (the header, THE BRAKE). Bounded: oldest
// forgotten.
const lastRead = new Map();
const LAST_READ_MAX = 1024;

// Is who's account an owner (the header, WHO MAY READ WHAT)? By id, or by an email already pinned to it.
async function isOwner(env, who) {
  const owners = ownersOf(env);
  if (tierOf(owners, who.account) === "owner") return true;
  const emails = ownerEmailsOf(owners);
  if (emails.length === 0 || !env.RELAY_BUDGET) return false;
  return (await relayBudgetOf(env).pinnedOwner({ account: who.account, emails })) === true;
}

// THE BRAKE (the header): true when device may ask now, and the mark set for now either way it goes.
function braked(device, now, everyMs) {
  const last = lastRead.get(device);
  if (last !== undefined && now - last < everyMs) return { ok: false, retryAfterMs: everyMs - (now - last) };
  lastRead.delete(device);
  if (lastRead.size >= LAST_READ_MAX) lastRead.delete(lastRead.keys().next().value);
  lastRead.set(device, now);
  return { ok: true };
}

export async function handleMetricsSummary(request, env, url, who, limits) {
  const settings = metricsSettingsOf(env, url);
  const now = Date.now();
  const brake = braked(String((who && who.device) || ""), now, settings.summaryEveryMs);
  if (!brake.ok) return refuseWith(429, CODES.rate, "this device asked for a summary a moment ago: wait", brake.retryAfterMs);
  if (request.method !== "GET") return refuse(405, "the summary is read with GET");
  if (!who || who.kind !== "machine") return refuse(403, "only a registered machine reads the relay's metrics");
  const day = dayOrNull(url.searchParams.get("day"));
  if (day === null) return refuse(400, "day must be a date, YYYY-MM-DD");
  // NO SCOPE ASKED - the PC's one request a day - is the most this machine may read: the relay-wide view
  // for an owner's machine, its own account's for any other. Asked for by name, relay-wide is refused to
  // a machine that is not an owner's.
  const asked = url.searchParams.get("scope");
  if (asked !== null && asked !== "relay" && asked !== "account") return refuse(400, "scope is relay or account");
  // COUNTED as a read of the account's, in its day and the relay's (the header).
  const g = await accountOf(env, who.account).admit({ device: who.device, epoch: who.epoch, op: "get", mailbox: "", now, limits, owners: ownersOf(env) });
  if (!g.ok) return refusalOf(g);
  const owner = asked === "account" ? false : await isOwner(env, who);
  const scope = asked || (owner ? "relay" : "account");
  if (scope === "relay" && !owner) return refuse(403, "only a machine of one of the relay's owner accounts reads the relay-wide metrics; ask with scope=account for your own");
  const m = metricsObjectOf(env);
  if (!m) return refuse(503, "this relay keeps no metrics");
  let account = null;
  if (scope === "account") {
    account = await accountHashOf(env[SALT_BINDING], who.account);
    if (account === null) return refuse(503, "this relay keeps no account metrics: it has no metrics salt");
  }
  const s = await m.summary({ day, account });
  if (scope === "account") return answer(200, { day, scope, account, accounts: s.accounts });
  return answer(200, { day, scope, requests: s.requests, accounts: s.accounts, own: s.own });
}
