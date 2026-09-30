# Execution plan: engines - which harness, provider and model each session runs on

Agreed 2026-09-30. The order of work that gives Horde an agent side to match its host side: engine
settings (steps E0 to E11), the `agents/<name>/` adapters for claude-code and codex, a gemini-cli
adapter, provider profiles for Z.ai, DashScope and DeepSeek
through the Claude Code harness, a session key that no longer assumes a UUID, the subscription rule,
resume bindings as the single source of truth, and local-only metrics collectors per engine. Its
companion for terminals is `planning/execution-plan-hosts.md`.

**Who builds what, so nothing is built twice.** Several artifacts this plan needs are shared with
sibling plans, and each has exactly one owner:

| artifact | owner | this plan |
|---|---|---|
| the transcript port and the follower: `core/Transcript.ps1`, `agents/claude-code/Transcript.ps1`, `agents/codex/Transcript.ps1`, `core/Observe.ps1` | the lifecycle plan (`planning/execution-plan-lifecycle.md`, PR #29 at `4670619`), steps 7 to 10 | uses them; builds only the gemini-cli adapter to the same port (G2) |
| the anchor and `core/Contain.ps1` | the lifecycle plan, steps 21 and 22 | E10 builds the real launch stub after lifecycle 22 |
| `Get-HordeHome` | the merged Phase 3 plan (`planning/execution-plan-phase-3.md`), step 1 (B1) | E6 uses it |
| `schema/host-capabilities.v1.json`, `hosts/wezterm/capabilities.json`, `hosts/wezterm/HostRead.ps1`, `test/lib/HostReadConformance.ps1` | the merged Phase 3 plan, steps 2 and 3 (B2, B3) | E4 and step 20 read them; the hosts plan extends them |
| the split into a fleet record and a binding record | the remote plan (`planning/execution-plan-remote.md`, PR #32 at `a0cac96`), step R10 | K1 and R1 follow it in one ordered sequence (group C) |
| the permission-ceiling vocabulary and node policy | the remote plan, step R9 | E2 adds the per-harness mapping it needs |
| the stream the metrics collectors read | the lifecycle plan's follower | M4 and M6 consume it (group H) |

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
  through their harness's adapter. Core never names an engine (lifecycle 4). The lifecycle plan builds
  the port and the first two adapters.
- **The stored session record splits** into a fleet record, written only by the hub, and a binding
  record, written only by the node that runs the session, with the owner `node` (remote decision 3).
  `engine` and `resume` belong in the binding record.
- **No environment variable turns metrics on** (metrics 1). **Tokens are counted only from local
  files**: transcripts, rollouts and harness logs. Horde never calls a vendor's usage or billing API.
  `reconcile` and the `metered` tier are dropped (7). **Nothing is backfilled from before consent**
  (8).
- **Windows agents only for now** (hosts decision 1, in the hosts plan).

From the engine-settings design's own "Decisions taken":

1. **There is no environment-variable layer for harness, provider or model** (engine-settings 1).
   The environment carries paths only: `HORDE_HOME`, and `HORDE_CONFIG` for tests.
2. **One home variable, `HORDE_HOME`, defaulting to `%USERPROFILE%\.horde`** (engine-settings 2). The
   Phase 3 plan's `HORDE_ROOT` is superseded, and the merged Phase 3 plan (PR #26) uses `HORDE_HOME`.
3. **The per-repo project engine file (L2) is deferred until a repo needs one** (engine-settings 3).
   When it comes, it may only choose among providers defined in the user file, and it may only lower
   the metrics and admission levels, never raise them. Nothing in Half A reads or writes an L2 file.
4. **Model aliases are pinned to a concrete id at spawn** (engine-settings 4).
5. **The `engine` and resume-binding fields are added by in-place v1 edits** (engine-settings 5).
   That is safe because no writer exists until step 3.8. Once a writer exists, any further change
   needs a v2. Under remote decision 3 they go into the binding record, `schema/session-binding.v1`,
   not into the fleet record.
6. **Resume uses the launched binding** (engine-settings 6). Drift from `/model` is shown in
   `horde status` and never rebinds the session.
7. **Model ids** as agent-engines 10 (engine-settings 7).
8. **Selector ranks follow the design** (engine-settings 8): `parent` outranks `run` plus `role` in
   the same layer.
9. **The admission tuner may raise reserves on its own, but only proposes lowering them**
   (engine-settings 9). A raise follows a reap that happened while the gate was open. It is a live
   (L4) rule that expires after 7 days, capped at the conservative tier plus 1 GB. The lifecycle plan's
   step 20 builds the tuner. This plan gives every rule a `writtenBy` field (E3), so the resolver can
   tell a tuner's rule from a person's (E4).
10. **The pane anchor is a small compiled executable**, following the precedent of `wf-cmdlog.exe`
    (engine-settings 10). The lifecycle plan builds it (step 22).

The decisions change the engine-settings design in five places, and the steps below use the
changed form:

1. The Z.ai provider is named `zai`, not `zhipu`.
2. A credential is `harness-login` or `env`. The design's `os-store` kind is not built, per
   agent-engines 9.
3. **A subscription is recognised from the credential kind, never from a declared field.** A
   provider whose credential is `harness-login` uses the harness's own login, which is the founder's
   subscription, so it is legal only on a harness whose descriptor names that provider as its
   `nativeProvider`. A provider has no `auth` or `vendor` field with which it could describe itself.
4. The config's layers are L0, L1, L3, L4 and L5. L2 is not built until a repo needs one
   (engine-settings 3).
5. The design's config keys grow beyond the binding: `metrics.*` (metrics step M12) and
   `admission.tier` (lifecycle 1). Each key lands in its own PR, but all of them go through the same
   resolver. Every rule carries `writtenBy` (`user`, `cli` or `tuner`), set by the program that
   writes it. The resolver refuses a `tuner` rule that lowers a reserve (engine-settings 9).

## When each step can start

- **NOW**: needs only what is on `main`.
- **CAPS**: waits for the merged Phase 3 plan's step 2 (B2), which settles the shape of
  `schema/host-capabilities.v1.json`.
- **PROJ**: waits until `feature/core-projection` merges with the HostPort contract. That contract
  makes `-Capabilities` mandatory, makes a handle unique per instance, and tags every pid and cwd with
  its namespace. The same branch also carries `schema/session-view.v1` and `core/Projection.ps1`, and
  both still match the UUID pattern: 1 and 2 occurrences, counted on 2026-09-30.
- **SPAWN**: waits for Horde's spawn and launch commands (migration-plan step 3.8, and engine-settings
  Half B).
- **INSTALL**: a tool not yet on this machine. The founder is told before it is installed.
- **FOLLOW**: waits for the lifecycle plan's transcript port and follower (its steps 7 to 10).
- **RECORD**: waits for its turn in the ordered sequence of v1 record edits (group C).

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
  and cited in a comment, as `lib/Agents.ps1` does in wezfleet.
- **One capability vocabulary everywhere**: `yes`, `no`, `declined` or `unverified`, the same four as
  the host port. A capability that has not been measured is `unverified`, and `unverified` counts as
  `no`: it never satisfies a requirement.
- **Engine names stay in their folders (CONTRIBUTING 14, extended by E1).** A fixture that names an
  engine lives only in `agents/<name>/test/`. Suites in `test/` use neutral fixture names, such as
  `harness-a` and `provider-a`, so the port-names ratchet never has to allow a test file.
- **Orc and Warchief context stays big-picture.** In routine use, a command gives an orc or the
  Warchief a distilled summary, and the detail stays on disk to be read on demand. For this plan, the
  Warchief never reads a full `horde config explain` per spawn. It reads one line (`explain --brief`)
  or one field of `explain -Json`, and opens full provenance only when that line shows a problem.
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
   behaviour.

   **The order of edits to `tools/HostNames.ps1` is fixed**, because three plans change it: first E1
   (this step, the `agents/*` ratchet), then the lifecycle plan's step 5, then the hosts plan's step 5
   (the cross-host import). Each rebases on the one before.
3. **E2. `schema/agent-descriptor.v1` and `core/capabilities.json`.** There is one descriptor for each
   of `agents/claude-code/agent.json` and `agents/codex/agent.json`. Each capability is `yes`, `no`,
   `declined` or `unverified`, and each has evidence. The descriptor has more fields than the design
   showed:
   - `nativeProvider` (the subscription rule);
   - `protocols` (the wire-format rule);
   - `sessionIdPattern` (step 12);
   - `ownedEnv` (the scrub list);
   - `events`, a map from the harness's hook names to Horde's four events: session-started,
     turn-started, turn-ended and session-ended;
   - `permissionLevels`, for the remote plan's step R9. The remote plan owns the closed, ordered
     vocabulary of Horde permission levels, landed on its own by remote step R0 as
     `core/permission-levels.json`; E2 waits for R0 and reads the vocabulary from that file. This field maps each level to this harness's own flags:
     for claude-code, a `--permission-mode` value or `--dangerously-skip-permissions`; for codex, its
     approval and sandbox settings. Every level in the vocabulary appears exactly once, either with
     its argv fragment and the evidence that the flag was read off `--help` here, or as
     `inexpressible` with the reason. A node then refuses a level its harness cannot express. It never
     lowers it to the nearest level the harness has, because a silent lowering is a policy change
     nobody asked for.

   `core/capabilities.json` says which port can satisfy each capability: `agent`, `host` or `either`.
   Golden fixtures cover the valid shapes and include one fixture per rejected shape. The schema's
   fixtures use neutral harness names; each real descriptor is checked by a suite in its own
   `agents/<name>/test/`. Tests:
   - a descriptor without evidence fails;
   - a state outside the four is refused, and `unverified` never counts as `yes`;
   - `permissionLevels` missing a level of the vocabulary fails, and so does a level listed twice;
   - a pure `Get-HordePermissionArgs` given an `inexpressible` level refuses with the reason. The
     control gives it an expressible level and gets that level's fragment back. A mutation that
     returns the nearest lower level instead must turn the test red.
4. **E3. `schema/engine-config.v1` and `core/EngineConfig.ps1` (`Test-HordeEngineConfig`).** This is
   the design's schema with the five changes above. The checker enforces three rules:
   - **The wire-format rule.** A profile or rule that pairs a harness with a provider whose protocol
     the harness's descriptor does not list is an error. With today's descriptors, claude-code with
     `google` is refused (only a translating proxy would work), and gemini-cli with anything but
     `google` is refused.
   - **The subscription rule.** A provider whose credential kind is `harness-login` is legal only on
     a harness whose `nativeProvider` is that provider. The subscription is derived from the kind, and
     nothing a config file declares can claim or disclaim it. So Claude Max runs only under
     claude-code, and ChatGPT only under codex.
   - **`writtenBy` on every rule.** `user` for a hand-written rule, `cli` for `horde config set`,
     `tuner` for the admission tuner. The checker refuses a `tuner` rule outside L4, because the tuner
     writes only live rules.
   - **The pinning rule.** A model that names an alias resolves to the concrete id mapped for the
     resolved provider. An alias with no entry for that provider is an error, and the alias's name
     is never passed through to the provider.

   Fixtures come first, one for each finding in the design's list (except the L2 findings, which wait
   with L2), plus one each for the wire-format and subscription rules. A file offered as L2 is refused
   with the reason that the project layer is not built yet. The secret-shaped-value fixture asserts
   that the value appears nowhere in the output. The subscription rule's fixture pairs a
   `harness-login` provider with a harness whose `nativeProvider` is another provider. Every finding is
   mutation-tested. All fixtures here use neutral names.
5. **E4. `core/EngineResolve.ps1`** (CAPS, after E2). A pure function. It takes the layers (already parsed) and a
   target, and returns one tristate answer per field, with its provenance. Tests cover:
   - the full precedence table;
   - that fields are resolved independently;
   - one test per specificity comparison, including `{parent}` beating `{run, role}`;
   - a tie between rules that disagree is unknown and names both rule ids, while a tie between rules
     that agree resolves;
   - alias resolution, and the error for a missing alias;
   - role aliases in selectors;
   - an alias resolves to its concrete id, and the answer records both (pinned at spawn);
   - a `tuner` rule that lowers a reserve is refused, and one that raises it resolves.

   The capability check runs against the harness, against the provider's `lacks`, and against the
   host. Host capabilities come in as data, in the shape the merged Phase 3 plan's step 2 settles for
   `schema/host-capabilities.v1.json`. So this step starts after that schema merges, and not before:
   a shape guessed now would be a second definition. Reading the real
   `hosts/<name>/capabilities.json` files is step 20.
6. **E5. `core/Secrets.ps1`.** It resolves `env` and `harness-login` references, and nothing else. It
   answers `set`, `missing` or `unknown (why)`, and it gives the value only to the launch stub. The
   test finds no fake secret in any output, with a positive control.
7. **E6. `horde config validate | explain | get`.** It uses the merged Phase 3 plan's
   `Get-HordeHome` (its step 1) and defines none of its own. `explain` has three forms: full
   provenance, `--brief` (one line: profile, harness, provider, pinned model, and `ok` or the first
   problem), and `-Json`. Each command gets an e2e scenario that drives the real `horde` with
   `HORDE_HOME` set to a temporary folder:
   - a config that validates clean;
   - a tie;
   - a warchief on a neutral harness whose descriptor says `delivery-receipt: unverified`;
   - a `harness-login` provider paired with a harness that is not its native one;
   - an explain whose provenance is asserted field by field, and a `--brief` line asserted whole;
   - the environment test, moved here from E4 because only a real process has a real environment:
     `horde` runs with every plausible spelling set (`HORDE_MODEL`, `HORDE_ENGINE`, `HORDE_PROVIDER`,
     `HORDE_HARNESS`), and the resolved engine does not move. The control makes the same change in
     the user file and sees it move.
8. **E7. `horde config set | unset`.** It writes with a unique temporary name and an atomic replace,
   and it compares and swaps on the L4 `revision`. The tests come first:
   - a set that would introduce a tie is refused and leaves the file byte-identical;
   - three concurrent writers lose no rule;
   - `--scope project` is refused while L2 is deferred;
   - every rule it writes carries `writtenBy: cli`.

   The e2e scenario runs set, explain, unset, explain.

**Adoption for Half A.** For one working day, every spawn the Warchief makes through wezfleet
records the `explain --brief` line beside what wezfleet actually launched, in a log on disk. The
Warchief reads the day's disagreements as a summary, and opens full provenance only for those.

B. Provider profiles through the Claude Code harness (NOW for data and checks; SPAWN for use)

9. **P1. `agents/claude-code/providers.example.json`.** Provider profiles for `zai`, `dashscope` and
   `deepseek`. Each has `protocol: anthropic-messages`, an `env` credential reference (never
   `harness-login`, which the subscription rule refuses on a provider that is not native), a `models` allowlist, and `lacks`. The file is an example the founder copies into L1;
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
    - `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`;
    - `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU,FABLE}_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL`;
    - `API_TIMEOUT_MS`, `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS`;
    - `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `CLAUDE_CODE_EFFORT_LEVEL`.

    Six rules. Each has a test that can fail, and a mutation that removes the rule must turn its test
    red. The tests run a pure function that builds the environment plan for a binding from a parent
    environment and the settings files it is given. All the fixtures are in `agents/claude-code/test/`.
    - **A provider that is not native must have its token set.** Claude Code uses the subscription
      login whenever `ANTHROPIC_BASE_URL` is set without `ANTHROPIC_AUTH_TOKEN`, so the founder's
      Claude Max credential would go to a third-party endpoint. The adapter refuses that combination.
      It is the subscription rule enforced where the environment is built. This step owns the
      refusal and its test. With a `zai` binding whose token reference resolves to nothing, the
      function refuses:
      the reason names the missing reference, and the plan sets no variables, `ANTHROPIC_BASE_URL`
      included. The control: the same binding
      with a fake token set gives a plan with both variables set, and the fake value appears in no
      output. E10's scrub test later runs the same case end to end.
    - **Every model alias is pinned to the provider's model.** All four
      `ANTHROPIC_DEFAULT_*_MODEL` variables and `CLAUDE_CODE_SUBAGENT_MODEL` are set, so no subagent
      asks a third-party endpoint for a Claude model name.
    - **An endpoint that rejects Claude Code's beta fields gets
      `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`.** Claude Code does not retry a 400 on those fields.
    - **An inherited `ANTHROPIC_API_KEY` never reaches a child.** Test: the parent environment holds a
      fake key, and the plan for any binding, native or not, does not carry it; the fake value is in no
      output. Control: when the binding's own reference names that key, the plan does carry it.
    - **A settings file cannot put back what the scrub removed.** Claude Code applies a settings
      file's `env` entries and its `apiKeyHelper` inside the harness, after the launch stub's scrub.
      The adapter reads, without writing, the user, project and local settings files the session
      would load. It refuses a binding when any of them sets a variable the adapter owns, or sets
      `apiKeyHelper`, and it names the file and the key. Tests: a fixture whose `env` sets
      `ANTHROPIC_BASE_URL` is refused; a fixture with `apiKeyHelper` is refused. Control: a settings
      file with neither passes. Whether a spawn-time flag could override those entries instead is not
      measured, so until it is, the refusal stands.
    - **Goblins keep the memory reaper.** `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP` is removed from
      every goblin's environment (lifecycle decision 5, which keeps the reaper on). Test: the parent
      environment sets it to 1, and the goblin's plan does not carry it. Control: for a role other than
      goblin the variable is reported, not removed, so the test can see the difference.

    DeepSeek's recipe adds the `[1m]` model suffix and `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, because an
    unrecognised model id is assumed to have a 200K context. Tests run on data and on that pure
    function. Applying the plan to a real process waits for E10.
11. **P3. Measure each provider once** (SPAWN). For each of zai, dashscope and deepseek, one session
    runs in the isolated terminal with the cheapest prompt and the founder's key, read by reference.
    Each measurement goes into `planning/ledger/agent-claude-code.md`: the endpoint answered, which
    model id the transcript recorded, whether `cache_control` was billed as uncached, and whether the
    beta fields drew a 400. Only a measured capability moves from `unverified` to `yes` or `no`.

C. The session record: the key, in one ordered sequence of v1 edits (PROJ, RECORD)

Four PRs, across three plans, edit the stored session record in place on v1. Each edit is safe only
while no writer exists (engine-settings 5). So **all four land as one ordered sequence, each rebased on
the one before, and the whole sequence merges before Phase 3 step 3.8** ships the first writer. After
that, any change is a v2. The order:

1. **Remote R10, the split** (the remote plan, "The fleet record and the binding record"). It comes
   first, because the other three add fields to the records it creates. `schema/session-record.v1`
   stays the fleet record, written only by the hub. A new `schema/session-binding.v1` is the binding
   record, written only by the node that runs the session, and `core/ownership.json` gains the owner
   `node`.
2. **Engines K1, the key** (step 12, below).
3. **Engines R1, the binding fields** (step 14, below).
4. **Lifecycle 24, the lifecycle plan's remaining binding rows** (its "The binding in the record").

A small follow-up PR adds this sequence to the merged Phase 3 plan as a gate on step 3.8, and the
lifecycle plan is moving its step 24 before 3.8.

12. **K1. The key is (harness, id)** (PROJ, RECORD: second in the sequence).
    - Both records, `schema/session-record.v1` (the fleet record) and `schema/session-binding.v1` (the
      binding record), gain a required `harness` as part of the key.
    - `sessionId` loosens to plain id text: `^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`.
    - The per-harness shape moves to `sessionIdPattern` in `agents/<name>/agent.json`, and the checker
      applies it. `core/Schema.ps1` has no conditional keywords, so the schema cannot.
    - `parent` gains a `parentHarness`.
    - `schema/restore-plan.v1`'s `sessionId` and `parent` change the same way, and its `resume.kind`
      enum becomes the harness name.
    - `schema/pane-session.v1` is not touched, because it documents wezfleet's format exactly.
    - Only harnesses whose pattern is a UUID compare ids ignoring case.

    Tests, all with neutral names in `test/`:
    - an `ses_...` id is accepted under a fixture harness whose pattern allows it, and refused under a
      fixture harness whose pattern is a UUID;
    - the same id under two harnesses gives two records;
    - `core/Identity.ps1`'s refusal of a malformed id still fires.

    `agents/claude-code/test/` holds the one check that names an engine: the real claude-code
    descriptor's pattern refuses an `ses_...` id. The step waits for PROJ because
    `schema/session-view.v1` and `core/Projection.ps1` on the projection branch match the UUID pattern.

D. The `agents/<name>/` adapters for claude-code and codex

The transcript port, the follower and the transcript adapters for claude-code and codex belong to the
lifecycle plan: `core/Transcript.ps1` and `schema/observe-event.v1` (its step 7),
`agents/claude-code/Transcript.ps1` (8), `agents/codex/Transcript.ps1` (9) and `core/Observe.ps1`
(10). This plan does not build them. What this plan adds to each adapter folder is the descriptor
(E2), the engine half (E9), the provider environment (P2), and the move below.

13. **A4. Move the agents' control-file reads out of core** (PROJ). The readers for stores X1-X3 and
    W8 move from `core/Identity.ps1` and `core/Projection.ps1` into `agents/claude-code/` and
    `agents/codex/`, beside the lifecycle plan's `Transcript.ps1` files. The ledgers come first, as
    the halves the lifecycle plan does not write: the control-file half of
    `planning/ledger/agent-claude-code.md`, and of `agent-codex.md`. E1's allowlist counts shrink in
    the same PR, and a projection parity run shows no difference.

E. Resume bindings as the single source of truth

14. **R1. The binding fields in the binding record** (PROJ, RECORD: third in the sequence). This is
    the design's E8, extended to lifecycle 3's list, and placed where remote decision 3 puts it. In
    `schema/session-binding.v1`, each field owned by `node` in `core/ownership.json`:
    - `engine`: `{ harness, provider, model, profile, requested, resolvedAt, provenance }`;
    - `resume`: `{ argv, envRefs }`;
    - `projectCwd`, which the remote split has already moved there.

    Nothing of this goes into the fleet record. `modelObserved` is owned by `agent` and derived when
    read: from W8 `model`, then from the model on the newest transcript message. Until Horde's first
    spawn, the rows read W3/W4 `exe` as the harness, and read provider and model as unknown, never as a
    default. The schema edit and the ownership rows land together. The remote split's twin test (a
    binding-record schema computed from the `node`-owned rows) fails if they drift, and so does a
    `node` row appearing in the fleet schema.
15. **R2. Printing the binding** (PROJ). The command is the lifecycle plan's `horde goblin show`
    (its step 25), not a second command here. This step supplies its engine half: harness, provider
    profile, pinned model and argv, each in tristate form with provenance, and `-Json`. Any field
    that is unknown refuses the whole answer, with the reason. Its test reads a fixture binding record
    with neutral names.
16. **R3. Resume acts from the record, and nothing else computes argv** (SPAWN). This is the design's
    E11, applied inside the lifecycle plan's `horde resume` (its step 25):
    - the restore plan's `resume` block is copied from the binding record, never rebuilt by a host or
      by the Lua;
    - resume starts exactly that argv through the anchor and the launch stub;
    - `--model` and `--reresolve` write a new `engine`, and the old one is kept in `engine.previous`;
    - a removed provider or a missing credential is refused with its reason, alongside the lifecycle
      plan's own refusals (a shorter transcript, a harness change);
    - a `/model` change inside the session is shown in `horde status` as drift and never rebinds the
      session (engine-settings 6). Only an explicit `--model` or `--reresolve` writes a new binding.

    `horde status` shows three answers side by side: the recorded model, the observed model, and what
    the config would resolve now.

F. Engine settings, Half B: Horde spawns with the resolved engine (SPAWN)

17. **E9. The engine half of `agents/claude-code/Agent.ps1` and `agents/codex/Agent.ps1`.** Each
    adapter builds the argv with the model flag, the permission flags from `permissionLevels`, the
    provider environment by reference, the scrub list, and the resume argv from a recorded binding.
    Every flag is read off `--help` on this machine. For shadowing, each wezfleet spawn is compared
    with Horde's computed argv, and every difference is logged and explained.
18. **E10. The `horde launch` stub, and the engine flags on `horde spawn` and in run specs** (after
    the lifecycle plan's step 22). The lifecycle plan builds the anchor first, against a stand-in
    child. This step then builds the real launch stub that the anchor runs as its child. The stub:
    - resolves the secret itself, so the job file never holds it (test: no fake secret on disk, with
      a control);
    - scrubs every owned variable of every adapter, so a goblin spawned on another provider from an
      orc holding a provider token inherits none of the orc's variables (test, end to end, including
      P2's missing-token refusal);
    - hands the anchor the final argv and environment over a pipe;
    - refuses a spawn whose capabilities fail;
    - writes the metrics consent record.

    e2e in the isolated terminal, with the cheapest prompt that proves the point.
19. **E11. Switch and adoption.** Resume and drift are step 16. The fleet runs a real wave with
    goblins on one model and orcs on another, set only through `horde config`, and the PR records who
    used it and what broke.
20. **E4-host. The capability check reads the real host files** (PROJ; after the merged Phase 3 plan's
    steps 2 and 3, and the hosts plan's step 1). E4's injected host capabilities are replaced by
    `hosts/<name>/capabilities.json`, read through the same loader the hosts plan's step 2 fixes.
    `validate` then says, per host, whether a warchief whose harness cannot inject messages is valid
    there: valid where the host can type text (`text.send: yes`), invalid elsewhere.

G. The gemini-cli adapter

21. **G1. Install and measure** (INSTALL, after E2). The founder is told first, then
    `npm install -g @google/gemini-cli` runs (0.62.0 when researched). The CLI needs Windows 11 24H2
    or later, and this machine is build 26200. The measurements go into
    `planning/ledger/agent-gemini-cli.md`:
    - `--help`: `-m`, `--resume`, `-p`, `-o`, `--approval-mode` (the last also feeds
      `permissionLevels`);
    - the session store `~/.gemini/tmp/<project_hash>/chats/`;
    - whether a session id can be set in advance;
    - the hooks, and their `GEMINI_SESSION_ID`;
    - whether a status file exists.

    Then `agents/gemini-cli/agent.json` is written with `protocols: [gemini]` and
    `nativeProvider: google`. Its events map AfterAgent to turn-ended and BeforeAgent to
    turn-started, and treat SessionEnd as best-effort. `message-inject` stays `unverified` until it is
    measured, so gemini-cli can run goblins but not orcs or the warchief.
22. **G2. `agents/gemini-cli/Transcript.ps1`** (INSTALL and FOLLOW: after G1 and the lifecycle plan's
    step 7). An adapter to the lifecycle plan's transcript port, over the chats store. It passes the
    port's own conformance tests and the planted-string test with its control.
23. **G3. `agents/gemini-cli/Agent.ps1`** (SPAWN). The spawn and resume argv (`--resume <uuid>`),
    measured.

H. Local-only metrics collectors, one per engine (the metrics plan's engine side)

Each collector lives in `agents/<name>/Metrics.ps1` and is a port of three functions:
`Get-<H>MetricsCapability`, `Read-<H>Spans` and `Get-<H>LaunchMetricsEnv`. They read local sources
only (metrics 7). **They consume the follower's stream** (the lifecycle plan's steps 7 to 11); they do
not read transcripts themselves. The one exception is backfill: a span the follower never saw may be
read from its transcript directly, and only when that span has a consent record (metrics 8, no
backfill from before consent). A test proves that backfill is refused without one.

24. **M4. claude-code** (after metrics M1 and M2, and FOLLOW). Spans from the follower's events for
    the transcripts and the `subagents/*.jsonl` files, deduplicated by `requestId`. It also covers
    sessions on zai, dashscope and deepseek. For those, the provider comes from the binding record's
    `engine`, never from the model string in the transcript, because an Anthropic-format endpoint may
    echo a Claude model name. That is inferred, not measured, and P3 measures it.
25. **M6. codex** (after metrics M1 and M2, and FOLLOW). Spans from the follower's events for the
    `token_count`, `task_complete` and `turn_context` payloads. Cumulative tokens are a
    `usage.snapshot`, never summed. The `rate_limits` quota reading is taken as it stands.
26. **G4. gemini-cli** (after G1 and G2). Gemini's `GEMINI_TELEMETRY_LOG_PROMPTS` defaults to true.
    So when telemetry is enabled, the launch stub sets it to false, and the collector refuses any
    telemetry file it did not configure itself. The capability stays `unverified` until it has run
    here once.
27. **Price rows** for zai, dashscope, deepseek and google go into `core/prices/`, marked
    `unverified` with the reason: the vendor pages were blocked on this network. A subscription
    provider's cost is reported as quota, and as a labelled notional amount in USD that is never summed
    into a USD total (metrics 4).

Dropped: metrics M9 (`reconcile`) and the `metered` tier (metrics 7).

## What can start now

In order, one PR each:

1. E0, the ledger.
2. E1, the ratchet: first in the fixed order of `tools/HostNames.ps1` edits (E1, then lifecycle 5,
   then hosts 5).
3. E2, E3, E5 and E7.
4. P1 and P2, as data and tests.

## What waits

- **Deferred until a repo needs one**: L2, the per-repo engine file. It may only choose among
  providers defined in the user file, and it may only lower the metrics and admission levels.
- **CAPS** (the merged Phase 3 plan's step 2): E4, and after it E6.
- **PROJ and RECORD**, in the sequence of group C, all before step 3.8: K1 after remote R10, then R1,
  then lifecycle 24.
- **PROJ**:
  - A4 (reads out of core);
  - R2;
  - E4-host.
- **FOLLOW**: M4 and M6 (also after metrics M1 and M2), and G2.
- **SPAWN**:
  - P3;
  - R3;
  - E9, E10 (after lifecycle 22) and E11;
  - G3.
- **INSTALL**: G1, and after it G2 and G4.
