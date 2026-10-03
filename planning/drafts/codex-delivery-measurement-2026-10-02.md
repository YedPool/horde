# Codex: delivery into a running session, and its receipt (measured 2026-10-02)

Asked by the coordinator to unblock codex orcs: the engines resolver (step E4) refused them because
`delivery-receipt` was `unverified` in `agents/codex/agent.json`. No plan step measured it; this is
that measurement. It moves `message-inject` and `delivery-receipt` to `yes` for codex 0.159.2.

## Setup

- Codex CLI 0.159.2, before and after (frozen; update checks off, and the driver refused to type while
  any menu showed - horde #41). Model as configured (gpt-5.5), reasoning effort low.
- An isolated `CODEX_HOME` made for the run: `auth.json` copied in and deleted after, a minimal
  `config.toml` (the configured model, `[windows] sandbox`, trust for the work folder), and test
  hooks of our own for UserPromptSubmit and Stop that append their stdin to a log.
- An isolated WezTerm instance (Horde's own isolation harness, pinned by `WEZTERM_UNIX_SOCKET`,
  `--skip-config`), torn down after: stopped, nothing survived, socket removed.
- The real profile, checked after: `~/.codex/config.toml` byte-identical (SHA-256), `~/.codex/sessions`
  file count unchanged (4 before, 4 after).

## What was delivered, and what came back

| step | how | receipt in the rollout | hook |
|---|---|---|---|
| ALPHA | typed into the pane, Enter | user message line 2.27 s after Enter (includes creating the rollout, the first prompt) | UserPromptSubmit with the prompt text |
| BRAVO | typed into the running, idle session | 2.13 s after Enter | UserPromptSubmit with the prompt text |
| CHARLIE | `codex queue --thread <id> --message <text>` from outside the pane | 1.66 s after the command started; the command exited 0 and printed "Queued message <id> for thread <id>"; the running session started a turn on it | UserPromptSubmit with the prompt text |
| DELTA | typed, never submitted (the control) | none within 10 s | none |

Each delivered message was answered (the assistant replied with the requested word) and its turn
ended with `task_complete` and the Stop hook.

## Verdict

- `message-inject: yes` - `codex queue` delivers into a running interactive session. Typing into the
  terminal also does, which is the host's `text.send`.
- `delivery-receipt: yes` - the rollout records every submitted message as a `response_item` user
  message carrying its text, within about 2 s, and the UserPromptSubmit hook carries the same text
  about 0.1 s earlier. Unsubmitted text leaves no receipt.

Not measured: `codex queue` into a session that is busy mid-turn (queued for the next turn, or
refused), and the queue on a session another program started. Those decide how a receipt should be
waited for, not whether one exists.

## Cost

Four model calls in all: three turns in the measuring run (ALPHA, BRAVO, CHARLIE), and one turn in an
earlier run whose driver failed after its first prompt and tore the session down mid-turn. A first run
before that submitted nothing (its prompt was typed before the composer was live): no call.
