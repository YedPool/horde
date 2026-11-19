# tools/MutateInstalled.ps1 - tools\Mutate.ps1 refuses to run from the INSTALLED Horde (T-0466).
#
# WHY. Mutate.ps1 applies each mutant to a copy of the tree it lives in, and the suite it runs reads that
# tree. Started from the installed copy - the clone every session runs `horde` from - it works on the
# very code every Orc is running, and a run cut off part way can leave the installed main broken. Every
# brief says "use your clone's tools\Mutate.ps1, never the bin copy"; this makes the tool say it.
#
# HOW THE INSTALLED COPY IS RECOGNISED. Two signals, either one refuses; neither names a person's folder.
#   1. THE SHIM. The `horde` command is a small horde.cmd that launches <its own folder>\horde\horde.ps1
#      (%~dp0horde\horde.ps1). A folder that a horde.cmd beside it launches IS the installed copy,
#      wherever it sits and whatever it is called: that is what "the copy every session runs" means.
#      A shim that names the folder by absolute path is read the same way.
#   2. THE DEFAULT PLACE. <profile>\bin\horde, the folder cli/ServicesBin.ps1 follows when no
#      installedCliFolder is set (Get-HordeInstalledCliPath). The profile is asked of the machine, never
#      written into this file. It catches an install whose shim is missing or unreadable.
# A clone anywhere else (a worktree under horde-worktrees, a scratch copy) matches neither and runs as
# before. NOT COVERED: a clone reached through a junction or a link, and a folder the installedCliFolder
# setting moves where no shim points - the shim is the truth of what is run, and a person who has moved
# the install has a shim that names it.
#
# No Set-StrictMode here: this file is dot-sourced.

function Get-HordeMutateInstalledShimText {
    # The text of horde.cmd beside the folder, or "" when there is none or it cannot be read. A shim is a
    # few lines; one over 64 KB is not one.
    param([Parameter(Mandatory = $true)][string]$Parent)
    $shim = Join-Path $Parent "horde.cmd"
    try {
        if (-not (Test-Path -LiteralPath $shim -PathType Leaf)) { return "" }
        if ((Get-Item -LiteralPath $shim).Length -gt 65536) { return "" }
        return [System.IO.File]::ReadAllText($shim)
    } catch { return "" }
}

function Get-HordeMutateInstalledRefusal {
    # Why Mutate.ps1 must not run from -Repo, in plain words, or "" when it may. PURE apart from reading
    # the one shim file. -ProfileDir is the profile folder (a test gives its own; empty asks the machine).
    param([Parameter(Mandatory = $true)][string]$Repo, [string]$ProfileDir = "")
    $full = [System.IO.Path]::GetFullPath($Repo).TrimEnd('\', '/')
    $parent = Split-Path -Parent $full
    $leaf = Split-Path -Leaf $full
    $why = ""
    if ($parent -and $leaf) {
        $text = Get-HordeMutateInstalledShimText -Parent $parent
        if ($text -ne "") {
            $bySibling = '(?i)%~dp0\\?' + [regex]::Escape($leaf) + '\\horde\.ps1'
            $byFull = [regex]::Escape($full + '\horde.ps1')
            if ($text -match $bySibling -or $text -imatch $byFull) { $why = "the horde command (" + (Join-Path $parent "horde.cmd") + ") runs it" }
        }
    }
    if ($why -eq "") {
        $prof = "" + $ProfileDir
        if ($prof.Trim() -eq "") { $prof = "" + $env:USERPROFILE }
        if ($prof.Trim() -eq "") { try { $prof = [System.Environment]::GetFolderPath("UserProfile") } catch { $prof = "" } }
        if ($prof.Trim() -ne "") {
            $default = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($prof, "bin", "horde")).TrimEnd('\', '/')
            if ($default -ieq $full) { $why = "it is the bin\horde folder under the profile" }
        }
    }
    if ($why -eq "") { return "" }
    return ("tools\Mutate.ps1 will not run from the installed Horde, " + $full + " (" + $why + "): it breaks the code it lives in on purpose, one way at a time, and a run cut off there can leave the copy every session runs broken. Run the tools\Mutate.ps1 of your own clone instead (a worktree made from origin/main). Nothing was mutated and nothing was written.")
}
