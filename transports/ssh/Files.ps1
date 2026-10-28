# transports/ssh/Files.ps1 - the ssh link's own files: how they are written, and who may write them.
#
# WHY A FILE OF ITS OWN (issue #123). authorized_keys, revoked_keys and known_hosts decide what the hub's
# listener admits and which hub a node trusts: a writable authorized_keys admits a key, a writable
# revoked_keys un-revokes one, a writable known_hosts swaps the hub's pin. They were written with no ACL of
# their own, so they inherited their folder's: harmless in the default home (C:\Users\<u>\.horde inherits
# SYSTEM, Administrators and the user), but under a custom HORDE_HOME in %TEMP% each admitted four other
# principals with Modify (review of PR #111, probes K6 and K7). Enrolment (Enroll.ps1) and the listener
# (Listen.ps1) both write them, so the writer lives here, beside the checks:
#   - EVERY WRITE IS THIS USER'S ALONE: the text goes to a file beside the target, that file's ACL is cut
#     to this user (inheritance off, read back), and only then is it renamed over the target in one step
#     (core/FileAtomic.ps1). A rename keeps the file's own ACL, so the target is never, even for a moment,
#     a file another principal may open.
#   - THE LISTENER REFUSES A FILE, OR A FOLDER ABOVE IT, THAT ANOTHER PRINCIPAL MAY WRITE
#     (Get-HordeSshOtherWriters): a folder another principal may write lets it delete or rename the file
#     and put its own in its place, whatever the file's ACL. "Another" is anyone but this user, SYSTEM and
#     the Administrators group: those two can take any file on the machine anyway, so a rule for them
#     closes no door, and Windows' own sshd accepts the same three (its file permission check).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\FileAtomic.ps1")

# The rights that change a file or a folder's contents, its ACL or its owner, or delete it or what it
# holds: WriteData/CreateFiles 0x2, AppendData/CreateDirectories 0x4, WriteExtendedAttributes 0x10,
# DeleteSubdirectoriesAndFiles 0x40, WriteAttributes 0x100, Delete 0x10000, ChangePermissions 0x40000,
# TakeOwnership 0x80000, and the generic write and all bits a raw ACE may carry (0x40000000, 0x10000000).
$script:HordeSshWriteRights = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x40000000 -bor 0x10000000
# SYSTEM and the Administrators group (header).
$script:HordeSshTrustedWriters = @("S-1-5-18", "S-1-5-32-544")

# THE ACLS ARE READ AND WRITTEN BY .NET, NOT THE Get-Acl / Set-Acl CMDLETS (T-0367). Set-Acl asks for
# SeSecurityPrivilege on a key ssh-keygen made, which a non-elevated user lacks, so a non-elevated `horde node init`
# failed; and the cmdlets' module does not load in a Windows PowerShell child of a PowerShell 7 parent (measured
# 2026-10-17, notices/Services.ps1), which is how a suite or a scheduled task may start horde. .NET reads the owner,
# group and access rules (never the audit rules) and writes only the sections the object sets. Windows PowerShell
# has the methods on FileInfo and DirectoryInfo; PowerShell 7 has them as FileSystemAclExtensions.

function Get-HordeSshAcl {
    # -Path's owner and access rules, for a file or a folder.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $di = New-Object System.IO.DirectoryInfo -ArgumentList $Path
        if ($di.PSObject.Methods["GetAccessControl"]) { return $di.GetAccessControl() }
        return [System.IO.FileSystemAclExtensions]::GetAccessControl($di)
    }
    $fi = New-Object System.IO.FileInfo -ArgumentList $Path
    if ($fi.PSObject.Methods["GetAccessControl"]) { return $fi.GetAccessControl() }
    return [System.IO.FileSystemAclExtensions]::GetAccessControl($fi)
}

function Set-HordeSshKeyAcl {
    # The file's ACL: this user alone, inheritance cut. Returns "" when it reads back so, or why not.
    # THE OWNER IS SET ONLY WHEN IT IS NOT ALREADY THIS USER: ssh-keygen's ACL gives the user no WRITE_OWNER, so even
    # setting the same owner is refused, while an owner may always change the access rules. An elevated process may
    # have made the file owned by BUILTIN\Administrators; then it is made this user's, which an elevated one may do.
    param([string]$Path)
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $owner = (Get-HordeSshAcl -Path $Path).GetOwner([System.Security.Principal.SecurityIdentifier])
    if ("$owner" -cne "$me") { $acl.SetOwner($me) }
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, "FullControl", "Allow")))
    $fi = New-Object System.IO.FileInfo -ArgumentList $Path
    if ($fi.PSObject.Methods["SetAccessControl"]) { $fi.SetAccessControl($acl) }
    else { [System.IO.FileSystemAclExtensions]::SetAccessControl($fi, $acl) }
    return (Test-HordeSshKeyAcl -Path $Path)
}

function Test-HordeSshKeyAcl {
    # "" when -Path's ACL is protected and admits this user alone; otherwise why not.
    param([string]$Path)
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $read = Get-HordeSshAcl -Path $Path
    if (-not $read.AreAccessRulesProtected) { return ("the key " + $Path + " inherits access from its folder") }
    $rules = @($read.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    $others = @($rules | Where-Object { "$($_.IdentityReference)" -cne "$me" })
    if ($rules.Count -lt 1 -or $others.Count -gt 0) { return ("the key " + $Path + " admits someone besides this user: " + (@($others | ForEach-Object { "$($_.IdentityReference)" }) -join ", ")) }
    return ""
}

function Get-HordeSshOtherWriters {
    # Who besides this user, SYSTEM and Administrators may write -Path (a file or a folder), or owns it:
    # one "<principal> (<how>)" per finding, empty when nobody. Only rules that apply to -Path itself
    # count: an inherit-only rule (CREATOR OWNER's, say) grants nothing on the object that carries it.
    param([Parameter(Mandatory = $true)][string]$Path)
    $me = "" + [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $ok = @($me) + $script:HordeSshTrustedWriters
    $acl = Get-HordeSshAcl -Path $Path
    $out = New-Object System.Collections.ArrayList
    $owner = "" + $acl.GetOwner([System.Security.Principal.SecurityIdentifier])
    if ($ok -cnotcontains $owner) { [void]$out.Add($owner + " (owns it, so it may change who writes it)") }
    foreach ($r in @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))) {
        if ("$($r.AccessControlType)" -cne "Allow") { continue }
        if ((([int]$r.PropagationFlags) -band 2) -ne 0) { continue }
        if ((([long]$r.FileSystemRights) -band $script:HordeSshWriteRights) -eq 0) { continue }
        $sid = "" + $r.IdentityReference
        if ($ok -ccontains $sid) { continue }
        [void]$out.Add($sid + " (" + $r.FileSystemRights + ")")
    }
    return @($out)
}

function Test-HordeSshOnlyMine {
    # Findings for -Paths and every folder above each up to and including -Top: one per path another
    # principal may write (Get-HordeSshOtherWriters). Empty means none. A path that does not exist is
    # skipped: whether it must exist is the caller's to say.
    param([Parameter(Mandatory = $true)][string[]]$Paths, [Parameter(Mandatory = $true)][string]$Top)
    $topFull = [System.IO.Path]::GetFullPath($Top).TrimEnd('\')
    $seen = New-Object System.Collections.ArrayList
    foreach ($p in $Paths) {
        $cur = [System.IO.Path]::GetFullPath($p).TrimEnd('\')
        while ($true) {
            if (-not $seen.Contains($cur.ToLowerInvariant())) { [void]$seen.Add($cur.ToLowerInvariant()) }
            if ($cur.Equals($topFull, [System.StringComparison]::OrdinalIgnoreCase) -or -not $cur.StartsWith($topFull + "\", [System.StringComparison]::OrdinalIgnoreCase)) { break }
            $cur = Split-Path -Parent $cur
        }
    }
    $out = New-Object System.Collections.ArrayList
    foreach ($s in $seen) {
        if (-not (Test-Path -LiteralPath $s)) { continue }
        $w = @(Get-HordeSshOtherWriters -Path $s)
        if ($w.Count -gt 0) { [void]$out.Add($s + " may be written by another principal: " + ($w -join ", ")) }
    }
    return @($out)
}

function Read-HordeSshLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    return @([System.IO.File]::ReadAllLines($Path) | Where-Object { "$_".Trim() -ne "" })
}

function Write-HordeSshLines {
    # The whole file at once, LF line ends, ASCII: sshd reads these. Written beside it, made this user's
    # alone, and renamed over it in one step (header; core/FileAtomic.ps1), never rewritten in place: a
    # kill mid-write of an in-place write left authorized_keys empty, every device locked out (review of
    # PR #111, N5).
    param([string]$Path, [string[]]$Lines)
    $text = ""
    foreach ($l in @($Lines)) { $text = $text + $l + "`n" }
    $tmp = $Path + ".tmp-" + [System.IO.Path]::GetRandomFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $text, [System.Text.Encoding]::ASCII)
        $acl = Set-HordeSshKeyAcl -Path $tmp
        if ($acl -ne "") { throw ("the new " + (Split-Path -Leaf $Path) + " could not be made this user's alone: " + $acl) }
        Move-HordeFileAtomic -From $tmp -To $Path
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}
