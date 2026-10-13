# Live link: the founder's laptop as hub, the always-on PC as node

Mesh v1, set up 2026-10-13 on the founder's ruling: "Yes set up the always on PC to be an extension of
our horde under you as thrall". Same procedure and the same doors as first-live-link-ov615.md; this file
records what differs and what is proven so far. STATUS: the dialled link is up and heard, and a spawn
is carried and answered; the spawn itself waits on a console sign-in with WezTerm open on the node.

## The machines (measured 2026-10-13)

| Role | Machine | Address | Account | Network profile |
|------|---------|---------|---------|-----------------|
| hub (Thrall, M) | YEDIDYA, laptop | 192.168.1.179 (Wi-Fi, DHCP) | yedid | Public until the admin step |
| node | DESKTOP-TJQJGTM, the always-on PC | 192.168.1.182 (Wi-Fi 2, DHCP) | Yagdil | Public (outbound only, no change needed) |

Same subnet, gateway 192.168.1.1. The always-on PC could not reach the laptop before the admin step
(ping and TCP 445 both false), as expected for a laptop on a Public profile. Note: OV615's record names
192.168.1.182 as its hub; that was a different setup, and the always-on PC held no Horde home or
checkout on 2026-10-13.

Node prerequisites, measured: PowerShell 5.1.26100, Git, Claude Code (signed in: credentials present),
OpenSSH client, WezTerm installed (not running: nobody signed in at the console at the time).

## Done

| # | Where | Command | Result |
|---|-------|---------|--------|
| 1 | node | clone YedPool/horde to %USERPROFILE%\bin\horde | main at 5f585de (#209) |
| 2 | hub | `horde hub init` | hub b18a795f-898a-40ba-bd48-ec079ad5920f, listener host key made |
| 3 | node | `horde node init` | node 32c5d8f3-0fe1-4ef0-abf8-726219924713, link key made |
| 4 | node | `horde node pin -Hub b18a795f-... -HostKey "ssh-ed25519 ..."` | hub pinned |
| 5 | hub | `horde hub enroll -Device 32c5d8f3-... -Key "ssh-ed25519 ..." -Address 192.168.1.182` | enrolled until 20271013 |
| 6 | node | `%USERPROFILE%\.horde\node\policy.json` | repos github.com/YedPool/imlev (Documents\Code\imadi) and github.com/YedPool/horde (bin\horde); profiles ["claude"] (the claude-code engine's profile, agents/claude-code/engine.json); parsed back |
| 7 | hub | scheduled task "Horde hub serve": `horde hub serve -Listen`, at logon, WakeToRun / AllowStartIfOnBatteries / DontStopIfGoingOnBatteries read back True/False/False | running: "hub listening for dialled links" |
| 8 | node | scheduled task "Horde node serve (dial laptop hub)": `horde node serve -Dial yedid@192.168.1.179:2222/b18a795f-...`, at logon, interactive | registered, Ready; starts when the founder signs in there |

Two snags worth keeping: over ssh, $env:USERDOMAIN is WORKGROUP, so a task principal built from it fails
"No mapping between account names and security IDs"; use
[System.Security.Principal.WindowsIdentity]::GetCurrent().Name. And a JSON policy written through a
PowerShell here-string sent by EncodedCommand lost its doubled backslashes; write it with ConvertTo-Json
and parse it back.

## Proven 2026-10-13 ~03:35Z

| # | Where | What | Result |
|---|-------|------|--------|
| 9 | hub, ADMIN | the founder ran the listener script: Wi-Fi set Private; task "Horde hub listener" (RunLevel Highest) running `horde listen -Address 192.168.1.179 -Port 2222`; rule 'Horde listen b18a795f-...' Domain+Private, remote 192.168.1.182 | 192.168.1.179:2222 LISTENING; node's Test-NetConnection to it True |
| 10 | node | one-link dial | first try: ssh auth worked, then "the far end closed the link; no frame" |
| 11 | hub | serve-task.log said why: "refused a client: process 66180 runs at integrity -1, below this node's 8192; run the hub and node at the same integrity level" | the OV615 section 4 UNPROVEN item, now MEASURED: the elevated listener's attach cannot reach a non-elevated hub serve |
| 12 | hub | FIX: task "Horde hub serve" set to RunLevel Highest (Set-ScheduledTask, accepted without a prompt), restarted | - |
| 13 | node | one-link dial again | "served 1 link(s)", DONE=0 |
| 14 | hub | `horde nodes` | `DESKTOP-TJQJGTM (32c5d8f3-...): heard at 2026-10-13T03:32:12Z, 0 session(s) ... [dialled, enrolled until 20271013, from 192.168.1.182]` |
| 15 | hub | `horde session spawn -Node 32c5d8f3-... -Label W -Run 20261013-033500-alwayson -Profile claude -Repo github.com/YedPool/horde -Prompt "Reply with the machine name." -Permission bypass -TimeoutSeconds 300` | carried over the link and answered by the node: `REFUSED session.spawn request fd676b91-...: this node cannot name its own terminal: no terminal of this user is running with a socket` |
| 16 | hub | `horde session status -RequestId fd676b91-...` | the same REFUSED line, read from the hub's record |

Rule learnt: when `horde listen` runs elevated, `horde hub serve -Listen` must run elevated too. (Run ids
must match `YYYYMMDD-HHMMSS-name`; `20261013-0335-x` is refused by the hub before anything is sent.)

## Waiting on the founder

1. DONE 2026-10-13: the elevated listener script (row 9).
2. The always-on PC: sign in at its console (TeamViewer) and leave a WezTerm window open; the node task
   starts at that sign-in, and the node starts each session in that window.

## Still to prove (sections 4 to 6 of first-live-link-ov615.md, unchanged)

- `horde session spawn -Node 32c5d8f3-... -Profile claude -Repo github.com/YedPool/horde -Prompt "Reply with the machine name." -Permission bypass -TimeoutSeconds 300`,
  then `horde session status -RequestId <rid>`, then `horde session close -SessionId <sid>`.
- Revoke, once proven: `horde hub revoke -Device 32c5d8f3-...`.

Risk to record: both addresses are DHCP. If either changes, the dial string, the listen address and the
firewall rule go stale. Reserving both addresses in the router removes that.
