# Ranks: Thrall, Orc, Warg, and the agent that is none of them

Four words, each meaning one thing. A wrong word in a brief, a status card, a ledger reason or code
corrupts the measurement that decides which kind of helper to use, so the words are decided by
records, not by habit.

## The three ranks (founder, 2026-10-11)

- **Thrall**: the war chief. One per horde (work, personal). Over everything.
- **Orc**: owns one area of operation, a lane (the installer, voice, the decisions page, ...). An Orc is a
  session of its own with a seat in the fleet.
- **Warg**: a subsession of an Orc. Its own session, in its own terminal pane, started by `wezspawn` under
  an Orc. It has a session id of its own and a parent.

## The agent (founder, 2026-10-21)

An **agent** is a helper launched INSIDE a session with the Agent tool. It has no window and no session of
its own, and it returns its result to the session that launched it (its parent). **An agent is never a
Warg**, and a Warg is never an agent. "A warg or an agent" is a real choice with real costs on both sides,
so say which one was launched.

| | Agent | Warg |
|---|---|---|
| Launched by | the Agent tool, inside a session | `wezspawn`, by an Orc |
| Window or pane | none | its own pane |
| Session id | none; named by the harness's agent id | its own |
| Ends | when it returns to its parent | when its session ends |
| Recorded by | the work-unit hook, at the harness's SubagentStart and SubagentStop | `wezspawn` at spawn, the work-unit hook at session end |

## Where it is decided, mechanically

- **Session rank.** A session's rank is `thrall`, `orc` or `warg`: the `kind` field of its registry record
  (written by `wezspawn` and the seats), read into `session.rank` in fleet.db when the session is new
  (`planning/fleet-db-design.md`, "The registry's kind"). A reader that wants to know what a session is reads
  `kind`. It does not read the session's label, its name, its folder or the words in its brief. A record with
  no `kind` is read by its older `role`, and an old record with neither stays unknown rather than guessed.
- **Delegated work.** Every agent and every Warg is one row of the `work_unit` table in fleet.db, written
  only through `horde work start` and `horde work end`:
  - an agent: kind `agent`, the parent session, the harness's agent id exactly as given (the id in the
    subagent transcript's file name), the model, the work type, the domain (the parent Orc's lane) and the
    task;
  - a Warg: kind `warg`, its own session id, its parent session and its Orc.
- **The task** is the first `T-NNNN` on the first line of the brief. No task there means the unit is
  recorded `no_task` and is counted.
- **The work type** is one of `build`, `review`, `verify`, `research`, `mechanical`, `monitor`, `other`. It is
  set by an explicit `work: <type>` line among the first three lines of an agent's brief, and otherwise it is
  `other` (Explore and Plan agents are `research`). It is never guessed from the brief's words.
- **Tokens and cost** are not in fleet.db. The fleet meter keeps them in its own database and joins on the
  agent id (an agent) or the session id (a Warg), read-only.

## The hook

`hooks/horde-work-unit.mjs` handles SubagentStart, SubagentStop and SessionEnd. It is never allowed to block
or slow a session: it exits 0 on every path, prints nothing, bounds every wait, and writes a failure as one
line in its log. Its entries go in the user's settings; the repository does not install them.

## Words to use

- Say "agent" (or "helper") for an Agent-tool helper. Say "Warg" only for a separate session in its own pane.
- Do not call an Orc's subsession a "worker session" or a "sub-orc".
