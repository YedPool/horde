// The one sorting of the decisions document (decisions/page/list.js, THE ORDER IS HIS), held without
// a page, under Node, for test/test-decisions-page-order.ps1. list.js is a page script: it is run
// here in a context of its own with an empty window, which is all it touches until a page mounts it,
// and the order it hands out (window.HordeDecisionsDocument.order) is what the window and the phone
// both sort by.
//
//   node order-units.mjs <path to list.js>
//
// Prints one line per check, "[PASS] name" or "[FAIL] name: detail", then "[DONE] n"; the suite turns
// each into a check of its own.
import { readFileSync } from "node:fs";
import vm from "node:vm";

const [, , listPath] = process.argv;
const window = {};
vm.runInContext(readFileSync(listPath, "utf8"), vm.createContext({ window, Date, isNaN, Number, String, Array, Object, JSON, Math, RegExp, Promise }));
const order = window.HordeDecisionsDocument && window.HordeDecisionsDocument.order;

let passed = 0;
let failures = 0;
function check(ok, name, detail = "") {
  if (ok) { passed += 1; process.stdout.write("[PASS] " + name + "\n"); }
  else { failures += 1; process.stdout.write("[FAIL] " + name + (detail ? ": " + detail : "") + "\n"); }
}
const numbers = (list) => list.map((q) => q.number).join(",");
// A question as a list hands it over; at is seconds into one minute of one day.
const q = (number, at, more = {}) => ({ number, addedAt: at === null ? undefined : "2026-10-12T09:00:" + String(at).padStart(2, "0") + ".0000000Z", ...more });
// Every order of a small list, to hold a sort to one answer whatever order it is handed.
function shuffles(list, times) {
  const out = [];
  let seed = 7;
  const next = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
  for (let t = 0; t < times; t += 1) {
    const copy = list.slice();
    for (let i = copy.length - 1; i > 0; i -= 1) { const j = Math.floor(next() * (i + 1)); [copy[i], copy[j]] = [copy[j], copy[i]]; }
    out.push(copy);
  }
  return out;
}
const always = (list, key, want, name) => {
  const got = new Set(shuffles(list, 60).map((s) => numbers(order.inOrder(s, key))));
  check(got.size === 1 && got.has(want), name, "wanted " + want + ", got " + [...got].join(" | "));
};

check(!!order && typeof order.inOrder === "function", "the page script hands out its one sorting without a page");
check(order.orders.join(",") === "date,importance,blocks", "the orders are date, task importance and blocking, date first", order.orders.join(","));

// --- date: the newest first ---
const byDate = [q(1, 10), q(2, 20), q(3, 30), q(4, 5)];
always(byDate, "date", "3,2,1,4", "by date the question asked last stands first, whatever number it has");
always([q(7, 10), q(9, 10), q(8, 10)], "date", "9,8,7", "asked in the same instant, the higher number - asked later - stands first");
always([q(1, null), q(3, null), q(2, null)], "date", "3,2,1", "with no time stated, as in a list from an earlier version, the higher number stands first");
always([{ number: 1, addedAt: "not a time" }, { number: 2, addedAt: "" }, { number: 3, addedAt: null }], "date", "3,2,1", "a time that is not a time is no time: the number decides, and nothing throws");
always([{ number: 1, addedAt: "2026-10-12T09:00:05Z" }, { number: 2, addedAt: "2026-10-12T09:00:05.5000000Z" }, { number: 3, addedAt: "2026-10-12T09:00:04.9990000Z" }], "date", "2,1,3", "times written with and without fractions of a second are compared as times, not as text");
always([q(5, 10), { number: 6 }, q(4, 30)], "date", "4,5,6", "a question with a time stands before one with none");
always(byDate, "no-such-order", "3,2,1,4", "an order the page does not know is the default: by date");
always(byDate, "", "3,2,1,4", "and so is no order at all");

// --- task importance ---
const ranked = [q(1, 10, { importance: "low" }), q(2, 20, { importance: "high" }), q(3, 30, { importance: "normal" }), q(4, 40, { importance: "high" }), q(5, 50, { importance: "low" }), q(6, 59)];
always(ranked, "importance", "4,2,6,3,5,1", "by task importance: high, then normal, then low - and inside each, the newest first");
always([q(1, 10), q(2, 20, { importance: "normal" }), q(3, 30)], "importance", "3,2,1", "A QUESTION THAT STATES NO IMPORTANCE reads as normal: among normal ones it stands by date");
always([q(1, 10, { importance: "urgent" }), q(2, 20, { importance: "high" }), q(3, 30, { importance: "low" }), q(4, 40, { importance: "normal" })], "importance", "2,4,1,3", "a word this page does not know - a later version's - stands where normal does, never first and never lost");
always([q(1, 10, { importance: "HIGH" }), q(2, 20, { importance: 1 }), q(3, 30, { importance: null }), q(4, 5, { importance: "high" })], "importance", "4,3,2,1", "a word in capitals, a number and nothing are none of them a known word: each reads as normal");
always([q(1, 10, { importance: "high", blocks: "none" }), q(2, 20, { importance: "high", blocks: "all" }), q(3, 30, { importance: "low", blocks: "all" })], "importance", "2,1,3", "by importance the blocking decides nothing: a tie goes to the newest");

// --- blocking ---
const blocking = [q(1, 10, { blocks: "none" }), q(2, 20, { blocks: "all" }), q(3, 30, { blocks: "part" }), q(4, 40, { blocks: "all" }), q(5, 50, { blocks: "none" }), q(6, 59)];
always(blocking, "blocks", "4,2,6,3,5,1", "by blocking: all, then part, then none - and inside each, the newest first");
always([q(1, 10), q(2, 20, { blocks: "part" }), q(3, 30)], "blocks", "3,2,1", "A QUESTION THAT STATES NO BLOCKING reads as part");
always([q(1, 10, { blocks: "everything" }), q(2, 20, { blocks: "all" }), q(3, 30, { blocks: "none" }), q(4, 40, { blocks: "part" })], "blocks", "2,4,1,3", "a blocking this page does not know stands where part does");
always([q(1, 10, { blocks: "all", importance: "low" }), q(2, 20, { blocks: "all", importance: "high" }), q(3, 5, { blocks: "all" })], "blocks", "2,1,3", "by blocking the importance decides nothing: a tie goes to the newest");
always([q(1, 10, { blocks: "high" }), q(2, 20, { blocks: "all" })], "blocks", "2,1", "a word of the other list is not a blocking: it reads as part");

// --- an old list, and what is handed in ---
const old = [{ number: 3 }, { number: 11 }, { number: 7 }];
for (const key of order.orders) always(old, key, "11,7,3", "a list from before the two words and the times existed is, by " + key + ", the highest number first");
const handed = [q(1, 10), q(2, 20)];
const sorted = order.inOrder(handed, "date");
check(numbers(handed) === "1,2" && numbers(sorted) === "2,1" && sorted !== handed, "the list handed in is not touched: a new one comes back");
check(order.inOrder(null, "date").length === 0 && order.inOrder(undefined, "blocks").length === 0 && order.inOrder("questions", "date").length === 0, "what is not a list sorts to an empty one, and nothing throws");
check(order.inOrder([], "importance").length === 0, "an empty list is an empty list");
const many = [];
for (let i = 1; i <= 300; i += 1) many.push(q(i, i % 60, { importance: ["high", "normal", "low"][i % 3], blocks: ["all", "part", "none"][i % 3] }));
const big = order.inOrder(many, "importance");
let inRank = true;
const place = { high: 0, normal: 1, low: 2 };
for (let i = 1; i < big.length; i += 1) {
  const a = big[i - 1], b = big[i];
  if (place[a.importance] > place[b.importance]) inRank = false;
  if (place[a.importance] === place[b.importance] && (Date.parse(a.addedAt) < Date.parse(b.addedAt) || (Date.parse(a.addedAt) === Date.parse(b.addedAt) && a.number < b.number))) inRank = false;
}
check(big.length === 300 && inRank && new Set(big.map((x) => x.number)).size === 300, "three hundred questions come back in order, every one of them, once");

process.stdout.write("[DONE] " + passed + "\n");
process.exit(failures === 0 ? 0 : 1);
