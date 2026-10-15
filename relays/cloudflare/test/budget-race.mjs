// relays/cloudflare/test/budget-race.mjs - AN ACCOUNT'S OWN COUNTS STAY EXACT ACROSS A LEASE OF THE
// RELAY'S, against a local dev of the real Worker, for relays/cloudflare/test/test-cloudflare-limits.ps1
// (part 5). The review of PR 281: the account's object asks the relay-wide object for a lease, and while
// it waits another request of the same account runs; a count written from what was read before the wait
// would lose the other's. With a lease of one, EVERY request here waits on the relay-wide object, and
// they are sent all at once from two phones of one account:
//   - the account's day of <day> requests: of 2 x <day> reads, exactly <day> are taken;
//   - the account's <chars> characters: of 20 puts of 10 into two mailboxes, exactly <chars>/10 are taken.
// A lost count would take more than either.
//
//   node budget-race.mjs <origin> <day> <chars> <phone A1> <phone A2> <phone B1> <phone B2>
//
// Prints one [PASS] or [FAIL] line a check, then [DONE] <failures>.
const [, , origin, dayText, charsText, a1, a2, b1, b2] = process.argv;
const day = Number(dayText);
const chars = Number(charsText);
let failures = 0;
function check(ok, name, detail = "") {
  if (!ok) failures++;
  process.stdout.write((ok ? "[PASS] " : "[FAIL] ") + name + (ok || !detail ? "" : " (" + String(detail).slice(0, 300) + ")") + "\n");
}
const headers = (session) => ({ Cookie: "__Host-horde-session=" + session, Origin: origin });
const read = (session) => fetch(origin + "/v1/mailboxes/work/phone/items?since=0&max=1", { headers: headers(session) }).then(async (r) => ({ status: r.status, code: (await r.json().catch(() => ({}))).code || "" }));
const put = (session, box, key) => fetch(origin + "/v1/mailboxes/work/" + box + "/items", { method: "POST", headers: { ...headers(session), "Content-Type": "application/json" }, body: JSON.stringify({ key, text: "x".repeat(10) }) }).then(async (r) => ({ status: r.status, code: (await r.json().catch(() => ({}))).code || "" }));
const tally = (answers) => { const t = {}; for (const a of answers) { const k = a.status + (a.code ? " " + a.code : ""); t[k] = (t[k] || 0) + 1; } return JSON.stringify(t); };

const reads = await Promise.all([...Array(day).keys()].flatMap((i) => [read(a1), read(a2)]));
const readsTaken = reads.filter((a) => a.status === 200).length;
check(readsTaken === day && reads.filter((a) => a.status === 429 && a.code === "daily-limit").length === day, "of " + 2 * day + " reads sent at once by two phones of one account, exactly its day of " + day + " are taken, and the rest refused daily-limit: no count lost while a lease was asked for", tally(reads));

const puts = await Promise.all([...Array(10).keys()].flatMap((i) => [put(b1, "race-a", "ra-" + i), put(b2, "race-b", "rb-" + i)]));
const putsTaken = puts.filter((a) => a.status === 200).length;
check(putsTaken === chars / 10 && puts.filter((a) => a.status === 507 && a.code === "account-full").length === 20 - chars / 10, "of 20 puts of 10 characters sent at once into two mailboxes of one account, exactly its " + chars + " characters are taken, and the rest refused account-full: no charge lost while a lease was asked for", tally(puts));

process.stdout.write("[DONE] " + failures + "\n");
process.exit(failures === 0 ? 0 : 1);
