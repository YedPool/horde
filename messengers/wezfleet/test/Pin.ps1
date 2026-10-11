# Pins this messenger, for every Horde process whose home is -HordeHome, to a folder that is no wezfleet
# checkout - so nothing a test runs under that home can find the fleet's real command on PATH and post
# through it. Run by test\lib\MessengerPins.ps1 for every suite that loads every messenger or starts a
# real horde child; a suite may also run it itself.
#
# HOW: the messenger's own settings file, <home>\settings\messenger-wezfleet.json (core/ModuleSettings.ps1),
# names root as an empty folder inside the home. A root in the settings file wins over the wezfleet
# command on PATH, so the messenger never looks there, and an empty folder is not a checkout, so every
# post and status is unknown and nothing is started. Written by hand it is:
#   { "schemaVersion": 1, "settings": { "root": "<home>\\pinned\\no-wezfleet" } }
# No environment variable can do this: the home says where Horde's files are, never what it does
# (core/Home.ps1), so the pin is a file in a home the test made.
#
# Refuses a home outside the temp folder, so it can never write into a person's real home.
param([Parameter(Mandatory = $true)][string]$HordeHome)
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$full = [System.IO.Path]::GetFullPath($HordeHome)
if (-not $full.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $full.TrimEnd('\') -ieq $tempRoot.TrimEnd('\')) {
    throw ("the wezfleet messenger is pinned only in a home under the temp folder, not '" + $full + "'")
}
$none = Join-Path $full "pinned\no-wezfleet"
[void](New-Item -ItemType Directory -Force -Path $none)
$settingsDir = Join-Path $full "settings"
[void](New-Item -ItemType Directory -Force -Path $settingsDir)
$doc = [pscustomobject][ordered]@{ schemaVersion = 1; settings = [pscustomobject][ordered]@{ root = $none } } | ConvertTo-Json -Compress -Depth 3
[System.IO.File]::WriteAllText((Join-Path $settingsDir "messenger-wezfleet.json"), $doc, (New-Object System.Text.UTF8Encoding($false)))
return $none
