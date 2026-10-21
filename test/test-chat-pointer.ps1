# DOES THE PHONE GET "MESSAGE RECEIVED" FOR WEZFLEET'S OWN LINES, AND ITS WORDS FOR NOTHING ELSE?
#
# channels/chat/Pointer.ps1 and Select-HordeChatChannelShown (T-0309, the founder 2026-10-20): the pointer
# line wezfleet types at a Thrall, the "NOT CONFIRMED" line, and the Stop hook's "MESSAGE FROM wezfleet tell"
# header (with that line as its body) are turned into a marker turn - role marker, no words, the time kept -
# on this machine, before the phone is sent anything. The wording is wezfleet's (lib/Mail.ps1
# Get-WfWakeNotice, commands/tell.ps1, hooks/wf-mail-deliver.mjs); a drift in it shows the line again, so
# each form is pinned by its exact text. Every positive sits beside its negative twins: a real line of the
# founder's that mentions wezfleet or a message, quotes part of the pointer, carries the pointer plus more
# words, or differs by one character is never hidden. Run under 5.1 and under MSI PowerShell 7.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray
$loaded = @(Get-HordeMessengerNames)
foreach ($n in $loaded) { [void]$script:HordeMessengers.Remove($n) }

$id32 = "7a5e99735c69f1bc6fdc90f7530561bc"
$id10 = "7a5e99735c"
$pointer = "wezfleet: a message is waiting for you (id " + $id32 + ") - run 'wezfleet mail read' to take it; this line is a pointer, not the message, and re-reading it changes nothing"
$many = "wezfleet: 3 messages are waiting for you (id " + $id32 + ") - run 'wezfleet mail read' to take it; this line is a pointer, not the message, and re-reading it changes nothing"
$unconf = "wezfleet tell to 8f2c1d0e-1111-4222-8333-444455556666 NOT CONFIRMED: the target did not take it in 60s; check with wezfleet mail status"
$header = "MESSAGE FROM wezfleet tell (wezfleet mail " + $id32 + "), delivered to you directly rather than typed into your input box."
$relay = $header + "`n`n" + $unconf
$relayMore = $relay + "`n`n[2 more messages waiting; the next arrives at your following turn boundary.]"

Write-Host "--- the matcher: each wezfleet form is matched whole ---" -ForegroundColor Cyan
Check ((Get-HordeChatPointerKind -Text $pointer) -ceq "pointer") "the pointer line, exactly as wezfleet types it, is a pointer"
Check ((Get-HordeChatPointerKind -Text $many) -ceq "pointer") "the pointer line for several messages is a pointer"
Check ((Get-HordeChatPointerKind -Text ($pointer.Replace($id32, $id10))) -ceq "pointer") "a pointer naming a 10-digit mail id is a pointer"
Check ((Get-HordeChatPointerKind -Text ($pointer + "`r`n")) -ceq "pointer") "a trailing line break does not change it"
Check ((Get-HordeChatPointerKind -Text $unconf) -ceq "unconfirmed") "the NOT CONFIRMED line is an unconfirmed notice"
Check ((Get-HordeChatPointerKind -Text $header) -ceq "relay") "the Stop hook's MESSAGE FROM wezfleet tell header alone is a relay line"
Check ((Get-HordeChatPointerKind -Text $relay) -ceq "relay") "the header with the NOT CONFIRMED line as its body is a relay line"
Check ((Get-HordeChatPointerKind -Text $relayMore) -ceq "relay") "the same with the more-messages trailer is a relay line"
Check ((Test-HordeChatPointerLine -Text $pointer) -eq $true) "Test-HordeChatPointerLine says yes to a pointer"

Write-Host "--- the matcher: a real line of the founder's is never matched ---" -ForegroundColor Cyan
$negatives = [ordered]@{
    "empty" = ""
    "spaces" = "   "
    "mentions wezfleet" = "please run wezfleet mail read for me"
    "mentions message" = "a message is waiting for you"
    "mentions both" = "wezfleet: a message is waiting"
    "quotes the start" = ("wezfleet: a message is waiting for you (id " + $id32 + ")")
    "quotes the end" = "this line is a pointer, not the message, and re-reading it changes nothing"
    "quotes the command" = "run 'wezfleet mail read' to take it"
    "pointer with a lead-in" = ("what is this? " + $pointer)
    "pointer with words after" = ($pointer + " - why did it appear?")
    "pointer with a second line" = ($pointer + "`nplease explain")
    "two pointers" = ($pointer + "`n" + $pointer)
    "pointer in a quote" = ('"' + $pointer + '"')
    "pointer with a capital" = $pointer.Replace("wezfleet:", "Wezfleet:")
    "pointer with a changed word" = $pointer.Replace("waiting for you", "waiting for me")
    "pointer with a bad id" = $pointer.Replace($id32, "not-an-id")
    "pointer with an upper-case id" = $pointer.Replace($id32, $id32.ToUpper())
    "pointer with a long id" = $pointer.Replace($id32, $id32 + "00")
    "pointer with no id" = $pointer.Replace(" (id " + $id32 + ")", "")
    "pointer with a leading space" = (" " + $pointer)
    "NOT CONFIRMED with a lead-in" = ("ok so " + $unconf)
    "NOT CONFIRMED as prose" = "the tell was NOT CONFIRMED yesterday"
    "NOT CONFIRMED on two lines" = ($unconf + "`nand then more")
    "NOT CONFIRMED lower case" = $unconf.Replace("NOT CONFIRMED", "not confirmed")
    "NOT CONFIRMED without a session" = "wezfleet tell to NOT CONFIRMED: x"
    "header with a lead-in" = ("see this: " + $header)
    "header with other words" = ($header + " Please merge it.")
    "header with a body that is not a notice" = ($header + "`n`nmerge the PR now")
    "header from another sender" = $header.Replace("wezfleet tell", "M")
    "header with a bad id" = $header.Replace($id32, "xyz")
    "header then a notice then words" = ($relay + "`n`nand also this")
    "founder line header" = ("FOUNDER LINE from the phone (line " + $id32 + ")`n`nhello")
}
foreach ($k in $negatives.Keys) { Check ((Get-HordeChatPointerKind -Text $negatives[$k]) -ceq "") ("not hidden: " + $k) }
Check ((Test-HordeChatPointerLine -Text $null) -eq $false) "a null text is not a pointer"

Write-Host "--- the channel: marker turns, in place, no words ---" -ForegroundColor Cyan
$src = [pscustomobject]@{ session = "s1" }
function NewTurn { param([string]$Role, [string]$Text, [string]$Id) return [pscustomobject]@{ role = $Role; text = $Text; turnId = $Id; time = "2026-10-20T15:44:00.000Z"; source = $src } }
$turns = @(
    (NewTurn "user" "how is it going?" "t1"),
    (NewTurn "user" $pointer "t2"),
    (NewTurn "assistant" $pointer "t3"),
    (NewTurn "user" ("I saw " + $pointer) "t4"),
    (NewTurn "delivered" $relay "t5"),
    (NewTurn "delivered" "MESSAGE FROM M (mail 0123)`n`nmerge it" "t6"),
    (NewTurn "user" $unconf "t7"),
    (NewTurn "system" $pointer "t8")
)
$shown = @(Select-HordeChatChannelShown -Turns $turns -Lines @())
Check ($shown.Count -eq 7) ("all but the other session's mail are shown (" + $shown.Count + ")")
$byId = @{}; foreach ($t in $shown) { $byId[$t.turnId] = $t }
Check ($byId["t1"].role -ceq "user" -and $byId["t1"].text -ceq "how is it going?") "a real user line is untouched"
foreach ($i in @("t2", "t5", "t7")) {
    Check ($byId[$i].role -ceq "marker" -and $byId[$i].text -ceq "" -and $byId[$i].time -ceq "2026-10-20T15:44:00.000Z" -and $null -ne $byId[$i].source -and $byId[$i].source.session -ceq "s1") ("turn " + $i + " is a marker with its time and no words")
}
Check ($byId["t3"].role -ceq "assistant" -and $byId["t3"].text -ceq $pointer) "the Thrall quoting the pointer is the Thrall's, shown as it is"
Check ($byId["t4"].role -ceq "user" -and $byId["t4"].text -ceq ("I saw " + $pointer)) "a user line that holds the pointer among other words is shown as his"
Check ($byId["t8"].role -ceq "system") "a system turn is not turned into a marker"
Check (-not $byId.ContainsKey("t6")) "another sender's delivered mail is still not sent to the phone"
$entries = @(ConvertTo-HordeChatChannelEntries -Turn $byId["t2"] -Room 4000)
Check ($entries.Count -eq 1 -and $entries[0] -cmatch '"role":"marker"' -and $entries[0] -cmatch '"text":""' -and $entries[0] -cnotmatch 'wezfleet|7a5e' -and $entries[0] -cmatch '"time":"2026-10-20T15:44:00.000Z"') ("the sealed entry says marker, its time and no text (" + $entries[0] + ")")

Complete-HordeSuite -Success "wezfleet's pointer, NOT CONFIRMED and MESSAGE FROM wezfleet tell lines reach the phone as a marker turn with only their time; a founder line that mentions, quotes or extends them is never hidden"
