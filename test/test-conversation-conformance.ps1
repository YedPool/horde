# DOES EVERY CONVERSATION ADAPTER KEEP THE PORT'S CONTRACT, AND SHOW EACH CAPABILITY IT CLAIMS?
#
# Relay design 2026-10-09, Q2 and PR plan item 9. Generated from each adapter's conversation.json, as
# the relay, transport and messenger conformance suites are from theirs: this suite names no harness.
# It loads every agents/<name>/Conversation.ps1 that has a test/ConversationFixture.ps1 beside it, and
# the memory source (test/lib/MemoryConversation.ps1) as a second subject, so the cases are shown not to
# depend on one harness's file format. Each is held to two things.
#
# I. THE CONTRACT EVERY ADAPTER KEEPS, whatever it declares: the Thrall is found; an empty conversation
#    reads empty; added turns come back in order, with their roles and their words, and nothing of the
#    harness's own noise (the fixture adds its harness's tool calls, side conversations and bookkeeping
#    around every turn); a read resumes from its cursor and a read at the end returns nothing and keeps
#    the cursor; a bounded read gives at most its batch and, read on to the end, exactly the whole; a
#    secret in a user turn and in an assistant turn is hidden by the port; multi-line and non-ASCII words
#    come back exactly; a turn half written is not read until it is whole, and then once; the harness's
#    clear is a reset to the new session, and the session it ended is still found by its id, its last
#    words after the cursor read to its end (the chat channel's drain); a rewritten history is a reset too.
# II. EACH CAPABILITY OF THE CLOSED LIST: a "yes" is DEMONSTRATED by its case below or the suite fails;
#    any other word must make a caller that requires it refuse the adapter, by name; a hazard that is not
#    "no" must make a caller that refuses it refuse the adapter. A capability added to the list with no
#    case here fails the suite.
#
# THE FIXTURE. agents/<name>/test/ConversationFixture.ps1, run with -Root, returns one object of script
# blocks, every one acting only on what New made:
#   New     ()                 -> a state: .options for Find-HordeConversationSource, .fleet its horde
#   Add     param($State, $Turns) - append turns, each { role; text }, in the harness's own format, with
#                                 its noise around them
#   Tear    param($State, $Turn)  -> $true after writing the first part of one turn's record and no more;
#                                 $false for a source that cannot be half written (then Mend is not called)
#   Mend    param($State)         - write the rest of the torn record
#   Clear   param($State)         - the harness's clear: a new session, which the Thrall's record now names
#   Rotate  param($State, $Turns) - the same session's history rewritten to hold only $Turns
#   Remove  param($State)         - removes everything New made
# A fixture writes nothing outside the temp folder and what it made. It is dot-sourced, so helpers it
# loads for its blocks stay defined when they run. Every word it is given here is
# made up in this file; no transcript is copied anywhere.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "conversations\Port.ps1")
. (Join-Path $root "core\Schema.ps1")
foreach ($f in @(Get-HordeConversationAdapterFiles)) { . $f }
. (Join-Path $root "test\lib\MemoryConversation.ps1")

$mark = Get-HordeSecretMark
$turnSchema = Get-HordeSchema -Name "conversation-turn.v1"

# THE SUBJECTS: every adapter under agents/ with a fixture, and the memory source.
$subjects = New-Object System.Collections.ArrayList
foreach ($f in @(Get-HordeConversationAdapterFiles)) {
    $folder = Split-Path -Parent $f
    $fx = Join-Path $folder "test\ConversationFixture.ps1"
    $name = Split-Path -Leaf $folder
    Check (Test-Path -LiteralPath $fx -PathType Leaf) ("adapter " + $name + " has a conformance fixture, test/ConversationFixture.ps1")
    if (Test-Path -LiteralPath $fx -PathType Leaf) { [void]$subjects.Add([pscustomobject]@{ name = $name; fixture = (. $fx -Root $root) }) }
}
Check ($subjects.Count -ge 1) ("CONTROL: at least one harness adapter is under test (" + (@($subjects | ForEach-Object { $_.name }) -join ", ") + ")")
[void]$subjects.Add([pscustomobject]@{ name = "memory"; fixture = (& (Join-Path $root "test\fixtures\conversations\memory\ConversationFixture.ps1") -Root $root) })

function Find-Subject {
    param($Subject, $State)
    $a = Find-HordeConversationSource -Fleet $State.fleet -Vendor $Subject.name -Require @() -Refuse @() -Options $State.options
    if ($a.state -cne "known") { throw ("adapter " + $Subject.name + " did not locate the fixture's Thrall: " + $a.state + " " + $a.reason) }
    return $a.value
}
function Read-All {
    # Every turn from -Cursor on, in batches of -Batch, and the last cursor.
    param($Source, $Cursor, [int]$Batch = 200)
    $turns = New-Object System.Collections.ArrayList
    $resets = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt 1000; $i++) {
        $r = Read-HordeConversationTurns -Source $Source -Cursor $Cursor -MaxTurns $Batch
        if ($r.state -cne "known") { throw ("a read failed: " + $r.reason) }
        if (@($r.value.turns).Count -gt $Batch) { throw ("a read of " + $Batch + " gave " + @($r.value.turns).Count) }
        foreach ($t in @($r.value.turns)) { [void]$turns.Add($t) }
        [void]$resets.Add($r.value.reset)
        $Cursor = $r.value.next
        if (-not $r.value.more) { break }
    }
    return [pscustomobject]@{ turns = @($turns); cursor = $Cursor; resets = @($resets) }
}
function Sig { param($Turns) return (@($Turns | ForEach-Object { $_.role + ":" + $_.text }) -join "|") }
function Ids { param($Turns) return (@($Turns | ForEach-Object { $_.turnId + "=" + $_.text }) -join "|") }

$hebrew = "" + [char]0x05E9 + [char]0x05DC + [char]0x05D5 + [char]0x05DD
$emoji = [char]::ConvertFromUtf32(0x1F44B)
$first = @(
    [pscustomobject]@{ role = "user"; text = "Please look at the build." },
    [pscustomobject]@{ role = "assistant"; text = "Looking now.`nThe build is green on the second line." },
    [pscustomobject]@{ role = "user"; text = ("Thanks " + $hebrew + " " + $emoji) }
)
$second = @(
    [pscustomobject]@{ role = "assistant"; text = "Two more things follow." },
    [pscustomobject]@{ role = "user"; text = "Go on." }
)

# Every capability of the closed list must have a case. Each gets the subject, a source with turns
# already read once (all), and returns $true when the capability was shown.
$cases = [ordered]@{
    "incremental" = {
        param($S, $State, $Src, $All)
        $S.fixture.Add.Invoke($State, @([pscustomobject]@{ role = "user"; text = "incremental probe" }))
        $r = Read-HordeConversationTurns -Source $Src -Cursor $All.cursor
        $at = Read-HordeConversationTurns -Source $Src -Cursor $r.value.next
        return ($r.state -ceq "known" -and (Sig $r.value.turns) -ceq "user:incremental probe" -and @($at.value.turns).Count -eq 0)
    }
    "stableTurnIds" = {
        param($S, $State, $Src, $All)
        $again = Read-All -Source $Src -Cursor $null
        $one = Read-All -Source $Src -Cursor $null -Batch 1
        $prefix = (Ids $All.turns)
        return ((Ids $again.turns).StartsWith($prefix) -and (Ids $one.turns) -ceq (Ids $again.turns))
    }
    "timestamps" = {
        param($S, $State, $Src, $All)
        return (@($All.turns).Count -gt 0 -and @($All.turns | Where-Object { $null -eq $_.PSObject.Properties["time"] }).Count -eq 0)
    }
    "roles" = {
        param($S, $State, $Src, $All)
        $users = @($All.turns | Where-Object { $_.role -ceq "user" }).Count
        $assts = @($All.turns | Where-Object { $_.role -ceq "assistant" }).Count
        return ($users -ge 1 -and $assts -ge 1)
    }
    # A HAZARD'S "no" is what is shown: a hazard's "yes" is a warning, not a feature, and the case only
    # passes it through (the -Refuse check in II holds every word that is not no).
    "partialTurns" = {
        param($S, $State, $Src, $All)
        $sup = Get-HordeConversationSupport -Adapter (Get-HordeConversationAdapter -Name $S.name) -Capability "partialTurns"
        if ($sup -cne "no") { return $true }
        $seen = @{}
        $c = $null
        for ($i = 0; $i -lt 1000; $i++) {
            $r = Read-HordeConversationTurns -Source $Src -Cursor $c -MaxTurns 1
            foreach ($t in @($r.value.turns)) { if ($seen.ContainsKey($t.turnId)) { return $false }; $seen[$t.turnId] = 1 }
            $c = $r.value.next
            if (-not $r.value.more) { break }
        }
        return ($seen.Count -ge @($All.turns).Count)
    }
    "mutableHistory" = {
        param($S, $State, $Src, $All)
        $sup = Get-HordeConversationSupport -Adapter (Get-HordeConversationAdapter -Name $S.name) -Capability "mutableHistory"
        if ($sup -cne "no") { return $true }
        $S.fixture.Add.Invoke($State, @([pscustomobject]@{ role = "assistant"; text = "history probe" }))
        $later = Read-All -Source $Src -Cursor $null
        return ((Ids $later.turns).StartsWith((Ids $All.turns)))
    }
}
foreach ($cap in @(Get-HordeConversationCapabilityNames)) { Check ($cases.Contains($cap)) ("the capability " + $cap + " has a conformance case") }

foreach ($S in $subjects) {
    $adapter = Get-HordeConversationAdapter -Name $S.name
    Write-Host ""
    Write-Host ("=== " + $S.name + " ===") -ForegroundColor Cyan

    Write-Host ""
    Write-Host ("--- " + $S.name + ": I. the contract ---") -ForegroundColor Cyan
    $State = & $S.fixture.New
    try {
        $src = Find-Subject $S $State
        Check ($src.vendor -ceq $S.name -and $src.fleet -ceq $State.fleet) ($S.name + ": the Thrall is found, for its horde")
        $r = Read-HordeConversationTurns -Source $src -Cursor $null
        Check ($r.state -ceq "known" -and @($r.value.turns).Count -eq 0 -and -not $r.value.more) ($S.name + ": an empty conversation reads empty")
        $S.fixture.Add.Invoke($State, $first)
        $all = Read-All -Source $src -Cursor $null
        Check ((Sig $all.turns) -ceq (Sig $first)) ($S.name + ": three turns come back in order, with their roles and their exact words, multi-line and non-ASCII included, and no noise")
        Check (@($all.turns | Where-Object { @(Test-HordeSchema -Value $_ -Schema $turnSchema).Count -gt 0 }).Count -eq 0) ($S.name + ": every turn passes schema/conversation-turn.v1")
        Check (@($all.turns | Where-Object { $_.source.vendor -cne $S.name -or $_.source.session -cne $src.session -or $_.source.fleet -cne $State.fleet }).Count -eq 0) ($S.name + ": every turn names its vendor, session and horde")
        $S.fixture.Add.Invoke($State, $second)
        $more = Read-HordeConversationTurns -Source $src -Cursor $all.cursor
        Check ($more.state -ceq "known" -and (Sig $more.value.turns) -ceq (Sig $second)) ($S.name + ": resumed from its cursor, only the two turns added after it")
        $still = Read-HordeConversationTurns -Source $src -Cursor $more.value.next
        Check ($still.state -ceq "known" -and @($still.value.turns).Count -eq 0 -and $still.value.next.position -ceq $more.value.next.position) ($S.name + ": at the end, nothing, and the cursor kept")
        $whole = Read-All -Source $src -Cursor $null
        $pairs = Read-All -Source $src -Cursor $null -Batch 2
        Check ((Sig $whole.turns) -ceq (Sig ($first + $second)) -and (Ids $pairs.turns) -ceq (Ids $whole.turns)) ($S.name + ": read two at a time to the end, exactly the whole")
        $two = Read-HordeConversationTurns -Source $src -Cursor $null -MaxTurns 2
        Check (@($two.value.turns).Count -eq 2 -and $two.value.more) ($S.name + ": a batch of two gives two, and says there is more")

        $secretUser = "the token is " + ("gh" + "p_" + ("Zq9" * 12)) + " ok"
        $secretAsst = "set password=" + "s3cretWord77" + " and go"
        $S.fixture.Add.Invoke($State, @([pscustomobject]@{ role = "user"; text = $secretUser }, [pscustomobject]@{ role = "assistant"; text = $secretAsst }))
        $sec = Read-HordeConversationTurns -Source $src -Cursor $still.value.next
        $blob = $sec.value | ConvertTo-Json -Depth 8 -Compress
        Check ($sec.state -ceq "known" -and @($sec.value.turns).Count -eq 2 -and -not $blob.Contains("Zq9Zq9") -and -not $blob.Contains("s3cretWord77")) ($S.name + ": a secret in a user turn and in an assistant turn is nowhere in the answer")
        Check ($sec.value.turns[0].text -ceq ("the token is " + $mark + " ok") -and $sec.value.turns[1].text.Contains($mark)) ($S.name + ": each is replaced by the marker, the words around it kept")
        $cur = $sec.value.next

        $torn = $S.fixture.Tear.Invoke($State, [pscustomobject]@{ role = "user"; text = "a turn written in two parts" })
        if (@($torn)[0] -eq $true) {
            $half = Read-HordeConversationTurns -Source $src -Cursor $cur
            Check ($half.state -ceq "known" -and @($half.value.turns).Count -eq 0) ($S.name + ": a turn half written is not read")
            $S.fixture.Mend.Invoke($State)
            $whole2 = Read-HordeConversationTurns -Source $src -Cursor $half.value.next
            $after = Read-HordeConversationTurns -Source $src -Cursor $whole2.value.next
            Check ((Sig $whole2.value.turns) -ceq "user:a turn written in two parts" -and @($after.value.turns).Count -eq 0) ($S.name + ": once whole, it is read, and only once")
            $cur = $after.value.next
        } else { Write-Host ("  [NOTE] " + $S.name + ": its fixture cannot half write a turn; the torn-record case does not apply") -ForegroundColor DarkGray }

        # The Thrall's last words before the clear, written after the cursor: the drain must find them.
        $S.fixture.Add.Invoke($State, @([pscustomobject]@{ role = "assistant"; text = "the last words before the clear" }))
        $S.fixture.Clear.Invoke($State)
        $S.fixture.Add.Invoke($State, @([pscustomobject]@{ role = "user"; text = "after the clear" }))
        $src2 = Find-Subject $S $State
        Check ($src2.session -cne $src.session) ($S.name + ": CONTROL: after the clear, the Thrall's session is a new one")
        $old = Find-HordeConversationSource -Fleet $State.fleet -Vendor $S.name -Session $src.session -Require @() -Refuse @() -Options $State.options
        Check ($old.state -ceq "known" -and $old.value.session -ceq $src.session) ($S.name + ": the session the clear ended is still found by its id (" + $old.state + ")")
        if ($old.state -ceq "known") {
            $tail = Read-HordeConversationTurns -Source $old.value -Cursor $cur
            Check ($tail.state -ceq "known" -and $tail.value.reset -ceq "none" -and (Sig $tail.value.turns) -ceq "assistant:the last words before the clear" -and -not $tail.value.more) ($S.name + ": and its tail after the cursor is read to its end, the new session's words not among it")
        }
        $none = Find-HordeConversationSource -Fleet $State.fleet -Vendor $S.name -Session "no-such-session-1" -Require @() -Refuse @() -Options $State.options
        Check ($none.state -ceq "absent") ($S.name + ": a session id the Thrall never had is absent (" + $none.state + ")")
        $x = Read-HordeConversationTurns -Source $src2 -Cursor $cur
        Check ($x.state -ceq "known" -and $x.value.reset -ceq "session" -and (Sig $x.value.turns) -ceq "user:after the clear") ($S.name + ": the old cursor reads the new session from its start, as a reset")
        $S.fixture.Rotate.Invoke($State, @([pscustomobject]@{ role = "user"; text = "a rewritten history" }, [pscustomobject]@{ role = "assistant"; text = "with a reply in it, longer than what stood before it" }))
        $y = Read-HordeConversationTurns -Source $src2 -Cursor $x.value.next
        Check ($y.state -ceq "known" -and $y.value.reset -ceq "rotated" -and (Sig $y.value.turns) -ceq "user:a rewritten history|assistant:with a reply in it, longer than what stood before it") ($S.name + ": a rewritten history is read from its start, as a rotation")
    } finally { & $S.fixture.Remove $State }

    Write-Host ""
    Write-Host ("--- " + $S.name + ": II. every capability it claims, shown ---") -ForegroundColor Cyan
    foreach ($cap in @(Get-HordeConversationCapabilityNames)) {
        $sup = Get-HordeConversationSupport -Adapter $adapter -Capability $cap
        $hazard = @(Get-HordeConversationHazardNames) -ccontains $cap
        if ($hazard) {
            $refused = Resolve-HordeConversationAdapter -Name $S.name -Require @() -Refuse @($cap)
            if ($sup -ceq "no") { Check ($refused.state -ceq "known") ($S.name + ": hazard " + $cap + " is no, so a caller that refuses it may use this adapter") }
            else { Check ($refused.state -ceq "unknown" -and $refused.reason -like ("*" + $S.name + "*")) ($S.name + ": hazard " + $cap + " is " + $sup + ", so a caller that refuses it is refused, by name") }
        } elseif ($sup -cne "yes") {
            $r = Resolve-HordeConversationAdapter -Name $S.name -Require @($cap) -Refuse @()
            Check ($r.state -ceq "unknown" -and $r.reason -like ("*" + $S.name + "*")) ($S.name + ": " + $cap + " is " + $sup + ", so a caller that requires it is refused, by name")
            continue
        }
        if (-not $hazard -or $sup -ceq "no") {
            $State = & $S.fixture.New
            try {
                $S.fixture.Add.Invoke($State, ($first + $second))
                $src = Find-Subject $S $State
                $all = Read-All -Source $src -Cursor $null
                $shown = & $cases[$cap] $S $State $src $all
                Check ($shown -eq $true) ($S.name + ": " + $cap + " " + $sup + " is shown by its case")
            } finally { & $S.fixture.Remove $State }
        }
    }
}

Complete-HordeSuite -Success "every conversation adapter keeps the contract and shows every capability it claims"
