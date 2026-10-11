# relay/Identity.ps1 - which horde this machine belongs to, and the machine's own relay keys: made
# once, loaded every time, rotated with the old keys' retirement on record.
#
# A HORDE is one Thrall's fleet - work, personal - which may span several machines, each with its own
# Horde install (relay design, Q10). Its name is the setting horde of module relay
# (<HORDE_HOME>\settings\relay.json, core/ModuleSettings.ps1): 1 to 63 of a-z, 0-9 and -, starting with a
# letter or digit, and never a Windows device name - it is the first part of every mailbox of the horde
# (relays/Port.ps1's addressing, whose rule is repeated here because relay/ may not load relays/). It has
# no default, on purpose: two hordes that both fell back to one default name would share mailboxes,
# so nothing is made or paired until a person names the horde. A MACHINE BELONGS TO ONE HORDE: the
# name is written into the identity when it is made, and an identity whose horde is not the setting's
# is refused, never silently moved - a renamed horde would orphan every phone and peer that pinned it.
#
# THE IDENTITY is a generation: a signing key (ES256: it signs every envelope and every request this
# machine sends) and an agreement key (it opens HPKE: what is sealed to this machine), made by
# relay/Keys.ps1 - non-exportable, in the TPM where it works there (-Provider auto), in the scope of
# the account Horde runs as unless -Scope machine is asked. Its record, under
# <HORDE_HOME>\relay\identity\machine-<generation>.json (relay/Records.ps1, write-once), names both keys
# and pins their public halves, so a key that was swapped in the store under the same name is refused,
# not used. Key ids (relay/P256.ps1's Get-HordeRelayKeyId) are what envelopes and mailboxes name the
# machine by: the machine's own mailbox is <horde>/<sign key id>.
# KEY NAMES are horde-relay-m<install>-g<generation>-s and -a, where install is 16 random hex digits
# made with the first generation and kept for every later one: two Horde homes on one account (two
# hordes, or a suite's temporary home) never reach each other's keys.
#
# ROTATION (Update-HordeRelayMachineIdentity) makes a NEW generation - new keys, so new key ids, so new
# streams for the journal and a new mailbox - and then RETIRES the old one with a record that is never
# deleted (retired-<generation>.json): which keys, why, when, and its successor's keys. When the old
# signing key still opens, the record carries its VOUCH: an ES256 signature by the old key over the
# record, which lets a phone or a peer that trusts the old key accept the new one without pairing
# again (a later pull request carries it to them). A rotation forced by a LOST or stolen key has no
# vouch, and every phone and peer must be told out of band; the record says which it was.
# THE OLD SIGNING KEY IS DELETED AT ONCE: nothing may be signed as the old generation again. THE OLD
# AGREEMENT KEY IS KEPT FOR OPENING ONLY, for the setting retiredAgreeKeyDays (7 by default, 0 to 30):
# envelopes a phone or peer sealed to it before it heard of the rotation still open
# (Get-HordeRelayOpeningKeys). It is never handed out again - offers and cards name the current key
# only - so nothing new is sealed to it, and an agreement key cannot sign. When the grace ends,
# Remove-HordeRelayRetiredAgreeKeys deletes it from the store and records that it did
# (released-<generation>.json), so both events - retired, released - are on record. The retirement
# record says when the grace ends (agreeKeptUntil), and the vouch covers it. Why capped at 30: a
# retired key that opens is still a key a thief of this machine could use on old traffic, and a
# month is longer than any relay keeps a message (design Q16: 30 days of ciphertext).
# A crash between the new record and the retirement leaves two live generations: the newest is the
# identity, the older is reported as unretired, and the next rotation retires it first.
#
# OFF WINDOWS there is no non-exportable key store yet (relay/Keys.ps1), so every answer here that needs
# the keys is absent, with that reason: no key is faked with a file.
#
# Answers are core/tristate: known, absent or unknown, with the reason.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ModuleSettings.ps1")
. (Join-Path $PSScriptRoot "Bytes.ps1")
. (Join-Path $PSScriptRoot "P256.ps1")
. (Join-Path $PSScriptRoot "Keys.ps1")
. (Join-Path $PSScriptRoot "Records.ps1")

$script:HordeRelaySettings = New-HordeModuleSettings -Module "relay" -Settings @(
    @{ name = "horde"; kind = "text"; default = ""; min = 0; max = 63
       what = "The name of the horde this machine belongs to (work, personal): a-z, 0-9 and -, starting with a letter or digit. Empty means none is named yet, and nothing is made or paired until it is." },
    @{ name = "retiredAgreeKeyDays"; kind = "whole"; default = 7; min = 0; max = 30
       what = "How many days a rotated-out agreement key is kept, to open what was sealed to it before the rotation; it never seals or signs. 0 deletes it at once." },
    # Read by relay/Pairing.ps1, declared here with the module's other settings: one table per module.
    @{ name = "pendingConfirmMinutes"; kind = "whole"; default = 10; min = 1; max = 30
       what = "How many minutes a newly registered device waits, pending, for its fingerprint to be confirmed at this machine, counted from its registration." },
    # Read by cli/RelayPair.ps1 (`horde relay pair`); checked as an offer's rpId and origins are
    # (relay/Pairing.ps1, Test-HordeRelayOriginForRpId) when the offer is made.
    @{ name = "pairRpId"; kind = "text"; default = ""; min = 0; max = 253
       what = "The relying party id the phone app makes its passkeys for: the host it is served from, or a parent domain of it. Empty means horde relay pair needs -RpId." },
    @{ name = "pairOrigin"; kind = "text"; default = ""; min = 0; max = 200
       what = "Where the phone app is served, as https://<host>[:port]. Empty means horde relay pair needs -Origin." }
)

$script:HordeRelayIdentityNamePattern = '\A(machine|retired|released)-([0-9]{6})\.json\z'
$script:HordeRelayHordePattern = '\A[a-z0-9][a-z0-9-]{0,62}\z'
$script:HordeRelayDeviceNamePattern = '\A(con|prn|aux|nul|com[0-9]|lpt[0-9])\z'

function Get-HordeRelayIdentitySpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "horde", "name", "install", "hex", "generation", "int", "scope", "name",
        "signName", "name", "signProvider", "name", "signKeyId", "hex32", "signPublic", "point",
        "agreeName", "name", "agreeProvider", "name", "agreeKeyId", "hex32", "agreePublic", "point", "createdAt", "int"))
}

function Get-HordeRelayRetiredSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "horde", "name", "generation", "int", "signKeyId", "hex32", "agreeKeyId", "hex32",
        "successor", "int", "successorSignKeyId", "hex32", "successorSignPublic", "point", "successorAgreeKeyId", "hex32", "successorAgreePublic", "point",
        "reason", "text", "retiredAt", "int", "agreeKeptUntil", "int", "vouch", "b64u"))
}

function Get-HordeRelayReleasedSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "horde", "name", "generation", "int", "agreeKeyId", "hex32", "releasedAt", "int", "reason", "text"))
}

function Get-HordeRelayCardSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "horde", "name", "label", "label", "generation", "int",
        "signKeyId", "hex32", "signPublic", "point", "agreeKeyId", "hex32", "agreePublic", "point", "mailbox", "mailbox", "issuedAt", "int", "proof", "b64u"))
}

function Get-HordeRelayIdentityDomain {
    # The fixed prefixes of what a machine key signs here, so neither signature can be read as an
    # envelope's (relay/Envelope.ps1 signs "horde-relay/envelope/v1 signed") or as the other's.
    param([string]$Part)
    if ($Part -ceq "vouch") { return "horde-relay/rotation/v1 vouch`n" }
    if ($Part -ceq "card") { return "horde-relay/machine-card/v1 proof`n" }
    throw ("no such domain part: " + $Part)
}

function Test-HordeRelayHordeName {
    # "" when Name may name a horde, else why not.
    param([AllowEmptyString()][string]$Name)
    if ($Name -cnotmatch $script:HordeRelayHordePattern) { return ("'" + $Name + "' is not a horde name: 1 to 63 of a-z, 0-9 and -, starting with a letter or digit") }
    if ($Name -cmatch $script:HordeRelayDeviceNamePattern) { return ("'" + $Name + "' is a device name, and a relay may keep mailboxes as folders") }
    return ""
}

function Get-HordeRelaySettingValues {
    # The relay module's settings answer (core/ModuleSettings.ps1): known, or unknown with the findings
    # of a refused file - never the defaults in its place.
    param([string]$HordeHome = "")
    try { $s = Get-HordeModuleSettings -Declaration $script:HordeRelaySettings -HordeHome $HordeHome }
    catch { return (New-HordeUnknown -Reason "the relay settings could not be read" -ErrorRecord $_) }
    if ($s.state -ceq "refused") { return (New-HordeUnknown -Reason ($s.findings -join " ")) }
    return (New-HordeKnown -Value $s)
}

function Get-HordeRelayHorde {
    # The horde this Horde home belongs to. Known name; absent when none is named yet; unknown when the
    # settings file is refused or names something that cannot be a horde.
    param([string]$HordeHome = "")
    $settings = Get-HordeRelaySettingValues -HordeHome $HordeHome
    if ($settings.state -cne "known") { return $settings }
    $s = $settings.value
    $name = "" + $s.values.horde
    if ($name -ceq "") { return (New-HordeAbsent -Note ("no horde is named: set horde in " + $s.path + ", for example {""schemaVersion"": 1, ""settings"": {""horde"": ""work""}}")) }
    $why = Test-HordeRelayHordeName -Name $name
    if ($why -cne "") { return (New-HordeUnknown -Reason ("the setting horde in " + $s.path + " is refused: " + $why)) }
    return (New-HordeKnown -Value $name)
}

function Get-HordeRelayKeyNames {
    # The store names of one generation's keys.
    param([string]$Install, [long]$Generation)
    $stem = "horde-relay-m" + $Install + "-g" + $Generation
    return [pscustomobject]@{ sign = ($stem + "-s"); agree = ($stem + "-a") }
}

function Read-HordeRelayIdentityRecords {
    # Every generation record and retirement record, checked against each other. { ok; reason;
    # machines (by generation, ascending); retired and released (hashtables generation -> record) }.
    # No identity is ok with no machines.
    param([string]$HordeHome)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; machines = @(); retired = @{}; released = @{} }
    try { $dir = Get-HordeRelayStateDir -HordeHome $HordeHome -Part "identity" } catch { $fail.reason = $_.Exception.Message; return $fail }
    $list = Get-HordeRelayRecordNames -Dir $dir -Pattern $script:HordeRelayIdentityNamePattern
    if (-not $list.ok) { $fail.reason = $list.reason; return $fail }
    $machines = New-Object System.Collections.ArrayList
    $retired = @{}
    $released = @{}
    foreach ($n in @($list.names)) {
        $m = [regex]::Match($n, $script:HordeRelayIdentityNamePattern)
        $gen = [long]$m.Groups[2].Value
        $file = Read-HordeRelayRecordFile -Path ([System.IO.Path]::Combine($dir, $n))
        if (-not $file.ok) { $fail.reason = $file.reason; return $fail }
        if ($m.Groups[1].Value -ceq "machine") {
            $r = Read-HordeRelayRecordText -Text $file.text -Spec (Get-HordeRelayIdentitySpec) -Kind "horde-relay-machine" -What ("the identity record " + $n)
            if (-not $r.ok) { $fail.reason = $r.reason; return $fail }
            if ($r.value.generation -ne $gen) { $fail.reason = ("the identity record " + $n + " says generation " + $r.value.generation); return $fail }
            if ($r.value.signKeyId -cne (Get-HordeRelayKeyId -Public (ConvertFrom-HordeRelayBase64Url -Text $r.value.signPublic)) -or
                $r.value.agreeKeyId -cne (Get-HordeRelayKeyId -Public (ConvertFrom-HordeRelayBase64Url -Text $r.value.agreePublic))) { $fail.reason = ("the identity record " + $n + " names key ids that are not its keys'"); return $fail }
            $names = Get-HordeRelayKeyNames -Install $r.value.install -Generation $gen
            if ($r.value.signName -cne $names.sign -or $r.value.agreeName -cne $names.agree) { $fail.reason = ("the identity record " + $n + " names keys that are not its generation's"); return $fail }
            [void]$machines.Add($r.value)
        } elseif ($m.Groups[1].Value -ceq "released") {
            $r = Read-HordeRelayRecordText -Text $file.text -Spec (Get-HordeRelayReleasedSpec) -Kind "horde-relay-machine-agree-released" -What ("the release record " + $n)
            if (-not $r.ok) { $fail.reason = $r.reason; return $fail }
            if ($r.value.generation -ne $gen) { $fail.reason = ("the release record " + $n + " says generation " + $r.value.generation); return $fail }
            $released["" + $gen] = $r.value
        } else {
            $r = Read-HordeRelayRecordText -Text $file.text -Spec (Get-HordeRelayRetiredSpec) -Kind "horde-relay-machine-retired" -What ("the retirement record " + $n)
            if (-not $r.ok) { $fail.reason = $r.reason; return $fail }
            if ($r.value.generation -ne $gen) { $fail.reason = ("the retirement record " + $n + " says generation " + $r.value.generation); return $fail }
            $retired["" + $gen] = $r.value
        }
    }
    $sorted = @($machines.ToArray() | Sort-Object -Property "generation")
    if ($sorted.Count -gt 0) {
        $first = $sorted[0]
        foreach ($mr in $sorted) {
            if ($mr.horde -cne $first.horde -or $mr.install -cne $first.install) { $fail.reason = ("the identity records disagree on the horde or the install (generation " + $mr.generation + ")"); return $fail }
        }
    }
    foreach ($k in @($retired.Keys)) {
        $mr = @($sorted | Where-Object { $_.generation -eq [long]$k })
        if ($mr.Count -ne 1) { $fail.reason = ("generation " + $k + " has a retirement record and no identity record"); return $fail }
        if ($retired[$k].signKeyId -cne $mr[0].signKeyId -or $retired[$k].agreeKeyId -cne $mr[0].agreeKeyId) { $fail.reason = ("the retirement record of generation " + $k + " names other keys than its identity record"); return $fail }
    }
    foreach ($k in @($released.Keys)) {
        if (-not $retired.ContainsKey($k) -or $retired[$k].agreeKeyId -cne $released[$k].agreeKeyId) { $fail.reason = ("generation " + $k + " has a release record but no retirement of that agreement key"); return $fail }
    }
    if ($sorted.Count -gt 0 -and $retired.ContainsKey("" + $sorted[-1].generation)) { $fail.reason = ("the newest generation (" + $sorted[-1].generation + ") is retired and has no successor; the identity is damaged"); return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; machines = $sorted; retired = $retired; released = $released }
}

function New-HordeRelayGenerationKeys {
    # Make one generation's two keys. Known { sign; agree } (relay/Keys.ps1's answers), or unknown/absent
    # with nothing left behind.
    param([string]$Install, [long]$Generation, [string]$Scope, [string]$Provider)
    $names = Get-HordeRelayKeyNames -Install $Install -Generation $Generation
    $sign = New-HordeRelayKey -Name $names.sign -Use "sign" -Scope $Scope -Provider $Provider
    if ($sign.state -cne "known") { return $sign }
    $agree = New-HordeRelayKey -Name $names.agree -Use "agree" -Scope $Scope -Provider $Provider
    if ($agree.state -cne "known") {
        [void](Remove-HordeRelayKey -Name $names.sign -Scope $Scope)
        return $agree
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ sign = $sign.value; agree = $agree.value }))
}

function Remove-HordeRelayGenerationKeys {
    # Delete one generation's keys; the reasons for any that could not be, as text ("" when none).
    param([string]$Install, [long]$Generation, [string]$Scope)
    $names = Get-HordeRelayKeyNames -Install $Install -Generation $Generation
    $why = New-Object System.Collections.ArrayList
    foreach ($n in @($names.sign, $names.agree)) {
        $r = Remove-HordeRelayKey -Name $n -Scope $Scope
        if ($r.state -ceq "unknown") { [void]$why.Add($r.reason) }
    }
    return (@($why.ToArray()) -join "; ")
}

function Write-HordeRelayIdentityRecord {
    # Write a generation's record; "" or why not.
    param([string]$HordeHome, [string]$Horde, [string]$Install, [long]$Generation, [string]$Scope, $Keys, [long]$CreatedAt)
    $text = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayIdentitySpec) -Values @{
        v = 1; kind = "horde-relay-machine"; horde = $Horde; install = $Install; generation = $Generation; scope = $Scope
        signName = $Keys.sign.name; signProvider = $Keys.sign.provider; signKeyId = $Keys.sign.keyId; signPublic = (ConvertTo-HordeRelayBase64Url -Bytes $Keys.sign.publicKey)
        agreeName = $Keys.agree.name; agreeProvider = $Keys.agree.provider; agreeKeyId = $Keys.agree.keyId; agreePublic = (ConvertTo-HordeRelayBase64Url -Bytes $Keys.agree.publicKey)
        createdAt = $CreatedAt
    }
    $dir = Get-HordeRelayStateDir -HordeHome $HordeHome -Part "identity"
    $moved = Write-HordeRelayRecordFile -Dir $dir -Name ("machine-" + $Generation.ToString("000000") + ".json") -Text $text
    if ($moved -ceq "moved") { return "" }
    if ($moved -ceq "exists") { return ("generation " + $Generation + " was made by another process at the same moment") }
    return ("the record of generation " + $Generation + " has its name, but nothing says it reached the disk")
}

function New-HordeRelayMachineIdentity {
    # Make this machine's relay identity, once: generation 1 of the horde the setting names. Known (the
    # identity, as Get-HordeRelayMachineIdentity answers it); unknown when one exists already (it is
    # never remade: rotate it) or could not be made; absent when no horde is named or there is no key
    # store here.
    param([string]$HordeHome = "", [string]$Scope = "user", [string]$Provider = "auto", $Now = $null)
    $horde = Get-HordeRelayHorde -HordeHome $HordeHome
    if ($horde.state -cne "known") { return $horde }
    $have = Read-HordeRelayIdentityRecords -HordeHome $HordeHome
    if (-not $have.ok) { return (New-HordeUnknown -Reason $have.reason) }
    if (@($have.machines).Count -gt 0) { return (New-HordeUnknown -Reason ("this machine already has a relay identity (generation " + $have.machines[-1].generation + "); it is made once and never remade - rotate it instead")) }
    $store = Get-HordeRelayKeyStore
    if ($store.state -cne "known") { return $store }
    $install = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelayRandomBytes -Count 8)
    $keys = New-HordeRelayGenerationKeys -Install $install -Generation 1 -Scope $Scope -Provider $Provider
    if ($keys.state -cne "known") { return $keys }
    $why = ""
    try { $why = Write-HordeRelayIdentityRecord -HordeHome $HordeHome -Horde $horde.value -Install $install -Generation 1 -Scope $Scope -Keys $keys.value -CreatedAt (ConvertTo-HordeRelayRecordMs -Time $Now) }
    catch { $why = ("its record could not be written: " + $_.Exception.Message) }
    if ($why -cne "") {
        [void](Remove-HordeRelayGenerationKeys -Install $install -Generation 1 -Scope $Scope)
        return (New-HordeUnknown -Reason ("the relay identity was not made: " + $why))
    }
    return (Get-HordeRelayMachineIdentity -HordeHome $HordeHome)
}

function Open-HordeRelayGenerationKey {
    # Open one key a record names and check it is the key the record pins. Known (relay/Keys.ps1's
    # answer, its key object open), absent with no store, unknown otherwise.
    param($Record, [string]$Use)
    $name = $(if ($Use -ceq "sign") { $Record.signName } else { $Record.agreeName })
    $pinned = $(if ($Use -ceq "sign") { $Record.signPublic } else { $Record.agreePublic })
    $k = Get-HordeRelayKey -Name $name -Use $Use -Scope $Record.scope
    if ($k.state -ceq "absent" -and (Get-HordeRelayKeyStore).state -ceq "known") { return (New-HordeUnknown -Reason ("the " + $Use + " key " + $name + " of generation " + $Record.generation + " is gone from the " + $Record.scope + " key store; rotate the identity")) }
    if ($k.state -cne "known") { return $k }
    if ((ConvertTo-HordeRelayBase64Url -Bytes $k.value.publicKey) -cne $pinned) {
        $k.value.key.Dispose()
        return (New-HordeUnknown -Reason ("the " + $Use + " key " + $name + " in the store is not the key generation " + $Record.generation + " pinned; it is not used"))
    }
    return $k
}

function Get-HordeRelayMachineIdentity {
    # This machine's relay identity: known { horde; generation; install; scope; mailbox; createdAt;
    # sign; agree; retired; unretired; opening }, where sign and agree are { name; provider; keyId;
    # public } and, with -Open, also key: the open key object (the caller disposes it); opening is the
    # retired agreement keys still in their grace at -Now, as { generation; agreeKeyId; until }. Absent
    # when there is none yet or no key store here; unknown when the records are damaged, the horde
    # setting is not the identity's, or a key is missing or not the one pinned.
    param([string]$HordeHome = "", [switch]$Open, $Now = $null)
    $have = Read-HordeRelayIdentityRecords -HordeHome $HordeHome
    if (-not $have.ok) { return (New-HordeUnknown -Reason $have.reason) }
    if (@($have.machines).Count -eq 0) { return (New-HordeAbsent -Note "this machine has no relay identity yet") }
    $cur = $have.machines[-1]
    $horde = Get-HordeRelayHorde -HordeHome $HordeHome
    if ($horde.state -ceq "unknown") { return $horde }
    if ($horde.state -ceq "absent" -or $horde.value -cne $cur.horde) {
        return (New-HordeUnknown -Reason ("this machine's relay identity belongs to the horde '" + $cur.horde + "', but the setting names " + $(if ($horde.state -ceq "absent") { "none" } else { "'" + $horde.value + "'" }) + ". A machine belongs to one horde; it is not moved by a setting"))
    }
    $sign = Open-HordeRelayGenerationKey -Record $cur -Use "sign"
    if ($sign.state -cne "known") { return $sign }
    $agree = Open-HordeRelayGenerationKey -Record $cur -Use "agree"
    if ($agree.state -cne "known") { $sign.value.key.Dispose(); return $agree }
    $signOut = [pscustomobject]@{ name = $cur.signName; provider = $cur.signProvider; keyId = $cur.signKeyId; public = $sign.value.publicKey }
    $agreeOut = [pscustomobject]@{ name = $cur.agreeName; provider = $cur.agreeProvider; keyId = $cur.agreeKeyId; public = $agree.value.publicKey }
    if ($Open) {
        $signOut | Add-Member -NotePropertyName "key" -NotePropertyValue $sign.value.key
        $agreeOut | Add-Member -NotePropertyName "key" -NotePropertyValue $agree.value.key
    } else { $sign.value.key.Dispose(); $agree.value.key.Dispose() }
    $retiredGens = @(@($have.retired.Keys) | ForEach-Object { [long]$_ } | Sort-Object)
    $unretired = @(@($have.machines) | Where-Object { $_.generation -ne $cur.generation -and -not $have.retired.ContainsKey("" + $_.generation) } | ForEach-Object { $_.generation })
    return (New-HordeKnown -Value ([pscustomobject]@{
        horde = $cur.horde; generation = $cur.generation; install = $cur.install; scope = $cur.scope
        mailbox = ($cur.horde + "/" + $cur.signKeyId); createdAt = $cur.createdAt
        sign = $signOut; agree = $agreeOut; retired = $retiredGens; unretired = $unretired
        opening = @(Get-HordeRelayGraceKeys -Have $have -NowMs (ConvertTo-HordeRelayRecordMs -Time $Now))
    }))
}

function Get-HordeRelayGraceKeys {
    # The retired agreement keys in their grace at NowMs: retired, not released, and NowMs before
    # agreeKeptUntil. { generation; agreeKeyId; until; record } each, oldest first.
    param($Have, [long]$NowMs)
    $out = New-Object System.Collections.ArrayList
    foreach ($m in @($Have.machines)) {
        $k = "" + $m.generation
        if (-not $Have.retired.ContainsKey($k) -or $Have.released.ContainsKey($k)) { continue }
        if ($NowMs -lt $Have.retired[$k].agreeKeptUntil) { [void]$out.Add([pscustomobject]@{ generation = $m.generation; agreeKeyId = $m.agreeKeyId; until = $Have.retired[$k].agreeKeptUntil; record = $m }) }
    }
    return @($out.ToArray())
}

function Get-HordeRelayOpeningKeys {
    # The agreement keys that may OPEN at -Now: the current generation's and every retired one still in
    # its grace. Known { keys (hashtable key id -> open key object; the caller disposes them); missing
    # (reasons for grace keys that would not open) }; the identity's answer when it has none.
    param([string]$HordeHome = "", $Now = $null)
    $id = Get-HordeRelayMachineIdentity -HordeHome $HordeHome -Open -Now $Now
    if ($id.state -cne "known") { return $id }
    $id.value.sign.key.Dispose()
    $keys = @{}
    $keys[$id.value.agree.keyId] = $id.value.agree.key
    $missing = New-Object System.Collections.ArrayList
    foreach ($g in @($id.value.opening)) {
        $k = Open-HordeRelayGenerationKey -Record $g.record -Use "agree"
        if ($k.state -ceq "known") { $keys[$g.agreeKeyId] = $k.value.key } else { [void]$missing.Add("generation " + $g.generation + ": " + $k.reason) }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ keys = $keys; missing = @($missing.ToArray()) }))
}

function Remove-HordeRelayRetiredAgreeKeys {
    # Release every retired agreement key whose grace has ended at -Now: delete it from the store, then
    # record the release (released-<generation>.json). Known { released (generations); problems };
    # unknown when the records are damaged. Safe to call again: a released key is not touched twice.
    param([string]$HordeHome = "", $Now = $null)
    $have = Read-HordeRelayIdentityRecords -HordeHome $HordeHome
    if (-not $have.ok) { return (New-HordeUnknown -Reason $have.reason) }
    $nowMs = ConvertTo-HordeRelayRecordMs -Time $Now
    $dir = Get-HordeRelayStateDir -HordeHome $HordeHome -Part "identity"
    $done = New-Object System.Collections.ArrayList
    $problems = New-Object System.Collections.ArrayList
    foreach ($m in @($have.machines)) {
        $k = "" + $m.generation
        if (-not $have.retired.ContainsKey($k) -or $have.released.ContainsKey($k)) { continue }
        if ($nowMs -lt $have.retired[$k].agreeKeptUntil) { continue }
        $gone = Remove-HordeRelayKey -Name $m.agreeName -Scope $m.scope
        if ($gone.state -ceq "unknown") { [void]$problems.Add("generation " + $k + ": " + $gone.reason); continue }
        try {
            $text = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayReleasedSpec) -Values @{
                v = 1; kind = "horde-relay-machine-agree-released"; horde = $m.horde; generation = $m.generation; agreeKeyId = $m.agreeKeyId
                releasedAt = $nowMs; reason = "its grace after retirement ended"
            }
            $moved = Write-HordeRelayRecordFile -Dir $dir -Name ("released-" + $m.generation.ToString("000000") + ".json") -Text $text
            if ($moved -cne "moved") { [void]$problems.Add("generation " + $k + "'s release: " + $moved); continue }
        } catch { [void]$problems.Add("generation " + $k + "'s release could not be written: " + $_.Exception.Message); continue }
        [void]$done.Add($m.generation)
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ released = @($done.ToArray()); problems = (@($problems.ToArray()) -join "; ") }))
}

function Get-HordeRelayRetirementVouch {
    # The old signing key's ES256 signature over a retirement record written with an empty vouch, as
    # base64url; "" when the old key does not open (lost, or this is not its machine any more).
    param($Record, [string]$TextWithoutVouch)
    $k = Open-HordeRelayGenerationKey -Record $Record -Use "sign"
    if ($k.state -cne "known") { return "" }
    try {
        $sig = New-HordeRelayEs256Signature -Key $k.value.key -Bytes (Get-HordeRelayAsciiBytes -Text ((Get-HordeRelayIdentityDomain -Part "vouch") + $TextWithoutVouch))
        return (ConvertTo-HordeRelayBase64Url -Bytes $sig)
    } catch { return "" }
    finally { $k.value.key.Dispose() }
}

function Update-HordeRelayMachineIdentity {
    # Rotate: make the next generation, retire every older live one (with its vouch when its key still
    # opens), delete the retired SIGNING keys at once and keep the agreement keys for their grace (the
    # header). Known { previous; vouched; released; cleanup; identity }; unknown or absent when it
    # cannot be done, with nothing retired.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Reason, [string]$Provider = "auto", $Now = $null)
    if ($Reason -cnotmatch '\A[\x20\x21\x23-\x5B\x5D-\x7E]{1,512}\z') { return (New-HordeUnknown -Reason "a rotation's reason is 1 to 512 printable ASCII characters, with no quote or backslash") }
    $have = Read-HordeRelayIdentityRecords -HordeHome $HordeHome
    if (-not $have.ok) { return (New-HordeUnknown -Reason $have.reason) }
    if (@($have.machines).Count -eq 0) { return (New-HordeAbsent -Note "this machine has no relay identity to rotate") }
    $cur = $have.machines[-1]
    $settings = Get-HordeRelaySettingValues -HordeHome $HordeHome
    if ($settings.state -cne "known") { return (New-HordeUnknown -Reason ("the relay settings are refused, so nothing is rotated: " + $settings.reason)) }
    $graceMs = [long]$settings.value.values.retiredAgreeKeyDays * 86400000
    $horde = Get-HordeRelayHorde -HordeHome $HordeHome
    if ($horde.state -cne "known" -or $horde.value -cne $cur.horde) { return (New-HordeUnknown -Reason ("the identity belongs to the horde '" + $cur.horde + "' and the setting does not name it; nothing is rotated")) }
    $store = Get-HordeRelayKeyStore
    if ($store.state -cne "known") { return $store }
    $next = $cur.generation + 1
    $keys = New-HordeRelayGenerationKeys -Install $cur.install -Generation $next -Scope $cur.scope -Provider $Provider
    if ($keys.state -cne "known") { return $keys }
    $nowMs = ConvertTo-HordeRelayRecordMs -Time $Now
    $why = ""
    try { $why = Write-HordeRelayIdentityRecord -HordeHome $HordeHome -Horde $cur.horde -Install $cur.install -Generation $next -Scope $cur.scope -Keys $keys.value -CreatedAt $nowMs }
    catch { $why = ("its record could not be written: " + $_.Exception.Message) }
    if ($why -cne "") {
        [void](Remove-HordeRelayGenerationKeys -Install $cur.install -Generation $next -Scope $cur.scope)
        return (New-HordeUnknown -Reason ("the identity was not rotated: " + $why))
    }
    # From here the new generation IS the identity. Each older live generation is retired; a failure
    # leaves it unretired, reported, and retired by the next rotation.
    $dir = Get-HordeRelayStateDir -HordeHome $HordeHome -Part "identity"
    $vouched = New-Object System.Collections.ArrayList
    $problems = New-Object System.Collections.ArrayList
    foreach ($old in @($have.machines | Where-Object { -not $have.retired.ContainsKey("" + $_.generation) })) {
        $values = @{
            v = 1; kind = "horde-relay-machine-retired"; horde = $old.horde; generation = $old.generation; signKeyId = $old.signKeyId; agreeKeyId = $old.agreeKeyId
            successor = $next; successorSignKeyId = $keys.value.sign.keyId; successorSignPublic = (ConvertTo-HordeRelayBase64Url -Bytes $keys.value.sign.publicKey)
            successorAgreeKeyId = $keys.value.agree.keyId; successorAgreePublic = (ConvertTo-HordeRelayBase64Url -Bytes $keys.value.agree.publicKey)
            reason = $Reason; retiredAt = $nowMs; agreeKeptUntil = ($nowMs + $graceMs); vouch = ""
        }
        $spec = Get-HordeRelayRetiredSpec
        $values.vouch = Get-HordeRelayRetirementVouch -Record $old -TextWithoutVouch (ConvertTo-HordeRelayRecordText -Spec $spec -Values $values)
        try {
            $moved = Write-HordeRelayRecordFile -Dir $dir -Name ("retired-" + $old.generation.ToString("000000") + ".json") -Text (ConvertTo-HordeRelayRecordText -Spec $spec -Values $values)
            if ($moved -cne "moved") { [void]$problems.Add("generation " + $old.generation + "'s retirement: " + $moved); continue }
        } catch { [void]$problems.Add("generation " + $old.generation + "'s retirement could not be written: " + $_.Exception.Message); continue }
        if ($values.vouch -cne "") { [void]$vouched.Add($old.generation) }
        $left = Remove-HordeRelayKey -Name $old.signName -Scope $old.scope
        if ($left.state -ceq "unknown") { [void]$problems.Add("generation " + $old.generation + "'s signing key: " + $left.reason) }
    }
    # A grace of 0 ends now: the agreement keys just retired are released in the same call.
    $rel = Remove-HordeRelayRetiredAgreeKeys -HordeHome $HordeHome -Now $Now
    $released = @()
    if ($rel.state -ceq "known") {
        $released = @($rel.value.released)
        if ($rel.value.problems -cne "") { [void]$problems.Add($rel.value.problems) }
    } else { [void]$problems.Add($rel.reason) }
    $id = Get-HordeRelayMachineIdentity -HordeHome $HordeHome -Now $Now
    if ($id.state -cne "known") { return $id }
    return (New-HordeKnown -Value ([pscustomobject]@{ previous = $cur.generation; vouched = @($vouched.ToArray()); released = $released; cleanup = (@($problems.ToArray()) -join "; "); identity = $id.value }))
}

function Test-HordeRelayRetirementVouch {
    # Does a retirement record's vouch verify under the retired signing key? A phone or peer that
    # pinned PublicOld asks this before it follows the record to the successor. Never throws.
    param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][byte[]]$PublicOld)
    $r = Read-HordeRelayRecordText -Text $Text -Spec (Get-HordeRelayRetiredSpec) -Kind "horde-relay-machine-retired"
    if (-not $r.ok -or $r.value.vouch -ceq "") { return $false }
    if ((Get-HordeRelayKeyId -Public $PublicOld) -cne $r.value.signKeyId) { return $false }
    $values = @{}
    foreach ($p in $r.value.PSObject.Properties) { $values[$p.Name] = $p.Value }
    $sig = ConvertFrom-HordeRelayBase64Url -Text $values.vouch
    $values.vouch = ""
    $signed = Get-HordeRelayAsciiBytes -Text ((Get-HordeRelayIdentityDomain -Part "vouch") + (ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayRetiredSpec) -Values $values))
    return (Test-HordeRelayEs256Signature -Public $PublicOld -Bytes $signed -Signature $sig)
}

function Get-HordeRelayRetirementText {
    # The text of generation's retirement record, for carrying to phones and peers. Known or absent.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][long]$Generation)
    $dir = Get-HordeRelayStateDir -HordeHome $HordeHome -Part "identity"
    $f = Read-HordeRelayRecordFile -Path ([System.IO.Path]::Combine($dir, ("retired-" + $Generation.ToString("000000") + ".json")))
    if (-not $f.ok) { return (New-HordeUnknown -Reason $f.reason) }
    if (-not $f.found) { return (New-HordeAbsent -Note ("generation " + $Generation + " is not retired")) }
    return (New-HordeKnown -Value $f.text)
}

function Export-HordeRelayMachineCard {
    # This machine's card: its horde, a label and its public keys, signed by its signing key, for a
    # peer machine of the same horde to add (relay/Trust.ps1). Known text, or the identity's answer.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Label, $Now = $null)
    if ((Test-HordeRelayRecordValue -Kind "label" -Value $Label) -cne "") { return (New-HordeUnknown -Reason "a machine's label is 1 to 64 printable ASCII characters, no quote or backslash, no space at either end") }
    $id = Get-HordeRelayMachineIdentity -HordeHome $HordeHome -Open
    if ($id.state -cne "known") { return $id }
    try {
        $values = @{
            v = 1; kind = "horde-relay-machine-card"; horde = $id.value.horde; label = $Label; generation = $id.value.generation
            signKeyId = $id.value.sign.keyId; signPublic = (ConvertTo-HordeRelayBase64Url -Bytes $id.value.sign.public)
            agreeKeyId = $id.value.agree.keyId; agreePublic = (ConvertTo-HordeRelayBase64Url -Bytes $id.value.agree.public)
            mailbox = $id.value.mailbox; issuedAt = (ConvertTo-HordeRelayRecordMs -Time $Now); proof = ""
        }
        $spec = Get-HordeRelayCardSpec
        $signed = Get-HordeRelayAsciiBytes -Text ((Get-HordeRelayIdentityDomain -Part "card") + (ConvertTo-HordeRelayRecordText -Spec $spec -Values $values))
        $values.proof = ConvertTo-HordeRelayBase64Url -Bytes (New-HordeRelayEs256Signature -Key $id.value.sign.key -Bytes $signed)
        return (New-HordeKnown -Value (ConvertTo-HordeRelayRecordText -Spec $spec -Values $values))
    } finally { $id.value.sign.key.Dispose(); $id.value.agree.key.Dispose() }
}

function Read-HordeRelayMachineCard {
    # A machine card's values, checked: canonical, key ids that are its keys', a mailbox that is its
    # horde and signing key, and a proof that verifies under its own signing key - so whoever made the
    # card held that key. { ok; reason; value }; never throws for the text.
    param([AllowEmptyString()][string]$Text)
    $r = Read-HordeRelayRecordText -Text $Text -Spec (Get-HordeRelayCardSpec) -Kind "horde-relay-machine-card" -What "the machine card"
    if (-not $r.ok) { return $r }
    $c = $r.value
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $signPub = ConvertFrom-HordeRelayBase64Url -Text $c.signPublic
    $agreePub = ConvertFrom-HordeRelayBase64Url -Text $c.agreePublic
    if ($c.signKeyId -cne (Get-HordeRelayKeyId -Public $signPub) -or $c.agreeKeyId -cne (Get-HordeRelayKeyId -Public $agreePub)) { $fail.reason = "the machine card names key ids that are not its keys'"; return $fail }
    if ((Test-HordeRelayHordeName -Name $c.horde) -cne "") { $fail.reason = ("the machine card's horde is refused: " + (Test-HordeRelayHordeName -Name $c.horde)); return $fail }
    if ($c.mailbox -cne ($c.horde + "/" + $c.signKeyId)) { $fail.reason = "the machine card's mailbox is not its horde and signing key"; return $fail }
    $values = @{}
    foreach ($p in $c.PSObject.Properties) { $values[$p.Name] = $p.Value }
    $values.proof = ""
    $signed = Get-HordeRelayAsciiBytes -Text ((Get-HordeRelayIdentityDomain -Part "card") + (ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayCardSpec) -Values $values))
    $proof = ConvertFrom-HordeRelayBase64Url -Text $c.proof
    if (-not (Test-HordeRelayEs256Signature -Public $signPub -Bytes $signed -Signature $proof)) { $fail.reason = "the machine card's proof does not verify under its own signing key"; return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = $c }
}
