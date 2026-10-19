// Row ids and content hashes for fleet.db.
//
// ULID: 48 bits of UTC milliseconds then 80 random bits, as 26 Crockford base32 characters. Sorted as text
// it sorts by time, and two PCs never mint the same one, so rows made on the second Thrall PC merge into
// the authority without renumbering. `rand` may be passed so a test (or a re-import that must reproduce an
// id) is deterministic; Horde's PowerShell twin is New-HordeFleetUlid (fleet/LotTables.ps1).
//
// CANONICAL TEXT: keys sorted by UTF-16 code unit, no whitespace, every non-ASCII character escaped as
// \uXXXX, undefined members dropped. The same content always gives the same bytes, so its sha256 is the
// row's identity for de-duplication: importing a line twice, or receiving it twice from another PC, is a
// no-op on the UNIQUE sha256 column. Only integers are allowed as numbers: a float's text form is not
// stable across languages, and every number in fleet.db is a count, a priority or a millisecond time.
import crypto from 'node:crypto';

const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

export function ulid(atMs = Date.now(), rand = crypto.randomBytes(10)) {
  if (!Number.isSafeInteger(atMs) || atMs < 0 || atMs > 0xffffffffffff) throw new Error('ulid: time out of range: ' + atMs);
  if (rand.length !== 10) throw new Error('ulid: need 10 random bytes');
  let out = '';
  let t = atMs;
  for (let i = 0; i < 10; i++) { out = CROCKFORD[t % 32] + out; t = Math.floor(t / 32); }
  let bits = 0n;
  for (const b of rand) bits = (bits << 8n) | BigInt(b);
  let tail = '';
  for (let i = 0; i < 16; i++) { tail = CROCKFORD[Number(bits & 31n)] + tail; bits >>= 5n; }
  return out + tail;
}

export function canonical(value) {
  if (value === null) return 'null';
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value)) throw new Error('canonical: only safe integers, not ' + value);
    return String(value);
  }
  if (typeof value === 'string') {
    return JSON.stringify(value).replace(/[\u007f-\uffff]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
  }
  if (Array.isArray(value)) return '[' + value.map((v) => (v === undefined ? 'null' : canonical(v))).join(',') + ']';
  if (typeof value === 'object') {
    const keys = Object.keys(value).filter((k) => value[k] !== undefined).sort();
    return '{' + keys.map((k) => canonical(k) + ':' + canonical(value[k])).join(',') + '}';
  }
  throw new Error('canonical: cannot encode ' + typeof value);
}

export function sha256(value) {
  return crypto.createHash('sha256').update(canonical(value), 'ascii').digest('hex');
}
