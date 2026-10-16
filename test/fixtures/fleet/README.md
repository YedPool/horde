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
  exit), `"done"` (every session has exited or been marked still-awake; the hibernation is about to
  move into `hibernations`, and the next snapshot has `running: null`).
- A hibernation is in `running` OR in `hibernations`, never both: it moves to `hibernations` when
  its phase ends.
- `running.sessions[]` and `hibernations[].sessions[]`: `{ label, role, state }`, role `"orc"` or
  `"warg"`.
- A running hibernation's session state is one of:
  - `"asked"`: told by mail to park at its next turn end.
  - `"parked"`: its PARKED file is written; waiting for it to be idle so it can exit.
  - `"exited"`: it exited cleanly and is asleep.
  - `"still-awake"`: it did not park within 15 minutes, so it was left running.
  - `"failed"`: something went wrong; the reason is in the PC's record.
- A finished hibernation's session state is one of:
  - `"asleep"`: not woken yet.
  - `"woken"`: resumed in a new window.
  - `"still-awake"`: it never went to sleep (it did not park in time), or a wake found it already
    running and left it alone.
  - `"failed"`: a wake tried and could not bring it back.
- `more`: how many sessions were left out of the list to keep the snapshot small, `0` when none.
- `startedAt`, `at`: UTC, `yyyy-mm-ddThh:mm:ssZ`.
- `lastResult.outcome`: `"done"`, `"refused"` (will not be done; the reason says why) or `"retry"`
  (not done now; ask again, usually after re-reading the snapshot).
- `lastResult` is `null` until the PC has answered its first request. It is never left out.
- `never` and `tiers` do not overlap: an Orc in `never` is left out of `tiers`. A `tier` request that
  names an Orc in `never` is answered `refused`.
- Only one hibernation runs at a time: a `hibernate` request while `running` is not `null` is
  answered `retry`. So no two hibernations start in the same second, and an id names exactly one.

## Phone to PC: one body per request

Each carries `v`, `setId` and `machine` (above), and exactly the members listed.

| file | request | members |
|---|---|---|
| `tier.json` | move one Orc to a tier | `orc`, `tier` (1 or 2), `version` |
| `hibernate.json` | put tier 2 to sleep | `tier` (always 2), `version` |
| `wake.json` | wake one hibernation | `hibernationId` (`yyyymmdd-hhmmss`) |

- The envelope: relay channel `fleet`, sender the founder; the envelope kind is the request name
  (`tier`, `hibernate`, `wake`).
- Signing (M's decision, 2026-10-16): all three ride the founder's unlocked session. The phone adds
  `fleet tier`, `fleet hibernate` and `fleet wake` to SESSION_SIGNED, and the PC's Accept takes
  `webauthn` or `session` proof for each. Hibernate asks for an on-page confirm first ("Hibernate N
  Tier 2 Orcs? Wake brings them back") instead of a fresh passkey, because Wake undoes it.
- `wake` carries no `version` on purpose: a hibernation id does not depend on the Orc registry. Do
  not add one for symmetry.
