# Execution plan: remote sessions - the link, the node, and the transport port

Agreed 2026-09-30. The order of work that lets Horde run sessions on another machine and operate
them from this one: a central listener on the hub, nodes that dial it, an allowlisted protocol that
is never a remote shell, a transport port whose first real adapter is ssh, and a boundary with a
separate overlay repository (Tailscale or WireGuard) that supplies only an address and a health
answer. Its companions, all on `origin/main`, are `planning/execution-plan-engines.md`,
`planning/execution-plan-hosts.md`, `planning/execution-plan-lifecycle.md` and
`planning/execution-plan-phase-3.md`. This plan builds nothing those plans build; where it needs
their work it names the step, by number and by title.

Planning prose may name terminals, engines and transport programs. Code may not: CONTRIBUTING 14,
extended to `agents/<name>/` by engines E1 and to `transports/<name>/` by step R5 below.

## Sources, and what is settled

The remote-sessions design, written 2026-09-30, read-only, not committed. Its measurements are cited
as M-01 to M-09 and its sections by number. It rests on the settled decisions of the engine-settings,
lifecycle, hosts and metrics designs, as carried in the companion plans.

From the remote design's own "Decisions taken":

1. **Nodes dial out to one listener on the hub, and the hub is always also a node**, served over the
   `local` transport through the same protocol. There is one actuation path; `local` is its
   degenerate case, not a second code path.
2. **OPEN, with the founder: may Horde install the Windows OpenSSH Server on this machine?** Elevated,
   once, listening on loopback and the overlay address only, for a dedicated non-administrator
   account. Until he answers, the ssh adapter is tested against a throwaway sshd in WSL (step R5), and
   step R16 does not start.
3. **The stored session record splits into a fleet record, written only by the hub, and a binding
   record, written only by the node that runs the session.** It lands before step 3.8's first
   writer, as an in-place edit of v1 (step R10).
4. **Each node caps the permission mode of the sessions the hub spawns on it** (step R9).
5. **The remaining decisions follow the design's recommendations**: no file-transfer verb, so code
   moves only by git and handoffs come back distilled (8); no remote update verb (9); Rule 14 gains
   `transports/` (10); the overlay repo is `horde-overlay`, and the hub listens on loopback and the
   overlay only (11); a partition never kills work (12); link keys are unencrypted ed25519 files with
   an owner-only ACL, `restrict` and a one-year expiry (13); Tailscale is the overlay's one-click
   default, WireGuard second, and the existing `vpn-hub` tunnel is never touched (14); Windows nodes
   first (6); a second, disabled test sshd for the listener's suite (3); delivery only through the
   node's local `deliver` primitive, never Claude's cross-machine route (7).

Findings that shape every step (design section 0): a Windows sshd kills every process its session
started and runs in Session 0, so **nothing that must outlive a link, and nothing that opens a
window, is a child of an ssh session**; Windows `ssh.exe` has no multiplexing and this machine has a
user `~/.ssh/config` (M-05), so **a Horde link never reads a user's ssh config**; this machine has
the ssh client and not the server (M-02, M-03); WSL `ubuntu-binder` has sshd 9.6p1 (M-04).

## When each step can start

The first four tags are the engines plan's; PHASE5 is added here.

- **NOW**: needs only what is on `main`. A step that waits on a named step of another plan says so
  in its own line and is not NOW.
- **PROJ**: waits until `feature/core-projection` merges with the HostPort contract (namespace-tagged
  pid and cwd, unique handles, mandatory `-Capabilities`).
- **SPAWN**: waits for Horde's spawn and launch commands (migration step 3.8, engines E10, and the
  lifecycle plan's anchor, its step 22).
- **INSTALL**: a tool or Windows feature not yet on this machine. For R16 it is not enough to tell the
  founder first: it waits for his OK (decision 2).
- **PHASE5**: waits for a writer the migration plan's Phase 5 moves behind the contract.

## How every step is done

As the phases 0-2 plan: a worktree from a freshly fetched `origin/main`; a ledger first wherever
anything is replaced; tests first, every new check mutation-tested; verified from a fresh CRLF
checkout; an independent adversarial review of every code PR; `gh pr merge --merge`, never squash;
every count copied from command output. Heavy suites run one at a time in one background job with a
`DONE=` marker.

Also for remote:

- **Never the user's keys, never `~/.ssh`.** Every ssh test generates its keys in a temp root and
  removes them. The SHA-256 and length of every file in `~/.ssh` are recorded before and compared
  after; any change fails the suite. Nothing opens them for writing.
- **Every remote answer is a `core/tristate` answer.** "I cannot hear the node" is `unknown` with the
  reason, never `absent` and never a stale value shown as current (design 7).
- **Option spellings are measured, not quoted.** Every ssh option and every `authorized_keys` option
  is proven on the installed `ssh.exe` 9.5p2 (R5) or the Windows sshd (R17) before a line depends on
  it. Until then it is `unverified`, which counts as `no`.
- **Two ends, one version rule.** A contract change is a new schema file, never an edit, once any
  node could hold the old one (migration-plan section 8, risk 2). The session-record edits of R10
  are the one exception, and only because no writer exists before step 3.8.

## Ledger notes

- **No ledger is owed for `remote/` or `transports/`.** Neither old system has remote code: a search
  for `ssh|tailscale|wireguard` over wezfleet `lib/` and `commands/` finds only the comment at
  `commands/sessions.ps1:11`, and the same search finding that comment is its control (design
  finding 1). The one inherited principle, "identity is not location"
  (wezfleet-v3-rewrite-proposal.html:105-111), is carried as a comment in R7.
- **R10 edits `core/ownership.json`**, so it re-reads `planning/ledger/core-ownership.md`. Every entry
  whose `where` names a row that moves to the binding record (projectCwd's `firstCwd` rule first)
  gets its `where` updated in the same PR, and `test/test-ledger.ps1` must stay green.
- **R11 extends the rule of `planning/ledger/core-identity.md`** that a pid is looked up only in its
  own space. Its entry cites this plan; no old code is replaced.
- **R21 replaces wezfleet `tell`'s duplicate guard** (`commands/tell.ps1` `Get-WfTellSuccessLines`,
  2026-09-16: a correction suppressed as a duplicate). It adds that entry to the ledgers lifecycle
  step 13 writes for the primitive (`planning/ledger/core-alerter.md` and the message half of
  `agent-claude-code.md`), and cites L-037 of `core-identity.md` (the Claude pipe is undocumented
  internal IPC).

## Steps

A. The protocol core (test-only, installs nothing; each step's tag in its line)

0. **R0. The permission-level vocabulary** (NOW). One small data file, `core/permission-levels.json`:
   a closed, ordered list of Horde permission levels, each with a one-line meaning in Horde's terms
   and no harness flag (starting proposal, settled in R0's review: `plan` < `ask` < `edits` <
   `bypass`). It lands on its own, **before engines E2**, and breaks a cycle: E2's `permissionLevels`
   checks (every level mapped exactly once per harness) and R9's ceiling both read this file, so
   neither waits on the other. Tests first: the list is non-empty, ordered, and has no duplicate; a
   level added or removed fails a fixture descriptor that maps the old list, so E2's check sees the
   change; the file names no harness (the ratchet). The follow-up this step owed is done: the engines
   plan's E2 names R0 and `core/permission-levels.json`. R0 also carries R9's one comparison,
   `Test-HordePermissionLevelAllowed` (known false above the ceiling, never clamped; unknown when
   either side is not a level), so R9 and R19 compare no levels of their own.
1. **R1. Contracts** (NOW). `schema/link-frame.v1`, `link-verbs.v1`, `node-manifest.v1`,
   `transport-capabilities.v1`, `overlay-endpoint.v1`, with golden fixtures (D4). Every verb row has
   `additionalProperties: false`, an effect class (`read`, `write`, `spawn`, `kill`
   from lifecycle H13, and `drive`, gated like `spawn`: see R9) and a `since`. Tests first:
   - a verb row without an effect class fails;
   - **no verb takes a command line, script, program path, environment map or arbitrary file path**:
     a fixture verb with an `argv`, `path` or `env` argument fails, and so does one whose argument
     type is an open object;
   - **no verb returns raw worker context**: every read result schema is closed and carries a size
     cap, and a fixture verb returning a transcript or tool-output field fails (the purity guard, see
     R14);
   - **size caps are data in the contract, not schema keywords.** `core/Schema.ps1` has no length or
     byte keywords, so R1 declares each cap as a field of the verb row (`maxArgsBytes`,
     `maxResultBytes`, and per string field a `maxBytes`: the prompt and message bodies 64 KiB, the
     handoff 64 KiB) and the frame cap in `link-frame.v1` (1 MiB, never above 4 MiB). A verb row
     without a result cap fails. R2 enforces them;
   - the absent verbs of design 6.4 (exec, shell, file, config set, credential, kill by pid, update)
     are each a refused fixture.
2. **R2. `remote/Protocol.ps1`** (NOW). NDJSON frames, the envelope, version negotiation. The encoder
   escapes every non-ASCII character as `\uXXXX` (PowerShell 5.1's `ConvertTo-Json` does not,
   CONTRIBUTING 12); the decoder refuses a raw byte above 0x7F. `Test-HordeProtocolLimits` enforces
   every cap R1 declares as data (frame, args, result, per-field bytes), on send and on receive,
   because the schema checker cannot. Every `result` is in `ConvertTo-HordeAnswerRecord` form, so no
   bare value crosses. Tests first: escaping round-trips; a raw non-ASCII byte is a framing error; a
   frame at cap + 1 is refused at the sender; a field one byte over its declared `maxBytes` is refused
   on both sides, and a cap removed from the data turns the test red; a stdout line that is not a frame closes the link; no common protocol version ends in
   `bye`. Mutations on the escaper and the cap.
3. **R3. `remote/Journal.ps1`.** The request and message journals: `FileMode.CreateNew` per id,
   `argsHash`, states `accepted|done|failed|refused`, 30-day retention (NOW). The root is a
   parameter, so this step needs no home folder; callers pass a root under `Get-HordeHome` (Phase 3
   plan step 1) once it exists. Tests first: two racing writers, one act; the same id
   with another `argsHash` is refused; a resend returns the recorded state and acts nothing.
4. **R4. The transport port and `transports/local`** (NOW). `New-HordeTransport` with `Open` and `Probe`,
   capabilities as data validated by R1's schema, and a conformance suite generated from each
   transport's `capabilities.json` (every `yes` a positive test, every `no` an honest refusal, as
   hosts step 3). `local` is a named pipe `\\.\pipe\horde-node-<deviceId>` whose ACL admits only the
   owning user; an in-process pair for unit tests declares `auth.peer: declined`, so no production
   path can pick it. Tests first: the pipe refuses another user (a test account, or the refusal
   asserted through the ACL read back); the in-process pair is refused where `auth.peer: yes` is
   required.
5. **R5. `transports/ssh`, and Rule 14 gains `transports/`** (waits for engines E1, lifecycle step
   5 and hosts step 5, the three earlier edits to `tools/HostNames.ps1`).
   - `Argv.ps1` builds argv from data, never from a user's config: `-F none`, `-T`, the Horde key,
     `IdentitiesOnly`, `IdentityAgent=none`, a Horde `UserKnownHostsFile`, `StrictHostKeyChecking=yes`,
     `HostKeyAlias=horde-hub-<hubId>`, `BatchMode=yes`, keepalives, `ControlMaster=no
     ControlPath=none`, no forwarding (design 2.4). The System32 `ssh.exe` is resolved by path so Git's
     copy (M-03) cannot win. Exit 255 maps to `unknown: transport error`, stderr's first line the
     reason, and stderr never enters the frame reader (no `2>&1`, CONTRIBUTING 12).
   - **The throwaway sshd in WSL** (`transports/ssh/test/Isolation.ps1`, design 12.3 T2): temp keys,
     a free loopback port, a test-only `sshd_config` with `ForceCommand` an echo script and
     **`AuthorizedKeysFile` pinned to the temp root**, so the WSL user's own `authorized_keys` is never
     consulted; started as `wsl.exe -d <distro> --exec /usr/sbin/sshd -D -e -f <path>`. The distro
     comes from configuration (CONTRIBUTING 11).
   - **Cleanup runs in `finally`**: sshd is killed by the pid the harness started (checked through
     its `PidFile` and start time), and the temp root with its keys is removed, so an aborted or
     failed run leaves no key behind. A mutation that throws mid-suite must still leave the temp root
     gone.
   - Assertions before anything runs: `ssh.exe -G` with the production argv shows only the temp
     identity, the temp known_hosts and `controlmaster no`. **Control:** the same `-G` without `-F
     none` shows the user's config taking effect (M-05), so the check can see the hazard. The SHA-256
     and length of every file in the Windows `~/.ssh` **and in the WSL distro's `~/.ssh`** (the
     sshd's user, root here, M-04) are recorded before and compared after; any change fails.
   - Cases, each with its mutation: bytes round-trip, including a 1 MiB frame; a client-requested
     command is ignored; `-L` is refused; a pty is refused; a wrong host key refuses with 255 mapped
     to `unknown`; an unknown client key is refused; an `expiry-time` in the past is refused; the link
     survives 60 s idle; killing sshd gives `unknown: link lost`.
   - If WSL localhost forwarding does not reach the sshd (unmeasured, design 12.3), the suite prints
     `[SKIP] <reason>`, never green.
   - `tools/HostNames.ps1` gains a third root: nothing outside `transports/<name>/` names `ssh`,
     `ssh.exe`, `sshd` or an ssh option. This is the **fourth** edit to that file, in a fixed order:
     engines E1 (the `agents/*` ratchet), then lifecycle step 5 (its names under that ratchet), then
     hosts step 5 (the cross-host import), then R5. Each rebases on the one before. Fixture trees
     first, as E1's.
6. **R6. `remote/Clock.ps1` and liveness answers** (NOW). Four-timestamp offset and round-trip per link;
   every remote `observedAt` stored with the node's stamp and the hub's receive time; freshness
   (`Limit-HordeAge`) judged on receive time; an offset above `HordeClockSkewSeconds` is a node fault.
   The three liveness tristates of design 7.1 as pure functions. Tests first: a node clock 10 min
   fast does not make stale data fresh; link silent past 60 s is `unknown` naming the last frame
   time; a node without `bye` is never `known false`.
7. **R7. Device id, `core/Device.ps1`** (waits for Phase 3 plan step 1, `Get-HordeHome`).
   `Get-HordeDeviceId` reads or creates `<HordeHome>/node/node.json` with `CreateNew`: a random
   UUID, never from a host name or hardware; `deviceName` a handle only. The lifecycle follower's
   `machineId` (the stream path `<machineId>.jsonl` of lifecycle step 7) **is** this device id, so R7
   lands before lifecycle step 7. **Follow-up owed:** the lifecycle plan does not name this
   dependency; its step 7 needs one line saying `machineId` comes from R7's `Get-HordeDeviceId`. Tests first: two racing first calls give one id; a copied `node.json` on a second
   machine is caught at enrolment (R17), not here, and the test says so.
8. **R8. The overlay boundary, Horde's side** (NOW). `remote/Overlay.ps1` resolves
   `link.hub.address = overlay:<name>` by running `horde-overlay endpoint --name <name> --json` and
   validating the output against `schema/overlay-endpoint.v1` (R1). **Horde owns that schema**; the
   overlay repo imports nothing of Horde's and Horde imports nothing of its code. Health is advisory:
   a healthy overlay with a refused ssh handshake is `unknown: link refused (overlay reports
   healthy)`. Horde never starts, stops or configures a tunnel. Tests first against a fake
   `horde-overlay` on a temp PATH: output that fails the schema is `unknown`, never a guessed address;
   a missing command is `unknown` with the reason.
9. **R9. Node policy, including the permission-mode ceiling** (waits for R0 and engines E2 to E4). The node's
   policy is keys in its own L1, through the one resolver, like `admission.tier`: `remote.repos[]`,
   `remote.profiles[]` (names offered to the hub), `remote.dailySpawnCap`, and
   `remote.permissionCeiling`. The ceiling is a level of R0's vocabulary; each harness maps the
   levels to its own flags in `agents/<name>/agent.json` `permissionLevels` (engines E2), so core
   names no flag. Default: **below prompts-bypassed**, unless the node's owner sets it higher. Like
   `admission.*`, the keys may be set only in L1 or L4; the checker refuses them in a run spec or a
   spawn. This step is the key, the checker and a pure `Test-HordeRemotePolicy` over a request;
   enforcement is R19. Tests first: a request above the ceiling is **refused with the reason, never
   clamped**; a resume whose recorded binding is above a since-lowered ceiling is refused; a request
   naming a profile the node does not offer is refused; an environment variable moves nothing, with
   a control that the L1 file does.
   **The ceiling gates `drive` exactly as it gates `spawn`** (review of PR #40, 2026-10-01). `session.deliver`
   types into a running session, which acts with whatever permissions it runs under, a prompts-bypassed
   one included, so R1 classes it `drive`, not `write`, and pins the class in `remote/Contract.ps1`. A
   deliver may target only a session this hub spawned on that node (hub-owned in the session record);
   any other target is refused, never forwarded. Tests first: a deliver to a session above the ceiling
   is refused with the reason, as a spawn is; a deliver to a session the hub did not spawn is refused.

B. Identity and the session record (PROJ; must merge before migration step 3.8)

10. **R10. The fleet record and the binding record: first of one ordered sequence of v1 edits.**
    Four PRs edit `schema/session-record.v1` in place, across three plans. Each is safe only while no
    writer exists (engine-settings decision 5), so **all four land as one ordered sequence before
    Phase 3 step 3.8**, each rebased on the one before, and any later change is a v2. The same order
    is the gate on step 3.8 in `planning/execution-plan-phase-3.md`, and the engines plan (its group
    C) and the lifecycle plan (its step 24) state it too. R10 also needs R7, for `device`:
    1. **R10, the split** (this plan). First, because the other three add fields to the records it
       creates. `schema/session-record.v1` stays the fleet record, written only by the hub's engine:
       role, parent, label, labelCycle, origin, runId, fleetSessionId, title, dependsOn, retired,
       retiredAt, and a new required **`device`** (the device id, R7). `projectCwd` leaves it. A new
       file, `schema/session-binding.v1`, is the binding record, written only by the node engine that
       spawned the session and stored on that node; the hub keeps a read-only mirror by cursor (R13).
       `core/ownership.json` gains the owner **`node`** ("the engine on the device that runs the
       session"), and `projectCwd` moves to it.
    2. **engines K1** (`planning/execution-plan-engines.md` step 12): the key becomes
       `(harness, id)` and `sessionId` stops assuming a UUID, in both records.
    3. **engines R1** (engines step 14): `engine { harness, provider, model, profile, requested,
       resolvedAt, provenance }` and `resume { argv, envRefs }` land in `session-binding.v1`, owner
       `node`.
    4. **lifecycle step 24** (`planning/execution-plan-lifecycle.md`, its 3.1 and 3.4): `binding`,
       `containment`, `predecessor`, `successor` and `closure` land in `session-binding.v1`, owner
       `node`; `closeOn` and `park` land in the fleet record, because an orc on any machine sets them
       through the hub. This plan confirms that placement.

    A local session is the same split with both writers on one machine. Tests first:
    `test/test-schema-session-record.ps1` computes the fleet record from `engine`-owned stored rows,
    and a new twin computes the binding record from `node`-owned rows; a row with both owners fails; a
    `node` row appearing in the fleet schema fails, and the reverse; `device` is required. Ledger
    note above.
11. **R11. Device on every namespace tag.** On top of the HostPort's `space` (hosts decision 5), every
    pid, procStart and path that leaves a node carries `ns: { device, space }`. Rules, each a test
    with its mutation:
    - core never looks up a pid whose `ns.device` is not the local device, in any process table;
    - two pids are one process only when device, space, pid and procStart all match;
    - a remote path is displayed and never opened by the hub;
    - Claude's `pidDomain` (`win32:<user>`, M-01) is carried as the agent's claim under its own name
      and never stands in for `ns.device`: a fixture with two devices sharing one `pidDomain` stays
      two devices.
    Built as `core/Namespace.ps1` (the four rules as tristate answers), a guard in core/identity's
    process check, `ns` on `session.close`'s expected pid, and one space vocabulary for the manifest,
    the link and `core/Platform.ps1`. Two parts wait for the first remote pid to reach them, and are
    owed there: `ns` on the session view's pid, procStart, cwd and transcriptPath answers, which leave
    a node in `sessions.list` (R12); and a process table that carries the namespace it was read in, so
    the guard checks the table and not the caller's word, with the hub-side path refusals (R13).

C. The node and the hub, read path (PROJ)

12. **R12. `horde node serve`, read verbs.** `hello`, `node.info`, `sessions.list`, `session.get`,
    `binding.get`, `observe.since`, `request.status`, and the per-user logon task. `sessions.list` is
    the node's own projection (step 2.2), built by its own host and agent adapters; `complete` is
    `known true` only when every store was readable. `observe.since` streams the node follower's file
    (lifecycle steps 7 and 11) from a `(deviceId, seq)` cursor. `node serve` is a separate process
    from `horde follow`, whose never-acts tripwire stays. After lifecycle step 11. Gate: T1, the full
    protocol hub daemon to node daemon over `local`, with a fake host and agent; e2e drives the real
    `horde` CLI.
    **Split, 2026-10-02 (coordinator's decision), so the read path does not wait on lifecycle step 11:**
    - **R12a (now):** `horde node serve` over `local`, answering `hello`, `node.info`, `sessions.list`,
      `session.get` and `request.status`; `sessions.list` says complete only when every store was
      readable; the T1 gate (a hub client against the node daemon, fake host and agent) and an e2e
      through the real `horde` CLI. No logon task: installing one is a side effect, and it lands with
      `horde install`.
    - **R12b (later):** `observe.since` after lifecycle step 11, and `binding.get` after Phase 3 step
      3.8 ships the first record writer (until then there is no binding record to read).
13. **R13. `horde hub serve`, mirrors, `horde nodes`.** Node registry, per-node outbox, mirror files
    and cursors, the binding-record mirror, `device` in the session view (step 2.3). Tests first: a
    dropped link resumes at the cursor with no loss and no duplicate; a node's sessions turn `unknown`
    with "node D unreachable since T" when the link drops, never `absent`; a partial inventory never
    marks a session absent; a key seen on two devices is a fault, never resolved by picking one.
    **Split, 2026-10-05, on R12's line, so the read path does not wait on R12b, R17 or R19:**
    - **R13a (now):** `horde hub serve` pulls each registered node's whole inventory (`hello`, a
      `ping` for the clock sample of R6, `sessions.list`, `bye`) over the transport port, and keeps
      one mirror file per node under `<HordeHome>/hub/mirror/`, checked on read by
      `schema/node-mirror.v1` and by the link contract itself. The registry is the hub's own node over
      the local link, because a node is added only by enrolment (R17). `horde nodes` shows each node's
      reachability, its inventory and the fleet's faults; every remote session row carries its
      `device`. Tests first, the four above, with the cursor test read for whole inventories: after a
      dropped link the next pull leaves the mirror equal to the node's inventory, nothing lost and
      nothing twice.
    - **R13b (later):** cursors, with `observe.since` (R12b); the binding-record mirror, with
      `binding.get` (R12b); the per-node outbox, with the first verb that queues for a node (R19's
      act verbs, R20's alerts); registry entries written by `horde hub enroll` (R17); and `device` in
      the local session view's schema (`schema/session-view.v1`, step 2.3), which R13a's rows carry
      but the local projection does not yet.
14. **R14. `handoff.get`, and context purity.** A goblin's handoff comes back as a distilled document,
    capped at 64 KiB, the cap declared as data on the verb in R1 and enforced on the node by R2's
    `Test-HordeProtocolLimits`, since the schema checker has no byte keyword; transcripts, tool output and exploratory notes stay on the node, on disk, and
    are named in the handoff, never sent. There is no file-transfer verb and no `evidence.get` in v1.
    Tests first: a handoff over the cap is refused at the node, not truncated silently; R1's purity
    guard covers the new verb. Lifecycle step 16's purity measure (orc and warchief context tokens
    per delivered result) reads remote handoffs the same as local ones.
15. **R15. `metrics.since`.** Content-free metrics events under the node's metrics gate, same cursor
    mechanics. Tokens are counted on the node from its own files (metrics decision 7, per machine);
    the salt never leaves the node, so fingerprints compare only within a device, written into the
    report as a limit. After metrics M2 and R12. Tests first: a planted content marker crosses in no
    frame, with a positive control on an allowlisted field.

D. The Windows listener (INSTALL; awaits the founder's OK)

16. **R16. The Windows OpenSSH Server, installed; the transport proven against it.** Rewritten
    2026-10-05. The founder installed `OpenSSH.Server~~~~0.0.1.0` (decision 2): the `sshd` service is
    Disabled and Stopped, its `OpenSSH-Server-In-TCP` firewall rule is disabled, and nothing listens on
    port 22. sshd runs only while `horde listen` runs (R17). **No second service, no throwaway account
    and no service DACL** (coordinator's decision, 2026-10-05): the listener's test fixture is
    `sshd.exe -D -e` started as the suite's own child (`transports/ssh/test/Sshd.ps1`), on 127.0.0.1
    and a free port, with a test-only config, host key, authorized_keys and pid file under a TEMP
    folder whose ACL admits only the user, SYSTEM and Administrators (Windows sshd refuses an
    authorized_keys another principal can read). A watchdog process kills it at the suite's
    wall-clock limit. Nothing under `C:\ProgramData\ssh`, no service setting, no firewall rule and no
    account is changed, and the suite checks each against its state at the start: a difference is a
    loud FAIL, never put back silently. Measured: sshd.exe runs this way from an elevated token and
    from a `runas /trustlevel:0x20000` one (Administrators deny-only); a true medium-integrity token
    is unmeasured. Suite `transports/ssh/test/test-sshd-local.ps1` (machine-bound): R5's live cases -
    frames round-trip, a mebibyte included; the forced command runs, never the requested one; a wrong
    host key and an unknown client key are unknown with the reason - and the authorized_keys options
    R17 depends on: `expiry-time` in the past refused, `restrict` refusing a port forward. When this
    machine cannot run it, the suite exits 3.
17. **R17. The listener.** The `horde-link` account (not an administrator, no interactive logon, no
    password), an sshd_config `Match User horde-link` fragment, the stateless attach shim, the hub
    pipe `\\.\pipe\horde-hub-<hubId>` with an ACL for the founder and `horde-link` only, and `horde node
    init` (key), `horde hub enroll`, `horde node pin`, `horde hub revoke`, `horde node rotate-key`.
    Enrolment and pinning move strings the founder carries; no host key is ever accepted from the
    network. **The ssh transport's `dial.out` flips from unverified to yes here** (coordinator's
    decision, 2026-10-05), when a node really dials the hub's listener over ssh: its evidence is
    `test/test-transport-conformance.ps1`'s live ssh case, run locally (the suite is machine-bound)
    against the child sshd of R16's `transports/ssh/test/Sshd.ps1`. Until then it stays unverified,
    and `test-sshd-local.ps1` opens through the adapter, with a control that the port still refuses.
    Gate, T3 against the same child sshd (R16; no `horde-test-sshd` service): `command=`, `restrict` and `expiry-time` are honoured
    (unmeasured on Win32 OpenSSH, so these are the first cases); a requested command and a port
    forward are refused; a revoked key is refused even with its line restored by hand; `hello`
    claiming another device than the key's is refused; enrolling a device id already bound to
    another key is refused.

E. Acting over the link

18. **R18. Containment: the anchor holds the job, the node daemon never does** (SPAWN; after lifecycle
    step 22). A kill-on-close job ends when its last handle closes, so a daemon holding goblins' job
    handles would kill every goblin on each upgrade or restart, and remote makes those routine. The
    handle is held only by the per-goblin anchor the lifecycle plan builds (its 2.2 and steps 21 and
    22). The node daemon asks the host to start the anchor and never creates, opens-and-keeps or
    duplicates a job handle; it queries through `core/Contain.ps1`, which closes the handle in the same
    call (the job-handle lifetime test of lifecycle step 11). Tests, in the isolated host instance only:
    restarting `node serve` mid-goblin leaves the goblin and a grandchild alive, checked by pid and
    procStart; **control:** a test-only daemon variant that keeps a duplicated handle kills them on
    restart, so the test can see the failure; a static tripwire finds no job-handle call outside
    `platform/windows/` and the anchor. A goblin is never a child of an ssh session: the spawn path
    from R19 runs in `node serve`, in the user's session.
19. **R19. Act verbs** (SPAWN; after step 3.8, R10, R18 and lifecycle steps 24 to 28).
    `session.spawn`, `session.resume`, `session.close`, `session.park`, `session.route`,
    `worktree.create`, `worktree.remove`, each journaled (R3) and admitted by the node's own gate
    (lifecycle step 32, on the node's own counters). R9's policy is enforced here, the
    permission ceiling first. Labels are allocated only by the hub before the request leaves.
    `session.close` carries the pid and procStart the hub last saw, with their ns (R11), and the node refuses if its view
    differs. The node's audit log
    records every act request with its outcome. Then the hub's own CLI switches to reach its own node
    over `local`, so there is one actuation path. Tests first: one refusal per policy rule, each
    mutated; a spawn above the ceiling is refused; a request cut by a partition resolves through
    `request.status`; T1 e2e over `local`, then T2 through the WSL sshd.
20. **R20. Alerts over the link** (PROJ; after lifecycle step 13 and R13). `alert.raise` from the node,
    a node outbox that drains in seq order on reconnect, alerts older than 24 h delivered marked
    stale. Tests first: a partition queues alerts and they drain in order; nothing is killed because
    of a partition.
21. **R21. Delivery** (PHASE5; after lifecycle step 13). `session.deliver` and `delivery.status`, the
    stages queued, accepted, handed-over, seen, expired, and the message journal. The node hands over
    through **`Send-SessionMessage`, the session-message primitive lifecycle step 13 owns**
    (`agents/<name>/Message.ps1` behind the engine port), the same primitive local wake messages and
    the delivery half of `tell` use, never Claude's cross-machine route. `handed-over` records that
    primitive's tristate receipt; `seen` is its `known: delivered` (the follower saw the marker as a
    user turn). Tests first with a fake primitive for each outcome: a refusal whose reason is held is
    `known not delivered: held`, never "failed"; a resend with the same messageId stops at `accepted`; an unheard
    outcome is `unknown` naming the last stage. Ledger note above.
22. **R22. Fleet adoption (D11)** (SPAWN and INSTALL; after R16 to R19 and overlay O1). A real second
    Windows device, enrolled, runs one real goblin through a working day, shadowed against the same
    work done locally. The PR records who used it, for what, how long, and what broke.

F. The overlay repository (separate; not built here)

`horde-overlay` is its own repository with its own rules. Its only contract with Horde is
`horde-overlay endpoint --name <n> --json`, emitting `schema/overlay-endpoint.v1` from this repo:
an address per peer, the local interface, and a tristate health with `observedAt`. O1 (endpoint over
an existing Tailscale install, read-only) can start once R1 merges; O2 (one-click Tailscale: detect
and reuse the installed 1.96.3, silent MSI otherwise, `up --auth-key --unattended`) and O3
(WireGuard, its own tunnel name, never touching `vpn-hub`) follow, tested in a throwaway VM, never on
this desktop. The overlay never sees Horde keys, never edits sshd and never opens Horde ports.

## What can start now

The NOW set, in order, one PR each: R0 (before engines E2); R1; R2, R3 and R4; R6; R8. Overlay O1
in its own repo after R1.

## What waits

- **Other plans' steps**: R5 (engines E1, lifecycle step 5, hosts step 5); R7 (Phase 3 plan step 1);
  R9 (R0, engines E2 to E4).
- **PROJ**: R10 (first of R10, engines K1, engines R1, lifecycle step 24; all four before step 3.8),
  R11, R12 to R15, R20.
- **INSTALL**: R16 is installed and proven (2026-10-05); R17 follows.
- **SPAWN**: R18, R19; R22 also needs INSTALL.
- **PHASE5**: R21 (and lifecycle step 13).
- **Deferred**: Linux and macOS nodes (decision 6), until the tmux adapter exists and the node's code
  is proven under PowerShell 7, which is on no machine here (M-07).

## Unproven, and written down

- Whether Win32 OpenSSH honours `command=`, `restrict` and `expiry-time`, and how `ForceCommand`
  quoting behaves through Windows' default shell (R17's first cases).
- Whether `ssh.exe` 9.5p2 accepts `GlobalKnownHostsFile=none` and `IdentityAgent=none` (R5's `-G`).
- Whether WSL 2 localhost forwarding reaches an sshd started with `wsl.exe --exec` (R5 self-check).
- Whether PowerShell 5.1 writes a BOM or re-encodes stdout for the shim (R2 and R5's first test).
- That a `\\.\pipe\LOCAL\` pipe is unreachable from Session 0 (reported, not measured; nothing
  depends on it).
