# test/lib/FleetPin.ps1 - an empty fleet for suites that load the relay channels, so no channel can find
# the machine's real Thrall.
#
# WHY. The chat channel (channels/chat) reads the horde's Thrall through the conversation port, and an
# adapter left to its defaults finds the fleet this machine runs: the fleet root is WEZFLEET_ROOT when it
# is set, else the user's own (core/Roles.ps1, Get-HordeWezfleetRoot). A suite that loads every channel
# and turns a run - or starts a real horde relay run - would then read the real Thrall's words and seal
# them to its test phone. Measured 2026-10-10: test/test-relay-channels.ps1, run once before this pin,
# sent 50 real turns into its own temporary relay folder (deleted with it). So every such suite points
# WEZFLEET_ROOT at an empty folder of its own, first thing, and every child it starts inherits it.
#
# USE, right after the suite's trap line:
#   . (Join-Path $root "test\lib\FleetPin.ps1")
#   $fleetPin = Enter-HordeTestEmptyFleet
#   try { ... } finally { Exit-HordeTestEmptyFleet -Pin $fleetPin }

function Enter-HordeTestEmptyFleet {
    # WEZFLEET_ROOT pointed at a new empty folder under the temp folder. { before; path }.
    $path = Join-Path $env:TEMP ("horde-empty-fleet-" + [guid]::NewGuid().ToString("N"))
    # The registry folder, empty: an adapter reading it finds no Thrall (absent), rather than no registry.
    New-Item -ItemType Directory -Path (Join-Path $path "registry\sessions") -Force | Out-Null
    $pin = [pscustomobject]@{ before = $env:WEZFLEET_ROOT; path = $path }
    $env:WEZFLEET_ROOT = $path
    return $pin
}

function Exit-HordeTestEmptyFleet {
    # WEZFLEET_ROOT put back, and the empty folder removed (only a folder this file made).
    param($Pin)
    if ($null -eq $Pin) { return }
    $env:WEZFLEET_ROOT = $Pin.before
    if ((Split-Path -Leaf $Pin.path) -match '^horde-empty-fleet-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $Pin.path)) { Remove-Item -LiteralPath $Pin.path -Recurse -Force -ErrorAction SilentlyContinue }
}
