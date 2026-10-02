# One racer for test/test-device.ps1. Not a suite: it is started as its own process, several at once,
# and each asks for the device id of the same fresh home at the same moment.
#
# It loads the device module named by -DevicePath (the real one, or the suite's broken copy), says it
# is ready, waits for the shared start tick in -GoFile, calls Get-HordeNode once, and writes
# "<created>|<raced>|<deviceId>" to -OutFile. The suite compares the ids every racer was given.
param(
    [Parameter(Mandatory = $true)][string]$DevicePath,
    [Parameter(Mandatory = $true)][string]$HomeRoot,
    [Parameter(Mandatory = $true)][string]$GoFile,
    [Parameter(Mandatory = $true)][string]$ReadyFile,
    [Parameter(Mandatory = $true)][string]$OutFile
)
$ErrorActionPreference = "Stop"
. $DevicePath
[System.IO.File]::WriteAllText($ReadyFile, "ready")
$deadline = [datetime]::UtcNow.AddSeconds(120)
while (-not (Test-Path -LiteralPath $GoFile)) {
    if ([datetime]::UtcNow -gt $deadline) { throw "no go file within 120 s" }
    Start-Sleep -Milliseconds 20
}
$startTicks = [long]([System.IO.File]::ReadAllText($GoFile).Trim())
while ([datetime]::UtcNow.Ticks -lt $startTicks) { }
$n = Get-HordeNode -HomeRoot $HomeRoot
[System.IO.File]::WriteAllText($OutFile, ("" + $n.created + "|" + $n.raced + "|" + $n.deviceId))
