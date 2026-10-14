# notices/Decide.ps1 - THE ONE PLACE ON THIS MACHINE THAT DECIDES WHAT BECOMES A NOTICE for the founder's
# phone, and the place push hooks in (Invoke-HordeNoticeHook, below). Nothing else writes a notice: the
# `horde notify` command and the notices channel (channels/notices/Channel.ps1) each hand this file what
# they have, and this file decides, under the store's lock (notices/Store.ps1).
#
# WHAT BECOMES A NOTICE (the founder's answers in the push design, 2026-10-13 and 14, records 176, 184 and
# the progress switch relayed on 2026-10-14):
#   1. A NOTIFY LINE (Submit-HordeNotify): a session he told "notify me when X is done" runs `horde notify
#      -Text <one line>`. The sender is the session's own label, PROVEN by notices/Sender.ps1 - the caller
#      gives no name. It is NEVER MUTED BY ANY SWITCH: he asked for it himself.
#        - NO SECRET LEAVES THE MACHINE: the WHOLE text is put through core/Secrets.ps1 (every kind, its
#          defaults, as the progress log's entries are) BEFORE it is cut to textChars. A text that trips
#          it becomes the fixed sentence below, never the text and never what tripped it; the caller is
#          told it was refused, and the notice still goes, so the founder still knows the session spoke.
#          Cut first, a token across the cut loses its tail and matches no pattern any more (review of
#          PR 244 measured 23 characters of a token getting out that way).
#        - THE HOURLY CAP, per session, per clock hour (UTC): perHour notices. The one past it is not
#          sent; the session is CUT OFF FOR THE REST OF THAT HOUR, and the founder is told ONCE, in plain
#          words, which session it was and until when (a cutoff notice). Every later call that hour is
#          refused to the caller and tells the founder nothing more. A new hour starts the count again.
#          Counted by the PROVEN session id, so two sessions that share a label are two counts, and one
#          session cannot spread its notices over names.
#   2. A NEW PROGRESS ENTRY OF A FOLLOWED LANE (Submit-HordeProgressNotices): each Orc's card and the
#      Thrall's has a follow switch on the phone, OFF BY DEFAULT. The channel hands over the entries that
#      are NEW to it (it follows the log from where it stood, never from its start), each with the lanes
#      it belongs to (the phone's own rule, relay/js/protocol.js entryLanes: its own lanes, else its
#      area's). An entry is ONE notice when ANY of its lanes is followed - however many are - and never
#      again, however often it is offered. An entry of no lane is the Thrall's: it shows only in the
#      Thrall's stream on the phone, so following the Thrall follows those.
#   3. A TRUST EVENT OF THIS MACHINE (Submit-HordeSystemNotice; phone-started pairing, relay/Join.ps1 and
#      threat 4 of its design: "every trusted device is told"): a new phone asked to join, and what became
#      of it - approved, rejected, expired. From "Horde", never muted, and with NO HOURLY CAP: the relay
#      already holds join requests to one pending and a few an hour, and a security event is never held
#      back. The same secret check and cut as rule 1.
#   4. NOTHING ELSE. No chat line, no decisions question (the decisions switch and push are later work).
#
# THE FOLLOW SWITCHES (Set-HordeNoticeFollow) are set on the phone and reach the machine SEALED, signed by
# the founder's passkey, the way an answer does (channels/notices/Channel.ps1); the machine keeps them
# and the phone shows what the machine holds. Of two settings of one lane, the one the phone signed
# LATER stands, whatever order they arrive in.
#
# WHERE PUSH HOOKS IN: Invoke-HordeNoticeHook is called with every notice this file has just written,
# once, after it is on disk. Today it does nothing - the phone reads the notices through the channel.
# The machine half of Web Push (RFC 8291 encryption to each phone's push key, the relay's posting
# endpoint) is the one call to add there, and nowhere else.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Store.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Secrets.ps1")

function Get-HordeNoticeSecretWords { return "This notice looked like it held a secret, so its words stay at the machine." }

function Get-HordeNoticeHour {
    # The clock hour (UTC) -Now is in, as the counts key it: "2026-10-14T03".
    param([Parameter(Mandatory = $true)][datetime]$Now)
    return $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-HordeNoticeText {
    # What a notice holds of -Text (NO SECRET LEAVES THE MACHINE, in the header): { text; refused } - the
    # control characters as spaces, trimmed; THEN the whole of it checked; THEN cut to -Chars with "...".
    param([AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][int]$Chars)
    $whole = ([regex]::Replace($Text, '\p{Cc}', ' ')).Trim()
    if ((Find-HordeSecretKind -Text $whole) -cne "") { return [pscustomobject]@{ text = (Get-HordeNoticeSecretWords); refused = $true } }
    if ($whole.Length -gt $Chars) { $whole = $whole.Substring(0, $Chars - 3).TrimEnd() + "..." }
    return [pscustomobject]@{ text = $whole; refused = $false }
}

function New-HordeNoticeId { return [guid]::NewGuid().ToString("N") }

function Get-HordeNoticeTime {
    param([Parameter(Mandatory = $true)][datetime]$Now)
    return $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Invoke-HordeNoticeHook {
    # WHERE PUSH HOOKS IN (the header): every notice just written, once, after it is on disk. Nothing is
    # done here yet; nothing may fail a notice from here.
    param([AllowEmptyCollection()][object[]]$Notices)
    return
}

function Get-HordeNoticeStore {
    # The settings and the store folder of -HordeHome: { ok; reason; settings; store }.
    param([string]$HordeHome = "")
    if ($HordeHome -ceq "") { $HordeHome = Get-HordeHome }
    $s = Get-HordeNoticeSettings -HordeHome $HordeHome
    if ($s.state -cne "known") { return [pscustomobject]@{ ok = $false; reason = ("the notices settings are refused: " + $s.reason); settings = $null; store = "" } }
    return [pscustomobject]@{ ok = $true; reason = ""; settings = $s.value; store = (Get-HordeNoticeStoreFolder -HordeHome $HordeHome -Folder $s.value.storeFolder) }
}

function Submit-HordeNotify {
    # A notify line from a PROVEN sender (notices/Sender.ps1's answer, ok): rule 1 of the header.
    # { outcome; reason; notice } - outcome "sent" (written, as notice), "sent-refused" (written as the
    # fixed sentence: the text looked like a secret), "cut-off" (over the cap: not written; the founder
    # told now, once - notice is that cutoff notice), "held" (over the cap, the founder already told) or
    # "failed" (nothing written, reason says why).
    param([Parameter(Mandatory = $true)]$Sender, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [string]$HordeHome = "", $Now = $null)
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    $fail = { param([string]$Why) return [pscustomobject]@{ outcome = "failed"; reason = $Why; notice = $null } }
    if ($null -eq $Sender -or -not $Sender.ok -or "$($Sender.sessionId)" -ceq "" -or "$($Sender.label)" -ceq "") { return (& $fail "no notice was sent: the sender is not proven") }
    if ($Text.Trim() -eq "") { return (& $fail "no notice was sent: -Text is empty") }
    if ($Text -cmatch "[\r\n]") { return (& $fail "no notice was sent: -Text is one line, and it has a line break") }
    $st = Get-HordeNoticeStore -HordeHome $HordeHome
    if (-not $st.ok) { return (& $fail ("no notice was sent: " + $st.reason)) }
    $hour = Get-HordeNoticeHour -Now $Now
    # The sender's name is checked like the text: it goes to the phone too.
    $from = Get-HordeNoticeText -Text $Sender.label -Chars 40
    $fromWords = $(if ($from.refused) { "a session" } else { $from.text })
    $said = Get-HordeNoticeText -Text $Text -Chars ([int]$st.settings.textChars)
    $answer = Use-HordeNoticeLock -Store $st.store -Body {
        $state = Read-HordeNoticeState -Store $st.store
        if ($state.state -cne "known") { return (& $fail ("no notice was sent: " + $state.reason)) }
        $s = $state.value
        $mine = $(if ($s.sessions.ContainsKey($Sender.sessionId)) { $s.sessions[$Sender.sessionId] } else { $null })
        if ($null -eq $mine -or $mine.hour -cne $hour) { $mine = [pscustomobject]@{ hour = $hour; count = 0; told = $false }; $s.sessions[$Sender.sessionId] = $mine }
        if ($mine.count -ge [int]$st.settings.perHour) {
            $until = $Now.ToUniversalTime().Date.AddHours($Now.ToUniversalTime().Hour + 1).ToString("HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
            $why = "no notice was sent: this session has sent " + $mine.count + " notices this hour, the most one session may (the setting perHour), so it is cut off until " + $until + " UTC"
            if ($mine.told) { return [pscustomobject]@{ outcome = "held"; reason = $why; notice = $null } }
            # CUT OFF, AND THE FOUNDER TOLD ONCE (the header).
            $cut = [pscustomobject]@{ id = (New-HordeNoticeId); ts = (Get-HordeNoticeTime -Now $Now); kind = "cutoff"; from = "Horde"
                text = ($fromWords + " sent more than " + $mine.count + " notices this hour, so its notices are held back until " + $until + " UTC."); lane = ""; entry = "" }
            $written = @(Add-HordeNoticeLines -Store $st.store -Notices @($cut) -Keep ([int]$st.settings.keepNotices))
            $mine.told = $true
            Write-HordeNoticeState -Store $st.store -State $s -Hour $hour
            return [pscustomobject]@{ outcome = "cut-off"; reason = ($why + "; the founder is told so once"); notice = $written[0] }
        }
        $one = [pscustomobject]@{ id = (New-HordeNoticeId); ts = (Get-HordeNoticeTime -Now $Now); kind = "notify"; from = $fromWords; text = $said.text; lane = ""; entry = "" }
        $written = @(Add-HordeNoticeLines -Store $st.store -Notices @($one) -Keep ([int]$st.settings.keepNotices))
        # Counted after it is written: a crash between the two costs the session one notice of its
        # hour's count, never the founder a notice.
        $mine.count = $mine.count + 1
        Write-HordeNoticeState -Store $st.store -State $s -Hour $hour
        if ($said.refused) { return [pscustomobject]@{ outcome = "sent-refused"; reason = "the text looked like it held a secret, so the founder was sent a notice saying so, not the text"; notice = $written[0] } }
        return [pscustomobject]@{ outcome = "sent"; reason = ""; notice = $written[0] }
    }
    if ($null -ne $answer.notice) { Invoke-HordeNoticeHook -Notices @($answer.notice) }
    return $answer
}

function Submit-HordeSystemNotice {
    # A trust event of this machine (rule 3 of the header), from "Horde". { outcome; reason; notice }:
    # "sent", "sent-refused" (it looked like a secret: the fixed sentence went) or "failed".
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [string]$HordeHome = "", $Now = $null)
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    $fail = { param([string]$Why) return [pscustomobject]@{ outcome = "failed"; reason = $Why; notice = $null } }
    if ($Text.Trim() -eq "" -or $Text -cmatch "[\r\n]") { return (& $fail "no notice was sent: the text is not one line") }
    $st = Get-HordeNoticeStore -HordeHome $HordeHome
    if (-not $st.ok) { return (& $fail ("no notice was sent: " + $st.reason)) }
    $said = Get-HordeNoticeText -Text $Text -Chars ([int]$st.settings.textChars)
    try {
        $answer = Use-HordeNoticeLock -Store $st.store -Body {
            $one = [pscustomobject]@{ id = (New-HordeNoticeId); ts = (Get-HordeNoticeTime -Now $Now); kind = "notify"; from = "Horde"; text = $said.text; lane = ""; entry = "" }
            $written = @(Add-HordeNoticeLines -Store $st.store -Notices @($one) -Keep ([int]$st.settings.keepNotices))
            return [pscustomobject]@{ outcome = $(if ($said.refused) { "sent-refused" } else { "sent" }); reason = ""; notice = $written[0] }
        }
    } catch { return (& $fail ("no notice was sent: " + $_.Exception.Message)) }
    if ($null -ne $answer.notice) { Invoke-HordeNoticeHook -Notices @($answer.notice) }
    return $answer
}

function Get-HordeNoticeLaneWords {
    # A lane id as the founder reads it in a notice's sender: "Thrall", "Orc E", or the lane's own name.
    param([Parameter(Mandatory = $true)][string]$Lane)
    if ($Lane -ceq "thrall") { return "Thrall" }
    if ($Lane -cmatch '\A[A-Z][A-Z0-9]{0,3}\z') { return ("Orc " + $Lane) }
    return $Lane
}

function Submit-HordeProgressNotices {
    # Rule 2 of the header: -Entries are NEW progress entries, each { id; title; kind; lanes } (lanes the
    # lanes it belongs to; none for the Thrall's). Known @(notices written), or unknown with the reason.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Entries, [string]$HordeHome = "", $Now = $null)
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    if (@($Entries).Count -eq 0) { return (New-HordeKnown -Value @()) }
    $st = Get-HordeNoticeStore -HordeHome $HordeHome
    if (-not $st.ok) { return (New-HordeUnknown -Reason $st.reason) }
    $answer = Use-HordeNoticeLock -Store $st.store -Body {
        $f = Read-HordeNoticeFollows -Store $st.store
        if ($f.state -cne "known") { return (New-HordeUnknown -Reason $f.reason) }
        $on = @(@($f.value.Keys) | Where-Object { $f.value[$_].on })
        # OFF BY DEFAULT: with no switch on, nothing is read or written.
        if ($on.Count -eq 0) { return (New-HordeKnown -Value @()) }
        $state = Read-HordeNoticeState -Store $st.store
        if ($state.state -cne "known") { return (New-HordeUnknown -Reason $state.reason) }
        $s = $state.value
        $done = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        foreach ($e in @($s.entries)) { [void]$done.Add($e) }
        $new = New-Object System.Collections.ArrayList
        foreach ($e in @($Entries)) {
            if ($done.Contains($e.id)) { continue }
            $lanes = @(@($e.lanes) | Where-Object { "$_" -cne "" })
            if ($lanes.Count -eq 0) { $lanes = @("thrall") }
            # ONE NOTICE WHEN ANY OF ITS LANES IS FOLLOWED, named by the first of them that is.
            $through = @($lanes | Where-Object { $on -ccontains $_ } | Select-Object -First 1)
            if ($through.Count -eq 0) { continue }
            $said = Get-HordeNoticeText -Text ("" + $e.title) -Chars ([int]$st.settings.textChars)
            $kind = "" + $e.kind
            $text = $(if ($said.refused -or $kind -ceq "" -or $kind -ceq "note") { $said.text } else { $kind.Substring(0, 1).ToUpperInvariant() + $kind.Substring(1) + ": " + $said.text })
            [void]$new.Add([pscustomobject]@{ id = (New-HordeNoticeId); ts = (Get-HordeNoticeTime -Now $Now); kind = "progress"; from = (Get-HordeNoticeLaneWords -Lane $through[0]); text = $text; lane = $through[0]; entry = $e.id })
            [void]$done.Add($e.id)
            $s.entries = @(@($s.entries) + $e.id)
        }
        if ($new.Count -eq 0) { return (New-HordeKnown -Value @()) }
        $written = @(Add-HordeNoticeLines -Store $st.store -Notices @($new.ToArray()) -Keep ([int]$st.settings.keepNotices))
        Write-HordeNoticeState -Store $st.store -State $s -Hour (Get-HordeNoticeHour -Now $Now)
        return (New-HordeKnown -Value $written)
    }
    if ($answer.state -ceq "known" -and @($answer.value).Count -gt 0) { Invoke-HordeNoticeHook -Notices @($answer.value) }
    return $answer
}

function Set-HordeNoticeFollow {
    # One switch from the phone: -Lane on or off, as the phone signed it at -At (ms) in the envelope -Key.
    # Known { changed; lane; on }: changed $false when the machine already holds this or a later setting
    # of the lane (the same envelope again, or one the phone signed earlier) - so it is idempotent by the
    # record. Unknown with the reason when the switches cannot be read or written.
    param([Parameter(Mandatory = $true)][string]$Lane, [Parameter(Mandatory = $true)][bool]$On, [Parameter(Mandatory = $true)][long]$At, [Parameter(Mandatory = $true)][string]$Key, [string]$HordeHome = "")
    if (-not (Test-HordeNoticeLane $Lane)) { return (New-HordeUnknown -Reason ("'" + $Lane + "' is not a lane")) }
    $st = Get-HordeNoticeStore -HordeHome $HordeHome
    if (-not $st.ok) { return (New-HordeUnknown -Reason $st.reason) }
    return (Use-HordeNoticeLock -Store $st.store -Body {
        $f = Read-HordeNoticeFollows -Store $st.store
        if ($f.state -cne "known") { return $f }
        $had = $(if ($f.value.ContainsKey($Lane)) { $f.value[$Lane] } else { $null })
        # THE LATER SIGNATURE STANDS (the header). On the same time, the replay key decides, so two
        # machines - or one machine twice - never disagree on which of two settings stands.
        if ($null -ne $had -and ($had.at -gt $At -or ($had.at -eq $At -and [string]::CompareOrdinal($had.key, $Key) -ge 0))) { return (New-HordeKnown -Value ([pscustomobject]@{ changed = $false; lane = $Lane; on = $had.on })) }
        $f.value[$Lane] = [pscustomobject]@{ on = $On; at = $At; key = $Key }
        Write-HordeNoticeFollows -Store $st.store -Follows $f.value
        return (New-HordeKnown -Value ([pscustomobject]@{ changed = $true; lane = $Lane; on = $On }))
    })
}
