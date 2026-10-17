# channels/progress/Settings.ps1 - which progress changelog the progress channel follows: its settings and
# the file they name. Moved out of channels/progress/Channel.ps1 unchanged (2026-10-15) so that the Orc
# registry (orcs/Registry.ps1), which reads each Orc's newest entry for its latest activity, reads the
# SAME file from the SAME setting, without loading the channel, which registers itself with the relay
# when it is loaded. One declaration of relay-progress, so the two cannot come to read two files.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")

$script:HordeProgressChannelSettings = New-HordeModuleSettings -Module "relay-progress" -Settings @(
    @{ name = "progressFile"; kind = "folder"; default = ""; what = "The progress changelog to follow, as an absolute path; empty means progress\changelog.jsonl under Horde's home." },
    # 200 entries is several working days of a fleet that writes a few tens a day: what a phone just
    # paired needs to pick up the thread, in two or three envelopes.
    @{ name = "backfillEntries"; kind = "whole"; default = 200; min = 0; max = 5000; what = "How many of the newest entries a phone key newly trusted, or the first look ever, is sent." },
    # 16,384 is the floor: an entry at its largest (a title of 100 and a text of 2,000 characters, every
    # one a six-byte escape) is about 13,000 bytes, so a page always holds at least one.
    @{ name = "pageBytes"; kind = "whole"; default = 262144; min = 16384; max = 1048576; what = "The largest body of one envelope of entries, in bytes; a longer batch is sent as more envelopes." },
    @{ name = "readBytes"; kind = "whole"; default = 1048576; min = 131072; max = 33554432; what = "The most bytes of the changelog read in one look." },
    @{ name = "sendIntervalMs"; kind = "whole"; default = 2000; min = 0; max = 600000; what = "The shortest time between two sends of entries, in milliseconds: lines written meanwhile go together." },
    # 100: channels/progress/Channel.ps1, THE PHONE'S MAILBOX HOLDS THE LAST keepEnvelopes. 1,000 is the
    # ceiling because the hosted relay's mailbox holds 2,000 envelopes for every channel of every machine
    # of the horde.
    @{ name = "keepEnvelopes"; kind = "whole"; default = 100; min = 1; max = 1000; what = "How many of this machine's newest progress envelopes stay in the phone's mailbox; older ones are deleted from the relay, so this is how far back the log goes on the phone." }
)

function Get-HordeProgressChannelSettingsDeclaration { return $script:HordeProgressChannelSettings }

function Get-HordeProgressChannelFilePath {
    # The changelog this home follows (WHICH FILE, in channels/progress/Channel.ps1's header).
    param([Parameter(Mandatory = $true)][string]$HordeHome, [AllowEmptyString()][string]$Setting = "")
    if ($Setting -cne "") { return $Setting }
    return [System.IO.Path]::Combine($HordeHome, "progress", "changelog.jsonl")
}
