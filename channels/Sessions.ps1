# channels/Sessions.ps1 - what this machine keeps of the founder's unlocked phone sessions, and the
# session member it hands relay/Session.ps1 on each trusted passkey (relay/Session.ps1, WHAT THE MACHINE
# TAKES). relay/ judges; this file remembers, by the PC's own clock.
#
# WHERE: <HORDE_HOME>\relay\sessions\
#   vouches\<vouchId>.json   every vouch the PC took, write-once (relay/Records.ps1): the vouch text, the
#                            passkey assertion over it, which passkey (by) and when the PC recorded it.
#                            Like a phone key's vouch it is the founder's own signature, so it stays
#                            provable once the envelope that carried it is gone; it is checked again
#                            against its passkey every time a policy is built from it.
#   ended\ended-<ms>-<8 hex>.json
#                            each "end all phone sessions" at the PC (`horde relay sessions end`),
#                            write-once: every vouch whose window began, or which the PC recorded, at
#                            or before it is over (session-ended), whatever its own times say.
#   state.json               when the PC last took an envelope under each vouch (seen), and the newest
#                            session refusals it gave (refused) - the idle clock and what the phone is
#                            told. Replaced whole in one rename (core/FileAtomic.ps1). Lost or damaged,
#                            it is empty: idle then counts from when each vouch was recorded, which can
#                            only end a session sooner, never keep one alive.
# A vouch record that is damaged makes the records unreadable as a whole (broken), as the trust store
# does: a record that cannot be read cannot be honoured, so no session is taken until it is repaired;
# a passkey still signs every envelope as before.
#
# THE IDLE LIMIT is the module setting idleMinutes (relay-sessions, <HORDE_HOME>\settings\
# relay-sessions.json), 60 by default, at most 480 (the 8-hour cap, which no setting moves).
#
# THE HONEST LIMIT is the journal's and the trust store's (relay/Journal.ps1): whoever can write to
# <HORDE_HOME> can delete an "ended" record or rewind state.json. That access is already the owner's.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\FileAtomic.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "relay\Journal.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "relay\Trust.ps1")

$script:HordeRelaySessionSettings = New-HordeModuleSettings -Module "relay-sessions" -Settings @(
    # 480 at most: a session never outlives its 8-hour cap (relay/Session.ps1), so a longer idle limit
    # would be a setting that does nothing.
    @{ name = "idleMinutes"; kind = "whole"; default = 60; min = 1; max = 480
       what = "How many minutes a phone session may go unused before this PC refuses it (the founder unlocks again)." }
)
# What the PC remembers of refusals for the phone: the newest 32, and seen times of vouches up to a day
# past their cap - long enough to say "expired" rather than "unknown" to a phone that comes back late.
$script:HordeRelaySessionRefusedMost = 32
$script:HordeRelaySessionKeepPastMs = [long]86400000
# How many vouches of one passkey the phone is told of in a receipt: the newest.
$script:HordeRelaySessionStatusMost = 8

function Get-HordeRelaySessionRecordSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "vouchId", "hex32", "by", "hex32", "vouch", "b64u",
        "authenticatorData", "b64u", "clientDataJSON", "b64u", "signature", "b64u", "recordedAt", "int"))
}

function Get-HordeRelaySessionEndedSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "endedAt", "int", "reason", "text"))
}

function Get-HordeRelaySessionsDir {
    param([string]$HordeHome = "")
    return (Get-HordeRelayStateDir -HordeHome $HordeHome -Part "sessions")
}

function Get-HordeRelaySessionIdleMs {
    # The idle limit in milliseconds, or a throw naming the refused setting.
    param([string]$HordeHome = "")
    $homeDir = $HordeHome
    if ($homeDir -ceq "") { $homeDir = Get-HordeHome }
    $s = Get-HordeModuleSettings -Declaration $script:HordeRelaySessionSettings -HordeHome $homeDir
    if ($s.state -ceq "refused") { throw ($s.findings -join " ") }
    return ([long]$s.values.idleMinutes * 60000)
}

function Get-HordeRelaySessionSkewMs {
    # The journal's clockSkewSeconds (relay/Journal.ps1), in milliseconds: how far a phone's clock may run
    # ahead. 600 s when the setting cannot be read: the journal refuses everything then anyway.
    param([string]$HordeHome = "")
    try {
        $homeDir = $HordeHome
        if ($homeDir -ceq "") { $homeDir = Get-HordeHome }
        $s = Get-HordeModuleSettings -Declaration $script:HordeRelayJournalSettings -HordeHome $homeDir
        if ($s.state -cne "refused") { return ([long]$s.values.clockSkewSeconds * 1000) }
    } catch { }
    return [long]600000
}

function Read-HordeRelaySessionState {
    # state.json: { seen (vouchId -> ms); refused (list of { from; vouchId; code; at }) }. Empty when it is
    # not there or does not read (the header).
    param([string]$HordeHome = "")
    $out = [pscustomobject]@{ seen = @{}; refused = (New-Object System.Collections.ArrayList) }
    try {
        $path = [System.IO.Path]::Combine((Get-HordeRelaySessionsDir -HordeHome $HordeHome), "state.json")
        if (-not [System.IO.File]::Exists($path)) { return $out }
        $j = ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($path))
        if ($null -eq $j -or $null -eq $j.PSObject.Properties["v"] -or $j.v -ne 1) { return $out }
        if ($null -ne $j.PSObject.Properties["seen"] -and $null -ne $j.seen) {
            foreach ($p in @($j.seen.PSObject.Properties)) {
                if ($p.Name -cmatch '\A[0-9a-f]{32}\z' -and ($p.Value -is [int] -or $p.Value -is [long])) { $out.seen[$p.Name] = [long]$p.Value }
            }
        }
        if ($null -ne $j.PSObject.Properties["refused"]) {
            foreach ($r in @($j.refused)) {
                if ($null -eq $r) { continue }
                if ("$($r.from)" -cmatch '\A[0-9a-f]{32}\z' -and "$($r.vouchId)" -cmatch '\A[0-9a-f]{32}\z' -and (Get-HordeRelaySessionRefusals) -ccontains "$($r.code)") {
                    [void]$out.refused.Add([pscustomobject]@{ from = "$($r.from)"; vouchId = "$($r.vouchId)"; code = "$($r.code)"; at = [long]$r.at })
                }
            }
        }
    } catch { return [pscustomobject]@{ seen = @{}; refused = (New-Object System.Collections.ArrayList) } }
    return $out
}

function Write-HordeRelaySessionState {
    # state.json written beside itself and moved over the old one in one step. "" when kept, else why not.
    param([string]$HordeHome = "", $State, [long]$NowMs)
    try {
        $dir = Get-HordeRelaySessionsDir -HordeHome $HordeHome
        [void][System.IO.Directory]::CreateDirectory($dir)
        $seen = @(@($State.seen.Keys) | Sort-Object | Where-Object { [long]$State.seen[$_] -ge ($NowMs - [long]28800000 - $script:HordeRelaySessionKeepPastMs) } | ForEach-Object { '"' + $_ + '":' + [long]$State.seen[$_] })
        $ref = @(@($State.refused) | Select-Object -Last $script:HordeRelaySessionRefusedMost | ForEach-Object { '{"from":"' + $_.from + '","vouchId":"' + $_.vouchId + '","code":"' + $_.code + '","at":' + [long]$_.at + '}' })
        $text = '{"v":1,"seen":{' + ($seen -join ",") + '},"refused":[' + ($ref -join ",") + ']}'
        $path = [System.IO.Path]::Combine($dir, "state.json")
        $temp = $path + "." + $PID + ".tmp"
        [System.IO.File]::WriteAllText($temp, $text, [System.Text.Encoding]::ASCII)
        Move-HordeFileAtomic -From $temp -To $path
        return ""
    } catch { return ("" + $_.Exception.Message) }
}

function Read-HordeRelaySessionRecords {
    # Every vouch record and every "end all", checked: { ok; reason; vouches; endedAt; state } - vouches a
    # list of { record; vouch } (vouch is Read-HordeRelaySessionVouch's value), endedAt the newest end, 0
    # for none. Not ok, with the reason, when any record is damaged (the header).
    param([string]$HordeHome = "")
    $fail = [pscustomobject]@{ ok = $false; reason = ""; vouches = @(); endedAt = [long]0; state = $null }
    try { $dir = Get-HordeRelaySessionsDir -HordeHome $HordeHome } catch { $fail.reason = $_.Exception.Message; return $fail }
    $vdir = [System.IO.Path]::Combine($dir, "vouches")
    $names = Get-HordeRelayRecordNames -Dir $vdir -Pattern '\A[0-9a-f]{32}\.json\z'
    if (-not $names.ok) { $fail.reason = $names.reason; return $fail }
    $out = New-Object System.Collections.ArrayList
    foreach ($n in @($names.names)) {
        $f = Read-HordeRelayRecordFile -Path ([System.IO.Path]::Combine($vdir, $n))
        if (-not $f.ok) { $fail.reason = $f.reason; return $fail }
        $r = Read-HordeRelayRecordText -Text $f.text -Spec (Get-HordeRelaySessionRecordSpec) -Kind "horde-relay-session-record" -What ("the session record " + $n)
        if (-not $r.ok) { $fail.reason = $r.reason; return $fail }
        if ($n -cne ($r.value.vouchId + ".json")) { $fail.reason = ("the session record " + $n + " is filed under another vouchId than its own"); return $fail }
        $text = [System.Text.Encoding]::ASCII.GetString((ConvertFrom-HordeRelayBase64Url -Text $r.value.vouch -What "the recorded vouch"))
        $v = Read-HordeRelaySessionVouch -Text $text
        if (-not $v.ok) { $fail.reason = ("the session record " + $n + " holds a vouch that does not read: " + $v.reason); return $fail }
        if ($v.value.vouchId -cne $r.value.vouchId -or $v.value.deviceKeyId -cne $r.value.by) { $fail.reason = ("the session record " + $n + " does not say what its vouch says"); return $fail }
        [void]$out.Add([pscustomobject]@{ record = $r.value; vouch = $v.value })
    }
    $edir = [System.IO.Path]::Combine($dir, "ended")
    $enames = Get-HordeRelayRecordNames -Dir $edir -Pattern '\Aended-[0-9]{16}-[0-9a-f]{8}\.json\z'
    if (-not $enames.ok) { $fail.reason = $enames.reason; return $fail }
    $endedAt = [long]0
    foreach ($n in @($enames.names)) {
        $f = Read-HordeRelayRecordFile -Path ([System.IO.Path]::Combine($edir, $n))
        if (-not $f.ok) { $fail.reason = $f.reason; return $fail }
        $r = Read-HordeRelayRecordText -Text $f.text -Spec (Get-HordeRelaySessionEndedSpec) -Kind "horde-relay-sessions-ended" -What ("the end record " + $n)
        if (-not $r.ok) { $fail.reason = $r.reason; return $fail }
        if (-not $n.StartsWith("ended-" + ([long]$r.value.endedAt).ToString("D16") + "-")) { $fail.reason = ("the end record " + $n + " is filed under another time than its own"); return $fail }
        if ([long]$r.value.endedAt -gt $endedAt) { $endedAt = [long]$r.value.endedAt }
    }
    return [pscustomobject]@{ ok = $true; reason = ""; vouches = @($out.ToArray()); endedAt = $endedAt; state = (Read-HordeRelaySessionState -HordeHome $HordeHome) }
}

function Add-HordeRelaySessionPolicies {
    # -Senders (Find-HordeRelayTrustedSenders' hashtable) again, each passkey a copy carrying its session
    # member (relay/Session.ps1, WHAT THE MACHINE TAKES), built from -Records (Read-HordeRelaySessionRecords)
    # and -Trust (Read-HordeRelayTrustStore) at -NowMs. Machines are as they were. Records that do not
    # read give every passkey a session member that is broken: no session is taken, a passkey still is.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)][hashtable]$Senders, $Records, $Trust, [long]$NowMs)
    $out = @{}
    $broken = ""
    if ($null -eq $Records -or -not $Records.ok) { $broken = $(if ($null -eq $Records) { "they were not read" } else { $Records.reason }) }
    elseif ($null -eq $Trust -or -not $Trust.ok) { $broken = ("the trust store cannot be read: " + $(if ($null -eq $Trust) { "it was not read" } else { $Trust.reason })) }
    $idle = [long]3600000
    try { $idle = Get-HordeRelaySessionIdleMs -HordeHome $Context.hordeHome } catch { $broken = ("the setting idleMinutes is refused: " + $_.Exception.Message) }
    $skew = Get-HordeRelaySessionSkewMs -HordeHome $Context.hordeHome
    # EVERY RECENT RECORD OF EVERY TRUSTED PASSKEY IS VERIFIED BEFORE ANY POLICY IS BUILT (review of PR
    # 302): one record that does not verify stops every session, as the header says - not only those of
    # the passkeys checked after it. The founder's signature is checked again whenever it is used.
    $verified = @{}
    if ($broken -ceq "") {
        foreach ($e in @($Records.vouches)) {
            if (-not $Senders.ContainsKey($e.record.by) -or $Senders[$e.record.by].proof -cne "webauthn") { continue }
            # Long past its cap a vouch says nothing a phone still needs; it is not verified again.
            if ([long]$e.vouch.notAfter + $script:HordeRelaySessionKeepPastMs -lt $NowMs) { continue }
            $s = $Senders[$e.record.by]
            $wa = Test-HordeRelayWebAuthnAssertion -Public $s.public -AuthenticatorData (ConvertFrom-HordeRelayBase64Url -Text $e.record.authenticatorData) `
                -ClientDataJson (ConvertFrom-HordeRelayBase64Url -Text $e.record.clientDataJSON) -Signature (ConvertFrom-HordeRelayBase64Url -Text $e.record.signature) `
                -Challenge (Get-HordeRelaySessionVouchChallenge -Text $e.vouch.text) -RpId $s.rpId -Origins @($s.origins) -RequireUserVerification $true
            if (-not $wa.ok) { $broken = ("the recorded vouch " + $e.record.vouchId + " does not verify under its passkey: " + $wa.reason); break }
            $verified[$e.record.vouchId] = $true
        }
    }
    foreach ($k in @($Senders.Keys)) {
        $s = $Senders[$k]
        if ($s.proof -cne "webauthn") { $out[$k] = $s; continue }
        $vouches = @{}
        $highest = [long]-1
        $phoneKeyIds = @()
        if ($broken -ceq "") {
            $phoneKeyIds = @(@($Trust.phones) | Where-Object { $_.state -ceq "trusted" -and $_.by -ceq $k } | ForEach-Object { $_.agreeKeyId })
            foreach ($e in @($Records.vouches)) {
                if ($e.record.by -cne $k) { continue }
                if ([long]$e.vouch.seq -gt $highest) { $highest = [long]$e.vouch.seq }
                # Only what was verified above (long past its cap, a vouch is left out).
                if (-not $verified.ContainsKey($e.record.vouchId)) { continue }
                $seen = [long]0
                if ($Records.state.seen.ContainsKey($e.record.vouchId)) { $seen = [long]$Records.state.seen[$e.record.vouchId] }
                $vouches[$e.record.vouchId] = [pscustomobject]@{ vouch = $e.vouch; recordedAt = [long]$e.record.recordedAt; lastSeen = $seen }
            }
        }
        $policy = [pscustomobject]@{ horde = $Context.horde; machine = $Context.signKeyId; mailbox = $Context.mailbox; nowMs = $NowMs; idleMs = $idle; skewMs = $skew
            endedAt = $(if ($null -ne $Records -and $Records.ok) { [long]$Records.endedAt } else { [long]0 }); broken = $broken; phoneKeyIds = @($phoneKeyIds); vouches = $vouches; highestSeq = $highest }
        $copy = [pscustomobject]@{ keyId = $s.keyId; public = $s.public; proof = $s.proof; rpId = $s.rpId; origins = @($s.origins); requireUserVerification = $s.requireUserVerification; session = $policy }
        $out[$k] = $copy
    }
    return $out
}

function Add-HordeRelaySessionVouch {
    # Record a vouch the PC has just verified (Test-HordeRelaySessionEnvelope said isNew), write-once, by
    # -By, from -Sig (the read envelope's session sig, carrying the vouch). "moved" or "exists" when it is
    # there; anything else, or a throw, when it is not.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$By, [Parameter(Mandatory = $true)]$Sig, [long]$NowMs)
    $values = @{ v = 1; kind = "horde-relay-session-record"; vouchId = $Sig.vouchId; by = $By; vouch = $Sig.vouchText
        authenticatorData = $Sig.authenticatorDataText; clientDataJSON = $Sig.clientDataJsonText; signature = $Sig.signatureText; recordedAt = $NowMs }
    $text = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelaySessionRecordSpec) -Values $values
    return (Write-HordeRelayRecordFile -Dir ([System.IO.Path]::Combine((Get-HordeRelaySessionsDir -HordeHome $HordeHome), "vouches")) -Name ($Sig.vouchId + ".json") -Text $text)
}

function Register-HordeRelaySessionSeen {
    # The PC took an envelope under -VouchId at -NowMs: the idle clock starts again. "" or why not.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$VouchId, [long]$NowMs)
    $st = Read-HordeRelaySessionState -HordeHome $HordeHome
    if (-not $st.seen.ContainsKey($VouchId) -or [long]$st.seen[$VouchId] -lt $NowMs) { $st.seen[$VouchId] = $NowMs }
    return (Write-HordeRelaySessionState -HordeHome $HordeHome -State $st -NowMs $NowMs)
}

function Add-HordeRelaySessionRefusal {
    # A session envelope from -From under -VouchId was refused with -Code: kept for what the phone is
    # told (Get-HordeRelaySessionStatus). "" or why not.
    param([string]$HordeHome = "", [string]$From, [string]$VouchId, [string]$Code, [long]$NowMs)
    if ($From -cnotmatch '\A[0-9a-f]{32}\z' -or $VouchId -cnotmatch '\A[0-9a-f]{32}\z' -or (Get-HordeRelaySessionRefusals) -cnotcontains $Code) { return "not a session refusal" }
    $st = Read-HordeRelaySessionState -HordeHome $HordeHome
    [void]$st.refused.Add([pscustomobject]@{ from = $From; vouchId = $VouchId; code = $Code; at = $NowMs })
    return (Write-HordeRelaySessionState -HordeHome $HordeHome -State $st -NowMs $NowMs)
}

function Stop-HordeRelaySessions {
    # END ALL PHONE SESSIONS: an "ended" record at -Now. Known { endedAt; live } - live how many vouches
    # were still inside their window; unknown when it could not be written.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Reason, $Now = $null)
    if ((Test-HordeRelayRecordValue -Kind "text" -Value $Reason) -cne "" -or $Reason.Trim() -ceq "") { return (New-HordeUnknown -Reason "the reason is 1 to 512 printable ASCII characters, with no quote or backslash") }
    $nowMs = ConvertTo-HordeRelayRecordMs -Time $Now
    $live = 0
    $recs = Read-HordeRelaySessionRecords -HordeHome $HordeHome
    if ($recs.ok) { $live = @(@($recs.vouches) | Where-Object { [long]$_.vouch.notAfter -ge $nowMs }).Count }
    $text = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelaySessionEndedSpec) -Values @{ v = 1; kind = "horde-relay-sessions-ended"; endedAt = $nowMs; reason = $Reason }
    $name = "ended-" + $nowMs.ToString("D16") + "-" + (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelayRandomBytes -Count 4)) + ".json"
    try { $moved = Write-HordeRelayRecordFile -Dir ([System.IO.Path]::Combine((Get-HordeRelaySessionsDir -HordeHome $HordeHome), "ended")) -Name $name -Text $text }
    catch { return (New-HordeUnknown -Reason "the end of every phone session could not be written" -ErrorRecord $_) }
    if ($moved -cne "moved") { return (New-HordeUnknown -Reason ("the end record has its name, but nothing says it reached the disk (" + $moved + ")")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ endedAt = $nowMs; live = $live }))
}

function Get-HordeRelaySessionStatus {
    # What the phone of passkey -From is told of its sessions (relay/js/protocol.js, sessionStatus), less
    # needsPasskey, which is the decisions channel's: { idleMs; vouches } with vouches a list of { vouchId;
    # state } - the newest vouches the PC holds of that passkey, each live or why not by the PC's clock
    # now, and any vouch it refused that it does not hold, with the code. $null when the records cannot
    # be read: a receipt then says nothing of sessions, and the phone signs with its passkey as before.
    # CHEAP ON PURPOSE: asked on every look of the decisions channel, it reads this folder and nothing
    # else - no signature is verified and the trust store is not read. A phone key no longer trusted is
    # sealed nothing anyway, so it never reads the "live" this may say of it.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$From, [long]$NowMs, $Records = $null)
    $recs = $Records
    if ($null -eq $recs) { $recs = Read-HordeRelaySessionRecords -HordeHome $HordeHome }
    if (-not $recs.ok) { return $null }
    try { $idle = Get-HordeRelaySessionIdleMs -HordeHome $HordeHome } catch { return $null }
    $skew = Get-HordeRelaySessionSkewMs -HordeHome $HordeHome
    $mine = @(@($recs.vouches) | Where-Object { $_.record.by -ceq $From } | Sort-Object -Property @{ Expression = { [long]$_.record.recordedAt } } | Select-Object -Last $script:HordeRelaySessionStatusMost)
    $list = New-Object System.Collections.ArrayList
    $held = @{}
    foreach ($e in $mine) {
        $v = $e.vouch
        $held[$v.vouchId] = $true
        $last = [long]$e.record.recordedAt
        if ($recs.state.seen.ContainsKey($v.vouchId) -and [long]$recs.state.seen[$v.vouchId] -gt $last) { $last = [long]$recs.state.seen[$v.vouchId] }
        $state = "live"
        # The same rule as relay/Session.ps1's: notBefore is the phone's clock, counted back skewMs.
        if ([long]$recs.endedAt -gt 0 -and (([long]$v.notBefore - $skew) -le [long]$recs.endedAt -or [long]$e.record.recordedAt -le [long]$recs.endedAt)) { $state = "session-ended" }
        elseif ($NowMs -gt [long]$v.notAfter) { $state = "session-expired" }
        elseif ($NowMs - $last -gt $idle) { $state = "session-idle" }
        [void]$list.Add([pscustomobject]@{ vouchId = $v.vouchId; state = $state })
    }
    foreach ($r in @(@($recs.state.refused) | Where-Object { $_.from -ceq $From })) {
        if ($held.ContainsKey($r.vouchId)) { continue }
        $held[$r.vouchId] = $true
        [void]$list.Add([pscustomobject]@{ vouchId = $r.vouchId; state = $r.code })
    }
    return [pscustomobject]@{ idleMs = $idle; vouches = @($list.ToArray()) }
}
