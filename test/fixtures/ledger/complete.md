module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 An unreadable source is unknown, never empty
- source: YedPool/wezfleet lib/Hosts.ps1:59
- disposition: test
- where: test/test-sample.ps1 :: "an unreadable source reads as unknown"

### L-002 A comment-carried lesson
- source: YedPool/wezfleet tasks/lessons.md
- disposition: comment
- where: docs/carried.ps1

### L-003 Typing into panes needs a second Enter sometimes
- source: YedPool/wezfleet planning/wezfleet-ssot-multi-backend-2026-09-29.md
- disposition: dropped
- reason: Horde never types into panes to deliver messages, so this cannot arise.
