# Knowledge ledgers

A ledger is written for a module **before** that module replaces anything in the old systems. It
lists everything the old code learned that could apply to the new one, with where each lesson came
from and what was done about it. `test/test-ledger.ps1` checks every ledger in this folder and fails
the build on any entry that nobody dealt with.

Why this exists: the knowledge in the systems Horde replaces is large and scattered - most of
wezfleet's commits carry explanatory bodies, and about a third of its library is comment. Read once
and remembered, it gets lost. Written down per module and checked, it cannot be skipped silently.

## One file per module

`planning/ledger/<module>.md`, for example `planning/ledger/core-tristate.md`. Files whose names
begin with `_`, and this README, are not ledgers and are not checked.

## The header

```
module: core/tristate
replaces: YedPool/wezfleet lib/Hosts.ps1 (Get-WfFleetSessions pane states), lib/CodexStatus.ps1 (-1 vs 0)
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched
```

All five sources must be marked `searched`. They are the five places the old systems keep what they
learned:

1. **comments** - the old module's own comments
2. **history** - `git log --follow` of every file the old module spans
3. **pull requests** - every pull request that touched those files, in both old repositories
4. **docs** - every planning document, BUG write-up and lessons entry that names the module
5. **tests** - the old module's tests; each test name is a behaviour someone once needed

A source that genuinely has nothing is still `searched` - the point is that someone looked.

## Entries

Each lesson is one entry, headed `### L-<number> <what was learned>`:

```
### L-001 An unreadable source is unknown, never empty
- source: YedPool/wezfleet lib/Hosts.ps1:59 "a real answer meaning UNKNOWN, never no panes"
- disposition: test
- where: test/test-tristate.ps1 :: "an unreadable source reads as unknown"
```

Every entry needs a `source` - a commit, pull request, document, or `file:line` that a reader can go
and check - and exactly one `disposition`:

| disposition | means | also needs |
|---|---|---|
| `test` | the lesson is enforced by a test in Horde | `where: <test file> :: "<assertion text>"` - the file must exist and contain that text |
| `comment` | the lesson is carried as an explanatory comment | `where: <file>` - the file must exist |
| `dropped` | the lesson does not apply to Horde | `reason: <why>` - at least a sentence |

`dropped` is a legitimate answer. Much of what the old systems learned was about typing into terminal
panes, which Horde does not do. The rule is only that the decision is written down, with its reason,
where the next reader can disagree with it.

## What the gate checks, and why each check exists

- **Every entry has a source.** A lesson that cannot be traced cannot be re-examined.
- **Every entry has exactly one disposition.** "Nobody looked" becomes an empty field instead of an
  absence.
- **A `test` disposition names a test that exists and contains the quoted assertion.** Otherwise
  writing `test` next to every entry would satisfy the gate while enforcing nothing.
- **A `comment` disposition names a file that exists.**
- **A `dropped` disposition gives a reason.**
- **All five sources are marked searched.**
- **Entry ids are unique within a ledger.**
