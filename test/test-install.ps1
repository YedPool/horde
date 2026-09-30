# DOES `horde install` WRITE A LAUNCHER THAT WORKS, AND NEVER DESTROY ONE IT DID NOT WRITE?
#
# The installer this replaces (YedPool/wezfleet install.ps1) rewrote its shim on every run, so a
# hand edit was silently reverted (wezfleet 2cfdacc), and nothing checked that the shim it wrote passed
# exit codes back. Every test here runs the real `horde install` as a separate process against a
# STAND-IN checkout copied into %TEMP%, and writes only into throwaway bin folders under %TEMP%. The
# real bin folder is never named as a target; the last section measures that it was left as it was.
#
# Each shim is then run the way callers run it: its path handed straight to the process API, which is
# how Bash and PowerShell start a .cmd file.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "cli\Install.ps1")

function Start-HordeTestProcess {
    # Run a program; returns { code; out; err }. Extra adds or, with a $null value, removes variables for
    # the child only. Not `2>&1`: on PowerShell 5.1 that turns a native command's stderr into an error.
    param([string]$File, [string]$Arguments, [hashtable]$Extra = @{}, [string]$WorkDir = "")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($WorkDir) { $psi.WorkingDirectory = $WorkDir }
    foreach ($k in $Extra.Keys) {
        if ($null -eq $Extra[$k]) { [void]$psi.EnvironmentVariables.Remove($k) } else { $psi.EnvironmentVariables[$k] = $Extra[$k] }
    }
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return [pscustomobject]@{ code = $p.ExitCode; out = $outTask.Result; err = $err }
}

function Invoke-HordeInstall {
    # `horde install <Arguments>` from the checkout at Checkout, run as a script runs it (-File).
    param([string]$Checkout, [string[]]$Arguments, [hashtable]$Extra = @{})
    $argText = (@($Arguments) | ForEach-Object { "`"" + $_ + "`"" }) -join " "
    return (Start-HordeTestProcess -File "powershell.exe" -Extra $Extra -Arguments ("-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $Checkout "horde.ps1") + "`" install " + $argText))
}

function Invoke-HordeShim {
    # Run a shim with these arguments, as Bash and PowerShell start a .cmd: its path is the program.
    param([string]$Shim, [string]$Arguments, [hashtable]$Extra = @{})
    return (Start-HordeTestProcess -File $Shim -Arguments $Arguments -Extra $Extra)
}

$scratch = Join-Path $env:TEMP ("horde-install-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $scratch | Out-Null

function New-HordeStandIn {
    # A copy of this checkout's CLI under the scratch folder, with a test command or two beside the
    # real ones. Kind: "checkout" gives it a .git folder, "worktree" a .git file as a linked worktree
    # has, "plain" neither.
    param([string]$Name, [string]$Kind = "checkout")
    $dir = Join-Path $scratch $Name
    New-Item -ItemType Directory -Path (Join-Path $dir "cli\commands") | Out-Null
    Copy-Item -LiteralPath (Join-Path $root "horde.ps1") -Destination $dir
    Copy-Item -LiteralPath (Join-Path $root "VERSION") -Destination $dir
    Copy-Item -Path (Join-Path $root "cli\*.ps1") -Destination (Join-Path $dir "cli")
    foreach ($c in @("help", "version", "install")) { Copy-Item -LiteralPath (Join-Path $root ("cli\commands\" + $c + ".ps1")) -Destination (Join-Path $dir "cli\commands") }
    foreach ($c in @("boom", "echo-args")) { Copy-Item -LiteralPath (Join-Path $root ("test\fixtures\cli\extra\" + $c + ".ps1")) -Destination (Join-Path $dir "cli\commands") }
    Copy-Item -LiteralPath (Join-Path $root "test\fixtures\install\rewrite-shim.ps1") -Destination (Join-Path $dir "cli\commands")
    # An empty .git folder is not a repository, so `horde version` reports the commit as unknown; what
    # install reads is only whether .git is a folder or a file.
    if ($Kind -eq "checkout") { New-Item -ItemType Directory -Path (Join-Path $dir ".git") | Out-Null }
    if ($Kind -eq "worktree") { [System.IO.File]::WriteAllText((Join-Path $dir ".git"), "gitdir: C:/nowhere/.git/worktrees/x`n") }
    return $dir
}

function New-HordeBin { param([string]$Name) return (Join-Path $scratch ("bin-" + $Name)) }

function Get-HordeBytes { param([string]$Path) return [System.IO.File]::ReadAllBytes($Path) }
function Test-HordeSameBytes { param([byte[]]$A, [byte[]]$B) return [bool]([System.Linq.Enumerable]::SequenceEqual($A, $B)) }

function Get-HordeSha256Hex {
    # The test's own hash, straight from .NET, so the header is checked against something the code
    # under test did not compute.
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return -join ($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString("x2") }) } finally { $sha.Dispose() }
}

function Set-HordeRehashedShim {
    # Rewrite a shim's body with Edit applied, then give it a header whose hash matches the new body -
    # what an older horde install's template looks like: ours, intact, and different.
    param([string]$Path, [scriptblock]$Edit)
    $text = [System.IO.File]::ReadAllText($Path)
    $nl = $text.IndexOf("`n")
    $body = & $Edit ($text.Substring($nl + 1))
    $hash = Get-HordeSha256Hex -Bytes ([System.Text.Encoding]::ASCII.GetBytes($body))
    [System.IO.File]::WriteAllText($Path, ("@rem horde install shim - sha256=" + $hash + " of the lines below`r`n" + $body), [System.Text.Encoding]::ASCII)
}

# The real default bin folder, measured before anything runs and again at the end. Derived from the
# environment, never written out (CONTRIBUTING 11).
$realShim = Join-Path (Get-HordeDefaultBinDir) "horde.cmd"
function Get-HordeFileState {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return "absent" }
    $i = Get-Item -LiteralPath $Path -Force
    if ($i.PSIsContainer) { return "folder" }
    return ((Get-HordeSha256Hex -Bytes ([System.IO.File]::ReadAllBytes($Path))) + " " + $i.LastWriteTimeUtc.Ticks)
}
$realBefore = Get-HordeFileState -Path $realShim

$version = "$(Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1)".Trim()

try {
    Write-Host ""
    Write-Host "--- install writes a shim, and the shim runs horde ---" -ForegroundColor Cyan

    $main = New-HordeStandIn -Name "main"
    $bin = New-HordeBin -Name "main"
    $shim = Join-Path $bin "horde.cmd"
    Check (-not (Test-Path -LiteralPath $bin)) "CONTROL: the bin folder does not exist before install"
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-BinDir", $bin)
    Check ($r.code -eq 0 -and $r.out -like ("*created " + $shim + "*")) ("install into a new bin folder creates horde.cmd there and exits 0 (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    Check (Test-Path -LiteralPath $shim -PathType Leaf) "the shim file exists where install said"

    $bytes = Get-HordeBytes -Path $shim
    Check (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0) "the shim is ASCII"
    $lfs = 0; $bare = 0
    for ($i = 0; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -eq 10) { $lfs++; if ($i -eq 0 -or $bytes[$i - 1] -ne 13) { $bare++ } } }
    Check ($lfs -gt 5 -and $bare -eq 0) "every line of the shim ends in CRLF, the line ending cmd.exe is written for"
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    $nl = $text.IndexOf("`n")
    $m = [regex]::Match($text.Substring(0, $nl), '\A@rem horde install shim - sha256=([0-9a-f]{64}) ')
    Check $m.Success "the shim's first line is horde install's header"
    $rest = New-Object byte[] ($bytes.Length - $nl - 1); [Array]::Copy($bytes, $nl + 1, $rest, 0, $rest.Length)
    Check ($m.Success -and $m.Groups[1].Value -eq (Get-HordeSha256Hex -Bytes $rest)) "the header's hash is the SHA-256 of every line below it"
    $launch = @($text -split "`r`n" | Where-Object { $_ -like '*-File "*' })
    Check ($launch.Count -eq 1 -and $launch[0] -like ('*-File "' + (Join-Path $main "horde.ps1") + '" %* & call exit /b %%ERRORLEVEL%%')) "the shim launches the horde.ps1 of the checkout install ran from, in one line"
    Check ($launch.Count -eq 1 -and $launch[0].StartsWith('"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" ')) "it runs powershell.exe by full path, never one found in the current folder"
    Check ($text -like "*A NEWLINE CANNOT PASS THROUGH THIS FILE*") "the shim states that a newline cannot pass through it"

    $r = Invoke-HordeShim -Shim $shim -Arguments "version"
    Check ($r.code -eq 0 -and $r.out -like ("horde " + $version + "*")) ("horde version through the shim prints the version and exits 0 (got " + $r.code + ": " + $r.out.Trim() + ")")
    $r = Invoke-HordeShim -Shim $shim -Arguments "version -Json"
    $j = $null; try { $j = $r.out | ConvertFrom-Json } catch { }
    Check ($r.code -eq 0 -and $null -ne $j -and $j.version -eq $version) "arguments pass through the shim: version -Json gives JSON"
    $r = Invoke-HordeShim -Shim $shim -Arguments "boom"
    Check ($r.code -eq 1 -and $r.err -like "*boom failed on purpose*") ("a failing command exits 1 through the shim (got " + $r.code + ")")
    $r = Invoke-HordeShim -Shim $shim -Arguments "no-such-command"
    Check ($r.code -eq 2 -and $r.err -like "*unknown command*") "an unknown command exits 2 through the shim"
    $r = Start-HordeTestProcess -File "powershell.exe" -Arguments ("-NoProfile -ExecutionPolicy Bypass -Command `"& '" + $shim + "' no-such-command; exit `$LASTEXITCODE`"")
    Check ($r.code -eq 2) ("called from PowerShell by its path, the shim's exit code reaches `$LASTEXITCODE (got " + $r.code + ")")

    Write-Host ""
    Write-Host "--- the shim's limits, measured ---" -ForegroundColor Cyan

    # The documented newline limit is real: cmd.exe drops everything after the first newline. The
    # control is the same argument handed to horde.ps1 directly, which arrives whole.
    $two = "`"first-line`nsecond-line`""
    $direct = Start-HordeTestProcess -File "powershell.exe" -Arguments ("-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $main "horde.ps1") + "`" echo-args " + $two)
    Check ($direct.code -eq 0 -and $direct.out -like "*first-line*second-line*") "CONTROL: a two-line argument given to horde.ps1 directly arrives whole"
    $viaShim = Invoke-HordeShim -Shim $shim -Arguments ("echo-args " + $two)
    Write-Host ("         through the shim: " + $viaShim.out.Trim()) -ForegroundColor DarkGray
    Check ($viaShim.out -like "*first-line*" -and $viaShim.out -notlike "*second-line*") "a two-line argument through the shim arrives as its first line only"
    $cut = Invoke-HordeShim -Shim $shim -Arguments ("no-such-command " + $two)
    Check ($cut.code -eq 2) ("and when the cut falls inside quotes, the exit code still passes through (got " + $cut.code + ")")

    # A shim rewritten while a command it launched is running must not run the new file's tail. The
    # command below appends `echo INJECTED-TAIL` and `exit /b 9` to its own shim before returning.
    $rwBin = New-HordeBin -Name "rewrite"
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-BinDir", $rwBin)
    $rwShim = Join-Path $rwBin "horde.cmd"
    $r = Invoke-HordeShim -Shim $rwShim -Arguments "rewrite-shim" -Extra @{ HORDE_TEST_SHIM = $rwShim }
    Check ((Get-HordeBytes -Path $rwShim).Length -gt $bytes.Length) "CONTROL: the command really rewrote its shim while running"
    Check ($r.code -eq 0 -and $r.out -notlike "*INJECTED-TAIL*") ("lines added to the shim while its command runs are never executed, and the command's exit code stands (got " + $r.code + ": " + $r.out.Trim() + ")")
    # CONTROL for that check: the same launch line without `& call exit /b ...`, as a plain last line.
    # cmd.exe goes back to the file after the program exits, and runs the appended tail.
    $plainShim = Join-Path (New-HordeBin -Name "plain-last-line") "horde.cmd"
    New-Item -ItemType Directory -Path (Split-Path -Parent $plainShim) | Out-Null
    [System.IO.File]::WriteAllText($plainShim, ("@echo off`r`n" + ($launch[0] -replace ' & call exit /b %%ERRORLEVEL%%$', '') + "`r`n"), [System.Text.Encoding]::ASCII)
    $r = Invoke-HordeShim -Shim $plainShim -Arguments "rewrite-shim" -Extra @{ HORDE_TEST_SHIM = $plainShim }
    Check ($r.out -like "*INJECTED-TAIL*" -and $r.code -eq 9) ("CONTROL: with the launch as a plain last line, the tail added mid-run DOES run (got " + $r.code + ")")

    Write-Host ""
    Write-Host "--- re-running install ---" -ForegroundColor Cyan

    $past = [datetime]::new(2020, 1, 2, 3, 4, 5, [System.DateTimeKind]::Utc)
    [System.IO.File]::SetLastWriteTimeUtc($shim, $past)
    $before = Get-HordeBytes -Path $shim
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-BinDir", $bin)
    Check ($r.code -eq 0 -and $r.out -like "*unchanged*") ("re-running install on a current shim says unchanged and exits 0 (got " + $r.code + ": " + $r.out.Trim() + ")")
    Check ((Test-HordeSameBytes (Get-HordeBytes -Path $shim) $before) -and [System.IO.File]::GetLastWriteTimeUtc($shim) -eq $past) "and changes nothing, not even the file's timestamp"

    # An older template: ours, intact, for this checkout, and different. Replaced without -Force.
    Set-HordeRehashedShim -Path $shim -Edit { param($b) $b.Replace("rem A NEWLINE", "rem AN OLDER NEWLINE") }
    Check ((Read-HordeShim -Path $shim).state -eq "ours") "CONTROL: a rehashed older shim reads as horde install's own, intact"
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-BinDir", $bin)
    Check ($r.code -eq 0 -and $r.out -like ("*updated " + $shim + "*") -and (Test-HordeSameBytes (Get-HordeBytes -Path $shim) $before)) ("install updates its own older shim for this checkout without -Force (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")

    Write-Host ""
    Write-Host "--- install never replaces a file it cannot account for, unless forced ---" -ForegroundColor Cyan

    # Edited by hand: the header is ours and the lines are not what it hashed.
    [System.IO.File]::AppendAllText($shim, "rem a line added by hand`r`n")
    $edited = Get-HordeBytes -Path $shim
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-BinDir", $bin)
    Check ($r.code -eq 1 -and $r.err -like "*edited by hand*" -and $r.err -like "*-Force*") ("a shim edited by hand is refused, exit 1, naming the reason and -Force (got " + $r.code + ": " + $r.err.Trim() + ")")
    Check (Test-HordeSameBytes (Get-HordeBytes -Path $shim) $edited) "and the edited shim is left exactly as it was"
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-BinDir", $bin, "-Force")
    Check ($r.code -eq 0 -and (Test-HordeSameBytes (Get-HordeBytes -Path $shim) $before)) "with -Force, the edited shim is replaced by a current one"

    # Not ours at all.
    $foreignText = "@echo off`r`necho somebody else's horde`r`n"
    [System.IO.File]::WriteAllText($shim, $foreignText, [System.Text.Encoding]::ASCII)
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-BinDir", $bin)
    Check ($r.code -eq 1 -and $r.err -like "*not written by horde install*") ("a horde.cmd install did not write is refused, exit 1 (got " + $r.code + ": " + $r.err.Trim() + ")")
    Check ([System.IO.File]::ReadAllText($shim) -eq $foreignText) "and it is left exactly as it was"
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-BinDir", $bin, "-DryRun")
    Check ($r.code -eq 1 -and [System.IO.File]::ReadAllText($shim) -eq $foreignText) "a dry run against it reports the same refusal, exit 1, and writes nothing"
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-BinDir", $bin, "-Force")
    Check ($r.code -eq 0 -and (Test-HordeSameBytes (Get-HordeBytes -Path $shim) $before)) "with -Force, a foreign horde.cmd is replaced"

    # Ours, intact, and launching a different checkout: moving the fleet to another horde is asked for.
    $other = New-HordeStandIn -Name "other"
    $r = Invoke-HordeInstall -Checkout $other -Arguments @("-BinDir", $bin)
    Check ($r.code -eq 1 -and $r.err -like ("*launches another checkout, " + (Join-Path $main "horde.ps1") + "*")) ("a shim launching another checkout is refused, naming that checkout (got " + $r.code + ": " + $r.err.Trim() + ")")
    Check (Test-HordeSameBytes (Get-HordeBytes -Path $shim) $before) "and it still launches the first checkout"
    $r = Invoke-HordeInstall -Checkout $other -Arguments @("-BinDir", $bin, "-Force")
    Check ($r.code -eq 0 -and $r.out -like ("*replaces a shim that launched " + (Join-Path $main "horde.ps1") + "*") -and (Read-HordeShim -Path $shim).target -eq (Join-Path $other "horde.ps1")) "with -Force it is re-pointed, and install says which checkout it replaced"

    # A folder named horde.cmd is never replaced.
    $dirBin = New-HordeBin -Name "folder"
    New-Item -ItemType Directory -Path (Join-Path $dirBin "horde.cmd") | Out-Null
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-BinDir", $dirBin, "-Force")
    Check ($r.code -eq 1 -and $r.err -like "*is a folder*" -and (Test-Path -LiteralPath (Join-Path $dirBin "horde.cmd") -PathType Container)) "a folder named horde.cmd is refused even with -Force, and left in place"

    Write-Host ""
    Write-Host "--- which checkout may install ---" -ForegroundColor Cyan

    $wt = New-HordeStandIn -Name "worktree" -Kind "worktree"
    $wtBin = New-HordeBin -Name "worktree"
    $r = Invoke-HordeInstall -Checkout $wt -Arguments @("-BinDir", $wtBin)
    Check ($r.code -eq 1 -and $r.err -like "*linked worktree*" -and $r.err -like "*-AllowWorktree*") ("install from a linked worktree is refused, exit 1, naming -AllowWorktree (got " + $r.code + ": " + $r.err.Trim() + ")")
    Check (-not (Test-Path -LiteralPath (Join-Path $wtBin "horde.cmd"))) "and writes no shim"
    $r = Invoke-HordeInstall -Checkout $wt -Arguments @("-BinDir", $wtBin, "-AllowWorktree")
    Check ($r.code -eq 0 -and (Read-HordeShim -Path (Join-Path $wtBin "horde.cmd")).target -eq (Join-Path $wt "horde.ps1")) "with -AllowWorktree, a worktree installs a shim that launches it"
    $plain = New-HordeStandIn -Name "plain" -Kind "plain"
    $r = Invoke-HordeInstall -Checkout $plain -Arguments @("-BinDir", (New-HordeBin -Name "plain"))
    Check ($r.code -eq 0) "a copy with no .git at all installs, as an exported copy would"

    # A path cmd.exe would misread. "%" is escaped and works; the rest are refused before writing.
    $pct = New-HordeStandIn -Name "horde 100% & co"
    $pctBin = New-HordeBin -Name "percent"
    $r = Invoke-HordeInstall -Checkout $pct -Arguments @("-BinDir", $pctBin)
    Check ($r.code -eq 0 -and [System.IO.File]::ReadAllText((Join-Path $pctBin "horde.cmd")) -like "*horde 100%% & co*") "CONTROL: a checkout path with % and & is written with the % doubled"
    $r = Invoke-HordeShim -Shim (Join-Path $pctBin "horde.cmd") -Arguments "version"
    Check ($r.code -eq 0 -and $r.out -like ("horde " + $version + "*")) ("and the shim for a path with %, & and spaces runs horde (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    $bang = New-HordeStandIn -Name "horde!bang"
    $r = Invoke-HordeInstall -Checkout $bang -Arguments @("-BinDir", (New-HordeBin -Name "bang"))
    Check ($r.code -eq 1 -and $r.err -like "*delayed expansion*" -and -not (Test-Path -LiteralPath (New-HordeBin -Name "bang"))) "a checkout path with ! is refused before anything is written"
    $accent = New-HordeStandIn -Name ("horde-caf" + [char]0xE9)
    $r = Invoke-HordeInstall -Checkout $accent -Arguments @("-BinDir", (New-HordeBin -Name "accent"))
    Check ($r.code -eq 1 -and $r.err -like "*printable ASCII*" -and -not (Test-Path -LiteralPath (New-HordeBin -Name "accent"))) "a checkout path outside ASCII is refused before anything is written"

    Write-Host ""
    Write-Host "--- -DryRun, -BinDir and PATH ---" -ForegroundColor Cyan

    $dryBin = New-HordeBin -Name "dry"
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-BinDir", $dryBin, "-DryRun")
    Check ($r.code -eq 0 -and $r.out -like ("*would create " + (Join-Path $dryBin "horde.cmd") + "*")) ("a dry run says what it would create (got " + $r.code + ": " + $r.out.Trim() + ")")
    Check (-not (Test-Path -LiteralPath $dryBin)) "and creates nothing, not even the bin folder"
    Set-HordeRehashedShim -Path $shim -Edit { param($b) $b.Replace("rem A NEWLINE", "rem AN OLDER NEWLINE") }
    $older = Get-HordeBytes -Path $shim
    $r = Invoke-HordeInstall -Checkout $other -Arguments @("-BinDir", $bin, "-DryRun")
    Check ($r.code -eq 0 -and $r.out -like "*would update*" -and (Test-HordeSameBytes (Get-HordeBytes -Path $shim) $older)) "a dry run over an older shim says it would update it, and leaves it as it was"

    # The default: %USERPROFILE%\bin, with USERPROFILE pointed at a scratch folder for the child only.
    $home2 = Join-Path $scratch "profile"
    New-Item -ItemType Directory -Path $home2 | Out-Null
    $r = Invoke-HordeInstall -Checkout $main -Arguments @() -Extra @{ USERPROFILE = $home2 }
    Check ($r.code -eq 0 -and (Read-HordeShim -Path (Join-Path $home2 "bin\horde.cmd")).target -eq (Join-Path $main "horde.ps1")) "with no -BinDir, the shim goes to the bin folder under USERPROFILE"
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-DryRun") -Extra @{ USERPROFILE = $null }
    Check ($r.code -eq 1 -and $r.err -like "*USERPROFILE is not set*") "with no -BinDir and no USERPROFILE, install refuses rather than guess a folder"

    # A relative -BinDir is taken from PowerShell's location, which is not the process's directory here.
    $loc = Join-Path $scratch "location"
    New-Item -ItemType Directory -Path $loc | Out-Null
    $r = Start-HordeTestProcess -File "powershell.exe" -WorkDir $scratch -Arguments ("-NoProfile -ExecutionPolicy Bypass -Command `"Set-Location -LiteralPath '" + $loc + "'; & '" + (Join-Path $main "horde.ps1") + "' install -BinDir rel-bin; exit `$LASTEXITCODE`"")
    Check ($r.code -eq 0 -and (Test-Path -LiteralPath (Join-Path $loc "rel-bin\horde.cmd")) -and -not (Test-Path -LiteralPath (Join-Path $scratch "rel-bin"))) "a relative -BinDir is resolved from PowerShell's current location"

    $pathBin = New-HordeBin -Name "on-path"
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-BinDir", $pathBin) -Extra @{ Path = ($env:SystemRoot + "\System32") }
    Check ($r.code -eq 0 -and $r.out -like "*is not on PATH*") "install warns when the bin folder is not on PATH"
    $r = Invoke-HordeInstall -Checkout $main -Arguments @("-BinDir", $pathBin) -Extra @{ Path = ($pathBin + "\;" + $env:SystemRoot + "\System32") }
    Check ($r.code -eq 0 -and $r.out -notlike "*not on PATH*") "and does not warn when it is, trailing backslash or not"
}
finally {
    if ((Split-Path -Leaf $scratch) -match '^horde-install-test-[0-9a-f]{32}$') { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "--- and nothing outside the scratch folder was touched ---" -ForegroundColor Cyan
Check (-not (Test-Path -LiteralPath $scratch)) "the scratch folder, with every bin folder the tests made, is removed"
Check ((Get-HordeFileState -Path $realShim) -eq $realBefore) ("the real default bin folder's horde.cmd is exactly as it was (" + $realBefore.Split(" ")[0] + ")")

Complete-HordeSuite -Success "horde install writes a working launcher, keeps it current, and never replaces one it cannot account for"
