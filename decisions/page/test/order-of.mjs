// The order the decisions document (decisions/page/list.js) puts a real list in, for a scenario that
// made the list through the horde command line (test/e2e/e2e-decisions-asked.ps1): the list.js that
// ships, run without a page as order-units.mjs runs it, sorting the questions of one `decisions list
// -Json` line.
//
//   node order-of.mjs <path to list.js> <file holding the -Json line> <order> [turned]
//
// Prints the question numbers in that order, joined by commas, on one line.
import { readFileSync } from "node:fs";
import vm from "node:vm";

const [, , listPath, linePath, key, turned] = process.argv;
const window = {};
vm.runInContext(readFileSync(listPath, "utf8"), vm.createContext({ window, Date, isNaN, Number, String, Array, Object, JSON, Math, RegExp, Promise }));
const answer = JSON.parse(readFileSync(linePath, "utf8").replace(/^\uFEFF/, ""));
const questions = (answer && answer.value && answer.value.questions) || [];
process.stdout.write(window.HordeDecisionsDocument.order.inOrder(questions, key, turned === "turned").map((q) => q.number).join(",") + "\n");
