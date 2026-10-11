# DOES `horde listen` KEEP EXACTLY ONE FIREWALL RULE OF ITS OWN, ONLY AS WIDE AS ITS NODES, AND NOTHING ELSE?
#
# Mesh v1 (2026-10-11). Off loopback, `horde listen` keeps one inbound rule named "Horde listen <hubId>":
# TCP to the listen address and port only, from the enrolled nodes' last-known addresses or -AllowFrom
# only, Private and Domain profiles only, removed when it stops (core/FirewallPort.ps1,
# cli/ListenFirewall.ps1). It is idempotent and owned by name, never touches another rule, and never
# elevates: without an administrator it refuses with the exact one line to run.
#
# A STAND-IN FIREWALL ONLY. Every case runs against an in-memory adapter that holds other rules too - the
# disabled remote-desktop rule Windows ships, another program's, another hub's - and checks they are
# untouched. No case makes, changes or deletes a real firewall rule: the Windows adapter is read here as
# text, never loaded, and its every firewall cmdlet is held to naming the one rule by -Name.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\FirewallPort.ps1")
. (Join-Path $root "cli\ListenFirewall.ps1")

$hub = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
$otherHub = "0f8fad5b-d9cb-469f-a165-70867728950e"
$ours = "Horde listen " + $hub

function New-FakeFirewall {
    # An in-memory firewall: { rules (name -> rule); calls; elevated; adapter }. It holds three rules that
    # are not ours, as a real one does.
    param([bool]$Elevated = $true, [scriptblock]$OnSet = $null)
    $st = [pscustomobject]@{ rules = [ordered]@{}; calls = (New-Object System.Collections.ArrayList); elevated = $Elevated; onSet = $OnSet }
    $st.rules["RemoteDesktop-UserMode-In-TCP"] = [pscustomobject]@{ name = "RemoteDesktop-UserMode-In-TCP"; direction = "Inbound"; action = "Allow"; protocol = "TCP"; localAddress = "Any"; localPort = 3389; remoteAddresses = @("Any"); profiles = @("Domain", "Private", "Public"); enabled = $false }
    $st.rules["Some App In"] = [pscustomobject]@{ name = "Some App In"; direction = "Inbound"; action = "Allow"; protocol = "TCP"; localAddress = "Any"; localPort = 8080; remoteAddresses = @("Any"); profiles = @("Private"); enabled = $true }
    $st.rules[("Horde listen " + $otherHub)] = [pscustomobject]@{ name = ("Horde listen " + $otherHub); direction = "Inbound"; action = "Allow"; protocol = "TCP"; localAddress = "10.0.0.1"; localPort = 2222; remoteAddresses = @("10.0.0.9"); profiles = @("Domain", "Private"); enabled = $true }
    $adapter = [pscustomobject]@{
        name = "fake"
        applies = { $true }
        elevated = { [void]$st.calls.Add("elevated"); return $st.elevated }.GetNewClosure()
        get = { param($Name) [void]$st.calls.Add("get " + $Name); if ($st.rules.Contains($Name)) { return $st.rules[$Name] } return $null }.GetNewClosure()
        set = { param($Spec) [void]$st.calls.Add("set " + $Spec.name); if ($null -ne $st.onSet) { & $st.onSet $Spec; return }; $st.rules[$Spec.name] = [pscustomobject]@{ name = $Spec.name; direction = $Spec.direction; action = $Spec.action; protocol = $Spec.protocol; localAddress = $Spec.localAddress; localPort = $Spec.localPort; remoteAddresses = @($Spec.remoteAddresses); profiles = @($Spec.profiles); enabled = $true } }.GetNewClosure()
        remove = { param($Name) [void]$st.calls.Add("remove " + $Name); if ($st.rules.Contains($Name)) { $st.rules.Remove($Name) } }.GetNewClosure()
    }
    $st | Add-Member -NotePropertyName adapter -NotePropertyValue $adapter
    return $st
}
function Get-Others { param($St) return ((@($St.rules.Keys | Where-Object { $_ -cne $ours } | Sort-Object | ForEach-Object { $_ + "=" + ($St.rules[$_] | ConvertTo-Json -Compress) })) -join "|") }
$lan = [pscustomobject]@{ address = "192.168.1.182"; family = "v4"; kind = "private (RFC 1918)"; loopback = $false }
$lo = [pscustomobject]@{ address = "127.0.0.1"; family = "v4"; kind = "loopback"; loopback = $true }

Write-Host ""
Write-Host "--- the rule as it should be: TCP, the listen address and port, the nodes only, never Public ---" -ForegroundColor Cyan
$sp = New-HordeListenRuleSpec -HubId $hub -Address "192.168.1.182" -Port 2222 -AllowFrom @("192.168.1.156")
Check ($sp.state -ceq "known") ("CONTROL: a rule for a LAN listener can be made (" + $sp.reason + ")")
$s = $sp.value
Check ($s.name -ceq $ours -and $s.direction -ceq "Inbound" -and $s.action -ceq "Allow" -and $s.protocol -ceq "TCP" -and $s.localAddress -ceq "192.168.1.182" -and $s.localPort -eq 2222) "named 'Horde listen <hubId>', inbound, allow, TCP, to the listen address and port only"
Check ((@($s.remoteAddresses) -join ",") -ceq "192.168.1.156" -and (@($s.profiles) -join ",") -ceq "Domain,Private") "from the nodes' addresses only, on the Private and Domain profiles only, never Public"
Check ($null -eq $s.PSObject.Properties["program"]) "it names no program: the port names no listener"
foreach ($bad in @(
        @{ a = "127.0.0.1"; p = 2222; f = @("192.168.1.156"); want = "*loopback*" },
        @{ a = "8.8.8.8"; p = 2222; f = @("192.168.1.156"); want = "*public address*" },
        @{ a = "0.0.0.0"; p = 2222; f = @("192.168.1.156"); want = "*every interface*" },
        @{ a = "192.168.1.182"; p = 0; f = @("192.168.1.156"); want = "*not a TCP port*" },
        @{ a = "192.168.1.182"; p = 2222; f = @(); want = "*no address to let nodes in from*" },
        @{ a = "192.168.1.182"; p = 2222; f = @("any"); want = "*not an IP address*" },
        @{ a = "192.168.1.182"; p = 2222; f = @("8.8.8.8"); want = "*public address*" })) {
    $r = New-HordeListenRuleSpec -HubId $hub -Address $bad.a -Port $bad.p -AllowFrom $bad.f
    Check ($r.state -ceq "unknown" -and $r.reason -like $bad.want) ("no rule for " + $bad.a + ":" + $bad.p + " from '" + ($bad.f -join ",") + "' (" + $r.reason + ")")
}
$threw = ""; try { $null = Get-HordeListenRuleName -HubId "HUB" } catch { $threw = $_.Exception.Message }
Check ($threw -like "*not a hub id*") "a rule is only ever named by a hub id"

Write-Host ""
Write-Host "--- written idempotently, owned by name, touching nothing else ---" -ForegroundColor Cyan
$fw = New-FakeFirewall
$before = Get-Others $fw
$r = Sync-HordeListenRule -Firewall $fw.adapter -Spec $s
Check ($r.ok -and $r.did -ceq "made" -and $fw.rules.Contains($ours)) ("the rule is made (" + $r.did + $r.reason + ")")
$fw.calls.Clear()
$r = Sync-HordeListenRule -Firewall $fw.adapter -Spec $s
Check ($r.ok -and $r.did -ceq "unchanged" -and @($fw.calls | Where-Object { $_ -like "set *" -or $_ -like "remove *" }).Count -eq 0) ("asked again, nothing is written (" + ($fw.calls -join "; ") + ")")
$s2 = (New-HordeListenRuleSpec -HubId $hub -Address "192.168.1.182" -Port 2222 -AllowFrom @("192.168.1.156", "192.168.1.157")).value
$r = Sync-HordeListenRule -Firewall $fw.adapter -Spec $s2
Check ($r.ok -and $r.did -ceq "replaced" -and (@($fw.rules[$ours].remoteAddresses) -join ",") -ceq "192.168.1.156,192.168.1.157") "a changed node list replaces the rule"
$fw.rules[$ours].profiles = @("Domain", "Private", "Public")
$r = Sync-HordeListenRule -Firewall $fw.adapter -Spec $s2
Check ($r.ok -and $r.did -ceq "replaced" -and (@($fw.rules[$ours].profiles) -join ",") -ceq "Domain,Private") "a rule widened to Public by hand is put back, never kept"
Check ((@($fw.calls | Where-Object { $_ -notlike ("* " + $ours) -and $_ -cne "elevated" })).Count -eq 0) ("every call named our rule and no other (" + (@($fw.calls) -join "; ") + ")")
Check ((Get-Others $fw) -ceq $before) "the remote-desktop rule, another program's and another hub's are exactly as they were"
$r = Sync-HordeListenRule -Firewall $fw.adapter -Spec ([pscustomobject]@{ name = "RemoteDesktop-UserMode-In-TCP"; direction = "Inbound"; action = "Allow"; protocol = "TCP"; localAddress = "Any"; localPort = 3389; remoteAddresses = @("Any"); profiles = @("Public") })
Check (-not $r.ok -and $r.reason -like "*not one this port owns*" -and (Get-Others $fw) -ceq $before) "a spec naming a rule that is not Horde's own is refused, and nothing is written"
$bad = New-FakeFirewall -OnSet { param($Spec) }
$r = Sync-HordeListenRule -Firewall $bad.adapter -Spec $s
Check (-not $r.ok -and $r.reason -like "*did not read back as written*") "a write that does not read back is a failure, never reported made"

Write-Host ""
Write-Host "--- never elevated by Horde: without an administrator, nothing is asked of the firewall ---" -ForegroundColor Cyan
$plain = New-FakeFirewall -Elevated $false
$r = Sync-HordeListenRule -Firewall $plain.adapter -Spec $s
Check (-not $r.ok -and $r.reason -like "*needs an administrator*" -and @($plain.calls | Where-Object { $_ -cne "elevated" }).Count -eq 0 -and -not $plain.rules.Contains($ours)) ("not elevated: refused, and no rule read or written (" + (@($plain.calls) -join "; ") + ")")

Write-Host ""
Write-Host "--- removed by name, and only that name ---" -ForegroundColor Cyan
$before = Get-Others $fw
Check ((Remove-HordeListenRule -Firewall $fw.adapter -Name $ours) -ceq "" -and -not $fw.rules.Contains($ours)) "the rule is removed"
Check ((Get-Others $fw) -ceq $before) "and every other rule is as it was"
Check ((Remove-HordeListenRule -Firewall $fw.adapter -Name $ours) -ceq "") "removing it when it is gone is not an error"
Check ((Remove-HordeListenRule -Firewall $fw.adapter -Name "Some App In") -like "*not one this port owns*" -and $fw.rules.Contains("Some App In")) "removing a rule that is not Horde's is refused, and it stays"
$stuck = New-FakeFirewall
$stuck.adapter.remove = { param($Name) }
$stuck.rules[$ours] = $s
Check ((Remove-HordeListenRule -Firewall $stuck.adapter -Name $ours) -like "*still there*") "a remove that leaves the rule is said, never reported gone"

Write-Host ""
Write-Host "--- horde listen's steps (cli/ListenFirewall.ps1) ---" -ForegroundColor Cyan
$fw = New-FakeFirewall
$known = New-HordeKnown -Value $fw.adapter
$o = Open-HordeListenFirewall -Where $lo -Port 0 -HubId $hub -Firewall (New-HordeUnknown -Reason "no firewall is needed on loopback") -Root "C:\horde"
Check ($o.ok -and $o.rule -ceq "") "loopback: no rule, and no firewall asked"
$o = Open-HordeListenFirewall -Where $lan -Port 0 -HubId $hub -Firewall $known -AllowFrom @("192.168.1.156") -Root "C:\horde"
Check (-not $o.ok -and $o.reason -like "*needs a fixed port*-Port*" -and $fw.calls.Count -eq 0) "a LAN listener with port 0 is refused: a node must be told the port"
$o = Open-HordeListenFirewall -Where $lan -Port 2222 -HubId $hub -Firewall $known -Root "C:\horde"
Check (-not $o.ok -and $o.reason -like "*no address to let nodes in from*horde hub enroll*-Address*" -and $fw.calls.Count -eq 0) ("nobody to let in - no -AllowFrom, no enrolled address - is refused, never 'any' (" + $o.reason + ")")
$o = Open-HordeListenFirewall -Where $lan -Port 2222 -HubId $hub -Firewall (New-HordeUnknown -Reason "no firewall adapter is for this system") -AllowFrom @("192.168.1.156") -Root "C:\horde"
Check (-not $o.ok -and $o.reason -like "*cannot be kept to its nodes*no firewall adapter*") "no firewall adapter: refused, never listening unguarded"
$plain = New-FakeFirewall -Elevated $false
$o = Open-HordeListenFirewall -Where $lan -Port 2222 -HubId $hub -Firewall (New-HordeKnown -Value $plain.adapter) -AllowFrom @("192.168.1.156") -Root "C:\horde" -Seconds 600
$cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\horde\horde.ps1" listen -Address 192.168.1.182 -Port 2222 -AllowFrom 192.168.1.156 -Seconds 600'
Check (-not $o.ok -and $o.reason.EndsWith("In an elevated PowerShell, run: " + $cmd) -and -not $plain.rules.Contains($ours)) ("not elevated: refused with the exact one line to run elevated, and no rule (" + $o.reason + ")")
Check ((Get-HordeListenElevationCommand -Root "C:\horde" -Address "192.168.1.182" -Port 2222) -ceq 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\horde\horde.ps1" listen -Address 192.168.1.182 -Port 2222') "with no -AllowFrom and no -Seconds the line carries neither"
$o = Open-HordeListenFirewall -Where $lan -Port 2222 -HubId $hub -Firewall $known -Known @("192.168.1.156", "192.168.1.160") -Root "C:\horde"
Check ($o.ok -and $o.rule -ceq $ours -and (@($fw.rules[$ours].remoteAddresses) -join ",") -ceq "192.168.1.156,192.168.1.160" -and $o.said -like "*enrolled nodes' last-known addresses*Private and Domain profiles only*") ("with no -AllowFrom, the enrolled nodes' last-known addresses are let in (" + $o.said + ")")
$o = Open-HordeListenFirewall -Where $lan -Port 2222 -HubId $hub -Firewall $known -AllowFrom @("192.168.1.156") -Known @("192.168.1.160") -Root "C:\horde"
Check ($o.ok -and (@($fw.rules[$ours].remoteAddresses) -join ",") -ceq "192.168.1.156" -and $o.said -like "*(-AllowFrom)*") "-AllowFrom, when given, is the whole list"
Check ((Close-HordeListenFirewall -Firewall $known -Rule $ours) -like "*removed*" -and -not $fw.rules.Contains($ours)) "and when horde listen stops, the rule is removed"
Check ((Close-HordeListenFirewall -Firewall $known -Rule "") -ceq "") "with no rule made, nothing is removed"

Write-Host ""
Write-Host "--- the port finds its adapter, and the Windows adapter only ever names the one rule ---" -ForegroundColor Cyan
$saved = @($script:HordeFirewalls)
$script:HordeFirewalls.Clear()
Check ((Get-HordeFirewall).state -ceq "unknown") "no adapter loaded: unknown, never a guess"
Register-HordeFirewall -Name "elsewhere" -Applies { $false } -Elevated { $true } -Get { } -Set { } -Remove { }
Check ((Get-HordeFirewall).state -ceq "unknown") "an adapter for another system is not used"
Register-HordeFirewall -Name "here" -Applies { $true } -Elevated { $true } -Get { } -Set { } -Remove { }
Check ((Get-HordeFirewall).value.name -ceq "here") "the adapter for this system is"
$script:HordeFirewalls.Clear(); foreach ($x in $saved) { [void]$script:HordeFirewalls.Add($x) }
$files = @(Get-HordeFirewallFiles -Root $root)
Check ($files.Count -eq 1 -and $files[0] -like "*\platform\windows\Firewall.ps1") "CONTROL: the Windows adapter is found by folder"
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($files[0], [ref]$tokens, [ref]$errors)
$fwCalls = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and "$($n.GetCommandName())" -like "*-NetFirewall*" }, $true))
Check ($fwCalls.Count -ge 4) ("CONTROL: its firewall cmdlets are found (" + $fwCalls.Count + ")")
$rule = @($fwCalls | Where-Object { "$($_.GetCommandName())" -like "*-NetFirewallRule" })
$byName = @($rule | Where-Object { $_.Extent.Text -match '-Name \$(Name|Spec\.name)\b' })
Check ($rule.Count -ge 4 -and $byName.Count -eq $rule.Count) ("every rule cmdlet names the one rule by -Name and nothing else selects one (" + $byName.Count + " of " + $rule.Count + ")")
$filters = @($fwCalls | Where-Object { "$($_.GetCommandName())" -notlike "*-NetFirewallRule" })
Check (@($filters | Where-Object { "$($_.GetCommandName())" -notlike "Get-NetFirewall*Filter" }).Count -eq 0) "beyond the rule cmdlets it only reads that rule's filters"
$text = [System.IO.File]::ReadAllText($files[0])
Check ($text -notmatch '(?i)-DisplayName\s+\$Name|-Group|Set-NetFirewallProfile|Set-NetFirewallSetting|RunAs|Start-Process|-Verb') "it selects no rule by display name or group, changes no profile or setting, and starts nothing, elevated or not"
Check ($text -notmatch '(?i)Public') "it never names the Public profile: the profiles are the spec's, Domain and Private"

Complete-HordeSuite -Success "horde listen keeps one firewall rule of its own, only as wide as its nodes, removed when it stops, and never elevates or touches another rule"
