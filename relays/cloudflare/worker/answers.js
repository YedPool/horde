// relays/cloudflare/worker/answers.js - how the Worker answers in JSON, success or refusal. A refusal
// is { "error": "<words>" } with its HTTP status; the words are this Worker's own and never quote what
// the request carried, so nothing a caller sent is ever echoed back.
//
// A REFUSAL BY A LIMIT (limits.js) says which, in a code word a client can act on without reading the
// words: { "error": "<words>", "code": "<code>" }, and - for a rate, or a count that will reset - a
// Retry-After header in whole seconds. The codes are CODES below.
export const CODES = Object.freeze({
  rate: "rate-limited",          // 429: a device's, an account's or an address's rate; wait Retry-After
  daily: "daily-limit",          // 429: the account's requests for the UTC day; wait Retry-After
  mailboxFull: "mailbox-full",   // 507: the mailbox holds its most unacked envelopes or characters
  machines: "machines-cap",      // 409: the account has its most machines
  phones: "phones-cap",          // 409: the account has its most phones signed in
  mailboxes: "mailboxes-cap",    // 409: the account has its most mailboxes holding unacked mail
  accountFull: "account-full",   // 507: the account's mailboxes hold its most unacked characters
  gone: "account-gone",          // 401: the account was deleted (its device's request was in flight)
  mailboxGone: "mailbox-gone",   // 410: the mailbox was deleted with its account
  deleting: "account-deleting",  // 409: the account is being deleted; try again once it is gone
  replaced: "watch-replaced"     // a watch's message: a newer watch of the same device took its place
});

export function answer(status, body) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

export function refuse(status, words) {
  return answer(status, { error: words });
}

// A refusal by a limit: { error, code }, with Retry-After when retryAfterMs is given.
export function refuseWith(status, code, words, retryAfterMs = 0) {
  const r = answer(status, { error: words, code });
  if (retryAfterMs > 0) r.headers.set("Retry-After", String(Math.max(1, Math.ceil(retryAfterMs / 1000))));
  return r;
}

// A refusal an object answered ({ status, code, reason, retryAfterMs }), as the Worker's answer.
export function refusalOf(r) { return refuseWith(r.status, r.code, r.reason, r.retryAfterMs || 0); }
