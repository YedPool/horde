// relays/cloudflare/worker/answers.js - how the Worker answers in JSON, success or refusal. A refusal
// is { "error": "<words>" } with its HTTP status; the words are this Worker's own and never quote what
// the request carried, so nothing a caller sent is ever echoed back.
export function answer(status, body) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

export function refuse(status, words) {
  return answer(status, { error: words });
}
