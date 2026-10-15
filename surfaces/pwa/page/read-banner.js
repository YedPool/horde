// surfaces/pwa/page/read-banner.js - the ONE banner the page shows while its reads of the relay fail, so
// it never shows what it last read as if it were current. Pure: the bridge (bridge.js, read-changed)
// says how the last read went, app.js puts the banner on the page by textContent, units.mjs checks it.
//
// WHY (the founder's phone, 2026-10-14: the progress log stopped at 02:36 while six newer entries were
// sent). Before this, a read that failed was said once, as an anomaly, and the very next drawing of the
// list - the old snapshot, kept - took the words away (app.js, render): the page went on showing what it
// last had, with nothing to say it was old. A watch the relay refuses at the socket (an expired sign-in)
// looks to the page like any failed watch, so whether he is still signed in is asked of the relay's
// session (account-client.js) - the read's own words are used when they carry the status.
//
// The cases, from the code's real states:
//   locked       the bridge found the horde locked (phone-core.js, fail code "locked")
//   limited      the relay refused the read by one of its limits, its code word in the reason
//                (relay-client.js, A REFUSAL KEEPS ITS CODE WORD): the relay's day for every account
//                together spent, its unread mail full, this account's own day or caps, a rate. The
//                banner says it in THIS PAGE'S words for that code (LIMIT_WORDS) - as a refused
//                sign-in's code is said (app.js, SIGNIN_REFUSED) - never in the relay's
//   signed-out   the relay answered the read 401 or 403, or the relay's session says he is not signed in
//   unreachable  any other failed read: the relay could not be reached, or answered nonsense
import { refusalCodeOf } from "./relay-client.js";

export const READ_WORDS = {
  limited: "The relay refused the read",
  "signed-out": "Not signed in to the relay - sign in again",
  unreachable: "Cannot reach the relay",
  locked: "This horde is locked - unlock to read"
};

// What a refusal by each of the relay's limits means, in the page's own plain words, by its code word
// (the hosted relay's answers.js names them). A code not here is not a limit this page knows: such a
// read is "unreachable" as before, and a put "did not take it just now".
export const LIMIT_WORDS = {
  "relay-daily-limit": "the relay has used all its requests for today, for all its accounts together. It takes more after midnight UTC; nothing already sent is lost",
  "relay-full": "the relay holds all the unread mail it may, for all its accounts together. Nothing more is taken until some is read; nothing it holds was lost",
  "daily-limit": "this account has made all the requests the relay takes from one account in a day. It takes more after midnight UTC",
  "rate-limited": "this phone asked the relay too often just now. It will try again in a moment",
  "account-full": "this account's mailboxes hold all the unread mail they may. Nothing more is taken until some is read",
  "mailbox-full": "this mailbox holds all the unread mail it may. Nothing more is taken until some is read",
  "mailboxes-cap": "this account has the most mailboxes with unread mail it may. Nothing goes into another until one is read"
};

// The page's words for the limit a reason names, or "" when it names none this page knows.
export function limitWordsOf(reason) {
  const code = refusalCodeOf(reason);
  return Object.prototype.hasOwnProperty.call(LIMIT_WORDS, code) ? LIMIT_WORDS[code] : "";
}

// The page's words for the limit the read was refused by, or "".
function limitOf(read) {
  for (const s of read && Array.isArray(read.said) ? read.said : []) {
    const w = limitWordsOf(s);
    if (w) return w;
  }
  return "";
}

// The kind of failure, or "" when the last read was good.
//   read     the bridge's read-changed record: { locked, relayDown, said: [the relay's words] }
//   session  the relay's session answer (account-client.js session()), or null when there are no accounts
export function readFailure(read, session = null) {
  if (!read) return "";
  if (read.locked === true) return "locked";
  if (read.relayDown !== true) return "";
  const said = Array.isArray(read.said) ? read.said.join(" ") : "";
  if (limitOf(read)) return "limited";
  if (/ with 40[13]\b/.test(said)) return "signed-out";
  if (session && (session.status === 401 || session.status === 403 || (session.state === "known" && session.value && session.value.signedIn !== true))) return "signed-out";
  return "unreachable";
}

// The banner for a kind, with the time of the last good read (timeText turns it into his local time), or
// "" for none. read, the same read-changed record, says which limit a limited read was refused by.
export function readBanner(kind, lastGoodAt, timeText, read = null) {
  const words = READ_WORDS[kind];
  if (!words) return "";
  const when = lastGoodAt > 0 && typeof timeText === "function" ? timeText(lastGoodAt) : "";
  const why = kind === "limited" ? limitOf(read) : "";
  return words + (why ? ": " + why : "") + "." + (when ? " Last updated " + when + "." : "");
}
