# core/Home - where Horde keeps its own files.
#
# ONE VARIABLE, HORDE_HOME, DEFAULTING TO %USERPROFILE%\.horde. Settled by the engine-settings design
# (decision 2) and carried by planning/execution-plan-phase-3.md step 1, which also renames the
# isolation harness's HORDE_ROOT; that rename is not done here. Two settled designs once disagreed on
# the name, and two names would have become two folders (metrics design, follow-up 1).
#
# A PATH, NEVER A SETTING. The environment may say WHERE Horde's files are, so a test can point Horde
# at a folder it created (CONTRIBUTING 9). It may never say what Horde does: no environment variable
# turns metrics on (metrics design, decision 1), because a child inherits its parent's environment.
#
# No Set-StrictMode here: this file is dot-sourced, so a file-scope Set-StrictMode would set the
# caller's mode (see core/Tristate.ps1). The functions run under -Version Latest.

function Get-HordeHome {
    # The absolute path of Horde's home. Not created here: a reader must not make folders.
    #
    # A RELATIVE HORDE_HOME IS REFUSED, not resolved against the current directory: the same command
    # run from two folders would write to two homes, and nothing would say so.
    $set = "$env:HORDE_HOME".Trim()
    if ($set -ne "") {
        if (-not [System.IO.Path]::IsPathRooted($set)) { throw ("HORDE_HOME must be an absolute path, not '" + $set + "'") }
        return [System.IO.Path]::GetFullPath($set)
    }
    $profileDir = "$env:USERPROFILE".Trim()
    if ($profileDir -eq "") { throw "HORDE_HOME is not set and USERPROFILE is empty, so Horde has no home" }
    return (Join-Path $profileDir ".horde")
}
