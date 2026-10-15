// The lanes of the decisions document (decisions/page/list.js, ONE LANE AT A TIME), held without a page,
// under Node, for test/test-decisions-page-lanes.ps1: the lane a question is of (laneOf, read from who
// asked) and the cards' numbers for a list and a test of "still to answer" (lanesOf). list.js is run here
// in a context of its own with an empty window, as order-units.mjs runs it. What the page itself counts
// as still to answer - answered, parts, closed, follow-ups - is counted on a real page by
// decisions/page/test/browser-cards.mjs.
//
//   node lane-units.mjs <path to list.js>
//
// Prints one line per check, "[PASS] name" or "[FAIL] name: detail", then "[DONE] n".
import { readFileSync } from "node:fs";
import vm from "node:vm";

const [, , listPath] = process.argv;
const window = {};
vm.runInContext(readFileSync(listPath, "utf8"), vm.createContext({ window, Date, isNaN, Number, String, Array, Object, JSON, Math, RegExp, Promise }));
const L = window.HordeDecisionsDocument && window.HordeDecisionsDocument.lanes;

let passed = 0;
let failures = 0;
function check(ok, name, detail = "") {
  if (ok) { passed += 1; process.stdout.write("[PASS] " + name + "\n"); }
  else { failures += 1; process.stdout.write("[FAIL] " + name + (detail ? ": " + detail : "") + "\n"); }
}
const words = (ls) => ls.map((l) => l.lane + ":" + l.open + (l.blocksAll ? "!" : "")).join(",");
const all = () => true;

check(!!L && typeof L.laneOf === "function" && typeof L.lanesOf === "function" && L.keeper === "thrall", "CONTROL: the page hands out its lanes (laneOf, lanesOf) and the keeper's lane is thrall, the Progress cards' word");
if (L) {
  // --- the lane a question is of: who asked ---
  const of = (askedBy) => L.laneOf(askedBy === undefined ? {} : { askedBy });
  check(of("Orc C") === "C" && of("Orc E") === "E" && of("Orc F1") === "F1" && of("Orc B, for the fleet") === "B", "an Orc's question is of its lane, as its lane file names it: C, E, F1; words after the name change nothing", [of("Orc C"), of("Orc F1"), of("Orc B, for the fleet")].join(","));
  check(of("M (Thrall)") === "thrall" && of("M (Thrall), for the fleet-tool session (now closed)") === "thrall" && of("Thrall") === "thrall", "the keeper's question (M (Thrall), Thrall - as the live list says it) is the Thrall's lane", [of("M (Thrall)"), of("Thrall")].join(","));
  check(of("") === "thrall" && of(undefined) === "thrall" && L.laneOf(null) === "thrall" && of("someone") === "thrall" && of("orc c") === "thrall", "A QUESTION THAT NAMES NOBODY (empty, no askedBy at all, or a name the list cannot read) is the Thrall's lane, as its letter is M", [of(""), of(undefined), of("someone"), of("orc c")].join(","));
  check(of("Orchard") === "thrall" && of("Orc Fred") === "thrall" && of("B (by hand)") === "B", "a word that only begins like an Orc is no lane of its own; one capital letter standing alone is that lane, as its letter is", [of("Orchard"), of("Orc Fred"), of("B (by hand)")].join(","));

  // --- the cards' numbers ---
  const qs = [
    { number: 1, askedBy: "Orc B", blocks: "all" },
    { number: 2, askedBy: "Orc B", blocks: "part" },
    { number: 3, askedBy: "Orc C" },
    { number: 4, askedBy: "M (Thrall)", blocks: "none" },
    { number: 5 },
    { number: 6, askedBy: "Orc A", blocks: "all" },
    { number: 7, askedBy: "Orc F1" }
  ];
  check(words(L.lanesOf(qs, all)) === "thrall:2,A:1!,B:2!,C:1,F1:1", "EACH LANE ITS COUNT, the keeper's lane first and then by name, and the mark on a lane any of whose questions blocks all its work", words(L.lanesOf(qs, all)));
  const toAnswer = (q) => q.number !== 1 && q.number !== 6;
  check(words(L.lanesOf(qs, toAnswer)) === "thrall:2,B:1,C:1,F1:1", "ONLY WHAT IS STILL TO ANSWER IS COUNTED: with 1 and 6 answered, A has no card's count and B's mark goes with 1", words(L.lanesOf(qs, toAnswer)));
  // MUST-FAIL TWIN: the same list read with a test that counts nothing must not give the numbers above.
  check(words(L.lanesOf(qs, () => false)) === "" && words(L.lanesOf(qs, () => false)) !== words(L.lanesOf(qs, all)), "MUST-FAIL TWIN: counting nothing gives no lane at all, not the numbers above");
  check(L.lanesOf([{ number: 1, askedBy: "Orc B", blocks: "ALL" }, { number: 2, askedBy: "Orc B", blocks: "everything" }], all)[0].blocksAll === false, "only the rules' own word (all) is the mark: another word, or another case, is not");
  check(words(L.lanesOf(null, all)) === "" && words(L.lanesOf([null, undefined, { number: 9, askedBy: "Orc D" }], all)) === "D:1", "no list is no lanes; what is not a question is passed over");
  const before = JSON.stringify(qs);
  L.lanesOf(qs, all);
  check(JSON.stringify(qs) === before, "the list handed in is not touched");
}
process.stdout.write("[DONE] " + passed + "\n");
process.exit(failures ? 1 : 0);
