# DOES THE RELAY JOURNAL CALL AN ENVELOPE FRESH EXACTLY ONCE, AND REFUSE RATHER THAN FORGET?
#
# relay/Journal.ps1 in one process; test/test-relay-journal-race.ps1 races real processes and kills
# real writers. Every journal here is a fresh home under %TEMP% that this suite made and removes
# (CONTRIBUTING 9). Sections:
#   I.    a folder that is not a journal is unknown, never empty; Initialize makes one once
#   II.   fresh, then a replay; the verdict is the one relay/Envelope.ps1 opens on, and only the first
#   III.  the sequence: out of order, a seq reused with another nonce, too far ahead, gaps reported
#   IV.   the clock: ahead of this machine, before the journal was made; a refusal records nothing
#   V.    damage is refused and never reset: a record cut short, one that lies about itself, a stray
#         file, a folder, a damaged marker; and the stream takes envelopes again once repaired
#   VI.   a write that fails at each step: before the move, an unconfirmed move, a system with no
#         durable move; leftovers of dead writers swept, a held one never
#   VII.  sending: the next seq, a seq taken twice, text that is not an envelope
#   VIII. one writer: a stream whose lock is held answers busy, and a refused settings file refuses
# Run under powershell.exe and pwsh alike.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relay\Journal.ps1")
. (Join-Path $root "relay\Keys.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$machine = New-HordeRelayP256Key -Use "ecdsa"
$machinePub = ConvertTo-HordeRelayP256Public -Key $machine
$machineId = Get-HordeRelayKeyId -Public $machinePub
$other = New-HordeRelayP256Key -Use "ecdsa"
$otherPub = ConvertTo-HordeRelayP256Public -Key $other
$otherId = Get-HordeRelayKeyId -Public $otherPub
$phone = New-HordeRelayP256Key -Use "ecdh"
$phonePub = ConvertTo-HordeRelayP256Public -Key $phone
$senders = @{ $machineId = (New-HordeRelaySender -Public $machinePub -Proof "es256"); $otherId = (New-HordeRelaySender -Public $otherPub -Proof "es256") }
$agreeKeys = @{ (Get-HordeRelayKeyId -Public $phonePub) = $phone }
# CAN THIS RUNTIME READ A SETTINGS FILE AT ALL? On 2026-10-09 core/ModuleSettings.ps1 refused every whole
# number under PowerShell 7, whose ConvertFrom-Json reads 5 as an Int64 where 5.1 reads an Int32 (its own
# suite, test/test-module-settings.ps1, fails there the same way). That is core's to mend, in its own pull
# request. Until it is, the checks that need a setting other than its default are SKIPPED under that
# runtime, said so, and the suite exits 3 - a partial run, never 0 (test/lib/Suite.ps1).
$probe = Read-HordeModuleSettingsText -Declaration $script:HordeRelayJournalSettings -Text '{"schemaVersion":1,"settings":{"seqWindow":5}}'
$settingsRead = ($probe.state -ceq "read")
$script:skipped = 0
function Skip { param([string]$What) $script:skipped++; Write-Host ("  [SKIP] " + $What + ": this runtime's settings reader refuses whole numbers (core/ModuleSettings.ps1)") -ForegroundColor Yellow }
$work = Join-Path $env:TEMP ("horde-relay-journal-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$script:homeCount = 0

function New-Home {
    # A fresh home with an initialized journal; its path.
    param([switch]$Bare)
    $script:homeCount++
    $h = Join-Path $work ("home" + $script:homeCount)
    New-Item -ItemType Directory -Path $h | Out-Null
    if (-not $Bare) { $null = Initialize-HordeRelayJournal -HordeHome $h }
    return $h
}
function Seal {
    # A read envelope from -Signer (the machine by default) on -Channel with -Seq, sent at -At.
    param([long]$Seq, [string]$Channel = "decisions", $Signer = $machine, $At = $null, [string]$Body = "yes")
    $t = New-HordeRelayEnvelope -Kind "answer" -Channel $Channel -Seq $Seq -Body ($utf8.GetBytes($Body)) -Recipients @(, $phonePub) -Signer $Signer -Now $At
    return (Read-HordeRelayEnvelope -Text $t).value
}
function SealText {
    param([long]$Seq, [string]$Channel = "decisions")
    return (New-HordeRelayEnvelope -Kind "answer" -Channel $Channel -Seq $Seq -Body ($utf8.GetBytes("out")) -Recipients @(, $phonePub) -Signer $machine)
}
$phoneId = Get-HordeRelayKeyId -Public $phonePub
function Receive {
    # As this machine (the phone's agree key) would: expecting the envelope's own channel and the kind
    # "answer" unless told otherwise.
    param($Envelope, [string]$HordeHome, $Now = $null, [string[]]$Mine = @($phoneId), [string]$Channel = "", [string]$Kind = "answer")
    $ch = $(if ($Channel -ceq "") { $Envelope.header.channel } else { $Channel })
    return (Register-HordeRelayJournalReceived -Envelope $Envelope -Senders $senders -RecipientKeyIds $Mine -Channel $ch -Kind $Kind -HordeHome $HordeHome -Now $Now)
}
function IsFresh { param($V) return [bool]($V.state -ceq "known" -and $V.value.fresh -is [bool] -and $V.value.fresh) }
function IsRefused { param($V, [string]$Like) return [bool]($V.state -ceq "known" -and $V.value.fresh -is [bool] -and -not $V.value.fresh -and $V.value.why.Contains($Like)) }
function IsUnknown { param($V, [string]$Like) return [bool]($V.state -ceq "unknown" -and $V.reason.Contains($Like)) }
function StreamDir { param([string]$HordeHome, [string]$Dir = "in", [string]$From = $machineId, [string]$Channel = "decisions") return [System.IO.Path]::Combine($HordeHome, "relay", "journal", $Dir, ("s-" + $From), ("c-" + $Channel)) }
function Names { param([string]$Dir) if (-not (Test-Path -LiteralPath $Dir)) { return "" }; return (@(Get-ChildItem -LiteralPath $Dir -Force | Sort-Object Name | ForEach-Object { $_.Name -creplace '\Awriting-[0-9a-f]{32}\.part\z', 'writing-<id>.part' }) -join ",") }
function RecName { param([long]$Seq) return ($Seq.ToString("D16") + ".rec") }
function Open-With {
    param($Envelope, $Verdict)
    return (Unprotect-HordeRelayEnvelope -Envelope $Envelope -Senders $senders -RecipientKeys $agreeKeys -Replay $Verdict -Channel $Envelope.header.channel -Kind "answer")
}
function Write-Settings {
    param([string]$HordeHome, [string]$Json)
    New-Item -ItemType Directory -Force -Path (Join-Path $HordeHome "settings") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $HordeHome "settings\relay-journal.json"), $Json, $utf8)
}

try {
    Write-Host ""
    Write-Host "--- I. not a journal is unknown, never empty ---" -ForegroundColor Cyan
    $h = New-Home -Bare
    $e1 = Seal -Seq 1
    $v = Receive -Envelope $e1 -HordeHome $h
    Check (IsUnknown $v "is not a relay journal") ("a home with no journal answers unknown, not fresh (" + $v.reason + ")")
    Check (-not (Test-Path -LiteralPath (Join-Path $h "relay"))) "and nothing was created by asking"
    $i1 = Initialize-HordeRelayJournal -HordeHome $h
    Check ($i1.state -ceq "known" -and $i1.value.createdAt -gt 0) "Initialize makes a journal and says when"
    $i2 = Initialize-HordeRelayJournal -HordeHome $h
    Check ($i2.state -ceq "known" -and $i2.value.createdAt -eq $i1.value.createdAt) "Initialize again answers with the same journal, its birth unchanged"
    Check ((Get-Content -LiteralPath (Join-Path $h "relay\journal\journal.json") -Raw) -cmatch '\A\{"v":1,"kind":"horde-relay-journal","createdAt":[0-9]+\}\z') "the marker is the canonical one line"
    $v = Receive -Envelope $e1 -HordeHome $h
    Check (IsFresh $v) "CONTROL: once made, the same envelope is fresh"
    # A journal that lost its marker but kept its streams.
    Remove-Item -LiteralPath (Join-Path $h "relay\journal\journal.json")
    $v = Receive -Envelope (Seal -Seq 2) -HordeHome $h
    Check (IsUnknown $v "is not a relay journal") "a journal whose marker is gone is unknown"
    $i3 = Initialize-HordeRelayJournal -HordeHome $h
    Check (IsUnknown $i3 "marker was lost") ("and Initialize does not write a new marker over its streams (" + $i3.reason + ")")
    Check (-not (Test-Path -LiteralPath (Join-Path $h "relay\journal\journal.json"))) "and no marker was written"
    $h = New-Home
    [System.IO.File]::WriteAllText((Join-Path $h "relay\journal\journal.json"), '{"v":2,"kind":"horde-relay-journal","createdAt":1}', $utf8)
    Check (IsUnknown (Receive -Envelope $e1 -HordeHome $h) "damaged or of another version") "a marker of another version is unknown"
    Check (IsUnknown (Initialize-HordeRelayJournal -HordeHome $h) "damaged or of another version") "and Initialize refuses it rather than replace it"
    Check (IsUnknown (Initialize-HordeRelayJournal -HordeHome "relative\home") "has no folder") "a relative home is refused"

    Write-Host ""
    Write-Host "--- II. fresh once, then a replay; the verdict opens only the first time ---" -ForegroundColor Cyan
    $h = New-Home
    $e = Seal -Seq 7 -Body "merge it"
    $first = Receive -Envelope $e -HordeHome $h
    Check (IsFresh $first) "the first time, fresh"
    Check ($first.value.key -ceq (Get-HordeRelayReplayKey -Header $e.header)) "the verdict names this envelope's replay key"
    Check ($first.value.fresh -is [bool] -and $first.value.direction -ceq "in" -and $first.value.why -ceq "") "fresh is the boolean true, inbound, with no refusal"
    $u = Open-With -Envelope $e -Verdict $first
    Check ($u.ok -and $utf8.GetString($u.value) -ceq "merge it") ("relay/Envelope.ps1 opens on that verdict (" + $u.reason + ")")
    $again = Receive -Envelope $e -HordeHome $h
    Check (IsRefused $again "a replay") ("the second time, a replay (" + $again.value.why + ")")
    $u = Open-With -Envelope $e -Verdict $again
    Check (-not $u.ok -and $u.reason.Contains("replay is refused")) "and relay/Envelope.ps1 does not open on it"
    $rec = [System.IO.File]::ReadAllText((Join-Path (StreamDir $h) (RecName 7)))
    $cut = $rec.IndexOf("`n")
    $wire = '{"header":' + $e.headerText + ',"recipients":' + $e.recipientsText + ',"ct":"' + $e.ctText + '","sig":' + (ConvertTo-HordeRelaySigText -Sig $e.sig) + '}'
    Check ($cut -gt 0 -and $rec.Substring($cut + 1) -ceq $wire) "the record holds the envelope exactly as it was signed"
    Check ((Read-HordeRelayEnvelope -Text $rec.Substring($cut + 1)).ok) "and it reads back as a canonical envelope: the evidence is kept whole"
    Check ($rec.Substring(0, $cut).Contains('"seq":7,"nonce":"' + $e.header.nonce + '"')) "its metadata names the seq and the nonce"
    $forger = New-HordeRelayP256Key -Use "ecdsa"
    $fe = Seal -Seq 8 -Signer $forger
    $v = Receive -Envelope $fe -HordeHome $h
    Check (IsUnknown $v "not verified") ("an envelope from an untrusted signer is not judged (" + $v.reason + ")")
    # Review of 6f7e8c1, finding 2: an envelope addressed only to another machine was recorded, and took
    # the stream's seq, so this machine's own lower seq arriving after it was refused as out of order.
    $elsewhere = New-HordeRelayEnvelope -Kind "answer" -Channel "decisions" -Seq 60 -Body ($utf8.GetBytes("for B")) -Recipients @(, (ConvertTo-HordeRelayP256Public -Key (New-HordeRelayP256Key -Use "ecdh"))) -Signer $machine
    $v = Receive -Envelope (Read-HordeRelayEnvelope -Text $elsewhere).value -HordeHome $h
    Check (IsUnknown $v "not addressed to this machine") ("an envelope addressed only to another machine is not judged (" + $v.reason + ")")
    Check (-not (Test-Path -LiteralPath (Join-Path (StreamDir $h) (RecName 60)))) "and it is not recorded"
    $v = Receive -Envelope (Seal -Seq 59) -HordeHome $h -Channel "chat"
    Check (IsUnknown $v "is for the channel decisions, not chat") ("an envelope on another channel than the caller expects is not judged (" + $v.reason + ")")
    $v = Receive -Envelope (Seal -Seq 59) -HordeHome $h -Kind "snapshot"
    Check (IsUnknown $v "is of the kind answer, not snapshot") ("an envelope of another kind than the caller expects is not judged (" + $v.reason + ")")
    Check (IsFresh (Receive -Envelope (Seal -Seq 59) -HordeHome $h)) "CONTROL: this machine's own seq 59 is still fresh: nothing above took its place"
    Check (-not (Test-Path -LiteralPath (StreamDir $h -From (Get-HordeRelayKeyId -Public (ConvertTo-HordeRelayP256Public -Key $forger))))) "and nothing of it is recorded"
    $o1 = Receive -Envelope (Seal -Seq 7 -Signer $other) -HordeHome $h
    Check (IsFresh $o1) "the same seq from another sender is its own stream, and fresh"
    $c1 = Receive -Envelope (Seal -Seq 7 -Channel "chat") -HordeHome $h
    Check (IsFresh $c1) "the same seq on another channel is its own stream, and fresh"

    Write-Host ""
    Write-Host "--- II b. a channel named like a Windows device is a stream like any other ---" -ForegroundColor Cyan
    # Review of 6f7e8c1 (finding 1): a channel "con" made the folder in\<from>\con, which Windows
    # PowerShell 5.1's Get-ChildItem reported as not found, so the stream read as empty every time and
    # its sequence, window and damage rules were off: a replay was "another writer", never refused as one.
    $h = New-Home
    foreach ($dev in @("con", "aux", "nul", "prn", "com1", "lpt1")) {
        $d1 = Seal -Seq 5 -Channel $dev
        $v = Receive -Envelope $d1 -HordeHome $h
        Check (IsFresh $v) ("channel " + $dev + ": the first envelope is fresh (" + $v.reason + ")")
        Check (IsRefused (Receive -Envelope $d1 -HordeHome $h) "a replay") ("channel " + $dev + ": the same again is refused as a replay")
        Check (IsRefused (Receive -Envelope (Seal -Seq 3 -Channel $dev) -HordeHome $h) "out of order") ("channel " + $dev + ": a lower seq is out of order")
        Check ((Names (StreamDir $h -Channel $dev)) -ceq ((RecName 5) + ",lock")) ("channel " + $dev + ": its stream folder is c-" + $dev + ", with its one record")
    }
    $missing = Get-HordeRelayJournalStream -Dir (Join-Path $work "no-such-stream") -Direction "in" -From $machineId -Channel "decisions" -MustExist $true
    Check (-not $missing.ok -and $missing.reason.Contains("not found")) ("a stream folder that was just made and lists as not found is damage, not an empty stream (" + $missing.reason + ")")
    $absent = Get-HordeRelayJournalStream -Dir (Join-Path $work "no-such-stream") -Direction "in" -From $machineId -Channel "decisions" -MustExist $false
    Check ($absent.ok -and $absent.last -eq -1) "CONTROL: asked only to read, a stream with no folder is a stream with no record"

    Write-Host ""
    Write-Host "--- III. the sequence only goes up ---" -ForegroundColor Cyan
    $h = New-Home
    $v = Receive -Envelope (Seal -Seq 10) -HordeHome $h
    # Review of 6f7e8c1, findings 3 and 4: a new stream is measured from seq 0, as if its last were 0 -
    # for the window and for the gap - so a first envelope of 2^53-1 cannot end the stream, and the seqs
    # below a first seq of 10 are reported missing, not silently refused when they come.
    Check ((IsFresh $v) -and $v.value.gapBefore -eq 9) ("a new stream's first seq 10 is fresh, and says 9 are missing (" + $v.value.gapBefore + ")")
    $hNew = New-Home
    $v = Receive -Envelope (Seal -Seq 9007199254740991) -HordeHome $hNew
    Check (IsRefused $v "more than the window of 100000") ("a new stream's first seq of 2^53-1 is past the window, measured from 0 (" + $v.value.why + ")")
    $v = Receive -Envelope (Seal -Seq 100001) -HordeHome $hNew
    Check (IsRefused $v "more than the window of 100000") "and so is its first seq of 100001"
    $v = Receive -Envelope (Seal -Seq 100000) -HordeHome $hNew
    Check ((IsFresh $v) -and $v.value.gapBefore -eq 99999) ("while 100000, exactly the window, is fresh, with 99999 missing (" + $v.value.gapBefore + ")")
    $v = Receive -Envelope (Seal -Seq 1 -Channel "chat") -HordeHome $hNew
    Check ((IsFresh $v) -and $v.value.gapBefore -eq 0) "CONTROL: a first seq of 1 has nothing missing"
    $v = Receive -Envelope (Seal -Seq 0 -Channel "zero") -HordeHome $hNew
    Check ((IsFresh $v) -and $v.value.gapBefore -eq 0) "and a first seq of 0 none either"
    $late = Seal -Seq 8
    $v = Receive -Envelope $late -HordeHome $h
    Check (IsRefused $v "out of order") ("seq 8 after seq 10 is refused as out of order (" + $v.value.why + ")")
    $v = Receive -Envelope (Seal -Seq 13) -HordeHome $h
    Check ((IsFresh $v) -and $v.value.gapBefore -eq 2) ("seq 13 after 10 is fresh, and says 2 are missing (" + $v.value.gapBefore + ")")
    $v = Receive -Envelope $late -HordeHome $h
    Check (IsRefused $v "out of order") "seq 8 is still refused: a skipped seq is never taken late"
    $v = Receive -Envelope (Seal -Seq 13) -HordeHome $h
    Check (IsRefused $v "another nonce") ("a new envelope under seq 13, another nonce, is a reuse (" + $v.value.why + ")")
    $v = Receive -Envelope (Seal -Seq 14) -HordeHome $h
    Check ((IsFresh $v) -and $v.value.gapBefore -eq 0) "CONTROL: seq 14 is fresh, with nothing missing"
    if ($settingsRead) {
        Write-Settings -HordeHome $h -Json '{"schemaVersion":1,"settings":{"seqWindow":5}}'
        $v = Receive -Envelope (Seal -Seq 20) -HordeHome $h
        Check (IsRefused $v "more than the window of 5") ("with a window of 5, seq 20 after 14 is refused (" + $v.value.why + ")")
        $v = Receive -Envelope (Seal -Seq 19) -HordeHome $h
        Check ((IsFresh $v) -and $v.value.gapBefore -eq 4) "and seq 19, exactly 5 ahead, is fresh"
        Check ((Names (StreamDir $h)) -ceq (((@(10, 13, 14, 19) | ForEach-Object { RecName $_ }) -join ",") + ",lock")) ("only the fresh envelopes have records (" + (Names (StreamDir $h)) + ")")
    } else { Skip "the sequence window, set to 5" }
    Write-Settings -HordeHome $h -Json '{"schemaVersion":1,"settings":{}}'
    $v = Receive -Envelope (Seal -Seq 200000) -HordeHome $h
    Check (IsRefused $v "more than the window of 100000") ("with the default window, a jump of more than 100000 is refused (" + $v.value.why + ")")

    Write-Host ""
    Write-Host "--- IV. the clock ---" -ForegroundColor Cyan
    $h = New-Home
    $born = (Initialize-HordeRelayJournal -HordeHome $h).value.createdAt
    $epoch = New-Object datetime -ArgumentList 1970, 1, 1, 0, 0, 0, ([System.DateTimeKind]::Utc)
    $bornAt = $epoch.AddMilliseconds($born)
    $ahead = Seal -Seq 1 -At $bornAt.AddMinutes(11)
    $v = Receive -Envelope $ahead -HordeHome $h -Now $bornAt
    Check (IsRefused $v "ahead of this machine's clock") ("sent 11 minutes ahead of this clock: refused (" + $v.value.why + ")")
    Check (-not (Test-Path -LiteralPath (Join-Path (StreamDir $h) (RecName 1)))) "and not recorded"
    $v = Receive -Envelope $ahead -HordeHome $h -Now $bornAt.AddMinutes(2)
    Check (IsFresh $v) "the same envelope, once this clock is 9 minutes behind it, is fresh: a refusal recorded nothing"
    $v = Receive -Envelope (Seal -Seq 2 -At $bornAt.AddMinutes(-11)) -HordeHome $h -Now $bornAt.AddMinutes(2)
    Check (IsRefused $v "before this journal was made") ("sent 11 minutes before the journal was made: refused (" + $v.value.why + ")")
    $v = Receive -Envelope (Seal -Seq 3 -At $bornAt.AddMinutes(-9)) -HordeHome $h -Now $bornAt.AddMinutes(2)
    Check (IsFresh $v) "sent 9 minutes before it was made, inside the skew: fresh"
    $v = Receive -Envelope (Seal -Seq 4 -At $bornAt.AddDays(3)) -HordeHome $h -Now $bornAt.AddDays(10)
    Check (IsFresh $v) "an envelope that waited a week on the relay is fresh: store and forward has no age limit"
    if ($settingsRead) {
        Write-Settings -HordeHome $h -Json '{"schemaVersion":1,"settings":{"clockSkewSeconds":0}}'
        $v = Receive -Envelope (Seal -Seq 5 -At $bornAt.AddDays(10).AddSeconds(5)) -HordeHome $h -Now $bornAt.AddDays(10)
        Check (IsRefused $v "more than 0 s ahead") "with the skew set to 0, five seconds ahead is refused: the setting is read"
    } else { Skip "the clock skew, set to 0" }

    Write-Host ""
    Write-Host "--- V. damage is refused, never reset ---" -ForegroundColor Cyan
    $h = New-Home
    $e21 = Seal -Seq 21
    $null = Receive -Envelope (Seal -Seq 20) -HordeHome $h
    $null = Receive -Envelope $e21 -HordeHome $h
    $null = Receive -Envelope (Seal -Seq 1 -Channel "chat") -HordeHome $h
    $chatSeq = 1
    $sd = StreamDir $h
    $top = Join-Path $sd (RecName 21)
    $whole = [System.IO.File]::ReadAllBytes($top)
    $cases = @(
        @{ what = "the last record cut short"; make = { [System.IO.File]::WriteAllBytes($top, $whole[0..($whole.Length - 40)]) }; want = "cut short" },
        @{ what = "the last record emptied"; make = { [System.IO.File]::WriteAllBytes($top, [byte[]]@()) }; want = "cut short" },
        @{ what = "the last record grown"; make = { [System.IO.File]::WriteAllBytes($top, $whole + [byte[]]@(65)) }; want = "cut short or grown" },
        @{ what = "the last record claiming another seq"; make = { [System.IO.File]::WriteAllText($top, $utf8.GetString($whole).Replace('"seq":21,', '"seq":22,'), $utf8) }; want = "not what its name and folder say" },
        @{ what = "the last record with spacing"; make = { [System.IO.File]::WriteAllText($top, $utf8.GetString($whole).Replace('{"v":1,', '{"v": 1,'), $utf8) }; want = "is damaged" },
        @{ what = "the last record not UTF-8"; make = { [System.IO.File]::WriteAllBytes($top, [byte[]]@(0xC3, 0x28) + $whole) }; want = "could not be read" },
        @{ what = "a stray file in the stream"; make = { [System.IO.File]::WriteAllText((Join-Path $sd "notes.txt"), "x") }; want = "never writes" },
        @{ what = "a record name past 2^53"; make = { [System.IO.File]::WriteAllText((Join-Path $sd "9999999999999999.rec"), "x") }; want = "past the largest" },
        @{ what = "a folder in the stream"; make = { New-Item -ItemType Directory -Path (Join-Path $sd "sub") | Out-Null }; want = "holds a folder" }
    )
    foreach ($c in $cases) {
        & $c.make
        $v = Receive -Envelope (Seal -Seq 30) -HordeHome $h
        Check (IsUnknown $v $c.want) ($c.what + ": a new seq is unknown, not fresh (" + $v.reason + ")")
        Check ($v.reason.Contains("not reset")) ("  and it says the journal is not reset")
        $r = Receive -Envelope $e21 -HordeHome $h
        Check ($r.state -ceq "unknown") "  and seq 21 again is still not fresh"
        $chatSeq++
        Check (IsFresh (Receive -Envelope (Seal -Seq $chatSeq -Channel "chat") -HordeHome $h)) "  CONTROL: another stream of the same journal is unharmed"
        # Repaired by putting back exactly what was there.
        [System.IO.File]::WriteAllBytes($top, $whole)
        foreach ($n in @("notes.txt", "9999999999999999.rec")) { if (Test-Path -LiteralPath (Join-Path $sd $n)) { Remove-Item -LiteralPath (Join-Path $sd $n) } }
        if (Test-Path -LiteralPath (Join-Path $sd "sub")) { Remove-Item -LiteralPath (Join-Path $sd "sub") }
    }
    Check (IsRefused (Receive -Envelope $e21 -HordeHome $h) "a replay") "repaired, seq 21 is a replay again: nothing was forgotten"
    # An older record damaged: the replay of exactly that seq cannot be judged.
    $older = Join-Path $sd (RecName 20)
    $olderWhole = [System.IO.File]::ReadAllBytes($older)
    [System.IO.File]::WriteAllBytes($older, [byte[]]@())
    $v = Receive -Envelope (Seal -Seq 20) -HordeHome $h
    Check (IsUnknown $v "cut short") ("a seq whose own record is damaged is unknown, not judged a reuse (" + $v.reason + ")")
    [System.IO.File]::WriteAllBytes($older, $olderWhole)
    $v = Receive -Envelope (Seal -Seq 30) -HordeHome $h
    Check ((IsFresh $v) -and $v.value.gapBefore -eq 8) "CONTROL: repaired, the stream takes seq 30, eight missing"
    [System.IO.File]::WriteAllText((Join-Path $h "relay\journal\journal.json"), "{}", $utf8)
    Check (IsUnknown (Receive -Envelope (Seal -Seq 31) -HordeHome $h) "damaged or of another version") "a damaged marker makes every stream unknown"

    Write-Host ""
    Write-Host "--- VI. a write that fails, at each step ---" -ForegroundColor Cyan
    $realMove = ${function:Move-HordeFileNewDurable}
    $h = New-Home
    $e5 = Seal -Seq 5
    try {
        function Move-HordeFileNewDurable { param($From, $To, $Open = $null) throw "the disk went away" }
        $v = Receive -Envelope $e5 -HordeHome $h
        Check (IsUnknown $v "could not be recorded") ("a move that throws: unknown (" + $v.reason + ")")
        Check ((Names (StreamDir $h)) -ceq "lock") ("and no record and no temporary file is left (" + (Names (StreamDir $h)) + ")")
        function Move-HordeFileNewDurable { param($From, $To, $Open = $null) $null = & $realMove -From $From -To $To -Open $Open; return "unconfirmed" }
        $v = Receive -Envelope $e5 -HordeHome $h
        Check (IsUnknown $v "flush after the move failed") ("a move whose flush failed: unknown, not fresh (" + $v.reason + ")")
        function Move-HordeFileNewDurable { param($From, $To, $Open = $null) return (& $realMove -From $From -To $To -Open $Open -OsPlatform "Unix") }
        $v = Receive -Envelope (Seal -Seq 6) -HordeHome $h
        Check (IsUnknown $v "no durable move for this system") ("on a system with no durable move: unknown, so nothing opens (" + $v.reason + ")")
    } finally { Set-Item -Path function:script:Move-HordeFileNewDurable -Value $realMove }
    Check ($null -ne (Get-Command Move-HordeFileNewDurable -ErrorAction SilentlyContinue) -and (Get-Command Move-HordeFileNewDurable).ScriptBlock.ToString() -ceq $realMove.ToString()) "CONTROL: the real move is back"
    $v = Receive -Envelope $e5 -HordeHome $h
    Check (IsRefused $v "a replay") "the envelope whose flush failed has its record: it is a replay now, never fresh twice"
    $v = Receive -Envelope (Seal -Seq 6) -HordeHome $h
    Check (IsFresh $v) "CONTROL: with the real move, seq 6 is fresh"
    # Leftovers: one a dead writer left, and one a live writer still holds.
    $sd = StreamDir $h
    $deadTmp = Join-Path $sd ("writing-" + [guid]::NewGuid().ToString("N") + ".part")
    $liveTmp = Join-Path $sd ("writing-" + [guid]::NewGuid().ToString("N") + ".part")
    [System.IO.File]::WriteAllText($deadTmp, "half a rec")
    $held = New-Object System.IO.FileStream -ArgumentList $liveTmp, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::Delete)
    try {
        $v = Receive -Envelope (Seal -Seq 7) -HordeHome $h
        Check (IsFresh $v) "a stream with leftovers still takes envelopes"
        Check (-not (Test-Path -LiteralPath $deadTmp)) "the dead writer's temporary file was swept"
        Check (Test-Path -LiteralPath $liveTmp) "the one a live writer holds was not"
    } finally { $held.Dispose() }

    Write-Host ""
    Write-Host "--- VII. sending ---" -ForegroundColor Cyan
    $h = New-Home
    $n = Get-HordeRelayJournalNextSeq -From $machineId -Channel "decisions" -HordeHome $h
    Check ($n.state -ceq "known" -and $n.value -eq 1) "a stream that sent nothing starts at seq 1"
    $t1 = SealText -Seq 1
    $s = Register-HordeRelayJournalSent -Text $t1 -HordeHome $h
    Check ((IsFresh $s) -and $s.value.direction -ceq "out") "sending seq 1 records it, outbound"
    Check ((Get-HordeRelayJournalNextSeq -From $machineId -Channel "decisions" -HordeHome $h).value -eq 2) "and the next seq is 2"
    $s = Register-HordeRelayJournalSent -Text (SealText -Seq 1) -HordeHome $h
    Check (IsRefused $s "another nonce") "another envelope under seq 1 is refused: a seq is sent once"
    $s = Register-HordeRelayJournalSent -Text $t1 -HordeHome $h
    Check (IsRefused $s "a replay") "the same envelope recorded twice is refused the second time"
    Check ((Names (StreamDir $h -Dir "out")) -ceq ((RecName 1) + ",lock")) "outbound records sit under out\, apart from what was received"
    Check (IsUnknown (Register-HordeRelayJournalSent -Text "not an envelope" -HordeHome $h) "not an envelope") "text that is not an envelope is not recorded"
    Check (IsUnknown (Get-HordeRelayJournalNextSeq -From "nope" -Channel "decisions" -HordeHome $h) "32-hex") "a stream name that is not one is refused"
    Check (IsUnknown (Get-HordeRelayJournalNextSeq -From $machineId -Channel "decisions" -HordeHome (New-Home -Bare)) "not a relay journal") "the next seq of no journal is unknown"

    Write-Host ""
    Write-Host "--- VIII. one writer per stream; settings ---" -ForegroundColor Cyan
    $h = New-Home
    $null = Receive -Envelope (Seal -Seq 1) -HordeHome $h
    $waitMs = 2000
    if ($settingsRead) { Write-Settings -HordeHome $h -Json '{"schemaVersion":1,"settings":{"lockWaitMs":300}}'; $waitMs = 300 }
    $lockPath = Join-Path (StreamDir $h) "lock"
    $holder = New-Object System.IO.FileStream -ArgumentList $lockPath, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), ([System.IO.FileShare]::None)
    $began = [datetime]::UtcNow
    try { $v = Receive -Envelope (Seal -Seq 2) -HordeHome $h } finally { $holder.Dispose() }
    $waited = ([datetime]::UtcNow - $began).TotalMilliseconds
    Check (IsUnknown $v "busy") ("while another holds the stream's lock: unknown, busy (" + $v.reason + ")")
    Check ($waited -ge ($waitMs - 50)) ("and it waited the setting's " + $waitMs + " ms first (" + [int]$waited + " ms)")
    Check (IsFresh (Receive -Envelope (Seal -Seq 2) -HordeHome $h)) "released, the same envelope is fresh"
    Write-Settings -HordeHome $h -Json '{"schemaVersion":1,"settings":{"seqWindow":0}}'
    $v = Receive -Envelope (Seal -Seq 3) -HordeHome $h
    Check (IsUnknown $v "relay-journal") ("a settings file that fails its checks refuses, never falls back to defaults (" + $v.reason + ")")
    Write-Settings -HordeHome $h -Json '{"schemaVersion":1,"settings":{}}'
    Check (IsFresh (Receive -Envelope (Seal -Seq 3) -HordeHome $h)) "CONTROL: an empty settings file is the defaults"
} finally {
    if ((Split-Path -Leaf $work) -match '^horde-relay-journal-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "every journal this suite made is gone"

if ($script:skipped -gt 0) { Complete-HordeSuite -Success ("partial: " + $script:skipped + " setting checks skipped on this runtime; every other check passed") -PassCode 3 }
Complete-HordeSuite -Success "the journal calls an envelope fresh once, refuses replays, reorders, reuses, skew and damage, and never resets"
