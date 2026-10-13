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

## License

MIT. See [LICENSE](LICENSE).
