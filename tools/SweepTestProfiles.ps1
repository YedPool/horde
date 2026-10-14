# tools/SweepTestProfiles.ps1 - removes the test-browser profile folders Horde's own suites leave in
# %TEMP% when a suite is killed outright. Run by the POST-MERGE NET only, never by a suite.
#
#   powershell -NoProfile -File tools\SweepTestProfiles.ps1            # sweep %TEMP%
#   powershell -NoProfile -File tools\SweepTestProfiles.ps1 -WhatIf    # list, delete nothing
#   powershell -NoProfile -File tools\SweepTestProfiles.ps1 -Root <folder standing in for %TEMP%>
#
# WHY. test/lib/Browser.ps1 (PR 288) puts every test browser in a kill-on-close job of its suite, so the
# browser dies with the suite whatever way the suite ends. But a suite killed outright (taskkill /F, its
# window closed) runs no code, so the profile folder it made under %TEMP% stays. 130 horde-cf-accounts-*
# folders had piled up between 2026-10-11 and 2026-10-14. Browser.ps1's header rejected a sweeper AS THE
# FIX (it would hide the leak); with the leak fixed, the review of PR 288 asked for one for the single
# exit no code can clean, and it was ruled (2026-10-14) to run in the post-merge net only, so no suite
# can ever remove a folder another suite running beside it is using.
#
# WHAT IS REMOVED - all of these, and nothing else:
#   - a DIRECT child folder of -Root (default: %TEMP%), never a file, never anything deeper by name;
#   - whose name matches one of $script:HordeSweepProfilePatterns IN FULL (anchored, case-sensitive:
#     the suites name them from [guid]::ToString("N"), lowercase hex of a fixed length), so a near miss
#     (horde-cf-accountsX, a non-hex or shorter suffix, another prefix) is never touched;
#   - that is not a link (junction or symbolic link): a link is skipped, never followed, never removed;
#   - whose newest write anywhere inside (the folder's own time does not change when a file deep in a
#     browser profile does) is older than 24 hours;
#   - whose name appears in no running process's command line. A browser names its profile in
#     --user-data-dir=<path>; the folder's NAME is matched rather than the path because %TEMP% can be
#     spelled long or short (8.3), and the name is unique (32 or 12 random hex). Any mention counts,
#     not only --user-data-dir: a folder some process names is skipped, which can only keep more.
#     A process whose command line this user cannot read (another user's, an elevated one's) is not
#     seen; Horde's suites run as this user. When the process list cannot be read at all, nothing is
#     removed.
# Removal walks the folder itself and deletes a link INSIDE it as a link (the link goes, its target is
# never entered), so nothing outside the folder is ever touched.
#
# Every matching folder is reported: REMOVED (or WOULD REMOVE under -WhatIf) or SKIPPED with the reason.
# Folders that do not match are not listed (%TEMP% holds thousands). The last line says the counts.
# It always exits 0: a folder it could not remove is reported, and the next net tries again.

param(
    [string]$Root = "",
    [switch]$WhatIf
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
# An error no step below expected (the root unreadable, say) is said, and the net carries on: exit 0.
trap { Write-Output ("sweep stopped: " + $_.Exception.Message); exit 0 }

# Every top-level folder a Horde suite or test launcher makes under %TEMP% for a browser profile (and
# the empty fleet below), with where it is made. A new launcher that leaves its own folder adds its
# pattern here.
$script:HordeSweepProfilePatterns = @(
    '\Ahorde-browser-[0-9a-f]{32}\z',             # test/lib/Browser.ps1, Start-HordeTestBrowser with no -Parent
    '\Ahorde-browser-cleanup-[0-9a-f]{32}\z',     # test/test-browser-cleanup.ps1, its browsers' -Parent
    '\Ahorde-cf-accounts-[0-9a-f]{12}\z',         # the hosted relay's accounts suite (its -Parent for the browser)
    '\Ahorde-pwa-browser-[0-9a-f]{32}\z',         # surfaces/pwa/test/test-pwa-browser.ps1
    '\Ahorde-decisions-browser-[0-9a-f]{32}\z',   # test/test-decisions-page-browser.ps1
    # Not a browser profile, but the same leak by the same exit: test/lib/FleetPin.ps1's empty fleet
    # (WEZFLEET_ROOT for a suite), about 40 left by killed suites (found 2026-10-14). A suite passes it
    # to its children by environment, not command line, so the in-use check cannot see it; the age
    # rule covers it (no suite runs for a day: the net stops one at 45 minutes).
    '\Ahorde-empty-fleet-[0-9a-f]{32}\z'          # test/lib/FleetPin.ps1, Enter-HordeTestEmptyFleet
)
$script:HordeSweepMaxAgeHours = 24
$script:HordeSweepLink = [System.IO.FileAttributes]::ReparsePoint

function Test-HordeSweepName {
    param([string]$Name)
    foreach ($p in $script:HordeSweepProfilePatterns) { if ($Name -cmatch $p) { return $true } }
    return $false
}

function Test-HordeSweepYoung {
    # Is anything in the tree (the folder, or any entry under it) written within the cutoff? A link
    # inside is neither entered nor counted: it holds no data of the folder's, and its target is not
    # the folder's to judge.
    param([System.IO.DirectoryInfo]$Dir, [datetime]$CutoffUtc)
    if ($Dir.LastWriteTimeUtc -ge $CutoffUtc) { return $true }
    foreach ($e in $Dir.GetFileSystemInfos()) {
        if (($e.Attributes -band $script:HordeSweepLink) -ne 0) { continue }
        if ($e.LastWriteTimeUtc -ge $CutoffUtc) { return $true }
        if ($e -is [System.IO.DirectoryInfo] -and (Test-HordeSweepYoung -Dir $e -CutoffUtc $CutoffUtc)) { return $true }
    }
    return $false
}

function Remove-HordeSweepTree {
    # Delete the folder's contents and then the folder. A link is deleted as a link: a directory link
    # with Directory.Delete(non-recursive), which removes the link and never its target's contents.
    param([System.IO.DirectoryInfo]$Dir)
    foreach ($e in $Dir.GetFileSystemInfos()) {
        if ($e -is [System.IO.DirectoryInfo]) {
            if (($e.Attributes -band $script:HordeSweepLink) -ne 0) { [System.IO.Directory]::Delete($e.FullName, $false) }
            else { Remove-HordeSweepTree -Dir $e }
        } else {
            $e.Attributes = [System.IO.FileAttributes]::Normal
            $e.Delete()
        }
    }
    $Dir.Attributes = [System.IO.FileAttributes]::Directory
    [System.IO.Directory]::Delete($Dir.FullName, $false)
}

if ($Root -eq "") { $Root = [System.IO.Path]::GetTempPath() }
$shown = [System.IO.Path]::GetFullPath($Root)
# LONG PATHS. A browser profile nests deep (cf-accounts\horde-browser-<32 hex>\Default\...), and past
# 260 characters .NET Framework refuses a plain path ("The specified path, file name, or both are too
# long", measured 2026-10-14 by this tool's suite under a long %TEMP%). The \\?\ form has no such limit
# (.NET 4.6.2 and later), so the walk runs on it; what is printed is the plain path.
$long = $(if ($shown.StartsWith("\\?\")) { $shown } elseif ($shown.StartsWith("\\")) { "\\?\UNC\" + $shown.Substring(2) } else { "\\?\" + $shown })
$rootInfo = New-Object System.IO.DirectoryInfo -ArgumentList $long
$mode = $(if ($WhatIf) { " (-WhatIf: nothing is deleted)" } else { "" })
Write-Output ("sweeping Horde test-browser profiles in " + $shown + $mode)
if (-not $rootInfo.Exists) {
    Write-Output ("swept " + $shown + ": 0 removed, 0 skipped (the folder does not exist)")
    exit 0
}

$cmdLines = $null
try { $cmdLines = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop | ForEach-Object { "" + $_.CommandLine } | Where-Object { $_ -ne "" }) }
catch { $cmdLines = $null }

$cutoff = [datetime]::UtcNow.AddHours(-$script:HordeSweepMaxAgeHours)
$removed = 0; $skipped = 0
foreach ($d in @($rootInfo.GetDirectories() | Sort-Object Name)) {
    $name = $d.Name
    if (-not (Test-HordeSweepName -Name $name)) { continue }
    $why = ""
    try {
        if (($d.Attributes -band $script:HordeSweepLink) -ne 0) { $why = "a link (junction or symbolic link): never followed or removed" }
        elseif ($null -eq $cmdLines) { $why = "the process list could not be read, so whether the folder is in use is not known" }
        elseif (@($cmdLines | Where-Object { $_.IndexOf($name, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0) { $why = "in use: a running process names it in its command line" }
        elseif (Test-HordeSweepYoung -Dir $d -CutoffUtc $cutoff) { $why = "written within the last " + $script:HordeSweepMaxAgeHours + " hours" }
    } catch { $why = "could not be read: " + $_.Exception.Message }
    if ($why -ne "") { Write-Output ("SKIPPED " + $name + ": " + $why); $skipped++; continue }
    if ($WhatIf) { Write-Output ("WOULD REMOVE " + $name); $removed++; continue }
    try {
        Remove-HordeSweepTree -Dir $d
        Write-Output ("REMOVED " + $name); $removed++
    } catch {
        $d.Refresh()
        Write-Output ("SKIPPED " + $name + ": could not remove it" + $(if ($d.Exists) { " (partly removed)" } else { "" }) + ": " + $_.Exception.Message)
        $skipped++
    }
}
$verb = $(if ($WhatIf) { " would be removed, " } else { " removed, " })
Write-Output ("swept " + $shown + ": " + $removed + $verb + $skipped + " skipped")
exit 0
