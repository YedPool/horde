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
