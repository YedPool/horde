module: core/metrics-transcript (core/Transcript.ps1, core/Metrics.ps1, core/MetricsReport.ps1, agents/claude-code/Transcript.ps1, agents/codex/Transcript.ps1)
replaces: the 2026-09-30 goblin-versus-agent study's throwaway extractors (scratchpad study/: worker-extract.js, orc-extract.js, join.js, orccat.js, window.js, reaps.js, rows.js, summ.js), and carries what YedPool/wezfleet lib/CodexStatus.ps1 and the 2026-09-30 Codex rollout measurement learned about Codex's files; CodexStatus.ps1 itself stays in wezfleet, read-only, and nothing here calls it
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

How the five sources were searched, 2026-10-01. Comments: every line of the eight scripts and of
lib/CodexStatus.ps1. History and pull requests: the scripts were never committed anywhere, so they
have none; lib/CodexStatus.ps1's own history is covered by planning/ledger/core-tristate.md, and the
entries below cite its lines. Docs: the study (goblin-vs-agent-study-20260930.md, sections 1.3, 1.4,
4, 5 and 9), the metrics design (2.1, 2.5, 2.9, 8), the experiment program (3.1, 3.4, 12.2) and the
Codex rollout measurement. Tests: the scripts had none; their positive controls are the study's
section 1.3 table, and each is carried below or dropped with its reason.

### L-001 One API response is many lines; count it once, with the usage of its last (largest) line
- source: study/worker-extract.js `msgs` keyed by `message.id`, with `rec.usage=m.usage` on every line, so the LAST line's usage stood; study 1.4; metrics design 2.1 (1.6x to 1.9x inflation when lines are summed); review of PR #50, F1 (the first-line rule undercounted subagent output by 88.9 percent)
- disposition: comment
- where: agents/claude-code/Transcript.ps1 :: "usage is the PER-FIELD MAXIMUM across them"

### L-002 A repeated call id is never summed twice, whatever the adapter does
- source: metrics design 2.1, "dedupe globally by requestId"; study/join.js counts orc calls per unique id
- disposition: test
- where: test/test-metrics.ps1 :: "three still-waiting calls; the repeated id is counted once"

### L-003 Claude Code's input_tokens excludes cache; the four usage fields add up
- source: study/worker-extract.js `u.in`, `u.cr`, `u.cc`, `u.out`; experiment program 12.2 "for Claude, the sum of the four fields"
- disposition: comment
- where: agents/claude-code/Transcript.ps1 :: "input_tokens EXCLUDES cache reads and writes on this harness"

### L-004 A notification arrives as user text or as a queued_command attachment
- source: study/orc-extract.js (user string, text block and `attachment.queued_command` all tested for `<task-notification>`); measured 2026-10-01: 594 string and 137 queued in the orchestrator's transcript
- disposition: comment
- where: agents/claude-code/Transcript.ps1 :: "NOTIFICATIONS are user content or a queued_command attachment"

### L-005 The queue's bookkeeping lines repeat a queued prompt and are not input
- source: study/orc-extract.js never reads `queue-operation`; measured 2026-10-01: 2,956 such lines in the orchestrator's transcript
- disposition: comment
- where: agents/claude-code/Transcript.ps1 :: "The queue-operation lines repeat a queued prompt as bookkeeping"

### L-006 isMeta user lines are the harness's text, not a trigger
- source: study/orc-extract.js classifies them `M`, which join.js never treats as a trigger
- disposition: comment
- where: agents/claude-code/Transcript.ps1 :: "isMeta and isCompactSummary user lines are the harness's own text"

### L-007 An interim notification says "still running" or "may be interim"
- source: study/join.js `/still running|may be interim/`; study 5.2 (124 interim notifications)
- disposition: comment
- where: agents/claude-code/Transcript.ps1 :: "Interim notifications are those whose text says"

### L-008 A still-waiting turn: no tool call, under 400 characters, answering a notification
- source: study/join.js `isWait`; study 1.4; experiment program A5
- disposition: test
- where: test/test-metrics.ps1 :: "the planted still-waiting call is found"

### L-009 The 400-character limit is a chosen number awaiting validation, so it is a parameter
- source: experiment program 3.4 (hand-label 20 turns, precision and recall at least 0.9)
- disposition: test
- where: test/test-metrics.ps1 :: "the character limit is a parameter: at 20 characters the 25-character call is not counted"

### L-010 A reply after a tool result answers the tool, not an earlier notification
- source: study/join.js keeps `lastTrigEv` across tool results, so a call answering a tool result after a notification counted as waiting; found while porting, 2026-10-01
- disposition: test
- where: test/test-metrics.ps1 :: "a tool result between the notification and the reply means the reply answers the tool, not the notification"

### L-011 What a still-waiting turn cost is the context it processed: input plus both cache counts
- source: study/join.js `ctx(u)`; study 5.2 (53.77M tokens over 106 turns)
- disposition: test
- where: test/test-metrics.ps1 :: "with the context it processed: input + cache read + cache write = 90305"

### L-012 Attribution by "a message naming the worker in the same turn" over- and under-attributes
- source: study/join.js `named()` and turn windows; study section 9 item 3 (427 of 898 calls unattributed, examples of both errors)
- disposition: test
- where: test/test-metrics.ps1 :: "what cannot be proved is counted unattributed (476 + 50), never given to a worker"

### L-013 A notification about a background shell job is not a worker's result
- source: study/orc-extract.js and join.js treat every notification as a possible worker; measured 2026-10-01: background-command notifications carry the shell call's tool-use id
- disposition: test
- where: test/test-metrics.ps1 :: "a notification about a background job is a job, not a worker result"

### L-014 A call naming several workers was split evenly between them
- source: study/join.js `f=1/ids.length`
- disposition: dropped
- reason: M1 attributes nothing by naming, so there is no multi-name call to split; plan step M2's orchestrator-attention measure (A4) decides how a proven multi-worker call is shared, with its own test.

### L-015 Characters convert to tokens at the measured 2.38, and the result is an estimate
- source: study/join.js `CPT=2.38`; study 1.4 (53 pairs, IQR 2.27 to 2.53, includes hook overhead)
- disposition: test
- where: test/test-metrics.ps1 :: "tokens are estimated at 2.38 characters each (3618 / 2.38 = 1520) and labelled ESTIMATE"

### L-016 Purity is better measured by usage delta than by characters
- source: study 4.5; experiment program A3
- disposition: dropped
- reason: not built in M1, which keeps the character estimate; plan step M2 builds the usage-delta measure and keeps the characters only to calibrate it.

### L-017 The longest silence is a gap between consecutive events, with what preceded it
- source: study/worker-extract.js `gaps` (5 minutes or more, with the pending call); study 5.1
- disposition: test
- where: test/test-metrics.ps1 :: "the longest silence is the same 300 minutes, starting when the call went out"

### L-018 Every gap of five minutes and more, listed with its kind (A>R, A>U)
- source: study/worker-extract.js `gaps`; study 1.4 "Stall gap"
- disposition: dropped
- reason: M1 reports the longest gap only, as asked; the full list and its classification are the stall detectors of plan step M6, which need their own positive controls.

### L-019 A tool call's duration is its result's time minus its own
- source: study/worker-extract.js `longest`
- disposition: test
- where: test/test-metrics.ps1 :: "with its name, its start, and that it returned"

### L-020 A tool call with no result was skipped, so a frozen call never counted
- source: study/worker-extract.js `if(!rr)continue`; study 5.1 (two calls frozen 314 and 325 minutes)
- disposition: test
- where: test/test-metrics.ps1 :: "a tool call with no result is counted to the last event (60 minutes) and flagged as not returned"

### L-021 The model is per message, and a session can use more than one
- source: study/worker-extract.js `models`; study 8 (two models in one orchestrator)
- disposition: test
- where: test/test-metrics.ps1 :: "the model is the one most calls used, and every model is listed with its calls"

### L-022 An API-error message is written as an assistant line with a "<synthetic>" model
- source: measured 2026-10-01, 14 such lines in the orchestrator's transcript; the study's scripts counted them as calls
- disposition: comment
- where: agents/claude-code/Transcript.ps1 :: "is the harness reporting an API error"

### L-023 A tool result's size is the text of its blocks
- source: study/worker-extract.js `txt()` (text blocks only); study/orc-extract.js counted other blocks as JSON, so the two disagreed
- disposition: comment
- where: agents/claude-code/Transcript.ps1 :: "Tool results are measured as the characters of their text blocks"

### L-024 A turn ends at the harness's turn_duration line
- source: study/orc-extract.js `T` events; study/join.js `turn++`
- disposition: comment
- where: agents/claude-code/Transcript.ps1 :: "Turn ends are the harness's turn_duration lines"

### L-025 A compaction boundary is an event of its own
- source: study/orc-extract.js `C`; study/worker-extract.js `compacts`
- disposition: comment
- where: core/Transcript.ps1 :: "the harness compacted its context"

### L-026 A line that does not parse was silently skipped
- source: study/orc-extract.js and worker-extract.js `try{JSON.parse(l)}catch{return}`; metrics design 2.1 ("never a silently smaller number")
- disposition: test
- where: test/test-transcript-port.ps1 :: "a bad last line that ends with a newline is skipped, not torn"

### L-027 A file being appended to must be read without blocking its writer
- source: Codex rollout measurement (tail.ps1 held files with FileShare ReadWrite and Delete, no failure across resume); core/ReadShared.ps1
- disposition: test
- where: test/test-transcript-port.ps1 :: "a file a writer holds open for appending is read"

### L-028 Missing usage is not zero
- source: YedPool/wezfleet lib/CodexStatus.ps1:420 and :504-511 ($null against @(), carried by planning/ledger/core-tristate.md L-004); study/worker-extract.js `x.input_tokens||0`
- disposition: test
- where: test/test-metrics.ps1 :: "a call with no usage makes the token total unknown, not smaller"

### L-029 Codex counts cached input inside input_tokens
- source: experiment program 12.2; Codex rollout measurement ("input 19275 / cached 18816")
- disposition: comment
- where: agents/codex/Transcript.ps1 :: "input_tokens INCLUDES cached_input_tokens on this harness"

### L-030 Codex writes a usage line per response; token_count misses an interrupted one
- source: Codex rollout measurement (`token_usage_record` "after every model response"); measured 2026-10-01 on rollout 01a0f4cf, 6 records against 5 token_count lines
- disposition: comment
- where: agents/codex/Transcript.ps1 :: "ONE CALL PER MODEL RESPONSE, from token_usage_record lines"

### L-031 A Codex turn that fails or is interrupted fires no Stop hook, but its rollout still ends it
- source: YedPool/wezfleet lib/CodexStatus.ps1:34-36 ("Stop was MEASURED not to fire on a turn that fails and not to fire on a turn that is interrupted"); Codex rollout measurement (task_complete with error; turn_aborted)
- disposition: comment
- where: agents/codex/Transcript.ps1 :: "TURN ENDS are task_complete and turn_aborted"

### L-032 Codex names its model per turn, never per message
- source: Codex rollout measurement, `model.perMessage` no, per turn yes
- disposition: comment
- where: agents/codex/Transcript.ps1 :: "The MODEL is per turn, from turn_context"

### L-033 After a Codex compaction the earlier context is re-emitted and is not new input
- source: Codex rollout measurement, run A ordinals 55-57
- disposition: comment
- where: agents/codex/Transcript.ps1 :: "USER INPUT is event_msg item_completed of a UserMessage"

### L-034 A Codex status reading expires instead of being cleared
- source: YedPool/wezfleet lib/CodexStatus.ps1:32-44 (the self-expiring busy flag and its TTL)
- disposition: dropped
- reason: that is about whether a live session is working, which a metrics reader of finished and growing transcripts does not decide; the lifecycle plan's liveness work carries it.

### L-035 The Codex hook events and their payloads
- source: YedPool/wezfleet lib/CodexStatus.ps1:16-23 and :59-63
- disposition: dropped
- reason: M1 has no live hooks by design; the rollout file is read after the fact, and a live collector that would need hook events is not planned before step M7's consent records.

### L-036 Identical repeated calls, re-reads, retries after errors and foreground polling loops
- source: study/worker-extract.js `repeats`, `rereads`, `retryAfterErr`, `fgWait` regex; study 1.3 positive controls (a436cf6 lines 948, 970, 977 and 886)
- disposition: dropped
- reason: these are the failure-pattern detectors of plan step M6, each to be built with the study's positive control; M1 measures the headline numbers only.

### L-037 Edit flip-flops were searched for with no known positive
- source: study/worker-extract.js `flips`; study 1.3 ("0 found; the 0 is UNPROVEN")
- disposition: dropped
- reason: an instrument with no known positive cannot be shown to work (CONTRIBUTING 7); plan step M6 builds it only when a real flip-flop is found to control it.

### L-038 Reap notices: a killed job with "low on memory"
- source: study/reaps.js and worker-extract.js `reaps`; study 1.3
- disposition: dropped
- reason: a lifecycle signal, carried by plan step M6's detectors and the lifecycle plan, not by M1's summary.

### L-039 Pull requests created and merged, read from gh command text and results
- source: study/worker-extract.js `prCreated`, `prMerged`, `pushes`
- disposition: dropped
- reason: an outcome must never come from the span it is about (metrics design section 5); plan step M8 reads outcomes from git and GitHub.

### L-040 The worker's final message was kept to read its verdict
- source: study/worker-extract.js `lastText` and finals/*.txt
- disposition: dropped
- reason: Horde stores no text at any level (metrics design section 8, rule 2); verdicts are graded outside the metrics store (experiment program section 4).

### L-041 Goblins and their run keys were entered by hand
- source: study/join.js `gob` and `runKeys`
- disposition: dropped
- reason: hand-entered attribution is what M1 refuses; plan step M2 links spans from meta.json and run records.

### L-042 The orchestrator's own reads were classified by command patterns
- source: study/orccat.js and join.js `readRe`; study 4.2 and 4.5
- disposition: dropped
- reason: purity by source class is plan step M2, measured by usage delta rather than by pattern-matching command text, which M1 does not keep.

### L-043 Medians, rows and the timeline viewer
- source: study/rows.js, summ.js and window.js
- disposition: dropped
- reason: tabulation and comparison are the report and compare steps (M3 and M9); window.js was a debugging view, not a measure.

### L-044 Peak context per worker
- source: study/worker-extract.js `peakCtx`; study 8 (966,153 tokens)
- disposition: dropped
- reason: not among M1's asked measures; plan step M2 adds it with the usage-delta work, where it is read from the same per-call context sums.

### L-045 The study counted a day by cutting at a time
- source: study/join.js `DAY` and the 15:36:39 UTC cutoff
- disposition: comment
- where: core/MetricsReport.ps1 :: "The records whose time is inside"
