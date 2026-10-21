// Finds the readers. A reader is agents/<harness>/metrics/reader.mjs: the ONLY place that knows how
// one harness writes its transcripts (CONTRIBUTING 14: nothing outside agents/<name>/ names a
// harness). The meter core scans the folder instead of listing readers, so a second harness is a new
// folder and never an edit here.
//
// A reader's default export is:
//   id                      short string, for messages
//   roots(opts)             folders to scan; opts.projects overrides (tests, or a moved store)
//   listFiles(root)         files to read, in any order
//   consume({path, lines, store, ctx}) -> batch   rows for the tables (see store.apply) from NEW
//                           complete lines of one file; may ask the store about earlier passes
//   inspectTail({path, text, store}) -> tail       what the last bytes of a file say about usage-limit
//                           hits (see watch-limits.mjs)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

export function readerFiles(agentsDir = path.join(here, '..', 'agents')) {
  const out = [];
  let names = [];
  try { names = fs.readdirSync(agentsDir).sort(); } catch { return out; }
  for (const n of names) {
    const f = path.join(agentsDir, n, 'metrics', 'reader.mjs');
    if (fs.existsSync(f)) out.push(f);
  }
  return out;
}

export async function openReaders(opts = {}) {
  const files = opts.readerFiles || readerFiles(opts.agentsDir);
  const out = [];
  for (const f of files) out.push((await import(pathToFileURL(f).href)).default);
  return out;
}
