// relays/cloudflare/worker/headers.js - the strict headers every answer of the Worker carries: the phone
// app's files, the mailbox API's answers, its refusals and its WebSocket upgrades alike.
//
// THE CONTENT SECURITY POLICY IS THE APP'S OWN, read from its policy line (surfaces/pwa/page/index.html,
// imported as text when the Worker is bundled), with frame-ancestors 'none' after it: a policy in a
// meta element cannot say frame-ancestors (browsers ignore it there), and a header can. One origin
// serves the app and the relay (wrangler.json), so the app is built with no relay origin of its own and
// its connect-src 'self' is the whole truth; the header and the page's line then agree word for word,
// which test-cloudflare-worker.ps1 checks on the built page. A page with no policy line fails the
// Worker at start: it serves nothing rather than serve the app with no policy.
//
// THE REST:
//   Strict-Transport-Security  two years, subdomains too: the app holds keys, and a downgrade to http
//                              is the one way to put another script in front of it
//   X-Content-Type-Options     nosniff: a sealed envelope is never read as a script or a page
//   Referrer-Policy            no-referrer, as the page's own meta line says
//   Permissions-Policy         the camera (scan.js reads the pairing QR code) and passkeys (webauthn.js)
//                              for this origin only; the rest of what a page could ask for, off
//   X-Frame-Options            DENY, for browsers older than frame-ancestors
// The mailbox API's answers are also Cache-Control: no-store, so no cache between holds an envelope.
import page from "../../../surfaces/pwa/page/index.html";

const POLICY_LINE = /<meta http-equiv="Content-Security-Policy" content="([^"]+)">/;
const found = POLICY_LINE.exec(page);
if (!found) throw new Error("surfaces/pwa/page/index.html has no Content-Security-Policy line");

export const STRICT_HEADERS = Object.freeze({
  "Content-Security-Policy": found[1] + "; frame-ancestors 'none'",
  "Strict-Transport-Security": "max-age=63072000; includeSubDomains",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "Permissions-Policy": "camera=(self), publickey-credentials-get=(self), publickey-credentials-create=(self), microphone=(), geolocation=(), payment=(), usb=(), serial=(), hid=(), bluetooth=()",
  "X-Frame-Options": "DENY"
});

// The answer again, with every strict header set over whatever it had.
export function withStrictHeaders(response, isApi) {
  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries(STRICT_HEADERS)) headers.set(name, value);
  if (isApi) headers.set("Cache-Control", "no-store");
  if (response.status === 101) return new Response(null, { status: 101, webSocket: response.webSocket, headers });
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}
