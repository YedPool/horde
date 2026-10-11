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
  async function call(method, path, body) {
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
    if (r.status !== 200) return unknown("the relay answered " + r.status + (j && typeof j.error === "string" ? ": " + j.error.slice(0, 200) : ""), r.status);
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
    deleteAccount: () => call("DELETE", "/v1/account", { confirm: DELETE_CONFIRM })
  };
}

// The accounts of a deployment's relay, or null when it has none (the header).
export function accountFromConfig(config, host) {
  if (!config || config.transport !== "http" || config.relayOrigin || !host || typeof host.fetch !== "function") return null;
  return accountClient(host.fetch.bind(host), "");
}
