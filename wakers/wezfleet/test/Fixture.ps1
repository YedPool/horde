# The wezfleet waker's fixture for test/test-waker-conformance.ps1 (the contract is in that suite's
# header), and for test/test-waker-wezfleet.ps1.
#
# Each state is a fresh folder under the temp folder holding test\FakeWezfleet.ps1 copied as wezfleet.ps1,
# beside the marker files of a checkout as empty stubs, and the waker is pointed at it, so the program the
# waker starts is the fake, which keeps every side effect in that folder. EVERYTHING OBSERVED IS READ FROM
# THE FAKE'S OWN RECORDS - its typed.log and its argv.log - never from what the waker answered.
# NO REAL FLEET IS EVER REACHED: the folder is under the temp folder or New throws, and HORDE_HOME is
# moved to a fresh temp folder too, so the waker's settings are read from there and Remove puts the old
# value back.
#
# Beside the four blocks the conformance suite calls (New, Remove, Seat, Observe), for the waker's own
# suite: SetRow (write a row exactly as given, to play what the fleet could say), SetMode (how the fake
# misbehaves), Runs (what it was handed), Rows (the fleet as it stands) and Forget (the waker forgets
# what it remembered of the fleet, as a new pass a tick later would).
param([Parameter(Mandatory = $true)][string]$Root)
return [pscustomobject]@{
    New = {
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $dir = Join-Path $tempRoot ("horde-wfw-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
        if (-not $dir.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw ("fixture folder '" + $dir + "' is not under the temp folder") }
        [void](New-Item -ItemType Directory -Path $dir)
        # Found through the registered waker's folder: a script block here runs in its caller's scope,
        # where no variable of this file survives.
        Copy-Item -LiteralPath (Join-Path (Get-HordeWaker -Name "wezfleet").folder "test\FakeWezfleet.ps1") -Destination (Join-Path $dir "wezfleet.ps1")
        foreach ($marker in @("lib\Mail.ps1", "commands\mail.ps1")) {
            $mp = Join-Path $dir $marker
            [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mp))
            [System.IO.File]::WriteAllText($mp, "# a marker stub for the wezfleet waker's tests`r`n")
        }
        [System.IO.File]::WriteAllText((Join-Path $dir "fleet.json"), "[]", [System.Text.Encoding]::ASCII)
        $hordeHome = $dir + "-home"
        [void](New-Item -ItemType Directory -Path $hordeHome)
        $oldHome = $env:HORDE_HOME
        $env:HORDE_HOME = $hordeHome
        Set-HordeWezfleetWakerRoot -Path $dir
        Set-HordeWezfleetWakerDeadlines
        Set-HordeWezfleetWakerClock $null
        return @{ dir = $dir; home = $hordeHome; oldHome = $oldHome }
    }
    Remove = {
        param($State)
        Set-HordeWezfleetWakerRoot -Path ""
        Set-HordeWezfleetWakerDeadlines
        Set-HordeWezfleetWakerClock $null
        Set-HordeWezfleetWakerSnapshotFault $false
        $env:HORDE_HOME = $State.oldHome
        foreach ($d in @($State.dir, $State.home)) { if ($d -and (Test-Path -LiteralPath $d)) { Remove-Item -LiteralPath $d -Recurse -Force } }
    }
    # ONE FAKE SESSION, as the conformance suite describes it: a row of the fleet, in the fleet's own
    # words for a role, and its mail's body in a file of the fake's - where a mailbox is, and nowhere a
    # nudge could take it from.
    Seat = {
        param($State, $Session)
        $words = @{ "warchief" = "master"; "orc" = "orchestrator"; "goblin" = "session" }
        $role = "unknown"
        if ($words.ContainsKey("$($Session.role)")) { $role = $words["$($Session.role)"] }
        $oldest = $null
        if ($Session.oldestUnreadAt -is [datetime]) { $oldest = $Session.oldestUnreadAt.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
        $row = [ordered]@{ id = "$($Session.id)"; label = "$($Session.label)"; role = $role; parent = "$($Session.parent)"; retired = $false; reachable = "yes"; mail = "known"
            unreadCount = [int]$Session.unreadCount; unreadableCount = 0; oldestUnreadAt = $oldest; idle = "$($Session.idle)"; boxEmpty = "$($Session.boxEmpty)"; midTurn = "$($Session.midTurn)"; reason = ""; reasons = @() }
        $path = Join-Path $State.dir "fleet.json"
        $parsed = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $rows = @(@($parsed) | Where-Object { $null -ne $_ -and $_.id -cne $row.id }) + [pscustomobject]$row
        [System.IO.File]::WriteAllText($path, ("[" + ((@($rows | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress -Depth 6 })) -join ",") + "]"), [System.Text.Encoding]::UTF8)
        $mail = Join-Path $State.dir "mail"
        [void](New-Item -ItemType Directory -Force -Path $mail)
        [System.IO.File]::WriteAllText((Join-Path $mail ($row.id + ".txt")), "$($Session.body)", [System.Text.Encoding]::UTF8)
        # The fleet changed under the waker: what it remembered of it a moment ago is another pass's.
        Clear-HordeWezfleetWakerMemory
    }
    Observe = {
        param($State, $Id)
        $typed = @()
        $typedPath = Join-Path $State.dir "typed.log"
        if (Test-Path -LiteralPath $typedPath) { $typed = @([System.IO.File]::ReadAllLines($typedPath, [System.Text.Encoding]::UTF8) | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { "$($_.id)" -ceq $Id }) }
        return [pscustomobject]@{ nudges = $typed.Count; typed = @($typed | ForEach-Object { "$($_.text)" }) }
    }
    SetRow = {
        param($State, $Row)
        $path = Join-Path $State.dir "fleet.json"
        $parsed = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $rows = @(@($parsed) | Where-Object { $null -ne $_ -and "$($_.id)" -cne "$($Row.id)" }) + [pscustomobject]$Row
        [System.IO.File]::WriteAllText($path, ("[" + ((@($rows | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress -Depth 6 })) -join ",") + "]"), [System.Text.Encoding]::UTF8)
        Clear-HordeWezfleetWakerMemory
    }
    Rows = {
        param($State)
        $parsed = [System.IO.File]::ReadAllText((Join-Path $State.dir "fleet.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        return @($parsed)
    }
    SetMode = {
        param($State, $Mode)
        $path = Join-Path $State.dir "mode.json"
        if ($null -eq $Mode) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
        else { [System.IO.File]::WriteAllText($path, ($Mode | ConvertTo-Json -Compress -Depth 4), [System.Text.Encoding]::ASCII) }
    }
    Runs = {
        param($State)
        $p = Join-Path $State.dir "argv.log"
        if (-not (Test-Path -LiteralPath $p)) { return @() }
        return @([System.IO.File]::ReadAllLines($p) | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_ | ConvertFrom-Json })
    }
    Forget = { param($State) Clear-HordeWezfleetWakerMemory }
    NoSnapshot = { param($State, [bool]$On) Set-HordeWezfleetWakerSnapshotFault $On }
    Clock = { param($State, $Now) Set-HordeWezfleetWakerClock $Now }
    # With no budget given, the waker's own default is what is set back: this fixture does not say what it is.
    Deadlines = { param($State, [int]$FleetSeconds = 10, [int]$PaneFlagSeconds = 5, [int]$NudgeBudgetSeconds = 0) if ($NudgeBudgetSeconds -gt 0) { Set-HordeWezfleetWakerDeadlines -FleetSeconds $FleetSeconds -PaneFlagSeconds $PaneFlagSeconds -NudgeBudgetSeconds $NudgeBudgetSeconds } else { Set-HordeWezfleetWakerDeadlines -FleetSeconds $FleetSeconds -PaneFlagSeconds $PaneFlagSeconds } }
}
