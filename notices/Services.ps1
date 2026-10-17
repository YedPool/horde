# notices/Services.ps1 - NOTICE SERVICES: an unattended program (a scheduled task, say) that sends the
# founder notices under its OWN registered name, "service: <name>", without being a fleet session.
#
# WHY (order of 2026-10-16): a scheduled task is no session, so notices/Sender.ps1 refuses it and its notices
# had to be forwarded by hand. The answer is a second kind of sender, not a looser rule: the session rule
# (Sender.ps1) is untouched, and a service can never be shown as a session, an Orc, M, the Thrall or the founder.
#
# REGISTERED ONCE, BY THE FOUNDER'S SIDE. Register-HordeNoticeService is run by a PROVEN session (the same proof
# as `horde notify`) whose label is in the setting serviceRegistrars (default "M"). A service has no session,
# so it can never register itself, another service or a bigger limit. Registering makes a secret of 32 random
# bytes and writes it to -SecretFile, a NEW file CREATED ALREADY LOCKED to the current Windows user (the access is part of
# the create call) and filled through that same handle. The
# machine keeps only a salted SHA-256 of it in <store>\services.json, never the secret: reading the store
# does not yield a way to send.
#
# WHAT PROVES A LATER CALL: the secret. Resolve-HordeServiceSender reads it from the file named by the caller
# (never from the command line, where every process could list it), hashes it with the stored salt and compares in
# constant time. A file that anyone but the current user and SYSTEM can read or re-permission is refused. The
# scheduled task's own identity was weighed and NOT chosen: on this machine every program of the founder runs as
# the same Windows user, so the identity proves no more than the file does, and the file can be revoked and
# renewed alone. An unregistered name and a wrong secret get the SAME answer.
#
# THE NAME ON THE PHONE: "service: <name>". A name must be 6 to 30 of a-z 0-9 and "-", starting with a letter,
# and is refused (at registration AND at every send) when it collides, ignoring case and dashes, with M, Thrall,
# founder, Horde, an Orc's label shape (a letter and up to three more characters), a word of the fleet's own
# (orc, warg, analyst, system, fleet, ...) or any label in the fleet's registry. Sessions labelled like
# "service: ..." are refused by Sender.ps1, so the form is the services' alone.
#
# ITS OWN RATE LIMIT: counted under the key "service:<name>" (a session id is never that), cap servicePerHour,
# cut off and the founder told once, exactly as a session (notices/Decide.ps1's Submit-HordeNotify).
#
# REVOKING: Remove-HordeNoticeService, by a registrar, deletes the record at once; the old secret then proves
# nothing and the name can be registered again with a new one. The old secret file is left for its owner to delete.
#
# THE REGISTRAR LABEL IS A FLEET LABEL, NOT A PROOF OF WHO SPAWNED THE SESSION: the registry takes the label from whoever
# spawned the session, so an Orc that starts a child labelled M passes the registrar gate (the session rule has the same weakness).
# A service run as ANOTHER Windows account (SYSTEM, a service account) is refused: its secret file must be readable by that account only.
#
# WHAT THIS DOES NOT STOP, said plainly: a program running as the same Windows user can read the secret file.
# The secret keeps out other users, other programs that were not handed the file, and the fleet's sessions
# acting by mistake; not an adversary who already has the user's own power.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Store.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\WezfleetState.ps1")
. (Join-Path $PSScriptRoot "Decide.ps1")

$script:HordeServiceNamePattern = '\A[a-z][a-z0-9-]{4,28}[a-z0-9]\z'
$script:HordeServiceReservedWords = @("m", "thrall", "founder", "horde", "orc", "orcs", "warg", "wargs", "analyst", "system", "fleet", "wezfleet", "operator", "admin", "root", "service", "services", "relay", "phone")

function Get-HordeServiceLabel { param([Parameter(Mandatory = $true)][string]$Name) return ("service: " + $Name) }

function Get-HordeServiceBare {
    # A name or label as collisions compare it: lower case, only letters and digits.
    param([AllowEmptyString()][string]$Text)
    return ([regex]::Replace($Text.ToLowerInvariant(), '[^a-z0-9]', ''))
}

function Get-HordeFleetLabels {
    # Every label the fleet's registry holds, as written. -RegistryRoot is the fleet's folder.
    param([string]$RegistryRoot = (Get-HordeWezfleetRoot))
    $reg = Read-HordeRegistry -Root $RegistryRoot
    $out = New-Object System.Collections.ArrayList
    foreach ($k in @($reg.records.Keys)) {
        $l = Get-HordeStoredField -Record $reg.records[$k].record -Name "label"
        if ($l.state -ceq "known" -and $l.value -is [string]) { [void]$out.Add($l.value) }
    }
    return @($out.ToArray())
}

function Test-HordeServiceName {
    # Is -Name a name a service may have? "" when it is, else the reason in words. -RegistryRoot is the fleet's
    # registry (its labels are reserved too).
    param([AllowEmptyString()][string]$Name, [string]$RegistryRoot = (Get-HordeWezfleetRoot), [string[]]$FleetLabels = $null)
    if ($Name -cnotmatch $script:HordeServiceNamePattern) { return "a service name is 6 to 30 characters of a-z, 0-9 and '-', starting with a letter and not ending in '-'" }
    # IT IS SHOWN AS "service: <name>" AND THAT TEXT GOES THROUGH THE SECRET FINDER (notices/Decide.ps1): a name that trips it
    # (sk-..., xoxb-...) would be shown as a bare word, so it is no name.
    if ((Find-HordeSecretKind -Text (Get-HordeServiceLabel -Name $Name)) -cne "") { return ("'" + $Name + "' looks like a secret, and a name is shown on the phone") }
    $bare = Get-HordeServiceBare -Text $Name
    if ($script:HordeServiceReservedWords -contains $bare -or $bare -match '\A(orc|thrall|founder|horde)') { return ("'" + $Name + "' is a name only the founder's side or the fleet may be shown as") }
    if ($bare -match '\A[a-z][a-z0-9]{0,3}\z') { return ("'" + $Name + "' has the shape of an Orc's label") }
    foreach ($l in @($(if ($null -ne $FleetLabels) { $FleetLabels } else { Get-HordeFleetLabels -RegistryRoot $RegistryRoot }))) {
        if ((Get-HordeServiceBare -Text "$l") -ceq $bare) { return ("'" + $Name + "' is the label of a session in the fleet") }
    }
    return ""
}

function Get-HordeServicesPath { param([Parameter(Mandatory = $true)][string]$Store) return [System.IO.Path]::Combine($Store, "services.json") }

function Read-HordeNoticeServices {
    # services.json: known hashtable name -> { salt; hash; at; by } (empty when none), unknown when it does not hold together.
    param([Parameter(Mandatory = $true)][string]$Store)
    $path = Get-HordeServicesPath -Store $Store
    $r = Read-HordeNoticeJson -Path $path -What "notice services"
    if ($r.state -ceq "absent") { return (New-HordeKnown -Value @{}) }
    if ($r.state -cne "known") { return $r }
    $why = "the notice services " + $path + " do not hold together"
    $o = $r.value
    if ((@($o.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -cne "services,v" -or $o.v -ne 1 -or $o.services -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ($why + ": it is not {""v"":1,""services"":{...}}")) }
    $out = New-Object System.Collections.Hashtable -ArgumentList ([System.StringComparer]::Ordinal)
    foreach ($p in @($o.services.PSObject.Properties)) {
        $s = $p.Value
        if ($p.Name -cnotmatch $script:HordeServiceNamePattern -or $s -isnot [System.Management.Automation.PSCustomObject] -or (@($s.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -cne "at,by,hash,salt" -or
            $s.salt -isnot [string] -or $s.salt -cnotmatch '\A[0-9a-f]{32}\z' -or $s.hash -isnot [string] -or $s.hash -cnotmatch '\A[0-9a-f]{64}\z' -or ($s.at -isnot [string] -and $s.at -isnot [datetime]) -or $s.by -isnot [string]) { return (New-HordeUnknown -Reason ($why + ": the service '" + $p.Name + "' is not {salt, hash, at, by}")) }
        # PowerShell 7 reads an ISO time as a date; keep it as the text it was written as.
        $at = $s.at
        if ($at -is [datetime]) { $at = $at.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture) }
        $out[$p.Name] = [pscustomobject]@{ salt = $s.salt; hash = $s.hash; at = "$at"; by = $s.by }
    }
    return (New-HordeKnown -Value $out)
}

function Write-HordeNoticeServices {
    # services.json replaced whole, names in order. Throws. The caller holds the lock.
    param([Parameter(Mandatory = $true)][string]$Store, [Parameter(Mandatory = $true)][hashtable]$Services)
    $parts = @(@($Services.Keys | Sort-Object { $_ } -CaseSensitive) | ForEach-Object {
        $s = $Services[$_]
        (ConvertTo-HordeNoticeJsonString $_) + ':{"salt":"' + $s.salt + '","hash":"' + $s.hash + '","at":' + (ConvertTo-HordeNoticeJsonString $s.at) + ',"by":' + (ConvertTo-HordeNoticeJsonString $s.by) + '}'
    })
    Write-HordeNoticeFile -Path (Get-HordeServicesPath -Store $Store) -Text ('{"v":1,"services":{' + ($parts -join ",") + '}}')
}

function ConvertTo-HordeServiceHash {
    param([Parameter(Mandatory = $true)][string]$Salt, [Parameter(Mandatory = $true)][string]$Secret)
    $saltBytes = New-Object byte[] 16
    for ($i = 0; $i -lt 16; $i++) { $saltBytes[$i] = [Convert]::ToByte($Salt.Substring(2 * $i, 2), 16) }
    $data = $saltBytes + [System.Text.Encoding]::UTF8.GetBytes($Secret)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($data)).Replace("-", "").ToLowerInvariant()) } finally { $sha.Dispose() }
}

function Test-HordeConstantTimeEqual {
    param([string]$A, [string]$B)
    if ($A.Length -ne $B.Length) { return $false }
    $d = 0
    for ($i = 0; $i -lt $A.Length; $i++) { $d = $d -bor ([int][char]$A[$i] -bxor [int][char]$B[$i]) }
    return ($d -eq 0)
}

function New-HordeRandomHex {
    param([Parameter(Mandatory = $true)][int]$Bytes)
    $b = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    return ([System.BitConverter]::ToString($b).Replace("-", "").ToLowerInvariant())
}

function Get-HordeFileAcl {
    # A file's access rules by .NET, not the Get-Acl cmdlet: its module does not load in a Windows PowerShell child of a
    # PowerShell 7 parent (measured 2026-10-17), and a scheduled task may run either. 5.1 has the method on FileInfo; 7 has the extension.
    param([Parameter(Mandatory = $true)][string]$Path)
    $fi = New-Object System.IO.FileInfo -ArgumentList $Path
    if ($fi.PSObject.Methods["GetAccessControl"]) { return $fi.GetAccessControl() }
    return [System.IO.FileSystemAclExtensions]::GetAccessControl($fi)
}

function Set-HordeFileAcl {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Acl)
    $fi = New-Object System.IO.FileInfo -ArgumentList $Path
    if ($fi.PSObject.Methods["SetAccessControl"]) { $fi.SetAccessControl($Acl); return }
    [System.IO.FileSystemAclExtensions]::SetAccessControl($fi, $Acl)
}

function New-HordeSecretFileSecurity {
    # The access a secret file is made with: the current Windows user and SYSTEM, nothing inherited, nobody else.
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $sys = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
    $sec = New-Object System.Security.AccessControl.FileSecurity
    $sec.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($me, $sys)) { $sec.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($sid, [System.Security.AccessControl.FileSystemRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow))) }
    return $sec
}

function New-HordeLockedSecretFile {
    # Make the NEW file -Path with -Text in it, ALREADY locked: the access is part of the creation (the security descriptor
    # is handed to the create call), and the text is written through the same handle. Windows checks access only when a
    # handle is opened, so a file made open and locked after would keep a handle opened in between (PR 332 review, S1).
    # -Probe (a test seam) runs with the handle open, before anything is written. Throws if the file exists.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [scriptblock]$Probe = $null)
    $sec = New-HordeSecretFileSecurity
    $rights = [System.Security.AccessControl.FileSystemRights]::Write
    if ($PSVersionTable.PSEdition -ceq "Desktop") {
        $fs = New-Object System.IO.FileStream -ArgumentList $Path, ([System.IO.FileMode]::CreateNew), $rights, ([System.IO.FileShare]::None), 4096, ([System.IO.FileOptions]::None), $sec
    } else {
        $fs = [System.IO.FileSystemAclExtensions]::Create((New-Object System.IO.FileInfo -ArgumentList $Path), [System.IO.FileMode]::CreateNew, $rights, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::None, $sec)
    }
    try {
        if ($null -ne $Probe) { & $Probe }
        $b = [System.Text.Encoding]::ASCII.GetBytes($Text)
        $fs.Write($b, 0, $b.Length); $fs.Flush($true)
    } catch { $fs.Dispose(); try { [System.IO.File]::Delete($Path) } catch { }; throw }
    $fs.Dispose()
}

function Test-HordeSecretFileOpen {
    # Can anyone but the current Windows user and SYSTEM read -Path? "" when not, else the reason. ONLY those two may hold an
    # allowing entry (S4): not Administrators, not Domain Users, not NETWORK, not a named other user. A file whose access
    # cannot be read is open.
    param([Parameter(Mandatory = $true)][string]$Path)
    $mine = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $allowed = @($mine, "S-1-5-18")
    try {
        # THE OWNER can re-permission the file whatever its entries say: it must be the current user (or, for an elevated process,
        # the Administrators group, which owns what an elevated process creates).
        $owner = (Get-HordeFileAcl -Path $Path).GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        $admin = ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($owner -cne $mine -and -not ($admin -and $owner -ceq "S-1-5-32-544")) { return ("the secret file is owned by " + $owner + ", not by the current user; its owner could give himself access") }
        foreach ($r in @((Get-HordeFileAcl -Path $Path).GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))) {
            if ($r.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
            $sid = $r.IdentityReference.Value
            if ($allowed -ccontains $sid) { continue }
            $read = [System.Security.AccessControl.FileSystemRights]::ReadData -bor [System.Security.AccessControl.FileSystemRights]::ExecuteFile
            if (([int]$r.FileSystemRights -band [int]$read) -ne 0 -or ([int]$r.FileSystemRights -band 0x10000000) -ne 0 -or ([int]$r.FileSystemRights -band 0x40000) -ne 0 -or ([int]$r.FileSystemRights -band 0x80000) -ne 0 -or ([int]$r.FileSystemRights -band [int]::MinValue) -ne 0) { return ("the secret file can be read by " + $sid + ", not only by the current user and SYSTEM; it must be the service's user's alone") }
        }
    } catch { return ("the secret file's access could not be checked: " + $_.Exception.Message) }
    return ""
}
function Test-HordeRegistrarLabel {
    # S3: a registrar's label must be its FLEET label (the registry's), never the agent's own name for the session, which
    # any session can set to "M". A sender with no labelSource is not one.
    param($Registrar)
    $p = $Registrar.PSObject.Properties["labelSource"]
    return ($null -ne $p -and "$($p.Value)" -ceq "registry")
}

function Register-HordeNoticeService {
    # Register -Name for a PROVEN -Registrar (Resolve-HordeNoticeSender's answer), writing its new secret to the new file
    # -SecretFile. { ok; reason }. Nothing is kept unless the secret file was made and locked.
    param([Parameter(Mandatory = $true)]$Registrar, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SecretFile,
        [string]$HordeHome = "", [string]$RegistryRoot = (Get-HordeWezfleetRoot), $Now = $null, [string[]]$FleetLabels = $null, [string]$TestSeamRepoRoot = "")
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    $no = { param([string]$Why) return [pscustomobject]@{ ok = $false; reason = $Why } }
    $st = Get-HordeNoticeStore -HordeHome $HordeHome
    if (-not $st.ok) { return (& $no $st.reason) }
    if ($null -eq $Registrar -or -not $Registrar.ok -or "$($Registrar.label)" -ceq "") { return (& $no "no service was registered: the registrar is not a proven session") }
    $allowed = @("$($st.settings.serviceRegistrars)".Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -cne "" })
    if ($allowed -cnotcontains "$($Registrar.label)" -or -not (Test-HordeRegistrarLabel -Registrar $Registrar)) { return (& $no ("no service was registered: only a session whose fleet label is " + ($allowed -join " or ") + " may register one (the setting serviceRegistrars), not '" + $Registrar.label + "'")) }
    $bad = Test-HordeServiceName -Name $Name -RegistryRoot $RegistryRoot -FleetLabels $FleetLabels
    if ($bad -cne "") { return (& $no ("no service was registered: " + $bad)) }
    if ($SecretFile.Trim() -ceq "" -or -not [System.IO.Path]::IsPathRooted($SecretFile)) { return (& $no "no service was registered: -SecretFile must be an absolute path of a file that does not exist yet") }
    $SecretFile = [System.IO.Path]::GetFullPath($SecretFile)
    # N8: never inside this checkout, where a commit could carry it away.
    # -TestSeamRepoRoot: a TEST SEAM (the command line never passes it), so a suite points the guard at a throwaway folder and never at the real checkout.
    if ($TestSeamRepoRoot -ceq "") { $TestSeamRepoRoot = Split-Path -Parent $PSScriptRoot }
    $repo = [System.IO.Path]::GetFullPath($TestSeamRepoRoot).TrimEnd([char]'\') + '\'
    if ($SecretFile.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) { return (& $no "no service was registered: -SecretFile is inside Horde's own folder; put it somewhere that is not in a repository") }
    try {
        return (Use-HordeNoticeLock -Store $st.store -Body {
            $cur = Read-HordeNoticeServices -Store $st.store
            if ($cur.state -cne "known") { return (& $no ("no service was registered: " + $cur.reason)) }
            if ($cur.value.ContainsKey($Name)) { return (& $no ("no service was registered: '" + $Name + "' is registered already; revoke it first to give it a new secret")) }
            if ([System.IO.File]::Exists($SecretFile)) { return (& $no ("no service was registered: " + $SecretFile + " exists; a secret file is always new")) }
            $salt = New-HordeRandomHex -Bytes 16
            $secret = New-HordeRandomHex -Bytes 32
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($SecretFile))
            $made = $false
            try {
                # Made locked and filled through one handle (S1). The file exists from here on, so a later failure removes it.
                New-HordeLockedSecretFile -Path $SecretFile -Text $secret
                $made = $true
                $cur.value[$Name] = [pscustomobject]@{ salt = $salt; hash = (ConvertTo-HordeServiceHash -Salt $salt -Secret $secret); at = (Get-HordeNoticeTime -Now $Now); by = "$($Registrar.label)" }
                Write-HordeNoticeServices -Store $st.store -Services $cur.value
            } catch {
                if ($made) { try { [System.IO.File]::Delete($SecretFile) } catch { } }
                return (& $no ("no service was registered: " + $_.Exception.Message))
            }
            return [pscustomobject]@{ ok = $true; reason = "" }
        })
    } catch { return (& $no ("no service was registered: " + $_.Exception.Message)) }
}

function Remove-HordeNoticeService {
    # Revoke -Name (a PROVEN registrar's act). { ok; reason }.
    param([Parameter(Mandatory = $true)]$Registrar, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name, [string]$HordeHome = "")
    $no = { param([string]$Why) return [pscustomobject]@{ ok = $false; reason = $Why } }
    $st = Get-HordeNoticeStore -HordeHome $HordeHome
    if (-not $st.ok) { return (& $no $st.reason) }
    if ($null -eq $Registrar -or -not $Registrar.ok -or "$($Registrar.label)" -ceq "") { return (& $no "no service was revoked: the registrar is not a proven session") }
    $allowed = @("$($st.settings.serviceRegistrars)".Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -cne "" })
    if ($allowed -cnotcontains "$($Registrar.label)" -or -not (Test-HordeRegistrarLabel -Registrar $Registrar)) { return (& $no ("no service was revoked: only a session whose fleet label is " + ($allowed -join " or ") + " may revoke one, not '" + $Registrar.label + "'")) }
    try {
        return (Use-HordeNoticeLock -Store $st.store -Body {
            $cur = Read-HordeNoticeServices -Store $st.store
            if ($cur.state -cne "known") { return (& $no ("no service was revoked: " + $cur.reason)) }
            if (-not $cur.value.ContainsKey($Name)) { return (& $no ("no service was revoked: '" + $Name + "' is not registered")) }
            $cur.value.Remove($Name)
            Write-HordeNoticeServices -Store $st.store -Services $cur.value
            return [pscustomobject]@{ ok = $true; reason = "" }
        })
    } catch { return (& $no ("no service was revoked: " + $_.Exception.Message)) }
}

function Resolve-HordeServiceSender {
    # The proven sender of a service's notice, in the shape Submit-HordeNotify takes: { ok; reason; sessionId ("service:<name>");
    # label ("service: <name>"); perHour }. Every refusal says the same about an unregistered name and a wrong secret.
    param([AllowEmptyString()][string]$Name, [AllowEmptyString()][string]$SecretFile, [string]$HordeHome = "", [string]$RegistryRoot = (Get-HordeWezfleetRoot), [string[]]$FleetLabels = $null)
    $no = { param([string]$Why) return [pscustomobject]@{ ok = $false; reason = $Why; sessionId = ""; label = ""; perHour = 0 } }
    $same = "no notice was sent: the service name or its secret is not right"
    $st = Get-HordeNoticeStore -HordeHome $HordeHome
    if (-not $st.ok) { return (& $no ("no notice was sent: " + $st.reason)) }
    if ($Name -cnotmatch $script:HordeServiceNamePattern) { return (& $no $same) }
    $bad = Test-HordeServiceName -Name $Name -RegistryRoot $RegistryRoot -FleetLabels $FleetLabels
    if ($bad -cne "") { return (& $no ("no notice was sent: " + $bad)) }
    $all = Read-HordeNoticeServices -Store $st.store
    if ($all.state -cne "known") { return (& $no ("no notice was sent: " + $all.reason)) }
    if (-not $all.value.ContainsKey($Name)) { return (& $no $same) }
    if ($SecretFile.Trim() -ceq "" -or -not [System.IO.File]::Exists($SecretFile)) { return (& $no $same) }
    $open = Test-HordeSecretFileOpen -Path $SecretFile
    if ($open -cne "") { return (& $no ("no notice was sent: " + $open)) }
    try { $secret = ([System.IO.File]::ReadAllText($SecretFile, [System.Text.Encoding]::ASCII)).Trim() } catch { return (& $no $same) }
    if ($secret -cnotmatch '\A[0-9a-f]{64}\z') { return (& $no $same) }
    $rec = $all.value[$Name]
    if (-not (Test-HordeConstantTimeEqual -A (ConvertTo-HordeServiceHash -Salt $rec.salt -Secret $secret) -B $rec.hash)) { return (& $no $same) }
    return [pscustomobject]@{ ok = $true; reason = ""; sessionId = ("service:" + $Name); label = (Get-HordeServiceLabel -Name $Name); perHour = [int]$st.settings.servicePerHour }
}
