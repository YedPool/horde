module: core/roles
replaces: YedPool/wezfleet lib/Hierarchy.ps1 ($script:WfRoles, Test-WfLooksLikeRole, the literal role comparisons in Get-WfHierarchy and Test-WfMayMessage), lib/Master.ps1 (pending-claim role test at :135), lib/Registry.ps1 (role on read: Read-WfAllSessionRecords, Get-WfSession, Read-WfPaneClaim)
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

## What each source held

- **comments** - `lib/Hierarchy.ps1:1-33` (the structure and the vocabulary), `lib/Registry.ps1:128-158`
  (the 2026-09-15 wipe), `:293-304` (merge, never replace), `:1226-1235` and `:1269-1293` (the claim that lost
  the master's role), `lib/Master.ps1:118-128`, `hooks/wf-registry-refresh.ps1:158-162`.
- **history** - b9c9122, 4eba288, 4d24868, f37dee4, 91e63df, 5c25640, 17c5d42, c67aefc, 03810bc.
- **pull requests** - none carries a role change: the commits above were pushed directly (controlled null:
  the commit-to-PR lookup returned #17 for 561466d and nothing for these). #13, #15, #16 mention role only as
  corrections to the migration plan.
- **docs** - `planning/BUG-2026-09-15-registry-record-wipe.md`, `planning/wezfleet-v2-architecture.md`
  (field table at :150-165, section 4.3), `README.md:325-333`. `tasks/lessons.md` has no role entry (the same
  grep finds "claim" at lines 423 and 589, so the search worked).
- **tests** - `test_debug/test-hierarchy.ps1`, `test-master.ps1`, `test-registry.ps1`,
  `test-registry-hook.ps1`, `test-record-writes.ps1`. (`test-receipt.ps1` hits are transcript JSON
  `message.role`, unrelated.)

### L-001 wezfleet's whole vocabulary is three strings, and each maps to one Horde role
- source: YedPool/wezfleet lib/Hierarchy.ps1:28; horde planning/migration-plan.html:314-318
- disposition: test
- where: test/test-roles.ps1 :: "each wezfleet role reads as its horde role"

### L-002 Both vocabularies read correctly: a Horde value on a record reads as itself
- source: horde planning/migration-plan.html:554 step 0.8 "Both vocabularies read correctly"
- disposition: test
- where: test/test-roles.ps1 :: "a native horde role reads as itself"

### L-003 An absent role is unknown, never goblin, because every roleless record that mattered was a lost master or orchestrator
- source: YedPool/wezfleet f37dee4 "came up with NO ROLE AT ALL"; 17c5d42 and planning/BUG-2026-09-15-registry-record-wipe.md:3-4 (A, an orchestrator, lost its role)
- disposition: test
- where: test/test-roles.ps1 :: "a record with no role reads as unknown"
- expected live behaviour: measured read-only on the live wezfleet store, 2026-09-29: 31 records, 16 live, 13 with no role key, 9 of them live. So every exact role count there is unknown (warchief: at least 1, 9 unsure; orc: at least 6, the same 9). Callers use the floor, `atLeast`, and the `unsure` list; the exact `answer` becomes known only as roles are filled in. Encoded as test/test-roles.ps1 :: "an unknown role still leaves a known floor, and names the unsure session"

### L-004 Absent and empty are different facts; wezfleet collapses them, as it once collapsed unowned and not-returned
- source: YedPool/wezfleet lib/Registry.ps1:497 and :499-502; commit 5c25640; claims write an empty role at lib/Registry.ps1:1261
- disposition: test
- where: test/test-roles.ps1 :: "an absent role and an empty role are reported apart"

### L-005 Role values on disk are not validated, so an unrecognised value is unknown and keeps its raw text
- source: YedPool/wezfleet wezspawn.ps1:50 and hooks/wf-registry-refresh.ps1:181 (no check); the only check is lib/Hierarchy.ps1:131; roles were assigned by hand per f37dee4
- disposition: test
- where: test/test-roles.ps1 :: "an unrecognised role reads as unknown and keeps its raw value"

### L-006 Matching ignores case, because every wezfleet comparison does and the shadow run must agree
- source: YedPool/wezfleet lib/Hierarchy.ps1:32,46,47,53,172 and lib/Master.ps1:135 (PowerShell -eq and -contains are case-insensitive)
- disposition: test
- where: test/test-roles.ps1 :: "role matching ignores case as wezfleet does"

### L-007 Padding is not trimmed into a match, because wezfleet does not trim either
- source: YedPool/wezfleet lib/Hierarchy.ps1:46 compares the role untrimmed
- disposition: test
- where: test/test-roles.ps1 :: "a padded role is not trimmed into a match"

### L-008 Horde opens no wezfleet file for writing; the rename happens on read, so the writer that lost role is never exercised
- source: horde planning/migration-plan.html:334-351 and :554; YedPool/wezfleet b9c9122 (key-list rebuild ate role), 17c5d42 (concurrent writers deleted the record, lib/Registry.ps1:136-144), 03810bc
- disposition: test
- where: test/test-roles.ps1 :: "horde opens no wezfleet file for writing"

### L-009 A reader must not create lock or temp files either, because a held record lock makes the hook skip its write
- source: YedPool/wezfleet lib/Registry.ps1:147-149 (lock opened CreateNew), :157-158 "a writer that cannot get the lock in time gives up and writes nothing"
- disposition: test
- where: test/test-roles.ps1 :: "reading leaves no new file in any wezfleet store"

### L-010 Only a .json whose claudeSessionId matches its file name is a record; temp files sit beside them mid-write
- source: YedPool/wezfleet lib/Registry.ps1:120-123 and :188 (temp name id.pid.guid.tmp); one such .tmp found in the live store 2026-09-29
- disposition: test
- where: test/test-roles.ps1 :: "a temp file beside the records is not read as a record"

### L-011 An unreadable record makes role counts unknown; wezfleet's reader skips it silently and can report no master falsely
- source: YedPool/wezfleet lib/Registry.ps1:121 (catch continue) against :153-155; horde planning/migration-plan.html:360-361
- disposition: test
- where: test/test-roles.ps1 :: "an unreadable record makes the role count unknown"

### L-012 A pending spawn claim carries a role too, and it is read through the same table as a record
- source: YedPool/wezfleet lib/Master.ps1:118-137 (a pending master claim counts as a master, f37dee4); claims store role at lib/Registry.ps1:1261
- disposition: test
- where: test/test-roles.ps1 :: "a claim role is read through the same alias table"

### L-013 A retired record keeps its role; retiring is a tombstone and never erases who it was
- source: YedPool/wezfleet lib/Registry.ps1:438-445; test_debug/test-registry.ps1:336 "and retiring does not erase who it was"
- disposition: test
- where: test/test-roles.ps1 :: "a retired record still reads its role"

### L-014 Role is never inferred from the label, even though M, A and A7 look like roles
- source: YedPool/wezfleet lib/Master.ps1:27 (label M); planning/wezfleet-v2-architecture.md:162; horde planning/migration-plan.html:380-381
- disposition: test
- where: test/test-roles.ps1 :: "role is never inferred from the label"

### L-015 The reader returns the raw stored value beside the mapped one, so a dropped field cannot pass for an empty one
- source: YedPool/wezfleet commit 5c25640 (Get-WfSession never returned owner); lib/Registry.ps1:499-502
- disposition: test
- where: test/test-roles.ps1 :: "the raw role is returned beside the mapped role"

### L-016 The store root is WEZFLEET_ROOT when set, else Documents\Code\.wezfleet, and the no-write test runs on a copy through it
- source: YedPool/wezfleet lib/Common.ps1:13-17 "Override with WEZFLEET_ROOT to relocate the whole store (tests use this)"
- disposition: test
- where: test/test-roles.ps1 :: "the wezfleet store root honours WEZFLEET_ROOT"

### L-017 Exactly one master; two is a finding naming both and resolved by a person, never by timestamp
- source: YedPool/wezfleet lib/Hierarchy.ps1:21-24,77-87; commit 4eba288; test_debug/test-hierarchy.ps1:66 "two masters is reported"
- disposition: dropped
- reason: Cardinality is the projection's job (horde execution plan step 13), not the alias table's; this lesson belongs in that module's ledger and is listed here so it is carried forward rather than lost.

### L-018 A claim consumed only on the first tool call loses the identity it carries if it expires first
- source: YedPool/wezfleet f37dee4, 91e63df; lib/Registry.ps1:1226-1235 and :1274-1293
- disposition: dropped
- reason: Horde 0.8 spawns nothing and writes no claims; the lesson returns when Horde owns spawning, and that module's ledger must cite these commits.

### L-019 The finding kinds no-master, two-masters and orchestrator-not-under-master are computed, never stored
- source: YedPool/wezfleet lib/Hierarchy.ps1:80,84,94
- disposition: dropped
- reason: Nothing on disk holds these strings, so there is nothing to alias; Horde emits findings in its own vocabulary.

### L-020 Remote control was planned to follow role but was never built
- source: YedPool/wezfleet planning/wezfleet-v2-architecture.md:302-316; remoteControl is referenced only inside lib/Registry.ps1
- disposition: dropped
- reason: No wezfleet behaviour derives from role here, so the alias table has nothing to preserve; revisit at host decoration, step 7.2.

### L-021 No code assigns orchestrator or session; own sets a parent without a role
- source: YedPool/wezfleet commands/own.ps1:75 (Set-WfSessionParent without -Role); lib/Master.ps1:192 is the only literal role write
- disposition: comment
- where: core/Roles.ps1 :: "no wezfleet code assigns orchestrator or session"

### L-022 Reading must never block wezfleet's writer, so every read shares write and delete
- source: measured 2026-09-29 while building this module: YedPool/wezfleet lib/Registry.ps1:197 swaps a record in with [System.IO.File]::Replace, and that Replace fails while a reader holds the record with the ordinary read share that ReadAllText uses; with read, write and delete sharing it succeeds
- disposition: test
- where: test/test-roles.ps1 :: "a wezfleet write succeeds while horde holds the file open for reading"

### L-023 A pending master claim is a master that is not visible yet; Horde counts it, as its own number
- source: YedPool/wezfleet lib/Master.ps1:118-137 ("a PENDING claim naming a master counts as one"; a master idle three days came up with no role, 2026-09-14); pending means lib/Registry.ps1:1294-1307 with the 10080-minute backstop at :1235; horde PR #10 review, 2026-09-29, finding 4
- disposition: test
- where: test/test-roles.ps1 :: "a pending master claim is counted as a pending warchief, separately from sessions"
