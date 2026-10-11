// relays/cloudflare/worker/accounts.js - one account: a Durable Object per account id, holding the list
// of machines registered to it, so a signed-in phone can see and remove them (account-api.js).
//
// AN ACCOUNT ID is "google:" and the id token's sub (jwt.js): the provider's own id for the person,
// never the email. It names the account's mailboxes too (api.js): a mailbox is the account's
// "<horde>/<reader>", so two accounts that both name a horde "work" never meet.
//
// THE LIST IS AN INDEX, the keys' own objects are the truth (machines.js): a request is decided by the
// key's object alone, so a list that missed a key could only fail to show it, never let it in. The API
// claims the key before listing it, and releases the key before unlisting it.
//
// This object is where 8c's account-wide state goes: its caps, its retention, and its deletion.
import { DurableObject } from "cloudflare:workers";

const MACHINE = "m:";

export class Account extends DurableObject {
  async listMachine(entry) { await this.ctx.storage.put(MACHINE + entry.keyId, entry); return true; }
  async unlistMachine(keyId) { return this.ctx.storage.delete(MACHINE + keyId); }
  async machines() {
    const out = [];
    for (const [, entry] of await this.ctx.storage.list({ prefix: MACHINE })) out.push(entry);
    return out;
  }
}

export const ACCOUNT_PREFIX = "google:";
export function accountOf(env, account) { return env.ACCOUNT.get(env.ACCOUNT.idFromName("account/" + account)); }
