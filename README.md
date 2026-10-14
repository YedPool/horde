# Horde

One session-state engine for a fleet of coding agents, with pluggable terminal and layout hosts.

**Status: private, pre-alpha.** Horde is being built as a strangler of two working systems - a
PowerShell fleet orchestrator and a Lua session-restore plugin for WezTerm. Its first module reads
their existing state and writes nothing; responsibilities move across one at a time, each only
after the running fleet has used it for real work. Nothing here replaces anything yet.

## Vocabulary

| Name    | Role                                          | Identifier |
|---------|-----------------------------------------------|------------|
| Thrall  | the Warchief - the one master orchestrator    | `warchief` |
| Orc     | an orchestrator that owns a task end to end   | `orc`      |
| Warg  | a short-lived subsession doing one thing      | `warg`   |
| Horde   | the whole running system                      | `horde`    |

Every warchief keeps one read-only fleet analyst, a warg that measures the fleet and reports only
to its warchief: [planning/roles/fleet-analyst.md](planning/roles/fleet-analyst.md).

## What the founder sees on his phone

The founder reads and answers his horde from the Horde phone app (`surfaces/pwa`, through the relay).
Every message on the way is end-to-end encrypted. **A session must never tell him it cannot reach him
on the phone.** What reaches it:

- **Chat** (`channels/chat`): the Thrall's conversation turns, meaning his own lines and the Thrall's
  answers, shown as they happen. Text is redacted by the conversation port before it leaves the
  machine. He can type a line back from the phone, and it is delivered to the Thrall. So **the
  Thrall's answers in its chat ARE what he reads on the phone.** Answer him there in plain words, as
  you would in the terminal.
- **Decisions** (`channels/decisions`): every open question on the decisions list (`horde decisions
  add`), with his answers sent back signed by his phone. An Orc that needs him asks here.
- **Progress** (`channels/progress`): the fleet's progress log, the analyst's changelog. Work worth
  his attention is written there.

The chat carries the Thrall's conversation only. An Orc or a Warg reaches him through a decisions
question or a progress entry, or through the Thrall. It does not reach him through its own chat.

## License

MIT. See [LICENSE](LICENSE).
