# remote/Overlay - the overlay boundary, Horde's side: read a hub address, read the overlay's answer,
# pick a peer's address, and hear its health as advice.
#
# WHY (remote plan step R8; remote design section 14). The overlay (Tailscale, WireGuard: whichever
# the separate horde-overlay repository runs) is how two machines reach each other. Its one contract
# with Horde is `horde-overlay endpoint --name <name> --json`, emitting schema/overlay-endpoint.v1,
# which Horde owns: the overlay imports nothing of Horde's and Horde imports nothing of its code.
# core/OverlayCommand.ps1 runs that command; this file only reads text, so remote/ still starts nothing
# (tools/ExecScan.ps1).
#   - Output that fails the schema, or answers for another overlay than the one asked, is unknown with
#     the reason - never a guessed address, never a host name to resolve.
#   - Health is ADVISORY. Whether a link exists is decided by the transport's own handshake: a healthy
#     overlay beside a refused handshake is unknown, "link refused (overlay reports healthy)", and an
#     unhealthy overlay cannot take a working link down.
#   - Horde never starts, stops or configures a tunnel: it asks one question and reads the answer.
#
# OWED: a key written twice in the output is read as its last copy, as ConvertFrom-Json does. The one
# duplicate-key scanner moves to core/JsonText.ps1 in PR #65; once that merges, this file reads through
# it (an ExecScan entry, argued there). Until then the schema check is the only gate.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path $PSScriptRoot "Contract.ps1")

# The overlay's output is a few hundred characters; 64 Ki characters is room for a large peer list.
$script:HordeOverlayMaxChars = 65536
# The peer an overlay:<name> hub address means when it names none.
$script:HordeOverlayDefaultPeer = "hub"

function Get-HordeOverlayPatterns {
    # The overlay-name, peer-name and address patterns, read from schema/overlay-endpoint.v1 so a hub
    # address is held to exactly the shapes the overlay's answer is - and re-anchored with \z: a final $
    # also matches before a trailing newline in .NET, so "100.64.0.2`n" passed (review of this PR; the
    # schema checker reads the same patterns in ECMAScript mode, core/Schema.ps1).
    $s = Get-HordeSchema -Name "overlay-endpoint.v1"
    return [pscustomobject]@{
        name = ("$($s.properties.overlay.pattern)" -replace '\$$', '\z')
        peer = ("$($s.properties.peers.items.properties.name.pattern)" -replace '\$$', '\z')
        address = ("$($s.definitions.address.pattern)" -replace '\$$', '\z')
    }
}

function ConvertFrom-HordeHubAddress {
    # A configured hub address: known { kind = "address"; address } for an IP address, known { kind =
    # "overlay"; name; peer } for overlay:<name> or overlay:<name>/<peer>, unknown for anything else. The
    # peer is which of the overlay's peers is the hub, "hub" when the address names none. A host name is
    # refused: resolving names is the overlay's job, and a name resolved here could reach any machine.
    # Turning an overlay address into an IP - this, then core/OverlayCommand.ps1's answer, then
    # Get-HordeOverlayPeerAddress - is the node's link code's to compose (R12), where the address is read.
    param([string]$Address)
    $p = Get-HordeOverlayPatterns
    if ($Address.StartsWith("overlay:", [System.StringComparison]::Ordinal)) {
        $rest = $Address.Substring(8)
        $name = $rest
        $peer = $script:HordeOverlayDefaultPeer
        $slash = $rest.IndexOf("/")
        if ($slash -ge 0) { $name = $rest.Substring(0, $slash); $peer = $rest.Substring($slash + 1) }
        if ($name -cnotmatch $p.name) { return (New-HordeUnknown -Reason ("'" + $name + "' is not an overlay name: a letter or digit, then letters, digits, dots, underscores or hyphens")) }
        if ($peer -cnotmatch $p.peer) { return (New-HordeUnknown -Reason ("'" + $peer + "' is not a peer name")) }
        return (New-HordeKnown -Value ([pscustomobject]@{ kind = "overlay"; name = $name; peer = $peer }))
    }
    if ($Address -cmatch $p.address) { return (New-HordeKnown -Value ([pscustomobject]@{ kind = "address"; address = $Address })) }
    return (New-HordeUnknown -Reason ("'" + $Address + "' is neither an IP address nor overlay:<name>; a host name is the overlay's to resolve"))
}

function Read-HordeOverlayEndpoint {
    # The overlay's answer to `endpoint --name <Name> --json`, as a known endpoint document, or unknown
    # with the reason. The text is printable ASCII within the cap, JSON, schema/overlay-endpoint.v1 with
    # its answer rule, and about the overlay that was asked.
    param([string]$Text, [Parameter(Mandatory = $true)][string]$Name)
    if ($Text.Length -gt $script:HordeOverlayMaxChars) { return (New-HordeUnknown -Reason ("the overlay's answer is longer than " + $script:HordeOverlayMaxChars + " characters")) }
    if ($Text.Trim() -eq "") { return (New-HordeUnknown -Reason "the overlay gave no answer") }
    foreach ($c in $Text.ToCharArray()) {
        $n = [int]$c
        if ($n -gt 126 -or ($n -lt 32 -and $n -ne 9 -and $n -ne 10 -and $n -ne 13)) { return (New-HordeUnknown -Reason "the overlay's answer holds a character that is not printable ASCII") }
    }
    $doc = $null
    try { $doc = ConvertFrom-HordeJson -Text ($Text) } catch { return (New-HordeUnknown -Reason "the overlay's answer is not JSON") }
    $found = @(Test-HordeContractDocument -Value $doc -SchemaName "overlay-endpoint.v1")
    if ($found.Count -gt 0) { return (New-HordeUnknown -Reason ("the overlay's answer fails schema/overlay-endpoint.v1, so no address is taken from it: " + $found[0])) }
    if ("$($doc.overlay)" -cne $Name) { return (New-HordeUnknown -Reason ("asked about overlay '" + $Name + "', the answer is about '" + $doc.overlay + "'")) }
    return (New-HordeKnown -Value $doc)
}

function Get-HordeOverlayPeerAddress {
    # The address the overlay gives for -Peer, matched exactly, or unknown: never a guess.
    param([Parameter(Mandatory = $true)]$Endpoint, [Parameter(Mandatory = $true)][string]$Peer)
    if ($Endpoint.state -cne "known") { return (New-HordeUnknown -Reason ("the overlay's answer is unknown: " + $Endpoint.reason)) }
    $peers = @()
    if ($null -ne $Endpoint.value) { $peers = @($Endpoint.value.peers) }
    foreach ($p in $peers) {
        if ("$($p.name)" -ceq $Peer) { return (New-HordeKnown -Value "$($p.address)") }
    }
    return (New-HordeUnknown -Reason ("the overlay lists no peer named '" + $Peer + "'"))
}

function Get-HordeOverlayLinkAnswer {
    # Is the link up? The transport's handshake decides; the overlay's health only explains a failure.
    param([Parameter(Mandatory = $true)]$Endpoint, [Parameter(Mandatory = $true)]$Handshake)
    # A boolean true, not anything -eq coerces to it: 1 and @("no", $true) both compared equal (review).
    if ("$($Handshake.state)" -ceq "known" -and $Handshake.value -is [bool] -and $Handshake.value) { return (New-HordeKnown -Value $true) }
    $why = "$($Handshake.reason)"
    if ($why -eq "") { $why = "the handshake did not succeed" }
    $note = "overlay state unknown"
    if ($Endpoint.state -ceq "known") {
        $h = $Endpoint.value.health
        if ("$($h.state)" -ceq "known" -and $h.value -is [bool] -and $h.value) { $note = "overlay reports healthy" }
        elseif ("$($h.state)" -ceq "known") { $note = "overlay reports unhealthy" }
        elseif ("$($h.state)" -ceq "absent") { $note = "overlay reports no health: " + $h.reason }
        else { $note = "overlay health unknown: " + $h.reason }
    } else { $note = "overlay answer unknown: " + $Endpoint.reason }
    return (New-HordeUnknown -Reason ($why + " (" + $note + ")"))
}
