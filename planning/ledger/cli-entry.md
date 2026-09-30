module: cli/entry
replaces: YedPool/wezfleet wezfleet.ps1 (param block and dispatch switch), lib/Commands.ps1 (command table and generated help)
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

## What each source held

- comments: lib/Commands.ps1:1-21 names the whole bug class and what was deliberately not done.
- history: a6d6ff1 (2026-09-11) is the fix and carries the measurement; 80aa026 (2026-09-03) is a
  help text that described commands as they used to be.
- pull requests: none. `gh api repos/YedPool/wezfleet/commits/a6d6ff1/pulls` returns no pull request;
  the command-table work was committed to main directly.
- docs: planning/wezfleet-v2-architecture.md:800, "the class of silent wiring bug that cost four
  separate incidents in one week".
- tests: test_debug/test-cli-surface.ps1, sections "dispatch", "controls" and "every command is
  declared exactly once".

### L-001 A command is declared in exactly one place, and nothing else has to be edited to add one
- source: YedPool/wezfleet lib/Commands.ps1:13 "A COMMAND IS DECLARED ONCE, HERE"
- disposition: test
- where: test/test-cli.ps1 :: "the dispatcher names no command, so adding one never means editing it"

### L-002 Help is generated from the declarations, never written beside them
- source: YedPool/wezfleet a6d6ff1, measured before the fix: 27 commands dispatched while the help advertised 16
- disposition: test
- where: test/test-cli.ps1 :: "help lists every command exactly once"

### L-003 A command that cannot be listed must be said out loud, not silently left out of help
- source: YedPool/wezfleet a6d6ff1, "ELEVEN commands were reachable and INVISIBLE, including census, tree and master"
- disposition: test
- where: test/test-cli.ps1 :: "help names broken command files instead of silently leaving them out"

### L-004 A dispatch branch that can never be reached must be impossible, not merely tested for
- source: YedPool/wezfleet a6d6ff1, a cleanup branch added to the dispatch switch in case form was unreachable
- disposition: test
- where: test/test-cli.ps1 :: "a command whose declared name is not its file name is refused"

### L-005 A flag the command does not declare must fail loudly, never be ignored
- source: YedPool/wezfleet a6d6ff1, a param with no trailing comma left -AllowCloseWindow and -ForceKill undeclared and unreachable for several commits
- disposition: test
- where: test/test-cli.ps1 :: "a flag the command does not take exits 2 with its usage, never silently ignored"

### L-006 A plain script block accepts any flag; only an advanced one refuses an unknown one
- source: measured 2026-09-29 on PowerShell 5.1 while building this module: a plain block handed -Bogus put it in $args and ran
- disposition: test
- where: test/test-cli.ps1 :: "a run block that would silently accept any flag is refused"

### L-007 Forwarded arguments keep their switches only when forwarded from $args
- source: measured 2026-09-29 on PowerShell 5.1: a ValueFromRemainingArguments param, or any hand-built array, delivers -Json as the literal string "-Json" bound to the first positional parameter. $args is also the only thing horde reads its arguments from: the process command line is not read (L-019), and what $args cannot say is refused (L-020, L-021)
- disposition: test
- where: test/test-cli.ps1 :: "the dispatcher has no param block - the one that would strip switches from forwarded arguments"

### L-008 The surface check fails in both directions, and has a control
- source: YedPool/wezfleet a6d6ff1, "a parser that matched nothing would leave both lists empty and both checks green"
- disposition: test
- where: test/test-cli.ps1 :: "CONTROL: the registry really finds the shipped commands"

### L-009 Help describes the commands as they are, not as they were
- source: YedPool/wezfleet 80aa026 (2026-09-03) "The help text described the old kill and the old tell"
- disposition: test
- where: test/test-cli.ps1 :: "help shows a command's summary as its file says it now, not as it was"

### L-010 help and its aliases are the entry point, not commands to look up
- source: YedPool/wezfleet test_debug/test-cli-surface.ps1:217 "help and its aliases are the CLI entry point, not commands people look up"
- disposition: test
- where: test/test-cli.ps1 :: "horde --help prints help"

### L-011 One file per command was deferred for churn, not rejected
- source: YedPool/wezfleet lib/Commands.ps1:17-21, "splitting the file buys organisation, not correctness, and it can follow at any time"
- disposition: comment
- where: cli/Commands.ps1 :: "WHY ONE FILE PER COMMAND, DISCOVERED"

### L-012 Listing commands must not run them
- source: YedPool/wezfleet lib/Commands.ps1 is data only, so dot-sourcing it runs nothing; Horde's command files hold code, which makes the property something to enforce rather than an accident
- disposition: test
- where: test/test-cli.ps1 :: "listing the commands ran none of their code"

### L-013 Exit codes are part of the interface and are stated
- source: YedPool/wezfleet lib/Commands.ps1 tell summary, which states exits 0 to 4 so a caller can act on them
- disposition: test
- where: test/test-cli.ps1 :: "a command that fails exits 1 and says why"

### L-014 A value joined to its parameter with a colon is one argument, where PowerShell kept the colon
- source: review of YedPool/horde PR #12, finding 1, measured 2026-09-29 on PowerShell 5.1: `horde echo-args -Json:$false` gave json=True target=[False], because $args holds the pair as two items ("-Json:" and $false typed; "-Json" and "$false" from -File, with the colon gone). This is the second half of L-007: forwarding from $args keeps a switch a switch, but not its colon value. Typed or in-process the colon survives on the tagged item and the pair is rejoined; from -File it does not, and L-020 says what is done instead
- disposition: test
- where: test/test-cli.ps1 :: "a switch turned off with a colon stays off"

### L-015 help and dispatch find commands through one listing
- source: review of YedPool/horde PR #12, finding 4: `Get-ChildItem -Filter *.ps1` listed zeta.ps1x through its 8.3 short name, and nul.ps1 was listed while `horde nul` said unknown command, because dispatch built a path of its own
- disposition: test
- where: test/test-cli.ps1 :: "dispatch finds every command that help lists"

### L-016 Loading a declaration must run none of it, not only listing it
- source: review of YedPool/horde PR #12, findings 2 and 3: a redirection's target (`@{...} 2> $(...)`), `using module` and `#requires -Modules` all ran code when a file that passed validation was loaded
- disposition: test
- where: test/test-cli.ps1 :: "and loading it runs none of it"

### L-017 horde exits 0, 1 or 2 whatever the command does, short of ending the process itself
- source: review of YedPool/horde PR #12, finding 6: a command's `exit 7` made horde exit 7, a bare `exit` made it exit 0, and a program left failed inside a command left horde exiting 0. Second review, finding 4, measured 2026-09-29: a body calling [Environment]::Exit(5) ends the process and horde exits 5, which no script can prevent; this is carried as a comment in horde.ps1, not claimed. Second review, finding 6: a `powershell -Command` caller gets 0 or 1 unless it appends `; exit $LASTEXITCODE` (unknown command: 1 without, 2 with), also stated there
- disposition: test
- where: test/test-cli.ps1 :: "a command that calls exit makes horde exit 1 and says so"

### L-018 A binding error inside a command's body is the command failing, not the command line
- source: review of YedPool/horde PR #12, finding 5: `Get-ChildItem -NoSuchParam` inside a run block was reported as exit 2 with the usage
- disposition: test
- where: test/test-cli.ps1 :: "a binding error inside a command's body exits 1 without the usage"

### L-019 horde never reads the process command line to recover what -File mode discarded
- source: second review of YedPool/horde PR #12, finding 1 and 2, measured 2026-09-29 on PowerShell 5.1: the reader of [Environment]::GetCommandLineArgs() read the OUTER horde's command line when horde was called from inside a command, and exited 2 "could not match the command line" on `"x"" -Json"`, which powershell.exe splits into two items and .NET into one. It reconstructed information -File mode had already thrown away, so it was removed rather than patched
- disposition: test
- where: test/test-cli.ps1 :: "horde called from inside a command binds its own colon value"

### L-020 A switch value that -File mode turned into a word is refused, never guessed at
- source: second review of YedPool/horde PR #12, measured 2026-09-29 on PowerShell 5.1: from -File, `-Json:$false` arrives as the tagged "-Json" then the [string] "$false", exactly as `-Json $false` does. Any argument that is the word "$true", "$false" or "$null", in any case, exits 2 and says the value arrived as text. "$null" was added by the third review, finding 4, measured 2026-09-30: from -File `-Verb:$null x` bound verb=[$null] target=[x] and `-Json:$null` bound json=True target=[$null], both exit 0. "-Json:false" (arrives as "-Json false") was not caught by this, and is now refused by L-026. Still not caught, because $args keeps no trace of them: a bare "-Json:" (arrives as nothing, or swallows the next word); and a switch's colon value outside L-026's words, such as "-Json:2", "-Json:y" or "-Json:$x", which arrives exactly as the switch and an argument and binds that way (measured 2026-09-30: json=True with target=[2], [y] and [$x], exit 0)
- disposition: test
- where: test/test-cli.ps1 :: "a colon value that arrived as text is refused, never guessed at"

### L-021 "--" has its meaning only where PowerShell parses it, so from a script it is refused
- source: second review of YedPool/horde PR #12, finding 8, measured 2026-09-29 on PowerShell 5.1: typed, "-- -Json" reached horde as the plain word "-Json"; from -File, "--" arrived as an argument and a -Name after it was still a parameter, giving target=[--] json=True unquoted and "parameter name '' is ambiguous" quoted
- disposition: test
- where: test/test-cli.ps1 :: "a double dash from a script is refused, not bound as a value"

### L-022 break and continue in a command body are a command not returning, like exit
- source: second review of YedPool/horde PR #12, finding 3: a body `cmd /c exit 3; break` made horde exit 0, because break travels up the call stack to the nearest loop and skipped horde's completion and $LASTEXITCODE checks. Measured 2026-09-29 on PowerShell 5.1: a do-while in cli/Runner.ps1 takes an unlabelled break or continue, but a labelled break whose label matches nothing passes it and ended horde with exit 0, so horde.ps1 also checks in a finally block
- disposition: test
- where: test/test-cli.ps1 :: "a command that leaves its body with break or continue makes horde exit 1"

### L-023 A command body cannot see or change horde's own variables by name
- source: second review of YedPool/horde PR #12, finding 5: a body that set $state.completed = $true and called `exit 0` made horde exit 0, because it runs in a scope below horde's and the runner's. Measured 2026-09-29 on PowerShell 5.1: before, the body saw 14 of their variables; made private, it sees none by name, though Get-Variable -Scope 1 or 2 still reaches them, so this guards against accidents and not against a body that means to
- disposition: test
- where: test/test-cli.ps1 :: "a command body cannot see horde's own variables"

### L-024 [Environment]::Exit in a command cannot be stopped, and a -Command caller must pass the code on
- source: second review of YedPool/horde PR #12, findings 4 and 6, measured 2026-09-29 on PowerShell 5.1: `[Environment]::Exit(5)` in a body gave horde exit 5; `powershell -Command "& horde.ps1 no-such-command"` exited 1, and 2 only with `; exit $LASTEXITCODE` appended
- disposition: comment
- where: horde.ps1 :: "caller that wants 0, 1 or 2 appends"

### L-025 A test says what it guards, and is mutation-checked against that claim
- source: second review of YedPool/horde PR #12, finding 7: the comment on the "..\Commands" dispatch test said it fails if the name check is removed, and it does not - dispatch compares names with the listing and never builds a path. The comment now says it guards against path joining; a unit test holds the name check in Find-HordeCommand, and fails when that check is removed (mutation-checked 2026-09-29)
- disposition: test
- where: test/test-cli.ps1 :: "a malformed name claims no broken file's findings"

### L-026 A switch followed by the word true or false is refused, since from a script horde cannot tell what it was
- source: third pass on YedPool/horde PR #12, measured 2026-09-29 on PowerShell 5.1: from -File, `horde echo-args -Json:false` arrives as the tagged "-Json" and the untagged word "false", exactly as `-Json false` does, and bound json=True target=[false] with exit 0 - the silent misbinding L-020 recorded as not caught. "false" is also a legitimate positional value, so the word is not refused alone; which parameters are switches is read from the run block's param AST without running it (exact name, alias, unambiguous prefix, and the common switches -Verbose, -Debug, -WhatIf and -Confirm), and a switch immediately followed by true, false, $true, $false, 0, 1, yes, no, on or off, in any case, exits 2. 0, 1, yes, no, on and off were added by the third review, finding 4, measured 2026-09-30: from -File `-Json:0`, `:1`, `:no` and `:off` bound json=True and the word as the target, exit 0, while typed PowerShell refuses every one of them. Typed "-Json false" is refused the same way; typed "-Json:false" is still PowerShell's to refuse; typed "-Json 0" is not refused, since 0 arrives as a number, which only PowerShell's own parsing makes. The shapes still undetectable are listed in L-020
- disposition: test
- where: test/test-cli.ps1 :: "a switch followed by a truth word from a script is refused, never bound as two arguments"

### L-028 A $null argument keeps its place, so the next word never shifts into its parameter
- source: third review of YedPool/horde PR #12, finding 1, measured 2026-09-30 on PowerShell 5.1: horde took its arguments as `$args | Select-Object -Skip 1`, and a pipeline drops a $null item. In-process, `$m = $null; horde echo-args -Verb:$m target` (and `-Verb $m target`) bound verb=[target] target=[] with exit 0, and typed `-Verb:$null x` bound verb=[x]. An index slice of $args keeps the $null and every parameter tag; now all three bind target=[...] verb=[]
- disposition: test
- where: test/test-cli.ps1 :: "a null value keeps its place, and the next word is not shifted into its parameter"

### L-029 A help word that is a parameter's value is that value, not a request for help
- source: third review of YedPool/horde PR #12, finding 2, measured 2026-09-30 on PowerShell 5.1: `horde echo-args -Target:-h`, `-Verb:--help` and `-Verb -h` printed the usage and exited 0 instead of running the command. -?, -h and --help now ask for help only when not the item after a colon-tagged parameter, nor after a parameter the run block's AST says takes a value (exact name, alias or prefix). Such a value is passed on as plain text, because still tagged "-?" is PowerShell's own help switch: `-Verb -?` failed with '"helpTarget" is null', exit 1. From a script "-Json:-h" arrives as "-Json" "-h", the colon gone, and is a request for help
- disposition: test
- where: test/test-cli.ps1 :: "a help word that is a parameter's value is bound, not taken as a request for help"

### L-030 A switch followed by a truth value, not a word, is refused
- source: third review of YedPool/horde PR #12, finding 3, measured 2026-09-30 on PowerShell 5.1: typed, or in-process, `horde echo-args -Json $false` arrives as the tagged "-Json" and a [bool], and bound json=True target=[False] with exit 0 - the switch on, when the caller meant it off. A switch immediately followed by an item that is a [bool] now exits 2 and says to join the value with a colon. A [bool] cannot arrive from -File, where every argument is text; the word forms are L-020 and L-026
- disposition: test
- where: test/test-cli.ps1 :: "a switch followed by a truth value is refused, never turned on"

### L-027 Every user-facing command is driven end to end, in a terminal that is not the user's
- source: CONTRIBUTING.md section 2 "Test end to end, the way a user would", which the migration plan's step 0.9 makes the CLI's gate; and section 3, YedPool/wezfleet tasks/lessons.md 2026-08-16, for why the terminal is a separate WezTerm instance and never a window. test/e2e/e2e-cli.ps1 spawns `powershell -File horde.ps1 --help` and `... version` in panes of an isolated instance and reads their screens; run 2026-09-30: 20 PASS, exit 0
- disposition: test
- where: test/e2e/e2e-cli.ps1 :: "the help pane lists 'horde version' exactly once"
