# Execution plan: metrics - measuring the horde from what is already on disk

Agreed 2026-10-01 (the founder's "Go" for M1). The order of work that turns the metrics design into
code. Its companions on `origin/main` are `planning/execution-plan-engines.md` (the engine
configuration the gate will live in, and the `agents/<name>/` ratchet), `planning/execution-plan-phase-3.md`
(`Get-HordeHome`, step 1) and `planning/execution-plan-lifecycle.md`. This plan builds nothing those
plans build; where it needs their work it names the step.

Planning prose may name harnesses and terminals. Code may not (CONTRIBUTING 14): every transcript
format, field name, store path and tool name of a harness lives in `agents/<name>/`, and `core/`
speaks only of calls, tool calls, inputs, turns, tokens, confidences and workers.

## Sources, and what is settled

The metrics design (2026-09-30, read-only, not committed; cited "MD" with its section), its handoff,
the experiment program (cited "EP"), the 2026-09-30 goblin-versus-agent study (cited "Study"), which
was reconstructed by hand with throwaway scripts, and the Codex rollout measurement of 2026-09-30.

From the design's "Decisions taken", binding on every step:

1. **Local-only counting.** Tokens and usage come only from transcripts, rollouts and harness logs on
   this machine. Horde never calls a vendor usage or billing API. The `metered` tier and `reconcile`
   are dropped.
2. **Gated, off by default, no environment override.** No environment variable turns metrics on or
   raises their level. A repo's engine file may lower the level, never raise it. Nothing recorded
   before consent is backfilled.
3. **Cost from a versioned price table**, never from the harness's own cost field. On a subscription
   it is a labelled notional figure, never summed into a USD total.
4. **Every value carries provenance and a confidence tier** (MD 1.2): `reported` (the harness wrote
   it), `derived` (computed from reported numbers by a stated, versioned rule), `estimated`
   (approximated by a method that can be wrong), `unknown` (with a reason). The design's `metered`
   tier is gone with decision 1.

Two placement decisions this plan takes, because CONTRIBUTING 14 forces them:

- **The price table is user data, not repository data.** `agents/claude-code/names.txt` already
  records that model ids "live in the user's own engine file and never in the repository", and the
  provider's model ids contain the harness's product name as a substring, so a table in `core/` would
  grow the ratchet. The table is `<HordeHome>\metrics\prices.json`, versioned by its own `version`
  field; every cost carries that version. The observed table of 2026-09-30 (MD 2.9) is given below
  for the founder to install, and the tests use fixture tables.
- **Adapter tests live in `agents/<name>/test/`**, like a host's in `hosts/<name>/test/`, because their
  fixtures are the harness's own files. `test/test-suite.ps1` learns to find them (M1).

## When each step can start

- **NOW**: needs only what is on `main`.
- **CONFIG**: waits for engine-settings E3 and E4 (`core/EngineConfig.ps1`, `core/EngineResolve.ps1`).
- **SPAWN**: waits for Horde's spawn and launch commands (migration step 3.8, engines E10).

## Steps

### M1. The transcript port, two adapters, and `horde metrics summarize` (NOW, this PR)

A reader with no live hooks. It replaces the study's throwaway extractors with instruments that carry
positive controls, so the study's headline measures come from code rather than by hand.

- **The port, `core/Transcript.ps1`.** An adapter turns one transcript into normalized records, in
  file order: `call` (one model request, deduplicated, with its model and its input, cache-read,
  cache-write and output tokens), `toolCall` and `toolResult` (paired by id), `input` (a user message
  or a notification, with its link to a worker when the transcript proves one), `turnEnd`,
  `compaction`, and `event` (any other timestamped line, kept for gap measurement). Anything a
  transcript does not say is a `core/tristate` unknown with a reason. Records carry lengths and ids,
  never text. The reader opens transcripts read-only and shared, and counts the lines it could not
  parse instead of dropping them silently.
- **Two adapters**, `agents/claude-code/Transcript.ps1` (session JSONL, its `subagents/` folder) and
  `agents/codex/Transcript.ps1` (rollout JSONL). Each declares its own store roots, so the writer can
  refuse to write inside them.
- **`core/Metrics.ps1`**: a per-worker summary (wall-clock from first to last event; tokens by kind;
  model calls; tool calls; the longest gap with no event and when it started; the longest single tool
  call, an unreturned one counted to the last event and flagged; the model) and the orchestrator
  measures of the Study: "still waiting" calls (no tool call, under 400 characters of text, answering
  a notification; Study 1.4, EP A5) with the context tokens they processed, and the characters of
  worker results landing in the orchestrator's context, with tokens ESTIMATED at the Study's measured
  2.38 characters per token. Both are attributed to a worker only where the transcript proves the
  link; the rest is counted as unattributed, never guessed.
- **`core/Price.ps1`**: cost per call from the price table, `derived`, tagged ESTIMATE, labelled
  `notionalUsd`, with the table's version. A call on a model the table does not price makes the total
  unknown, with the model named.
- **`core/MetricsStore.ps1`** and **`core/Home.ps1`**: `Get-HordeHome` (`HORDE_HOME`, default
  `%USERPROFILE%\.horde`, as Phase 3 step 1 specifies; that step still renames `HORDE_ROOT`). The
  interim gate is `<HordeHome>\metrics\gate.json`, `{ schemaVersion, level, enabledAt }`, level `off`
  or `usage`; no file means off, an unreadable one is refused. Records are written to
  `<HordeHome>\metrics\summaries\` only when the gate says `usage` and the transcript began after
  `enabledAt` (decision 2: no backfill). Writes are atomic and never land inside an adapter's store
  root.
- **`horde metrics summarize <transcript|dir> [-From] [-To] [-Json]`** prints a table. Reading a file
  the user names is not gated; recording is. A windowed summary is never recorded.
- **Proof**: positive controls for every instrument (fixtures with known counts, a planted "still
  waiting" call and a planted 300-minute tool call), a clean fixture that finds none, a planted-secret
  test with its control, mutation specs, and a read-only reality check over the orchestrator's own
  transcript compared with the Study's method.
- **Ledger**: `planning/ledger/core-metrics-transcript.md`, for the study scripts and wezfleet's Codex
  knowledge this replaces.

### M2. Spans, and the batch-1 measures (NOW)

What batch 1 of the experiment program needs and M1 does not give (EP 3.1, EP 9).

- Each `subagents/agent-<id>.jsonl` becomes an `agent` span linked to the orchestrator's launch call
  through its `meta.json` `toolUseId`; a session's total is the parent plus its spans, deduplicated
  across files.
- A2: wall-clock from the launch call to the first final (not interim) completion notification.
- A3: context landed by usage delta (Study 4.5), the growth in input plus cache tokens between
  consecutive orchestrator calls, split by the events between them; the character estimate is kept
  only to calibrate it.
- A4: orchestrator attention per worker, by proven links only (the launch call, a notification's
  turn, a resume message to the worker's id). The Study's name-window heuristic is not ported (Study 9
  item 3).
- `schema/metrics-summary.v1.json` for the record M1 writes, validated before writing.

### M3. The event envelope and the writer (NOW)

`schema/metrics-event.v1.json` (MD 4.2) with golden and rejected fixtures; one file per writer with
`seq` from the writer's own counter, a size cap with a recorded `truncated`; `horde metrics harvest`
and `horde metrics report --json` over the recorded summaries.

### M4. The price table, complete (NOW)

The lookup key of MD 2.9: provider, model, timestamp, input size, speed, geography, service tier.
Context tiers, time-of-day windows, fast mode, the stale-table warning, and `horde metrics price
list|show|verify`. `verify` diffs; it never edits a table.

### M5. Codex quota, and the cross-engine normaliser controls (NOW)

`rate_limits.used_percent` as a `quota` reading (MD 2.7), never summed; for every engine, the
normaliser's classes summed against the engine's own total on a real file (EP 12.2).

### M6. The failure-pattern detectors (NOW)

The Study 5.6 table as instruments, each with a positive control from the Study 1.3 list: frozen tool
call, silent background job, identical-call loop, re-read, error-retry loop, foreground polling loop,
reap notice. The edit flip-flop detector waits for a known positive.

### M7. The gate in the engine configuration, and consent records (CONFIG)

`metrics.*` keys through the engine resolver (MD 7), the lower-only project rule, the environment
test with its control, the consent sentinel, and harvest refusing sessions with no consent. The
interim `gate.json` of M1 is migrated and removed.

### M8. Outcomes (NOW)

`git` and `gh` outcome events attributed by branch and window (MD 2.10, M7 of the design).

### M9. Compare and route (NOW, after M8)

`horde metrics compare` with all the refusals of MD 10.3, and `horde metrics route`, the routing
guide (MD "Founder direction").

### M10. Retention, compaction and export (NOW)

MD 9 and MD 8's export allowlist with its planted-secret test.

## The observed price table (2026-09-30), for the founder to install

Copy into `<HordeHome>\metrics\prices.json`. Rates are USD per million tokens. Source:
https://platform.claude.com/docs/en/about-claude/pricing and https://developers.openai.com/api/docs/pricing ,
read 2026-09-30 (MD 2.9). Only models observed on this machine are listed; anything else prices as
unknown.

```
{
  "schemaVersion": 1,
  "version": "2026-09-30.1",
  "observedAt": "2026-09-30",
  "currency": "USD",
  "perTokens": 1000000,
  "models": {
    "claude-opus-5-5": { "provider": "anthropic", "rates": { "input": 4, "cacheWrite5m": 5, "cacheWrite1h": 8, "cacheRead": 0.2, "output": 20 }, "geo": { "us": 1.1 }, "geoStandard": ["not_available", ""] },
    "claude-opus-5":   { "provider": "anthropic", "rates": { "input": 5, "cacheWrite5m": 6.25, "cacheWrite1h": 10, "cacheRead": 0.5, "output": 25 }, "geo": { "us": 1.1 }, "geoStandard": ["not_available", ""] },
    "gpt-5.5":         { "provider": "openai", "rates": { "input": 5, "cacheRead": 0.5, "output": 30 } }
  }
}
```
