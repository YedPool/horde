# Execution plan: engines - which harness, provider and model each session runs on

Agreed 2026-09-30. The order of work that gives Horde an agent side to match its host side: engine
settings (steps E0 to E11), the `agents/<name>/` adapters for claude-code and codex with their
transcript-port readers, a gemini-cli adapter, provider profiles for Z.ai, DashScope and DeepSeek
through the Claude Code harness, a session key that no longer assumes a UUID, the subscription rule,
resume bindings as the single source of truth, and local-only metrics collectors per engine. Its
companion for terminals is `planning/execution-plan-hosts.md`.

## Sources, and what is already decided

Four designs written on 2026-09-30, read-only, and not committed: the engine-settings design, the
agent-engines research, the lifecycle and admission design, and the metrics design. What this plan
needs from them is carried below. Their decisions are cited as "engine-settings decision N",
"agent-engines decision N", "lifecycle decision N" and "metrics decision N".

Vendors, confirmed:

| name | vendor | harness it runs on here |
|---|---|---|
| opus, sonnet, haiku, fable | Anthropic (fable = `claude-fable-5-1`) | claude-code |
| sol | OpenAI | codex |
| GLM | Z.ai | claude-code, provider `zai` |
| Qwen | Alibaba | claude-code, provider `dashscope` |
| DeepSeek | DeepSeek | claude-code, provider `deepseek` |
| Gemini | Google | gemini-cli |

Settled:

- **A binding has three parts, named by a profile** (agent-engines 1). Horde checks the harness
  against the provider's wire format and refuses a pair that does not match. It never picks a harness
  implicitly.
- **GLM, Qwen and DeepSeek run through Claude Code**, on their Anthropic-format endpoints
  (agent-engines 2). The Codex path for them comes later.
- **gemini-cli gets its own adapter** (agent-engines 3). The Qwen Code harness waits until its hooks
  regression (P1, open at 0.21.6) is measured fixed (4). DeepSeek's `dsh` waits until it leaves
  developer preview (5). opencode is not adopted, but the session key stops assuming a UUID now,
  because that fix is cheap (6).
- **A Claude Max or ChatGPT subscription credential runs only on its vendor's own CLI**
  (agent-engines 7).
- **Aliases pin to a concrete id, at spawn** (engine-settings 4). "sol" pins to the id the installed Codex lists, `gpt-5.6-sol`
  today; the founder is offered a Codex upgrade to reach `gpt-6.1-sol` (8). opus = `claude-opus-5-5`,
  fable = `claude-fable-5-1`, sonnet = `claude-sonnet-5-5`, haiku = `claude-haiku-4-5` (10).
- **Provider keys are read from named environment variables, and Horde never stores them**
  (agent-engines 9).
- **Admission thresholds come in named tiers, set through the engine-settings layers** (lifecycle 1).
  The default tier is "standard".
- **Resume information is the single source of truth**: harness, session id, cwd, provider profile,
  model and argv. It lives in Horde's session record, and one command prints it and resumes from it
  (lifecycle 3).
- **Transcripts are read through a transcript port**, with one adapter per engine under
  `agents/<name>/`. Claude Code and Codex come first, then Gemini CLI. GLM, Qwen and DeepSeek are read
  through their harness's adapter. Core never names an engine (lifecycle 4).
- **No environment variable turns metrics on** (metrics 1). **Tokens are counted only from local
  files**: transcripts, rollouts and harness logs. Horde never calls a vendor's usage or billing API.
  `reconcile` and the `metered` tier are dropped (7).
- **Windows agents only for now** (hosts decision 1, in the hosts plan).

From the engine-settings design's own "Decisions taken":

1. **There is no environment-variable layer for harness, provider or model** (engine-settings 1).
   The environment carries paths only: `HORDE_HOME`, and `HORDE_CONFIG` for tests.
2. **One home variable, `HORDE_HOME`, defaulting to `%USERPROFILE%\.horde`** (engine-settings 2). The
   Phase 3 plan's `HORDE_ROOT` is superseded; shadow logs live under `HORDE_HOME`, and PR #26 is being
   corrected to match.
3. **The per-repo project engine file (L2) is deferred until a repo needs one** (engine-settings 3).
   When it comes, it may only choose among providers defined in the user file, and it may only lower
   the metrics and admission levels, never raise them. Nothing in Half A reads or writes an L2 file.
4. **Model aliases are pinned to a concrete id at spawn** (engine-settings 4).
5. **The `engine` and resume-binding fields are added by editing `session-record.v1` in place**
   (engine-settings 5). That is safe because no writer exists until step 3.8. Once a writer exists,
   any further change needs a `session-record.v2`.
6. **Resume uses the launched binding** (engine-settings 6). Drift from `/model` is shown in
   `horde status` and never rebinds the session.
7. **Model ids** as agent-engines 10 (engine-settings 7).
8. **Selector ranks follow the design** (engine-settings 8): `parent` outranks `run` plus `role` in
   the same layer.
9. **The admission tuner may raise reserves on its own, but only proposes lowering them**
   (engine-settings 9). A raise follows a reap that happened while the gate was open. It is a live
   (L4) rule that expires after 7 days, capped at the conservative tier plus 1 GB.
10. **The pane anchor is a small compiled executable**, following the precedent of `wf-cmdlog.exe`
    (engine-settings 10).

The decisions change the engine-settings design in five places, and the steps below use the
changed form:

1. The Z.ai provider is named `zai`, not `zhipu`.
2. A credential is `harness-login` or `env`. The design's `os-store` kind is not built, per
   agent-engines 9.
3. A provider entry is a **provider profile**. It gains `vendor` and `auth` (`subscription` or
   `api-key`), so the subscription rule is data that the checker enforces.
4. The config's layers are L0, L1, L3, L4 and L5. L2 is not built until a repo needs one
   (engine-settings 3).
5. The design's config keys grow beyond the binding: `metrics.*` (metrics step M12) and
   `admission.tier` (lifecycle 1). Each key lands in its own PR, but all of them go through the same
   resolver. The tuner's raise-only rule (engine-settings 9) is checked by the resolver: a live rule
   written by the tuner that lowers a reserve is refused.

## When each step can start

- **NOW**: needs only what is on `main`.
- **PROJ**: waits until `feature/core-projection` merges with the HostPort contract. That contract
  makes `-Capabilities` mandatory, makes a handle unique per instance, and tags every pid and cwd with
  its namespace. The same branch also carries `schema/session-view.v1` and `core/Projection.ps1`, and
  both still match the UUID pattern: 1 and 2 occurrences, counted on 2026-09-30.
- **SPAWN**: waits for Horde's spawn and launch commands (migration-plan step 3.8, and engine-settings
  Half B).
- **INSTALL**: a tool not yet on this machine. The founder is told before it is installed.

## How every step is done

The same as the phases 0-2 plan:

- a worktree from a freshly fetched `origin/main`;
- a ledger first, wherever anything is replaced;
- tests first, and every new check mutation-tested;
- verified from a fresh CRLF checkout;
- an independent adversarial review of every code PR before merge;
- `gh pr merge --merge`, never squash;
- every count in a commit or PR copied from command output.

Also for this plan:

- **Every flag, variable and file path of a harness is read off the installed CLI** on this machine
  and cited in a comment, as `lib/Agents.ps1` does in wezfleet. A capability that has not been
  measured is `unmeasured`, and `unmeasured` never satisfies a requirement.
- **A real model call costs money.** A test that makes one uses the cheapest prompt that proves the
  point, and says so. `horde config validate` never makes a model call.
- **No secret appears in any file, log, job file or output.** Every step that handles a credential
  has a planted-value test with a positive control.

## Steps

A. Engine settings, Half A: configuration, resolution and explanation (NOW)

Half A writes only config files, so it can ship before Horde spawns anything.

1. **E0. The ledger, `planning/ledger/agents-engine.md`.** Harvested from wezfleet `lib/Agents.ps1`,
   `wezspawn.ps1`, `lib/Run.ps1` (exe and args), `lib/CodexStatus.ps1` and `lib/Common.ps1`
   `Set-WfCwdTrusted`, with their history, PRs, lessons and tests. It carries at least these, each with
   a disposition:
   - the skip-permissions flags differ between agents;
   - codex has no name flag;
   - codex trust is written to its config file before start, as lowercase single-quoted TOML, because
     `-c` does not take;
   - `$Args` is an automatic variable, which is why the parameter is named `ArgList`;
   - a flag the caller gave wins over a generated one;
   - a session's `args` replaces the defaults instead of merging with them;
   - `CLAUDE_CODE_CHILD_SESSION` is removed in the pane, and
     `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE` is set;
   - the job file writes `env` to disk;
   - an unknown exe gets its args back untouched.

   Gate: `test/test-ledger.ps1`.
2. **E1. The `agents/` folder and a port-names ratchet.** `tools/HostNames.ps1` is generalised to
   cover both `hosts/*` and `agents/*`, with the same rules and the same `origin/main` comparison.
   Tests come first: a fixture tree that names a harness outside its folder fails, and the
   growth-record rules hold for agents exactly as they do for hosts. The first PR measures and
   allowlists the mentions core already has: `core/ownership.json` stores X1-X3 and W8, the
   descriptions in `schema/session-record.v1`, and `core/Identity.ps1`. There is no change in
   behaviour. This step and step 5 of the hosts plan both edit `tools/HostNames.ps1`, so they land one
   after the other, never at the same time.
3. **E2. `schema/agent-descriptor.v1` and `core/capabilities.json`.** There is one descriptor for each
   of `agents/claude-code/agent.json` and `agents/codex/agent.json`. Each capability is `yes`, `no` or
   `unmeasured`, and each has evidence. The descriptor has more fields than the design showed:
   - `vendor` (the subscription rule);
   - `protocols` (the wire-format rule);
   - `sessionIdPattern` (step 12);
   - `ownedEnv` (the scrub list);
   - `events`, a map from the harness's hook names to Horde's four events: session-started,
     turn-started, turn-ended and session-ended.

   `core/capabilities.json` says which port can satisfy each capability: `agent`, `host` or `either`.
   Golden fixtures cover the valid shapes and include one fixture per rejected shape. Tests: a
   descriptor without evidence fails, and `unmeasured` never counts as `yes`.
4. **E3. `schema/engine-config.v1` and `core/EngineConfig.ps1` (`Test-HordeEngineConfig`).** This is
   the design's schema with the five changes above. The checker enforces three rules:
   - **The wire-format rule.** A profile or rule that pairs a harness with a provider whose protocol
     the harness's descriptor does not list is an error. With today's descriptors, claude-code with
     `google` is refused (only a translating proxy would work), and gemini-cli with anything but
     `google` is refused.
   - **The subscription rule.** A provider profile with `auth: subscription` is legal only on a
     harness whose `vendor` equals the provider's `vendor`. So Claude Max runs only under claude-code,
     and ChatGPT only under codex.
   - **The pinning rule.** A model that names an alias resolves to the concrete id mapped for the
     resolved provider. An alias with no entry for that provider is an error, and the alias's name
     is never passed through to the provider.

   Fixtures come first, one for each finding in the design's list (except the L2 findings, which wait
   with L2), plus one each for the wire-format and subscription rules. A file offered as L2 is refused
   with the reason that the project layer is not built yet. The secret-shaped-value fixture asserts that the value appears nowhere in
   the output. Every finding is mutation-tested.
5. **E4. `core/EngineResolve.ps1`.** A pure function. It takes the layers (already parsed) and a
   target, and returns one tristate answer per field, with its provenance. Tests cover:
   - the full precedence table;
   - that fields are resolved independently;
   - one test per specificity comparison, including `{parent}` beating `{run, role}`;
   - a tie between rules that disagree is unknown and names both rule ids, while a tie between rules
     that agree resolves;
   - alias resolution, and the error for a missing alias;
   - role aliases in selectors;
   - an alias resolves to its concrete id, and the answer records both (pinned at spawn);
   - every plausible environment spelling (`HORDE_MODEL`, `HORDE_ENGINE`, `HORDE_PROVIDER`,
     `HORDE_HARNESS`) moves nothing, with a control that the same change made in the user file does.

   The capability check runs against the harness, against the provider's `lacks`, and against the
   host. Host capabilities come in as data, a parameter shaped like `schema/host-capabilities.v1`, so
   this step does not have to wait for the contract. Reading the real `hosts/<name>/capabilities.json`
   files is step 23.
6. **E5. `core/Secrets.ps1`.** It resolves `env` and `harness-login` references, and nothing else. It
   answers `set`, `missing` or `unknown (why)`, and it gives the value only to the launch stub. The
   test finds no fake secret in any output, with a positive control.
7. **E6. `horde config validate | explain | get`, and `Get-HordeHome`.** Each command gets an e2e
   scenario that drives the real `horde` with `HORDE_HOME` set to a temporary folder:
   - a config that validates clean;
   - a tie;
   - a warchief on codex, which fails on `delivery-receipt: unmeasured`;
   - a subscription profile paired with another vendor's harness;
   - an explain whose provenance is asserted field by field.

   `Get-HordeHome` returns `HORDE_HOME` when it is non-empty, else `%USERPROFILE%\.horde`, derived from
   the environment (CONTRIBUTING 11). A test covers both branches.
8. **E7. `horde config set | unset`.** It writes with a unique temporary name and an atomic replace,
   and it compares and swaps on the L4 `revision`. The tests come first:
   - a set that would introduce a tie is refused and leaves the file byte-identical;
   - three concurrent writers lose no rule;
   - `--scope project` is refused while L2 is deferred.

   The e2e scenario runs set, explain, unset, explain.

**Adoption for Half A.** For one working day, the warchief runs `horde config explain` for every
spawn it makes through wezfleet, and logs every place the answer disagrees with what wezfleet
actually launched.

B. Provider profiles through the Claude Code harness (NOW for data and checks; SPAWN for use)

9. **P1. `agents/claude-code/providers.example.json`.** Provider profiles for `zai`, `dashscope` and
   `deepseek`. Each has `protocol: anthropic-messages`, `auth: api-key`, an `env` credential
   reference, a `models` allowlist, and `lacks`. The file is an example the founder copies into L1;
   it is never loaded implicitly, so no provider is trusted by default.

   | profile | endpoint | pinned models | lacks, or unknown |
   |---|---|---|---|
   | zai | `https://api.z.ai/api/anthropic` | glm-5.3, glm-5.3-flash | vision and web search depend on the plan tier; caching, count_tokens and beta features unknown |
   | dashscope | `https://dashscope-intl.aliyuncs.com/apps/anthropic` (international) or `https://coding.dashscope.aliyuncs.com/apps/anthropic` (coding plan) | qwen3.7-plus | thinking, caching and images unknown |
   | deepseek | `https://api.deepseek.com/anthropic` | deepseek-flash, deepseek-v4-pro | prompt caching (`cache_control` ignored), `mcp_servers`, documents |

   The Z.ai and DashScope endpoints come from secondary sources, because their first-party pages were
   blocked on this network. They stay `unverified` until step 11 measures them. DeepSeek's come from
   its own documentation.
10. **P2. What the claude-code adapter sends for a provider** (data in `agents/claude-code/`). It
    owns, and scrubs from every child, these variables:
    - `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`;
    - `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU,FABLE}_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL`;
    - `API_TIMEOUT_MS`, `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS`;
    - `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `CLAUDE_CODE_EFFORT_LEVEL`.

    Three rules, each with a test:
    - **A provider that is not native must have its token set.** Claude Code uses the subscription
      login whenever `ANTHROPIC_BASE_URL` is set without `ANTHROPIC_AUTH_TOKEN`, so the founder's
      Claude Max credential would go to a third-party endpoint. The adapter refuses that combination.
      It is the subscription rule enforced where the environment is built. This step owns the
      refusal and its test. The test runs a pure function that builds the environment plan for a
      binding. With a `zai` binding whose token reference resolves to nothing, the function refuses:
      the reason names the missing reference, and the plan sets no variables, `ANTHROPIC_BASE_URL`
      included. A mutation that drops the check must turn the test red. The control: the same binding
      with a fake token set gives a plan with both variables set, and the fake value appears in no
      output. E10's scrub test later runs the same case end to end.
    - **Every model alias is pinned to the provider's model.** All four
      `ANTHROPIC_DEFAULT_*_MODEL` variables and `CLAUDE_CODE_SUBAGENT_MODEL` are set, so no subagent
      asks a third-party endpoint for a Claude model name.
    - **An endpoint that rejects Claude Code's beta fields gets
      `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`.** Claude Code does not retry a 400 on those fields.

    DeepSeek's recipe adds the `[1m]` model suffix and `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, because an
    unrecognised model id is assumed to have a 200K context. Tests run on data and on that pure
    function. Applying the plan to a real process waits for E10.
11. **P3. Measure each provider once** (SPAWN). For each of zai, dashscope and deepseek, one session
    runs in the isolated terminal with the cheapest prompt and the founder's key, read by reference.
    Each measurement goes into `planning/ledger/agent-claude-code.md`: the endpoint answered, which
    model id the transcript recorded, whether `cache_control` was billed as uncached, and whether the
    beta fields drew a 400. Only a measured capability moves from `unmeasured` to `yes` or `no`.

C. The session record's key stops assuming a UUID (PROJ)

12. **K1. The key is (harness, id).**
    - `schema/session-record.v1` gains a required `harness`.
    - `sessionId` loosens to plain id text: `^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`.
    - The per-harness shape moves to `agents/<name>/agent.json` `sessionIdPattern`, and the checker
      applies it. `core/Schema.ps1` has no conditional keywords, so the schema cannot.
    - `parent` gains a `parentHarness`.
    - `schema/restore-plan.v1`'s `sessionId` and `parent` change the same way, and its `resume.kind`
      enum becomes the harness name.
    - `schema/pane-session.v1` is not touched, because it documents wezfleet's format exactly.
    - Only harnesses whose pattern is a UUID compare ids ignoring case.

    Tests:
    - an `ses_...` id (opencode's shape) is accepted under a fixture harness whose pattern allows it,
      and refused under claude-code;
    - the same id under two harnesses gives two records;
    - `core/Identity.ps1`'s refusal of a malformed id still fires.

    This edits v1 in place, which is safe because no writer exists before step 3.8
    (engine-settings 5). It waits for PROJ because the projection branch matches the UUID pattern.

D. The `agents/<name>/` adapters for claude-code and codex

13. **A1. The transcript port contract, `core/TranscriptPort.ps1`** (NOW). It names no engine. For
    each harness it has four functions:
    - `Get-<H>TranscriptCapability`;
    - `Find-<H>Transcript` (a session to its file);
    - `Read-<H>Observations -Since <byte offset>`, which returns content-free observations in Horde's
      vocabulary: the four events, a tool's name and duration, the model, and token counts;
    - `Get-<H>TranscriptLength`, which lifecycle A3.2 needs to refuse a resume of a truncated
      transcript.

    It is followed by byte offset, and it tolerates a half-written last line: the line is skipped and
    counted. Lifecycle step H2 (the classifier) consumes it. A missing capability is unknown with a
    reason, never "none".
14. **A2. `agents/claude-code/Observe.ps1`** (lifecycle H3; NOW). It reads the transcript tail by byte
    offset, the control file, the task output files and the loop guard, and it outputs no content. The
    test plants a string in a message body and asserts it appears in no output, with a positive
    control that plants it in an allowlisted field and asserts that it does appear. It is e2e against
    a copied transcript. The same adapter reads sessions on zai, dashscope and deepseek, because they
    run inside claude-code.
15. **A3. `agents/codex/Observe.ps1`** (lifecycle H4; NOW). It reads the rollout file, using the
    three-payload-type allowlist from metrics 2.5. Two measured facts become rules:
    - SessionStart fires only on the first turn, so a thread with no turn yet has no
      session-started.
    - Stop does not fire on a failed or interrupted turn, so the turn after a failure ends as
      unknown, never as idle.

    Its fixture is built from the one real rollout.
16. **A4. Move the agents' reads out of core** (PROJ). The control-file readers for stores X1-X3 and
    W8 move from `core/Identity.ps1` and `core/Projection.ps1` into `agents/claude-code/` and
    `agents/codex/`, behind the port. The ledgers come first: `planning/ledger/agent-claude-code.md`
    and `agent-codex.md`. E1's allowlist counts shrink in the same PR, and a projection parity run
    shows no difference.

E. Resume bindings as the single source of truth

17. **R1. The binding in the session record** (PROJ). This is an in-place v1 edit (engine-settings
    5), so it must merge before step 3.8. It is the design's E8, extended to lifecycle 3's list. The record stores the following, each owned by `engine` in
    `core/ownership.json`:
    - `engine`: `{ harness, provider, model, profile, requested, resolvedAt, provenance }`;
    - the existing `projectCwd`;
    - `resume`: `{ argv, envRefs }`.

    `modelObserved` is owned by `agent` and derived when read: from W8 `model`, then from the model on
    the newest transcript message. Until Horde's first spawn, the rows read W3/W4 `exe` as the
    harness, and read provider and model as unknown, never as a default. The schema and ownership rows
    land together, because `test/test-schema-session-record.ps1` couples them.
18. **R2. `horde resume <id> --print`** (PROJ). A read-only command that prints the binding (harness,
    session id, cwd, provider profile, model, argv), each field in tristate form with its provenance.
    `--json` gives the same as data. Any field that is unknown refuses the print, with the reason. Its
    e2e reads a fixture record.
19. **R3. Resume acts from the record, and nothing else computes argv** (SPAWN). This is the design's
    E11:
    - the restore plan's `resume` block is copied from the record, never rebuilt by a host or by the
      Lua;
    - `horde resume <id>` starts exactly that argv through the launch stub;
    - `--model` and `--reresolve` write a new `engine`, and the old one is kept in `engine.previous`;
    - a removed provider, a missing credential, or a transcript shorter than the recorded length is
      refused with its reason;
    - a request to change the harness is always refused.

    `horde status` shows the recorded model, the observed model, and what the config would resolve
    now. A `/model` change inside the session is shown there as drift and never rebinds the session
    (engine-settings 6). Only an explicit `--model` or `--reresolve` writes a new binding. This is the lifecycle closer's precondition: a goblin is auto-closed only when R2 answers
    every field.

F. Engine settings, Half B: Horde spawns with the resolved engine (SPAWN)

20. **E9. The engine half of `agents/claude-code/Agent.ps1` and `agents/codex/Agent.ps1`.** Each
    adapter builds the argv with the model flag, the provider environment by reference, the scrub
    list, and the resume argv from a recorded engine. Every flag is read off `--help` on this machine.
    For shadowing, each wezfleet spawn is compared with Horde's computed argv, and every difference is
    logged and explained.
21. **E10. The `horde launch` stub, and the engine flags on `horde spawn` and in run specs.** The stub
    resolves the secret itself, so the job file never holds it (test: no fake secret on disk, with a
    control). It scrubs every owned variable of every adapter. For example, a goblin spawned on
    another provider from an orc holding a provider token must inherit none of the orc's variables.
    The stub runs as a child of the anchor, which owns the goblin's job object (lifecycle plan section
    2.2 and step 19; hosts plan, group F), and it hands the anchor the final argv and environment over
    a pipe. It refuses a spawn whose capabilities fail, and writes the metrics consent record. e2e in
    the isolated terminal.
22. **E11. Resume, restore and drift**: step 19. **Switch and adoption**: the fleet runs a real wave
    with goblins on one model and orcs on another, set only through `horde config`, and the PR records
    who used it and what broke.
23. **E4-host. The capability check reads the real host files** (PROJ, after hosts plan steps 1 and
    2). E4's injected host capabilities are replaced by `hosts/<name>/capabilities.json`. `validate` then says,
    per host, whether a warchief whose harness cannot inject messages is valid there. It is valid
    where the host can type text (`text.send: yes`), and invalid elsewhere.

G. The gemini-cli adapter

24. **G1. Install and measure** (INSTALL, after E2). The founder is told first, then
    `npm install -g @google/gemini-cli` runs (0.62.0 when researched). The CLI needs Windows 11 24H2
    or later, and this machine is build 26200. The measurements go into
    `planning/ledger/agent-gemini-cli.md`:
    - `--help`: `-m`, `--resume`, `-p`, `-o`, `--approval-mode`;
    - the session store `~/.gemini/tmp/<project_hash>/chats/`;
    - whether a session id can be set in advance;
    - the hooks, and their `GEMINI_SESSION_ID`;
    - whether a status file exists.

    Then `agents/gemini-cli/agent.json` is written with `vendor: google`, `protocols: [gemini]` and
    `nativeProvider: google`. Its events map AfterAgent to turn-ended and BeforeAgent to turn-started,
    and treats SessionEnd as best-effort. `message-inject` stays `unmeasured` until measured, so
    gemini-cli can run goblins but not orcs or the warchief.
25. **G2. `agents/gemini-cli/Observe.ps1`** (after G1 and A1). The transcript port over its chats
    store, with the same planted-string test and control.
26. **G3. `agents/gemini-cli/Agent.ps1`** (SPAWN). The spawn and resume argv (`--resume <uuid>`),
    measured.

H. Local-only metrics collectors, one per engine (the metrics plan's engine side)

Each collector lives in `agents/<name>/Metrics.ps1` and is a port of three functions:
`Get-<H>MetricsCapability`, `Read-<H>Spans` and `Get-<H>LaunchMetricsEnv`. They read local files only
(metrics 7), and they come after metrics M1 and M2 (the schema and the writer).

27. **M4. claude-code** (NOW, after M2). It reads the transcripts and the `subagents/*.jsonl` files,
    deduplicated by `requestId`. It also covers sessions on zai, dashscope and deepseek. For those, the
    provider comes from the session record's `engine`, never from the model string in the transcript,
    because an Anthropic-format endpoint may echo a Claude model name. That is inferred, not measured,
    and P3 measures it.
28. **M6. codex** (NOW, after M2). It reads the `token_count`, `task_complete` and `turn_context`
    payloads and refuses every other line. The `rate_limits` quota reading is taken as it stands.
29. **G4. gemini-cli** (after G1). Gemini's `GEMINI_TELEMETRY_LOG_PROMPTS` defaults to true. So
    enabling telemetry means the launch stub sets it to false, and the collector refuses any telemetry
    file it did not configure itself. The capability stays `unmeasured` until it has run here once.
30. **Price rows** for zai, dashscope, deepseek and google go into `core/prices/` marked `unverified`,
    with the reason: the vendor pages were blocked on this network. A subscription provider's cost is
    reported as quota, and as a labelled notional amount in USD that is never summed into a USD total
    (metrics 4).

Dropped: metrics M9 (`reconcile`) and the `metered` tier (metrics 7).

## What can start now

In order, one PR each:

1. E0, the ledger.
2. E1, the ratchet. It lands before or after hosts step 5, never alongside it.
3. E2, E3, E4, E5, E6 and E7.
4. P1 and P2 as data and tests.
5. A1, A2 and A3.
6. M4 and M6, once metrics M1 and M2 are in.

## What waits

- **Deferred until a repo needs one**: L2, the per-repo engine file. It may only choose among
  providers defined in the user file, and it may only lower the metrics and admission levels.

- **PROJ**:
  - K1 (the key);
  - A4 (reads out of core);
  - R1 and R2 (the binding and `--print`);
  - E4-host.
- **SPAWN**:
  - P3;
  - R3;
  - E9, E10 and E11;
  - G3.
- **INSTALL**: G1, and after it G2 and G4.
