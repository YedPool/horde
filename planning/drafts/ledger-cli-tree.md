DRAFT - not a ledger yet. Kept outside planning/ledger/ because its test dispositions cite suites
that do not exist; test/test-ledger.ps1 would fail on it there. Its command's first PR (steps 12-14 of
planning/execution-plan-phase-3.md) deletes this paragraph and the next, moves the file to
planning/ledger/cli-tree.md, and adds the tests in the same PR.

Adapted: L-018 is carried in `cli/Tree.ps1`, which outlives the shadow harness, and says what step 12 does - fault kinds map through one table of old and new names, while roles map through `core/roles`. L-019 is carried in `cli/Tree.ps1` rather than in an adoption line, which would break the day that line moves to `horde`.

module: cli/tree
replaces: YedPool/wezfleet commands/tree.ps1 (Invoke-WfTree), the display use of lib/Hierarchy.ps1 (Get-WfHierarchy, Get-WfHierarchyFindings) and lib/Common.ps1 (Format-WfRecordPane)
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

## What each source held

- comments: commands/tree.ps1:5-9, :38-39, :50-52; lib/Hierarchy.ps1:1-24, :36-39, :49-51, :77-78, :100-102, :113-117;
  lib/Common.ps1:598-601.
- history: git log --follow commands/tree.ps1: b1770fb, 0e1c75a; pickaxe Invoke-WfTree: 4eba288; lib/Hierarchy.ps1:
  4eba288 only; 1e8837a made own write the parent edge tree draws.
- pull requests: none touched commands/tree.ps1 or lib/Hierarchy.ps1 (gh pr list, 17 pull requests, --json files).
- docs: planning/BUG-2026-09-15-restart-pane-identity.md:72 "display only: tree (3 sites), master (3 sites)"; horde
  planning/migration-plan.html section 2 correction (Hierarchy.ps1:85); README.md:109;
  ~/.claude/skills/master-orchestrator-handoff/SKILL.md:67-68 (scope names from ROSTER.md or wezfleet tree).
- tests: test_debug/test-hierarchy.ps1 (24 assertions); test-instance.ps1:239-240; strays M found reading tree:
  test-delivery.ps1:68-69, test-registry-hook.ps1:183, :303, test-safe-kill.ps1:58.
- carried elsewhere, not repeated: the fault rules are core/projection L-035 to L-040 and L-072, and P-24, P-25.

### L-001 Looking at the tree costs nobody a message
- source: YedPool/wezfleet commands/tree.ps1:5-9; lib/Hierarchy.ps1:11-15; 4eba288; test_debug/test-hierarchy.ps1:112, :116 (a tripwire and its control)
- disposition: test
- where: test/test-tree.ps1 :: "drawing the tree calls no host verb at all"

### L-002 A child hangs under its parent by session id, never by name
- source: YedPool/wezfleet lib/Hierarchy.ps1:17-19; commands/own.ps1:51-64; 1e8837a (own wrote a name, tree read an id, and they disagreed)
- disposition: test
- where: test/test-tree.ps1 :: "a child is drawn under its parent by session id"

### L-003 Every finding reports and nothing repairs
- source: YedPool/wezfleet commands/tree.ps1:50-52; lib/Hierarchy.ps1:21-24; test_debug/test-hierarchy.ps1:68
- disposition: test
- where: test/test-tree.ps1 :: "tree leaves every record unchanged when it reports two warchiefs"

### L-004 Two warchiefs are both drawn as roots and both named
- source: YedPool/wezfleet commands/tree.ps1:32-36; lib/Hierarchy.ps1:83-87; test_debug/test-hierarchy.ps1:66-67
- disposition: test
- where: test/test-tree.ps1 :: "two warchiefs are both drawn and both named"

### L-005 No warchief is printed as a finding
- source: YedPool/wezfleet lib/Hierarchy.ps1:79-82; test_debug/test-hierarchy.ps1:45 "no master is a FINDING, not a silent normal"
- disposition: test
- where: test/test-tree.ps1 :: "no warchief is printed as a finding"

### L-006 A handle is shown only when it is live in this host instance
- source: YedPool/wezfleet lib/Common.ps1:597-609 (instance only, no live check); 0e1c75a (tree printed the master at pre-restart pane 32); test_debug/test-instance.ps1:239-240; horde planning/parity-2.3.md P-23
- disposition: test
- where: test/test-tree.ps1 :: "a handle not live in this instance prints as unknown"

### L-007 Sessions with no parent are listed with their directory
- source: YedPool/wezfleet commands/tree.ps1:38-48 "called out rather than left in a column"
- disposition: test
- where: test/test-tree.ps1 :: "sessions with no parent are listed with their directory"

### L-008 Unassigned means no parent, whatever the origin, and the rule is stated once
- source: YedPool/wezfleet lib/Hierarchy.ps1:49-54 (the comment says origin=user with no parent; the code checks only role and parent), read-found 2026-09-30
- disposition: test
- where: test/test-tree.ps1 :: "an orc with no parent is unassigned whatever its origin"

### L-009 Every live session appears in the tree exactly once
- source: YedPool/wezfleet commands/tree.ps1:20-47: only warchiefs are recursed from and the unassigned list is flat, so a child of an unassigned node is never drawn; read-found 2026-09-30
- disposition: test
- where: test/test-tree.ps1 :: "every live session appears exactly once in the tree"

### L-010 Members of a parent loop are drawn and the loop is a fault
- source: YedPool/wezfleet lib/Hierarchy.ps1:52-58 and :70-110 (no loop check; loop members are neither unassigned nor orphans); :133-142 (Set-WfSessionParent refuses a loop, other writers do not); read-found 2026-09-30; horde fault parent-cycle in schema/session-view.v1.json (feature/core-projection)
- disposition: test
- where: test/test-tree.ps1 :: "a parent loop is drawn and reported as a fault"

### L-011 A retired session is not a member
- source: YedPool/wezfleet lib/Hierarchy.ps1:38-42; test_debug/test-hierarchy.ps1:71 (the control: closing one clears the finding)
- disposition: test
- where: test/test-tree.ps1 :: "a retired session is not drawn in the tree"

### L-012 A session whose parent is gone is drawn, and says whether the parent is missing or retired
- source: YedPool/wezfleet lib/Hierarchy.ps1:100-107 (only the finding names it; the body never draws it); horde planning/parity-2.3.md P-25
- disposition: test
- where: test/test-tree.ps1 :: "a session whose parent is gone is drawn and named"

### L-013 An orc under something other than the warchief is printed with its label
- source: YedPool/wezfleet lib/Hierarchy.ps1:89-98; horde planning/ledger/core-projection.md L-038
- disposition: test
- where: test/test-tree.ps1 :: "an orc outside the warchief is printed with its label"

### L-014 Advice names only commands Horde has
- source: YedPool/wezfleet commands/tree.ps1:47 and commands/census.ps1:36 advise wezfleet own; own matches pane, claude id or fleet id but not the label (commands/own.ps1:43); Horde has no assigning command before step 3.8
- disposition: dropped
- reason: Horde has no command that sets a parent until step 3.8, and advice naming another system's command would tie Horde's output to wezfleet's surface; the adoption ledger records who still assigns through wezfleet.

### L-015 An unreadable registry prints unknown, never no sessions recorded
- source: YedPool/wezfleet commands/tree.ps1:13-18; lib/Registry.ps1:115 onward (Read-WfAllSessionRecords)
- disposition: test
- where: test/test-tree.ps1 :: "an unreadable registry prints unknown, never no sessions"

### L-016 An unlabelled session is drawn with its id prefix, so two of them can be told apart
- source: YedPool/wezfleet commands/tree.ps1:25, :33, :44 print (unlabelled) for every one
- disposition: test
- where: test/test-tree.ps1 :: "an unlabelled session is drawn with its id prefix"

### L-017 Roles print in Horde's vocabulary, read through the alias table
- source: YedPool/wezfleet commands/tree.ps1:26, :34 print wezfleet's role words; lib/Hierarchy.ps1:28; horde planning/migration-plan.html step 0.8
- disposition: test
- where: test/test-tree.ps1 :: "roles print in the horde vocabulary"

### L-018 Fault kinds were renamed from wezfleet's, and the old names are recorded once
- source: YedPool/wezfleet lib/Hierarchy.ps1:80, :84, :94, :104 (no-master, two-masters, orchestrator-not-under-master, parent-missing); horde schema/session-view.v1.json fault kinds (feature/core-projection)
- disposition: comment
- where: cli/Tree.ps1 :: "fault kinds were renamed from wezfleet"
### L-019 The Warchief reads scope names from the tree
- source: ~/.claude/skills/master-orchestrator-handoff/SKILL.md:67-68; command logs measured 2026-09-30: M 11 uses of tree
- disposition: comment
- where: cli/Tree.ps1 :: "the warchief reads scope names here"

### L-020 Test records must never reach the live registry the tree is drawn from
- source: YedPool/wezfleet test_debug/test-delivery.ps1:68-69; test-registry-hook.ps1:183, :303; test-safe-kill.ps1:58 (M found strays by reading tree)
- disposition: test
- where: test/test-tree.ps1 :: "the tree suite reads only its temporary copy"

### L-021 The command must reach the projection, proven by running the command
- source: YedPool/wezfleet c850e7b; tasks/lessons.md:449-481; horde planning/ledger/core-projection.md L-052
- disposition: test
- where: test/test-tree.ps1 :: "horde tree reaches the projection through the command"
