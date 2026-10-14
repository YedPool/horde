// surfaces/pwa/page/pair-countdown.js - how long the pairing code on the pairing screen still works, in
// plain words, read from the offer's own expiresAt. Pure: app.js puts the words on the page by
// textContent once a second while the pairing screen is up, units.mjs checks them on a fake clock.
//
// WHY (founder decision 2026-10-14, issue #283): twice that day an offer expired while he copied it by
// hand, and nothing on the phone said it had. The machine says its own countdown (cli/RelayPair.ps1, THE
// OFFER'S LIFE); this is the phone's. The time is the phone's clock against the machine's expiresAt, so
// a clock that is off moves it by as much - the relay and the machine still refuse an expired offer by
// their own clocks, so this only ever informs.

export const EXPIRED_WORDS = "This pairing code has expired - ask the PC for a new one.";

// The offer's expiresAt (ms since 1970) from the text in the paste box, or 0 when the text is not an
// offer that says one. Nothing else of the offer is read or trusted here (phone-core.js checks it all
// when the passkey is made).
export function offerExpiresAt(text) {
  let o = null;
  try { o = JSON.parse(String(text || "").trim()); } catch (e) { return 0; }
  if (!o || typeof o !== "object" || o.kind !== "horde-relay-pairing-offer") return 0;
  return Number.isSafeInteger(o.expiresAt) && o.expiresAt > 0 ? o.expiresAt : 0;
}

// What the screen says at -now: "" for no offer, the expired words at or after expiresAt, else the
// time left as minutes and seconds ("Time left to use this pairing code: 9:05").
export function countdownWords(expiresAt, now) {
  if (!(expiresAt > 0)) return "";
  const left = expiresAt - now;
  if (left <= 0) return EXPIRED_WORDS;
  const s = Math.ceil(left / 1000);
  const m = Math.floor(s / 60);
  const r = s % 60;
  return "Time left to use this pairing code: " + m + ":" + (r < 10 ? "0" : "") + r;
}
