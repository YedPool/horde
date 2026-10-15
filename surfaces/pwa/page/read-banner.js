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
//   signed-out   the relay answered the read 401 or 403, or the relay's session says he is not signed in
//   unreachable  any other failed read: the relay could not be reached, or answered nonsense

export const READ_WORDS = {
  "signed-out": "Not signed in to the relay - sign in again",
  unreachable: "Cannot reach the relay",
  locked: "This horde is locked - unlock to read"
};

// The kind of failure, or "" when the last read was good.
//   read     the bridge's read-changed record: { locked, relayDown, said: [the relay's words] }
//   session  the relay's session answer (account-client.js session()), or null when there are no accounts
export function readFailure(read, session = null) {
  if (!read) return "";
  if (read.locked === true) return "locked";
  if (read.relayDown !== true) return "";
  const said = Array.isArray(read.said) ? read.said.join(" ") : "";
  if (/ with 40[13]\b/.test(said)) return "signed-out";
  if (session && (session.status === 401 || session.status === 403 || (session.state === "known" && session.value && session.value.signedIn !== true))) return "signed-out";
  return "unreachable";
}

// The banner for a kind, with the time of the last good read (timeText turns it into his local time), or
// "" for none.
export function readBanner(kind, lastGoodAt, timeText) {
  const words = READ_WORDS[kind];
  if (!words) return "";
  const when = lastGoodAt > 0 && typeof timeText === "function" ? timeText(lastGoodAt) : "";
  return words + "." + (when ? " Last updated " + when + "." : "");
}
