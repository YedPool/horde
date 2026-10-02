# Execution plan: workflows - the productivity rules Horde installs in every project it runs

Drafted 2026-10-02 for review. The founder, the same day: "we should continue to run metrics and
canonize workflows that improve productivity as a part of the horde repo setup for when it runs ANY
project." This plan turns the workflows proven on Horde itself into versioned modules, promotes the
three scratch tools behind them into tested Horde code, and adds `horde project init` to install them
in any repository. Its companions on `origin/main` are `planning/execution-plan-metrics.md`,
`planning/execution-plan-engines.md`, `planning/execution-plan-lifecycle.md`,
`planning/execution-plan-remote.md` and `planning/execution-plan-hosts.md`. This plan builds nothing
those plans build; where it needs their work it names the step.

Planning prose may name harnesses, terminals and transport programs. Code may not (CONTRIBUTING 14).
No machine name, address, account or home path appears in this plan or in anything it ships.

## Sources, and what is settled

- **The workflows proven on 2026-10-01 and 2026-10-02**, each paid for by an incident:
  - testing the merge result: PRs #40 and #45 merged green and left main red (`tasks/lessons.md`);
  - batched merges and diff-scoped mutation: re-rebasing after every merge cost about 8 regate
    cycles in one day, and full mutation runs took hours per review round (founder approval,
    2026-10-02);
  - a run with no checks is NOT RUN, and runners get a failure matrix: the scratch gate lock shipped
    four defects in one afternoon, two of them false greens (v1 exit 0 on a dead console, v2 a 3 h
    hang on leaked grandchildren, v3 a lost exit code, v4 a stray CR);
  - test levels;
  - liveness from evidence: an agent was stopped as stalled while its worktree showed edits within the
    hour, because its output file stays empty until it ends.
- **The policy text** is being written into CONTRIBUTING by the "Test levels and merging" PR (in
  progress, 2026-10-02). This plan packages that text; it does not restate or change it. Tag CPR below.
- **Metrics**: M1 merged (#50); M2, the collector and the gate as a setting, in flight. The experiment
  program (cited "EP") and the role-profile design (2026-09-30, read-only, not committed; cited "RP")
  supply the versioning and comparison model this plan reuses. The metrics design is cited "MD" and
  the 2026-09-30 goblin-versus-agent study "Study", as in the metrics plan.
- **The three scratch tools** (interfaces only, below): the gate lock (v4) with its failure-matrix
  test, the remote gate, and the remote agent runner (pilot blocked: the harness on the remote box is
  not logged in).

Binding on every step:

1. **A workflow is data plus at most one module.** Its rules are text and config; any code it needs is
   an ordinary Horde module under the usual ports and Rule 14.
2. **Workflows attach to a project; role profiles attach to a role.** Rules about how an orchestrator
   behaves (context purity, liveness from evidence, distilled handoffs) are RP fragments, not
   workflows. Rules about how a repository is worked (levels, merging, gates, worktrees, lessons) are
   workflows. One rule lives in exactly one of the two.
3. **Metrics decisions 1 to 4 of the metrics plan hold unchanged**: local-only counting, consent before
   recording, no environment override, no backfill, a confidence tier on every value.

## When each step can start

- **NOW**: needs only what is on `main`.
- **CPR**: waits for the "Test levels and merging" CONTRIBUTING PR to merge.
- **CONFIG**: waits for engines E3, E4, E6 and E7 (`horde config` with layers and `explain`).
- **M2**, **M3**, **M8**, **M9**: wait for that metrics step.
- **R5**: waits for remote R5, `transports/ssh`.
- **LOGIN**: waits for the founder to log the harness in on the remote box (open question 6).

## How every step is done

As the remote plan: a worktree from a freshly fetched `origin/main`; a ledger first wherever old code
is replaced; tests first, every new check mutation-tested (diff-scoped per review round, full specs on
the final head); verified from a fresh CRLF checkout; an independent adversarial review of every code
PR; touched suites run on the merge result; `gh pr merge --merge`, never squash. Also for this plan:

- **Every runner ships with its failure matrix**, and the matrix runs against a candidate copy before
  the live tool is replaced: a planted red, a crash, a kill mid-run, a lingering grandchild, an
  unreadable exit code, and a run that ends without its completion line. Each case asserts the run is
  red or NOT RUN, never green.
- **`horde project init` is tested only on fixture repositories it creates** under a temp root, never
  on a real checkout, and each test asserts the files outside the fixture are byte-identical after.

---

# Part 1 - The workflow pack as versioned profiles

## 1.1 A workflow module

```
workflows/
  README.md
  releases.jsonl                     append-only release records, the RP B4.1 shape
  <name>/
    workflow.json                    the manifest, schema/workflow.v1.json
    sections/NN-<id>.md              CONTRIBUTING sections it installs, engine-free
    rules/NN-<id>.md                 short imperatives for the repo-rules layer (RP A2.1)
    gates.json                       its contribution to the project's gates config, if any
```

`workflow.json` (`additionalProperties: false`, arrays of named objects, as `core/Schema.ps1` needs):

| field | meaning |
|---|---|
| `name`, `version`, `schemaVersion` | identity; a positive integer per name, plus a content hash over the composed module (RP B1.3 rules: UTF-8, LF, sorted keys, so a CRLF checkout hashes the same) |
| `summary`, `evidence[]` | one line, and the incidents that justify it, each cited |
| `installs[]` | `{ kind, target, id }`, kind one of `contributing-section`, `repo-rule`, `gates-entry`, `lessons-header`, `config-default`; nothing else can be installed |
| `requires[]` | capabilities: `runner`, `runner.mutation.changed`, `remoteBox`, `gateLock`, `metrics.level>=usage`. An unmet requirement installs the workflow as `degraded`, reported, never silently |
| `judgedBy[]` | `{ metric, direction, guard[] }`: the metric that says it helps and the guard metrics that must not worsen (Part 4) |
| `off` | `{ configKey, removes[], keeps[] }`: `workflows.<name>.enabled = false`; what turning it off removes (its unedited sections and gates entries) and what it never removes (lessons entries, project-edited text) |
| `domains[]` | EP families it is expected to affect, or `all` |

Releases use the RP B4.1 statuses (`candidate`, `promoted`, `rejected`, `retired`, `rolled-back`)
and the same promotion rule (RP B2.4), with one difference: a workflow that only installs CONTRIBUTING
text is reviewed like a planning PR; one that installs a `gates-entry` or `config-default` is reviewed
like code, because it changes what runs.

## 1.2 The seed pack (v1 is today's text, same meaning)

| workflow | installs | judged by (Part 4) |
|---|---|---|
| `worktrees` | the sibling `<repo>-worktrees` folder, fetch-then-add command, one concern per PR, merge commits only | rebase conflicts per merged PR |
| `test-levels` | the CPR levels; `gates.json` levels | wall-clock from ready to merged; main-red events (guard) |
| `merge-result` | touched suites on the merge result before merge | main-red events per merged PR |
| `batched-merges` | combined-tree batch, red member dropped, no rebase between batches | regate cycles per merged PR; main-red events (guard) |
| `diff-mutation` | mutation scoped to the diff per round, full specs on the final head | minutes per review round; mutants escaping to the final full run (guard) |
| `not-run` | a run with no checks, or no completion line, is NOT RUN | false greens found later (guard, target 0) |
| `infra-matrix` | runners and gates ship a failure matrix | infrastructure defects found after rollout |
| `gate-lock` | one heavy job per machine through `horde gate run` | reaps during gate runs; gate queue minutes (guard) |
| `remote-gate` | heavy suites on a configured remote box | local reaps; wall-clock per gate; NOT RUN rate (guard) |
| `lessons` | `tasks/lessons.md` with the header rule only, no inherited entries (a lesson earns its entry in the project that paid for it) | none; carried as policy |
| `metrics-consent` | the consent prompt (Part 3) | none; carried as policy |

`gate-lock` and `remote-gate` install `degraded` until W4 and W10 ship their modules. `remote-agent`
is not in the seed pack: it stays `candidate` until its pilot runs (step W10).

## 1.3 Which version a project gets

A config key, `workflows`, joins `schema/engine-config.v1` and is resolved by the same resolver and
layers as `roleProfile` (RP B4.2): L0 the promoted release of each; the project layer may disable or
pin an older version, never enable a `candidate`; an experiment's run spec (L3) may pin exact
versions. `horde config explain workflows` shows each with its provenance. The project records what
was installed in `.horde/project.json` (Part 3); a span records the versions in force (Part 4).

---

# Part 2 - Promoting the three scratch tools

Each promotion writes `planning/ledger/<module>.md` first, from the scratch file's header comments,
its version history and the lessons and memory entries that name it, with a disposition for every
entry. Everything machine-specific - the box's ssh alias, its account, its remote root, its address -
becomes local config in the user layer (`remote.testBoxes[]: { name, sshAlias, root }` under
`<HordeHome>`), never a default in code. Tests reach a box only through a throwaway sshd they start
(the remote plan's R5 technique) or the `local` transport.

## 2.1 The gate lock: `core/GateLock.ps1`, `horde gate run`

Interface today: `-Label -Command [-MinFreeMB 1536]`; an exclusive file lock released by the OS if the
holder dies; waits for free memory; runs the command as a child with output to files; prints
`GATE <label> released exit=<n>`, and exits with the child's code, 99 if it is unreadable.

- **Where.** Engine-free and host-free, so `core/`. The two OS facts it needs - an exclusive lock that
  dies with its holder, and free physical memory - go behind `core/Platform.ps1`. The lock and run
  folders move under `<HordeHome>\gate\`, one per machine; the scratch tool's lock beside the script
  meant a copied script had its own lock, which the test exploited and a user would not want.
- **Command.** `horde gate run --label <l> [--min-free-mb n] -- <command>`; the last line is the
  released line; no line means NOT RUN.
- **Failure matrix**, `test/test-gate-lock.ps1`, porting the eleven checks of the scratch test and
  adding: the holder killed mid-run releases the lock and the run reports NOT RUN; two contenders run
  one after the other; the memory wait with an injected probe; a null exit code is 99; run folders
  never collide. The lingering-grandchild case uses a guarded killer (CONTRIBUTING 9).

## 2.2 The remote gate: `core/RemoteRun.ps1` + `transports/ssh/` + `hosts/wezterm/Contain.ps1`

Interface today: `-Repo -Commit -Suites -Label [-Mutate] [-Env] [-Companion] [-AllowWezterm]
[-SuiteTimeoutMinutes] [-Keep]`, or `-Attach <run id>`. It ships the commit as a git bundle cut from a
throwaway bare repository, launches a detached job that writes only under its per-label run folder,
copies back logs and decides the verdict locally; exit 0 green, 1 red, 2 setup, 3 NOT RUN.

It splits along Rule 14:

- **`core/RemoteRun.ps1`**: bundle cutting, the run folder layout, per-label pruning (a run never
  deletes another label's folders), the environment redirect into the run folder, the verdict from
  files (`DONE=` per suite, a verdict line, the complete line, else NOT RUN), and kill-by-pid-and-
  creation-time of only what it started. Names no transport, host or harness.
- **`transports/ssh/`** (after R5): copy, run an encoded command, start detached outside the
  session's job object. The program names and the encoding trick live only here.
- **`hosts/wezterm/Contain.ps1`**: the per-run containment the host needs - the shim source
  (`hosts/wezterm/shim/`, built at install, never a committed binary), the socket, config and log
  variables, and the marker sweep that sorts processes into LEAK, FOREIGN and UNATTRIBUTED. It is the
  host's answer to a new HostPort capability, `containRun`; a host without one reports `unknown`, and
  the remote gate then refuses suites that start that host. tmux's answer is the hosts plan's to give.
- **Command.** `horde gate remote --box <name> --commit <c> --suites ... --label <l>`, and
  `horde gate attach <run id>`.
- **Failure matrix**, `transports/ssh/test/test-remote-gate.ps1` against a throwaway sshd: a planted
  red suite; a suite with zero checks (NOT RUN); the local side killed mid-run, then attach collects;
  the remote runner killed (NOT RUN); a missing `DONE=`; pruning leaves another label alone; a reused
  pid is not killed; a marked leaked host process fails the suite and a foreign one is untouched; a
  write outside the run folder fails (the remote profile is listed before and after).

## 2.3 The remote agent: `core/RemoteRun.ps1` + `agents/claude-code/Headless.ps1`

Interface today: `-Repo -Commit -Branch -PromptFile -Label [-Model] [-MaxBudgetUsd] [-TimeoutMinutes]
[-AllowedTools] [-StubAgent]`, or `-Attach`, and `-Fetch`. No credentials of ours go to the box: the
clone's push URL cannot resolve, GitHub variables are removed, commits come back as a bundle, and
`-Fetch` only creates a local branch, never moving an existing one.

- **Shared** with the remote gate: shipping, run folder, detached launch, containment, verdict.
- **`agents/claude-code/Headless.ps1`**: the harness's argv for a fenced, headless, non-persisting run
  (settings sources, permission mode, allowed and disallowed tools, no MCP, budget). It is the
  headless half of engines E9's `Agent.ps1`; a harness without one cannot be sent remotely. Each
  harness's remote login is a `harness-login` secret reference (engines E5), never a copied token.
- **Command.** `horde agent remote --box <name> --branch <b> --prompt-file <f> --label <l> [--fetch]`.
- **Failure matrix** with the stub agent (every line says it is a stub): a stub commit fetched; no
  commit (1); a push attempt fails; fetch refuses to move an existing branch; GitHub variables absent;
  a containment breach (1); the runner killed (3); attach after a local kill.

---

# Part 3 - `horde project init`

`horde project init [<path>] [--dry-run] [--workflows a,b] [--accept <id>...]`. It writes:

| what | where | owned how |
|---|---|---|
| project record | `.horde/project.json` (`schema/project.v1`): a random `projectId`, the runner adapter, the worktree folder, each installed workflow with version and hash | wholly Horde's |
| gates config | `.horde/gates.json`: runner, suite discovery, the levels, the heavy-job lock, a remote box by its local-config name only | wholly Horde's |
| CONTRIBUTING sections | the project's existing contributing file (root, `docs/` or `.github/`), else a new `CONTRIBUTING.md` | between `horde:workflow <name>@<v> sha=<hash>` comment markers |
| repo rules | rendered into each harness's instruction file by that harness's adapter (RP A2.2), never by init | the adapter's marked block |
| lessons file | `tasks/lessons.md` with the header only, if absent | created once, never edited after |
| worktree convention | the sibling `<repo>-worktrees` folder name, in the record and in the worktrees section | as above |
| metrics consent | the user layer, once per user, not per project (3.2) | `horde config` |

## 3.1 Safety rules, each with its test

1. **Idempotent.** A second run with nothing changed writes nothing: the fixture's bytes and
   modification times are compared before and after.
2. **Never overwrites the project's own words.** A marked block whose text no longer matches its
   recorded hash was edited by the project: init shows a unified diff and skips it, exit 2 (needs a
   decision), until `--accept <id>`. An unmarked section with the same heading is the project's own:
   init shows the diff and installs nothing over it.
3. **`--dry-run` is the default on a first run in a repository**: it prints every file it would write,
   with diffs, and writes nothing.
4. **Safe anywhere.** It refuses a path that is not a git work tree, a bare repository or a
   submodule; refuses files it would touch that are dirty; never commits, pushes or switches branch
   (open question 3); keeps each file's existing line endings; writes ASCII itself but imposes no
   ASCII rule on the project. A language with no runner adapter gets `runner: none` and its test
   workflows installed `degraded` with the reason; init never guesses a test command.
5. **Turning a workflow off** (`workflows.<name>.enabled = false`, project layer) removes its unedited
   marked blocks and gates entries on the next run, and shows a diff for edited ones.

Fixtures: an empty repository; this repository (its own sections already exist, unmarked: expect diffs
and zero writes); a Python repository (no adapter); a CRLF repository; a repository with an edited
marked block; one with `docs/CONTRIBUTING.md`.

## 3.2 The runner port, first adapter PowerShell

Test runners get a port like hosts and harnesses: `runners/<name>/`, under the same name ratchet, so
no file outside `runners/pytest/` will name pytest. The port asks:
`Detect(repo)` (tristate), `ListSuites`, `SuitesTouchedBy(diff)`, `Command(suite)`,
`Verdict(log)` (pass, fail, or NOT RUN when the log shows zero checks or no completion line), and the
optional capability `mutation.changed`. `runners/powershell/` is the first adapter, built on the
`test/lib/SuiteFiles.ps1` convention and `tools/Mutate.ps1`; its `Verdict` reads `Complete-HordeSuite`'s
line, and a plain script with no such line is judged by exit code and labelled `estimated`.

---

# Part 4 - Metrics on by default for Horde-run projects

## 4.1 Consent

Metrics decision 2 says off until consent and nothing backfilled. This plan keeps that and makes
consent the normal path: the first `horde project init` for a user asks once, states what is counted
and that nothing leaves the machine, and on yes sets `metrics.level usage` in the user layer (M2's
setting, keeping `enabledAt`). A project may lower the level, never raise it. No environment variable
changes it. Whether the prompt preselects yes is open question 1.

## 4.2 What is counted per project

Every span gains `project { projectId, workflows[{ name, version, hash }] }` beside RP's
`roleProfile`, copied at span open. No path, remote URL or repository name is recorded; `projectId`
is the random id from `.horde/project.json`. Per project, from transcripts and outcome events only:

- tokens by kind, model calls, notional cost, wall-clock, per role, engine, profile and workflow set
  (M1, M2);
- still-waiting turns and context landed (M2 A3 and A5);
- outcomes (M8): PRs opened and merged, regate cycles per merged PR, main-red events after a merge,
  wall-clock from ready to merged, NOT RUN results, false greens later found;
- gate measures from `horde gate`: queue minutes, reaps during a gate run (M6's reap detector),
  remote NOT RUN rate;
- the task's EP domain where it was registered, else `unknown`, never inferred.

## 4.3 Comparing workflow versions

A workflow version is a project-level treatment, so EP's matched task pairs cannot test most of them.
`horde metrics compare --by workflow` compares before and after a version change within one project,
and across projects within one EP family, with n and an interval on every number, and refuses (MD
10.3) when anything else changed in the window: role profile, engine, harness version, metrics
definition version. A result moves a release from `candidate` to `promoted` only under RP B2.4.

## 4.4 The routing method: session, agent or goblin

Routing chooses who does a task: the orchestrating session itself, an in-process agent, or a goblin
session. Until the data supports a rule, it is the Study's draft rules, carried as policy. Derivation:

1. Spans record the choice made, `routing { methodVersion, rule, chosen }`, so following or ignoring
   a rule is itself measured.
2. `horde metrics route` (M9) proposes a rule per EP family, by project, only from declared results
   (EP 5.4) at MODERATE confidence or better; below that it prints "no result at this n".
3. A rule set is released like a workflow: `routing/releases.jsonl`, with `version`, `hash`, its
   evidence chain (route row to batch to pairs to spans) and the founder's approval. `route`
   recommends; it never changes routing by itself (EP 8.1).

---

# Steps

One PR each, in order within a tag.

0. **W0. Ledger** (NOW). `planning/ledger/workflows-scratch.md`: the three scratch tools' headers,
   version histories and failure matrices, and the 2026-10-01 and 10-02 lessons, each with a
   disposition. Test: `test/test-ledger.ps1`.
1. **W1. `schema/workflow.v1.json` and `core/Workflow.ps1`** (NOW). Load, validate, compose, hash;
   golden and rejected fixtures; the hash is equal on LF and CRLF checkouts, with a control that
   changes one byte.
2. **W2. The seed pack, data only** (CPR, after W1). The eleven manifests of 1.2 at v1, their text
   taken from the merged CONTRIBUTING; a shadow test asserts each installed section equals the
   CONTRIBUTING text it came from, with a one-word positive control.
3. **W3. The runner port and `runners/powershell/`** (NOW). The ratchet learns `runners/`. Tests: each
   verdict (pass, fail, zero checks, no completion line) on fixtures; `SuitesTouchedBy` on a planted
   diff with a control diff that touches nothing.
4. **W4. `core/GateLock.ps1` and `horde gate run`** (NOW). The 2.1 matrix. Shadow: agents run heavy
   jobs through both for a day; switch when every result matches; adoption recorded.
5. **W5. `horde project init --dry-run`** (after W2 and W3). Read-only: plans and diffs on the 3.1
   fixtures; asserts zero writes.
6. **W6. `horde project init`, the writer** (after W5). Rules 1 to 5 of 3.1, each a test with its
   control; the e2e scenario drives the real `horde` CLI on a fixture.
7. **W7. Workflows as config, and turning one off** (CONFIG, after W6). The `workflows` key, layers,
   `explain`; disable and re-run removes only unedited blocks.
8. **W8. Consent and project spans** (M2 and M3, after W6). The 4.1 prompt; `project` in the span;
   a planted-secret test shows no path or URL is recorded.
9. **W9. `hosts/wezterm/Contain.ps1` and the `containRun` capability** (NOW). The
   shim built at install; the LEAK, FOREIGN and UNATTRIBUTED sweep in the isolated instance only.
10. **W10. The remote gate** (R5, after W4 and W9). 2.2's split and matrix. Shadow against the scratch
    tool on the same commits until the verdicts match.
11. **W11. The remote agent** (R5 and LOGIN, after W10 and engines E9). 2.3; the stub matrix first, then
    one real pilot with the cheapest prompt that proves a fetched commit.
12. **W12. Workflow outcomes and `compare --by workflow`** (M8 and M9, after W8).
13. **W13. Routing releases** (after W12 and two EP batches with a declared result).
14. **W14. Adoption** (after W6 and W8). `horde project init` on one real non-Horde repository
    (open question 5), shadowed for a week; the PR records what was installed, what was refused, and
    what broke.

## What can start now

W0, W1, W3, W4 and W9, in that order.

## What waits

- **CPR**: W2, then W5 and W6.
- **CONFIG**: W7. **M2/M3**: W8. **M8/M9**: W12, W13.
- **R5**: W10. **R5 and LOGIN**: W11.

## Unproven, and written down

- That a project-level before-and-after comparison can separate a workflow's effect from everything
  else that changes in a week. The refusals in 4.3 make it say "no result" rather than guess; whether
  it ever says more is measured, not assumed.
- That an exclusive file lock is released on holder death the same way under PowerShell 7 and on
  Linux; measured only on Windows PowerShell 5.1.
- That a harness without a native fenced headless mode can be made safe for W11 at all.

# Open questions for the founder

1. Metrics: should `horde project init` ask consent once per user with yes preselected, or must the
   answer be typed with nothing preselected?
2. Until remote node verbs exist, may the remote gate run suites over the user's own ssh alias, though
   the remote design says the link is never a remote shell?
3. Should `horde project init` commit its edits on a new branch and open a PR, or only write files for
   the user to commit?
4. Add "the orchestrating session does it itself" as a third experiment arm beside goblin and agent,
   so routing can choose among all three?
5. Which non-Horde repository should be the first real adoption of `horde project init`?
6. The remote agent is blocked on the remote harness login: will you log it in once, interactively,
   on that box?
