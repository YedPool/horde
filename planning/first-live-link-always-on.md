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


## Round trip proven, 2026-10-13 05:20-06:01Z

### How the always-on PC got an interactive desktop without anyone at it

- S4U tasks (run whether or not signed in, no stored password) were tried first: wezterm-gui did start in
  session 0, made gui-sock-<pid> and answered `wezterm cli list`, and the hub heard an S4U dial. Abandoned
  for the route below before a session ran; every S4U task, its config folder and processes were removed.
- The route that stands: M enabled Remote Desktop on the always-on PC (firewall rule "Horde M - RDP from
  laptop only", remote 192.168.1.179 only, NLA on), signed Yagdil in once from the laptop and DISCONNECTED;
  the desktop session (session 2, state Disc) keeps running. No auto-logon, no stored password on either
  machine.
- Founder rule: WezTerm runs as admin ("many operations require admin access"). Task "Horde M - WezTerm at
  logon" starts wezterm-gui RunLevel Highest; "Horde node serve (dial laptop hub)" is RunLevel Highest too.

### Three things had to be fixed on the node before a spawn could run

1. Claude's folder-trust dialog. Each spawn stopped at "Is this a project you trust?" and Horde's close
   text then answered it No. Fix: `projects["C:/Users/Yagdil/bin/horde"]` and
   `projects["C:/Users/Yagdil/Documents/Code/imadi"]` got `hasTrustDialogAccepted: true` in
   %USERPROFILE%\.claude.json (backup: .claude.json.before-horde-trust).
2. The bypass-mode warning kept appearing although settings.json already said
   `skipDangerousModePermissionPrompt: true`: the file was INVALID, so Claude skipped all of it -- one hook
   (wf-cmdlog.exe) had `"args": {}` where the laptop has `"args": []`. Fixed to `[]` with node (backup of
   the broken original: settings.json.before-horde-bypass). Do not rewrite these files with Windows
   PowerShell 5.1's ConvertTo-Json: it turns one-item and empty arrays into objects, which is how this
   breaks.
3. The account's usage limit was hit at 05:27Z (reset 05:30Z); the run waited it out.

### The run

| # | Command (hub) | Result |
|---|---------------|--------|
| 17 | `horde session spawn -Node 32c5d8f3-... -Label W -Run 20261013-055000-alwayson -Profile claude -Repo github.com/YedPool/horde -Prompt "<write hostname, UTC time, elevation to C:\Users\Yagdil\horde-spawn-proof.txt>" -Permission bypass -TimeoutSeconds 300` | `DONE session.spawn request 118682ce-... session 46211e51-... pid 15628 procStart 134363426815649205`; pid 15628 is claude in session 2 |
| 18 | read over ssh: C:\Users\Yagdil\horde-spawn-proof.txt | `hostname: DESKTOP-TJQJGTM`, `utc: 2026-10-13T05:31:10.0404876Z`, `elevated: True` |
| 19 | `horde session status -RequestId 118682ce-...` | the same DONE line |
| 20 | `horde session close -SessionId 46211e51-... -TimeoutSeconds 300` | `DONE session.close request af6ce86b-... session 46211e51-...` |
| 21 | `horde hub revoke -Device 32c5d8f3-...` | key refused; a spawn to it: "is not enrolled live, so nothing is sent to it"; the node's next dial: "Connection reset by 192.168.1.179 port 2222"; the listener stopped (no enrolled node left) |
| 22 | node: `horde node rotate-key`; hub: `horde hub enroll -Device 32c5d8f3-... -Key <new> -Address 192.168.1.182`; restart the listener task, then the node's serve task | `heard at 2026-10-13T06:01:02Z` |

UNRESOLVED, recorded not explained: in row 17's run, Horde's typed no-op line and its "Read ...prompt.txt"
line both sat UNSUBMITTED in Claude's input box; the spawn was still reported DONE (mode proven), and the
work ran only after an Enter was sent by hand. Earlier spawns of the same night failed on the dialogs
above, so this is the first spawn that reached the typing step on this node. Needs its own look.

Operational notes:
- After a revoke the listener exits; restart its task after re-enrolling. Its start takes about 40 s
  (a NetTCPIP module-load error is printed and survived each time). The node's serve process must be
  restarted after `node rotate-key`; the running one kept failing to frame until it was.
- The listener task's log was switched from `*>> listen-task.log` (it stopped writing after a restart)
  to a transcript: C:\Users\yedid\.horde\hub\listen-transcript.log.
- `horde nodes` shows the inventory as "partial" (R1 no layout port; W1/W3/W8 no .wezfleet folders;
  X4 no host adapter). That is the read-only fleet inventory, which looks for wezfleet's stores; the
  always-on PC has no wezfleet. It does not affect spawn/close (proven above); it only means the hub
  cannot list sessions on that machine that Horde did not start.

### Undo, every change on the always-on PC
- Tasks: `Unregister-ScheduledTask 'Horde node serve (dial laptop hub)'`, and M's 'Horde M - WezTerm at logon'.
- Claude config: restore %USERPROFILE%\.claude.json.before-horde-trust (loses Claude state written since)
  or delete the two `projects` trust entries; settings.json: keep the `args: []` fix (the backup is the
  broken file).
- Node: `horde hub revoke -Device 32c5d8f3-...` on the hub; delete %USERPROFILE%\.horde and \bin\horde.
- RDP: M's rule "Horde M - RDP from laptop only" and the RDP switch (M's change; M lists it).

## Waiting on the founder

1. DONE 2026-10-13: the elevated listener script (row 9).
2. DONE 2026-10-13: signed in by M over RDP and left disconnected (see above).

## Still to prove (sections 4 to 6 of first-live-link-ov615.md, unchanged)

- `horde session spawn -Node 32c5d8f3-... -Profile claude -Repo github.com/YedPool/horde -Prompt "Reply with the machine name." -Permission bypass -TimeoutSeconds 300`,
  then `horde session status -RequestId <rid>`, then `horde session close -SessionId <sid>`.
- Revoke, once proven: `horde hub revoke -Device 32c5d8f3-...`.

Risk to record: both addresses are DHCP. If either changes, the dial string, the listen address and the
firewall rule go stale. Reserving both addresses in the router removes that.
