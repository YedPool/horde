// The fleet line's rows (fleet/line/line.js), drawn without a page, under Node, for
// test/test-fleet-status.ps1. line.js is a page script: it is run here in a context of its own with a
// small stand-in for the document - elements that hold children and text, and lay out nothing - and
// mounted, unfolded, with the status the suite hands it. What it drew is printed as one line of JSON:
// the snapshot's head and rows, the same text a real window reports.
//
//   node draw-rows.mjs <path to line.js> <path to a JSON file holding the status>
import { readFileSync } from "node:fs";
import vm from "node:vm";

const [, , linePath, statusPath] = process.argv;

function element(tag) {
  const node = {
    tagName: tag, className: "", type: "", children: [], ownText: "",
    get firstChild() { return this.children.length ? this.children[0] : null; },
    appendChild(child) { this.children.push(child); return child; },
    removeChild(child) { this.children.splice(this.children.indexOf(child), 1); return child; },
    setAttribute() { }, addEventListener() { },
    getClientRects() { return []; }
  };
  Object.defineProperty(node, "textContent", {
    get() { return this.children.length ? this.children.map((c) => c.textContent).join("") : this.ownText; },
    set(v) { this.children = []; this.ownText = String(v); }
  });
  return node;
}
const document = {
  createElement: element,
  createTextNode: (text) => ({ textContent: String(text), children: [], getClientRects() { return []; } })
};
const window = {};
vm.runInContext(readFileSync(linePath, "utf8"), vm.createContext({ window, document, Object, String, Array, Math, RegExp, Infinity }));
const line = window.HordeFleetLine.mount(element("div"), {});
line.update(JSON.parse(readFileSync(statusPath, "utf8")));
line.setOpen(true);
const shot = line.snapshot();
process.stdout.write(JSON.stringify({ head: shot.head, rows: shot.rows }) + "\n");
