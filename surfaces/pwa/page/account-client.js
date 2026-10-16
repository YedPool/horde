// surfaces/pwa/page/account-client.js - the phone's side of the hosted relay's ACCOUNTS: whether this
// browser is signed in, the sign-in and sign-out addresses, and the machines registered to the account -
// the one place the app speaks to them, as relay-client.js is for the mailboxes.
//
// WHEN THERE ARE ACCOUNTS AT ALL: only with the http transport (relay-client.js), whose relay is the very
// site that serves this app. A memory or binding relay has no accounts, so accountFromConfig answers null
// and the app shows no sign-in, and pairs as it always did.
//
// SIGN-IN IS THE SERVER'S (Sign in with Google): the app only sends the browser to /auth/google, and the
// relay keeps the session in an HttpOnly cookie no script here can read. So every call below is a fetch
// of this same origin with the browser's own cookie (credentials same-origin), never a token held here;
// the browser adds the page's Origin to each POST and DELETE, which the relay requires of a change.
//
// REGISTERING A MACHINE (pairing, phone-core.js): the offer's horde, id, machine key id, machine label,
// signing key, expiry and ACCOUNT GRANT (relay/Pairing.ps1) go to the relay, which takes the machine's key into this
// account only if the grant verifies under it. Without that, the machine could not reach the relay at
// all: it signs every request with that key, and the relay knows a machine only by a registered one.
//
// THE ACCOUNT ITSELF (relay PR 8c): its phones, each of which any of them may sign out, and DELETING it -
// every mailbox, machine registration and session at once. The relay takes a deletion only with the
// words DELETE_CONFIRM in its body; the app asks the person first, in words of its own.
//
// Every answer is { state, value, reason, status } in core/Tristate.ps1's words; nothing here throws
// for the far end, and the relay's words are cut to 200 characters for the caller's diagnostics.
const known = (value) => ({ state: "known", value, reason: "", status: 200 });
const unknown = (reason, status = 0) => ({ state: "unknown", value: null, reason, status });

export const SIGN_IN_PATH = "/auth/google";
export const DELETE_CONFIRM = "delete this account";

export function accountClient(fetchFn, origin = "") {
  // withCode: a refusal's answer also carries the relay's code word (answers.js), or "".
  async function call(method, path, body, withCode = false) {
    let r;
    try {
      r = await fetchFn(origin + path, {
        method, credentials: "same-origin", cache: "no-store", redirect: "error",
        headers: body === undefined ? {} : { "Content-Type": "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body)
      });
    } catch (x) { return unknown("the relay could not be reached"); }
    let j = null;
    try { j = await r.json(); } catch (x) { j = null; }
    if (r.status !== 200) {
      const u = unknown("the relay answered " + r.status + (j && typeof j.error === "string" ? ": " + j.error.slice(0, 200) : ""), r.status);
      if (withCode) u.code = j && typeof j.code === "string" && /^[a-z-]{1,32}$/.test(j.code) ? j.code : "";
      return u;
    }
    if (!j || typeof j !== "object" || Array.isArray(j)) return unknown("the relay's answer is not a JSON object", r.status);
    return known(j);
  }
  return {
    signInUrl: () => origin + SIGN_IN_PATH,
    session: () => call("GET", "/auth/session"),
    signOut: () => call("POST", "/auth/signout"),
    account: () => call("GET", "/v1/account"),
    // offer is relay/js/protocol.js's readOffer value.
    registerMachine: (offer) => call("POST", "/v1/account/machines", { horde: offer.horde, offer: offer.offer, machine: offer.machine, label: offer.label, signPublic: offer.signPublic, expiresAt: offer.expiresAt, grant: offer.grant }),
    removeMachine: (keyId) => (/^[0-9a-f]{32}$/.test(String(keyId)) ? call("DELETE", "/v1/account/machines/" + keyId) : Promise.resolve(unknown("not a machine's key id"))),
    signOutPhone: (phoneId) => (/^[0-9a-f]{64}$/.test(String(phoneId)) ? call("DELETE", "/v1/account/phones/" + phoneId) : Promise.resolve(unknown("not a phone's id"))),
    deleteAccount: () => call("DELETE", "/v1/account", { confirm: DELETE_CONFIRM }),
    // ASKING TO JOIN one machine of the account ("Add this phone"; the relay's join.js). The answer
    // carries code too: the relay's word for a limit - "join-pending" (another request is pending),
    // "rate-limited" (too many this hour), "join-blocked" (this address's request was rejected: none
    // for an hour) - so the screen can say which. Nothing here retries a refusal: the person asks again.
    requestJoin: async ({ machine, request, label, agent, requestKey }) => {
      const r = await call("POST", "/v1/account/join", { machine, request, label, agent, requestKey }, true);
      return { ...r, code: typeof r.code === "string" ? r.code : "" };
    }
  };
}

// IS THE PC THERE? (the founder, 2026-10-14, fix 2 of six). The account's answer carries, for each of
// its machines, lastSeenAt - the second the relay last verified a request signed by it, or null for a
// machine not heard from yet - and now, the relay's own clock (the hosted relay's presence record). A
// machine is OFFLINE when now - lastSeenAt is over OFFLINE_AFTER_MS, BOTH TIMES THE RELAY'S: the phone's
// own clock is never read here, so a phone set wrong cannot raise the banner or hold it down. An idle
// runner is heard at least once a minute (its watch is 60 s), so two minutes is a PC that has stopped.
// A machine never heard from gets no offline banner - nothing says it ever ran - only a quiet "not heard
// from yet" on the Account screen. An answer that is not the relay's shape says nothing about anyone.
export const OFFLINE_AFTER_MS = 120000;

// The machines of an account answer (accountClient's account().value), each as
// { keyId, name, state: "online" | "offline" | "never", lastSeenAt }. name is the machine's own label and
// its horde, as the Account screen shows it.
export function presenceOf(answer) {
  if (!answer || !Number.isSafeInteger(answer.now) || !Array.isArray(answer.machines)) return [];
  const out = [];
  for (const m of answer.machines) {
    if (!m || typeof m.keyId !== "string") continue;
    const name = (typeof m.label === "string" && m.label ? m.label : "machine " + m.keyId.slice(0, 12)) + (typeof m.horde === "string" && m.horde ? " (" + m.horde + ")" : "");
    const seen = Number.isSafeInteger(m.lastSeenAt) && m.lastSeenAt > 0 ? m.lastSeenAt : null;
    const state = seen === null ? "never" : answer.now - seen > OFFLINE_AFTER_MS ? "offline" : "online";
    out.push({ keyId: m.keyId, name, state, lastSeenAt: seen });
  }
  return out;
}

// The banner of one offline machine, in the founder's words. timeText turns lastSeenAt into the phone's
// local time (the app hands in protocol.js's dayTime). Nothing is lost while the PC is away - the answers
// wait in this phone's outbox and in the relay's mailbox - so the words never say otherwise.
// THE HOOK FOR "N ANSWERS WAITING" (fixes 3 and 4, later): options.waiting, a count of answers not yet
// applied, adds one sentence; nothing passes it yet.
export function offlineWords(machine, timeText, options = {}) {
  const waiting = Number.isSafeInteger(options.waiting) && options.waiting > 0 ? " " + options.waiting + (options.waiting === 1 ? " answer is" : " answers are") + " waiting." : "";
  return "PC " + machine.name + " offline since " + timeText(machine.lastSeenAt) + ". Your answers are kept and will be applied when it is back." + waiting;
}

// The accounts of a deployment's relay, or null when it has none (the header).
export function accountFromConfig(config, host) {
  if (!config || config.transport !== "http" || config.relayOrigin || !host || typeof host.fetch !== "function") return null;
  return accountClient(host.fetch.bind(host), "");
}
