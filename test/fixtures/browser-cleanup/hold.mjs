// A STAND-IN DRIVER for test/test-browser-cleanup.ps1: it does what the real drivers
// (relays/cloudflare/test/browser-signin.mjs, surfaces/pwa/test/browser-drive.mjs) do first - reach the
// suite's browser on its debugging port and hold a debugging socket to its page - and then waits, so the
// test can end it every way a real driver ends: its input closed (it finishes), killed, or timed out.
//
//   node hold.mjs <browser debugging port>
//
// Prints CONNECTED once the socket is open; exits 0 when its input closes.
const port = process.argv[2];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let targets = [];
for (let i = 0; i < 100 && !targets.some((t) => t.type === "page"); i++) {
  try { targets = await (await fetch("http://127.0.0.1:" + port + "/json/list")).json(); } catch (e) { /* not yet */ }
  if (!targets.some((t) => t.type === "page")) await sleep(100);
}
const page = targets.find((t) => t.type === "page");
if (!page) { process.stdout.write("NO PAGE\n"); process.exit(1); }
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
process.stdout.write("CONNECTED\n");
process.stdin.on("end", () => process.exit(0));
process.stdin.on("error", () => process.exit(0));
process.stdin.resume();
setInterval(() => {}, 60000);
