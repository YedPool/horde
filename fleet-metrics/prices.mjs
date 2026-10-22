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

// CONTEXT WINDOW SIZES, in tokens, by family: the denominator of "how full is this session". THESE ARE
// ASSUMPTIONS, not numbers any transcript states (a transcript carries the model id and the token counts
// of each request, never the window):
//   - 200000 is the standard window the model maker documents for these families. It is
//     the figure used for every family here, INCLUDING 'fable', whose window was not looked up (assumed).
//   - 1000000 is the extended window some models offer as an opt-in; the harness marks the opt-in with a
//     "[1m]" suffix on the model id. The suffix is not always recorded in the transcript, so a session is
//     also taken to have the extended window once ONE of its requests filled more than the standard
//     window: a request cannot hold more than the window, so that is evidence, and the only evidence
//     available. A 1M-window session that has not yet passed 200000 is shown with the smaller limit.
//   - An unknown model gets the standard window.
// If a window is wrong, change this table and nothing else; the limit is worked out when a usage row is
// refreshed, so the next refresh restates it.
export const CONTEXT_LIMITS = {
  opus: 200000,
  fable: 200000,
  sonnet: 200000,
  haiku: 200000,
};
export const CONTEXT_LIMIT_DEFAULT = 200000;
export const CONTEXT_LIMIT_EXTENDED = 1000000;

// model: the model id as recorded; maxContext: the largest context_tokens any request of the session had.
export function contextLimitOf(model, maxContext = 0) {
  const m = String(model || '').toLowerCase();
  if (m.includes('[1m]') || Number(maxContext) > CONTEXT_LIMIT_DEFAULT) return CONTEXT_LIMIT_EXTENDED;
  return CONTEXT_LIMITS[familyOf(model)] || CONTEXT_LIMIT_DEFAULT;
}
