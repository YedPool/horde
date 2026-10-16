// The lanes a progress entry belongs to, as the phone reads them (relay/js/protocol.js, entryLanes), for a
// list of entries and one area map, so test/test-orcs-registry.ps1 can hold the PC's copy of the rule
// (orcs/Registry.ps1, Get-HordeOrcEntryLanes) to the phone's, entry for entry.
//
//   node entry-lanes.mjs <path to protocol.js> <path to {"entries":[...],"areas":[{area,lanes}]}>
//
// Prints one JSON array: the lanes of each entry, in order.
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const [, , protocolPath, casesPath] = process.argv;
const { entryLanes } = await import(pathToFileURL(protocolPath).href);
const cases = JSON.parse(readFileSync(casesPath, "utf8"));
process.stdout.write(JSON.stringify(cases.entries.map((e) => entryLanes(e, cases.areas))) + "\n");
