# The wezfleet messenger's fixture for test/test-messenger-conformance.ps1 (the contract is in that
# suite's header), and for test-wezfleet-messenger.ps1 beside it.
#
# Each state is a fresh folder under the temp folder holding test\FakeWezfleet.ps1 copied as wezfleet.ps1,
# and the messenger is pointed at it, so the program the messenger starts is the fake, which keeps every
# side effect in that folder. EVERYTHING OBSERVED IS READ FROM THE FAKE'S OWN RECORDS - its store, its
# typed.log and its argv.log - never from what the messenger answered (review of #102, finding 1).
#
# -Spaced puts the folder under a name with a space in it, so a test can see an argument with a space
# arrive as one argument.
param([Parameter(Mandatory = $true)][string]$Root)
return [pscustomobject]@{
    New = {
        param([switch]$Spaced)
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $leaf = "horde-wfm-" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        if ($Spaced) { $leaf = $leaf + " spaced" }
        $dir = Join-Path $tempRoot $leaf
        # NEVER A REAL WEZFLEET: the folder the messenger is pointed at is a fresh one under the temp folder.
        if (-not $dir.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw ("fixture folder '" + $dir + "' is not under the temp folder") }
        [void](New-Item -ItemType Directory -Path $dir)
        # Found through the registered messenger's folder: a script block here runs in its caller's scope,
        # where no variable of this file survives.
        $fakeSource = Join-Path (Get-HordeMessenger -Name "wezfleet").folder "test\FakeWezfleet.ps1"
        Copy-Item -LiteralPath $fakeSource -Destination (Join-Path $dir "wezfleet.ps1")
        Set-HordeWezfleetMessengerRoot -Path $dir -TimeoutSeconds 60
        return @{ dir = $dir }
    }
    Remove = {
        param($State)
        Set-HordeWezfleetMessengerRoot -Path ""
        if ($State.dir -and (Test-Path -LiteralPath $State.dir)) { Remove-Item -LiteralPath $State.dir -Recurse -Force }
    }
    Observe = {
        param($State, $MessageId)
        $n = $MessageId.Replace("-", "")
        $recPath = Join-Path (Join-Path $State.dir "store") ($n + ".json")
        $bodies = @()
        if (Test-Path -LiteralPath $recPath) { $bodies = @(([System.IO.File]::ReadAllText($recPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json).body) }
        $typed = @()
        $typedPath = Join-Path $State.dir "typed.log"
        if (Test-Path -LiteralPath $typedPath) { $typed = @([System.IO.File]::ReadAllLines($typedPath, [System.Text.Encoding]::UTF8) | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_ | ConvertFrom-Json }) }
        return [pscustomobject]@{
            records = $bodies.Count
            bodies = $bodies
            typed = @($typed | ForEach-Object { "$($_.text)" })
            wakes = @($typed | Where-Object { "$($_.id)" -ceq $n }).Count
        }
    }
    # Plays the receiving session's Stop hook, by the fake's own store: the record is taken, as wezfleet's
    # hook acks it once the id is in that session's transcript.
    Receive = {
        param($State, $MessageId)
        $recPath = Join-Path (Join-Path $State.dir "store") ($MessageId.Replace("-", "") + ".json")
        $rec = [System.IO.File]::ReadAllText($recPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $rec.stage = "taken"
        [System.IO.File]::WriteAllText($recPath, ($rec | ConvertTo-Json -Compress -Depth 4), [System.Text.Encoding]::UTF8)
    }
    # For test-wezfleet-messenger.ps1: how the fake misbehaves, and what it was handed.
    SetMode = { param($State, $Mode) [System.IO.File]::WriteAllText((Join-Path $State.dir "mode.json"), ($Mode | ConvertTo-Json -Compress -Depth 4), [System.Text.Encoding]::ASCII) }
    Runs = {
        param($State)
        $p = Join-Path $State.dir "argv.log"
        if (-not (Test-Path -LiteralPath $p)) { return @() }
        return @([System.IO.File]::ReadAllLines($p) | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_ | ConvertFrom-Json })
    }
}
