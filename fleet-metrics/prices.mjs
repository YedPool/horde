// Cost WEIGHT, not a bill. These are list prices per million tokens, used only to rank sinks and to
// compare one day with another, because the plan's limits follow cost and raw token counts hide the
// difference between a cache read and an output token. Nothing here is what anyone was charged. If a
// price list changes, change this table and nothing else: stored rows keep the weight they were
// given, so a changed table only affects rows collected afterwards (re-collect to restate history).
//
// Prices as given by the fleet analyst, 2026-10-16: [input, output] in USD per million tokens.
// Cache read is 0.1x input, a 5-minute cache write 1.25x, a 1-hour cache write 2x (the multipliers
// the reference report used, measured against real usage blocks).
// An unknown model is priced as opus, the dearest, so a missing entry over- and never under-counts.

export const PRICES = {
  opus: [5.0, 25.0],
  fable: [5.0, 25.0],
  sonnet: [3.0, 15.0],
  haiku: [1.0, 5.0],
};
export const CACHE_READ_X = 0.1;
export const CACHE_WRITE_5M_X = 1.25;
export const CACHE_WRITE_1H_X = 2.0;

// Which price row a model id uses. '' and placeholder ids (those that start with '<') are
// 'unknown'; any other id that names no known family is priced as opus but still stored as given.
export function familyOf(model) {
  const m = String(model || '').toLowerCase();
  for (const k of Object.keys(PRICES)) if (m.includes(k)) return k;
  return m && !m.startsWith('<') ? 'opus' : 'unknown';
}

// usage: { input, output, cache_read, cache_write_5m, cache_write_1h } as plain token counts.
export function costOf(family, usage) {
  const [pin, pout] = PRICES[family] || PRICES.opus;
  const n = (k) => Number(usage[k]) || 0;
  return (
    (n('input') * pin +
      n('output') * pout +
      n('cache_write_5m') * pin * CACHE_WRITE_5M_X +
      n('cache_write_1h') * pin * CACHE_WRITE_1H_X +
      n('cache_read') * pin * CACHE_READ_X) /
    1e6
  );
}
