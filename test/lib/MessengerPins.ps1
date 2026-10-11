# test/lib/MessengerPins.ps1 - a Horde home for tests in which no messenger can reach a real program.
#
# WHY. A messenger may find the program it hands messages to on its own - the wezfleet messenger runs the
# checkout the wezfleet command on PATH runs, when its settings name none. On a machine where that command
# is installed, a suite that loads every messenger, or starts a real horde child, could then post into the
# real fleet. So such a suite runs under a home made here, in which every messenger that has a
# messengers/<name>/test/Pin.ps1 has pinned itself to nothing. This file names no messenger: a pin is the
# messenger's own, found by folder.
#
# USE, in a suite (children it starts inherit HORDE_HOME, so they are pinned too):
#   . (Join-Path $root "test\lib\MessengerPins.ps1")
#   $pinned = Enter-HordeTestPinnedHome -Root $root
#   try { ...checks... } finally { Exit-HordeTestPinnedHome -State $pinned }
# A suite that makes its own temp home for a child instead runs, before it starts the child:
#   Set-HordeTestMessengerPins -Root $root -HordeHome <that home>

function Set-HordeTestMessengerPins {
    # Runs every messengers/<name>/test/Pin.ps1 on -HordeHome, which must be under the temp folder.
    # Returns the names of the messengers it pinned.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$HordeHome)
    $pinnedNames = New-Object System.Collections.ArrayList
    foreach ($d in @(Get-ChildItem -LiteralPath (Join-Path $Root "messengers") -Directory | Sort-Object Name)) {
        $pin = Join-Path $d.FullName "test\Pin.ps1"
        if (-not (Test-Path -LiteralPath $pin -PathType Leaf)) { continue }
        $null = & $pin -HordeHome $HordeHome
        [void]$pinnedNames.Add($d.Name)
    }
    return @($pinnedNames)
}

function Enter-HordeTestPinnedHome {
    # A fresh home under the temp folder, every messenger pinned in it, and HORDE_HOME pointed at it.
    # Returns { home; oldHome; pinned } for Exit-HordeTestPinnedHome.
    param([Parameter(Mandatory = $true)][string]$Root)
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $dir = Join-Path $tempRoot ("horde-pinned-" + [guid]::NewGuid().ToString("N"))
    [void](New-Item -ItemType Directory -Path $dir)
    $pinnedNames = @(Set-HordeTestMessengerPins -Root $Root -HordeHome $dir)
    $state = [pscustomobject]@{ home = $dir; oldHome = $env:HORDE_HOME; pinned = $pinnedNames }
    $env:HORDE_HOME = $dir
    return $state
}

function Exit-HordeTestPinnedHome {
    # Puts HORDE_HOME back and removes the home Enter-HordeTestPinnedHome made.
    param([Parameter(Mandatory = $true)]$State)
    $env:HORDE_HOME = $State.oldHome
    if ((Split-Path -Leaf $State.home) -match '\Ahorde-pinned-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $State.home)) { Remove-Item -LiteralPath $State.home -Recurse -Force }
}
