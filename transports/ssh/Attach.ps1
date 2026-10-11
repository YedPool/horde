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
    # It sits unquoted inside the key's command="...", and Win32 sshd runs it through cmd.exe /c, so
    # Horde's root must be a drive path (C:\...) of letters, digits and . _ - only: a space or a quote
    # splits it, and cmd.exe reads & | ^ % < > ( ) ! (review of PR #111, N1: C:\R&D\horde ran as two
    # commands; N2: C:h and \h passed a rooted-path check). A device id that is not one is refused too.
    param([Parameter(Mandatory = $true)][string]$HordeRoot, [Parameter(Mandatory = $true)][string]$DeviceId)
    if ($DeviceId -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') { throw ("not a device id: '" + $DeviceId + "'") }
    if ($HordeRoot -cnotmatch '\A[A-Za-z]:\\') { throw ("Horde's root must be a full path that starts with a drive letter and :\, not '" + $HordeRoot + "'") }
    if ($HordeRoot -cnotmatch '\A[A-Za-z]:\\[A-Za-z0-9\\._-]*\z') { throw ("Horde's root '" + $HordeRoot + "' holds a character the hub's forced command cannot carry: only letters, digits, \ . _ and - (no space, quote or cmd.exe metacharacter)") }
    $script = $HordeRoot.TrimEnd('\') + "\cli\attach.ps1"
    $exe = $script:HordeSshAttachPowerShell
    if ($exe -cnotmatch '\A[A-Za-z]:\\[A-Za-z0-9\\._-]*\z') { throw ("System32's powershell.exe is at a path the forced command cannot carry: " + $exe) }
    return ($exe + " -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + $script + " -Device " + $DeviceId)
}
