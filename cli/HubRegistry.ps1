# cli/HubRegistry - the hub's register of enrolled nodes: one file per device, written by `horde hub
# enroll` and `horde hub revoke`, read by `horde listen` and `horde hub serve`.
#
# WHY A REGISTER OF ITS OWN (issue #144, item 3; issue #147, item 4; remote plan R13b, "registry entries
# written by horde hub enroll"). Before it, the transport's own file of admitted keys was the only
# record of whom the hub admitted, so a line written there by hand - under any device id - was
# admitted by the transport's server and believed by the hub. Now two records, written together by the enrolment verbs and
# by nothing else, must agree before anything is admitted:
#   - `horde listen` serves a key line only for a device this register holds, live, with that same key
#     (the listener's Health re-checks it every second and stops on a line it does not hold);
#   - `horde hub serve` binds a dialled link only to a device this register holds, live, AND whose key
#     the transport still holds, unrevoked and unexpired (Test-HordeHubAdmits) - checked when the link's
#     preamble is read and again before every request on it, so a revoke ends the link mid-round
#     (issue #124).
# LIVE means: an entry that reads (schema/hub-enrolment.v1), names its own device, is not revoked, and
# is not past its expiry.
#
# ORDER OF WRITES, EACH FAILING CLOSED. Enrol: the transport first, then the register; a register that
# could not be written leaves a key line the listener refuses to serve, and the message says to enrol
# again. Revoke: the register first, then the transport; a transport that could not be written leaves a
# revoked entry that the hub refuses to bind and the listener stops on.
#
# EACH FILE IS THIS USER'S ALONE (issue #123's rule for the files that decide admission): written beside
# its name with its ACL cut to this user, then renamed over it in one step (core/FileAtomic.ps1), so it is
# never readable or writable by another principal, not even for a moment.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeHubRegistryDevicePattern = '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'

function Get-HordeHubRegistryRoot {
    # The register's folder: <home>\hub\nodes.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return (Join-Path $HordeHome "hub\nodes")
}

function Get-HordeHubEnrolmentPath {
    # One device's entry: <home>\hub\nodes\<deviceId>.json. Only a device id names a file.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$DeviceId)
    if ($DeviceId -cnotmatch $script:HordeHubRegistryDevicePattern) { throw ("not a device id: '" + $DeviceId + "'") }
    return (Join-Path (Get-HordeHubRegistryRoot -HordeHome $HordeHome) ($DeviceId + ".json"))
}

function ConvertTo-HordeHubRegistryTime {
    # A UTC time as the register writes it: yyyy-MM-ddTHH:mm:ssZ.
    param([Parameter(Mandatory = $true)][datetime]$At)
    return $At.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Test-HordeHubExpired {
    # Is an enrolment that runs to -Expires (YYYYMMDD) over at -Now? The transport's own rule, which its
    # adapter documents: a key dated YYYYMMDD is refused from 00:00 of that day, local time, so the
    # register reads its expiry the same way. A date that does not parse is over.
    param([string]$Expires, [Parameter(Mandatory = $true)][datetime]$Now)
    $d = [datetime]::MinValue
    if (-not [datetime]::TryParseExact("$Expires", "yyyyMMdd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { return $true }
    return ($Now.ToLocalTime().Date -ge $d.Date)
}

function Set-HordeHubRegistryAcl {
    # -Path's ACL: this user alone, inheritance cut. Throws when it does not read back so.
    param([Parameter(Mandatory = $true)][string]$Path)
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($me)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, "FullControl", "Allow")))
    Set-Acl -LiteralPath $Path -AclObject $acl
    $read = Get-Acl -LiteralPath $Path
    $rules = @($read.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    if (-not $read.AreAccessRulesProtected -or $rules.Count -ne 1 -or "$($rules[0].IdentityReference)" -cne "$me") { throw ("the register file " + $Path + " could not be made this user's alone") }
}

function Write-HordeHubEnrolment {
    # Write one entry, checked first, this user's alone, renamed into place in one step. Returns the path.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)]$Entry)
    $found = @(Test-HordeSchema -Value $Entry -Schema (Get-HordeSchema -Name "hub-enrolment.v1"))
    if ($found.Count -gt 0) { throw ("this register entry is not one to write: " + ($found -join "; ")) }
    $path = Get-HordeHubEnrolmentPath -HordeHome $HordeHome -DeviceId "$($Entry.deviceId)"
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    $tmp = $path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    try {
        [System.IO.File]::WriteAllText($tmp, ($Entry | ConvertTo-Json -Compress), [System.Text.Encoding]::ASCII)
        Set-HordeHubRegistryAcl -Path $tmp
        Move-HordeFileAtomic -From $tmp -To $path
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    return $path
}

function Read-HordeHubEnrolment {
    # One device's entry: known, the entry; absent when there is no file; unknown with the reason when it
    # cannot be read, fails the schema, or names another device than its file.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$DeviceId)
    $path = Get-HordeHubEnrolmentPath -HordeHome $HordeHome -DeviceId $DeviceId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-HordeAbsent -Note ("device " + $DeviceId + " is not in the hub's register (" + $path + " does not exist): enrol it with horde hub enroll")) }
    $e = $null
    try { $e = Read-HordeSharedText -Path $path | ConvertFrom-Json } catch { return (New-HordeUnknown -Reason ("the register entry " + $path + " could not be read") -ErrorRecord $_) }
    if ($null -eq $e) { return (New-HordeUnknown -Reason ("the register entry " + $path + " is empty")) }
    $found = @(Test-HordeSchema -Value $e -Schema (Get-HordeSchema -Name "hub-enrolment.v1"))
    if ($found.Count -gt 0) { return (New-HordeUnknown -Reason ("the register entry " + $path + " is not one to trust: " + ($found -join "; "))) }
    if ("$($e.deviceId)" -cne $DeviceId) { return (New-HordeUnknown -Reason ("the register entry " + $path + " names device " + $e.deviceId + ", not " + $DeviceId)) }
    return (New-HordeKnown -Value $e)
}

function Add-HordeHubEnrolment {
    # Record that -Transport enrolled -DeviceId with -Key until -Expires. A fresh entry: a device enrolled
    # again (a renewal, or a new key after a revoke) is written whole, without a revokedAt.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$DeviceId, [Parameter(Mandatory = $true)][string]$Transport, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][string]$Expires, $Now = $null)
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    $entry = [pscustomobject][ordered]@{ schemaVersion = 1; deviceId = $DeviceId; transport = $Transport; key = $Key; expires = $Expires; enrolledAt = (ConvertTo-HordeHubRegistryTime -At $Now) }
    return (Write-HordeHubEnrolment -HordeHome $HordeHome -Entry $entry)
}

function Set-HordeHubEnrolmentRevoked {
    # Mark -DeviceId's entry revoked at -Now. Returns "" when it is (or there was no entry: a device the
    # register never held is refused anyway), or why it could not be.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$DeviceId, $Now = $null)
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    $r = Read-HordeHubEnrolment -HordeHome $HordeHome -DeviceId $DeviceId
    if ($r.state -ceq "absent") { return "" }
    if ($r.state -cne "known") { return ("the hub's register entry for device " + $DeviceId + " cannot be read, so it cannot be marked revoked: " + $r.reason) }
    $e = $r.value
    if ($null -ne $e.PSObject.Properties["revokedAt"]) { return "" }
    $e | Add-Member -NotePropertyName revokedAt -NotePropertyValue (ConvertTo-HordeHubRegistryTime -At $Now)
    $null = Write-HordeHubEnrolment -HordeHome $HordeHome -Entry $e
    return ""
}

function Get-HordeHubEnrolledKey {
    # The key the register holds for -DeviceId when its enrolment is live at -Now: known, the key; absent
    # when the register does not hold the device; unknown, with the reason, when the entry cannot be
    # trusted, is revoked or is past its expiry.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$DeviceId, $Now = $null)
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    if ($DeviceId -cnotmatch $script:HordeHubRegistryDevicePattern) { return (New-HordeUnknown -Reason ("'" + $DeviceId + "' is not a device id")) }
    $r = Read-HordeHubEnrolment -HordeHome $HordeHome -DeviceId $DeviceId
    if ($r.state -cne "known") { return $r }
    $e = $r.value
    if ($null -ne $e.PSObject.Properties["revokedAt"]) { return (New-HordeUnknown -Reason ("device " + $DeviceId + " was revoked at " + $e.revokedAt)) }
    if (Test-HordeHubExpired -Expires "$($e.expires)" -Now $Now) { return (New-HordeUnknown -Reason ("device " + $DeviceId + "'s enrolment ran to " + $e.expires + " and is over: enrol it again with horde hub enroll")) }
    return (New-HordeKnown -Value "$($e.key)")
}

function Get-HordeHubLiveKeys {
    # Every device the register holds live at -Now, as a hashtable: device id -> its key. What the
    # listener holds its admitted key lines to (transports/Listener.ps1). An entry that is not live, or cannot be
    # read, is left out: it admits nothing.
    param([Parameter(Mandatory = $true)][string]$HordeHome, $Now = $null)
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    $out = @{}
    $dir = Get-HordeHubRegistryRoot -HordeHome $HordeHome
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $out }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter "*.json" | Where-Object { $_.Name -cmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.json\z' })) {
        $id = $f.Name.Substring(0, 36)
        $k = Get-HordeHubEnrolledKey -HordeHome $HordeHome -DeviceId $id -Now $Now
        if ($k.state -ceq "known") { $out[$id] = $k.value }
    }
    return $out
}

function Test-HordeHubAdmits {
    # May a link be bound to -DeviceId at -Now? "" when it may; otherwise why not. Both records must agree:
    # the register holds the device live, and -Enrollment - the transport's enrolment, transports/Port.ps1 -
    # still holds a key for it, unrevoked and unexpired, and that key is the register's.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$DeviceId, [Parameter(Mandatory = $true)]$Enrollment, $Now = $null)
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    $k = Get-HordeHubEnrolledKey -HordeHome $HordeHome -DeviceId $DeviceId -Now $Now
    if ($k.state -cne "known") { return ("device " + $DeviceId + " is not enrolled: " + $k.reason) }
    $t = $null
    try { $t = & $Enrollment.hubEnrolled $HordeHome $DeviceId $Now } catch { return ("device " + $DeviceId + "'s enrolment could not be checked with the " + $Enrollment.name + " transport: " + $_.Exception.Message) }
    if ($null -eq $t -or -not $t.ok) { return ("device " + $DeviceId + " is not enrolled with the " + $Enrollment.name + " transport: " + "$($t.reason)") }
    if ("$($t.line)" -cne "$($k.value)") { return ("device " + $DeviceId + " holds another key with the " + $Enrollment.name + " transport than the one the hub's register enrolled") }
    return ""
}
