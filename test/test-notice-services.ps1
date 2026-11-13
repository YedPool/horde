# CAN AN UNATTENDED SERVICE SEND THE FOUNDER NOTICES UNDER ITS OWN REGISTERED NAME - AND NEVER AS A SESSION, AN
# ORC, M OR THE THRALL, NEVER WITHOUT ITS SECRET, NEVER PAST ITS OWN CAP, NEVER A SECRET - WITHOUT THE SESSION RULE
# BECOMING ANY WEAKER?
#
# notices/Services.ps1 and the shipped `horde notify -Service` / `horde notify-service`, in homes of the suite's own.
# It attacks:
#   1. REGISTRATION: only a proven session labelled as a registrar (M) registers; an Orc, an unproven caller and
#      a second registration of one name are refused; names that collide with M, the Thrall, the founder, Horde,
#      an Orc label, a fleet label or a bad shape are refused; the secret file is new, locked, and the store
#      holds a hash, never the secret.
#   2. SENDING: a registered service's notice is "service: <name>"; an unregistered name, a wrong secret, an
#      edited, empty, short or someone else's secret, a revoked service, a secret file open to a broad group,
#      and a name that became a fleet label since it was registered are all refused - the guesses with ONE
#      answer, so nothing says which name exists.
#   3. ITS OWN CAP, apart from every session's; a secret in the text is still the fixed sentence.
#   4. THE SESSION RULE, unchanged: a session labelled "service: ..." is refused, and a session's cap is its own.
#   5. THE SHIPPED COMMANDS end to end.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "notices\Sender.ps1")
. (Join-Path $root "notices\Services.ps1")
. (Join-Path $root "notices\Decide.ps1")
Set-StrictMode -Version Latest

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$work = Join-Path $env:TEMP ("horde-noticesvc-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$realHome = $env:HORDE_HOME

function Sid { param([int]$N) return ("cccccccc-0000-4000-8000-" + $N.ToString("000000000000")) }
function New-Home {
    param([string]$Settings = "")
    $h = Join-Path $work ("home-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    if ($Settings -cne "") { [System.IO.File]::WriteAllText((Join-Path $h "settings\notices.json"), ('{"schemaVersion": 1, "settings": ' + $Settings + '}'), $utf8) }
    return $h
}
function Get-Notices { param([string]$HordeHome) $r = Read-HordeNoticeLog -Store (Join-Path $HordeHome "notices"); if ($r.state -cne "known") { throw $r.reason }; return @($r.value) }
function Proven { param([string]$Sid, [string]$Label) return [pscustomobject]@{ ok = $true; reason = ""; sessionId = $Sid; label = $Label; labelSource = "registry" } }
function Secret-Path { param([string]$Leaf) return (Join-Path $work ("secrets\" + $Leaf + "-" + [guid]::NewGuid().ToString("N") + ".txt")) }
function Register {
    param($Home_, [string]$Name, [string]$File, $By = $null)
    if ($null -eq $By) { $By = Proven (Sid 1) "M" }
    return (Register-HordeNoticeService -Registrar $By -Name $Name -SecretFile $File -HordeHome $Home_ -RegistryRoot $fleetPin.path -FleetLabels $script:labels)
}
function Send {
    param($Home_, [string]$Name, [string]$File, [string]$Text = "the net is green", $Now = $null)
    $who = Resolve-HordeServiceSender -Name $Name -SecretFile $File -HordeHome $Home_ -RegistryRoot $fleetPin.path -FleetLabels $script:labels
    if (-not $who.ok) { return [pscustomobject]@{ outcome = "refused"; reason = $who.reason; notice = $null } }
    return (Submit-HordeNotify -Sender $who -Text $Text -HordeHome $Home_ -PerHour $who.perHour -Now $Now)
}

$script:labels = @()
$now = New-Object DateTime 2026, 10, 16, 3, 10, 0, ([DateTimeKind]::Utc)
$token = "ghp_" + ("A1b2C3d4E5f6G7h8I9j0" * 2)
try {
    Write-Host ""
    Write-Host "--- 1. registration: the founder's side only, once, with a new locked secret file ---" -ForegroundColor Cyan
    $H = New-Home
    $f1 = Secret-Path "net"
    $r = Register $H "postmerge-net" $f1
    Check ($r.ok -and [System.IO.File]::Exists($f1)) ("M registers a service and its secret file is made (" + $r.reason + ")")
    $secret = ([System.IO.File]::ReadAllText($f1)).Trim()
    Check ($secret -cmatch '\A[0-9a-f]{64}\z') "the secret is 32 random bytes in hex"
    Check ((Test-HordeSecretFileOpen -Path $f1) -ceq "") "the secret file is readable by no broad group"
    Check (@((Get-HordeFileAcl -Path $f1).GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])).Count -eq 2) "the secret file has exactly two access entries (this user and SYSTEM), none inherited"
    $store = [System.IO.File]::ReadAllText((Join-Path $H "notices\services.json"))
    Check ((-not $store.Contains($secret)) -and $store.Contains('"hash":"')) "THE STORE HOLDS A HASH, NEVER THE SECRET"
    $r2 = Register $H "postmerge-net" (Secret-Path "again")
    Check (-not $r2.ok -and $r2.reason -like "*registered already*") "a name is registered once"
    $r3 = Register $H "other-service" $f1
    Check (-not $r3.ok -and $r3.reason -like "*exists*" -and ([System.IO.File]::ReadAllText($f1)).Trim() -ceq $secret) "an existing file is never overwritten with a new secret"
    $r4 = Register $H "orc-builder" (Secret-Path "x") (Proven (Sid 2) "E3")
    Check (-not $r4.ok -and $r4.reason -like "*only a session whose fleet label is M*") "AN ORC CANNOT REGISTER A SERVICE"
    $r5 = Register $H "orc-builder" (Secret-Path "x") ([pscustomobject]@{ ok = $false; reason = "x"; sessionId = ""; label = "M" })
    Check (-not $r5.ok -and $r5.reason -like "*not a proven session*") "an unproven caller claiming the label M cannot register"
    $r5b = Register $H "other-service" (Secret-Path "x") (Proven (Sid 3) "service: postmerge-net")
    Check (-not $r5b.ok) "a sender labelled like a service is not a registrar"
    # S3: the agent's own name for a session is no fleet label, so "M" from it registers nothing and revokes nothing.
    $byName = [pscustomobject]@{ ok = $true; reason = ""; sessionId = (Sid 4); label = "M"; labelSource = "agent-name" }
    $noSrc = [pscustomobject]@{ ok = $true; reason = ""; sessionId = (Sid 4); label = "M" }
    Check (-not (Register $H "stray-service" (Secret-Path "x") $byName).ok -and -not (Register $H "stray-service" (Secret-Path "x") $noSrc).ok) "A SESSION NAMED M BY ITSELF (NO FLEET LABEL) CANNOT REGISTER"
    Check (-not (Remove-HordeNoticeService -Registrar $byName -Name "postmerge-net" -HordeHome $H).ok -and (Read-HordeNoticeServices -Store (Join-Path $H "notices")).value.ContainsKey("postmerge-net")) "...nor revoke"
    # N8: not inside the repository.
    # A THROWAWAY "checkout" under the suite's own work folder, never the real one: if the guard fails, the secret lands
    # where the final clean-up removes it, and no later run is poisoned.
    $fakeRepo = Join-Path $work "fake-checkout"
    $inRepo = Join-Path $fakeRepo "keep\net.txt"
    $rr = Register-HordeNoticeService -Registrar (Proven (Sid 1) "M") -Name "repo-service" -SecretFile $inRepo -HordeHome $H -RegistryRoot $fleetPin.path -FleetLabels @() -TestSeamRepoRoot $fakeRepo
    Check (-not $rr.ok -and $rr.reason -like "*inside Horde's own folder*" -and -not (Test-Path $fakeRepo)) "a secret file inside the checkout is refused, and nothing is made there"
    # The seam only ADDS a folder: the real checkout stays guarded when it is set.
    $realIn = Join-Path $root "never-made-by-this-suite\net.txt"
    $rr3 = Register-HordeNoticeService -Registrar (Proven (Sid 1) "M") -Name "repo-service" -SecretFile $realIn -HordeHome $H -RegistryRoot $fleetPin.path -FleetLabels @() -TestSeamRepoRoot $fakeRepo
    Check (-not $rr3.ok -and $rr3.reason -like "*inside Horde's own folder*" -and -not (Test-Path (Split-Path $realIn))) "THE TEST SEAM CANNOT SWITCH OFF THE REAL GUARD: with it set, a file in the real checkout is still refused"
    # The owner rule, with the environment made a parameter (an elevated process owns what it creates as Administrators).
    Check ((Test-HordeSecretFileOwner -Owner "S-1-5-21-1-2-3-1001" -Mine "S-1-5-21-1-2-3-1001" -Elevated $false) -and -not (Test-HordeSecretFileOwner -Owner "S-1-5-21-1-2-3-1002" -Mine "S-1-5-21-1-2-3-1001" -Elevated $true)) "the owner must be the current user; another user never"
    Check ((Test-HordeSecretFileOwner -Owner "S-1-5-32-544" -Mine "S-1-5-21-1-2-3-1001" -Elevated $true) -and -not (Test-HordeSecretFileOwner -Owner "S-1-5-32-544" -Mine "S-1-5-21-1-2-3-1001" -Elevated $false)) "the Administrators group may own it only when the process is elevated"
    # T-0304: a secret file made by an ELEVATED registrar was owned by Administrators, and the non-elevated service then refused it.
    # The owner is part of the security the file is made with, so the registrar's elevation cannot change it.
    $meSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Check ("$((New-HordeSecretFileSecurity).GetOwner([System.Security.Principal.SecurityIdentifier]))" -ceq $meSid) "the security a secret file is made with names the current user as its OWNER (not left to the elevated default)"
    $ownedPath = Join-Path $work "owned-by-me.secret"
    New-HordeLockedSecretFile -Path $ownedPath -Text "x"
    Check ((Get-HordeFileAcl -Path $ownedPath).GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ceq $meSid) "a secret file made by New-HordeLockedSecretFile is owned by the current user"
    Check ((Test-HordeSecretFileOpen -Path $ownedPath) -ceq "") "CONTROL: a file made that way passes the sender's own check"
    $adminWhy = Get-HordeSecretOwnerRefusal -Owner "S-1-5-32-544" -Mine $meSid -Elevated $false -Path "C:\sa.secret" -MineName "PC\me"
    Check ($adminWhy -like "*is owned by S-1-5-32-544*" -and $adminWhy -like '*icacls "C:\sa.secret" /setowner "PC\me"*') "a file owned by Administrators is refused for a non-elevated sender, with the one command that fixes it"
    $otherWhy = Get-HordeSecretOwnerRefusal -Owner "S-1-5-21-1-2-3-1002" -Mine $meSid -Elevated $true -Path "C:\sa.secret" -MineName "PC\me"
    Check ($otherWhy -like "*is owned by S-1-5-21-1-2-3-1002*" -and $otherWhy -like "*/setowner*") "a file owned by another user is refused even for an elevated sender, with the fix text"
    Check ((Get-HordeSecretOwnerRefusal -Owner $meSid -Mine $meSid -Elevated $false -Path "p" -MineName "n") -ceq "" -and (Get-HordeSecretOwnerRefusal -Owner "S-1-5-32-544" -Mine $meSid -Elevated $true -Path "p" -MineName "n") -ceq "") "CONTROL: the current user passes, and Administrators pass only for an elevated sender"
    $rr2 = Register-HordeNoticeService -Registrar (Proven (Sid 1) "M") -Name "repo-service" -SecretFile (Join-Path $work "outside\net.txt") -HordeHome $H -RegistryRoot $fleetPin.path -FleetLabels @() -TestSeamRepoRoot $fakeRepo
    Check ($rr2.ok) "CONTROL: a secret file beside the checkout, not in it, is accepted"
    $null = Remove-HordeNoticeService -Registrar (Proven (Sid 1) "M") -Name "repo-service" -HordeHome $H
    # M1: a name that trips the secret finder would be shown as a bare word.
    foreach ($sk in @("sk-abcdefghijklmnopqrstu", "xoxb-1234567890", "glpat-abcdefghijklmnop")) {
        Check ((Find-HordeSecretKind -Text ("service: " + $sk)) -cne "") ("CONTROL: the finder flags service: " + $sk)
        $rk = Register $H $sk (Secret-Path "sk")
        Check (-not $rk.ok -and $rk.reason -like "*looks like a secret*") ("the name " + $sk + " is refused at registration, so it is never shown as a session (" + $rk.reason + ")")
        Check ((Test-HordeServiceName -Name $sk -RegistryRoot $fleetPin.path -FleetLabels @()) -like "*looks like a secret*") ("...and is refused as a name at every send, too: " + $sk)
    }
    $fb = Submit-HordeNotify -Sender ([pscustomobject]@{ ok = $true; reason = ""; sessionId = "service:legacy"; label = "service: sk-abcdefghijklmnopqrstu" }) -Text "x" -HordeHome (New-Home) -Now $now
    Check ($fb.outcome -ceq "sent" -and $fb.notice.from -ceq "a service") ("THE FALLBACK SAYS a service, never a session (" + $fb.notice.from + ")")
    # S1: the file is locked from the instant it exists.
    $pf = Secret-Path "probe"; New-Item -ItemType Directory -Path (Split-Path $pf) -Force | Out-Null
    $seen = @{ rules = @(); length = -1 }
    New-HordeLockedSecretFile -Path $pf -Text "abc" -Probe { $seen.rules = @((Get-HordeFileAcl -Path $pf).GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])); $seen.length = (New-Object System.IO.FileInfo -ArgumentList $pf).Length }
    Check ($seen.rules.Count -eq 2 -and @($seen.rules | Where-Object { $_.IsInherited }).Count -eq 0 -and $seen.length -eq 0) "THE SECRET FILE IS LOCKED WHEN IT FIRST EXISTS: two entries, none inherited, with nothing yet written"
    Check (([System.IO.File]::ReadAllText($pf)) -ceq "abc" -and (Test-HordeSecretFileOpen -Path $pf) -ceq "") "...and what was written through that handle is there"
    Check (Throws { New-HordeLockedSecretFile -Path $pf -Text "other" }) "a file that exists is never taken over"
    $script:labels = @("buildmaster")
    foreach ($bad in @("m", "thrall", "founder-bot", "horde-notes", "orc-e3", "orcs-pool", "wezfleet", "E3", "abcd", "Bad_Name", "build-master", ("a" * 40), "-lead-dash", "trail-dash-", "e-3-x-y", "a-b-c-d")) {
        $rb = Register $H $bad (Secret-Path "bad")
        Check (-not $rb.ok) ("the name '" + $bad.Substring(0, [Math]::Min(12, $bad.Length)) + "' is refused at registration (" + $rb.reason.Substring(0, [Math]::Min(60, $rb.reason.Length)) + ")")
    }
    Check (@((Read-HordeNoticeServices -Store (Join-Path $H "notices")).value.Keys).Count -eq 1) "none of the refused names was kept"
    $f2 = Secret-Path "second"
    Check ((Register $H "docs-watcher" $f2).ok) "CONTROL: a plain name is registered"

    Write-Host ""
    Write-Host "--- 2. sending: its own name, its secret, and the same refusal for every wrong guess ---" -ForegroundColor Cyan
    $s = Send $H "postmerge-net" $f1 "post-merge net is red on main" $now
    $all = @(Get-Notices $H)
    Check ($s.outcome -ceq "sent" -and $all.Count -eq 1 -and $all[0].from -ceq "service: postmerge-net" -and $all[0].text -ceq "post-merge net is red on main" -and $all[0].kind -ceq "notify") ("a registered service's notice is from 'service: postmerge-net' (" + $s.outcome + ")")
    Check (-not [System.IO.File]::ReadAllText((Join-Path $H "notices\notices.jsonl")).Contains($secret)) "the secret is nowhere in the notices"
    $same = "no notice was sent: the service name or its secret is not right"
    $wrongFile = Secret-Path "wrong"
    $flipChar = "a"; if ($secret[0] -ceq "a") { $flipChar = "b" }
    $short = Secret-Path "short"; $empty = Secret-Path "empty"; $flip = Secret-Path "flip"
    New-HordeLockedSecretFile -Path $wrongFile -Text (("0" * 64))
    New-HordeLockedSecretFile -Path $short -Text ($secret.Substring(0, 40))
    New-HordeLockedSecretFile -Path $empty -Text ("")
    New-HordeLockedSecretFile -Path $flip -Text (($flipChar + $secret.Substring(1)))
    $g = @(
        (Send $H "postmerge-net" $wrongFile), (Send $H "postmerge-net" $short), (Send $H "postmerge-net" $empty), (Send $H "postmerge-net" $flip),
        (Send $H "postmerge-net" $f2), (Send $H "never-registered" $f1), (Send $H "postmerge-net" (Join-Path $work "secrets\no-such-file.txt")), (Send $H "postmerge-net" "")
    )
    Check (@($g | Where-Object { $_.outcome -ceq "refused" -and $_.reason -ceq $same }).Count -eq 8) "A WRONG, SHORT, EMPTY, EDITED OR ANOTHER SERVICE'S SECRET, AN UNREGISTERED NAME, A MISSING FILE: all refused with one answer"
    Check (@(Get-Notices $H).Count -eq 1) "none of the refused sends wrote a notice"
    Check ((Send $H "docs-watcher" $f1).outcome -ceq "refused") "the secret of one service does not send as another"
    $hash = ((Read-HordeNoticeServices -Store (Join-Path $H "notices")).value["postmerge-net"]).hash
    $hf = Secret-Path "hash"; New-HordeLockedSecretFile -Path $hf -Text $hash
    Check ((Send $H "postmerge-net" $hf).outcome -ceq "refused") "READING THE STORE GIVES NO WAY TO SEND: the stored hash is refused as a secret"
    $open = Secret-Path "open"; [System.IO.File]::WriteAllText($open, $secret, $utf8)
    $null = & icacls.exe $open /grant "*S-1-5-32-545:(R)"
    $o = Send $H "postmerge-net" $open
    Check ($o.outcome -ceq "refused" -and $o.reason -like "*can be read by*") ("a copy of the right secret that Users can read is refused (" + $o.reason + ")")
    # S4: only this user and SYSTEM. Guests, NETWORK and Administrators are refused too (the old list named broad groups only).
    foreach ($right in @("WDAC", "WO")) {
        $cp = Secret-Path "wdac"; New-Item -ItemType Directory -Path (Split-Path $cp) -Force | Out-Null
        New-HordeLockedSecretFile -Path $cp -Text $secret
        $null = & icacls.exe $cp /grant ("*S-1-5-32-545:(" + $right + ")")
        $gr = Send $H "postmerge-net" $cp
        Check ($gr.outcome -ceq "refused" -and $gr.reason -like "*can be read by S-1-5-32-545*") ("a copy where Users may " + $right + " (and so grant themselves read) is refused (" + $gr.reason + ")")
    }
    foreach ($grant in @("S-1-5-32-546", "S-1-5-2", "S-1-5-32-544")) {
        $cp = Secret-Path "grant"; New-Item -ItemType Directory -Path (Split-Path $cp) -Force | Out-Null
        New-HordeLockedSecretFile -Path $cp -Text $secret
        Check ((Send $H "postmerge-net" $cp "ok").outcome -ceq "sent") ("CONTROL: the locked copy is accepted before the grant to " + $grant)
        $null = & icacls.exe $cp /grant ("*" + $grant + ":(R)")
        $gr = Send $H "postmerge-net" $cp
        Check ($gr.outcome -ceq "refused" -and $gr.reason -like ("*can be read by " + $grant + "*")) ("a copy that " + $grant + " can read is refused (" + $gr.reason + ")")
    }
    $rv = Remove-HordeNoticeService -Registrar (Proven (Sid 2) "E3") -Name "postmerge-net" -HordeHome $H
    Check (-not $rv.ok -and (Send $H "postmerge-net" $f1).outcome -ceq "sent") "an Orc cannot revoke a service"
    $rv = Remove-HordeNoticeService -Registrar (Proven (Sid 1) "M") -Name "postmerge-net" -HordeHome $H
    Check ($rv.ok -and (Send $H "postmerge-net" $f1).outcome -ceq "refused") "M revokes it and its secret proves nothing at once"
    $f3 = Secret-Path "renewed"
    Check ((Register $H "postmerge-net" $f3).ok -and (Send $H "postmerge-net" $f1).outcome -ceq "refused" -and (Send $H "postmerge-net" $f3).outcome -ceq "sent") "registered again it has a NEW secret; the old one stays dead"
    Check (-not (Remove-HordeNoticeService -Registrar (Proven (Sid 1) "M") -Name "not-there" -HordeHome $H).ok) "revoking a name that is not registered says so"
    $script:labels = @("Docs-Watcher")
    $c = Send $H "docs-watcher" $f2
    Check ($c.outcome -ceq "refused" -and $c.reason -like "*label of a session*") ("A NAME THAT BECAME A FLEET LABEL is refused at send, ignoring case and dashes (" + $c.reason + ")")
    [System.IO.File]::WriteAllText((Join-Path $H "notices\services.json"), "{not json", $utf8)
    $d = Send $H "postmerge-net" $f3
    Check ($d.outcome -ceq "refused" -and $d.reason -like "*notice services*") "a services file that does not hold together sends nothing and says why"
    $d2 = Register $H "fresh-service" (Secret-Path "fresh")
    Check (-not $d2.ok -and $d2.reason -like "*notice services*") "...and registers nothing over it"

    Write-Host ""
    Write-Host "--- 3. its own cap, and a secret in the text ---" -ForegroundColor Cyan
    $H = New-Home -Settings '{"perHour": 5, "servicePerHour": 2}'
    $fa = Secret-Path "a"; $fb = Secret-Path "b"
    $null = Register $H "net-watcher" $fa; $null = Register $H "disk-watcher" $fb
    $o1 = Send $H "net-watcher" $fa "one" $now
    $o2 = Send $H "net-watcher" $fa "two" $now
    $o3 = Send $H "net-watcher" $fa "three" $now.AddMinutes(1)
    $o4 = Send $H "net-watcher" $fa "four" $now.AddMinutes(2)
    $all = @(Get-Notices $H)
    Check ($o3.reason -like "*this service has sent 2 notices*" -and $o3.reason -notlike "*this session*") ("the cutoff says service, not session (" + $o3.reason + ")")
    Check ($o1.outcome -ceq "sent" -and $o2.outcome -ceq "sent" -and $o3.outcome -ceq "cut-off" -and $o4.outcome -ceq "held" -and $all.Count -eq 3 -and $all[-1].kind -ceq "cutoff") "servicePerHour (2) cuts the third off, the founder is told once, the fourth is held"
    Check ($all[-1].text -like "service: net-watcher sent more than 2 notices*") ("the cutoff names the service (" + $all[-1].text + ")")
    Check ((Send $H "disk-watcher" $fb "mine" $now.AddMinutes(3)).outcome -ceq "sent") "another service has its own count"
    $ses = @(1..5 | ForEach-Object { (Submit-HordeNotify -Sender (Proven (Sid 7) "E3") -Text ("s" + $_) -HordeHome $H -Now $now.AddMinutes(4)).outcome })
    $ses6 = (Submit-HordeNotify -Sender (Proven (Sid 7) "E3") -Text "s6" -HordeHome $H -Now $now.AddMinutes(4)).outcome
    Check (@($ses | Where-Object { $_ -ceq "sent" }).Count -eq 5 -and $ses6 -ceq "cut-off") "THE SESSION RULE IS UNCHANGED: a session keeps perHour (5), whatever the services' cap or count"
    Check ((Send $H "net-watcher" $fa "next hour" $now.AddHours(1)).outcome -ceq "sent") "the next clock hour starts the service's count again"
    $sec = Send $H "disk-watcher" $fb ("leaked " + $token) $now.AddHours(2)
    $last = @(Get-Notices $H)[-1]
    Check ($sec.outcome -ceq "sent-refused" -and $last.from -ceq "service: disk-watcher" -and $last.text -ceq (Get-HordeNoticeSecretWords) -and -not [System.IO.File]::ReadAllText((Join-Path $H "notices\notices.jsonl")).Contains("ghp_")) "A SECRET IN A SERVICE'S TEXT IS THE FIXED SENTENCE, as for a session"
    $longName = "a" + ("b" * 28) + "c"; $fl = Secret-Path "long"
    $mx = Register $H $longName $fl
    $null = Send $H $longName $fl "longest" $now.AddHours(3)
    Check ($mx.ok -and @(Get-Notices $H)[-1].from -ceq ("service: " + $longName)) "the longest name is shown whole, not cut"

    Write-Host ""
    Write-Host "--- 4. the session rule: no session takes a service's form, and the registry's labels are really read ---" -ForegroundColor Cyan
    foreach ($lbl in @("service: postmerge-net", "Service:x", "  SERVICE : y", "services: x", "service; x", "service - x", "5ervice: x", "serv1ce: x", "s-e-r-v-i-c-e: x", ([string][char]0x200B + "service: x"), "servlce: postmerge-net", "SERVlCE", "serv|ce", "serv!ce", '$ervice', "servi(e", "seruice", "servise", "servce", "serrvice", "sxrvice", "servic3: x", "serv1c3", "(1) service: x", "[!] SERVICE: x", "((service))", "!! service", "11 service", '$$ service', "sevrice", "srevice", "serivce", "servcie", "esrvice", "ser\/ice", "ser\/ic", "serv1c", "5ervic", "ssservice", "sexrvice", "servixce", "serv|c", "serv!c", "servlc", '$ervic', "servi(", "servi<", "servi[", "servi{", "seruic", "s3rvic", "s3rv1c3", "s|e|r|v|i|c|e", "s!e!r!v!i!c!e", "s1e1r1v1i1c1e", "s(e)r(v)i(c)e", "[s][e][r][v][i][c][e]", "[!] serv1c3")) {
        Check (Test-HordeNoticeServiceForm -Label $lbl) ("a session label '" + $lbl.Trim() + "' reads as a service's, so Resolve-HordeNoticeSender refuses it")
    }
    foreach ($lbl in @("servlet", "servile", "E3 service")) { Check (Test-HordeNoticeServiceForm -Label $lbl) ("KNOWN AND ACCEPTED: '" + $lbl + "' is one edit from service and is reserved") }
    foreach ($lbl in @("M", "E3", "Orc E3", "C12", "Thrall", "the service desk", "server", "serene", "serve", "A1", "Orc F", "Warg 3", "servers", "serial", "seven", "sieve", "receive", "serving", "servant", "survey", "device", "series", "Serbia", "servo", "C13", "fleet-analyst", "orah-triage", "postmerge-net", "Orc C service", "Warg service-check", "reserve", "severe", "sericite")) { Check (-not (Test-HordeNoticeServiceForm -Label $lbl)) ("CONTROL: the ordinary label '" + $lbl + "' is not refused") }
    foreach ($lbl in @([string]::Concat([char]0x0455, [char]0x0435, [char]0x0433, [char]0x0475, [char]0x0456, [char]0x0441, [char]0x0435, ": x"), [string]::Concat("service", [char]0x3164), (-join ([char]0x05E9, [char]0x05DC, [char]0x05D5, [char]0x05DD)))) {
        Check ((Get-HordeNoticeShownLabel -Label $lbl) -ceq "a session") "a label that is not printable ASCII is shown as a session"
    }
    foreach ($lbl in @([string]::Concat("serv", [char]0x00EC, "ce"), [string]::Concat("a", [char]0x007F, "b"), [string]::Concat("a", [char]0x00A0, "b"), [string]::Concat("caf", [char]0x00E9))) {
        Check ((Get-HordeNoticeShownLabel -Label $lbl) -ceq "a session") ("a label with a character in 0x7F-0xFF is shown as a session: U+" + ([int][char]$lbl[-1]).ToString("X4"))
    }
    Check ((Get-HordeNoticeShownLabel -Label "Orc E3") -ceq "Orc E3") "CONTROL: a printable ASCII label is shown as written"
    # THE OWNER: a file owned by someone else (the system's own hosts file belongs to the installer) is refused first.
    $hosts = Join-Path $env:windir "System32\drivers\etc\hosts"
    Check ((Test-HordeSecretFileOpen -Path $hosts) -like "*is owned by*") "a secret file whose owner is not the current user is refused for that, before its entries"
    $fixtureFleet = Join-Path $root "test\fixtures\projection\fleet\wezfleet"
    $real = @(Get-HordeFleetLabels -RegistryRoot $fixtureFleet)
    Check ($real.Count -gt 5 -and $real -ccontains "M" -and $real -ccontains "A1") ("CONTROL: the fleet registry's labels are read from its records (" + $real.Count + " found)")
    $H = New-Home
    $script:labels = $null
    $viaReg = Register $H "a1" (Secret-Path "x")
    Check (-not $viaReg.ok) "a label the real registry holds is refused as a service name (by shape, as every Orc label is)"
    Check ((Test-HordeServiceName -Name "thrall-notes" -RegistryRoot $fixtureFleet) -ne "" -and (Test-HordeServiceName -Name "plain-service" -RegistryRoot $fixtureFleet) -ceq "") "the registry read does not refuse a plain name"

    Write-Host ""
    Write-Host "--- 5. the shipped commands, end to end ---" -ForegroundColor Cyan
    $script:labels = @()
    $H = New-Home
    $profileDir = Join-Path $work "profile"
    [void](New-HordeTestProfile $profileDir)
    $envNone = @{ HORDE_HOME = $H; USERPROFILE = $profileDir }
    $cf = Secret-Path "cli"
    # Registered in the suite's process (the registrar's proof is notices/Sender.ps1's own suite); the CLI then proves and sends.
    Check ((Register $H "cli-service" $cf).ok) "CONTROL: the service is registered"
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify-service", "register", "-Name", "other-service", "-SecretFile", (Secret-Path "cli2")) -Env $envNone
    Check ($r.code -eq 1 -and $r.out -like "*no notice was sent*" -and @((Read-HordeNoticeServices -Store (Join-Path $H "notices")).value.Keys).Count -eq 1) ("the register command without a proven session registers nothing (" + $r.code + ": " + $r.out.Trim() + ")")
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify-service", "revoke", "-Name", "cli-service") -Env $envNone
    Check ($r.code -eq 1 -and @((Read-HordeNoticeServices -Store (Join-Path $H "notices")).value.Keys).Count -eq 1) "...and the revoke command without one revokes nothing"
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify-service", "list") -Env $envNone
    Check ($r.code -eq 0 -and $r.out -like "*cli-service*by M*" -and -not $r.out.Contains(([System.IO.File]::ReadAllText($cf)).Trim())) "list shows the name and who registered it, never a secret"
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify", "-Text", "from the service", "-Service", "cli-service", "-SecretFile", $cf) -Env $envNone
    $all = @(Get-Notices $H)
    Check ($r.code -eq 0 -and $r.out -like "*from service: cli-service*" -and $all.Count -eq 1 -and $all[0].from -ceq "service: cli-service") ("a service sends with no session at all (" + $r.code + ": " + $r.out.Trim() + ")")
    $wrong = Secret-Path "cliwrong"; New-Item -ItemType Directory -Path (Split-Path $wrong) -Force | Out-Null; New-HordeLockedSecretFile -Path $wrong -Text ("1" * 64)
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify", "-Text", "bad", "-Service", "cli-service", "-SecretFile", $wrong) -Env $envNone
    Check ($r.code -eq 1 -and $r.out -like "*not right*" -and @(Get-Notices $H).Count -eq 1) ("a wrong secret exits 1, nothing is sent (" + $r.out.Trim() + ")")
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify", "-Text", "bad", "-Service", "cli-service") -Env $envNone
    Check ($r.code -eq 1 -and $r.out -like "*go together*" -and @(Get-Notices $H).Count -eq 1) "-Service without -SecretFile is refused"
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify", "-Text", "bad", "-SecretFile", $cf) -Env $envNone
    Check ($r.code -eq 1 -and $r.out -like "*go together*") "-SecretFile without -Service is refused"
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify", "-Text", "x", "-From", "M") -Env $envNone
    Check ($r.code -eq 2) "there is still no -From"
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify", "-Text", ("x " + $token), "-Service", "cli-service", "-SecretFile", $cf) -Env $envNone
    Check ($r.code -eq 1 -and $r.out -like "*without its words*" -and -not [System.IO.File]::ReadAllText((Join-Path $H "notices\notices.jsonl")).Contains("ghp_")) "a secret on the command line is not sent by a service either"
    $null = Remove-HordeNoticeService -Registrar (Proven (Sid 1) "M") -Name "cli-service" -HordeHome $H
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify", "-Text", "after revoke", "-Service", "cli-service", "-SecretFile", $cf) -Env $envNone
    Check ($r.code -eq 1 -and @(Get-Notices $H).Count -eq 2) "after revoking, the service's secret sends nothing"
    # N5: the service cap, with a value that is not the default, through the shipped command.
    $H2 = New-Home -Settings '{"perHour": 5, "servicePerHour": 1}'
    $c2 = Secret-Path "cap"
    Check ((Register $H2 "cap-service" $c2).ok) "CONTROL: a service for the cap check"
    $envCap = @{ HORDE_HOME = $H2; USERPROFILE = $profileDir }
    $r1 = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify", "-Text", "one", "-Service", "cap-service", "-SecretFile", $c2) -Env $envCap
    $r2 = Invoke-HordeCliProcess -Root $root -HordeArgs @("notify", "-Text", "two", "-Service", "cap-service", "-SecretFile", $c2) -Env $envCap
    Check ($r1.code -eq 0 -and $r2.code -eq 1 -and $r2.out -like "*cut off*" -and @(Get-Notices $H2).Count -eq 2 -and @(Get-Notices $H2)[-1].kind -ceq "cutoff") ("THE SERVICE CAP REACHES THE SHIPPED COMMAND: servicePerHour 1 sends one, cuts the second off (" + $r2.out.Trim() + ")")
    $r = Invoke-HordeCliProcess -Root $root -Shell "pwsh.exe" -HordeArgs @("help") -Env $envNone
    Check ($r.code -eq 0 -and $r.out -like "*notify-service*" -and $r.out.Contains("notify -Text <one line> [-Service")) "horde help lists both commands"} finally {
    $env:HORDE_HOME = $realHome
    # a broken guard would have made this folder in the real checkout: never leave it (the one name this suite makes there)
    $strayDir = Join-Path $root "never-made-by-this-suite"
    if ((Split-Path -Leaf $strayDir) -ceq "never-made-by-this-suite" -and (Test-Path -LiteralPath $strayDir)) { Remove-Item -LiteralPath $strayDir -Recurse -Force -ErrorAction SilentlyContinue }
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    if ((Split-Path -Leaf $work) -match '^horde-noticesvc-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    Check (-not (Test-Path -LiteralPath $work)) "every folder the suite made is gone"
}

Complete-HordeSuite -Success "a registered service's notice reaches the founder as 'service: <name>' only with its secret, never as a session, an Orc, M or the Thrall, under its own cap; the session rule is as it was"
