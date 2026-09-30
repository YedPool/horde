# What `horde install` does: write a horde.cmd launcher into a bin folder, so that `horde` on PATH
# reaches the checkout the install was run from. cli\commands\install.ps1 declares the command and
# loads this file when it runs; the logic lives here so test\test-install.ps1 can reach each piece.
#
# THE SHIM POINTS AT A CHECKOUT; IT COPIES NOTHING. The installer this replaces (YedPool/wezfleet
# install.ps1) copied the module into bin and wrote a shim beside it, so every `git pull` needed a
# re-install and an installed copy once lacked a file the copy list forgot (wezfleet 561466d, LICENSE).
# Pointing at the checkout means pulling updates horde. The price is that the checkout install ran
# from BECOMES the fleet's horde, so a linked worktree is refused unless -AllowWorktree says so: a
# temporary worktree that installed itself would be deleted out from under every session.
#
# NO SILENT OVERWRITE. The old installer rewrote bin\wezfleet.cmd from a template on every run, and
# its own comment records that a hand-edited shim "would have been silently reverted" by the next
# install (wezfleet 2cfdacc). Here the first line of every shim written is a header carrying the
# SHA-256 of the lines below it. A file without that header was not written by horde install; a file
# whose lines no longer match the hash was edited by hand; a shim that points at another checkout
# belongs to that checkout. All three are refused unless -Force, and the refusal says which it is.
# Re-running against a current shim changes nothing, not even its timestamp.

Set-StrictMode -Off

# The header's fixed text. What follows it on the line is the hash, then a space and a note to readers.
function Get-HordeShimMarker { return "@rem horde install shim - sha256=" }

function Get-HordeDefaultBinDir {
    # %USERPROFILE%\bin, the folder the installer this replaces used and the one already on the
    # fleet's PATH. NOT derived from where the checkout sits: a clone in a code folder would put
    # horde.cmd in that code folder, which nothing puts on PATH. Returns "" when USERPROFILE is unset,
    # and the caller asks for -BinDir rather than guessing.
    if ("$env:USERPROFILE".Trim() -eq "") { return "" }
    return (Join-Path $env:USERPROFILE "bin")
}

function Get-HordeCheckoutKind {
    # "worktree" when Root's .git is a FILE - a linked worktree, or a submodule, both of which live
    # inside something else that can remove them. "checkout" when it is a directory. "plain" when there
    # is none, as in an exported copy. Read from the file system, not git, so it needs no git on PATH.
    param([string]$Root)
    $g = Join-Path $Root ".git"
    if (Test-Path -LiteralPath $g -PathType Container) { return "checkout" }
    if (Test-Path -LiteralPath $g -PathType Leaf) { return "worktree" }
    return "plain"
}

function Get-HordeShimTargetProblem {
    # Why a path cannot be written into a .cmd file, or $null if it can.
    # - Not ASCII: this repository's files are ASCII (CONTRIBUTING 13), and cmd.exe reads a batch file
    #   in the console code page, so a non-ASCII character would reach powershell.exe as a different one.
    # - "!": with delayed expansion enabled for cmd.exe in the registry, !...! is expanded inside quotes.
    # - A double quote or a control character cannot be quoted in a batch line at all.
    # "%" is not refused; Get-HordeShimText doubles it, which cmd.exe reads back as one "%".
    param([string]$Path)
    if ($Path -cmatch '[^\x20-\x7E]') { return "its path has a character outside printable ASCII, which a .cmd file cannot carry reliably: " + $Path }
    if ($Path.Contains("!")) { return "its path has a '!', which cmd.exe would expand when delayed expansion is on: " + $Path }
    if ($Path.Contains('"')) { return "its path has a double quote, which a .cmd file cannot quote: " + $Path }
    return $null
}

function Get-HordeShimBody {
    # The shim's lines after the header, CRLF-terminated, for the horde.ps1 at Target.
    #
    # THE LAUNCH IS ONE LINE, AND ENDS IN `call exit /b %%ERRORLEVEL%%`. Measured 2026-09-30 on
    # Windows 11, a stand-in script exiting 0, 1, 2 and 7, called through the shim from PowerShell and
    # from `cmd /c`:
    #   `powershell ... %* & exit /b`      returned 0 every time: a bare exit /b dropped the code.
    #   `powershell ... %*` as the last line   returned 0, 1, 2, 7 - but cmd.exe goes back to the FILE
    #                                        for the next line after the program exits, at the same
    #                                        byte offset, so a shim rewritten by an install while a
    #                                        long command runs would have its new tail executed.
    #   `powershell ... %* & call exit /b %%ERRORLEVEL%%`   returned 0, 1, 2, 7. The whole line is
    #                                        parsed before it runs, so the file is not read again, and
    #                                        `call` expands %ERRORLEVEL% after powershell has set it
    #                                        (a plain %ERRORLEVEL% on the same line would be read
    #                                        before powershell ran).
    # test\test-install.ps1 proves both: exit codes 0, 1 and 2 through the shim, and a command that
    # rewrites its own shim mid-run without the new tail running.
    #
    # THE ONE CASE THE TAIL DOES NOT COVER. A newline inside a quoted argument cuts the line while
    # cmd.exe is inside the quotes, so `& call exit /b ...` becomes part of that argument: measured
    # 2026-09-30, `echo-args "first-line<LF>second-line"` bound target=[first-line & call exit /b
    # %ERRORLEVEL%]. That argument was already cut short (the limit the shim states), and the exit
    # code still arrives, through the end of the file (`no-such "a<LF>b"` exited 2). A parenthesised
    # block would keep the tail on a line of its own, but an unquoted ")" in any argument would then
    # close the block, breaking ordinary calls to spare one that is already broken.
    #
    # POWERSHELL BY FULL PATH. cmd.exe looks in the CURRENT directory before PATH, so a bare
    # `powershell` would run a powershell.cmd or powershell.exe sitting in whatever folder horde was
    # called from. %SystemRoot% is Windows' own folder, never a user's.
    #
    # -File, NOT -Command: -File passes horde's exit code through as it is; -Command reduces it to
    # 0 or 1 (horde.ps1's header measures this).
    param([string]$Target)
    $escaped = $Target.Replace("%", "%%")
    $lines = @(
        "@echo off",
        "rem Launches horde from the checkout named below. Written by 'horde install'; to change it,",
        "rem run that again - the header above holds a hash of these lines, and an install refuses to",
        "rem replace a shim whose lines no longer match it.",
        "rem",
        "rem A NEWLINE CANNOT PASS THROUGH THIS FILE. cmd.exe ends the command line at the first newline",
        "rem and discards the rest before this file runs, so a multi-line argument arrives as its first",
        "rem line only, and nothing here can see what was lost. A caller with multi-line text runs",
        "rem horde.ps1 directly (powershell -File), or passes the text in a file. When the cut falls",
        "rem inside quotes, the rest of the launch line below joins that argument as well; the exit",
        "rem code still passes through.",
        "rem",
        "rem Exit codes pass through: the launch is one line so the file is never read again after it,",
        "rem and 'call exit /b' returns the code powershell set. cli\Install.ps1 records the measurements.",
        ('"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "' + $escaped + '" %* & call exit /b %%ERRORLEVEL%%')
    )
    return (($lines -join "`r`n") + "`r`n")
}

function Get-HordeShimHash {
    # Lowercase hex SHA-256 of the body's bytes. The body is ASCII by construction, and a file read
    # back is hashed over its raw bytes, so a changed line ending counts as an edit too.
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString("x2") }) -join "") }
    finally { $sha.Dispose() }
}

function Get-HordeShimText {
    # The whole shim: the header line, then the body.
    param([string]$Target)
    $body = Get-HordeShimBody -Target $Target
    $hash = Get-HordeShimHash -Bytes ([System.Text.Encoding]::ASCII.GetBytes($body))
    return ((Get-HordeShimMarker) + $hash + " of the lines below" + "`r`n" + $body)
}

function Read-HordeShim {
    # What is at Path now: { state; target; bytes }. state is one of
    #   absent     nothing there
    #   directory  a folder of that name, which nothing may replace
    #   foreign    a file without horde install's header
    #   edited     horde install's header, but the lines below no longer match its hash
    #   ours       horde install's header and matching lines; target is the horde.ps1 it launches
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Container) { return [pscustomobject]@{ state = "directory"; target = $null; bytes = $null } }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [pscustomobject]@{ state = "absent"; target = $null; bytes = $null } }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    # The header is found in the raw bytes: its line ends at the first LF, and everything after that
    # LF is what its hash covers.
    $lf = [Array]::IndexOf($bytes, [byte]10)
    $first = ""
    if ($lf -ge 0) { $first = [System.Text.Encoding]::ASCII.GetString($bytes, 0, $lf).TrimEnd("`r") }
    $m = [regex]::Match($first, '\A' + [regex]::Escape((Get-HordeShimMarker)) + '([0-9a-f]{64}) ')
    if (-not $m.Success) { return [pscustomobject]@{ state = "foreign"; target = $null; bytes = $bytes } }
    $rest = New-Object byte[] ($bytes.Length - $lf - 1)
    [Array]::Copy($bytes, $lf + 1, $rest, 0, $rest.Length)
    if ((Get-HordeShimHash -Bytes $rest) -ne $m.Groups[1].Value) { return [pscustomobject]@{ state = "edited"; target = $null; bytes = $bytes } }
    # The target is read from the launch line itself - the line that runs - not from a comment about it.
    $t = [regex]::Match([System.Text.Encoding]::ASCII.GetString($rest), '-File "([^"]*)" %\*')
    $target = $null
    if ($t.Success) { $target = $t.Groups[1].Value.Replace("%%", "%") }
    return [pscustomobject]@{ state = "ours"; target = $target; bytes = $bytes }
}

function Get-HordeInstallPlan {
    # Decide what an install would do, reading and writing nothing but reads. Returns
    # { action; problem; shim; target; previous; text; checkout } where action is create, update,
    # unchanged or refuse, and problem says why when it is refuse. -DryRun prints this and stops.
    param([string]$Root, [string]$BinDir, [switch]$Force, [switch]$AllowWorktree)
    $target = Join-Path $Root "horde.ps1"
    $shim = Join-Path $BinDir "horde.cmd"
    $kind = Get-HordeCheckoutKind -Root $Root
    $plan = [ordered]@{ action = "refuse"; problem = $null; shim = $shim; target = $target; previous = $null; text = $null; checkout = $kind }
    if ($kind -eq "worktree" -and -not $AllowWorktree) {
        $plan.problem = "this is a linked worktree (" + $Root + "), and the shim would make it the horde every caller of horde.cmd runs; install from the main checkout, or pass -AllowWorktree if that is really meant"
        return [pscustomobject]$plan
    }
    $why = Get-HordeShimTargetProblem -Path $target
    if ($why) { $plan.problem = "cannot write a shim for this checkout: " + $why; return [pscustomobject]$plan }
    $plan.text = Get-HordeShimText -Target $target
    $now = Read-HordeShim -Path $shim
    $plan.previous = $now.target
    switch ($now.state) {
        "directory" { $plan.problem = $shim + " is a folder; nothing replaces a folder, -Force included"; return [pscustomobject]$plan }
        "absent" { $plan.action = "create"; return [pscustomobject]$plan }
    }
    $wanted = [System.Text.Encoding]::ASCII.GetBytes($plan.text)
    if ($now.state -eq "ours" -and [System.Linq.Enumerable]::SequenceEqual([byte[]]$now.bytes, [byte[]]$wanted)) {
        $plan.action = "unchanged"; return [pscustomobject]$plan
    }
    $refusal = $null
    if ($now.state -eq "foreign") { $refusal = $shim + " was not written by horde install (it has no horde install header)" }
    elseif ($now.state -eq "edited") { $refusal = $shim + " was written by horde install and then edited by hand (its lines no longer match the hash in its header)" }
    elseif ("$($now.target)" -ine $target) { $refusal = $shim + " launches another checkout, " + $now.target + "; replacing it changes which horde every caller runs" }
    # Anything left is our own shim for this checkout, from an older template: replacing it is the
    # point of re-running install, and loses nothing a person wrote.
    if ($refusal -and -not $Force) {
        $plan.problem = "refusing to replace it: " + $refusal + ". Pass -Force to replace it anyway."
        return [pscustomobject]$plan
    }
    $plan.action = "update"
    return [pscustomobject]$plan
}

function Write-HordeShim {
    # Write the planned text to the shim's path, then read it back and compare. The new text goes to a
    # temporary file in the same folder first and is moved into place, so a caller starting horde.cmd
    # mid-install finds the old file or the new one, never half of one.
    param($Plan)
    $dir = Split-Path -Parent $Plan.shim
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $wanted = [System.Text.Encoding]::ASCII.GetBytes($Plan.text)
    $tmp = Join-Path $dir ("horde.cmd." + [guid]::NewGuid().ToString("N") + ".tmp")
    try {
        [System.IO.File]::WriteAllBytes($tmp, $wanted)
        # [NullString]::Value, not $null: PowerShell hands $null to a [string] .NET parameter as "", and
        # measured 2026-09-30, File.Replace then threw "The path is not of a legal form".
        if (Test-Path -LiteralPath $Plan.shim -PathType Leaf) { [System.IO.File]::Replace($tmp, $Plan.shim, [System.Management.Automation.Language.NullString]::Value) }
        else { [System.IO.File]::Move($tmp, $Plan.shim) }
    }
    finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
    $back = [System.IO.File]::ReadAllBytes($Plan.shim)
    if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$back, [byte[]]$wanted)) { throw ("wrote " + $Plan.shim + " but reading it back does not give what was written") }
}

function Test-HordeOnPath {
    # Whether Dir is one of the folders in PATH, compared without case or a trailing backslash.
    param([string]$Dir)
    $want = $Dir.TrimEnd("\")
    return (@("$env:Path" -split ";" | Where-Object { $_.Trim() -ne "" -and $_.Trim().TrimEnd("\") -ieq $want }).Count -gt 0)
}
