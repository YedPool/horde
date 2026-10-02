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

- **The price tables live in the repository, one per engine, at `agents/<name>/prices.json`**
  (coordinator's decision, 2026-10-01). `agents/<name>/` is where CONTRIBUTING 14 allows a harness's
  and its models' names, and a price change becomes a reviewable commit. A user may add
  `<HordeHome>\metrics\prices.json`, an override layered on top: a model it prices replaces the
  repository's entry for that model. Every table carries a `version`, and every cost names the file
  and version of each table that priced it. (M1's first draft kept the table only in HORDE_HOME,
  because model ids contain the harness's name; the engine folder resolves that without the ratchet
  growing.)
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
- **`core/Price.ps1`**: cost per call from the price book - every `agents/<name>/prices.json` with the
  user's override on top - `derived`, tagged ESTIMATE, labelled `notionalUsd`, naming the file and
  version that priced it. A call on a model no table prices makes the total unknown, with the model
  named.
- **`core/MetricsStore.ps1`** and **`core/Home.ps1`**: `Get-HordeHome` (`HORDE_HOME`, default
  `%USERPROFILE%\.horde`, as Phase 3 step 1 specifies; that step still renames `HORDE_ROOT`). The
  gate is a STOPGAP, accepted for M1 only (coordinator, 2026-10-01) and replaced in M2 by a setting
  under `horde config`: `<HordeHome>\metrics\gate.json`, `{ schemaVersion, level, enabledAt }`, level `off`
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

- **First: running totals instead of per-line records** (coordinator's decision, 2026-10-02). Measured
  on the always-on box on 2026-10-02 (review of PR #50): the JSONL reader streams - its peak working
  set stays at 124 MB from a 33 MB to a 133 MB transcript - but `horde metrics summarize` peaked at
  593 MB and 1,734 MB (80 s and 477 s) on those files, because the adapter keeps one record per line
  and core keeps answer objects for each; about 11 MB of memory per MB of transcript. The adapter and
  the measures fold each line into running totals (calls, tokens, gaps, open tool calls, the
  still-waiting state) instead. Target: peak working set under 200 MB on the 133 MB file, measured
  the same way, with the probe kept as a suite so a regression fails the gate.
  **Built (PR for M2 part 1):** the adapters read twice - facts per id, then records in M1's order -
  and hand each record to a sink; `core/Metrics.ps1` folds them into running totals. Output pinned
  byte for byte to M1's by golden files written by M1's own command; `agents/claude-code/test/test-summarize-memory.ps1`
  is the probe as a suite. Measured 2026-10-02 on the always-on box: 256 MB on both the 33 MB and the
  133 MB transcripts (M1: 599 and 1,734 MB), and byte for byte M1's output on 13 runs over large
  varied transcripts. The bare command's floor - the same command on a one-response transcript - is
  164 MB on that box and 143 MB on the working box (where the 33 MB file peaks at 155 MB); a forced
  collection every 1,000 lines did not lower the peak. The 200 MB target is restated (coordinator,
  2026-10-02): flat with file size, and within 120 MB of the floor on the same box (measured +92 MB
  and +12 MB); the rise is the garbage collector's room on a box with memory to spare, not records.
- **`horde metrics collect`** (founder, 2026-10-02: "I want the metrics collector on until we have a
  clear initial method for when to use a real session, when an agent etc."). Finds every transcript in
  the folders each `agents/<name>/stores.json` declares under `transcripts`, and records what is new
  or changed since its last run, keyed in `<HordeHome>\metrics\collect-index.json` by path, size and
  modification time. The gate exactly as summarize; a file last written before consent is not read; a
  transcript written within the last 10 minutes is recorded as provisional and collected again once
  still; one run at a time; never writes in an engine's folder.
- **`horde metrics schedule install|remove|status`**: one job, "Horde metrics collect", every 30
  minutes as the current user, priority 7, stopped after 20 minutes, installed only while the gate
  says usage. `core/Schedule.ps1` defines the job; `core/schedule/WindowsTaskScheduler.ps1` is the
  first scheduler; cron or a systemd timer is a new file there.
- **Found while keeping M1's output (for its own pull request):** M1 sorted records with Sort-Object,
  which is not stable on PowerShell 5.1 (measured 2026-10-02: 17,773 of 50,000 tied records
  reordered), so the kind it reports before the longest silence, when several records share that
  time and line, is whatever the sort did. M2 replays the same sort to stay byte for byte M1; a stable
  rule is an intended change of output, with new golden files.
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
- **The gate becomes a setting** (coordinator's decision, 2026-10-01): `metrics.level` in the layered
  engine-settings precedence, read and written through `horde config` (`horde config set metrics.level
  usage --scope user`, shown with its provenance by `horde config explain`), the project layer allowed
  only to lower it (MD 7.3), and no environment variable able to change it (MD 7.2, with the test and
  its control). M1's stopgap `<HordeHome>\metrics\gate.json` is migrated into the user layer, keeping
  its `enabledAt` as the consent time, and then removed. This item waits for engine-settings E3 and E4
  (`core/EngineConfig.ps1`, `core/EngineResolve.ps1`); the rest of M2 does not.

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

### M7. Consent records (CONFIG)

The consent sentinel per session (MD 7.4), written at spawn and deleted at close, and harvest
refusing sessions with no consent record. The gate itself moves into the engine settings in M2.

### M8. Outcomes (NOW)

`git` and `gh` outcome events attributed by branch and window (MD 2.10, M7 of the design).

### M9. Compare and route (NOW, after M8)

`horde metrics compare` with all the refusals of MD 10.3, and `horde metrics route`, the routing
guide (MD "Founder direction").

### M10. Retention, compaction and export (NOW)

MD 9 and MD 8's export allowlist with its planted-secret test.

## The observed price tables (2026-09-30)

In the repository: `agents/claude-code/prices.json` (Anthropic models; source
https://platform.claude.com/docs/en/about-claude/pricing) and `agents/codex/prices.json` (OpenAI models;
source https://developers.openai.com/api/docs/pricing), both version `2026-09-30.1`, read 2026-09-30
(MD 2.9). Rates are USD per million tokens. A model neither table lists prices as unknown. A user who
pays different rates puts only the models that differ in `<HordeHome>\metrics\prices.json`, with a
version of their own.
