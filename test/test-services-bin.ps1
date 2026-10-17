# DOES THE INSTALLED CLI FOLLOW MAIN - AND NEVER TOUCH A CLONE IT SHOULD LEAVE ALONE?
#
# cli/ServicesBin.ps1 (the follower and its status), the notice words in cli/ServicesTell.ps1.
#
# NOTHING OF THIS MACHINE'S IS MOVED OR TOLD: every repository here is a throwaway under this suite's own
# temp folder (an origin, a seed that pushes to it, and the "installed" clone), the teller is a block that
# records what it was handed, and the probe is either a block of the suite's or the real `horde version`
# of a stub horde.ps1 this suite wrote into its own clone.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "Services", "ServicesFiles", "ServiceHostPort", "Schedule")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
foreach ($f in @("ServicesAct", "ServicesTend", "ServicesTell")) { . (Join-Path $root ("cli\" + $f + ".ps1")) }

$work = Join-Path $env:TEMP ("horde-bin-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$t0 = [datetime]::new(2026, 10, 17, 12, 0, 0, [System.DateTimeKind]::Utc)
$okScript = 'if ($args[0] -ne "version") { exit 9 }; exit 0'
$gitEnv = @{ GIT_AUTHOR_NAME = "t"; GIT_AUTHOR_EMAIL = "t@example.invalid"; GIT_COMMITTER_NAME = "t"; GIT_COMMITTER_EMAIL = "t@example.invalid" }

function G {
    # One git call in a folder; returns its trimmed output; throws when it fails.
    param([string]$Dir, [string[]]$Arguments)
    $r = Invoke-HordeServiceProgram -Program (Get-HordeServiceGitProgram) -Arguments (@("-C", $Dir) + $Arguments) -Environment $gitEnv -TimeoutSeconds 60
    if ($r.code -ne 0) { throw ("git " + ($Arguments -join " ") + " failed: " + $r.err) }
    return $r.out.Trim()
}
function New-World {
    # origin (bare), seed (pushes to it) and bin (the installed clone), all on main. The first commit
    # carries a horde.ps1 that loads; Push-Commit adds more.
    param([string]$Name)
    $w = [pscustomobject]@{ origin = (Join-Path $work ($Name + "-origin")); seed = (Join-Path $work ($Name + "-seed")); bin = (Join-Path $work ($Name + "-bin")); home = (Join-Path $work ($Name + "-home")); n = 0 }
    [void][System.IO.Directory]::CreateDirectory($w.origin); [void][System.IO.Directory]::CreateDirectory($w.seed); [void][System.IO.Directory]::CreateDirectory($w.home)
    $null = G $w.origin @("init", "--bare", "--quiet")
    $null = G $w.origin @("symbolic-ref", "HEAD", "refs/heads/main")
    $null = G $w.seed @("init", "--quiet")
    $null = G $w.seed @("symbolic-ref", "HEAD", "refs/heads/main")
    $null = G $w.seed @("remote", "add", "origin", $w.origin)
    $null = Push-Commit $w $okScript
    $r = Invoke-HordeServiceProgram -Program (Get-HordeServiceGitProgram) -Arguments @("clone", "--quiet", $w.origin, $w.bin) -Environment $gitEnv -TimeoutSeconds 60
    if ($r.code -ne 0) { throw ("clone failed: " + $r.err) }
    return $w
}
function Push-Commit {
    # A new commit on origin/main whose horde.ps1 is -Script (a file the real probe runs).
    param($W, [string]$Script)
    $W.n++
    [System.IO.File]::WriteAllText((Join-Path $W.seed "horde.ps1"), ($Script + "`r`n"))
    [System.IO.File]::WriteAllText((Join-Path $W.seed "n.txt"), ("" + $W.n))
    if ($W.n -eq 1) { [System.IO.File]::WriteAllText((Join-Path $W.seed "keep.txt"), "keep") }
    $null = G $W.seed @("add", "-A")
    $null = G $W.seed @("commit", "--quiet", "-m", ("c" + $W.n))
    $null = G $W.seed @("push", "--quiet", "origin", "main")
    return (G $W.seed @("rev-parse", "HEAD"))
}
function Head { param($W) return (G $W.bin @("rev-parse", "HEAD")) }
function New-Policy {
    param($W, [bool]$Follow = $true, [int]$Interval = 300)
    return [pscustomobject]@{ followInstalledCli = $Follow; installedCliFolder = $W.bin; fetchIntervalSeconds = $Interval; gitSeconds = 30; checkSeconds = 30; tellWarchief = $true }
}
function New-Told { return @{ notices = (New-Object System.Collections.ArrayList); ok = $true } }
function New-Teller {
    param($Told)
    return { param($Notices, $HordeHome, $Policy) if (-not $Told.ok) { return [pscustomobject]@{ told = @(); problem = "no session holds the role of warchief" } }; foreach ($n in @($Notices)) { [void]$Told.notices.Add($n) }; return [pscustomobject]@{ told = @($Notices | ForEach-Object { $_.id }); problem = "" } }.GetNewClosure()
}
function Follow {
    param($W, $Policy, [datetime]$Now, $Told, $Probe = $null, [switch]$NoFetch)
    $tools = New-HordeInstalledCliTools
    if ($null -ne $Probe) { $tools["Probe"] = $Probe }
    return (Quiet { Invoke-HordeInstalledCliFollow -HordeHome $W.home -Policy $Policy -Now $Now -Tell (New-Teller $Told) -Tools $tools -NoFetch:$NoFetch })
}
# A call that must not throw: when it does, the answer says so and the check that reads it FAILS.
function Quiet { param([scriptblock]$Block) try { return @(& $Block) } catch { return @("IT THREW: " + $_.Exception.Message) } }
function Said { param($Lines) return ((@($Lines) | ForEach-Object { "" + $_ }) -join " | ") }

try {
    Write-Host ""
    Write-Host "--- I. behind, clean, on main: fast-forwarded, and proved to load ---" -ForegroundColor Cyan
    $w = New-World "a"
    $pol = New-Policy $w
    $told = New-Told
    $tip = Push-Commit $w $okScript
    $probed = New-Object System.Collections.ArrayList
    $probe = { param($Path, $Policy) [void]$probed.Add($Path); return [pscustomobject]@{ ok = $true; detail = "loads" } }.GetNewClosure()
    $lines = Follow $w $pol $t0 $told $probe
    Check ((Head $w) -ceq $tip) "a clone that is behind origin/main, clean and on main is fast-forwarded to it"
    Check ($probed.Count -eq 2 -and $probed[1] -ceq $w.bin) "and the CLI is proved to load: once beside the clone, and once in the clone itself"
    Check ((Said $lines) -like "*installed CLI: moved * -> " + $tip.Substring(0, 9) + " and it loads*") "and the pass says what it moved"
    Check ($told.notices.Count -eq 0) "and tells nobody: nothing was wrong"
    Check (@(Read-HordeServiceJournalTail -Count 10 -HordeHome $w.home | Where-Object { $_ -like '*"service":"installed-cli"*' -and $_ -like '*"code":"updated"*' }).Count -eq 1) "and the move is journaled"
    $probed.Clear()
    $lines = Follow $w $pol $t0.AddSeconds(400) $told $probe
    Check (@($lines).Count -eq 0 -and $probed.Count -eq 0) "a clone already on origin/main costs a quiet pass: no line, no probe"

    Write-Host ""
    Write-Host "--- II. the remote is asked at the interval, and never faster than once a minute ---" -ForegroundColor Cyan
    $w = New-World "b"
    $pol = New-Policy $w -Interval 30
    $told = New-Told
    $first = Push-Commit $w $okScript
    $null = Follow $w $pol $t0 $told $probe
    Check ((Head $w) -ceq $first) "the first pass asks the remote and moves"
    $second = Push-Commit $w $okScript
    $null = Follow $w $pol $t0.AddSeconds(45) $told $probe
    Check ((Head $w) -ceq $first) "a setting of 30 s is held to the floor of a minute: at 45 s the remote is not asked, so the clone stays"
    $null = Follow $w $pol $t0.AddSeconds(61) $told $probe
    Check ((Head $w) -ceq $second) "at 61 s it is asked, and the clone moves"
    $third = Push-Commit $w $okScript
    $w2 = New-World "b2"
    $pol2 = New-Policy $w2 -Interval 600
    $null = Follow $w2 $pol2 $t0 (New-Told) $probe
    $newer = Push-Commit $w2 $okScript
    $null = Follow $w2 $pol2 $t0.AddSeconds(300) (New-Told) $probe
    Check ((Head $w2) -cne $newer) "a setting of 600 s is kept: at 300 s the remote is not asked"
    $null = Follow $w2 $pol2 $t0.AddSeconds(601) (New-Told) $probe
    Check ((Head $w2) -ceq $newer) "and at 601 s it is"

    Write-Host ""
    Write-Host "--- III. a changed tracked file: never touched, told once ---" -ForegroundColor Cyan
    $w = New-World "c"
    $pol = New-Policy $w
    $told = New-Told
    $tip = Push-Commit $w $okScript
    $before = Head $w
    [System.IO.File]::WriteAllText((Join-Path $w.bin "n.txt"), "my own edit")
    $probed.Clear()
    $lines = Follow $w $pol $t0 $told $probe
    Check ((Head $w) -ceq $before -and [System.IO.File]::ReadAllText((Join-Path $w.bin "n.txt")) -ceq "my own edit") "a dirty clone is not moved, and its edit is still there"
    Check ($probed.Count -eq 0) "and nothing is probed"
    Check ($told.notices.Count -eq 1 -and (Get-HordeTestMember $told.notices[0] "kind") -ceq "cli" -and (Get-HordeTestMember $told.notices[0] "what") -ceq "dirty") "and the warchief is told, as the kind cli and what dirty"
    $null = Follow $w $pol $t0.AddSeconds(120) $told $probe
    $null = Follow $w $pol $t0.AddSeconds(240) $told $probe
    Check ($told.notices.Count -eq 1) "and told ONCE, however many passes find it so"
    $body = Format-HordeServiceNoticeBody -Notice $told.notices[0]
    Check ($body -ceq "HORDE SERVICES - installed CLI needs attention`nthe installed CLI has changed files of its own, so it is not being kept current; a person commits or discards them`nSee it with: horde services status") "and the words told are fixed ones"
    $null = G $w.bin @("checkout", "--quiet", "--", "n.txt")
    $null = Follow $w $pol $t0.AddSeconds(360) $told $probe
    Check ((Head $w) -ceq $tip) "once the edit is gone, the clone moves on the next pass"
    [System.IO.File]::WriteAllText((Join-Path $w.bin "n.txt"), "again")
    $tip2 = Push-Commit $w $okScript
    $null = Follow $w $pol $t0.AddSeconds(720) $told $probe
    Check ($told.notices.Count -eq 2) "and a dirty clone later is told again: being in order forgot the first telling"

    # A person mends it by hand (the clone is then ON origin/main): what was told is over.
    $w = New-World "c2"
    $pol = New-Policy $w
    $told = New-Told
    $null = Push-Commit $w $okScript
    [System.IO.File]::WriteAllText((Join-Path $w.bin "n.txt"), "my own edit")
    $null = Follow $w $pol $t0 $told $probe
    $null = G $w.bin @("checkout", "--quiet", "--", "n.txt")
    $null = G $w.bin @("merge", "--ff-only", "--quiet", "origin/main")
    $null = Follow $w $pol $t0.AddSeconds(120) $told $probe -NoFetch
    $null = Push-Commit $w $okScript
    [System.IO.File]::WriteAllText((Join-Path $w.bin "n.txt"), "edit again")
    $null = Follow $w $pol $t0.AddSeconds(500) $told $probe
    Check ($told.notices.Count -eq 2) "a clone a person brought up to date by hand has forgotten the old telling: the next trouble is told"

    Write-Host ""
    Write-Host "--- IV. on another branch, or detached: never moved ---" -ForegroundColor Cyan
    $w = New-World "d"
    $pol = New-Policy $w
    $told = New-Told
    $null = Push-Commit $w $okScript
    $null = G $w.bin @("checkout", "--quiet", "-b", "feature/mine")
    $before = Head $w
    $lines = Follow $w $pol $t0 $told $probe
    Check ((Head $w) -ceq $before -and (G $w.bin @("symbolic-ref", "--short", "HEAD")) -ceq "feature/mine") "a clone on a feature branch is not moved and stays on it"
    Check ($told.notices.Count -eq 1 -and $told.notices[0].what -ceq "branch") "and the warchief is told, what branch"
    $null = G $w.bin @("checkout", "--quiet", "--detach")
    $null = Follow $w $pol $t0.AddSeconds(120) $told $probe
    Check ((Head $w) -ceq $before) "a detached clone is not moved either"
    Check ($told.notices.Count -eq 1) "and the same trouble is not told twice"

    Write-Host ""
    Write-Host "--- V. diverged: never merged, reset or rebased ---" -ForegroundColor Cyan
    $w = New-World "e"
    $pol = New-Policy $w
    $told = New-Told
    [System.IO.File]::WriteAllText((Join-Path $w.bin "mine.txt"), "local work")
    $null = G $w.bin @("add", "mine.txt")
    $null = G $w.bin @("commit", "--quiet", "-m", "local")
    $local = Head $w
    $null = Push-Commit $w $okScript
    $lines = Follow $w $pol $t0 $told $probe
    Check ((Head $w) -ceq $local) "a clone holding a commit origin/main lacks, while origin/main moved, is left exactly as it is"
    Check ($told.notices.Count -eq 1 -and $told.notices[0].what -ceq "diverged") "and the warchief is told, what diverged"
    Check ((Said $lines) -like "*installed CLI: diverged*") "and the pass says so"
    $w3 = New-World "e2"
    $pol3 = New-Policy $w3
    $told3 = New-Told
    [System.IO.File]::WriteAllText((Join-Path $w3.bin "mine.txt"), "local work")
    $null = G $w3.bin @("add", "mine.txt")
    $null = G $w3.bin @("commit", "--quiet", "-m", "local")
    $local3 = Head $w3
    $null = Follow $w3 $pol3 $t0 $told3 $probe
    Check ((Head $w3) -ceq $local3 -and $told3.notices.Count -eq 1 -and (Get-HordeTestMember $told3.notices[0] "what") -ceq "ahead") "a clone only AHEAD of origin/main is not moved either, and is told as ahead, not diverged"

    Write-Host ""
    Write-Host "--- VI. an update that does not load is put back, and not tried again ---" -ForegroundColor Cyan
    $w = New-World "f"
    $pol = New-Policy $w
    $told = New-Told
    $good = Head $w
    $bad = Push-Commit $w "exit 3"
    $lines = Follow $w $pol $t0 $told
    Check ((Head $w) -ceq $good) "with the real probe: a horde.ps1 that exits 3 fails horde version, and the clone is put back on the revision it was on"
    Check ((Said $lines) -like ("*" + $bad.Substring(0, 9) + " did not load when tried*the clone was not moved*")) "and the pass says which revision did not load, and that the clone was not moved"
    Check ($told.notices.Count -eq 1 -and $told.notices[0].what -ceq "failed") "and the warchief is told, what failed"
    Check ((G $w.bin @("status", "--porcelain", "--untracked-files=no")) -ceq "" -and (G $w.bin @("symbolic-ref", "--short", "HEAD")) -ceq "main") "and the clone is clean and still on main"
    $probed.Clear()
    $counting = { param($Path, $Policy) [void]$probed.Add($Path); return [pscustomobject]@{ ok = $false; detail = "no" } }.GetNewClosure()
    $null = Follow $w $pol $t0.AddSeconds(400) $told $counting
    Check ($probed.Count -eq 0 -and (Head $w) -ceq $good -and $told.notices.Count -eq 1) "the failed revision is not tried again, nor told again, while origin/main is still on it"
    $fixed = Push-Commit $w $okScript
    $null = Follow $w $pol $t0.AddSeconds(800) $told
    Check ((Head $w) -ceq $fixed) "once origin/main moves on to a revision that loads, the clone follows"
    $w = New-World "f2"
    $pol = New-Policy $w
    $told = New-Told
    $good = Head $w
    $null = Push-Commit $w $okScript
    $throwing = { param($Path, $Policy) throw "the shell would not start" }
    $lines = Follow $w $pol $t0 $told $throwing
    Check ((Head $w) -ceq $good -and $told.notices.Count -eq 1 -and $told.notices[0].what -ceq "failed") "a probe that throws is a failed load too: put back, and told"
    $w = New-World "f3"
    $pol = New-Policy $w
    $told = New-Told
    $good = Head $w
    $null = Push-Commit $w $okScript
    $silent = { param($Path, $Policy) return $null }
    $null = Follow $w $pol $t0 $told $silent
    Check ((Head $w) -ceq $good) "a probe that answers nothing is not a proof: put back"

    Write-Host ""
    Write-Host "--- VI-b. a revision is tried beside the clone before the clone moves ---" -ForegroundColor Cyan
    $w = New-World "t"
    $pol = New-Policy $w
    $told = New-Told
    $tip = Push-Commit $w $okScript
    $seen = New-Object System.Collections.ArrayList
    $recording = { param($Path, $Policy) [void]$seen.Add($Path); return [pscustomobject]@{ ok = $true; detail = "" } }.GetNewClosure()
    $null = Follow $w $pol $t0 $told $recording
    Check ($seen.Count -eq 2 -and $seen[0] -cne $w.bin -and $seen[1] -ceq $w.bin) "the first proof is made in a folder of its own, and the second, as a backstop, in the clone"
    Check (-not [System.IO.Directory]::Exists($seen[0]) -and -not [System.IO.File]::Exists($seen[0] + ".zip")) "and the folder it tried in is gone"
    $w = New-World "t2"
    $pol = New-Policy $w
    $told = New-Told
    $good = Head $w
    $null = Push-Commit $w $okScript
    $seen = New-Object System.Collections.ArrayList
    $refusing = { param($Path, $Policy) [void]$seen.Add($Path); return [pscustomobject]@{ ok = $false; detail = "no" } }.GetNewClosure()
    $null = Follow $w $pol $t0 $told $refusing
    Check ($seen.Count -eq 1 -and $seen[0] -cne $w.bin -and (Head $w) -ceq $good) "a revision that fails its first proof is never put in the clone: the clone itself is not even probed"
    $null = Push-Commit $w $okScript
    $null = Follow $w $pol $t0.AddSeconds(400) $told $refusing
    Check ($told.notices.Count -eq 2) "and a second, different bad revision is told again"
    $w = New-World "t3"
    $pol = New-Policy $w
    $told = New-Told
    $null = Push-Commit $w $okScript
    $null = Follow $w $pol $t0 $told
    Check ((Head $w) -ceq (G $w.origin @("rev-parse", "main"))) "with the real probe (horde version of the stub) a good revision is let in"

    Write-Host ""
    Write-Host "--- VI-c. the backstop puts the clone back without discarding a person's edit ---" -ForegroundColor Cyan
    $w = New-World "k"
    $pol = New-Policy $w
    $told = New-Told
    $good = Head $w
    $null = Push-Commit $w $okScript
    $bin = $w.bin
    $late = { param($Path, $Policy) if ($Path -ceq $bin) { [System.IO.File]::WriteAllText((Join-Path $bin "keep.txt"), "my edit in the window"); return [pscustomobject]@{ ok = $false; detail = "broke" } }; return [pscustomobject]@{ ok = $true; detail = "" } }.GetNewClosure()
    $null = Follow $w $pol $t0 $told $late
    Check ((Head $w) -ceq $good -and [System.IO.File]::ReadAllText((Join-Path $w.bin "keep.txt")) -ceq "my edit in the window") "a clone put back after a failed backstop keeps an edit a person made in the window"
    Check ($told.notices.Count -eq 1 -and (Get-HordeTestMember $told.notices[0] "what") -ceq "failed") "and the warchief is told, what failed"

    Write-Host ""
    Write-Host "--- VI-d. a clone that cannot be put back stays reported as broken ---" -ForegroundColor Cyan
    $w = New-World "u"
    $pol = New-Policy $w
    $told = New-Told
    $good = Head $w
    $tipU = Push-Commit $w $okScript
    $bin = $w.bin
    $mode = @{ broken = $true }
    $stuckProbe = { param($Path, $Policy) if ($Path -ceq $bin) { if ($mode.broken) { [System.IO.File]::WriteAllText((Join-Path $bin "n.txt"), "my edit in a file the update changed"); return [pscustomobject]@{ ok = $false; detail = "broke" } } }; return [pscustomobject]@{ ok = $true; detail = "" } }.GetNewClosure()
    $lines = Follow $w $pol $t0 $told $stuckProbe
    Check ((Head $w) -ceq $tipU -and [System.IO.File]::ReadAllText((Join-Path $w.bin "n.txt")) -ceq "my edit in a file the update changed") "when the edit is in a file the update changed, reset --keep refuses: the clone stays where it is and the edit is not discarded"
    Check ($told.notices.Count -eq 1 -and (Get-HordeTestMember $told.notices[0] "what") -ceq "stuck") "and the warchief is told, what stuck"
    $row = Get-HordeInstalledCliStatus -HordeHome $w.home -Policy $pol
    Check ($row.state -ceq "blocked" -and $row.said -like "stuck:*") "status does not call it current: it is blocked, stuck"
    $lines = Follow $w $pol $t0.AddSeconds(120) $told $stuckProbe -NoFetch
    Check ((Get-HordeInstalledCliStatus -HordeHome $w.home -Policy $pol).state -ceq "blocked" -and $told.notices.Count -eq 1 -and @($lines).Count -eq 0) "the next pass finds it still broken, says nothing new, tells nothing again, and it is still not current"
    $mode.broken = $false
    $lines = Follow $w $pol $t0.AddSeconds(240) $told $stuckProbe -NoFetch
    Check ((Said $lines) -like "*loads now*" -and (Get-HordeInstalledCliStatus -HordeHome $w.home -Policy $pol).state -ceq "current") "once it loads again it is current"

    Write-Host ""
    Write-Host "--- VI-e. a move that fails for a reason of the moment is tried again ---" -ForegroundColor Cyan
    $w = New-World "v"
    $pol = New-Policy $w
    $told = New-Told
    $good = Head $w
    $tipV = Push-Commit $w $okScript
    $lock = Join-Path $w.bin ".git\index.lock"
    [System.IO.File]::WriteAllText($lock, "")
    $lines = Follow $w $pol $t0 $told $probe
    Check ((Head $w) -ceq $good -and $told.notices.Count -eq 1 -and (Get-HordeTestMember $told.notices[0] "what") -ceq "apply") "a merge that cannot complete (an index lock) leaves the clone as it was, and is told as apply"
    Check ((Read-HordeInstalledCliState -HordeHome $w.home).failedTip -ceq "") "and pins nothing: the revision is not marked as failed"
    $row = Get-HordeInstalledCliStatus -HordeHome $w.home -Policy $pol
    Check ($row.state -ceq "behind" -and $row.said -notlike "*did not load*") "and status does not say it did not load"
    $null = Follow $w $pol $t0.AddSeconds(120) $told $probe -NoFetch
    Check ($told.notices.Count -eq 1) "the same trouble is not told twice"
    [System.IO.File]::Delete($lock)
    $null = Follow $w $pol $t0.AddSeconds(240) $told $probe -NoFetch
    Check ((Head $w) -ceq $tipV) "and with the lock gone the next pass moves the clone"

    Write-Host ""
    Write-Host "--- VII. telling that did not get through is tried again; off and absent are quiet ---" -ForegroundColor Cyan
    $w = New-World "g"
    $pol = New-Policy $w
    $told = New-Told
    $told.ok = $false
    [System.IO.File]::WriteAllText((Join-Path $w.bin "n.txt"), "edit")
    $null = Push-Commit $w $okScript
    $lines = Follow $w $pol $t0 $told $probe
    Check ($told.notices.Count -eq 0 -and (Said $lines) -like "*waits untold*") "a tell nobody took is not counted as told, and the line says it waits"
    $told.ok = $true
    $null = Follow $w $pol $t0.AddSeconds(120) $told $probe
    Check ($told.notices.Count -eq 1) "and is tried again next pass, and goes through"
    $w = New-World "h"
    $polOff = New-Policy $w -Follow $false
    $before = Head $w
    $tipH = Push-Commit $w $okScript
    $lines = Follow $w $polOff $t0 (New-Told) $probe
    Check (@($lines).Count -eq 0 -and (Head $w) -ceq $before) "with followInstalledCli false the clone is not even asked"
    $polGone = New-Policy $w
    $polGone.installedCliFolder = Join-Path $work "nothing-installed-here"
    $lines = Follow $w $polGone $t0 (New-Told) $probe
    Check (@($lines).Count -eq 0) "with no installed CLI at the path the pass is quiet and throws nothing"
    $inner = Join-Path $w.bin "sub"
    [void][System.IO.Directory]::CreateDirectory($inner)
    $polInner = New-Policy $w
    $polInner.installedCliFolder = $inner
    $lines = Follow $w $polInner $t0 (New-Told) $probe
    Check ((Said $lines) -like "*left alone*not the top of a checkout of its own*" -and (Head $w) -ceq $before) "a folder inside some other repository is never acted on: git would walk up to the repository above it"

    Write-Host ""
    Write-Host "--- VIII. status: the installed CLI's revision, and whether it is behind ---" -ForegroundColor Cyan
    $w = New-World "s"
    $pol = New-Policy $w
    $cur = Head $w
    $null = G $w.bin @("update-ref", "-d", "refs/remotes/origin/main")
    $row = Get-HordeInstalledCliStatus -HordeHome $w.home -Policy $pol
    Check ($row.state -ceq "unknown" -and $row.said -like "*has not been fetched*") "before the remote was fetched into the clone status cannot judge, and says so"
    $null = G $w.bin @("fetch", "--quiet", "origin", "+refs/heads/main:refs/remotes/origin/main")
    $row = Get-HordeInstalledCliStatus -HordeHome $w.home -Policy $pol
    Check ($row.state -ceq "current" -and $row.sha -ceq $cur -and $row.behind -eq 0) "on origin/main: current, its sha, not behind"
    $t1 = Push-Commit $w $okScript; $t2 = Push-Commit $w $okScript
    $null = G $w.bin @("fetch", "--quiet", "origin", "+refs/heads/main:refs/remotes/origin/main")
    $row = Get-HordeInstalledCliStatus -HordeHome $w.home -Policy $pol
    Check ($row.state -ceq "behind" -and $row.behind -eq 2 -and $row.sha -ceq $cur -and $row.wanted -ceq $t2) "two commits behind: state behind, the count, its own sha and the wanted one"
    $text = (Format-HordeInstalledCliStatus -Row $row) -join "`n"
    Check ($text -like "*installed CLI: BEHIND*is on " + $cur.Substring(0, 9) + ", origin/main was " + $t2.Substring(0, 9) + " (2 behind)*") "and the human line shows both and how far"
    $rep = [pscustomobject]@{ home = $w.home; supervisor = [pscustomobject]@{ state = "running" }; installedCli = $row; definitions = [pscustomobject]@{ state = "none"; path = "x"; findings = [string[]]@() }; settings = [pscustomobject]@{ state = "read"; path = "y"; findings = [string[]]@() }; services = @() }
    $rec = ConvertTo-HordeServiceStatusRecord -Report $rep
    $json = ConvertTo-Json -InputObject $rec -Depth 8 -Compress | ConvertFrom-Json
    Check ((Get-HordeTestMember $json "installedCli.sha") -ceq $cur -and (Get-HordeTestMember $json "installedCli.isBehind") -eq $true -and (Get-HordeTestMember $json "installedCli.behind") -eq 2) "and -Json carries the sha and isBehind"
    [System.IO.File]::WriteAllText((Join-Path $w.bin "n.txt"), "edit")
    $row = Get-HordeInstalledCliStatus -HordeHome $w.home -Policy $pol
    Check ($row.state -ceq "blocked" -and $row.said -like "dirty*") "a dirty clone behind origin/main is blocked, and status says why"
    $null = G $w.bin @("checkout", "--quiet", "--", "n.txt")
    $null = Follow $w $pol $t0 (New-Told) $probe -NoFetch
    $row = Get-HordeInstalledCliStatus -HordeHome $w.home -Policy $pol
    Check ($row.state -ceq "current" -and $row.sha -ceq $t2) "after a pass it is current again"
    Check ((Get-HordeInstalledCliStatus -HordeHome $w.home -Policy (New-Policy $w -Follow $false)).state -ceq "off") "switched off, status says off"
    $polGone = New-Policy $w; $polGone.installedCliFolder = Join-Path $work "nothing-installed-here"
    Check ((Get-HordeInstalledCliStatus -HordeHome $w.home -Policy $polGone).state -ceq "absent") "with nothing installed, status says absent"
    Check (-not [System.IO.File]::Exists((Get-HordeInstalledCliStatePath -HordeHome (Join-Path $work "never-followed")))) "status writes no state of its own: a home nothing followed in has none"

    Write-Host ""
    Write-Host "--- IX. a test's home never reaches the real installed CLI ---" -ForegroundColor Cyan
    $polDefault = New-Policy $w
    $polDefault.installedCliFolder = ""
    Check ((Get-HordeInstalledCliRefusal -HordeHome (Join-Path $env:TEMP "some-test-home") -Policy $polDefault) -like "*under the temp folder*") "a home under the temp folder with no folder set is refused: its default would be the person's own installed CLI"
    Check ((Get-HordeInstalledCliRefusal -HordeHome (Join-Path $env:TEMP "some-test-home") -Policy (New-Policy $w)) -ceq "") "but a test that names a throwaway clone is let follow it"
    Check ((Get-HordeInstalledCliRefusal -HordeHome "C:\horde-home-of-a-person" -Policy $polDefault) -ceq "") "and a real home follows the default"

    Write-Host ""
    Write-Host "--- X. the settings ---" -ForegroundColor Cyan
    $hs = Join-Path $work "settings-home"
    [void][System.IO.Directory]::CreateDirectory((Join-Path $hs "settings"))
    $set = Get-HordeServiceSettings -HordeHome $hs
    Check ($set.values.followInstalledCli -eq $true -and "" + $set.values.installedCliFolder -eq "") "the installed CLI is followed by default, at the bin clone"
    Check ((Get-HordeInstalledCliPath -Policy $set.values) -ceq [System.IO.Path]::Combine([System.Environment]::GetFolderPath("UserProfile"), "bin", "horde")) "and the default folder is bin\horde under the person's profile"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the installed CLI is fast-forwarded to main only when that is safe, proved to load and put back if not, told once when it cannot be moved, and shown in status"
