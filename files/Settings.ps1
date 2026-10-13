# files/Settings.ps1 - every number the files store and `horde files share` can be tuned by, named.
#
# WHY ITS OWN FILE. A refusal that quotes a number ("larger than 1048576 bytes") must quote a number a
# person can find and change, so none is written where it is used. They are declared once, here,
# through core/ModuleSettings.ps1, the one way a module declares settings: a person overrides any of
# them in <HORDE_HOME>\settings\files.json, and a file that fails a check refuses the command with the
# file and the key named. It never falls back to a default the person did not choose.
#
# A FUNCTION, NOT A $script: VARIABLE: this file is loaded inside a command's run block, where $script:
# is the runner's scope (cli/Commands.ps1 has the measurement).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ModuleSettings.ps1")

function Get-HordeFilesSettingsDeclaration {
    # The table. maxFileBytes is 1 MiB by default: the design's cap for one shared file (a phone on a
    # mobile link fetches it whole). Its largest value is 16 MiB, so the cap can be raised and never
    # removed. The store's waits are the decisions store's defaults, which were measured there.
    return (New-HordeModuleSettings -Module "files" -Settings @(
        @{ name = "maxFileBytes"; kind = "whole"; default = 1048576; min = 1; max = 16777216; what = "The largest file that may be shared, in bytes." },
        @{ name = "maxTitleChars"; kind = "whole"; default = 120; min = 1; max = 1000; what = "The longest title a shared file may have, in characters." },
        @{ name = "versionTries"; kind = "whole"; default = 20; min = 1; max = 1000; what = "How many times a share tries for the next version when another share takes it first." },
        @{ name = "leftoverMinAgeSeconds"; kind = "whole"; default = 600; min = 1; max = 86400; what = "How old a dead writer's temporary file must be before it is removed, in seconds." },
        @{ name = "heldReadTries"; kind = "whole"; default = 40; min = 1; max = 1000; what = "How many times a record held open by another process is tried." },
        @{ name = "heldReadWaitMs"; kind = "whole"; default = 50; min = 1; max = 10000; what = "The wait between two tries of a held record, in milliseconds." }
    ))
}

function Get-HordeFilesSettings {
    # The settings in force, one property each. THROWS the findings when the override file is refused:
    # the caller does not proceed, and horde prints which file and which key are wrong.
    param([string]$HordeHome = "")
    $read = Get-HordeModuleSettings -Declaration (Get-HordeFilesSettingsDeclaration) -HordeHome $HordeHome
    if ($read.state -ceq "refused") { throw (@($read.findings) -join [Environment]::NewLine) }
    return $read.values
}
