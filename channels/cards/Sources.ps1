# channels/cards/Sources.ps1 - where the cards channel reads the fleet from: its settings, the paths they
# give, and the reader of the area-to-lane map with the two text helpers it needs. Moved out of
# channels/cards/Channel.ps1 (2026-10-15) so that the Orc registry (orcs/Registry.ps1) reads the SAME
# lanes folder and the SAME area map from the SAME settings, without loading the channel, which registers
# itself with the relay when it is loaded. One declaration of relay-cards and one map reader, so the
# phone's cards and the Orc list cannot come to read two different folders or one map two ways.
# Moved unchanged, but for one line: the map is parsed with ConvertFrom-HordeJson, not ConvertFrom-Json,
# so a date-shaped area name stays text under PowerShell 7 (core/JsonText.ps1, issue #274).
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ReadShared.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Secrets.ps1")

$script:HordeCardsChannelSettings = New-HordeModuleSettings -Module "relay-cards" -Settings @(
    @{ name = "lanesFolder"; kind = "folder"; default = ""; what = "The folder of lane folders, each with its status.txt, as an absolute path; empty means progress\lanes under Horde's home." },
    @{ name = "ledgerFile"; kind = "folder"; default = ""; what = "The fleet's task ledger, as an absolute path; empty means progress\tasks.jsonl under Horde's home." },
    @{ name = "areaLanesFile"; kind = "folder"; default = ""; what = "Which lanes each area of the progress log belongs to, as an absolute path; empty means progress\area-lanes.json under Horde's home." },
    @{ name = "runsFolder"; kind = "folder"; default = ""; what = "The fleet's runs, for the count of sessions running, as an absolute path; empty means progress\runs under Horde's home." },
    @{ name = "thrallStatusFile"; kind = "folder"; default = ""; what = "The Thrall's own status file, as an absolute path; empty means progress\thrall-status.txt under Horde's home." },
    @{ name = "machineName"; kind = "text"; default = ""; min = 0; max = 64; what = "The name each card gives its machine; empty means this computer's name." },
    @{ name = "sendIntervalMs"; kind = "whole"; default = 30000; min = 0; max = 3600000; what = "The shortest time between two looks at the lanes, in milliseconds." },
    # 64: the most lanes read, as fleet/StatusPanel.ps1 reads; the rest are counted.
    @{ name = "lanesRead"; kind = "whole"; default = 64; min = 1; max = 256; what = "The most lane folders read; the rest are counted and said." }
)

function Get-HordeCardsChannelSettingsDeclaration { return $script:HordeCardsChannelSettings }

function Get-HordeCardsChannelPaths {
    # Every source this home reads (WHAT IT READS, in channels/cards/Channel.ps1): a setting, or its place
    # under the home.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)]$Settings)
    $under = { param([string]$Set, [string]$Leaf) if ($Set -cne "") { return $Set }; return [System.IO.Path]::Combine($HordeHome, "progress", $Leaf) }
    return [pscustomobject]@{
        lanes = (& $under $Settings.lanesFolder "lanes"); ledger = (& $under $Settings.ledgerFile "tasks.jsonl"); areas = (& $under $Settings.areaLanesFile "area-lanes.json")
        runs = (& $under $Settings.runsFolder "runs"); thrall = (& $under $Settings.thrallStatusFile "thrall-status.txt") }
}

$script:HordeCardsChannelTextChars = 300
$script:HordeCardsChannelAreasMost = 200
$script:HordeCardsChannelLanePattern = '\A[A-Za-z0-9][A-Za-z0-9 ._-]{0,31}\z'

function Get-HordeCardsChannelClean {
    # A text with its control characters as spaces, trimmed, and WHOLE: what the secret refusal looks at.
    param([AllowEmptyString()][string]$Text)
    return ([regex]::Replace($Text, '\p{Cc}', ' ')).Trim()
}

function Get-HordeCardsChannelPlain {
    # A text as a card holds it: clean, and at most 300 characters - a card is a glance, and the whole
    # story is the lane's stream. Never handed to the refusal: cut, a secret may no longer look like one.
    param([AllowEmptyString()][string]$Text)
    $t = Get-HordeCardsChannelClean $Text
    if ($t.Length -gt $script:HordeCardsChannelTextChars) { $t = $t.Substring(0, $script:HordeCardsChannelTextChars - 3).TrimEnd() + "..." }
    return $t
}

function Read-HordeCardsChannelAreas {
    # The area-to-lane map (areaLanesFile, in the header): { ok; reason; areas; refused } - areas a list
    # of { area; lanes } in the file's order. No file is an empty map and says so; a file that does not
    # hold together is an empty map, said, never half of one. An area or a lane that trips the secret
    # refusal is left out and counted.
    param([Parameter(Mandatory = $true)][string]$Path)
    $answer = [pscustomobject]@{ ok = $false; reason = ""; areas = @(); refused = 0 }
    if (-not [System.IO.File]::Exists($Path)) { $answer.reason = "there is no area-to-lane map at " + $Path + ", so the log's entries that name no lane show only in the Thrall's stream"; return $answer }
    try { $text = Read-HordeSharedText -Path $Path } catch { $answer.reason = "the area-to-lane map " + $Path + " could not be read"; return $answer }
    $why = "the area-to-lane map " + $Path + " does not hold together"
    if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { $answer.reason = $why + ": a member is repeated"; return $answer }
    try { $m = ConvertFrom-HordeJson $text } catch { $answer.reason = $why + ": it is not JSON"; return $answer }
    if ($m -isnot [System.Management.Automation.PSCustomObject] -or $null -eq $m.PSObject.Properties["v"] -or $m.v -ne 1 -or $null -eq $m.PSObject.Properties["areas"] -or $m.areas -isnot [System.Management.Automation.PSCustomObject]) { $answer.reason = $why + ": it is not {""v"":1,""areas"":{...}}"; return $answer }
    $list = New-Object System.Collections.ArrayList
    foreach ($p in @($m.areas.PSObject.Properties)) {
        if ($list.Count -ge $script:HordeCardsChannelAreasMost) { $answer.reason = "the area-to-lane map holds more than " + $script:HordeCardsChannelAreasMost + " areas; the rest are left out"; break }
        $area = "$($p.Name)"
        if ($p.Value -isnot [string] -or $area.Trim() -eq "" -or $area.Length -gt 60 -or $area -cmatch '\p{Cc}') { $answer.reason = $why + ": the area '" + (Get-HordeCardsChannelPlain $area) + "' is not 1 to 60 plain characters naming lanes"; $answer.areas = @(); return $answer }
        $lanes = @($p.Value.Split([char]',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        if ($lanes.Count -eq 0 -or @($lanes | Where-Object { $_ -cnotmatch $script:HordeCardsChannelLanePattern }).Count -gt 0) { $answer.reason = $why + ": the lanes of '" + (Get-HordeCardsChannelPlain $area) + "' are not lane ids separated by commas"; $answer.areas = @(); return $answer }
        if ((Find-HordeSecretKind -Text ($area + " " + ($lanes -join ","))) -cne "") { $answer.refused++; continue }
        [void]$list.Add([pscustomobject]@{ area = $area; lanes = $lanes })
    }
    $answer.ok = $true
    $answer.areas = @($list.ToArray())
    return $answer
}
