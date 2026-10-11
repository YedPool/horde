# RootProbe.ps1 - the child each case of test-wezfleet-messenger-root.ps1 runs, under the PATH and the
# HORDE_HOME that suite gives it. Loads the port and this messenger, asks one status (or, with -Post, one
# post) and prints the answer as one line of JSON { state; reason }. With -ThenRoot it then writes the
# messenger's settings file under HORDE_HOME naming that folder as root, and asks again in the SAME
# process: the second answer shows whether the setting is read when the messenger needs the folder, or
# only once when it loaded.
param([Parameter(Mandatory = $true)][string]$Root, [string]$ThenRoot = "", [switch]$Post)
$ErrorActionPreference = "Stop"
. (Join-Path $Root "messengers\Port.ps1")
. (Join-Path $Root "messengers\wezfleet\Messenger.ps1")
$m = Get-HordeMessenger -Name "wezfleet"
function Ask {
    if ($Post) {
        $msg = [pscustomobject]@{
            messageId = "0e000000-0000-4000-8000-000000000002"; sessionId = "22222222-3333-4444-8555-666666666666"; label = "A"
            from = [pscustomobject]@{ deviceId = "0f000000-0000-4000-8000-000000000001"; sessionId = "33333333-4444-4555-8666-777777777777"; label = "M" }
            body = "probe body"; ttlSeconds = 3600
        }
        $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    } else {
        $a = Get-HordeMessengerStatus -Messenger $m -MessageId "0e000000-0000-4000-8000-000000000001"
    }
    $r = $a.PSObject.Properties["reason"]
    return ([pscustomobject]@{ state = "$($a.state)"; reason = $(if ($null -ne $r) { "$($r.Value)" } else { "" }) } | ConvertTo-Json -Compress)
}
Ask
if ($ThenRoot -ne "") {
    $dir = Join-Path $env:HORDE_HOME "settings"
    [void](New-Item -ItemType Directory -Force -Path $dir)
    $doc = [pscustomobject]@{ schemaVersion = 1; settings = [pscustomobject]@{ root = $ThenRoot } } | ConvertTo-Json -Compress -Depth 3
    [System.IO.File]::WriteAllText((Join-Path $dir "messenger-wezfleet.json"), $doc, (New-Object System.Text.UTF8Encoding($false)))
    Ask
}
