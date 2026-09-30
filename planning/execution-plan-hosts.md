# Execution plan: hosts - tmux first, psmux second, Ghostty deferred

Agreed 2026-09-30. This plan sets the order of work for Horde's next terminal hosts after WezTerm. It
covers the capability files and their schema, the tmux command language that tmux and psmux share,
each host's isolation harness and e2e, and how each host handles job objects and orphans. Its
companion for agents is `planning/execution-plan-engines.md`.

VS Code stays the LayoutPort proof, in migration-plan Phase 7. tmux becomes the TerminalPort proof.
VS Code cannot prove that port, because it declares text read and text send as "no" and so cannot
exercise those verbs.

## Sources, and what is already decided

Two designs written on 2026-09-30 and not committed:

- **The hosts research.** Read-only, except for a throwaway tmux server on a private socket inside
  WSL, killed at the end. It measured WSL 2.7.8.0, the distro `ubuntu-binder`, tmux 3.4, and nothing
  on the Windows PATH.
- **The lifecycle and admission design.**

Their decisions are cited as "hosts decision N" and "lifecycle decision N". Settled:

1. **Windows agents only for now** (hosts 1). The tmux adapter proves the port in tests and serves a
   future Linux or macOS Horde. It does not run the live Windows fleet inside WSL.
2. **psmux is installed with `winget install psmux` when its adapter goblin starts**, because the
   founder asked for psmux support (hosts 2). The founder is told first.
3. **The shared tmux command language lives in `hosts/tmux/`** (hosts 3). `hosts/psmux` imports it as
   a declared dependency, and the host-name check gains one allowlisted cross-host import. The code is
   not duplicated.
4. **Ghostty ships its capability file and a minimal adapter only when Horde runs on macOS or Linux**
   (hosts 4). Until then it is deferred.
5. **The port contract changes go into the projection PR before it merges** (hosts 5):
   - `-Capabilities` becomes mandatory;
   - a handle is unique per instance;
   - every pid and cwd carries its namespace;
   - each adapter maps native ids to handle text.

   All four are now written in `core/HostPort.ps1` on `feature/core-projection` (commit 40d457f), which
   has not merged yet.
6. **Descendants are tied to the goblin's lifetime** (lifecycle 2): a Windows job object with
   kill-on-close, or the equivalent on each host. Anything that escapes is found by its ancestry. It
   is reclaimed only when ownership is proven, and reported otherwise.

## The contract the adapters are written against

This is `core/HostPort.ps1` on `feature/core-projection`.

**The capability vocabulary is closed.** A port declares each of these 15 names:

- `list`, `pid`, `tty`, `cwd`
- `title.read`, `title.set`, `text.read`, `text.send`
- `spawn`, `spawn.env`, `spawn.cwd`
- `kill`, `focus`, `selfHandle`, `instance.startedAt`

Each is declared as `yes`, `no`, `declined` or `unverified`. Core relies on a capability only when it
is `yes`. A request for anything else is unknown, with a reason.

**Handles:**

- Handle text is plain. The adapter maps each native id to it one to one, for example `%1` to `p1`,
  so no `$` reaches a reason string.
- A handle is unique within its instance.
- `running` counts instances (namespaces), not server processes.
- The adapter builds the instance id, and the id must change when the server restarts.

**The window and tab levels:** a multiplexer's session maps onto `window`, and its window onto `tab`.

**Namespaces:** a pid or cwd names its space: `windows`, `wsl:<distro>`, `posix` or `synthetic`.
Core's process table is `windows`, so a pid or cwd from any other space is unknown, with the reason.

## When each step can start

- **NOW**: needs only what is on `main`.
- **PROJ**: waits until `feature/core-projection` merges with the HostPort contract.
- **SPAWN**: waits for Horde's launch stub (`planning/execution-plan-engines.md` step 21, E10).
- **INSTALL**: waits for a tool that must first be installed, and the founder is told before it is.
- **UNIX**: waits until Horde runs on macOS or Linux.

## How every step is done

As in the phases 0-2 plan:

- a worktree from a freshly fetched `origin/main`;
- tests first;
- every new check mutation-tested;
- verified from a fresh CRLF checkout;
- an independent adversarial review of every code PR before merge;
- `gh pr merge --merge`, never squash;
- every count copied from command output.

Also for hosts:

- **Everything that spawns or kills panes runs only inside that host's isolation harness**
  (CONTRIBUTING 3). The harness asserts it cannot see anything it did not create before it destroys
  anything, and aborts if it can. It never falls back to a shared server.
- **A test that kills never lets the code under test choose the victim** (CONTRIBUTING 9). It passes a
  guard that acts only on what the test created and still holds, as
  `hosts/wezterm/test/test-isolation.ps1` does.
- **Host-specific tooling lives in `hosts/<name>/test/`** (CONTRIBUTING 14), and every suite is built
  on `test/lib/Suite.ps1`.
- **A capability is `yes` only with evidence.** A documented one that has not been run here is
  `unverified`, which counts as `no`.

## Steps

A. The capability files (PROJ)

1. **`schema/host-capabilities.v1.json`.** The schema names no host; the data in each file is the
   host's own.
   - `core/Schema.ps1` has no maps with free keys, so the file holds an array of `{ name, state,
     evidence, minVersion?, maxVersion?, space? }`.
   - `name` covers the 15 terminal-port names, plus the layout rows of migration-plan section 4:
     `windows`, `tabs`, `splits`, `sizes`, `workspaces`, `capture`, `applyBeforePaint` and `decorate`.
   - `state` is `yes`, `no`, `declined` or `unverified`, and `evidence` is required and must not be
     empty.
   - `space` is `windows`, `wsl:<distro>`, `posix` or `synthetic`, and qualifies `pid` and `cwd`.

   A drift test fails if the schema's terminal-port names differ from `core/HostPort.ps1`'s list, the
   same guard `test/test-schema-session-record.ps1` keeps against the ownership table. Golden fixtures
   come first, with one rejected fixture per rule.
2. **`hosts/wezterm/capabilities.json`, and one loader.** The first host's data comes from what has
   already been measured. `Read-HordeHostCapabilities -HostName <name>` in core names no host. It
   reads the file, validates it, and passes it as the port's `-Capabilities`. An adapter may only
   narrow the static file at run time from the version it detects, and never widen it.
3. **The conformance suite, `test/lib/Conformance.ps1`** (migration-plan 4.1). It iterates over a
   host's `capabilities.json`:
   - every `yes` gets a positive test inside that host's isolated instance;
   - every `no` or `declined` gets a test that the adapter refuses honestly, with an unknown that
     names the capability.

   The WezTerm adapter from Phase 3 decision 1 is the first host to run it.
4. **The migration plan's host table is generated from the files.** A test fails when a
   `capabilities.json` and the section 4 table disagree, so the table cannot drift (D5; D12: "a new
   host is a new column").

B. The shared tmux dialect in the name ratchet (NOW)

5. **One allowlisted cross-host import.** `tools/HostNames.ps1` learns one new kind of entry: a file
   in another host's folder may name this host once, when that single mention is a dot-source of this
   host's `Dialect.ps1`.
   - The entry sits in `hosts/tmux/allowlist.txt`, for example
     `hosts/psmux/Adapter.ps1 | 1 | declared import of the shared dialect`.
   - The ratchet checks that the one mention in that file is the import line.
   - Any other mention of tmux in `hosts/psmux/` fails.

   Everything psmux needs from the dialect is exposed by `hosts/tmux/Dialect.ps1` under names that
   are neutral to both hosts:
   - the `-F` field lists and their parser;
   - the target syntax;
   - the `send-keys -l` escaping;
   - the list of variables to scrub (`TMUX`, `TMUX_PANE`).

   "psmux" does not contain the substring "tmux", so the two hosts' names do not collide.

   Tests come first, on fixture trees:
   - the import passes;
   - a second mention fails;
   - an import of a file other than `Dialect.ps1` fails;
   - the growth rules still hold.

   This step and engines step 2 (E1) both edit `tools/HostNames.ps1`, so they land one after the
   other.

C. tmux, over WSL (first)

6. **`hosts/tmux/Transport.ps1` and `hosts/tmux/Dialect.ps1`** (NOW; pure and fixture-driven).
   - **Call form.** Every call is `wsl.exe -d <distro> --exec tmux ...`. It is never `wsl.exe -- tmux`.
     With `--`, the Linux shell parses the arguments again: `#{pane_id}|$HOME` came back as `n`, and a
     `|` became a pipe (measured). The distro comes from configuration. `ubuntu-binder` is only this
     machine's measurement and is never written into code (CONTRIBUTING 11).
   - **Decoding.** Before each call the transport sets `[Console]::OutputEncoding` to UTF-8. wsl.exe's
     own messages are UTF-16 with NULs between the characters, so they are decoded as such.
   - **Exit codes.**
     - exit -1 (`WSL_E_DISTRO_NOT_FOUND`) means unknown, and the reason names the distro;
     - exit 1 with `no server running` or `error connecting` means no instance on that socket;
     - any other failure means unknown, with stderr as the reason.
   - **Cost.** One `list-panes -a -F` per read, never one call per pane: a warm wsl.exe call measured
     about 207 ms.
   - **Read path.** It never calls `new-session` or `start-server`. In tmux a read on a dead socket
     does not start a server (measured twice), but only this rule guarantees it.
   - **Dialect.** The dialect maps each native id to handle text and back: `%N` to `pN`, `@N` to `wN`,
     `$N` to `sN`.

   Tests:
   - the mapping round-trips every id;
   - no `$` reaches any output;
   - one malformed row makes the whole list unknown;
   - a fixture with UTF-16 stderr decodes to readable text.
7. **The isolation harness, `hosts/tmux/test/Isolation.ps1` and `test-isolation.ps1`** (NOW). It does
   exactly what the research measured:
   - **Private server.** Every call, `kill-server` included, carries `-L horde-test-<pid> -f /dev/null`.
     Measured: the private server listed exactly its own two panes. `kill-server` exited 0, and the
     next call answered `no server running on /tmp/tmux-0/horde-probe-759` with exit 1.
   - **Private socket folder.** `TMUX_TMPDIR` points at a fresh temporary folder, so even a mistyped
     socket name cannot land in the user's socket folder. How it reaches the Linux side (`WSLENV`, or
     `--exec env TMUX_TMPDIR=...`) is not measured yet. This step measures it first, and the harness
     asserts the socket path afterwards.
   - **Scrub.** `TMUX` and `TMUX_PANE` are removed from the harness environment, because a bare `tmux`
     inside a tmux pane targets that pane's server. This is the same trap as `WEZTERM_UNIX_SOCKET`.
   - **Assert before destroy.** `#{socket_path}` must equal the path the harness built, and
     `list-panes -a` must show only the panes the harness created. Otherwise the harness aborts.
   - **Teardown.** `kill-server` runs on the private socket. The harness then checks that `no server
     running` really comes back before it reports the teardown done.

   Mutations: dropping `-L` must trip the assertion, and so must an extra pane nobody created. There
   is also a control: a harness pointed at the default socket must abort.
8. **The read half, `hosts/tmux/Adapter.ps1` and `hosts/tmux/capabilities.json`** (PROJ).
   `New-HordeTmuxHostPort` builds:
   - handles through the dialect;
   - `window` from the tmux session, and `tab` from the tmux window;
   - the instance id `<distro>.<socket>.<serverpid>`, which changes on restart;
   - `startedAt` from `#{start_time}`;
   - pid and cwd with the space `wsl:<distro>`, which core reads as unknown by design.

   `capabilities.json` follows the research's table 1.4. Every entry measured with tmux 3.4 is `yes`,
   with the exact command as its evidence. The step also measures one thing the research did not:
   whether tmux ever reissues a killed `%N` within one server's life. The result goes into the
   evidence for `list`.
9. **The runtime verbs** (PROJ; spawn needs SPAWN for a real agent).
   - `spawn` is `split-window` or `new-window` with `-d -P -F '#{pane_id}'`, the cwd from
     `wslpath -u`, `-e` for environment, and `-- <argv>`.
   - `text.send` is `send-keys -l`, then `Enter`. `text.read` is `capture-pane -p -J`. `title.set` is
     `select-pane -T`. `kill` is `kill-pane`.
   - Paths going back to Windows use `wslpath -w`.
   - The adapter sets `WSLENV` so that a Windows child sees `TMUX_PANE` and Horde's variables.
     Measured: without it, `cmd.exe` saw `%TMUX_PANE%` unset; with `WSLENV=TMUX_PANE` it printed `%7`.
     This is `selfHandle`.
   - Under hosts decision 1, the argv is Horde's Windows launch stub, run through interop.
10. **The e2e, `hosts/tmux/test/e2e/e2e-tmux.ps1`.** It runs only inside the isolated server. It
    drives the real `horde` commands that read the host (census, sessions, status) with tmux as the
    host, and runs the conformance suite of step 3 over `hosts/tmux/capabilities.json`. The gate:
    every `yes` has passed a positive test, and every `no` an honest refusal.

D. psmux (second)

11. **Install** (INSTALL, when its goblin starts). The founder is told first, then
    `winget install psmux` runs (v3.3.8, the latest release when researched). The installed version
    is recorded.
12. **Measure what the research only read in the docs and source** (after 11). Every psmux capability
    is `unverified` until this PR runs it in isolation:
    - whether pane ids repeat across sessions. The architecture suggests they do, and if so the
      handle becomes `<session>.<pane>` (contract: a handle is unique per instance);
    - the scope of `kill-server` in the installed version;
    - whether two `PSMUX_DATA_DIR` folders are fully independent;
    - `-f NUL` and `PSMUX_NO_WARM`;
    - whether `#{pane_pid}` is a Windows pid;
    - that `#{pane_tty}` is synthetic (`/dev/pty<N>`);
    - `send-paste` with base64.

    Each result becomes the evidence in `hosts/psmux/capabilities.json`.
13. **The isolation harness, `hosts/psmux/test/Isolation.ps1`** (after 11). It is built exactly as
    the research designed it, and the first run measures it:
    - **Private data folder.** Every call sets `PSMUX_DATA_DIR` to a fresh temporary folder, which
      gives a separate registry, mutex and warm server. `-L` alone is not enough: up to 3.3.8, a bare
      `kill-server` tore down every socket.
    - **Every call** also carries `-L <namespace>`, `-f NUL` and `PSMUX_NO_WARM=1`.
    - **Scrub.** Six variables are removed from the harness environment: `TMUX`, `TMUX_PANE`,
      `PSMUX_TARGET_SESSION`, `PSMUX_SESSION_NAME`, `PSMUX_TARGET_FULL` and `PSMUX_DEFAULT_SESSION`.
      With no `-t`, a `$TMUX` inherited from the pane you are typing in wins.
    - **Commands never run.** `kill-server -a` ends every namespace in the data folder, and
      `kill-server` without `-L` is never run either.
    - **Assert before destroy.**
      - The data folder's `*.port` files belong only to the harness's own sessions.
      - `#{pid}` is a process the harness started, checked by pid and creation time, as
        `hosts/wezterm/test/Isolation.ps1` does.
    - **Program path.** The harness and the adapter call `psmux.exe` by its resolved full path, never
      `tmux`. psmux also ships a `tmux.exe` that is the same binary, and the name would also trip the
      ratchet.

    Mutations: an unset `PSMUX_DATA_DIR` must abort, and so must a foreign `.port` file.
14. **The adapter, `hosts/psmux/Adapter.ps1`** (PROJ, after 5, 12 and 13).
    - It dot-sources `hosts/tmux/Dialect.ps1`. That is its one allowlisted import.
    - The instance is the namespace, a hash of the data folder plus the namespace name, and `running`
      counts namespaces, so a user with two sessions is still one instance.
    - pid and cwd are in the `windows` space. That is psmux's main value on this machine: agents run
      as ordinary Windows processes against the same stores.
    - `tty` is `synthetic`, which core reads as absent.
    - `text.send` uses `send-paste`, where newlines, quotes and `;` are never read as a second
      command, and there is no 8191-character limit.
15. **The e2e, and a differential conformance run** (after 14). `hosts/psmux/test/e2e/e2e-psmux.ps1`
    runs inside the isolated data folder. Then the same scenario runs against tmux and psmux, and the
    two results are diffed. Every difference is either explained by the capability files or is a bug.

E. Ghostty (deferred, UNIX)

16. **Nothing is built until Horde runs on macOS or Linux.** Ghostty 1.3.1 has no Windows build; the
    earliest Windows work is planned for late 2026, and that is not a commitment. It cannot read the
    screen on any platform. Its Linux side cannot list surfaces. Neither platform can be isolated to
    the standard of CONTRIBUTING 3: there is no instance whose surfaces a harness can list and assert
    on.

    When the trigger arrives:
    - an honest `hosts/ghostty/capabilities.json` (`text.read: no` everywhere; on Linux, almost
      everything `no`);
    - a minimal macOS adapter over AppleScript for spawn and text send;
    - fixture-only tests;
    - an e2e that prints `[SKIP]` with its reason unless it runs on a macOS runner;
    - no destructive test on a machine where the user runs Ghostty.

    Re-check the deferral when a Windows build ships, or when AppleScript 1.4 changes its API.

F. Job objects and orphans, per host

Lifecycle decision 2 applies to every host. The mechanism belongs to the launch stub, not to the host,
so that it is identical wherever a Windows agent runs. The host sections below say only what differs.

17. **The job object, in the launch stub** (SPAWN, with engines step 21, E10). Before it starts the
    harness, the stub:
    - creates a job object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`;
    - assigns itself to it;
    - holds the only handle;
    - never sets `JOB_OBJECT_LIMIT_BREAKAWAY_OK`.

    Every descendant is then born inside the job. When the stub ends for any reason, the job closes,
    and the node dev servers, background shells and test runners go with it. The stub is the pane's
    program, with no `-NoExit` shell (lifecycle H15), so the pane closes when the agent exits. The
    Win32 code is shared with `horde job run` (lifecycle H11) in one core file that names no host.

    Two points need care:
    - **Services.** A service a goblin declares must be able to outlive the goblin. It is started
      through `horde job run` in its own job, which Horde owns, with an expiry. It is never allowed to
      break away.
    - **Nested jobs.** Nested jobs exist since Windows 8, but whether a host already puts its panes in
      a job of its own is measured per host (below). The design does not assume it.
18. **Per host.**

    | host | what differs | to measure |
    |---|---|---|
    | WezTerm | Pane processes are ordinary Windows children of the mux. | Whether WezTerm assigns pane processes to a job of its own; if it does, that the stub's nested job still kills on close. |
    | psmux | Panes are ConPTY children of a server per session. Its `kill-pane` kills the tree by parent pid and creation time, so a reused pid is never killed (docs). The per-session servers and any `__warm__` server are psmux's own processes: `horde status` reports them as host processes, never as orphans. Tests use `PSMUX_NO_WARM=1`. | That the stub's job survives psmux's ConPTY spawn, so a job created inside the pane still holds every descendant. |
    | tmux (WSL) | Linux processes cannot be in a Windows job. A Windows agent started through interop is still a Windows process, and its stub creates the job as on any other host. Core's process table is `windows`, so pids in `wsl:<distro>` are unknown to it. An orphan inside WSL is reported unknown, with that reason, and never reclaimed. For a future Linux Horde, the equivalent is a process group (`setsid`, then kill the group) or a cgroup (`systemd-run --scope`), measured then. | Whether the Windows process tree of an agent started through interop has an ancestry that core's walk can follow. |
    | Ghostty | Deferred. On macOS and Linux: a process group or cgroup, as for tmux. | When UNIX arrives. |

19. **The kill-on-close e2e, per Windows host** (SPAWN, after 17). This runs in each isolated harness
    only.
    - **Scenario.** A goblin stub starts a child, which starts a long-running grandchild. The test kills
      the stub through the victim guard. Both descendants must be gone within a bounded time, checked
      by pid and creation time, never by pid alone.
    - **Control.** The same scenario without the job object must leave the grandchild alive. That
      proves the test can see a survivor.
    - **Mutations.** Setting `BREAKAWAY_OK`, or dropping `KILL_ON_JOB_CLOSE`, must turn the test red.
20. **Orphans that escaped: report, then reclaim** (lifecycle H1 and H18). Core's
    `core/ProcessTree.ps1` finds dead-root trees in the `windows` namespace. It records each goblin's
    descendants, with their creation times, at every follower sample. That record is what later proves
    ownership, because Windows does not re-parent orphans.
    - **Reclaim.** Only a tree whose ancestry passes through a session Horde spawned and recorded is
      reclaimed, through a verified process handle.
    - **Report.** Everything else is listed as `orphaned, owner unknown`, with its memory.
    - **Host processes** are reported as the host's, from its capability data, never as orphans.

## What can start now

In order:

1. Step 5, the cross-host import in the ratchet. It lands before or after engines E1, never alongside
   it.
2. Step 6, the tmux transport and dialect, on fixtures only.
3. Step 7, the tmux isolation harness.

## What waits

- **PROJ**: steps 1 to 4 (the capability schema, files, conformance and generated table), 8 and 9
  (the tmux adapter), 14 and 15 (the psmux adapter and differential e2e), and step 10 once 8 is in.
- **INSTALL**: steps 11 to 13 (psmux install, measurement and harness). They start when the psmux
  goblin starts, after tmux step 8.
- **SPAWN**: steps 17 to 19 (the job object and its e2e), and a real agent in step 9.
- **UNIX**: step 16 (Ghostty).
- **Lifecycle**: step 20 reports once lifecycle H1 (`core/ProcessTree.ps1`) is in, and reclaims
  with lifecycle H18 in Phase 5.
