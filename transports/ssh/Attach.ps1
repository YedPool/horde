# transports/ssh/Attach.ps1 - the one builder of the command a hub forces on an enrolled device's key
# (remote plan R17b; R17a's listener and its tests load this file and define no builder of their own).
# Self-contained: it loads nothing, so R17a can dot-source it without the enrolment code.
#
# WHY cli\attach.ps1 AND NOT horde.ps1 attach (R17a's measurement, 2026-10-07): a top-level $input in
# horde.ps1 made every horde command wait at exit for stdin to end while stdin was an open pipe
# (PowerShell 5.1 waits for EOF), so the forced command is a script of its own.
# WHY restrict AND command= ON EVERY KEY ARE THE WHOLE GUARD: the listener runs no ForceCommand, since a
# ForceCommand overrides each key's command= (measured, R17a). Add-HordeSshEnrolment writes both, always.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

# System32's Windows PowerShell, by its absolute path: never a PATH lookup in a line sshd runs.
$script:HordeSshAttachPowerShell = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")

function Get-HordeSshAttachCommand {
    # The forced command for device -DeviceId, Horde installed at -HordeRoot:
    #   <System32>\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File <root>\cli\attach.ps1 -Device <id>
    # It sits unquoted inside the key's command="...", so a root holding a space or a quote is refused
    # here rather than half-run, and so is a device id that is not one.
    param([Parameter(Mandatory = $true)][string]$HordeRoot, [Parameter(Mandatory = $true)][string]$DeviceId)
    if ($DeviceId -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') { throw ("not a device id: '" + $DeviceId + "'") }
    if (-not [System.IO.Path]::IsPathRooted($HordeRoot)) { throw ("Horde's root must be a full path, not '" + $HordeRoot + "'") }
    $script = [System.IO.Path]::Combine($HordeRoot, "cli", "attach.ps1")
    $exe = $script:HordeSshAttachPowerShell
    if ($exe -match '[\s"]' -or $script -match '[\s"]') { throw ("Horde is installed under a path with a space or a quote (" + $script + "); the hub's forced command cannot name it unquoted") }
    return ($exe + " -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + $script + " -Device " + $DeviceId)
}
