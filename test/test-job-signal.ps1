# DO `horde job` AND `horde signal` KEEP THEIR PROMISES THROUGH THE REAL COMMAND, IN BOTH POWERSHELLS?
#
# The rules of the verbs are attacked in fleet-db/test/jobs.test.mjs (node). This suite drives the real horde.ps1 the way
# the overseer does, under Windows PowerShell 5.1 and PowerShell 7 (CONTRIBUTING 12; without pwsh.exe the 7 half is NOT RUN,
# said loudly, and the suite exits 3, never 0): that a verb with no home names the home, that a missing fleet.db is refused
# (and is not made), that every repeat says kept, that long text goes in by -File with its quotes and line breaks intact, that
# an empty value, a double quote in an argument, a flag of another verb, a local time and a character outside ASCII are each
# refused in words, that the finer exit code (4 no fleet.db yet) is named in the message, and that db status counts the two
# tables and db check stays ok.
# NOTHING REAL IS READ OR WRITTEN: the home and the user profile every child sees are folders this suite made in %TEMP% and
# removes, so an empty environment cannot fall through to the real home pointer (the empty-env rule).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] no node here: fleet.db cannot run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}

$work = Join-Path $env:TEMP ("horde-job-signal-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$fakeProfile = Join-Path $work "profile"
New-Item -ItemType Directory -Path $fakeProfile | Out-Null

$shells = New-Object System.Collections.ArrayList
[void]$shells.Add([pscustomobject]@{ name = "Windows PowerShell 5.1"; exe = "powershell.exe" })
$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
$partial = $false
if ($null -eq $pwsh) {
    Write-Host ""
    Write-Host "  [NOT RUN] POWERSHELL 7 IS NOT ON THIS MACHINE (no pwsh.exe). Only 5.1 was checked." -ForegroundColor Yellow
    $partial = $true
} else {
    [void]$shells.Add([pscustomobject]@{ name = "PowerShell 7"; exe = $pwsh.Source })
}

$pastMs = "1700000000000"
$futureMs = [string]([DateTimeOffset]::UtcNow.AddDays(30).ToUnixTimeMilliseconds())

try {

foreach ($sh in $shells) {
    Write-Host ""
    Write-Host ("--- " + $sh.name + " ---") -ForegroundColor Cyan
    $homeDir = Join-Path $work ("home-" + ($sh.exe -replace '[^a-zA-Z0-9]', ''))
    New-Item -ItemType Directory -Path $homeDir | Out-Null
    $env1 = @{ HORDE_HOME = $homeDir; USERPROFILE = $fakeProfile }
    $shellExe = $sh.exe
    $dbFile = Join-Path $homeDir "fleet.db"
    function Invoke-Verb { param([string[]]$VerbArgs, [hashtable]$Env = $env1) return (Invoke-HordeCliProcess -Root $root -HordeArgs $VerbArgs -Env $Env -Shell $shellExe) }

    # --- no home, no database ---
    $nohome = Invoke-Verb @("job", "list") @{ HORDE_HOME = ""; USERPROFILE = $fakeProfile }
    Check ($nohome.code -ne 0 -and $nohome.out -like "*horde job needs HORDE_HOME set*") "job with no home is refused, naming the home"
    $nohome2 = Invoke-Verb @("signal", "list") @{ HORDE_HOME = ""; USERPROFILE = $fakeProfile }
    Check ($nohome2.code -ne 0 -and $nohome2.out -like "*horde signal needs HORDE_HOME set*") "signal with no home is refused, naming the home"
    $nodb = Invoke-Verb @("job", "list")
    Check ($nodb.code -eq 1 -and $nodb.out -like "*fleet.db does not exist yet (run horde db init)*" -and $nodb.out -like "*stopped with exit code 4*") "no fleet.db is refused in one line and the message names exit code 4"
    $nodb2 = Invoke-Verb @("signal", "raise", "-Key", "K:1", "-Kind", "alarm", "-Text", "stuck")
    Check ($nodb2.code -eq 1 -and $nodb2.out -like "*stopped with exit code 4*") "a signal raise with no fleet.db is refused the same way"
    Check ((-not (Test-Path -LiteralPath $dbFile)) -and @(Get-ChildItem -LiteralPath $homeDir -Force).Count -eq 0) "and neither verb made the database or anything else in the home"
    $init = Invoke-Verb @("db", "init")
    Check ($init.code -eq 0 -and $init.out -like "*(schema 8, created)*") "horde db init makes it, at schema 8"

    # --- jobs ---
    $j1 = Invoke-Verb @("job", "upsert", "-Id", "J-1", "-Owner", "R", "-Job", "review the PRs", "-By", "S", "-Due", $futureMs)
    Check ($j1.code -eq 0 -and $j1.out -cmatch '(?m)^created J-1\r?$') "job upsert makes a job"
    $j2 = Invoke-Verb @("job", "upsert", "-Id", "J-1", "-Owner", "R", "-Job", "review the PRs", "-By", "S", "-Due", $futureMs)
    Check ($j2.code -eq 0 -and $j2.out -cmatch '(?m)^kept J-1\r?$') "the same call again says kept and exits 0"
    $j3 = Invoke-Verb @("job", "upsert", "-Id", "J-1", "-Owner", "Q", "-Job", "review the PRs", "-By", "S")
    Check ($j3.code -eq 0 -and $j3.out -cmatch '(?m)^updated J-1 \(owner\)\r?$') "a changed owner says updated and names the field; a due time left out stays"
    $jl = Invoke-Verb @("job", "list")
    Check ($jl.code -eq 0 -and $jl.out -cmatch '(?m)^J-1 Q open started=\S+ due=\S+ done=- \| review the PRs\r?$') "job list is one plain line per job"
    $jj = Invoke-Verb @("job", "list", "-Json", "-Open")
    Check ($jj.code -eq 0 -and $jj.out -like '*"id":"J-1"*' -and $jj.out -like '*"owner":"Q"*' -and $jj.out -like '*"state":"open"*') "job list -Json is one line of data"
    $late = Invoke-Verb @("job", "upsert", "-Id", "J-late", "-Owner", "R", "-Job", "was due long ago", "-By", "S", "-Due", $pastMs)
    $od = Invoke-Verb @("job", "list", "-Overdue")
    Check ($od.code -eq 0 -and $od.out -like "*J-late R overdue*" -and $od.out -notlike "*J-1 *") "job list -Overdue shows only the open job past its due time"

    $wo = Invoke-Verb @("job", "upsert", "-Id", "J-late", "-Owner", "R", "-Job", "was due long ago", "-By", "S", "-WaitingOn", "the founder")
    Check ($wo.code -eq 0 -and $wo.out -cmatch '(?m)^updated J-late \(waiting_on\)\r?$') "job upsert -WaitingOn records who it waits on and says updated"
    $wo2 = Invoke-Verb @("job", "upsert", "-Id", "J-late", "-Owner", "R", "-Job", "was due long ago", "-By", "S", "-WaitingOn", "the founder")
    Check ($wo2.code -eq 0 -and $wo2.out -cmatch '(?m)^kept J-late\r?$') "the same -WaitingOn again says kept"
    $wl = Invoke-Verb @("job", "list", "-Open")
    Check ($wl.code -eq 0 -and $wl.out -cmatch '(?m)^J-late R overdue started=\S+ due=\S+ done=- waiting=the_founder \| was due long ago\r?$') "-Open still lists a waiting job, and its line says what it waits on"
    $wj = Invoke-Verb @("job", "list", "-Json")
    Check ($wj.out -like '*"waiting_on":"the founder"*') "-Json carries waiting_on"
    $nw = Invoke-Verb @("job", "list", "-Open", "-NotWaiting")
    Check ($nw.code -eq 0 -and $nw.out -notlike "*J-late *" -and $nw.out -like "*J-1 *") "job list -Open -NotWaiting leaves out the waiting job"
    $wb = Invoke-Verb @("job", "upsert", "-Id", "J-late", "-Owner", "R", "-Job", "was due long ago", "-By", "S", "-WaitingOn", "x", "-NotWaiting")
    Check ($wb.code -eq 1 -and $wb.out -like "*contradict*") "-WaitingOn and -NotWaiting together are refused"
    $wc = Invoke-Verb @("job", "upsert", "-Id", "J-late", "-Owner", "R", "-Job", "was due long ago", "-By", "S", "-NotWaiting")
    Check ($wc.code -eq 0 -and $wc.out -cmatch '(?m)^updated J-late \(waiting_on\)\r?$') "job upsert -NotWaiting clears it"
    $nw2 = Invoke-Verb @("job", "list", "-Open", "-NotWaiting")
    Check ($nw2.code -eq 0 -and $nw2.out -like "*J-late *") "and the job is back among the ones that wait on nothing"

    # --- long text by -File: quotes and line breaks survive; a non-ASCII file is refused in words ---
    $longFile = Join-Path $work ("long-" + $sh.exe.Length + ".txt")
    [System.IO.File]::WriteAllText($longFile, ("line one says `"hi`"`r`nline two`r`n"), $utf8)
    $jf = Invoke-Verb @("job", "upsert", "-Id", "J-file", "-Owner", "R", "-File", $longFile, "-By", "S")
    Check ($jf.code -eq 0 -and $jf.out -cmatch '(?m)^created J-file\r?$') "job upsert -File takes long text"
    $jfl = Invoke-Verb @("job", "list", "-Json")
    Check ($jfl.out -like '*"job":"line one says \"hi\"\nline two"*') "its quotes and line break came through, the CRLF as one LF and no trailing newline"
    $accFile = Join-Path $work ("acc-" + $sh.exe.Length + ".txt")
    [System.IO.File]::WriteAllBytes($accFile, $utf8.GetBytes("caf" + [char]0xE9))
    $jacc = Invoke-Verb @("job", "upsert", "-Id", "J-acc", "-Owner", "R", "-File", $accFile, "-By", "S")
    Check ($jacc.code -eq 1 -and $jacc.out -like "*refused: Job must be ASCII (character 4 is U+00E9)*") "a file with a character outside ASCII is refused, naming the place and the character"
    $both = Invoke-Verb @("job", "upsert", "-Id", "J-both", "-Owner", "R", "-Job", "x", "-File", $longFile, "-By", "S")
    Check ($both.code -eq 1 -and $both.out -like "*give exactly one of --job and --file*") "text and a file together are refused"

    # --- refusals in words, before the database ---
    $quote = Invoke-Verb @("job", "upsert", "-Id", "J-q", "-Owner", "R", "-Job", 'a\"b', "-By", "S")
    Check ($quote.code -eq 1 -and $quote.out -like "*-Job holds a double quote*use -File*") "a double quote in an argument is refused and -File is named"
    $empty = Invoke-Verb @("job", "upsert", "-Id", "J-e", "-Owner", " ", "-Job", "x", "-By", "S")
    Check ($empty.code -eq 1 -and $empty.out -like "*-Owner is empty*") "an empty value is refused, not passed on to shift the next flag into it"
    $foreign = Invoke-Verb @("job", "list", "-Proof", "x")
    Check ($foreign.code -ne 0 -and $foreign.out -like "*-Proof does not belong to job list*") "a flag of another verb is refused"
    $foreign2 = Invoke-Verb @("signal", "close", "-Key", "K:1", "-By", "S", "-Days", "3")
    Check ($foreign2.code -ne 0 -and $foreign2.out -like "*-Days does not belong to signal close*") "and on signal too"
    $local = Invoke-Verb @("job", "upsert", "-Id", "J-t", "-Owner", "R", "-Job", "x", "-By", "S", "-Due", "2026-11-01T01:30:00")
    Check ($local.code -eq 1 -and $local.out -like "*refused: Due has no time zone*") "a local time with no zone is refused"
    $zoned = Invoke-Verb @("job", "upsert", "-Id", "J-t", "-Owner", "R", "-Job", "x", "-By", "S", "-Due", "2026-11-01T01:30:00-04:00", "-Session", "00000000-0000-4000-8000-000000000001")
    Check ($zoned.code -eq 0 -and $zoned.out -cmatch '(?m)^created J-t\r?$') "the same time with an offset is accepted"
    $js = Invoke-Verb @("job", "list", "-Json")
    Check ($js.code -eq 0 -and $js.out -like '*"session_id":"00000000-0000-4000-8000-000000000001"*') "the session came through to the row"
    $noid = Invoke-Verb @("job", "upsert", "-Owner", "R", "-Job", "x", "-By", "S")
    Check ($noid.code -eq 1 -and $noid.out -like "*--id is required*") "a missing required flag is refused in words"

    # --- done is final ---
    $d1 = Invoke-Verb @("job", "done", "-Id", "J-1", "-Proof", "PR 77 merged", "-By", "S")
    Check ($d1.code -eq 0 -and $d1.out -cmatch '(?m)^done J-1\r?$') "job done closes it with its proof"
    $lo = Invoke-Verb @("job", "list", "-Open")
    Check ($lo.code -eq 0 -and $lo.out -notlike "*J-1 *" -and $lo.out -like "*J-late *") "job list -Open leaves out the done job"
    $la = Invoke-Verb @("job", "list")
    Check ($la.code -eq 0 -and $la.out -cmatch '(?m)^J-1 Q done started=\S+ due=\S+ done=\S+ \| review the PRs\r?$') "and without -Open the done job is listed"
    $d2 = Invoke-Verb @("job", "done", "-Id", "J-1", "-Proof", "PR 77 merged", "-By", "S")
    Check ($d2.code -eq 0 -and $d2.out -cmatch '(?m)^kept J-1\r?$') "the same proof again says kept"
    $d2b = Invoke-Verb @("job", "done", "-Id", "J-1", "-Proof", "PR 77 merged", "-By", "T")
    Check ($d2b.code -eq 0 -and $d2b.out -cmatch '(?m)^kept J-1\r?$') "the same proof with another -By says kept"
    $dj = Invoke-Verb @("job", "list", "-Json")
    Check ($dj.out -like '*"done_by":"S"*' -and $dj.out -notlike '*"done_by":"T"*') "done_by is the first -By"
    $d3 = Invoke-Verb @("job", "done", "-Id", "J-1", "-Proof", "PR 78 merged", "-By", "S")
    Check ($d3.code -eq 1 -and $d3.out -like "*already done with another proof*") "another proof is refused"
    $d4 = Invoke-Verb @("job", "upsert", "-Id", "J-1", "-Owner", "R", "-Job", "again", "-By", "S")
    Check ($d4.code -eq 1 -and $d4.out -like "*job J-1 is done; a new piece of work takes a new id*") "an upsert on a done job is refused, and says what to do"
    $d5 = Invoke-Verb @("job", "done", "-Id", "J-1", "-By", "S")
    Check ($d5.code -ne 0 -and $d5.out -like "*give exactly one of --proof and --file*") "a done with no proof is refused"

    $dAt = Invoke-Verb @("job", "done", "-Id", "J-t", "-Proof", "too early", "-By", "S", "-At", $pastMs)
    Check ($dAt.code -eq 1 -and $dAt.out -like "*At is before the job started*") "job done -At before the start is refused (the -At reached the rule)"
    $st0 = Invoke-Verb @("job", "upsert", "-Id", "J-st", "-Owner", "R", "-Job", "started in the past", "-By", "S", "-Started", $pastMs)
    $st1 = Invoke-Verb @("job", "list", "-Owner", "R")
    Check ($st0.code -eq 0 -and $st1.out -cmatch '(?m)^J-st R open started=2023-11-14T22:13:20\.000Z due=- done=- \| started in the past\r?$') "-Started is taken as given, in UTC"

    # --- signals ---
    $s1 = Invoke-Verb @("signal", "raise", "-Key", "ALARM:T-1", "-Kind", "alarm", "-Owner", "O", "-Text", "T-1 is stuck", "-At", $pastMs)
    Check ($s1.code -eq 0 -and $s1.out -cmatch '(?m)^raised ALARM:T-1 \(count 1\)\r?$') "signal raise makes a signal"
    $s2 = Invoke-Verb @("signal", "raise", "-Key", "ALARM:T-1", "-Kind", "alarm", "-Text", "T-1 is stuck", "-At", $pastMs)
    Check ($s2.code -eq 0 -and $s2.out -cmatch '(?m)^kept ALARM:T-1\r?$') "the same key at the same -At is a retry: kept, not counted twice"
    $later = [string]([long]$pastMs + 60000)
    $s3 = Invoke-Verb @("signal", "raise", "-Key", "ALARM:T-1", "-Kind", "alarm", "-Text", "T-1 is still stuck", "-At", $later)
    Check ($s3.code -eq 0 -and $s3.out -cmatch '(?m)^updated ALARM:T-1 \(count 2\)\r?$') "a later raise counts"
    $sl = Invoke-Verb @("signal", "list", "-Open")
    Check ($sl.code -eq 0 -and $sl.out -cmatch '(?m)^ALARM:T-1 alarm O open count=2 first=\S+ last=\S+ woke=- ok=- \| T-1 is still stuck\r?$') "signal list is one plain line per signal, the owner kept from the first raise"
    $mw = Invoke-Verb @("signal", "list", "-Open", "-MarkWoke", "-Json")
    Check ($mw.code -eq 0 -and $mw.out -like '*"key":"ALARM:T-1"*' -and $mw.out -cmatch '"woke_at":\d{13}') "signal list -MarkWoke (which implies -Unwoken) records the wake attempt on the signals it returns"
    $uw = Invoke-Verb @("signal", "list", "-Open", "-Unwoken")
    Check ($uw.code -eq 0 -and $uw.out -like "*ALARM:T-1 *") "an attempted wake is not a confirmed one: the signal is still unwoken, so a failed wake is retried"
    $wk = Invoke-Verb @("signal", "woke", "-Key", "ALARM:T-1")
    Check ($wk.code -eq 0 -and $wk.out -cmatch '(?m)^woke ALARM:T-1\r?$') "signal woke records that the wake worked"
    $wk2 = Invoke-Verb @("signal", "woke", "-Key", "ALARM:T-1")
    Check ($wk2.code -eq 0 -and $wk2.out -cmatch '(?m)^kept ALARM:T-1\r?$') "and a repeat says kept"
    $uw2 = Invoke-Verb @("signal", "list", "-Open", "-Unwoken")
    Check ($uw2.code -eq 0 -and $uw2.out -like "*no signals*") "after a confirmed wake the signal is no longer unwoken"
    $wk3 = Invoke-Verb @("signal", "woke", "-Key", "no-such-key")
    Check ($wk3.code -eq 1 -and $wk3.out -like "*refused: no signal is called no-such-key*") "signal woke on an unknown key is refused"
    $mwBad = Invoke-Verb @("signal", "list", "-MarkWoke")
    Check ($mwBad.code -eq 1 -and $mwBad.out -like "*MarkWoke needs Open*") "-MarkWoke without -Open is refused"
    $c1 = Invoke-Verb @("signal", "close", "-Key", "ALARM:T-1", "-By", "S")
    Check ($c1.code -eq 0 -and $c1.out -cmatch '(?m)^closed ALARM:T-1\r?$') "signal close closes it"
    $c2 = Invoke-Verb @("signal", "close", "-Key", "ALARM:T-1", "-By", "S")
    Check ($c2.code -eq 0 -and $c2.out -cmatch '(?m)^kept ALARM:T-1\r?$') "closing a closed one says kept"
    $c3 = Invoke-Verb @("signal", "close", "-Key", "no-such-key", "-By", "S")
    Check ($c3.code -eq 1 -and $c3.out -like "*refused: no signal is called no-such-key*") "an unknown key is refused"
    $reopenAt = [string]([long]$pastMs + 120000)
    $s4 = Invoke-Verb @("signal", "raise", "-Key", "ALARM:T-1", "-Kind", "alarm", "-Text", "it came back", "-At", $reopenAt)
    Check ($s4.code -eq 0 -and $s4.out -cmatch '(?m)^reopened ALARM:T-1 \(count 3\)\r?$') "a closed signal raised again is reopened and says so"
    $s5 = Invoke-Verb @("signal", "raise", "-Key", "ALARM:T-1", "-Kind", "other", "-Text", "x", "-At", [string]([long]$pastMs + 180000))
    Check ($s5.code -eq 1 -and $s5.out -like "*is of kind alarm, not other*") "a key of another kind is refused"
    $sfile = Join-Path $work ("sig-" + $sh.exe.Length + ".txt")
    [System.IO.File]::WriteAllText($sfile, "analyst raised: T-2 stuck`r`nsecond line`r`n", $utf8)
    $s6 = Invoke-Verb @("signal", "raise", "-Key", "ALARM:T-2", "-Kind", "alarm", "-File", $sfile, "-At", $pastMs)
    Check ($s6.code -eq 0 -and $s6.out -cmatch '(?m)^raised ALARM:T-2 \(count 1\)\r?$') "signal raise -File takes long text"
    $localAt = Invoke-Verb @("signal", "raise", "-Key", "ALARM:T-3", "-Kind", "alarm", "-Text", "x", "-At", "2026-11-06T09:00:00")
    Check ($localAt.code -eq 1 -and $localAt.out -like "*refused: At has no time zone*") "a signal time with no zone is refused"
    # --- quiet, urgent, owners with spaces and paths, a value ending in a backslash, a reopen by an old -At ---
    $q1 = Invoke-Verb @("signal", "raise", "-Key", "Q:1", "-Kind", "alarm", "-Text", "quiet one", "-Quiet", "-At", $pastMs)
    $u1 = Invoke-Verb @("signal", "raise", "-Key", "U:1", "-Kind", "alarm", "-Owner", "parent e9932755", "-Text", "urgent one", "-Urgent", "-At", $pastMs)
    $pth = Invoke-Verb @("signal", "raise", "-Key", "P:1", "-Kind", "alarm", "-Owner", "C:\Windows\system32\cmd.exe", "-Text", "path owner", "-At", $pastMs)
    $bsl = Invoke-Verb @("signal", "raise", "-Key", "B:1", "-Kind", "alarm", "-Owner", "C:\My Folder\\", "-Text", "owner ending in a backslash", "-At", $pastMs)
    Check ($q1.code -eq 0 -and $u1.code -eq 0 -and $pth.code -eq 0 -and $bsl.code -eq 0) "-Quiet, -Urgent, an owner with spaces, a path and a value ending in a backslash are all accepted"
    $oj = Invoke-Verb @("signal", "list", "-Json")
    Check ($oj.out -like '*"owner":"parent e9932755"*' -and $oj.out -like '*"owner":"C:\\Windows\\system32\\cmd.exe"*') "an owner with spaces and an owner that is a path arrive whole"
    Check ($oj.out -like '*"owner":"C:\\My Folder\\"*') "a value ending in a backslash arrives whole (the closing quote was not eaten)"
    Check ($oj.out -like '*"key":"U:1"*"urgent":1*' -and $oj.out -like '*"key":"Q:1"*"quiet":1*') "urgent and quiet are carried"
    $un = Invoke-Verb @("signal", "list", "-Open", "-Unwoken")
    Check ($un.code -eq 0 -and $un.out -like "*U:1 *" -and $un.out -like "*P:1 *" -and $un.out -notlike "*Q:1 *") "a quiet signal is never unwoken"
    $mk = Invoke-Verb @("signal", "list", "-Open", "-MarkWoke", "-Json", "-Owner", "parent e9932755")
    Check ($mk.code -eq 0 -and $mk.out -like '*"key":"U:1"*' -and $mk.out -cmatch '"woke_at":\d{13}') "MarkWoke stamps the signal it lists"
    $uok = Invoke-Verb @("signal", "woke", "-Key", "U:1")
    $mk2 = Invoke-Verb @("signal", "list", "-Open", "-MarkWoke", "-Json")
    Check ($mk2.code -eq 0 -and $mk2.out -like '*"key":"P:1"*' -and $mk2.out -notlike '*"key":"U:1"*' -and $mk2.out -notlike '*"key":"Q:1"*') "MarkWoke without -Unwoken still stamps only what needs a wake: not the confirmed one, not the quiet one"
    $ucl = Invoke-Verb @("signal", "close", "-Key", "U:1", "-By", "S")
    $uro = Invoke-Verb @("signal", "raise", "-Key", "U:1", "-Kind", "alarm", "-Text", "back again", "-At", $pastMs)
    Check ($uro.code -eq 0 -and $uro.out -cmatch '(?m)^reopened U:1 \(count 2\)\r?$') "a closed signal raised with an old -At is reopened"
    $urj = Invoke-Verb @("signal", "list", "-Json", "-Owner", "parent e9932755")
    Check ($urj.out -like '*"last_at":1700000000000,"count":2,"woke_at":null,"woke_ok_at":null,"urgent":0*') "last_at did not move back, both wake times are cleared, urgent is back to 0"
    $ushow = Invoke-Verb @("signal", "list", "-Open", "-Unwoken")
    Check ($ushow.out -like "*U:1 *") "and it needs a wake again"

    $p0 = Invoke-Verb @("signal", "prune")
    Check ($p0.code -eq 1 -and $p0.out -like "*--days is required*") "prune without -Days is refused"
    $p00 = Invoke-Verb @("signal", "prune", "-Days", "0")
    Check ($p00.code -eq 1 -and $p00.out -like "*Days is required and must be a whole number of 1 or more*") "prune with 0 days is refused"
    $p1 = Invoke-Verb @("signal", "prune", "-Days", "30")
    Check ($p1.code -eq 0 -and $p1.out -cmatch '(?m)^pruned 0 closed signals closed more than 30 days ago\r?$') "prune says how many it deleted; a signal closed just now is not old"

    # --- the reading side ---
    $st = Invoke-Verb @("db", "status")
    Check ($st.code -eq 0 -and $st.out -cmatch '(?m)^job: 5 rows\r?$' -and $st.out -cmatch '(?m)^signal: 6 rows\r?$') "db status counts the two tables like every other"
    $ck = Invoke-Verb @("db", "check")
    Check ($ck.code -eq 0 -and $ck.out -cmatch '(?m)^check: ok\r?$') "db check still says ok on a file the verbs wrote"
}

} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($partial) {
    Complete-HordeSuite -Success "PARTIAL: Windows PowerShell 5.1 only; PowerShell 7 was not run" -PassCode 3
}
Complete-HordeSuite -Success "horde job and horde signal keep their promises in both shells"
