# IS THE WARCHIEF TOLD ONCE OF EACH THING THE WATCHER CANNOT MEND, AND NEVER BURIED IN IT?
#
# core/WakeTell.ps1 - the tell sender. Its pass is pure, so it is driven here with conditions this suite
# makes, a clock it moves by hand and a poster it hands in; the poster itself is driven through the
# in-process test messenger and one registered from the messenger port suite's fixture folder:
#   - ONE MAIL A CONDITION: the same condition on later passes is nothing; another session or another
#     instance is another mail, under an id made from what it is.
#   - AT MOST SIX AN HOUR: the rest are journaled as suppressed, once, and only real tells count.
#   - THE TEXT SAYS IT IS AUTOMATED, AND FROM WHOM.
#   - SHADOW POSTS NOTHING, and journals what it would tell.
#   - NOTHING IS CLAIMED THAT DID NOT HAPPEN: a post that could not say is tried again, later.
# The file (tells-<mode>.json) is written under a home this suite made and removes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "test\lib\FleetPin.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
# PINNED FIRST: an empty fleet and a home of this suite's, so nothing below can read or write the real ones.
$fleetPin = Enter-HordeTestEmptyFleet
$pinned = Enter-HordeTestPinnedHome -Root $root
. (Join-Path $root "core\WakeTell.ps1")
. (Join-Path $root "messengers\memory\Messenger.ps1")

$t0 = New-Object System.DateTime(2026, 10, 12, 8, 0, 0, [System.DateTimeKind]::Utc)
function At { param([double]$Seconds) return $t0.AddSeconds($Seconds) }
function Sid { param([int]$N) return ("0a000000-0000-4000-8000-" + $N.ToString("000000000000")) }
function Cond { param([int]$N, [string]$Kind = "gave-up", [string]$Instance = "one") return (New-HordeWakeTellCondition -Kind $Kind -Subject (Sid $N) -Instance $Instance -Text ("session " + $N + " needs a look")) }
function Kinds { param($Result) return (@($Result.entries | ForEach-Object { $_.kind + ":" + $_.outcome }) -join ",") }
$chief = Sid 99
$settings = Get-HordeWakeTellSettings
$script:mails = New-Object System.Collections.ArrayList
$taking = { param($m) [void]$script:mails.Add($m); New-HordeKnown -Value ([pscustomobject]@{ messageId = $m.messageId; stage = "accepted" }) }

try {
    Write-Host "--- what a tell is ---" -ForegroundColor Cyan

    Check ($settings.maxTellsPerHour -eq 6 -and $settings.fromLabel -ceq "WW" -and $settings.prefix -ceq "AUTOMATED, from the wake watcher: ") "at most six tells an hour, wearing WW, and beginning with the words that say a machine wrote it"
    $threw = $false; try { $null = Get-HordeWakeTellSettings -Overrides @{ maxTells = 1 } } catch { $threw = $true }
    Check $threw "a name that is no tell setting is refused"
    $threw = $false; try { $null = New-HordeWakeTellCondition -Kind "lonely" -Instance "x" -Text "x" } catch { $threw = $true }
    Check $threw "a condition of a kind nobody declared is refused"
    # EVERY KIND THE WATCHER MAKES IS ONE THE SENDER TAKES. A kind left out of the list throws where the tick
    # makes the condition, and the warchief is never told of it - the end of the silent probes was one.
    $taken = @(@("gave-up", "fleet-read-failing", "bad-mail", "nudge-killed", "fleet-silent", "silent-probes-ended") | Where-Object { $k = $_; try { $null = New-HordeWakeTellCondition -Kind $k -Instance "x" -Text "x"; $true } catch { $false } })
    Check ($taken.Count -eq 6) ("every kind of condition the watcher makes is one the sender takes, the end of the silent probes too (" + ($taken -join ",") + ")")
    $idA = Get-HordeWakeTellMessageId -Condition (Cond 1)
    Check ($idA -ceq (Get-HordeWakeTellMessageId -Condition (Cond 1)) -and $idA -cmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') "the same condition is the same message id, every time"
    Check ($idA -cne (Get-HordeWakeTellMessageId -Condition (Cond 2)) -and $idA -cne (Get-HordeWakeTellMessageId -Condition (Cond 1 "gave-up" "two")) -and $idA -cne (Get-HordeWakeTellMessageId -Condition (Cond 1 "bad-mail"))) "another session, another instance or another kind is another message"

    Write-Host ""
    Write-Host "--- one mail a condition ---" -ForegroundColor Cyan

    $script:mails.Clear()
    $one = Invoke-HordeWakeTellPass -Conditions @((Cond 1), (Cond 2)) -Warchief $chief -Now (At 0) -Settings $settings -Post $taking
    Check ((Kinds $one) -ceq "tell:posted,tell:posted" -and $script:mails.Count -eq 2 -and $one.told.Count -eq 2) "two conditions are two tells, each posted and marked told"
    Check (@($script:mails | Where-Object { $_.to -cne $chief -or -not "$($_.body)".StartsWith("AUTOMATED, from the wake watcher: session ") }).Count -eq 0 -and $script:mails[0].messageId -ceq $idA -and $one.entries[0].messageId -ceq $idA -and $one.entries[0].id -ceq (Sid 1)) "each goes to the warchief, under the condition's own id, and its text begins by saying it is automated and from the wake watcher"
    $two = Invoke-HordeWakeTellPass -Conditions @((Cond 1), (Cond 2)) -Warchief $chief -Now (At 3) -Settings $settings -Post $taking -Told $one.told
    Check (@($two.entries).Count -eq 0 -and $script:mails.Count -eq 2 -and $two.told.Count -eq 2) "the same conditions on the next pass are nothing: not posted, not journaled"
    $week = Invoke-HordeWakeTellPass -Conditions @((Cond 1)) -Warchief $chief -Now (At 604801) -Settings $settings -Post $taking -Told $two.told
    Check ((Kinds $week) -ceq "tell:posted" -and $week.told.Count -eq 1) "after a week what was told is forgotten: a condition still there then is news again"

    Write-Host ""
    Write-Host "--- never a stream: six an hour ---" -ForegroundColor Cyan

    $script:mails.Clear()
    $flood = Invoke-HordeWakeTellPass -Conditions @(1..8 | ForEach-Object { Cond $_ }) -Warchief $chief -Now (At 0) -Settings $settings -Post $taking
    Check ((@($flood.entries | Where-Object { $_.kind -ceq "tell" -and $_.outcome -ceq "posted" }).Count -eq 6) -and $script:mails.Count -eq 6) "of eight conditions at once, six are told"
    $rest = @($flood.entries | Where-Object { $_.kind -ceq "tell-suppressed" })
    Check ($rest.Count -eq 2 -and $rest[0].id -ceq (Sid 7) -and "$($rest[0].reason)".StartsWith("gave-up: over 6 tells in an hour") -and "$($rest[0].reason)".Contains("session 7 needs a look")) "and two are journaled as suppressed, each with what it would have said"
    $after = Invoke-HordeWakeTellPass -Conditions @(1..8 | ForEach-Object { Cond $_ }) -Warchief $chief -Now (At 3) -Settings $settings -Post $taking -Told $flood.told
    Check (@($after.entries).Count -eq 0 -and $script:mails.Count -eq 6) "the next pass says none of the eight again: a suppressed tell is journaled once and is not sent later"
    $half = Invoke-HordeWakeTellPass -Conditions @(11..16 | ForEach-Object { Cond $_ }) -Warchief $chief -Now (At 1800) -Settings $settings -Post $taking -Told $after.told
    Check (@($half.entries | Where-Object { $_.kind -ceq "tell-suppressed" }).Count -eq 6 -and $script:mails.Count -eq 6) "half an hour on the six of that hour still count: six more are all suppressed"
    $hour = Invoke-HordeWakeTellPass -Conditions @((Cond 21)) -Warchief $chief -Now (At 3601) -Settings $settings -Post $taking -Told $half.told
    Check ((Kinds $hour) -ceq "tell:posted" -and $script:mails.Count -eq 7) "an hour after the six were told the next is told: the limit is by the hour, and only what was told counts against it - not what was suppressed"

    # A NOTICE ABOUT THE WHOLE FLEET is never crowded out by notices about sessions.
    $script:mails.Clear()
    $silent = New-HordeWakeTellCondition -Kind "fleet-silent" -Subject "" -Instance "2026-10-12T08:00:00Z" -Text "the fleet is silent"
    $dark = New-HordeWakeTellCondition -Kind "fleet-read-failing" -Subject "" -Instance "2026-10-12T08:00:00Z" -Text "the fleet cannot be read"
    $six = Invoke-HordeWakeTellPass -Conditions @(1..6 | ForEach-Object { Cond $_ }) -Warchief $chief -Now (At 0) -Settings $settings -Post $taking
    Check ($script:mails.Count -eq 6) "CONTROL: six sessions given up on are six tells, and the hour's budget for sessions is spent"
    $then = Invoke-HordeWakeTellPass -Conditions @((Cond 7), $silent) -Warchief $chief -Now (At 60) -Settings $settings -Post $taking -Told $six.told
    Check ((@($then.entries | Where-Object { $_.kind -ceq "tell" -and $_.outcome -ceq "posted" -and $_.id -ceq "" }).Count -eq 1) -and (@($then.entries | Where-Object { $_.kind -ceq "tell-suppressed" -and $_.id -ceq (Sid 7) }).Count -eq 1) -and $script:mails.Count -eq 7 -and "$($script:mails[6].body)".Contains("the fleet is silent")) "a minute later the fleet's one notice IS told, though a seventh session's is suppressed: the notice that explains the others is never the one crowded out"
    Check ($then.entries[0].id -ceq "" -and $then.entries[0].kind -ceq "tell") "and it is sent first, whatever order the conditions came in"
    $more = Invoke-HordeWakeTellPass -Conditions @($dark) -Warchief $chief -Now (At 120) -Settings $settings -Post $taking -Told $then.told
    Check ((Kinds $more) -ceq "tell:posted") "a second kind of fleet notice in the same hour is told too"
    $script:mails.Clear()
    $fleetOnly = Invoke-HordeWakeTellPass -Conditions @(1..8 | ForEach-Object { New-HordeWakeTellCondition -Kind "fleet-silent" -Subject "" -Instance ("instance-" + $_) -Text "silent again" }) -Warchief $chief -Now (At 0) -Settings $settings -Post $taking
    $afterFleet = Invoke-HordeWakeTellPass -Conditions @((Cond 1)) -Warchief $chief -Now (At 30) -Settings $settings -Post $taking -Told $fleetOnly.told
    Check ($script:mails.Count -eq 7 -and @($fleetOnly.entries | Where-Object { $_.kind -ceq "tell-suppressed" }).Count -eq 2 -and (Kinds $afterFleet) -ceq "tell:posted") "fleet notices have a limit of their own - six an hour - and do not use up the sessions' either: a flapping fleet cannot bury the warchief or silence a session's tell"
    $hc = Join-Path $pinned.home ("class-" + [guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $hc | Out-Null
    Save-HordeWakeTellState -Told $then.told -Mode "shadow" -HordeHome $hc
    $classes = @((Read-HordeWakeTellState -Mode "shadow" -HordeHome $hc).value.told.Values | ForEach-Object { Get-HordeWakeTellClass $_ } | Group-Object | ForEach-Object { $_.Name + "=" + $_.Count } | Sort-Object)
    Check (($classes -join ",") -ceq "fleet=1,session=7") ("which budget each tell counted against is saved with it (" + ($classes -join ",") + ")")

    Write-Host ""
    Write-Host "--- shadow, nobody to tell, and a post that fails ---" -ForegroundColor Cyan

    $script:mails.Clear()
    $hush = Invoke-HordeWakeTellPass -Conditions @((Cond 1), (Cond 2)) -Warchief $chief -Now (At 0) -Settings $settings -Shadow -Post $taking
    Check ((Kinds $hush) -ceq "would-tell:would-tell,would-tell:would-tell" -and $script:mails.Count -eq 0 -and "$($hush.entries[0].reason)" -ceq "gave-up: session 1 needs a look" -and $hush.entries[0].messageId -ceq $idA) "in shadow each is journaled as would-tell, with its id and what it would say, and the poster in hand is never called"
    $hush2 = Invoke-HordeWakeTellPass -Conditions @((Cond 1), (Cond 2)) -Warchief $chief -Now (At 3) -Settings $settings -Shadow -Post $taking -Told $hush.told
    Check (@($hush2.entries).Count -eq 0) "and not again on the next pass"
    $hushFlood = Invoke-HordeWakeTellPass -Conditions @(1..8 | ForEach-Object { Cond $_ }) -Warchief $chief -Now (At 0) -Settings $settings -Shadow
    Check (@($hushFlood.entries | Where-Object { $_.kind -ceq "would-tell" }).Count -eq 6 -and @($hushFlood.entries | Where-Object { $_.kind -ceq "tell-suppressed" }).Count -eq 2) "shadow is held to the same six an hour, so its journal shows what a live run would have sent"
    $nobody = Invoke-HordeWakeTellPass -Conditions @((Cond 1)) -Warchief "" -Now (At 0) -Settings $settings -Post $taking
    Check ((Kinds $nobody) -ceq "tell:unposted" -and $script:mails.Count -eq 0 -and "$($nobody.entries[0].reason)".Contains("no one session is the warchief")) "with no one warchief nothing is posted, and the entry says so"
    $noPost = Invoke-HordeWakeTellPass -Conditions @((Cond 1)) -Warchief $chief -Now (At 0) -Settings $settings
    Check ((Kinds $noPost) -ceq "tell:unposted" -and "$($noPost.entries[0].reason)".Contains("nothing to post through")) "and so does a pass given nothing to post through"
    $script:tries = 0
    $failing = { param($m) $script:tries++; New-HordeUnknown -Reason "the messenger is away" }
    $f1 = Invoke-HordeWakeTellPass -Conditions @((Cond 1)) -Warchief $chief -Now (At 0) -Settings $settings -Post $failing
    Check ((Kinds $f1) -ceq "tell:unknown" -and "$($f1.entries[0].reason)" -ceq "gave-up: the messenger is away" -and @($f1.told.Values)[0].state -ceq "failed") "a post that could not say is journaled unknown with its reason, and is not marked told"
    $f2 = Invoke-HordeWakeTellPass -Conditions @((Cond 1)) -Warchief $chief -Now (At 100) -Settings $settings -Post $failing -Told $f1.told
    Check (@($f2.entries).Count -eq 0 -and $script:tries -eq 1) "it is not tried again at once"
    $f3 = Invoke-HordeWakeTellPass -Conditions @((Cond 1)) -Warchief $chief -Now (At 300) -Settings $settings -Post $taking -Told $f2.told
    Check ((Kinds $f3) -ceq "tell:posted" -and @($f3.told.Values)[0].state -ceq "told") "after five minutes it is tried again, and told"
    $f4 = Invoke-HordeWakeTellPass -Conditions @((Cond 1)) -Warchief $chief -Now (At 0) -Settings $settings -Post { param($m) throw "the wire fell out" }
    Check ((Kinds $f4) -ceq "tell:unknown" -and @($f4.told.Values)[0].state -ceq "failed") "a poster that throws is a post that failed, never a throw of the pass"
    $f5 = Invoke-HordeWakeTellPass -Conditions @((Cond 1)) -Warchief $chief -Now (At 0) -Settings $settings -Post { param($m) "yes" }
    Check ((Kinds $f5) -ceq "tell:unknown") "and a poster that answers with something that is not an answer told nobody"

    Write-Host ""
    Write-Host "--- the poster: through the messenger port, as the wake watcher ---" -ForegroundColor Cyan

    $inProcess = Get-HordeMessenger -Name "memory"
    $watch = & (Join-Path $root "messengers\memory\test\Fixture.ps1") -Root $root
    $box = & $watch.New
    try {
        $through = { param($m) Send-HordeWakeTell -Mail $m -Settings $settings -Messenger $inProcess -HordeHome $pinned.home }
        $sent = Invoke-HordeWakeTellPass -Conditions @((Cond 1)) -Warchief $chief -Now (At 0) -Settings $settings -Post $through
        $seen = & $watch.Observe $box $idA
        Check ((Kinds $sent) -ceq "tell:posted" -and $seen.records -eq 1 -and "$(@($seen.bodies)[0])" -ceq "AUTOMATED, from the wake watcher: session 1 needs a look" -and @($seen.typed).Count -eq 0) "a tell is one record in the messenger's store, holding its text, and nothing was typed"
        $null = Invoke-HordeWakeTellPass -Conditions @((Cond 1)) -Warchief $chief -Now (At 0) -Settings $settings -Post $through
        Check ((& $watch.Observe $box $idA).records -eq 1) "a pass that lost what it had told posts the same id, and the messenger keeps it as the one message it has"
        $alone = Send-HordeWakeTell -Mail ([pscustomobject]@{ to = $chief; messageId = "0d000000-0000-4000-8000-0000000000ba"; body = "x" }) -Settings $settings -HordeHome $pinned.home
        Check ($alone.state -ceq "unknown" -and "$($alone.reason)".Contains("no messenger to post through")) "left to find a messenger itself, the sender does not pick the in-process one"
        $script:got = $null
        $catcher = Register-HordeMessenger -Folder (Join-Path $root "test\fixtures\messenger\caps\fixture-good") -Post { param($m) $script:got = $m; New-HordeKnown -Value ([pscustomobject]@{ messageId = $m.messageId; stage = "accepted"; at = [datetime]::UtcNow }) } -Status { param($id) New-HordeAbsent -Note "the fixture knows nothing" }
        $worn = Send-HordeWakeTell -Mail ([pscustomobject]@{ to = $chief; messageId = "0d000000-0000-4000-8000-0000000000bb"; body = "x" }) -Settings $settings -Messenger $catcher -HordeHome $pinned.home
        Check ($worn.state -ceq "known" -and $null -ne $script:got -and "$($script:got.from.sessionId)" -ceq "horde-wake-watcher" -and "$($script:got.from.label)" -ceq "WW" -and "$($script:got.sessionId)" -ceq $chief) "the mail is from horde-wake-watcher, wearing WW, to the warchief"
    } finally { & $watch.Remove $box }

    Write-Host ""
    Write-Host "--- the file ---" -ForegroundColor Cyan

    $h = Join-Path $pinned.home ("tell-" + [guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $h | Out-Null
    Check ((Read-HordeWakeTellState -Mode "shadow" -HordeHome $h).state -ceq "absent") "with nothing saved, nothing was told"
    Save-HordeWakeTellState -Told $flood.told -Mode "shadow" -HordeHome $h
    $back = Read-HordeWakeTellState -Mode "shadow" -HordeHome $h
    Check ($back.state -ceq "known" -and $back.value.told.Count -eq 8 -and $back.value.told[$idA].state -ceq "told" -and $back.value.told[$idA].at -eq (At 0) -and @($back.value.told.Values | Where-Object { $_.state -ceq "suppressed" }).Count -eq 2) "what was told and what was suppressed are read back as they were saved"
    Check ((Test-Path -LiteralPath (Join-Path $h "wake\tells-shadow.json")) -and (Read-HordeWakeTellState -Mode "live" -HordeHome $h).state -ceq "absent" -and (Read-HordeWakeTellState -Mode "proof" -HordeHome $h).state -ceq "absent") "it is the shadow run's own file: a live run and a proof run read nothing told from it"
    Set-Content -LiteralPath (Join-Path $h "wake\tells-shadow.json") -Value "{ not json" -Encoding ASCII
    Check ((Read-HordeWakeTellState -Mode "shadow" -HordeHome $h).state -ceq "unknown") "a file that cannot be read is unknown, never nothing told"
} finally {
    Exit-HordeTestPinnedHome -State $pinned
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}

Complete-HordeSuite -Success "the warchief is told once of each thing the watcher cannot mend, six an hour at most, in words that say a machine wrote them, and in shadow not at all"
