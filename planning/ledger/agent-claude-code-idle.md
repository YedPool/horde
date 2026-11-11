module: agents/claude-code/Idle.ps1
replaces: the founder's run-complete-handoff hook (user hooks folder, run-complete-handoff.mjs: its count of background launches and their completions), and YedPool/wezfleet lib/Activity.ps1 and lib/CodexStatus.ps1 (activity and idle reads)
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

The reader does not take over either job: the hook still decides when to ask for a handoff, and wezfleet
still reports activity. What follows is every lesson of those two that the idle reader needed, and
what became of it. Found while answering the review of #93 (2026-10-07), whose finding F1 pointed at
the hook's rule.

### L-001 A command the harness moved to the background on its timeout is a launch too
- source: run-complete-handoff.mjs:204-213 "A foreground command that hit its timeout is moved to the background by the harness, and the tool result says so. That is a launch too."
- disposition: comment
- where: agents/claude-code/Idle.ps1 :: "the founder's run-complete-handoff hook already counted the timeout shape"

### L-002 A launch is matched by what the result says, not only by run_in_background on the call
- source: run-complete-handoff.mjs:238-241 "shell jobs started with run_in_background, and foreground commands the harness moved to the background on timeout, do not appear there"
- disposition: comment
- where: agents/claude-code/Idle.ps1 :: "A SHELL task is recognised by its"

### L-003 A notification closes the launch it names, and only a harness-marked one counts
- source: run-complete-handoff.mjs:190-198 "One notification closes one launch"
- disposition: comment
- where: agents/claude-code/Idle.ps1 :: "They finish at a notification the HARNESS marked as one"

### L-004 A resumed subagent (SendMessage) is back in flight and ends in a notification
- source: run-complete-handoff.mjs:221-226 "Resuming a finished subagent with SendMessage puts it back in flight"
- disposition: dropped
- reason: a resumed subagent is a running background agent, which the harness counts in the turn end's pendingBackgroundAgentCount and keeps the control file busy for (design I-05, I-06); the reader holds a session on that count, so a separate SendMessage rule would only repeat it. If the replay of a later review finds one it misses, it becomes a test.

### L-005 Activity read from a file's modification time misread quiet sessions
- source: YedPool/wezfleet lib/Activity.ps1:101-106 "a tool's result is written 0.8-7 s after the call, so mtime cannot tell the reporting call apart from later work"
- disposition: comment
- where: agents/claude-code/Idle.ps1 :: "The age is never the"

### L-006 A status that is only believed for a while cannot say idle
- source: YedPool/wezfleet lib/CodexStatus.ps1:32-75 "Stop does not fire on a failed or interrupted turn" and its 900 s TTL
- disposition: comment
- where: agents/codex/Idle.ps1 :: "The status hook's file is not read"
