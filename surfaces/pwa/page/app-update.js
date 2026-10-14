// surfaces/pwa/page/app-update.js - when a new version of the phone app may take the place of the one
// running: the pure decisions, for app.js to act on and units.mjs to check.
//
// WHY THE PAGE MUST ACT. The worker (sw.js) takes over at once when a deployment changes it (skipWaiting,
// clients.claim), but the page in memory is still the old one: an installed home-screen app on an iPhone
// is rarely closed, so it can run the old app for days. So app.js reloads the page ONCE when a new worker
// takes control - never on the first install (no worker before: the page is already the new one), and
// never over his unsent words (an answer or a chat line typed, a send in flight): then it says
// UPDATE_READY_WORDS and reloads at the next safe moment. And iOS fetches a new sw.js only now and then,
// so the page asks for one (registration.update()) when it is shown, at most once per UPDATE_EVERY_MS.
//
// THE VERSION is the deployment's (surfaces/pwa/Site.ps1 writes it into sw.js and config.json): the page
// knows its own from config.json, and the worker that controls it answers its own when asked.

export const UPDATE_EVERY_MS = 600000;
export const UPDATE_READY_WORDS = "A new version is ready - it loads when you finish.";
const VERSION = /^[0-9a-f]{16}$/;
// Where the decisions document keeps its drafts in the storage it is handed (decisions/page/list.js, DRAFTS_KEY).
export const DRAFTS_KEY = "horde-decisions-drafts-v1";

// "reload", "wait" (unsent words: reload later), or "none".
//   hadController  the page was controlled by a worker before this one took over
//   reloaded       the page has reloaded, or begun to, already
//   busy           he has unsent words, or a send is in flight
export function reloadDecision({ hadController, reloaded, busy }) {
  if (reloaded || !hadController) return "none";
  return busy ? "wait" : "reload";
}

// Whether the document's drafts, as its storage keeps them (one JSON object, question number -> text),
// hold any: a draft that is empty text is still one, as the document keeps it only while it differs.
export function draftsHeld(text) {
  if (typeof text !== "string") return false;
  try { const o = JSON.parse(text); return !!o && typeof o === "object" && Object.keys(o).length > 0; } catch (e) { return false; }
}

// Whether it is time to ask for a new worker again: never asked, UPDATE_EVERY_MS since, or a clock set back.
export function updateDue(lastAt, now, everyMs = UPDATE_EVERY_MS) {
  if (!(lastAt > 0)) return true;
  return now < lastAt || now - lastAt >= everyMs;
}

// The Account screen's line: the version the page was built as, and "update pending" when the worker in
// control is of another. Anything that is not a version is not shown.
export function versionWords(pageVersion, workerVersion) {
  if (typeof pageVersion !== "string" || !VERSION.test(pageVersion)) return "Version not known.";
  if (typeof workerVersion === "string" && VERSION.test(workerVersion) && workerVersion !== pageVersion) return "Version " + pageVersion + " - update pending (" + workerVersion + ").";
  return "Version " + pageVersion + ".";
}
