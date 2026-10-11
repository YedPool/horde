# test/lib/ChatFleet.ps1 - a synthetic Thrall and a messenger stand-in, for the chat channel's end-to-end
# suites (test/test-relay-chat-e2e.ps1, surfaces/pwa/test/test-pwa-phone-e2e.ps1), which drive a real
# `horde relay run` as its own process.
#
# THE THRALL is made by the first conversation adapter whose conformance fixture
# (agents/<name>/test/ConversationFixture.ps1, the contract in test/test-conversation-conformance.ps1)
# keeps its registry in a fleet root of its own (options.registryRoot), in the temp folder, with words
# the suite makes up written in that harness's own format. WEZFLEET_ROOT - the fleet root a child reads
# (core/Roles.ps1) - is pointed at it, so the child finds that Thrall and no other. Load it after
# test/lib/FleetPin.ps1 has pinned the fleet to an empty folder: before a Thrall is made, none exists.
#
# THE MESSENGER is the loaded messenger that ships a test stand-in (messengers/<name>/test/
# FakeWezfleet.ps1, which keeps every post in its own folder), named as that messenger's checkout in
# the child's home settings (messenger-<name>.json, root), with the marker files a checkout holds. No
# post can reach a real session: the stand-in is the only program the messenger starts.
#
# Requires conversations/Port.ps1 and messengers/Port.ps1 with their adapters loaded (channels/chat
# loads them).

function Get-HordeTestChatFixtureFiles {
    # Every adapter's conformance fixture, for the suite to dot-source AT SCRIPT LEVEL - a fixture
    # dot-sources the helpers its blocks call, and inside a function they would not outlive it:
    #   $fixtures = @(Get-HordeTestChatFixtureFiles | ForEach-Object { . $_ -Root $root })
    return @(Get-HordeConversationAdapterFiles | ForEach-Object { Join-Path (Split-Path -Parent $_) "test\ConversationFixture.ps1" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function New-HordeTestChatThrall {
    # A synthetic fleet with a Thrall, from the first of -Fixtures that keeps a fleet root of its own:
    # { fixture; state }, or $null when none does. WEZFLEET_ROOT is pointed at it.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Fixtures)
    foreach ($candidate in $Fixtures) {
        $st = & $candidate.New
        if ($st.options -is [System.Collections.IDictionary] -and $st.options.Contains("registryRoot")) {
            $env:WEZFLEET_ROOT = $st.options.registryRoot
            return [pscustomobject]@{ fixture = $candidate; state = $st }
        }
        & $candidate.Remove $st
    }
    return $null
}

function Add-HordeTestChatTurns {
    # Turns written by the synthetic Thrall: each @{ role; text }.
    param([Parameter(Mandatory = $true)]$Thrall, [Parameter(Mandatory = $true)][object[]]$Turns)
    $Thrall.fixture.Add.Invoke($Thrall.state, @($Turns | ForEach-Object { [pscustomobject]@{ role = $_.role; text = $_.text } }))
}

function Remove-HordeTestChatThrall {
    param($Thrall)
    if ($null -ne $Thrall) { try { & $Thrall.fixture.Remove $Thrall.state } catch { } }
}

function New-HordeTestFleetMessenger {
    # The stand-in under -Folder, named in -HordeHome's settings. The messenger's name, or "" when no
    # loaded messenger ships a stand-in.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$Folder)
    foreach ($name in @(Get-HordeMessengerNames)) {
        $standIn = Join-Path (Get-HordeMessenger -Name $name).folder "test\FakeWezfleet.ps1"
        if (-not (Test-Path -LiteralPath $standIn -PathType Leaf)) { continue }
        [void](New-Item -ItemType Directory -Force -Path $Folder)
        Copy-Item -LiteralPath $standIn -Destination (Join-Path $Folder ($name + ".ps1"))
        foreach ($marker in @("lib\Mail.ps1", "lib\MailPost.ps1", "commands\mail.ps1")) {
            $mp = Join-Path $Folder $marker
            [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mp))
            [System.IO.File]::WriteAllText($mp, "# a marker stub for the chat end-to-end suites`r`n")
        }
        $doc = [pscustomobject]@{ schemaVersion = 1; settings = [pscustomobject]@{ root = $Folder } } | ConvertTo-Json -Compress -Depth 3
        [void](New-Item -ItemType Directory -Force -Path (Join-Path $HordeHome "settings"))
        [System.IO.File]::WriteAllText((Join-Path $HordeHome ("settings\messenger-" + $name + ".json")), $doc, (New-Object System.Text.UTF8Encoding -ArgumentList $false))
        return $name
    }
    return ""
}

function Get-HordeTestFleetPosts {
    # Every message the stand-in under -Folder was posted, one record per message id.
    param([Parameter(Mandatory = $true)][string]$Folder)
    $store = Join-Path $Folder "store"
    if (-not (Test-Path -LiteralPath $store)) { return @() }
    return @(Get-ChildItem -LiteralPath $store -Filter "*.json" | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json })
}
