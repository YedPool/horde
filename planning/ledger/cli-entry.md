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
- source: measured 2026-09-29 on PowerShell 5.1: a ValueFromRemainingArguments param, or any hand-built array, delivers -Json as the literal string "-Json" bound to the first positional parameter
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

### L-017 horde exits 0, 1 or 2, whatever the command does
- source: review of YedPool/horde PR #12, finding 6: a command's `exit 7` made horde exit 7, a bare `exit` made it exit 0, and a program left failed inside a command left horde exiting 0
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
- source: second review of YedPool/horde PR #12, measured 2026-09-29 on PowerShell 5.1: from -File, `-Json:$false` arrives as the tagged "-Json" then the [string] "$false", exactly as `-Json $false` does. Any argument that is the word "$true" or "$false" exits 2 and says the value arrived as text. Not caught, because $args keeps no trace of them: "-Json:false" (arrives as "-Json false") and a bare "-Json:" (arrives as nothing, or swallows the next word)
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
