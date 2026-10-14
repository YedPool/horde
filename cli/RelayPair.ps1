# cli/RelayPair - `horde relay pair`: pair the founder's phone with this machine, at this machine.
#
# WHAT IT DOES, in order (relay design 2026-10-09; relay/Pairing.ps1 has every rule it relies on):
#   1. makes a one-time offer (New-HordeRelayPairingOffer) for the relying party and origin of the
#      phone app - the relay settings pairRpId and pairOrigin, or -RpId and -Origin;
#   2. shows it: as a QR code in a PNG it writes to the temporary folder and opens locally
#      (cli/QrCode.ps1 says why a PNG and not text), and as text, for the app's paste box;
#      The offer lives -TtlSeconds, 30 to 900; 600 (ten minutes) when not given (THE OFFER'S LIFE, below);
#   3. waits, until the offer expires, for the phone's response: through the relay, in the offer's own
#      pairing mailbox (Open-HordeRelayPairingSealed refuses everything not sealed for this offer), or
#      pasted here - a plain response, or the sealed text;
#   4. completes the pairing (Complete-HordeRelayPairing): the phone's passkey is enrolled PENDING;
#   5. asks the founder to TYPE the 12-digit fingerprint HIS PHONE shows, and compares it
#      (Confirm-HordeRelayDevice). Three wrong tries, or "reject", reject the device (it is revoked).
#
# WHY THE MACHINE NEVER PRINTS ITS OWN FINGERPRINT. What protects a stolen offer (relay/Pairing.ps1,
# WHAT A STOLEN OFFER CAN AND CANNOT DO) is the founder entering what his PHONE shows: a thief who
# registered first left a device whose fingerprint is not the one on the founder's phone. A machine
# that printed its number and asked for it back would let a founder copy it from the screen without
# looking at his phone, and confirm the thief. So this command shows which device registered and asks
# for the phone's number; the comparison is the machine's, never the founder's eye.
#
# THE INPUT is the keyboard - read a key at a time while the relay is watched, so a response can be
# pasted while one may still arrive through the relay - or, with -InputFile, a file read as it grows,
# line by line: the seam a script or a suite types through (never a redirected stdin). A console whose
# input is redirected and no -InputFile: lines are read from stdin only where the command blocks for
# one (the fingerprint), so nothing can be pasted while it waits.
#
# A CLEAN END. On a response, a refusal, the offer's expiry or Ctrl+C, the PNG is deleted (the offer
# is a bearer secret for its short life) and the pairing mailbox is acked through what was read. An
# offer interrupted while it waits (Ctrl+C) is voided (Close-HordeRelayPairingOffer); one that
# expired needs nothing. A process killed outright runs no finally block, so every
# pairing that starts first sweeps the pictures older than the longest an offer lives (900 s).
#
# THE OFFER'S LIFE AND ITS COUNTDOWN (founder decision 2026-10-14, issue #283: twice that day an offer
# expired while he copied it by hand). An offer lives 600 s unless -TtlSeconds says otherwise, 30 to 900
# (relay/Pairing.ps1's limits; the picture sweep above relies on the 900). The offer line says until when
# and for how long; while it waits, the command says the time left each time it falls past a whole
# minute, then every 10 s in the last minute - one line a step, never one a look, so a log stays short.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

# The machine's name for its offer (relay/Pairing.ps1, THE LABEL): the computer's, as a device name.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Device.ps1")

# How many refused items one pairing mailbox may bring before the offer is given up: each costs an
# ECDH, and a relay flooding the mailbox could otherwise keep the machine opening garbage until the
# offer expires. An honest pairing brings one item, and a phone that sends again stores once (its key).
$script:HordeRelayPairMaxRefused = 32
# How long one watch of the pairing mailbox waits: short, so a paste is noticed within a second.
$script:HordeRelayPairWatchMs = 1000
# A WATCH THAT FAILED IS TRIED AGAIN AFTER 5 s, THEN 10, THEN EVERY 15 s, or after the relay's own
# Retry-After when that is longer; one that works starts the count again. The wait is spent reading the
# keyboard, so a paste still lands at once. Why (the founder's first live use, 2026-10-11): the hosted
# relay answers 401 until the phone registers this machine, and a try every 1 to 6 s tripped the
# Worker's refused-signature limit (10 a minute per key, in the hosted relay's worker limits), 429, for
# about 90 s. Every 15 s is 4 a minute, under it.
$script:HordeRelayPairRetryFirstMs = 5000
$script:HordeRelayPairRetryMostMs = 15000
# The relay's statuses that mean "it refuses this machine": not registered yet (401), and the limit
# that refusing it trips (429). Said once, as waiting for the phone, never as the relay's raw words.
$script:HordeRelayPairRefusedStatuses = @(401, 429)
$script:HordeRelayPairTries = 3
# How long an offer lives when -TtlSeconds is not given (THE OFFER'S LIFE, in the header).
$script:HordeRelayPairDefaultTtlSeconds = 600

function Test-HordeRelayPairTtl {
    # Why -TtlSeconds is refused, or "" when it is 30 to 900 (relay/Pairing.ps1's limits).
    param([int]$TtlSeconds)
    $l = Get-HordeRelayPairingLimits
    if ($TtlSeconds -lt $l.minTtlSeconds -or $TtlSeconds -gt $l.maxTtlSeconds) {
        return ("-TtlSeconds is how many seconds the offer stays open: " + $l.minTtlSeconds + " to " + $l.maxTtlSeconds + ", not " + $TtlSeconds + " (" + $script:HordeRelayPairDefaultTtlSeconds + ", ten minutes, when not given)")
    }
    return ""
}

function Format-HordeRelayPairSpan {
    # A length of time in plain words: "10 minutes", "1 minute 30 seconds", "45 seconds".
    param([long]$Ms)
    $s = [long][System.Math]::Ceiling([double]$Ms / 1000)
    $m = [long][System.Math]::Floor([double]$s / 60)
    $r = $s - $m * 60
    $parts = @()
    if ($m -gt 0) { $parts += ("" + $m + $(if ($m -eq 1) { " minute" } else { " minutes" })) }
    if ($r -gt 0 -or $m -eq 0) { $parts += ("" + $r + $(if ($r -eq 1) { " second" } else { " seconds" })) }
    return ($parts -join " ")
}

function Get-HordeRelayPairCountdownMark {
    # The step of the countdown -LeftMs falls in (THE OFFER'S LIFE, in the header): the whole minute at
    # or above it while more than a minute is left, then the 10 s at or above it. A new, smaller mark is
    # a line to say; the same mark is not.
    param([long]$LeftMs)
    if ($LeftMs -gt 60000) { return ([long][System.Math]::Ceiling([double]$LeftMs / 60000) * 60000) }
    return ([long][System.Math]::Ceiling([double]$LeftMs / 10000) * 10000)
}

function New-HordeRelayPairInput {
    # Where typed lines come from: -InputFile (read as it grows), else the console's keys, else - input
    # redirected - stdin, read only where the command blocks for a line. { mode; path; taken; buffer }.
    param([string]$InputFile = "")
    if ($InputFile -cne "") { return [pscustomobject]@{ mode = "file"; path = $InputFile; taken = 0; buffer = "" } }
    $redirected = $true
    try { $redirected = [Console]::IsInputRedirected } catch { $redirected = $true }
    return [pscustomobject]@{ mode = $(if ($redirected) { "stdin" } else { "console" }); path = ""; taken = 0; buffer = "" }
}

function Read-HordeRelayPairLine {
    # The next typed line, waiting up to -TimeoutMs for it; $null when none came in time. -Block waits
    # for a line where only a blocking read can (stdin). Throws "end of input" when the input has ended.
    param([Parameter(Mandatory = $true)]$Source, [int]$TimeoutMs = 0, [switch]$Block)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    if ($Source.mode -ceq "stdin") {
        if (-not $Block) { if ($TimeoutMs -gt 0) { Start-Sleep -Milliseconds $TimeoutMs }; return $null }
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { throw "end of input" }
        return $line
    }
    while ($true) {
        if ($Source.mode -ceq "file") {
            $text = ""
            if ([System.IO.File]::Exists($Source.path)) {
                # Shared, so the writer may keep the file open; only whole lines (ending LF) are taken.
                $fs = New-Object System.IO.FileStream($Source.path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try { $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::ASCII); $text = $sr.ReadToEnd() } finally { $fs.Dispose() }
            }
            $lines = $text.Split([char]10)
            if ($lines.Count - 1 -gt $Source.taken) {
                $line = $lines[$Source.taken].TrimEnd([char]13)
                $Source.taken++
                return $line
            }
        } else {
            while ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq [ConsoleKey]::Enter) { Write-Host ""; $line = $Source.buffer; $Source.buffer = ""; return $line }
                if ($k.Key -eq [ConsoleKey]::Backspace) {
                    if ($Source.buffer.Length -gt 0) { $Source.buffer = $Source.buffer.Substring(0, $Source.buffer.Length - 1); Write-Host -NoNewline ([string][char]8 + " " + [char]8) }
                    continue
                }
                $c = $k.KeyChar
                if ([int]$c -ge 0x20 -and [int]$c -le 0x7E) { $Source.buffer += [string]$c; Write-Host -NoNewline ([string]$c) }
            }
        }
        if ($clock.ElapsedMilliseconds -ge $TimeoutMs) { return $null }
        Start-Sleep -Milliseconds ([System.Math]::Min(100, [System.Math]::Max(1, $TimeoutMs - $clock.ElapsedMilliseconds)))
    }
}

function Remove-HordeRelayPairPictures {
    # Delete the pictures of offers in -Dir older than the longest an offer may live
    # (Get-HordeRelayPairingLimits): what a pairing killed outright, past its finally block, left
    # behind. Only names this command writes (horde-pair-<offer id>.png); a file that will not go is
    # left for the next sweep.
    param([Parameter(Mandatory = $true)][string]$Dir)
    $limit = [datetime]::UtcNow.AddSeconds(-(Get-HordeRelayPairingLimits).maxTtlSeconds)
    if (-not [System.IO.Directory]::Exists($Dir)) { return }
    foreach ($f in @([System.IO.Directory]::GetFiles($Dir, "horde-pair-*.png"))) {
        if ([System.IO.Path]::GetFileName($f) -cnotmatch '\Ahorde-pair-[0-9a-f]{32}\.png\z') { continue }
        try { if ([System.IO.File]::GetLastWriteTimeUtc($f) -lt $limit) { [System.IO.File]::Delete($f) } } catch { }
    }
}

function Get-HordeRelayPairTime {
    # A moment in milliseconds since 1970 as local hh:mm:ss, for what the founder reads.
    param([long]$Ms)
    return ([System.DateTimeOffset]::FromUnixTimeMilliseconds($Ms).LocalDateTime.ToString("HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))
}

function Get-HordeRelayPairOrigin {
    # The relying party and origin the offer names: -RpId and -Origin, else the relay settings pairRpId
    # and pairOrigin. Known { rpId; origins } or unknown saying what to set.
    param([string]$HordeHome, [string]$RpId = "", [string]$Origin = "")
    $s = Get-HordeRelaySettingValues -HordeHome $HordeHome
    if ($s.state -cne "known") { return $s }
    $rp = $(if ($RpId -cne "") { $RpId } else { "" + $s.value.values.pairRpId })
    $or = $(if ($Origin -cne "") { $Origin } else { "" + $s.value.values.pairOrigin })
    if ($rp -ceq "" -or $or -ceq "") { return (New-HordeUnknown -Reason "no phone app is named: give -RpId <host> and -Origin https://<host>, or set pairRpId and pairOrigin in the relay settings (settings\relay.json)") }
    return (New-HordeKnown -Value ([pscustomobject]@{ rpId = $rp; origins = @($or) }))
}

function Receive-HordeRelayPairText {
    # One text that arrived for the offer - through the relay (-Sealed: only a sealed response is taken
    # from it) or pasted - opened if sealed, and completed. { ok; reason; value; spent }: spent when the
    # offer can no longer enroll anything.
    param([string]$HordeHome, $Offer, [string]$Text, [string]$Label, $Now, [switch]$Sealed)
    $t = $Text.Trim()
    $response = $t
    if ($Sealed -or $t.StartsWith('{"v":1,"kind":"horde-relay-pairing-sealed"')) {
        $o = Open-HordeRelayPairingSealed -HordeHome $HordeHome -Offer $Offer.offer -Text $t -Now $Now
        if (-not $o.ok) { return [pscustomobject]@{ ok = $false; reason = $o.reason; value = $null; spent = $o.reason.Contains("already used") } }
        $response = $o.value
    } elseif (-not $t.StartsWith('{"v":1,"kind":"horde-relay-pairing-response"')) {
        return [pscustomobject]@{ ok = $false; reason = "that is not a pairing response: paste the text the phone shows under 'The answer for the machine'"; value = $null; spent = $false }
    } else {
        # A pasted response to ANOTHER offer - an old one, already used - is refused here, so that its
        # "already used" can never be read as this offer being spent.
        $m = [regex]::Match($t, '\A\{"v":1,"kind":"horde-relay-pairing-response","offer":"([0-9a-f]{32})"')
        if (-not $m.Success -or $m.Groups[1].Value -cne $Offer.offer) { return [pscustomobject]@{ ok = $false; reason = ("that response answers another offer than this one (" + $Offer.offer + "); pair the phone with the offer shown here"); value = $null; spent = $false } }
    }
    $c = Complete-HordeRelayPairing -HordeHome $HordeHome -Response $response -Label $Label -Now $Now
    $spent = ((-not $c.ok) -and ($c.reason.Contains("already used") -or $c.reason.Contains("the offer is now used") -or $c.reason.Contains("the offer is spent")))
    return [pscustomobject]@{ ok = $c.ok; reason = $c.reason; value = $c.value; spent = $spent }
}

function Get-HordeRelayPairRetryMs {
    # How long after the -Failures-th failed watch in a row the relay is watched again (the header of
    # this file): 5 s, 10 s, then 15 s - or -Answer's retryAfterMs, the relay's Retry-After carried by
    # relays/Port.ps1, when that is longer.
    param([int]$Failures, $Answer)
    $ms = [long][System.Math]::Min([double]$script:HordeRelayPairRetryMostMs, [double]$script:HordeRelayPairRetryFirstMs * $Failures)
    $p = $Answer.PSObject.Properties["retryAfterMs"]
    if ($null -ne $p -and [long]$p.Value -gt $ms) { $ms = [long]$p.Value }
    return $ms
}

function Get-HordeRelayPairDownWords {
    # What to say of a failed watch: a relay that refuses this machine (its status, relays/Port.ps1) is
    # waiting for the phone, in plain words; anything else is the relay's reason.
    param($Answer, [string]$Relay)
    $p = $Answer.PSObject.Properties["status"]
    if ($null -ne $p -and $script:HordeRelayPairRefusedStatuses -contains $p.Value) {
        return ("waiting for the phone to register this machine with the relay '" + $Relay + "': until it does, the relay refuses this machine, so it is asked again every 5 to 15 s; a pasted response works too")
    }
    return ("the relay could not be read (" + $Answer.reason + "); still waiting, and a pasted response works too")
}

function Wait-HordeRelayPairResponse {
    # Until the offer expires: watch its pairing mailbox (with -Connection) and the typed input, and
    # take the first response that completes. { ok; reason; value (Complete's) }.
    param([string]$HordeHome, $Offer, $Connection, $Source, [string]$Label, [scriptblock]$Say, [scriptblock]$Clock)
    $cursor = [long]0
    $refused = 0
    $lastDown = ""
    # Failed watches in a row, and when (ms) the relay is watched again (the header of this file).
    $failures = 0
    $retryAt = [long]0
    # The countdown's last step said (THE OFFER'S LIFE, in the header): the offer line said the start.
    $mark = [long]-1
    try {
        while ($true) {
            $now = & $Clock
            $nowMs = ConvertTo-HordeRelayRecordMs -Time $now
            if ($nowMs -gt $Offer.expiresAt) { return [pscustomobject]@{ ok = $false; reason = ("the offer expired at " + (Get-HordeRelayPairTime -Ms $Offer.expiresAt) + " with no response from the phone; nothing was enrolled. Run horde relay pair again for a new one"); value = $null } }
            $leftMs = [long]($Offer.expiresAt - $nowMs)
            $step = Get-HordeRelayPairCountdownMark -LeftMs $leftMs
            if ($mark -ge 0 -and $step -lt $mark -and $leftMs -gt 0) { $null = & $Say ("The offer is open for " + (Format-HordeRelayPairSpan -Ms $step) + " more, until " + (Get-HordeRelayPairTime -Ms $Offer.expiresAt) + ".") }
            $mark = $step
            $left = [int][System.Math]::Max(1, [System.Math]::Min([double]$script:HordeRelayPairWatchMs, [double]($Offer.expiresAt - $nowMs)))
            if ($null -ne $Connection -and $nowMs -lt $retryAt) {
                # Until the relay is watched again, the wait is spent reading the keyboard, so a paste
                # still lands at once (review of a3cce1c: 6,691 watches in 3 s without a wait), and a
                # line read early does not bring the next watch forward. A second a read at most, so
                # the countdown's 10 s steps are said on time while the relay waits 15 s.
                $line = Read-HordeRelayPairLine -Source $Source -TimeoutMs ([int][System.Math]::Max(1, [System.Math]::Min([System.Math]::Min([double]($retryAt - $nowMs), [double]$script:HordeRelayPairWatchMs), [double]($Offer.expiresAt - $nowMs + 1))))
                if ($null -ne $line -and $line.Trim() -cne "") {
                    $r = Receive-HordeRelayPairText -HordeHome $HordeHome -Offer $Offer -Text $line -Label $Label -Now (& $Clock)
                    if ($r.ok -or $r.spent) { return $r }
                    $null = & $Say ("refused: " + $r.reason)
                }
                continue
            }
            if ($null -ne $Connection) {
                $w = Wait-HordeRelayItems -Connection $Connection -Mailbox $Offer.pairMailbox -Since $cursor -TimeoutMs ([int][System.Math]::Min([double]$left, [double]$Connection.relay.limits.maxWatchMs))
                if ($w.state -cne "known") {
                    # Said once: a relay that stays down, or refuses with 401 and 429 in turn, is not a
                    # line a try.
                    $words = Get-HordeRelayPairDownWords -Answer $w -Relay $Connection.relay.name
                    if ($words -cne $lastDown) { $null = & $Say $words }
                    $lastDown = $words
                    $failures++
                    $retryAt = (ConvertTo-HordeRelayRecordMs -Time (& $Clock)) + (Get-HordeRelayPairRetryMs -Failures $failures -Answer $w)
                    continue
                } else {
                    $lastDown = ""
                    $failures = 0
                    foreach ($a in @($w.value.anomalies)) { $null = & $Say ("relay: " + $a) }
                    foreach ($item in @($w.value.items)) {
                        $cursor = $item.seq
                        $r = Receive-HordeRelayPairText -HordeHome $HordeHome -Offer $Offer -Text $item.text -Label $Label -Now (& $Clock) -Sealed
                        if ($r.ok) { return $r }
                        $refused++
                        $null = & $Say ("refused what the relay brought (item " + $item.seq + "): " + $r.reason)
                        if ($r.spent) { return $r }
                        if ($refused -ge $script:HordeRelayPairMaxRefused) { return [pscustomobject]@{ ok = $false; reason = ("the pairing mailbox brought " + $refused + " refused items; the offer is given up. Run horde relay pair again"); value = $null } }
                    }
                }
            }
            $line = Read-HordeRelayPairLine -Source $Source -TimeoutMs $(if ($null -eq $Connection) { $left } else { 0 })
            if ($null -ne $line -and $line.Trim() -cne "") {
                $r = Receive-HordeRelayPairText -HordeHome $HordeHome -Offer $Offer -Text $line -Label $Label -Now (& $Clock)
                if ($r.ok -or $r.spent) { return $r }
                $null = & $Say ("refused: " + $r.reason)
            }
        }
    } finally {
        if ($null -ne $Connection -and $cursor -gt 0) { $null = Confirm-HordeRelayItems -Connection $Connection -Mailbox $Offer.pairMailbox -Through $cursor }
    }
}

function Get-HordeRelayPairRevokeFailure {
    # What to say when a device to reject could not be revoked: not "revoked". It stays pending - so it
    # trusts nothing - until its window closes, and the command that ends it now.
    param($Device, [long]$PendingUntil, [string]$Why)
    return [pscustomobject]@{ ok = $false; value = $null; reason = ("the device " + $Device.id + " could not be revoked (" + $Why + "). It stays pending, trusting nothing, until " +
        (Get-HordeRelayPairTime -Ms $PendingUntil) + " when its window closes; to end it now: horde relay trust revoke " + $Device.id) }
}

function Confirm-HordeRelayPairFingerprint {
    # Ask for the fingerprint the phone shows and compare it (the header): up to three tries before the
    # device is rejected; "reject" rejects it at once. { ok; reason; value (the trusted device) }.
    param([string]$HordeHome, $Device, [long]$PendingUntil, $Source, [scriptblock]$Say, [scriptblock]$Clock)
    $null = & $Say ""
    $null = & $Say ("A phone registered: '" + $Device.label + "' (device " + $Device.id + "). It waits, PENDING, until " + (Get-HordeRelayPairTime -Ms $PendingUntil) + ".")
    $null = & $Say "Look at your PHONE: it shows a 12-digit number. Type that number here (or type reject):"
    $tries = 0
    while ($true) {
        $nowMs = ConvertTo-HordeRelayRecordMs -Time (& $Clock)
        if ($nowMs -gt $PendingUntil) { return [pscustomobject]@{ ok = $false; reason = ("the confirm window closed at " + (Get-HordeRelayPairTime -Ms $PendingUntil) + "; the device " + $Device.id + " expired unconfirmed. Run horde relay pair again"); value = $null } }
        try { $line = Read-HordeRelayPairLine -Source $Source -TimeoutMs ([int][System.Math]::Min(1000, $PendingUntil - $nowMs + 1)) -Block }
        catch { return [pscustomobject]@{ ok = $false; reason = ("no number was typed (the input ended); the device " + $Device.id + " stays pending until its window closes, and trusts nothing"); value = $null } }
        if ($null -eq $line -or $line.Trim() -ceq "") { continue }
        if ($line.Trim() -ieq "reject") {
            $rv = Revoke-HordeRelayTrust -HordeHome $HordeHome -Subject "device" -Id $Device.id -Reason "rejected at the machine during horde relay pair" -Now (& $Clock)
            if ($rv.state -cne "known") { return (Get-HordeRelayPairRevokeFailure -Device $Device -PendingUntil $PendingUntil -Why $rv.reason) }
            return [pscustomobject]@{ ok = $false; reason = ("the device " + $Device.id + " was rejected; it is revoked and never trusted"); value = $null }
        }
        $c = Confirm-HordeRelayDevice -HordeHome $HordeHome -Id $Device.id -Fingerprint $line.Trim() -Now (& $Clock)
        if ($c.ok) { return [pscustomobject]@{ ok = $true; reason = ""; value = $c.value.device } }
        if (-not $c.reason.Contains("does not match")) { return [pscustomobject]@{ ok = $false; reason = $c.reason; value = $null } }
        $tries++
        if ($tries -ge $script:HordeRelayPairTries) {
            $rv = Revoke-HordeRelayTrust -HordeHome $HordeHome -Subject "device" -Id $Device.id -Reason "the number typed at the machine did not match the phone's fingerprint three times" -Now (& $Clock)
            if ($rv.state -cne "known") { return (Get-HordeRelayPairRevokeFailure -Device $Device -PendingUntil $PendingUntil -Why $rv.reason) }
            return [pscustomobject]@{ ok = $false; reason = ("that number does not match either, three times: the device " + $Device.id + " is not the phone in your hand, or the number was misread. It is rejected (revoked); run horde relay pair again"); value = $null }
        }
        $null = & $Say ("That number does not match the device that registered (" + ($script:HordeRelayPairTries - $tries) + " tries left). If your phone shows another number, type reject: the device that registered is not your phone.")
    }
}

function Invoke-HordeRelayPair {
    # The whole command (the header). -Connection is a relays/Port.ps1 connection, or $null to take a
    # pasted response only; -Say receives each line; -OpenPicture opens the PNG (the command starts the
    # system's viewer; a suite records the path); -Clock answers the time (a suite moves it).
    # { ok; reason; device; offer }.
    param([string]$HordeHome = "", $Connection = $null, [string]$RpId = "", [string]$Origin = "", [string]$Label = "", [string]$InputFile = "",
        [Parameter(Mandatory = $true)][scriptblock]$Say, [scriptblock]$OpenPicture = $null, [scriptblock]$Clock = $null, [int]$TtlSeconds = $script:HordeRelayPairDefaultTtlSeconds, $Source = $null, [string]$PictureDir = "")
    $done = [pscustomobject]@{ ok = $false; reason = ""; device = $null; offer = $null }
    # Refused before anything is made or read, in the command's words, not the offer maker's.
    $ttlWhy = Test-HordeRelayPairTtl -TtlSeconds $TtlSeconds
    if ($ttlWhy -cne "") { $done.reason = $ttlWhy; return $done }
    if ($HordeHome -ceq "") { $HordeHome = Get-HordeHome }
    if ($null -eq $Clock) { $Clock = { [datetime]::UtcNow } }
    if ($null -eq $Source) { $Source = New-HordeRelayPairInput -InputFile $InputFile }
    if ($Label -cne "" -and (Test-HordeRelayRecordValue -Kind "label" -Value $Label) -cne "") { $done.reason = "-Label is 1 to 64 printable ASCII characters, no quote or backslash, no space at either end"; return $done }
    $where = Get-HordeRelayPairOrigin -HordeHome $HordeHome -RpId $RpId -Origin $Origin
    if ($where.state -cne "known") { $done.reason = $where.reason; return $done }
    # The machine's name, which a hosted relay's Account screen lists it by (relay/Pairing.ps1, THE LABEL).
    $o = New-HordeRelayPairingOffer -HordeHome $HordeHome -RpId $where.value.rpId -Origins $where.value.origins -TtlSeconds $TtlSeconds -Now (& $Clock) -Label (ConvertTo-HordeDeviceName -Text "$env:COMPUTERNAME")
    if ($o.state -cne "known") { $done.reason = ("no offer was made: " + $o.reason); return $done }
    $offer = $o.value
    $done.offer = $offer
    # -PictureDir is the temporary folder unless a suite names its own.
    if ($PictureDir -ceq "") { $PictureDir = [System.IO.Path]::GetTempPath() }
    Remove-HordeRelayPairPictures -Dir $PictureDir
    $png = [System.IO.Path]::Combine($PictureDir, ("horde-pair-" + $offer.offer + ".png"))
    # Set once the command ends by itself; an interruption (Ctrl+C) leaves it false, and the offer is
    # voided on the way out, so a phone that answers it later enrolls nothing nobody is watching.
    $ended = $false
    try {
        $code = New-HordeQrCode -Text $offer.text -Level "M"
        [System.IO.File]::WriteAllBytes($png, (ConvertTo-HordeQrPng -Code $code -Scale 6 -Border 4))
        $null = & $Say ("Pairing offer " + $offer.offer + ", open until " + (Get-HordeRelayPairTime -Ms $offer.expiresAt) + " (" + (Format-HordeRelayPairSpan -Ms ([long]$TtlSeconds * 1000)) + ").")
        $null = & $Say ("Scan this QR code with the phone app (Pair with a machine, Scan the QR code): " + $png)
        if ($null -ne $OpenPicture) { $null = & $OpenPicture $png }
        $null = & $Say "Or paste this offer into the app:"
        $null = & $Say $offer.text
        if ($null -ne $Connection) { $null = & $Say ("Waiting for the phone's response through the relay '" + $Connection.relay.name + "' (" + $offer.pairMailbox + "); a response pasted here works too.") }
        else { $null = & $Say "No relay is named (-Relay), so paste the phone's response here when it shows it." }
        $got = Wait-HordeRelayPairResponse -HordeHome $HordeHome -Offer $offer -Connection $Connection -Source $Source -Label $Label -Say $Say -Clock $Clock
        if (-not $got.ok) { $ended = $true; $done.reason = $got.reason; return $done }
        # The PNG goes as soon as the offer is used: it opens nothing now, and the window can close.
        try { [System.IO.File]::Delete($png) } catch { }
        $ended = $true
        $k = Confirm-HordeRelayPairFingerprint -HordeHome $HordeHome -Device $got.value.device -PendingUntil $got.value.pendingUntil -Source $Source -Say $Say -Clock $Clock
        if (-not $k.ok) { $done.reason = $k.reason; return $done }
        $done.ok = $true
        $done.device = $k.value
        $null = & $Say ("Confirmed: '" + $k.value.label + "' (device " + $k.value.id + ") is trusted. On the phone, tap 'I confirmed it at the machine: announce this phone'.")
        return $done
    } finally {
        try { if ([System.IO.File]::Exists($png)) { [System.IO.File]::Delete($png) } } catch { }
        if (-not $ended) { $null = Close-HordeRelayPairingOffer -HordeHome $HordeHome -Offer $offer.offer }
    }
}

function Get-HordeRelayTrustLines {
    # The trust store, one line an entry, for `horde relay trust list`.
    param($Trust)
    $out = New-Object System.Collections.ArrayList
    foreach ($d in @($Trust.devices)) {
        # No fingerprint, in any state: a pending device's is the number `relay pair` waits for, and the
        # founder must read it from his phone, never copy it from here (review of a3cce1c).
        $line = "device " + $d.id + "  " + $d.state + "  '" + $d.label + "'  key " + $d.keyId
        if ($null -ne $d.revoked) { $line += "  revoked: " + $d.revoked.reason }
        [void]$out.Add($line)
    }
    foreach ($m in @($Trust.machines)) { [void]$out.Add("machine " + $m.keyId + "  " + $m.state + "  '" + $m.label + "'" + $(if ("" + $m.why -cne "") { "  (" + $m.why + ")" } else { "" })) }
    foreach ($p in @($Trust.phones)) { [void]$out.Add("phone key " + $p.agreeKeyId + "  " + $p.state + "  vouched for by " + $p.by + $(if ("" + $p.why -cne "") { "  (" + $p.why + ")" } else { "" })) }
    if ($out.Count -eq 0) { [void]$out.Add("the trust store is empty: no phone or machine is paired with this one (horde relay pair)") }
    return @($out.ToArray())
}

function Invoke-HordeRelayTrustRevoke {
    # Revoke the device or peer machine -Id names (a device id or a machine's key id). The lines to
    # print, or a throw naming why nothing was revoked.
    param([string]$HordeHome = "", [string]$Id, [string]$Reason = "revoked at the machine with horde relay trust revoke")
    $t = Get-HordeRelayTrust -HordeHome $HordeHome
    if ($t.state -cne "known") { throw ("the trust store cannot be read, so nothing is revoked: " + $t.reason) }
    $subject = ""
    if (@($t.value.devices | Where-Object { $_.id -ceq $Id }).Count -gt 0) { $subject = "device" }
    elseif (@($t.value.machines | Where-Object { $_.keyId -ceq $Id }).Count -gt 0) { $subject = "machine" }
    else { throw ("the trust store holds no device or machine '" + $Id + "' (horde relay trust list shows the ids)") }
    $r = Revoke-HordeRelayTrust -HordeHome $HordeHome -Subject $subject -Id $Id -Reason $Reason
    if ($r.state -cne "known") { throw ("the " + $subject + " " + $Id + " was not revoked: " + $r.reason) }
    if ($r.value.already) { return @("the " + $subject + " " + $Id + " was already revoked: " + $r.value.revocation.reason) }
    return @("revoked the " + $subject + " " + $Id + ": it signs nothing this machine accepts, for good")
}

function Get-HordeRelayIdentityLines {
    # This machine's relay identity, for `horde relay identity`.
    param($Identity)
    $v = $Identity
    return @(
        ("horde: " + $v.horde),
        ("signing key: " + $v.sign.keyId + "  (" + $v.sign.provider + ", " + $v.scope + " scope)"),
        ("agreement key: " + $v.agree.keyId + "  (" + $v.agree.provider + ", " + $v.scope + " scope)"),
        ("mailbox: " + $v.mailbox),
        ("generation: " + $v.generation + ", made " + ([System.DateTimeOffset]::FromUnixTimeMilliseconds([long]$v.createdAt).UtcDateTime.ToString("yyyy-MM-dd HH:mm 'UTC'", [System.Globalization.CultureInfo]::InvariantCulture)))
    )
}
