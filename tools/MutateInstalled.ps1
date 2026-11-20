# tools/MutateInstalled.ps1 - tools\Mutate.ps1 refuses to run from the INSTALLED Horde (T-0466).
#
# WHY. Mutate.ps1 applies each mutant to a copy of the tree it lives in, and the suite it runs reads that
# tree. Started from the installed copy - the clone every session runs `horde` from - it works on the
# very code every Orc is running, and a run cut off part way can leave the installed main broken. Every
# brief says "use your clone's tools\Mutate.ps1, never the bin copy"; this makes the tool say it.
#
# HOW THE INSTALLED COPY IS RECOGNISED. Two signals, either one refuses; neither names a person's folder.
#   1. THE SHIM. The `horde` command is a small horde.cmd whose launch line is
#        powershell.exe ... -File "%~dp0horde\horde.ps1" %*
#      A folder that a horde.cmd beside it launches that way IS the installed copy, wherever it sits and
#      whatever it is called: that is what "the copy every session runs" means. Read as the shim really
#      launches, not as text that merely mentions the folder:
#        - only a line that is not a comment (rem, ::) counts, so a note or a cd naming a clone does not
#          make that clone the install;
#        - the path must follow -File and end in \horde.ps1;
#        - it is %~dp0<folder>, %~dp0.\<folder> or %~dp0\<folder>, or the folder's absolute path, and /
#          is read as \ ;
#        - %USERPROFILE% in the path is read as the profile folder (a moved install).
#      NOT read: a shim that sets a variable and launches through it, or any other launch form. Such a
#      shim is not recognised by this signal; the default place below still catches the usual install.
#   2. THE DEFAULT PLACE. <profile>\bin\horde, the folder cli/ServicesBin.ps1 follows when no
#      installedCliFolder is set (Get-HordeInstalledCliPath). The profile is asked of the MACHINE first,
#      as that file asks it, and the USERPROFILE variable is used only when the machine gives nothing.
#      It catches an install whose shim is missing or unreadable.
# A clone anywhere else (a worktree under horde-worktrees, a scratch copy) matches neither and runs as
# before.
#
# NOT COVERED, stated so a reader can disagree:
#   - FAILS OPEN when the profile cannot be read and no shim names the folder: with neither the machine
#     nor USERPROFILE giving a profile, the default place cannot be worked out, so nothing is refused
#     (test-mutate checks this as a CONTROL). That is deliberate: refusing would stop every ordinary
#     clone on a machine with no profile. Closing it would take a fixed record of where the install is
#     (for instance a marker file the install writes), which this tool does not have.
#   - A clone reached through a junction or a symbolic link: its path is compared as given. Covering it
#     would take the real path, which is a P/Invoke (GetFinalPathNameByHandle) this tool does not carry.
#   - The setting installedCliFolder (<HORDE_HOME>\settings\services.json): it is not read. Covering it
#     would take the settings loader (core/ModuleSettings.ps1 and what it loads), which would add that
#     chain to every file this tool copies. A person who moved the install has a shim that names it.
#
# No Set-StrictMode here: this file is dot-sourced.

# THE MACHINE'S ANSWER FOR THE PROFILE, in one block so a test can replace it (as core/Home.ps1 does for
# its fallback) and never ask about the real profile.
$script:HordeMutateProfileProbe = { [System.Environment]::GetFolderPath("UserProfile") }

function Get-HordeMutateProfileDir {
    # The profile folder: the machine's answer, else USERPROFILE; "" when neither gives one.
    $p = ""
    try { $p = ("" + (& $script:HordeMutateProfileProbe)).Trim() } catch { $p = "" }
    if ($p -eq "") { $p = ("" + $env:USERPROFILE).Trim() }
    return $p
}

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

function Test-HordeMutateInstalledShimLaunches {
    # Whether the shim's text launches the folder named by -Full and -Leaf (see the header). PURE.
    param([string]$Text, [Parameter(Mandatory = $true)][string]$Full, [Parameter(Mandatory = $true)][string]$Leaf, [string]$ProfileDir = "")
    $t = ("" + $Text).Replace('/', '\')
    if ($ProfileDir -ne "") { $t = $t -ireplace '%USERPROFILE%', $ProfileDir.Replace('$', '$$') }
    $launch = '-File\s+"?(?:%~dp0(?:\.?\\)?' + [regex]::Escape($Leaf) + '|' + [regex]::Escape($Full) + ')\\horde\.ps1(?=["\s]|$)'
    foreach ($line in @($t -split '\r?\n')) {
        if ($line.TrimStart() -match '^(rem(\s|$)|::)') { continue }
        if ($line -match $launch) { return $true }
    }
    return $false
}

function Get-HordeMutateInstalledRefusal {
    # Why Mutate.ps1 must not run from -Repo, in plain words, or "" when it may. PURE apart from reading
    # the one shim file. -ProfileDir is the profile folder (a test gives its own; empty asks the machine).
    param([Parameter(Mandatory = $true)][string]$Repo, [string]$ProfileDir = "")
    try { $full = [System.IO.Path]::GetFullPath($Repo).TrimEnd('\', '/') } catch {
        return ("tools\Mutate.ps1 cannot tell whether " + ($Repo -replace '[^\x20-\x7E]', '?') + " is the installed Horde (" + $_.Exception.Message + "), so it will not run from there. Run the tools\Mutate.ps1 of your own clone instead. Nothing was mutated and nothing was written.")
    }
    $prof = ("" + $ProfileDir).Trim()
    if ($prof -eq "") { $prof = Get-HordeMutateProfileDir }
    # .NET, not Split-Path: Split-Path -Parent throws for a drive root ("C:"), which has no parent.
    $parent = [System.IO.Path]::GetDirectoryName($full)
    $leaf = [System.IO.Path]::GetFileName($full)
    $why = ""
    if ($parent -and $leaf) {
        $text = Get-HordeMutateInstalledShimText -Parent $parent
        if ($text -ne "" -and (Test-HordeMutateInstalledShimLaunches -Text $text -Full $full -Leaf $leaf -ProfileDir $prof)) {
            $why = "the horde command (" + (Join-Path $parent "horde.cmd") + ") runs it"
        }
    }
    if ($why -eq "" -and $prof -ne "") {
        $default = ""
        try { $default = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($prof, "bin", "horde")).TrimEnd('\', '/') } catch { $default = "" }
        if ($default -ne "" -and $default -ieq $full) { $why = "it is the bin\horde folder under the profile" }
    }
    if ($why -eq "") { return "" }
    return ("tools\Mutate.ps1 will not run from the installed Horde, " + $full + " (" + $why + "): it breaks the code it lives in on purpose, one way at a time, and a run cut off there can leave the copy every session runs broken. Run the tools\Mutate.ps1 of your own clone instead (a worktree made from origin/main). Nothing was mutated and nothing was written.")
}
