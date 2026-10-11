// relays/cloudflare/dev-host.cjs - runs the pinned wrangler's command line IN THIS PROCESS and ends
// when this process's standard input ends.
//
//   node dev-host.cjs <wrangler-dist/cli.js> dev --config ... --port ...
//
// WHY. A local `wrangler dev` is a node process with the Worker runtime (workerd) as its child, and the
// runtime dies with that node process (measured 2026-10-11: killing it freed the port at once). But
// wrangler does not end when its input closes, so a suite that was itself killed - a mutation run's
// timeout, a crash - would leave it serving on its port for ever. Started through this host, with its
// input a pipe from the suite, it ends when the suite does, however the suite ends: the pipe closes
// with the suite's process. Running the command line in this process (Module.runMain, so wrangler
// sees itself as the main module) rather than as a child keeps it one process to end, not two.
const Module = require("node:module");

const quit = () => process.exit(0);
process.stdin.on("end", quit);
process.stdin.on("error", quit);
process.stdin.resume();
// argv is [node, this file, cli.js, ...]: drop this file, so cli.js is the main module with its own
// arguments after it.
process.argv.splice(1, 1);
Module.runMain();
