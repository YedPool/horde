# Execution plan: from the harness to the fleet on `horde status`

Agreed 2026-09-29. The order of work through the rest of Phase 0, Phase 1 and Phase 2 of
`planning/migration-plan.html`, plus the host-folder move required by D12.

## How every step is done

Worktree from a freshly fetched `origin/main`. Ledger first wherever a module replaces anything.
Test-first. Every new check mutation-tested. Verified from a fresh CRLF checkout. Every code PR gets
an independent adversarial review before merge. `gh pr merge --merge`, never squash. Every count in a
commit or PR is copied from command output.

## Steps

A. Close PR #4 (isolation harness)
1. Independent re-review of the kill-safety fixes.
2. Fix findings, rerun fast + ledger + e2e, merge.

B. Host folder (D12)
3. Move the WezTerm harness from `test/harness/` to `hosts/wezterm/test/`; update callers and
   ledger paths. No behaviour change.
4. A ratchet test: no WezTerm-specific name outside `hosts/wezterm/`, with a shrink-only allowlist.

C. Phase 0 remainder
5. 0.6 Ownership and source precedence as data; every field has exactly one owner and one rule.
6. 0.7 `core/tristate` with its ledger and unit suite.
7. 0.8 Role alias table on read; a test proves no wezfleet file is opened for writing.
8. 0.9 `horde` entry point, help generated from a command table; first e2e scenario runs
   `horde --help` and `horde version` in the isolated terminal. MILESTONE 1: reported.

D. Phase 1: the contract
9. `schema/pane-session.v1`: the existing format documented exactly, golden fixtures.
10. `schema/session-record.v1`, with role and parent.
11. `schema/restore-plan.v1`, with a degraded plan per host.

E. Phase 2: the read model
12. `core/identity`: one record shape from every agent's control files; no terminal in it.
13. The projection: reads every old store, writes nothing, proven by test.
14. `horde status --json`, with parity against today's commands on the same fixtures. Its output is
    described by `schema/session-view.v1`, deferred here from step 10, which describes only the record
    the engine stores: one answer for every field in `core/ownership.json`'s `required`, over every
    owner; each answer in `core/tristate`'s form (known, absent, unknown); its provenance (the store
    and field it was read from); the provisional mark wherever the ownership table has one; and a
    value type per field, the same as `schema/session-record.v1`'s for a field the engine stores.
15. Battle test (D11): the Warchief runs `horde status` beside `wezfleet status` and logs every
    disagreement. MILESTONE 2: reported.

## Recorded along the way (2026-09-30)

- The engine's stored session record gets its one writer in Phase 3 (migration-plan step 3.8):
  the first Horde command that sets role, parent or label owns it.
- Open follow-ups in core/Schema.ps1, from the reviews of PRs #15 and #17: a `$ref` given as a
  non-string is followed rather than refused; definitions nothing refers to are never checked;
  the recursion depth limits (about 47 levels through ConvertFrom-Json, about 100 built in
  PowerShell) are not stated in the header; a `minimum` keyword would let the schema itself
  refuse a negative labelCycle.
  Closed on branch fix/schema-followups: a non-string `$ref` is refused; every definition is
  checked once, referenced or not; the measured limits (102-deep JSON, so a plan's layout root 46
  containers deep; call depth overflow at 127 containers for a tree built in PowerShell) are in
  the header; minimum is implemented and session-record.v1 states labelCycle >= 0; and
  core/RestorePlan.ps1 no longer refuses a Decimal ratio just below 1.
