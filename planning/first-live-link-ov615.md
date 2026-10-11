# First live link: the hub on this PC, a node on OV615

Mesh v1 (2026-10-11). The steps, in order, that give the founder's work hub (this PC, 192.168.1.182)
its first live ssh link from office device OV615 (192.168.1.156), over the office LAN. Each line is a
command to type; `ADMIN` marks the one that must run in an elevated PowerShell. Everything else runs in
an ordinary PowerShell as the founder's own account. Both machines run a Horde checkout that holds the
mesh v1 branches (mesh/v1-fixes, mesh/v1-listen-address, then mesh/remote-act); `horde` below is that
checkout's `horde.ps1` (`powershell -NoProfile -ExecutionPolicy Bypass -File <checkout>\horde.ps1 ...`).
The whole run, enrolment to close, is rehearsed on one machine over 127.0.0.1 by
`transports/ssh/test/test-mesh-act-local.ps1` (two Horde homes, the real CLI, a fake terminal and harness
on the node's side); what only OV615 can show is the real session in section 5.

The doors this run keeps shut (the founder's rules of 2026-10-11): the link is key-only; every key is
forced to Horde's attach, with no shell, no forwarding and no files; OV615 pins the hub's host key; the
hub listens on 192.168.1.182 only, never a public address, with one firewall rule that admits only
OV615's address on the Private and Domain profiles; revoke is instant and every key expires in a year.

## 0. Before you start

- Both machines on the office LAN, and the LAN's Windows network profile is **Private** (Settings,
  Network, the connection, Network profile type). On a Public profile the hub's rule does not apply,
  and OV615 cannot reach it.
- On the hub: the Windows OpenSSH Server is installed (it is: R16), its `sshd` service stays Disabled
  or Manual and Stopped - `horde listen` runs its own copy and never touches the service.
- On OV615: the Windows OpenSSH Client (`C:\Windows\System32\OpenSSH\ssh.exe`) is present.
- The hub's account name, lowercase, is the user OV615 dials as (here `yedidya`):
  `$env:USERNAME.ToLowerInvariant()` on the hub.

## 1. Keys and pins - strings you carry between the machines

| # | Where | Command | What to carry |
|---|-------|---------|---------------|
| 1 | hub | `horde hub init` | the printed `horde node pin -Hub <hubId> -HostKey "ssh-ed25519 ..."` line, to OV615 |
| 2 | OV615 | `horde node init` | the printed `horde hub enroll -Device <ov615Id> -Key "ssh-ed25519 ..."` line, to the hub |
| 3 | OV615 | `horde node pin -Hub <hubId> -HostKey "ssh-ed25519 ..."` (the line from step 1) | - |
| 4 | hub | `horde hub enroll -Device <ov615Id> -Key "ssh-ed25519 ..." -Address 192.168.1.156` (the line from step 2, plus `-Address`) | - |

Step 4 writes OV615's key, forced to attach, restricted and expiring in a year, and records OV615 in
the hub's register with its last-known address, which is who step 6's firewall rule lets in. Check on
the hub: `Get-Content $env:USERPROFILE\.horde\hub\nodes\<ov615Id>.json` shows the key and the address.

## 2. What OV615 lets the hub start

5. On OV615, the node's policy: `<home>\node\policy.json` (`<home>` is `%USERPROFILE%\.horde` unless
   `HORDE_HOME` says otherwise), plain ASCII:

   ```json
   { "schemaVersion": 1,
     "repos": [ { "repoId": "github.com/YedPool/horde", "path": "C:\\Users\\<you>\\Documents\\Code\\horde" } ],
     "profiles": ["default"] }
   ```

   (`default` stands for a profile OV615's engine configuration defines; the hub may name only profiles
   listed here.)

   No `dailySpawnCap` means the default 32 a day, and no ceiling rule means sessions run with prompts
   bypassed (the founder's decision: not security by limiting power). Lower either in the node's own
   files if wanted.

   For the round trip below, OV615 also needs what any session it starts needs: the harness of that
   profile signed in on OV615 under the founder's account, and a WezTerm window open there, since the
   node starts each session in its own terminal and never opens one.

## 3. Bring the link up

| # | Where | Command | Notes |
|---|-------|---------|-------|
| 6 | hub, **ADMIN** | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<checkout>\horde.ps1" listen -Address 192.168.1.182 -Port 2222` | Prints `firewall rule 'Horde listen <hubId>' made: TCP 192.168.1.182:2222 from 192.168.1.156 (the enrolled nodes' last-known addresses), Private and Domain profiles only`, then `listening on 192.168.1.182:2222 for hub <hubId>`. Leave it running; Ctrl+C stops the listener and removes the rule. Not elevated, it refuses and prints this exact line to run. `-AllowFrom 192.168.1.156` names the node instead of the register. |
| 7 | hub | `horde node serve` | Optional, in a window of its own: the hub's own node. Without it each round still pulls the hub's own node and waits up to 15 s for it to answer before it listens for OV615 (measured on the loopback rehearsal, 2026-10-11). |
| 8 | hub | `horde hub serve -Listen` | Leave it running: each round pulls the hub's own node, takes OV615's dialled link, bound to OV615 only while it stays enrolled, and carries over it every `horde session` request written down for OV615. |
| 9 | OV615 | `horde node serve -Dial yedidya@192.168.1.182:2222/<hubId>` | Leave it running. It dials, answers the hub's round and its requests, and dials again. No `-ReadOnly`: OV615 acts as its own policy (step 5) allows. |

## 4. See it work

| # | Where | Command | Expect |
|---|-------|---------|--------|
| 10 | hub | (watch step 8's window) | `node (dialled) (<ov615Id>): heard, N session(s)` within a round or two (20 s each). UNPROVEN HERE: step 6 runs elevated, so the attach it starts for OV615 is elevated, and it dials step 8's hub pipe, made by a process that is not. The pipe admits this user, and a higher integrity may write to a lower one, so it should connect; if step 8 shows nothing and step 6's window shows attach failing on the pipe, stop step 8 and run it elevated too. |
| 11 | hub | `horde nodes` | OV615 listed, heard, with its sessions, and `[dialled, enrolled until <date>, from 192.168.1.156]`. |

## 5. The session round trip, over OV615's dialled link

Each command below runs on the hub. `horde session` writes the request down (`<home>\hub\acts`), step 8
carries it in the next round OV615 dials into, and the command waits for the answer: up to a round and a
dial (about 40 s) for the link, and for a spawn up to about 160 s more while OV615 starts the session and
reads its mode back (remote plan R19). `-TimeoutSeconds 300` covers both; if it runs out, the request is
still carried, and `horde session status -RequestId <id>` reads its answer later.

| # | Command | Expect |
|---|---------|--------|
| 12 | `horde session spawn -Node <ov615Id> -Label E -Run 20261011-120000-ov615 -Profile default -Repo github.com/YedPool/horde -Prompt "Reply with the machine name." -Permission bypass -TimeoutSeconds 300` | `DONE session.spawn request <rid> session <sid> pid <pid> procStart <t>`. Prompts bypassed: OV615's ceiling, unset, is the top level, so `bypass` is allowed; a level is always named, never defaulted. Step 8's window says `DONE session.spawn request <rid>` under OV615. |
| 13 | `horde session status -RequestId <rid>` | The same DONE line, read from the hub's record of OV615's answer. |
| 14 | (on OV615, the WezTerm window) | The one prompt: a new pane named `E ...` with Remote Control on, which first answered the fixed no-op line, then was told to read its prompt file, and replied with OV615's machine name. |
| 15 | `horde nodes` | OV615 now lists the new session. |
| 16 | `horde session close -SessionId <sid> -TimeoutSeconds 300` | `DONE session.close request <rid2> session <sid>`; the pane on OV615 is gone. |

What R19's acceptance checklist asks of a first live run applies here too: the mode read back is the
level asked, the prompt only after it, the session closed and gone by pid and start time.

## 6. Prove revoke

| # | Where | Command | Expect |
|---|-------|---------|--------|
| 17 | hub | `horde hub revoke -Device <ov615Id>` | Within one round the hub refuses OV615's link (`... is not enrolled: device <ov615Id> was revoked ...`) and step 6's listener stops, saying the register no longer holds OV615. `horde nodes` no longer lists OV615, and a `horde session spawn -Node <ov615Id> ...` is refused before anything is written. Enrol again with a NEW key (`horde node rotate-key` on OV615, then step 4 with its new line): a revoked key is never enrolled again. |

## 7. Stop

- OV615: Ctrl+C in step 9's window.
- Hub: Ctrl+C in step 8's window (and step 7's, if it runs), then in step 6's (it removes the firewall
  rule; `Get-NetFirewallRule -Name "Horde listen <hubId>"` then finds nothing).
- If step 6's process was killed rather than stopped, the rule stays, still only for OV615's address
  and port 2222; the next `horde listen` replaces it by its name, or remove it in an elevated
  PowerShell: `Remove-NetFirewallRule -Name "Horde listen <hubId>"`.
