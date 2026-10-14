// relays/cloudflare/worker/metrics-book.js - WHAT THE METRICS OBJECT KEEPS AND HOW (metrics-store.js is
// the Durable Object around it): rows added from the isolates' batches, the day's summary, and the daily
// deletion of what is older than the retention. Over a storage of the Durable Object storage API's shape
// (get, put, list, delete, getAlarm, setAlarm), so a unit test runs it over one in memory.
//
// STORAGE, one entry a row, every key built from metrics.js's fixed lists:
//   r:<hour>|<route>|<kind>|<outcome>   a request row's counters (metrics.js, COUNTERS and LATENCY)
//   a:<hour>|<account hash>             an account's counters for the hour
//   o:<hour>                            THE METRICS OBJECT'S OWN LINE: its own calls in that hour -
//                                       flushes taken, increments they carried, alarms run, summaries
//                                       read, rows deleted - so its cost is measured, not only reckoned
//                                       (the design note, "Its own cost")
// Keys sort by hour within each prefix, so a day is one range and "older than the retention" another.
//
// IT TOUCHES NOTHING ELSE: no account, no mailbox, no relay-wide budget (relay-budget.js). It is asked by
// the isolates' flushes (metrics-request.js) and by the summary (metrics-api.js), and by nothing on a
// user's path, so it can never refuse or slow a user's request.
import { DAY_MS } from "./throttle.js";
import { METRICS, hourOf, cutoffHourOf, batchOrNull, rowPartsOf, accountPartsOf, addCounters, addAccountCounters, addOwnCounters } from "./metrics.js";

const ROW = "r:";
const ACCOUNT = "a:";
const OWN = "o:";
// The storage API reads, writes and deletes at most 128 keys in one call.
const BATCH = 128;

function chunks(list) {
  const out = [];
  for (let i = 0; i < list.length; i += BATCH) out.push(list.slice(i, i + BATCH));
  return out;
}

export class MetricsBook {
  constructor(storage) { this.storage = storage; }

  // Add to the counters under prefix: entries [[key, counters]], summed with what is stored by sum.
  async addAll(prefix, entries, sum) {
    for (const part of chunks(entries)) {
      const keys = part.map(([k]) => prefix + k);
      const held = await this.storage.get(keys);
      const out = {};
      for (const [k, c] of part) out[prefix + k] = sum(held.get(prefix + k), c);
      await this.storage.put(out);
    }
  }

  async own(now, add) {
    const key = OWN + hourOf(now);
    await this.storage.put(key, addOwnCounters(await this.storage.get(key), add));
  }

  // The daily alarm is set by the first flush and set again by each alarm: one wake a day.
  async keepAlarm(now) {
    if ((await this.storage.getAlarm()) === null) await this.storage.setAlarm(now + DAY_MS);
  }

  // One isolate's batch (metrics.js, Recorder): true when it was taken. A batch that is not one is
  // refused whole. failFlush (a test's only) refuses it as a broken object would.
  async add(batch, { now, failFlush = 0 } = {}) {
    if (failFlush) throw new Error("the metrics object refuses flushes (test)");
    const b = batchOrNull(batch);
    if (!b) return false;
    // Duplicate keys in one batch are summed, not overwritten: a batch is built from a Map, but the
    // object does not take the isolate's word for it.
    const rows = new Map();
    for (const [k, c] of b.rows) rows.set(k, addCounters(rows.get(k), c));
    const accounts = new Map();
    for (const [k, c] of b.accounts) accounts.set(k, addAccountCounters(accounts.get(k), c));
    await this.addAll(ROW, [...rows.entries()], addCounters);
    await this.addAll(ACCOUNT, [...accounts.entries()], addAccountCounters);
    await this.own(now, { flushes: 1, increments: b.increments });
    await this.keepAlarm(now);
    return true;
  }

  async listDay(prefix, day) { return this.storage.list({ start: prefix + day + "T", end: prefix + day + "U" }); }

  // The summary of day ("YYYY-MM-DD", checked by the caller): { requests, accounts, own } - or, for one
  // account (hash), only that account's hours. Counted as a summary read on the own line.
  async summary(day, { now, account = null } = {}) {
    await this.own(now, { summaryReads: 1 });
    const accounts = [];
    for (const [k, c] of await this.listDay(ACCOUNT, day)) {
      const p = accountPartsOf(k.slice(ACCOUNT.length));
      if (!p || (account !== null && p.account !== account)) continue;
      accounts.push({ hour: p.hour, account: p.account, ...addAccountCounters(null, c) });
    }
    if (account !== null) return { accounts };
    const requests = [];
    for (const [k, c] of await this.listDay(ROW, day)) {
      const p = rowPartsOf(k.slice(ROW.length));
      if (p) requests.push({ ...p, ...addCounters(null, c) });
    }
    const own = [];
    for (const [k, c] of await this.listDay(OWN, day)) {
      own.push({ hour: k.slice(OWN.length), ...addOwnCounters(null, c) });
    }
    return { requests, accounts, own };
  }

  // The daily alarm: every row of an hour older than retentionDays is deleted, then the next alarm set.
  async alarm({ now, retentionDays = METRICS.retentionDays } = {}) {
    const cutoff = cutoffHourOf(now, retentionDays);
    let deleted = 0;
    for (const prefix of [ROW, ACCOUNT, OWN]) {
      const old = [...(await this.storage.list({ start: prefix, end: prefix + cutoff })).keys()];
      for (const part of chunks(old)) deleted += await this.storage.delete(part);
    }
    await this.own(now, { alarms: 1, rowsDeleted: deleted });
    await this.storage.setAlarm(now + DAY_MS);
    return deleted;
  }
}
