# test/lib/TestProfile.ps1 - the one way a suite makes a fake profile for a child (T-0470).
#
# A suite that hands a child a USERPROFILE of its own makes that folder with New-HordeTestProfile, which
# also makes AppData\Local and AppData\Roaming inside it. Without them, Windows PowerShell 5.1 finds no
# local application data folder under USERPROFILE and gets "" for it, so a 5.1 child that lives about
# 20 s saves its module analysis cache as a RELATIVE path - into its working folder, which is often the
# repo root: Microsoft\Windows\PowerShell\ModuleAnalysisCache (T-0411, measured 2026-11-11; PowerShell 7
# makes the folder itself and is not affected). A profile a test keeps empty or absent on purpose is not
# made here.
#
# Loaded by test/lib/Suite.ps1, so every suite has it, and by test/lib/WindowProbe.ps1, whose scenario
# helpers make a profile for the commands they start.

function New-HordeTestProfile {
    # Make -Path (and any missing parents) with AppData\Local and AppData\Roaming inside; return -Path.
    param([Parameter(Mandatory = $true)][string]$Path)
    foreach ($d in @($Path, (Join-Path $Path "AppData\Local"), (Join-Path $Path "AppData\Roaming"))) {
        [void][System.IO.Directory]::CreateDirectory($d)
    }
    return $Path
}
