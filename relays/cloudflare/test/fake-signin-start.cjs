// relays/cloudflare/test/fake-signin-start.cjs - a stand-in for a deployed relay's sign-in start, for the
// deploy's suite: the deploy's check (Deploy.ps1, Test-HordeCloudflareRelaySignInClient) is pointed at it
// by the setting deployCheckOrigin, so no suite ever asks the real relay. It contacts nothing.
//
//   node fake-signin-start.cjs <client id> <mode>
//
// It listens on 127.0.0.1 at a port the system picks, prints "PORT <n>", and answers GET /auth/google:
//   same   303 to Google with client_id=<the id>, as the Worker does (worker/oidc.js, authorizeUrl)
//   mark   the same, the id with a byte order mark (U+FEFF) in front: the incident of 2026-10-14
//   space  the same, the id with a space after it
//   none   503, as a Worker whose sign-in is not set up answers
//   two    303 with client_id twice
// Anything else is 404. It ends when its standard input closes.
const http = require("node:http");
const [, , clientId, mode] = process.argv;
const google = "https://accounts.google.com/o/oauth2/v2/auth";
function location() {
  const q = "response_type=code&scope=openid%20email%20profile&state=s&nonce=n";
  if (mode === "mark") return google + "?client_id=" + encodeURIComponent("\uFEFF" + clientId) + "&" + q;
  if (mode === "space") return google + "?client_id=" + encodeURIComponent(clientId + " ") + "&" + q;
  if (mode === "two") return google + "?client_id=" + encodeURIComponent(clientId) + "&client_id=" + encodeURIComponent(clientId) + "&" + q;
  return google + "?client_id=" + encodeURIComponent(clientId) + "&" + q;
}
const server = http.createServer((req, res) => {
  if (req.method !== "GET" || req.url !== "/auth/google") { res.writeHead(404); res.end(); return; }
  if (mode === "none") { res.writeHead(503, { "Content-Type": "application/json" }); res.end('{"error":"sign-in is not set up on this relay"}'); return; }
  res.writeHead(303, { Location: location() });
  res.end();
});
server.listen(0, "127.0.0.1", () => process.stdout.write("PORT " + server.address().port + "\n"));
process.stdin.on("data", () => {});
process.stdin.on("end", () => process.exit(0));
