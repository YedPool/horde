DRAFT - not a ledger yet. Kept outside planning/ledger/ because its test dispositions cite suites
that do not exist; test/test-ledger.ps1 would fail on it there. Its command's first PR (steps 6-8 of
planning/execution-plan-phase-3.md) deletes this paragraph and the next, moves the file to
planning/ledger/cli-census.md, and adds the tests in the same PR.

Adapted: comment dispositions point at `cli/Census.ps1`; L-018 to L-021 name the adoption capability each dropped feature stays on (decision 5); L-026 added for `-Json` (decision 4).

module: cli/census
replaces: YedPool/wezfleet commands/census.ps1 (Invoke-WfCensus), lib/Commands.ps1 (the census entry), and the printing of lib/Registry.ps1 Get-WfUnclaimedUserSessions and Write-WfIdentityHealth
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

## What each source held

- comments: commands/census.ps1:5-9, :19, :28-30, :38-45, :65-67, :78-88, :106-107, :110-112; lib/Registry.ps1:809-824,
  :830-832, :862-870, :1015-1016, :1191-1198.
- history: git log --follow commands/census.ps1: b1770fb, d811106, 0e1c75a, 6fe4e02, 71afcb0. Pickaxe Invoke-WfCensus
  and Get-WfFleetCensus before the split: 10b1782, c850e7b, 50a6944; and e36ea8e (two invented functions corrected).
- pull requests: none touched commands/census.ps1 or lib/Registry.ps1 (gh pr list, 17 pull requests, --json files).
- docs: planning/registry-design.md:64, :112, :132, :147; planning/BUG-2026-09-15-restart-pane-identity.md:6, :18-20,
  :94, :111; planning/BUG-2026-09-15-unsent-input-box.md:94; planning/wezfleet-v2-architecture.md:28, :100-111, :752;
  tasks/lessons.md:418-447; README.md:110.
- tests: test_debug/test-registry.ps1:92-172; test-instance.ps1:110-128; test-presentation.ps1:96-105;
  test-disk-space.ps1:102-106; test-input-box.ps1:382-402; test-delivery-callers.ps1:156.
- carried elsewhere, not repeated: the data rules, meaning which store answers each handle and every guard, are
  core/projection L-004 to L-006, L-011 to L-018, L-021, L-022, L-024 to L-027, L-042 to L-046, L-049, L-063 to L-065,
  and P-04, P-08 to P-16, P-26 and P-27. Title drift, bare shells, unsent text and disk space are dropped there
  (L-058, L-059, L-060); they are repeated below only to record that they stay on wezfleet in the adoption ledger.

### L-001 One row per live handle, including handles nothing knows
- source: YedPool/wezfleet lib/Registry.ps1:835-878; test_debug/test-registry.ps1:106 "a pane nothing knows about is reported as UNKNOWN, not omitted"; 10b1782 mutation "census omitting unknown panes"
- disposition: test
- where: test/test-census.ps1 :: "a handle no session answers is printed as unknown"

### L-002 Every row says which store answered it
- source: YedPool/wezfleet lib/Registry.ps1:822-823 "a census that cannot say how confident it is invites the reader to treat a guess as a fact"; planning/wezfleet-v2-architecture.md:752
- disposition: test
- where: test/test-census.ps1 :: "every row names the store its session came from"

### L-003 The summary counts rows per source in name=count form, because callers grep it
- source: YedPool/wezfleet commands/census.ps1:26-27; command logs measured 2026-09-30: Select-String -Pattern '^PANE|^\d|registry=' and '^13 |^PANE|registry=|UNSENT'
- disposition: test
- where: test/test-census.ps1 :: "the summary line counts rows per source as name equals count"

### L-004 The header starts with the handle column and each row starts with its handle
- source: YedPool/wezfleet commands/census.ps1:14, :23; command logs measured 2026-09-30 anchor on ^PANE and ^\d
- disposition: test
- where: test/test-census.ps1 :: "the header and every data row start with the handle column"

### L-005 Data rows come before every diagnostic section
- source: command logs measured 2026-09-30: wezfleet census 2>&1 | Select-Object -First 14 (and 16, 20, 25, 30, 32, 40, 45); YedPool/wezfleet commands/census.ps1:13-27 before :28-123
- disposition: test
- where: test/test-census.ps1 :: "every data row is printed before any diagnostic section"

### L-006 An unreadable handle list prints unknown, never no live panes
- source: YedPool/wezfleet commands/census.ps1:11; horde planning/parity-2.3.md P-16; horde planning/ledger/core-projection.md L-006
- disposition: test
- where: test/test-census.ps1 :: "an unknown handle list prints unknown, not no live panes"

### L-007 An age that cannot be measured prints a dash, never a number
- source: YedPool/wezfleet commands/census.ps1:19-20; lib/Registry.ps1:868-870; test_debug/test-registry.ps1:115, :128 (with its control)
- disposition: test
- where: test/test-census.ps1 :: "an unknown activity age prints a dash"

### L-008 The age column is last activity; it once silently meant first seen
- source: YedPool/wezfleet planning/wezfleet-v2-architecture.md:100-111 "The field named lastSeen records FIRST seen"; lib/Registry.ps1:862-876; horde planning/parity-2.3.md P-10
- disposition: test
- where: test/test-census.ps1 :: "the age column reads last activity, not a record write time"

### L-009 Sessions the founder opened that nobody owns are called out, not left in a column
- source: YedPool/wezfleet commands/census.ps1:28-37; lib/Registry.ps1:1190-1202; 10b1782; test_debug/test-registry.ps1:169, :172 (the control: once assigned it stops being flagged)
- disposition: test
- where: test/test-census.ps1 :: "founder sessions nobody owns are listed after the table"

### L-010 The owner column prints the derived owner, not an empty stored one
- source: YedPool/wezfleet commands/census.ps1:17 prints (unowned) for an empty stored owner; horde planning/parity-2.3.md P-11 (9 records agreed, 7 differed, all 7 empty where founder is derived)
- disposition: test
- where: test/test-census.ps1 :: "the owner column prints the derived owner"

### L-011 A missing origin is shown as missing, not as the word unknown
- source: YedPool/wezfleet lib/Registry.ps1:858; horde planning/parity-2.3.md P-12; horde planning/ledger/core-projection.md L-046
- disposition: test
- where: test/test-census.ps1 :: "a missing origin prints a dash"

### L-012 The session column is the first eight characters of the id
- source: YedPool/wezfleet commands/census.ps1:16
- disposition: test
- where: test/test-census.ps1 :: "the session column prints eight characters of the id"

### L-013 Titles are cut so a row stays one line
- source: YedPool/wezfleet commands/census.ps1:21-22 (44 characters)
- disposition: comment
- where: cli/Census.ps1 :: "titles are cut so each row stays one line"

### L-014 Handles sort numerically when they are numbers, and as text otherwise
- source: YedPool/wezfleet lib/Registry.ps1:835 sorts by [int]; horde core/HostPort.ps1:10-12 (feature/core-projection) makes a handle opaque text, per D12
- disposition: test
- where: test/test-census.ps1 :: "handles sort numerically when every handle is a number"

### L-015 Identity faults print only when present, through one printer that status also uses
- source: YedPool/wezfleet lib/Registry.ps1:1014-1016 "so census and startup cannot drift into saying different things about the same fault"; commands/census.ps1:106-108
- disposition: test
- where: test/test-census.ps1 :: "faults print through the one fault formatter"

### L-016 A side check that fails is said, not swallowed
- source: YedPool/wezfleet commands/census.ps1:68-76, :108, :113-123 each wrap a check in try with an empty catch
- disposition: test
- where: test/test-census.ps1 :: "a fault answer that is unknown is printed with its reason"

### L-017 Unknown panes come with a reason that names the missing writer
- source: YedPool/wezfleet commands/census.ps1:99-104 (advice naming wezfleet registry status); horde fault registry-hook-silent in schema/session-view.v1.json (feature/core-projection)
- disposition: comment
- where: cli/Census.ps1 :: "a handle nobody recorded is explained by the fault list"

### L-018 Tab titles that name the wrong pane, and their repair with -Fix
- source: YedPool/wezfleet commands/census.ps1:38-63; 50a6944; d811106 (whole-string comparison would have truncated good titles)
- disposition: dropped
- reason: horde census writes nothing and reads no tab title rules; title repair belongs to a host decoration adapter (step 7.2), and census -Fix stays on wezfleet as the adoption capability census-fix until one exists (decision 5) (horde core-projection ledger L-058).

### L-019 A pane showing a bare shell after its session exited is reported, not acted on
- source: YedPool/wezfleet commands/census.ps1:78-97; d811106
- disposition: dropped
- reason: it reads host pane titles, which are host presentation; it stays on wezfleet as the adoption capability census-bare-shell until a host adapter carries it (decision 5; horde core-projection ledger L-058).

### L-020 Unsent text sitting in an input box is listed
- source: YedPool/wezfleet commands/census.ps1:110-123; 6fe4e02; planning/BUG-2026-09-15-unsent-input-box.md:94
- disposition: dropped
- reason: it reads each pane's screen for typed delivery safety; Horde does not type, and the feature stays on wezfleet as the adoption capability census-unsent (decision 5; horde core-projection ledger L-059).

### L-021 Free disk space is reported because a full drive broke networking box-wide
- source: YedPool/wezfleet commands/census.ps1:64-76; 71afcb0
- disposition: dropped
- reason: machine health is not a session fact and belongs to a future startup or doctor command; it stays on wezfleet as the adoption capability census-disk (decision 5; horde core-projection ledger L-060).

### L-022 census exists because every consumer invented its own and got identity wrong
- source: YedPool/wezfleet commands/census.ps1:5-9 "cost one orchestrator three collisions in a day"; lib/Registry.ps1:814-815
- disposition: comment
- where: cli/Census.ps1 :: "one census so no caller rebuilds identity rules"

### L-023 census rows come from the view's handles section, one per handle
- source: horde planning/parity-2.3.md P-08 and the lead's decision 3; horde planning/ledger/core-projection.md L-065
- disposition: test
- where: test/test-census.ps1 :: "census prints one row per handle in the view"

### L-024 The command must reach the projection, proven by running the command
- source: YedPool/wezfleet c850e7b; tasks/lessons.md:449-481; test_debug/test-delivery-callers.ps1:156 proved it by reading the function body; horde planning/ledger/core-projection.md L-052
- disposition: test
- where: test/test-census.ps1 :: "horde census reaches the projection through the command"

### L-025 A read command writes nothing, and the proof runs it against a copied store
- source: YedPool/wezfleet commands/census.ps1:44-45 "Renaming twenty tabs as a side effect of looking at them is a surprise"; 50a6944 tripwire on Set-WfTabTitle
- disposition: test
- where: test/test-census.ps1 :: "running census leaves every store byte identical"

### L-026 Agents get a JSON form beside the text anchors, and move to it when they choose
- source: command logs measured 2026-09-30 (callers grep ^PANE, ^\d and registry=); decision 4 of 2026-09-30 keeps the anchors and adds -Json
- disposition: test
- where: test/test-census.ps1 :: "census json validates against the session view schema"
