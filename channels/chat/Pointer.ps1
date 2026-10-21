# channels/chat/Pointer.ps1 - the wezfleet lines that are not the founder's and not his Thrall's words, so the
# phone shows "message received" for them and never their wording (task T-0309, the founder 2026-10-20).
#
# THE THREE LINES. wezfleet puts them in front of a Thrall and they land in its transcript, where the chat
# reader would hand them to the phone as text typed at the machine (the founder saw the first as "At the
# machine 15:44", id and all):
#   pointer     wezfleet: a message is waiting for you (id <id>) - run 'wezfleet mail read' to take it; this line
#               is a pointer, not the message, and re-reading it changes nothing
#               (lib/Mail.ps1 Get-WfWakeNotice; "N messages are" for more than one)
#   unconfirmed wezfleet tell to <session> NOT CONFIRMED: <what>
#               (commands/tell.ps1 Send-WfTellUnconfirmedNotice: one line, 300 characters at most)
#   relay       MESSAGE FROM wezfleet tell (wezfleet mail <id>), delivered to you directly rather than typed into
#               your input box.  - the Stop hook's header (hooks/wf-mail-deliver.mjs), then a blank line and the
#               notice's body (an unconfirmed line), then a "[N more message(s) waiting; ...]" trailer if more wait
#
# DECIDED HERE, WHERE THE LINE IS READ (Select-HordeChatChannelShown), so the words never leave this machine:
# a phone that never gets them cannot show them, and an older phone cannot either.
#
# EXACT, ANCHORED, WHOLE TEXT, CASE SENSITIVE. A real line of the founder's that merely mentions wezfleet or
# a message, quotes part of the pointer, or carries more than the pointer, is not matched and is shown as his.
# The only slack is a trailing line break. Everything wezfleet fixes is spelled out below; the free parts (the
# session, the reason) are one bounded line each.

$script:HordeChatPointerId = '(?:[0-9a-f]{32}|[0-9a-f]{10})'
$script:HordeChatPointerPatterns = [ordered]@{
    pointer = '\Awezfleet: (?:a message is|[0-9]{1,6} messages are) waiting for you \(id ' + $script:HordeChatPointerId + '\) - run ''wezfleet mail read'' to take it; this line is a pointer, not the message, and re-reading it changes nothing\z'
    unconfirmed = '\Awezfleet tell to [^\s]{1,128} NOT CONFIRMED: [^\r\n]{0,300}\z'
}
$script:HordeChatPointerRelayHeader = '\AMESSAGE FROM wezfleet tell \(wezfleet mail ' + $script:HordeChatPointerId + '\), delivered to you directly rather than typed into your input box\.'
$script:HordeChatPointerRelayMore = '\n\n\[[0-9]{1,6} more messages? waiting; the next arrives at your following turn boundary\.\]\z'

function Get-HordeChatPointerKind {
    # Which wezfleet line -Text is, whole: "pointer", "unconfirmed" or "relay"; "" for anything else.
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return "" }
    $t = $Text.TrimEnd([char]13, [char]10)
    if ($t -eq "") { return "" }
    foreach ($k in $script:HordeChatPointerPatterns.Keys) { if ($t -cmatch $script:HordeChatPointerPatterns[$k]) { return $k } }
    $h = [regex]::Match($t, $script:HordeChatPointerRelayHeader)
    if (-not $h.Success) { return "" }
    $rest = $t.Substring($h.Index + $h.Length)
    $more = [regex]::Match($rest, $script:HordeChatPointerRelayMore)
    if ($more.Success) { $rest = $rest.Substring(0, $more.Index) }
    if ($rest -eq "") { return "relay" }
    if ($rest.StartsWith("`n`n", [System.StringComparison]::Ordinal) -and $rest.Substring(2) -cmatch $script:HordeChatPointerPatterns["unconfirmed"]) { return "relay" }
    return ""
}

function Test-HordeChatPointerLine {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    return ((Get-HordeChatPointerKind -Text $Text) -cne "")
}
