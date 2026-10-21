# cli/MeterTell.ps1 - how the fleet meter's limit watch tells the warchief's session something.
#
# THE HORDE-NATIVE WAY, and the only one: one message through the messenger port (messengers/Port.ps1)
# to the warchief's seat (core/SessionSeat.ps1), the same road the analyst supervisor uses
# (cli/AnalystTend.ps1, Send-HordeAnalystPost). The messenger chosen is the one that keeps a body out of
# any input box and takes a repost as one message ("body.untyped", "idempotent.post"). The meter never
# types into a pane: that is the defect family the fleet's mail was built to end.
#
# THE TEXT COMES FROM A FILE, never from a command line (the fleet's interim rule of 2026-10-14: a
# tell carries no command and never rides one). The watch script, which is Node, writes the sentence
# to a temporary file and runs `horde meter tell -File <that file>`.
#
# A TEST'S HOME TELLS NOBODY, as for the analyst and the services: a Horde home under the temp folder is
# a suite's, and a tell from one is refused before any messenger or any seat is looked for, because the
# seat is found in a store whose place does not follow the Horde home.
#
# THE CALLER LOADS the port: core/Tristate.ps1, Home.ps1, SessionSeat.ps1, Device.ps1, messengers/Port.ps1
# and every messenger file must be dot-sourced in the scope this is called from (cli/commands/meter.ps1).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeMeterTellRole = "warchief"
$script:HordeMeterFromSession = "horde-meter"
# How long the message may wait in a mailbox: the link's most, 7 days (messengers/Port.ps1).
$script:HordeMeterTtlSeconds = 604800
$script:HordeMeterTellNeeds = @("body.untyped", "idempotent.post")
$script:HordeMeterTakenStages = @("accepted", "handed-over", "seen")
# A tell is one or two sentences; far over this is a mistake, not a message.
$script:HordeMeterTellMaxChars = 1500

function Test-HordeMeterHomeIsATests {
    # Is -HordeHome under the temp folder? A home that cannot be resolved is taken as a test's.
    param([string]$HordeHome)
    try {
        $rootFull = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/') + '\'
        $full = [System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\', '/') + '\'
        return [bool]$full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
    } catch { return $true }
}

function Send-HordeMeterTell {
    # Tell the warchief's session -Body once: { ok; detail }. The message id is new each time, so each
    # call is one message; the watch's alerted_at is what keeps it to one per hit.
    param([Parameter(Mandatory = $true)][string]$Body, [Parameter(Mandatory = $true)][string]$HordeHome)
    if ($Body.Trim() -eq "") { return [pscustomobject]@{ ok = $false; detail = "the text is empty" } }
    if ($Body.Length -gt $script:HordeMeterTellMaxChars) { return [pscustomobject]@{ ok = $false; detail = ("the text is over " + $script:HordeMeterTellMaxChars + " characters") } }
    if (Test-HordeMeterHomeIsATests -HordeHome $HordeHome) { return [pscustomobject]@{ ok = $false; detail = "this Horde home is a test's: nobody is told" } }
    $seat = Get-HordeRoleSeat -Role $script:HordeMeterTellRole
    if ($seat.state -cne "known") { return [pscustomobject]@{ ok = $false; detail = ("the warchief's session cannot be told: " + $(if ($seat.state -ceq "absent") { $seat.note } else { $seat.reason })) } }
    $found = Find-HordeMessenger -Require $script:HordeMeterTellNeeds
    if ($found.state -cne "known") { return [pscustomobject]@{ ok = $false; detail = ("no messenger can deliver to a session: " + $(if ($found.state -ceq "absent") { $found.note } else { $found.reason })) } }
    $deviceId = ""
    try { $deviceId = Get-HordeDeviceId -HomeRoot $HordeHome } catch { return [pscustomobject]@{ ok = $false; detail = ("this machine's device id could not be had: " + $_.Exception.Message) } }
    $message = [pscustomobject]@{
        messageId = [guid]::NewGuid().ToString(); sessionId = $seat.value.sessionId
        from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeMeterFromSession }
        body = $Body; ttlSeconds = $script:HordeMeterTtlSeconds
    }
    $posted = Send-HordeMessengerMessage -Messenger $found.value -Message $message
    if ($posted.state -ceq "known" -and $script:HordeMeterTakenStages -ccontains "$($posted.value.stage)") { return [pscustomobject]@{ ok = $true; detail = ("told the warchief's session (" + $posted.value.stage + ")") } }
    return [pscustomobject]@{ ok = $false; detail = $(if ($posted.state -ceq "known") { "the messenger answered " + $posted.value.stage } else { "the messenger did not take it: " + $posted.reason }) }
}
