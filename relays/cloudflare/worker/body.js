// relays/cloudflare/worker/body.js - a request's body, read UNDER A CAP and never past it: the mailbox
// API's puts and acks (api.js), the account API's registrations (account-api.js), and the bytes a
// machine's signature covers (auth.js) all come through here.
import { refuse } from "./answers.js";

// The body as bytes, or null when it is longer than cap: read chunk by chunk, so a body that says
// nothing of its length, or lies about it, is still never held past the cap.
export async function readCappedBytes(request, cap) {
  const declared = request.headers.get("Content-Length");
  if (declared !== null && !(Number(declared) <= cap)) return null;
  if (!request.body) return new Uint8Array(0);
  const reader = request.body.getReader();
  const parts = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > cap) { await reader.cancel(); return null; }
    parts.push(value);
  }
  const all = new Uint8Array(size);
  let at = 0;
  for (const p of parts) { all.set(p, at); at += p.byteLength; }
  return all;
}

// The body as an object with exactly the members named, or a refusal: { body } or { refusal }.
export async function readJson(request, members, cap) {
  const bytes = await readCappedBytes(request, cap);
  if (bytes === null) return { refusal: refuse(413, "the body is longer than this relay takes") };
  let body;
  try { body = JSON.parse(new TextDecoder("utf-8", { fatal: false }).decode(bytes)); } catch (e) { return { refusal: refuse(400, "the body is not JSON") }; }
  if (!body || typeof body !== "object" || Array.isArray(body)) return { refusal: refuse(400, "the body is not a JSON object") };
  const names = Object.keys(body).sort().join(",");
  if (names !== members.slice().sort().join(",")) return { refusal: refuse(400, "the body must hold exactly: " + members.join(", ")) };
  return { body };
}
