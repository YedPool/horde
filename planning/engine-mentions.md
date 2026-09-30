# Engine names in the projection, until engines A4 moves them out

The read model still names the two agents whose stores it reads: their control-file readers, the
`--resume` pattern that finds a process by the conversation it resumes, and the agent enum in
`schema/session-view.v1`. The engines plan moves those reads into `agents/<name>/`
(`planning/execution-plan-engines.md` step 13, A4), and its E1 ratchet will then count what is left in
core. Until E1 exists, this list is the ratchet for the projection's own files (review of PR #31,
finding 10): `test/test-projection.ps1` counts every name below in each file it scans, and fails when
a file has more or fewer mentions than listed. When a mention goes, lower its count; A4 empties the
list. A new mention is not added here without a reviewer agreeing to the reason.

A mention is one occurrence of a name, ignoring case. Files not listed must have none.

names: claude, codex

```
path | mentions | why the file still names an engine
core/Projection.ps1 | 49 | the control-file, transcript and pane-sessions readers for the two agents (stores X1-X3, W8), the --resume pattern, and comments citing what those agents' files were measured to hold; A4 moves them
core/Faults.ps1 | 19 | conversation-in-two-processes and orphan-process read claude processes' command lines, and registry-hook-silent counts claude sessions; the checks move with the process readers in A4
core/WezfleetState.ps1 | 5 | comments on Claude's path key and the codex control files the registry sits beside
core/PaneSessions.ps1 | 4 | the pane-sessions files are Claude Code's own (its SessionStart hook writes them)
schema/session-view.v1.json | 2 | the agent enum [claude, codex]; engines K1 and A4 make it the harness name
```
