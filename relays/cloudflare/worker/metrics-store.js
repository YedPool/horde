// relays/cloudflare/worker/metrics-store.js - THE METRICS OBJECT: one Durable Object for the whole relay
// (named "relay/metrics"), holding the request metrics the isolates flush to it (metrics.js,
// metrics-request.js). What it keeps and how is metrics-book.js's; this is the object around it.
//
// ONE OBJECT, CALLED RARELY: each isolate flushes to it at most once in five minutes or once in 500
// requests (metrics.js, METRICS), so a quiet relay of two to four isolates calls it 600 to 1,200 times a
// day - about one percent of the free plan's 100,000 requests - plus one alarm a day and one summary
// read a day. Its own calls are counted on a line of their own (metrics-book.js, the own line), so the
// one percent is checked against the real number from the first summary.
import { DurableObject } from "cloudflare:workers";
import { MetricsBook } from "./metrics-book.js";

export class Metrics extends DurableObject {
  // A batch from an isolate: true when taken. opts.failFlush is a test's only (metrics.js, THE SETTINGS).
  async add(batch, opts) {
    return new MetricsBook(this.ctx.storage).add(batch, { now: Date.now(), failFlush: opts && opts.failFlush ? 1 : 0 });
  }

  // The summary of a day, whole or for one account hash (metrics-book.js, summary).
  async summary({ day, account }) {
    return new MetricsBook(this.ctx.storage).summary(day, { now: Date.now(), account: typeof account === "string" ? account : null });
  }

  async alarm() {
    await new MetricsBook(this.ctx.storage).alarm({ now: Date.now() });
  }
}
