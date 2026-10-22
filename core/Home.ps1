# core/Home - where Horde keeps its own files.
#
# ONE RESOLUTION ORDER, the same in every resolver (this file, and core/home.mjs for node: fleet-db/store.mjs,
# fleet-metrics/home.mjs, hooks/horde-turn-duty.mjs), so one step moves the whole fleet:
#   1. HORDE_HOME, when set. A path, never a setting (below). Tests rely on it (CONTRIBUTING 9).
#   2. the POINTER FILE %USERPROFILE%\.horde-home.json, exactly {"v":1,"hordeHome":"<absolute path>"}, ASCII. It
#      lives outside any home. It is read on EVERY call, so a running session, hook or scheduled task sees a change
#      at its next call: an environment variable set at user level reaches only processes started afterwards, and
#      the fleet would have stayed split between two folders for days.
#   3. %USERPROFILE%\.horde (PowerShell only; node has no default, its comments say why).
# A POINTER THAT IS THERE BUT BAD IS REFUSED, never skipped: unreadable, not JSON, not ASCII, not v 1, no hordeHome,
# a relative path, or a folder that does not exist. Skipping it would send this program to a folder the others do not
# use, and nothing would say so. The message names the file.
#
# ONE VARIABLE, HORDE_HOME. Settled by the engine-settings design (decision 2) and carried by
# planning/execution-plan-phase-3.md step 1, which also renames the isolation harness's HORDE_ROOT; that rename is
# not done here. Two settled designs once disagreed on the name, and two names would have become two folders
# (metrics design, follow-up 1).
#
# A PATH, NEVER A SETTING. The environment may say WHERE Horde's files are, so a test can point Horde
# at a folder it created (CONTRIBUTING 9). It may never say what Horde does: no environment variable
# turns metrics on (metrics design, decision 1), because a child inherits its parent's environment.
#
# No Set-StrictMode here: this file is dot-sourced, so a file-scope Set-StrictMode would set the
# caller's mode (see core/Tristate.ps1). The functions run under -Version Latest.

. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "FileAtomic.ps1")

# THE USER PROFILE. A scheduled task that runs without a loaded profile (S4U) may have no USERPROFILE in its
# environment, and the tasks Horde registers no longer bake the home in, so they must still find the pointer: when
# USERPROFILE is empty the profile folder is asked of the system, as core/home.mjs asks os.homedir(). ASSUMPTION
# (planning/fleet-db-design.md): the system's answer for the account a task runs as is the profile that holds that
# account's pointer. A test replaces this block, so it never asks about the real profile.
$script:HordeProfileFallback = { [System.Environment]::GetFolderPath("UserProfile") }

function Get-HordeProfileDir {
    # The user's profile folder: USERPROFILE, else the system's answer; "" when neither gives one.
    $p = "$env:USERPROFILE".Trim()
    if ($p -eq "") { try { $p = ("" + (& $script:HordeProfileFallback)).Trim() } catch { $p = "" } }
    return $p
}

function Get-HordeHomePointerPath {
    # <profile>\.horde-home.json, or $null when there is no profile folder. The one pointer path rule (core/home.mjs).
    $profileDir = Get-HordeProfileDir
    if ($profileDir -eq "") { return $null }
    return (Join-Path $profileDir ".horde-home.json")
}

function Test-HordeHomeRooted {
    # Whether -Path names its drive or is a UNC path. A path with no drive depends on the current drive, so it is
    # not a home. The same test as core/home.mjs.
    param([string]$Path)
    return ("$Path" -match '\A([A-Za-z]:[\\/]|\\\\[^\\/])')
}

function Read-HordeHomePointer {
    # The pointer's target: { ok = $true; home; file } or { ok = $false; message } when the file is there but bad
    # (the message names it). Not called when the file is absent.
    param([Parameter(Mandatory = $true)][string]$File)
    $bad = { param($why) [pscustomobject]@{ ok = $false; home = ""; file = $File; message = ("the home pointer file " + $File + " is refused: " + $why + "; fix it with horde home set -Path <folder> or remove it with horde home clear") } }
    try { $bytes = [System.IO.File]::ReadAllBytes($File) } catch { return (& $bad ("it cannot be read (" + $_.Exception.Message + ")")) }
    foreach ($b in $bytes) {
        if ($b -gt 0x7E -or ($b -lt 0x20 -and $b -ne 0x09 -and $b -ne 0x0A -and $b -ne 0x0D)) { return (& $bad "it holds a character that is not ASCII") }
    }
    try { $obj = ConvertFrom-HordeJson ([System.Text.Encoding]::UTF8.GetString($bytes)) } catch { return (& $bad "it is not JSON") }
    if ($null -eq $obj -or $obj -isnot [System.Management.Automation.PSCustomObject]) { return (& $bad "it is not a JSON object") }
    $v = $obj.PSObject.Properties["v"]
    if ($null -eq $v -or ($v.Value -isnot [int] -and $v.Value -isnot [long] -and $v.Value -isnot [double]) -or $v.Value -ne 1) { return (& $bad "v is not 1") }
    $h = $obj.PSObject.Properties["hordeHome"]
    if ($null -eq $h -or $h.Value -isnot [string] -or $h.Value.Trim() -eq "") { return (& $bad "hordeHome is missing") }
    $target = $h.Value.Trim()
    if (-not (Test-HordeHomeRooted $target)) { return (& $bad ("hordeHome """ + $target + """ is not an absolute path")) }
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { return (& $bad ("hordeHome """ + $target + """ is not an existing folder")) }
    return [pscustomobject]@{ ok = $true; home = [System.IO.Path]::GetFullPath($target); file = $File; message = "" }
}

function Resolve-HordeHome {
    # { path; source } where source is "HORDE_HOME", "pointer" or "default". Throws with the reason when HORDE_HOME is
    # relative, the pointer is bad, or there is no home at all. Not created here: a reader must not make folders.
    #
    # A RELATIVE HORDE_HOME IS REFUSED, not resolved against the current directory: the same command
    # run from two folders would write to two homes, and nothing would say so. "Relative" is decided by
    # Test-HordeHomeRooted, the same test as the pointer file and core/home.mjs, so a path like "\x" or "C:x"
    # (which IsPathRooted accepts but which depend on the current drive or folder) is refused in both languages.
    $set = "$env:HORDE_HOME".Trim()
    if ($set -ne "") {
        if (-not (Test-HordeHomeRooted $set)) { throw ("HORDE_HOME must be an absolute path, not '" + $set + "'") }
        return [pscustomobject]@{ path = [System.IO.Path]::GetFullPath($set); source = "HORDE_HOME" }
    }
    $pointer = Get-HordeHomePointerPath
    if ($null -eq $pointer) { throw "HORDE_HOME is not set and USERPROFILE is empty, so Horde has no home" }
    if (Test-Path -LiteralPath $pointer) {
        $r = Read-HordeHomePointer -File $pointer
        if (-not $r.ok) { throw $r.message }
        return [pscustomobject]@{ path = $r.home; source = "pointer" }
    }
    return [pscustomobject]@{ path = (Join-Path (Get-HordeProfileDir) ".horde"); source = "default" }
}

function Get-HordeHome {
    # The absolute path of Horde's home (see the order above).
    return (Resolve-HordeHome).path
}

function Set-HordeHomePointer {
    # Write the pointer so the home is -Path, in ONE step (a temp file in the same folder, then a rename over the
    # pointer: a reader sees the old pointer or the new one, never half). Refused: a relative path, a folder that
    # does not exist, a folder without fleet.db (a pointer at the wrong folder would split the data at once), a path
    # that is not plain ASCII (the pointer is). Returns { old; new; file }; old is the home before, or "" when it
    # could not be resolved (a bad pointer being mended).
    param([Parameter(Mandatory = $true)][string]$Path)
    $file = Get-HordeHomePointerPath
    if ($null -eq $file) { throw "USERPROFILE is empty, so there is no place for the home pointer" }
    $p = "$Path".Trim()
    if (-not (Test-HordeHomeRooted $p)) { throw ("the home must be an absolute path, not '" + $p + "'") }
    if ($p -notmatch '\A[\x20-\x7E]+\z' -or $p.Contains('"')) { throw ("the home '" + $p + "' holds a character the pointer file cannot (it is plain ASCII, no double quote)") }
    if (-not (Test-Path -LiteralPath $p -PathType Container)) { throw ("the home '" + $p + "' is not an existing folder") }
    $full = [System.IO.Path]::GetFullPath($p)
    if (-not (Test-Path -LiteralPath (Join-Path $full "fleet.db") -PathType Leaf)) { throw ("the home '" + $full + "' has no fleet.db; run horde db init there first, so the pointer never names a folder the data is not in") }
    $old = ""
    try { $old = (Resolve-HordeHome).path } catch { $old = "" }
    $json = '{"v":1,"hordeHome":"' + $full.Replace('\', '\\') + '"}'
    $temp = $file + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    try {
        [System.IO.File]::WriteAllBytes($temp, [System.Text.Encoding]::ASCII.GetBytes($json))
        Move-HordeFileAtomic -From $temp -To $file
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
    return [pscustomobject]@{ old = $old; new = $full; file = $file }
}

function Clear-HordeHomePointer {
    # Remove the pointer (a no-op when there is none). Returns { removed; file }.
    $file = Get-HordeHomePointerPath
    if ($null -eq $file) { throw "USERPROFILE is empty, so there is no home pointer" }
    $removed = $false
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force; $removed = $true }
    return [pscustomobject]@{ removed = $removed; file = $file }
}
