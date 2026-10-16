# test/fixtures/fleet - the phone/PC contract for sleeping sessions

The founder hibernates and wakes sessions from his phone. These four files are the contract, agreed
between the PC side (the hibernation lane) and the phone side (the relay and phone lane), before
either side builds against it. They are data: no suite reads them yet. The first suite that does
must fail on any member that is not listed here.

Every file is version 1 (`"v": 1`), one JSON object, ASCII, and strict: a reader refuses a member it
does not know, a member that is missing, and a value outside the shape below. Never a guess.

Shared shapes:

- `setId`: 32 lower-case hex digits, chosen by the phone once per request and kept on every retry, so
  a request carried twice is acted on once. The PC answers it in `lastResult.setId`.
- `machine`: the key id of the machine the request is for, 32 lower-case hex digits (the relay's
  `keyId`, the first 16 bytes of SHA-256 of the machine's public signing point).
- `version`: the Orc registry's version, a whole number. A request names the version it was made
  against; the PC refuses it with `outcome: "retry"` when its registry has moved on, so the phone
  re-reads the snapshot and asks again rather than acting on a stale list.
- An Orc id is its lane folder name (`sleeping-sessions`).
- A hibernation id is the time it was taken, `yyyymmdd-hhmmss`, in UTC.

## PC to phone: `fleet-snapshot.json`

What the phone shows. Replaced whole each time.

| member | shape |
|---|---|
| `v` | `1` |
| `version` | the registry version this snapshot was read from |
| `tiers` | map of Orc id to `1` (stays awake) or `2` (sleeps with "hibernate tier 2") |
| `never` | list of `{ orc, reason }`: Orcs that are never put to sleep, and why, in plain words |
| `running` | `null` when nothing is in progress, or `{ id, startedAt, phase, sessions, more }` |
| `hibernations` | the newest 10 at most, newest first: `{ id, at, sessions, more }` |
| `lastResult` | `{ setId, outcome, reason }` for the last request the PC answered |

- `running.phase`: `"asking"` (sessions asked to park), `"parking"` (waiting for them to park and
  exit), `"done"`.
- `running.sessions[]` and `hibernations[].sessions[]`: `{ label, role, state }`, role `"orc"` or
  `"warg"`. A hibernation's state is `"asleep"`, `"woken"`, `"still-awake"` (it was running when a
  wake came, so it was left alone) or `"failed"`.
- `more`: how many sessions were left out of the list to keep the snapshot small, `0` when none.
- `startedAt`, `at`: UTC, `yyyy-mm-ddThh:mm:ssZ`.
- `lastResult.outcome`: `"done"`, `"refused"` (will not be done; the reason says why) or `"retry"`
  (not done now; ask again, usually after re-reading the snapshot).

## Phone to PC: one body per request

Each carries `v`, `setId` and `machine` (above), and exactly the members listed.

| file | request | members |
|---|---|---|
| `tier.json` | move one Orc to a tier | `orc`, `tier` (1 or 2), `version` |
| `hibernate.json` | put tier 2 to sleep | `tier` (always 2), `version` |
| `wake.json` | wake one hibernation | `hibernationId` (`yyyymmdd-hhmmss`) |
