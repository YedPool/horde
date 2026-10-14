// relays/cloudflare/worker/metrics-api.js - THE DAY'S SUMMARY, read by a machine once a day:
//
//   GET /v1/metrics/summary?day=YYYY-MM-DD[&scope=relay|account]
//     scope relay    -> 200 { day, scope, requests, accounts, own }   owner machines only
//     scope account  -> 200 { day, scope, account, accounts }         any machine, its own
//     no scope       -> the most the machine may read: relay for an owner's machine, account for any other
//
// WHO MAY READ WHAT. Only a MACHINE, by its signed request (auth.js): a phone, the test principal and
// anyone else are refused 403. THE RELAY-WIDE VIEW - every route, every account's hours, the metrics
// object's own line - only for a machine of an OWNER ACCOUNT, by the owners' list the relay-wide budget
// already reads (budget.js, ownersOf and tierOf: HORDE_RELAY_OWNER_ACCOUNTS). With no owner named,
// nobody is an owner here: the relay-wide view is refused to everyone (the budget's tier "everyone" is
// a share of requests, not a right to read every account's counts). ITS OWN ACCOUNT'S HOURS - count,
// bytes in and out, under its account hash - for any machine.
//
// A SUMMARY READ IS THE METRICS OBJECT'S OWN CALL: it is not one of the account's requests (accounts.js,
// admit, is never asked: metrics never touch a budget), it is not counted among the request rows
// (metrics-request.js), and the object counts it on its own line (summaryReads). So that a machine cannot
// use it to call the object as fast as it likes, one key reads at most once a summaryEveryMs (a minute)
// from one isolate; the PC reads once a day.
//
// WHAT A SUMMARY CAN HOLD is only what metrics.js lets a row hold: an hour, a route, a kind and an outcome
// from their fixed lists, a 16-hex account hash, and whole numbers. The day asked for is a date, checked.
import { answer, refuse, refuseWith, CODES } from "./answers.js";
import { ownersOf, tierOf } from "./budget.js";
import { metricsSettingsOf, dayOrNull, accountHashOf, SALT_BINDING } from "./metrics.js";
import { metricsObjectOf, METRICS_SUMMARY_PATH } from "./metrics-request.js";

export { METRICS_SUMMARY_PATH };
// When each machine key last read a summary from this isolate (the header). Bounded: oldest forgotten.
const lastRead = new Map();
const LAST_READ_MAX = 1024;

export async function handleMetricsSummary(request, env, url, who) {
  if (request.method !== "GET") return refuse(405, "the summary is read with GET");
  if (!who || who.kind !== "machine") return refuse(403, "only a registered machine reads the relay's metrics");
  const day = dayOrNull(url.searchParams.get("day"));
  if (day === null) return refuse(400, "day must be a date, YYYY-MM-DD");
  // NO SCOPE ASKED - the PC's one request a day - is the most this machine may read: the relay-wide view
  // for an owner's machine, its own account's for any other. Asked for by name, relay-wide is refused to
  // a machine that is not an owner's.
  const asked = url.searchParams.get("scope");
  if (asked !== null && asked !== "relay" && asked !== "account") return refuse(400, "scope is relay or account");
  const scope = asked || (tierOf(ownersOf(env), who.account) === "owner" ? "relay" : "account");
  if (scope === "relay" && tierOf(ownersOf(env), who.account) !== "owner") return refuse(403, "only a machine of one of the relay's owner accounts reads the relay-wide metrics; ask with scope=account for your own");
  const settings = metricsSettingsOf(env, url);
  const now = Date.now();
  const last = lastRead.get(who.keyId);
  if (last !== undefined && now - last < settings.summaryEveryMs) return refuseWith(429, CODES.rate, "this machine read a summary a moment ago: wait", settings.summaryEveryMs - (now - last));
  const m = metricsObjectOf(env);
  if (!m) return refuse(503, "this relay keeps no metrics");
  let account = null;
  if (scope === "account") {
    account = await accountHashOf(env[SALT_BINDING], who.account);
    if (account === null) return refuse(503, "this relay keeps no account metrics: it has no metrics salt");
  }
  lastRead.delete(who.keyId);
  if (lastRead.size >= LAST_READ_MAX) lastRead.delete(lastRead.keys().next().value);
  lastRead.set(who.keyId, now);
  const s = await m.summary({ day, account });
  if (scope === "account") return answer(200, { day, scope, account, accounts: s.accounts });
  return answer(200, { day, scope, requests: s.requests, accounts: s.accounts, own: s.own });
}
