# Lessons

Mistakes made while building Horde, each written as a rule that prevents it. Read at the start of a
session. A lesson earns an entry when it was paid for, not when it sounds wise.

## Every number in a commit, PR or report comes from command output

Four times in the first week a count was written from memory and was wrong: 17 checks that were 16,
26 that were 24, 16 that were 15, and an end-to-end run reported as 22 that was 20. Three were caught
before push; one reached the founder.

**Rule:** run the command, then copy the number. If the output is not on screen, the number does not
go in.

## Tests I wrote and mutated myself are not an adversarial review

The ledger gate passed every mutation test I wrote, and an independent reviewer then found three blocking ways
to pass it without reading anything - naming a directory, quoting a single letter, citing the ledger
itself. I mutate what I thought of; a reviewer attacks what I did not.

**Rule:** every code PR gets an independent review whose brief is to break it, before merge. Mutation
testing proves the tests I have can fail; it says nothing about the tests I am missing.

## An "improvement" to cleanup code is a change to what gets killed

Adding orphan cleanup to the isolation harness walked the process tree by recorded parent pid. On
Windows those are reused, so the walker would have killed unrelated user processes - reproduced live:
a chrome whose recorded parent pid now belonged to a younger chrome. The re-review then found the
same hole one level up, at the root.

**Rule:** anything that kills or deletes identifies its target by more than a reusable name - pid
AND creation time, a path AND its expected folder - and the PR carries a test where the reusable
name points at something else and nothing happens.

## Two readings of one value must be compared exactly, and that is tested on real data

The kill check compared creation times through `[Math]::Floor($ticks / 10)`, which divides as a
double. For 304 of 365 processes on this machine the CIM and .NET readings disagreed, so the harness
would have refused to kill the processes it started - leaking them, the exact failure it exists to
prevent. The fixed-table unit tests could not see it; only a check across every real process could.

**Rule:** where two sources must agree, one test compares them across real data, not only against a
table I wrote.

## A scripted edit on a CRLF checkout can match nothing and still exit 0

With `core.autocrlf`, `$`-anchored patterns miss `\r\n` lines. A mutation silently applied to nothing
and "passed"; a ledger update changed 3 of the intended lines.

**Rule:** after every scripted edit, assert it changed something (`cmp`, a diff line count) before
trusting what follows.

## Mutation testing kill code runs broken kill code

The isolation harness's mutation run broke the kill-safety rules on purpose and then ran the fast
suite - which killed whatever the broken walker returned, starting from real processes. The third
review found it. If a process id had been reused at the wrong moment, a mutant would have killed a
process that was not the suite's; nothing recorded what, if anything, it did kill.

**Rule:** a test of code that kills or deletes never lets that code choose the victim. The test
passes a guarded killer (or deleter) that acts only on things the test created and still holds, and
records - never acts on - anything else. A broken rule then becomes a failed check, never a harmed
stranger. The same goes for any destructive code under mutation.

## A helper that returns a value alongside output lies to if

A test helper, Throws, returned whatever its block printed together with $false; PowerShell reads
that array as true, so a "must throw" check passed when nothing threw. Separately, `-like` on a
list returns the matching items rather than a boolean.

**Rule:** Check refuses any condition that is not exactly true or false, and helpers discard their
blocks' output (`$null = & $Block`).

## A background run started with & tells nobody when it ends

Twice on 2026-09-30 a mutation run was started with a shell `&` inside an ordinary command. Nothing
tracks such a process, so nothing reports when it finishes; a tracked watcher had to be added after
the fact each time.

**Rule:** long runs go through the tool's own background mechanism, with an exit marker written to
the log. Never `&` inside a foreground command.

## Agents sharing one scratch folder can delete each other's evidence

A gate's mutation log vanished before it was read: another agent cleaning up the shared scratch
folder removed it, and the result had to be rerun. A missing log is an unknown result, not a pass.

**Rule:** every run writes its log under a name no other run uses, and a result is read from the
log it came from - never inferred from a command's exit code alone.

## A PR green on its branch can break main when main moved under it

On 2026-10-02 PRs #40 and #45 merged green and left main red: 86 checks of test-link-contracts and
100 of test-link-protocol failed. Main had moved under both branches. PR #39 had added
remote/Journal.ps1, which the new exec scan had never seen. The schema cache work had removed
core/Schema.ps1's Get-HordeObjectProps, and made Read-HordeSchemaFile refuse anything that is not a
schema, which the link suites used to read frames. Each branch passed against the main it started
from; none was tested against the main it merged into.

**Rule:** a PR green on its branch can break main when main moved under it. Before merging, run the
touched suites on the merge result (git merge-tree, or a throwaway merge commit), not only on the
branch.

## A native tool's idea of home is measured, not assumed

On 2026-10-02, building the ssh transport, the plan was to prove independence from the user's
~/.ssh/config by planting a hostile one in a temporary profile. Win32 OpenSSH (9.5p2) ignores
USERPROFILE and HOME and resolves ~ to the real profile, so the planted file would never have been
read and the test would have passed for the wrong reason - or, done the obvious way, written into the
user's real ~/.ssh. The same tool, given an -i key file that does not exist, silently offered the
user's default ~/.ssh keys instead, even with -F none and IdentitiesOnly=yes.

**Rule:** before isolating a native tool by redirecting its home, measure that it follows the
redirection. If it does not, prove isolation with the tool's own report of its configuration (ssh
-G), with a control that shows the hazard, never by writing into the real profile. And refuse to
start when a file the isolation depends on is missing, because a native tool's fallback is the
user's own files.
