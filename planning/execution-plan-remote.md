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
   **Amended 2026-10-05 (coordinator's decision, for cross-PC messaging, R21):** a deliver may also
   target a session whose label the node's own `remote.deliverTo` lists. That key is the node owner's
   exactly like `remote.permissionCeiling`: settable only in the node's own layers, L1
   (`<HordeHome>\engine.json`) and L4 (`<HordeHome>\engine-live.json`), the engines plan's two files,
   read by the node's one layer reader, `core/NodeEngineLayers.ps1`'s `Get-HordeNodeEngineLayers` (#109), again
   for every deliver as for every spawn - one source of truth for a node's configuration; never from
   the link; and its default is no label. A live rule beats L1, and an empty value withdraws every
   opt-in. The value is a bounded list: at most 64 hub labels, each `^[A-Z]{1,2}([1-9][0-9]{0,3})?$`,
   none twice, and every refusal names the entry. **A node layer that fails its checks refuses every
   deliver, exactly as it refuses every spawn** (coordinator's decision, 2026-10-06), a deliver to a
   hub-spawned session included. **Until R9 lands, hub-spawned or opted-in is the whole deliver
   gate.** What R9 changes: the permission ceiling
   is checked on top of that rule, for an opted-in session exactly as for a hub-spawned one, so an
   opted-in label running above the ceiling is refused with the reason; R9 does not widen the rule.
   **The gate is applied to the resolved session** (review of PR #97, F1): the one the session id, or
   the label it carries, led to on the node, never the one the hub meant. Hub-spawned status passes to a
   new session id only through the process (pid and procStart, in R11's namespace), never through a
   label, because labels are not unique and a session the hub never spawned can wear the label of one
   that ended. A live session id wearing a label other than the one the deliver names is refused, never
   retargeted. `remote/Messaging.ps1`'s `Resolve-HordeDeliverTarget` decides it, and R9's ceiling is
   checked on the session it returns.

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
    **The attach shim reads stdin through PowerShell's `$input`, never a .NET Console stream**
    (`[Console]::In`, `[Console]::OpenStandardInput()`): under Windows sshd the Console stream never
    returns the session's data and the session hangs, while `$input` streams (issue #100, measured
    2026-10-06 on 9.5p1 and 9.5p2; review of PR #103, probe p8). The node writes every frame into that
    stdin, so this is the shim's first case; R16 pins it with the mutant `echo-reads-console-stdin`
    (`transports/ssh/test/mutations/sshd-live.psd1`).
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
    **The act path, first version (founder's request and coordinator's decisions, 2026-10-05).** So that
    M can start, message and close an orchestrator on the always-on box before 3.8, R18 and lifecycle
    steps 24 to 28 land, `session.spawn` and `session.close` are built first, in four PRs: A1 (R9: the
    `permission` and `remote.permissionCeiling` keys, `schema/node-policy.v1` and `core/NodePolicy.ps1`,
    the launch port `core/AgentLaunch.ps1` with `agents/<name>/Launch.ps1`, and the effective mode read
    back from the harness's own record, issue #67); A2 (spawn, send-text and close in the node's own
    WezTerm mux, `hosts/wezterm/`); A3 (the two verbs, journaled once per id); A4 (the hub's CLI and a
    live acceptance run). Process launching lives only in `hosts/<name>/` and `agents/<name>/`;
    `remote/` stays under ExecScan's proof. What this version decides:
    - **No anchor yet, so no job-object containment.** The pane's program is the harness itself, a
      child of the terminal's mux, never of `node serve`, so restarting the node kills nothing.
      Containment arrives with the anchor at lifecycle step 22 and the anchored spawn of step 27;
      until then a remote session's descendants are what the host's own teardown leaves (R18).
    - **The worktree is optional.** Absent, the session runs in the node's registered clone
      (`node-policy.v1` repos); present, in `<worktreeRoot>\<name>` and nowhere else.
    - **The ceiling** defaults to the level below the top. A node's owner may set it to the top in L1
      (the always-on box: ssh access there is already that trust); L4 may only lower it; nothing the
      link carries can raise it.
    - **The name** is the label plus the run title, capped at 60 characters, given at birth with
      Remote Control on.
    - **Fail closed on the mode, before any work.** The session starts with no prompt. The node reads
      the effective mode back from the harness's own record, after typing one fixed line that asks for
      nothing, "Reply with OK only.": a session started with no prompt keeps its transcript in memory
      until the first user turn (measured 2026-10-06 over 279 transcripts), so there is nothing to read
      before it. The cost is one model turn; the window is that one turn, which asks for nothing. If the
      mode cannot be read, or it is any other level than
      the one asked, the session is closed and the spawn refused, so a wrong mode never sees work. Only
      then is the prompt delivered, and always by file (review of #104, F4 and F9): it is written to
      `<records>\<sessionId>\prompt.txt`, a folder only this user may open and that the session is
      granted at launch (`--add-dir` for the harness, F10); the one line typed is "Read <that file> and
      do what it says.", printable ASCII checked before anything starts. The hub's text is never typed,
      since the input box reads `!`, `/`, `#` and `@` as modes. A session that cannot be ended is answered failed,
      recorded as still running, and alerted, never reported refused (F2).
    - **The owner's controls are live.** `policy.json`, `engine.json` (L1) and `engine-live.json` (L4)
      are read again inside every spawn, under the spawn lock: a cap of 0, a lowered ceiling or a
      deleted policy holds from the next spawn without a restart (review of #104, F1).
    - **A session belongs to the hub that asked.** The node records the spawning hub's device id, and
      a close from another hub is refused (F8). At serve start, records a stopped node left `starting`
      are settled by pid and start time as running (alerted: the mode was never read back) or failed
      (F5).
    - **A spawn holds the node's serve loop**, which is single-threaded: up to about 160 s at the
      default bounds (process 60 s, mode 60 s, and when the session is not kept, close 20 s and the
      host's end 20 s). Pings and reads on other links wait meanwhile, so a hub waits at least that
      long before judging the node gone (review of #104, F7). Acting asynchronously is later work.
    - **No live acceptance before #99.** The live run waits for #99 (a pane tied to its process by
      the pane id), as well as R17 and the founder's login.
    - **The acceptance run's checklist** (laptop to the always-on box, one real session): the session
      starts with no prompt; the no-op line is typed and the permission-mode line read back as the level
      asked; only then the prompt; the session is named with Remote Control on; it is closed and
      verified gone by pid and start time; the report lists it. And one measurement: whether a local
      slash command, typed instead of the no-op line, makes the harness write its transcript without a
      model turn. If it does, a later PR swaps it in for the no-op line.
      And one more measured item: reading the prompt file in its granted folder causes no approval
      prompt at plan and at ask.
    - **No engine environment.** A pane does not inherit its starter's environment (measured
      2026-10-05, issue #95), so until engines E10's launch stub a remote spawn allows only a profile on
      the harness's own login.
    - **Not yet**: `session.resume`, `session.park`, `session.route`, `worktree.*`, the per-node
      outbox and the binding record, each at its planned step.
20. **R20. Alerts over the link** (PROJ; after lifecycle step 13 and R13). `alert.raise` from the node,
    a node outbox that drains in seq order on reconnect, alerts older than 24 h delivered marked
    stale. Tests first: a partition queues alerts and they drain in order; nothing is killed because
    of a partition.
21. **R21. Messaging over the link** (NOW; re-scoped 2026-10-05 at the founder's request, top priority:
    M on this laptop messages an orchestrator on the always-on box and gets its reply, all through
    Horde). It no longer waits on lifecycle step 13: the node hands a message over through a
    **messenger port**, and the first messenger is the fleet's mail, whose delivery semantics are
    ported, not re-built.
    - **What the fleet's mail does, and what is kept** (wezfleet `lib/Mail.ps1`,
      `hooks/wf-mail-deliver.mjs`, `commands/tell.ps1`, `commands/mail.ps1`): the body is written to the
      target's inbox and never typed; the receiving session's own Stop hook hands it over at a turn
      boundary and acks it only once its id is seen in that session's transcript (TAKEN); for an idle
      target one short wake notice, carrying only the id, is typed through the guarded path; a mailbox
      follows a session-id change by the process (pid and start time). Kept, all of it. The body is
      never typed, on any path; there is no keystroke fallback.
    - **The slices, one PR each, in order:**
      1. wezfleet (its own repository): `wezfleet mail post` (queue under a caller-given id, then the
         wake notice; a second post of the same id writes nothing and wakes nothing) and `wezfleet mail
         status` (queued, handed-over, taken, unconfirmed, absent), both with `-Json`.
      2. Contracts and this amendment: `mail.next` (hub to node, read: the node's oldest unsettled
         outbound message and how many wait) and `mail.receipt` (hub to node, write: the stage of the
         hub's delivery, written to that outbox record only); `session.deliver` gains an optional
         `label`, the target's stable identity, followed by the node when the session id moved (a
         compact or a /clear), never a pane. `link-verbs.v1` may still be edited until R17.
      3. **Amended 2026-10-06 to what PR #102 ships (review of #102, finding 8); split in two.**
         - **3a, the messenger port (PR #102).** `messengers/Port.ps1` (post and status, tristate
           answers), the fourth port family beside `hosts/`, `agents/` and `transports/`
           (`tools/HostNames.ps1`, `tools/FunctionNames.ps1`, and `messengers/*/test` in
           `test/lib/SuiteFiles.ps1`), `schema/messenger-capabilities.v1` (body.untyped,
           idempotent.post, receipt.receiver, wake; only yes counts), and `messengers/memory`, the
           in-process test fake, which declines receipt.receiver so `Resolve-HordeNodeMessenger` never
           picks it. **The port lives in `messengers/`, not `remote/`**: it invokes what each messenger
           registers, and `remote/` stays pure under `tools/ExecScan.ps1`. The port checks the message
           against session.deliver's own patterns and ttl ceiling before any adapter sees it, calls
           only a registered messenger, and reads an adapter's answer only when it names the message it
           was asked about, its stage is one of the list, and its reason is one line within reasonBytes
           (given for held). **The port passes stages through as the adapter said them.** It does not
           own forward-only receipts or the args-hash check on a repost: those are
           `remote/Messaging.ps1`'s rules (review of PR #97), enforced in slice 4 against the message
           journal, and a port test pins that a backward stage reaches slice 4 uncorrected.
         - **3b, the wezfleet adapter (its own PR, after slice 1's CLI shape has shipped).**
           `messengers/wezfleet`, which runs slice 1's two commands, and the `messengers/` exec guard
           that comes with the first messenger that starts a program. **Merge conditions, recorded from
           the review of #102 (findings 1 and 7), each tested red first with a mutant:**
           (1) the conformance suite observes real side effects, never the adapter's own report: what
           was actually typed is read from a fake pane or a recorded send-text stub, and wakes are
           counted the same way; the wake text is one line, holds no control characters and never
           contains the body; a repost wakes nothing and never resets a stage, and a repost after a
           later stage returns that later stage; a conformance mutation spec for each messenger, as the
           transports have one.
           (2) start sites: an absolute .exe, or a fixed `powershell.exe` with a fixed script path, its
           arguments built as separate argv elements, never one command string; a `messengers/`
           ExecScan or ExecGuard allowlist that refuses a second start site.
           (3) wezfleet missing, the wrong version, or output that is not JSON each comes back
           `unknown` with the reason, never a stage.
         The node takes its messenger injected in both: slice 4 does not wait for 3b.
      4. The node side: `node serve` answers `session.deliver` and `delivery.status` through the
         message journal (R3, kind `message`, keyed by messageId with its argsHash: a resend returns the
         recorded stage and posts nothing), and `mail.next` and `mail.receipt` from the node's outbox.
         It takes its deliverer injected and wires in slice 3a's port once #102 merges. **Slice 4 owns
         what the port passes through** (review of #102, findings 2 and 4): a stage a messenger reports
         is never allowed to move a message backward or overwrite a final stage (forward-only, as
         `Resolve-HordeMailReceipt` already rules for receipts), and a repost of one messageId with a
         different argsHash is refused, never answered with the first content's stage. The
         `remote.deliverTo` gate, the journal and the wake-notice decision are this slice's and 3b's,
         not 3a's.
         The gate above (hub-spawned or `remote.deliverTo`) is checked here, on the resolved session,
         through `remote/Messaging.ps1` (landed with slice 2, after the review of PR #97): the deliver
         target (`Resolve-HordeDeliverTarget`), the receipt (`Resolve-HordeMailReceipt`: forward only,
         a final stage never overwritten, the ack carrying the recorded stage, a receipt for a message
         never handed out refused) and the outbox (`Select-HordeMailNext`: every stage but queued
         settles, so held never blocks the queue). A ttl above 7 days is refused by the contract.
      5. The hub side and the CLI: `horde tell <device>/<label>` resolves the label through the mirror
         and waits for TAKEN; `horde tell --status <messageId>`; `horde hub serve` drains every node's
         outbox, delivers through its own node over `local` (one actuation path), and sends the receipt
         back, so the sender on the node sees TAKEN too. The hub believes only the link about who
         sent outbound mail: `from.deviceId` must be the link peer's enrolled device
         (`Test-HordeMailSender`), or the receipt is refused; mail for a third device goes only through
         that device's own node and its gate. Its end-to-end test measures the 5 s drain twice: with an
         ordinary outbox, and with a held message at its head.
    - **Stages.** queued (journaled on the node), accepted (in the target's mailbox), handed-over (the
      receiving hook handed it to a turn), seen (TAKEN: confirmed in the target's own transcript),
      expired, held (known not delivered, never "failed"). A mail receipt adds refused (the hub would not
      deliver it: no live session wears the label, or the target's gate said no). An outcome nobody
      heard is `unknown` naming the last stage.
    - **Latency, decided 2026-10-05: pull, bounded.** When a node's outbox is non-empty, the hub drains
      it within 5 s; the end-to-end test of slice 5 measures it and fails above the bound. **A node push
      (a node-to-hub verb) is a later slice**, after R17 gives the link a node-initiated end.
    - **Tested without a live session.** Every suite runs under a temp `WEZFLEET_ROOT` and a temp
      HordeHome, and refuses to start if either is outside the temp folder. The wake notice is tested
      only against a fake. The real Stop hook is run with a fake session id and a fake transcript, which
      proves a message Horde posted is handed over and TAKEN. Over `local`, the end-to-end test runs two
      node daemons, one playing the remote box; nothing waits for R17.
    - **Later, unchanged in intent:** when lifecycle step 13's `Send-SessionMessage` lands, it becomes a
      second messenger behind the same port, and the hub picks per target what that target supports.
      Ledger note above (wezfleet `tell`'s duplicate guard) still applies when slice 5 replaces `tell`.
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

The NOW set, in order, one PR each: R0 (before engines E2); R1; R2, R3 and R4; R6; R8. Since
2026-10-05, R21's five slices, at the founder's top priority. Overlay O1
in its own repo after R1.

## What waits

- **Other plans' steps**: R5 (engines E1, lifecycle step 5, hosts step 5); R7 (Phase 3 plan step 1);
  R9 (R0, engines E2 to E4).
- **PROJ**: R10 (first of R10, engines K1, engines R1, lifecycle step 24; all four before step 3.8),
  R11, R12 to R15, R20.
- **INSTALL**: R16 is installed and proven (2026-10-05); R17 follows.
- **SPAWN**: R18, R19; R22 also needs INSTALL.
- **PHASE5**: none since 2026-10-05; R21 was re-scoped to NOW (see its line).
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
