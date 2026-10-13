# Live link: the founder's laptop as hub, the always-on PC as node

Mesh v1, set up 2026-10-13 on the founder's ruling: "Yes set up the always on PC to be an extension of
our horde under you as thrall". Same procedure and the same doors as first-live-link-ov615.md; this file
records what differs and what is proven so far. STATUS: enrolled and serving on both sides; the link is
NOT yet up, and the session round trip is UNPROVEN (section 5).

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

## Waiting on the founder

1. ADMIN, laptop, once: the one-line script RUN-AS-ADMIN-horde-hub-listener.ps1 (kept with the fleet's
   briefs). It sets the home Wi-Fi to Private and registers an elevated logon task running
   `horde listen -Address 192.168.1.179 -Port 2222`, which makes the one firewall rule admitting only
   192.168.1.182.
2. The always-on PC: sign in at its console (TeamViewer) and leave a WezTerm window open; the node task
   starts at that sign-in, and the node starts each session in that window.

## Still to prove (sections 4 to 6 of first-live-link-ov615.md, unchanged)

- `horde nodes` lists DESKTOP-TJQJGTM as dialled and heard.
- `horde session spawn -Node 32c5d8f3-... -Profile claude -Repo github.com/YedPool/horde -Prompt "Reply with the machine name." -Permission bypass -TimeoutSeconds 300`,
  then `horde session status -RequestId <rid>`, then `horde session close -SessionId <sid>`.
- The UNPROVEN item from OV615 section 4 applies unchanged: the elevated listener's attach writing to the
  non-elevated hub serve's pipe.
- Revoke, once proven: `horde hub revoke -Device 32c5d8f3-...`.

Risk to record: both addresses are DHCP. If either changes, the dial string, the listen address and the
firewall rule go stale. Reserving both addresses in the router removes that.
