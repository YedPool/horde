// relays/cloudflare/test/fake-wrangler.cjs - a stand-in for wrangler's command line, for the deploy's
// suite: it contacts nothing. Each run appends one JSON line to the file HORDE_FAKE_WRANGLER_LOG names:
//   argv     its arguments after this script
//   stdin    everything read from standard input, byte for byte (latin1, so a byte order mark shows)
//   env      the variables the deploy must set, and the test binding, which it must not
//   config   what the --config file held when it ran: whether it names a test binding, whether its
//            app folder holds app/index.html, and that app's config.json
// HORDE_FAKE_WRANGLER_FAIL names a command ("secret" or "deploy") to fail; it then prints what it was
// given on its error stream, so the suite can see the deploy hide it.
const fs = require("node:fs");
const path = require("node:path");
const argv = process.argv.slice(2);
const chunks = [];
function configSeen() {
  const at = argv.indexOf("--config");
  if (at < 0 || !argv[at + 1]) return null;
  const text = fs.readFileSync(argv[at + 1], "utf8");
  const cfg = JSON.parse(text);
  const dir = cfg.assets && cfg.assets.directory;
  const appConfig = dir && fs.existsSync(path.join(dir, "app/config.json")) ? fs.readFileSync(path.join(dir, "app/config.json"), "utf8").trim() : "";
  return { path: argv[at + 1], namesTestBinding: text.indexOf("HORDE_RELAY_TEST_") >= 0, appIndex: Boolean(dir && fs.existsSync(path.join(dir, "app/index.html"))), appConfig, name: cfg.name };
}
process.stdin.on("data", (c) => chunks.push(c));
process.stdin.on("end", () => {
  const stdin = Buffer.concat(chunks).toString("latin1");
  const env = {};
  for (const k of ["WRANGLER_SEND_METRICS", "CLOUDFLARE_CF_FETCH_ENABLED", "CI", "HORDE_RELAY_TEST_AUTH"]) if (process.env[k] !== undefined) env[k] = process.env[k];
  fs.appendFileSync(process.env.HORDE_FAKE_WRANGLER_LOG, JSON.stringify({ argv, stdin, env, config: configSeen() }) + "\n");
  if (process.env.HORDE_FAKE_WRANGLER_FAIL && argv[0] === process.env.HORDE_FAKE_WRANGLER_FAIL) {
    process.stderr.write("fake wrangler failed on purpose, given: " + stdin + "\n");
    process.exit(7);
  }
  if (argv[0] === "deploy") process.stdout.write("Uploaded relay\nDeployed relay triggers\n  https://relay.example.workers.dev\n");
  else process.stdout.write("Success! Uploaded secret " + argv[2] + "\n");
  process.exit(0);
});
