// relays/cloudflare/worker/sessions.js - a signed-in phone's session, SERVER SIDE: one Durable Object per
// session, named by the session's id, holding which account it is and until when. The cookie
// (cookies.js) carries the id and nothing else, so nothing in it can be read, edited or forged into
// another account; a session that ends here - signed out, expired - is over wherever its cookie still is.
//
// A SESSION LIVES SESSION_MS (30 days) from its sign-in, and no longer: no use extends it. A phone
// signs in again after that, which is one tap when Google remembers it. The object deletes its record
// at the end by an alarm, so an abandoned session leaves nothing behind; a read after the end and
// before the alarm answers none all the same. Ending sessions early (account deletion, a lost phone) is
// 8c's; signing out ends this one.
//
// THE ID is 256 random bits, base64url (43 characters).
import { DurableObject } from "cloudflare:workers";
import { b64u, randomBytes } from "../../../relay/js/protocol.js";

export const SESSION_MS = 30 * 24 * 3600 * 1000;
const RECORD = "session";
const ID = /^[A-Za-z0-9_-]{43}$/;

export class Session extends DurableObject {
  // Begin: { account, email, createdAt, expiresAt }.
  async begin(record) {
    await this.ctx.storage.put(RECORD, record);
    await this.ctx.storage.setAlarm(record.expiresAt);
    return true;
  }

  // The record while it lives at now, or null.
  async read(now) {
    const r = await this.ctx.storage.get(RECORD);
    if (!r) return null;
    if (now >= r.expiresAt) { await this.ctx.storage.deleteAll(); return null; }
    return r;
  }

  async end() {
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
    return true;
  }

  async alarm() { await this.ctx.storage.deleteAll(); }
}

export function newSessionId() { return b64u(randomBytes(32)); }

// The session's object, or null for an id that is not one this Worker makes.
export function sessionOf(env, id) {
  if (typeof id !== "string" || !ID.test(id)) return null;
  return env.SESSION.get(env.SESSION.idFromName("session/" + id));
}
