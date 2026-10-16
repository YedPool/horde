// The lane a question is of, as the decisions page reads it (decisions/page/list.js, laneOf), for a list of
// askedBy values, so test/test-orcs-registry.ps1 can hold the PC's copy of the rule (orcs/Registry.ps1,
// Get-HordeOrcQuestionLane) to the page's, name for name. list.js is run in a context of its own with an
// empty window, as decisions/page/test/lane-units.mjs runs it.
//
//   node lane-of.mjs <path to list.js> <path to a JSON array of askedBy values>
//
// Prints one JSON array: the lane of each value, in order.
import { readFileSync } from "node:fs";
import vm from "node:vm";

const [, , listPath, namesPath] = process.argv;
const window = {};
vm.runInContext(readFileSync(listPath, "utf8"), vm.createContext({ window, Date, isNaN, Number, String, Array, Object, JSON, Math, RegExp, Promise }));
const L = window.HordeDecisionsDocument && window.HordeDecisionsDocument.lanes;
const names = JSON.parse(readFileSync(namesPath, "utf8"));
process.stdout.write(JSON.stringify(names.map((n) => L.laneOf(n === null ? {} : { askedBy: n }))) + "\n");
