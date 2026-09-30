# Knowledge ledgers

A ledger is written for a module **before** that module replaces anything in the old systems. It
lists everything the old code learned that could apply to the new one, with where each lesson came
from and what was done about it. `test/test-ledger.ps1` checks every ledger in this folder and fails
on any entry that nobody dealt with. (There is no CI yet; the suite is run by hand and by review.
See "What the gate does not check" below.)

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
| `test` | the lesson is enforced by a test in Horde | `where: <test file> :: "<assertion text>"` - a `.ps1` file under `test/`, inside the repository, containing that text **as a quoted string** of at least three words |
| `comment` | the lesson is carried as an explanatory comment | `where: <file> :: "<phrase>"` - a file inside the repository, not a ledger, containing that phrase of at least three words |
| `dropped` | the lesson does not apply to Horde | `reason: <why>` - at least a sentence |

`dropped` is a legitimate answer. Much of what the old systems learned was about typing into terminal
panes, which Horde does not do. The rule is only that the decision is written down, with its reason,
where the next reader can disagree with it.

## What the gate checks, and why each check exists

- **Every entry has a source.** A lesson that cannot be traced cannot be re-examined.
- **Every entry has exactly one disposition.** "Nobody looked" becomes an empty field instead of an
  absence.
- **A `test` disposition names a real test and quotes one of its assertions.** The file must be a
  `.ps1` under `test/`, inside the repository, and must contain the quoted text *as a quoted string*
  of at least three words. Each part closes a way an independent review found to pass the gate
  without reading anything: naming a directory, naming the ledger itself, climbing out with `..`,
  or quoting a single letter that appears in every file.
- **A `comment` disposition names a file and quotes the phrase that carries the lesson.** The file
  must exist inside the repository and must not be a ledger. Without the phrase, nothing would show
  the lesson was carried anywhere - `.` used to pass.
- **A `dropped` disposition gives a reason of at least four distinct words.** Enough to stop `n/a`
  and `a a a a`, not so strict that a short, true reason is refused.
- **The header - everything before the first entry - names the module, what it replaces, and all
  five sources as searched.** Only the header counts; sources claimed inside an entry do not.
- **Entry ids are unique within a ledger.**

## What the gate does not check

Stated so nobody relies on a guarantee the code does not give.

- **That a ledger exists at all.** A module could replace old code with no ledger and the suite would
  still pass. Until something enforces it, review does.
- **That a source is real.** Any non-empty `source:` is accepted. A reader can follow it; the gate
  cannot.
- **That a quoted assertion is the right one.** The gate proves the quoted test name exists. It
  cannot prove that test actually enforces the lesson. That is a reviewer's question.
- **Assertions that contain a double quote.** They cannot be cited, because the quote ends the
  `where:` text. The gate refuses them rather than guessing, so the failure is safe but real.
- **Anything, automatically.** There is no CI yet. The suite runs when someone runs it.
