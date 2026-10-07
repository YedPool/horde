# DOES A FILE TAKE A NEW NAME ONLY WHEN THE NAME IS FREE, AND IS EVERYTHING DONE THAT MAKES THE MOVE DURABLE?
#
# core/FileAtomic.ps1's Move-HordeFileNewDurable: the move a write-once record is put in place by
# (decisions/Store.ps1). This suite attacks what a caller is told:
#   - "moved" only when the file has the name; "exists" when something already had it, with both
#     files untouched; "unconfirmed" when the file has the name and the flush after the move failed;
#   - the flush is made on the caller's open stream, to disk, AFTER the move;
#   - on a system this file has no durable move for, it refuses in words and moves nothing.
#
# WHAT THIS SUITE CANNOT SEE, AND SAYS SO: whether the move survives a power cut. It proves the
# write-through flag is the one handed to the operating system (the flags are one function, read here
# and found in the call by its syntax), that a move with it does not replace, and that the flush is
# called, with the right argument, at the right moment. That the operating system and the disk then
# keep their word is reasoned in core/FileAtomic.ps1, not tested.
#
# Every file is in a folder under %TEMP% that this suite made and removes (CONTRIBUTING 9).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\FileAtomic.ps1")

$script:work = Join-Path $env:TEMP ("horde-file-move-new-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:n = 0
function New-Pair {
    # A source file holding -Text and a destination name nothing has, in a folder of their own.
    param([string]$Text = "the source")
    $script:n++
    $dir = Join-Path $script:work ("case-" + $script:n)
    New-Item -ItemType Directory -Path $dir | Out-Null
    $from = Join-Path $dir "from.part"
    [System.IO.File]::WriteAllText($from, $Text, $utf8)
    return [pscustomobject]@{ dir = $dir; from = $from; to = (Join-Path $dir "to.json") }
}
function Move-Safely {
    # The move, a throw turned into text: a mutant that makes it throw must fail a check, not crash the suite.
    param([string]$From, [string]$To, $Open = $null, $OsPlatform = $null)
    try {
        if ($null -ne $OsPlatform) { return (Move-HordeFileNewDurable -From $From -To $To -Open $Open -OsPlatform $OsPlatform) }
        return (Move-HordeFileNewDurable -From $From -To $To -Open $Open)
    } catch { return ("THREW: " + $_.Exception.Message) }
}
function New-FakeStream {
    # Something with a Flush method, as the caller's open stream has, that writes down how it was
    # called and what was on disk at that moment. -Fails makes the flush throw.
    param([string]$From, [string]$To, [switch]$Fails)
    $fake = [pscustomobject]@{ calls = (New-Object System.Collections.ArrayList); from = $From; to = $To; fails = [bool]$Fails }
    $fake | Add-Member -MemberType ScriptMethod -Name Flush -Value {
        param($ToDisk)
        [void]$this.calls.Add([pscustomobject]@{ toDisk = $ToDisk; fromThere = [System.IO.File]::Exists($this.from); toThere = [System.IO.File]::Exists($this.to) })
        if ($this.fails) { throw "the disk said no" }
    }
    return $fake
}

try {

Write-Host ""
Write-Host "--- a free name is taken, and the file is whole under it ---" -ForegroundColor Cyan
$p = New-Pair "exactly this text"
Check ((Move-Safely $p.from $p.to) -ceq "moved") "a move to a name nothing has is told moved"
Check ([System.IO.File]::Exists($p.to) -and -not [System.IO.File]::Exists($p.from)) "the file has the new name, and the old name is gone"
Check ([System.IO.File]::ReadAllText($p.to) -ceq "exactly this text") "and it holds exactly what it held"

Write-Host ""
Write-Host "--- a taken name is never replaced ---" -ForegroundColor Cyan
$p = New-Pair "the newcomer"
[System.IO.File]::WriteAllText($p.to, "the one already there", $utf8)
Check ((Move-Safely $p.from $p.to) -ceq "exists") "a move onto a name a file already has is told exists"
Check ([System.IO.File]::ReadAllText($p.to) -ceq "the one already there") "the file that had the name is untouched"
Check ([System.IO.File]::Exists($p.from) -and [System.IO.File]::ReadAllText($p.from) -ceq "the newcomer") "and so is the one that was to be moved: nothing was lost on either side"
$p = New-Pair
New-Item -ItemType Directory -Path $p.to | Out-Null
Check ((Move-Safely $p.from $p.to) -ceq "exists") "a folder of that name is told exists too: which of the two it is, is the caller's to ask"
Check ([System.IO.File]::Exists($p.from) -and [System.IO.Directory]::Exists($p.to)) "and nothing moved"

Write-Host ""
Write-Host "--- what is not 'exists' is an error, and leaves the file where it was ---" -ForegroundColor Cyan
$p = New-Pair
[System.IO.File]::Delete($p.from)
$got = Move-Safely $p.from $p.to
Check ($got -like "THREW:*" -and -not [System.IO.File]::Exists($p.to)) ("a file that is not there is an error, never 'exists' and never 'moved' (" + $got + ")")
$p = New-Pair
$got = Move-Safely $p.from (Join-Path $p.dir "no-such-folder\to.json")
Check ($got -like "THREW:*" -and [System.IO.File]::Exists($p.from)) ("a name in a folder that is not there is an error, and the file stays (" + $got + ")")

Write-Host ""
Write-Host "--- the file may be moved while its writer still holds it open ---" -ForegroundColor Cyan
# This is how decisions/Store.ps1 uses it: the writer never lets go of its file between writing it and
# naming it, so there is no moment when the file exists and nothing shows that a writer is alive.
$p = New-Pair
[System.IO.File]::Delete($p.from)
$bytes = $utf8.GetBytes("written and still held")
$stream = New-Object System.IO.FileStream($p.from, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Delete, 4096, [System.IO.FileOptions]::WriteThrough)
try {
    $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true)
    $got = Move-Safely $p.from $p.to $stream
    Check ($got -ceq "moved") ("a file held open with delete sharing is moved, and its holder's stream is flushed after (" + $got + ")")
    Check ([System.IO.File]::Exists($p.to) -and -not [System.IO.File]::Exists($p.from)) "it has its new name while still held"
} finally { $stream.Dispose() }
Check ([System.IO.File]::ReadAllText($p.to) -ceq "written and still held") "and once its writer lets go it reads whole under the new name"

Write-Host ""
Write-Host "--- the flush: on the caller's stream, to disk, after the move ---" -ForegroundColor Cyan
$p = New-Pair
$fake = New-FakeStream $p.from $p.to
$got = Move-Safely $p.from $p.to $fake
Check ($got -ceq "moved" -and $fake.calls.Count -eq 1) ("the caller's stream is flushed exactly once (" + $got + ", " + $fake.calls.Count + " call(s))")
Check ($fake.calls.Count -eq 1 -and $fake.calls[0].toDisk -is [bool] -and $fake.calls[0].toDisk) "and it is a flush to disk: Flush(true), not a flush of the stream's own buffer"
Check ($fake.calls.Count -eq 1 -and $fake.calls[0].toThere -and -not $fake.calls[0].fromThere) "and it comes AFTER the move: at that moment the file already had its new name"
$p = New-Pair
$fake = New-FakeStream $p.from $p.to
[System.IO.File]::WriteAllText($p.to, "already there", $utf8)
$got = Move-Safely $p.from $p.to $fake
Check ($got -ceq "exists" -and $fake.calls.Count -eq 0) "a move that was told exists flushes nothing: there is nothing of its own to confirm"
$p = New-Pair "it did move"
$fake = New-FakeStream $p.from $p.to -Fails
$got = Move-Safely $p.from $p.to $fake
Check ($got -ceq "unconfirmed") ("when the flush after the move fails, the answer is unconfirmed - not moved, and not an error that reads as 'nothing happened' (" + $got + ")")
Check ([System.IO.File]::Exists($p.to) -and [System.IO.File]::ReadAllText($p.to) -ceq "it did move") "because the file DOES have its name: the caller must know that, and must not call it saved"
$p = New-Pair
Check ((Move-Safely $p.from $p.to $null) -ceq "moved") "CONTROL: with no stream given there is nothing to flush, and the move is made"

Write-Host ""
Write-Host "--- the flags handed to the operating system ---" -ForegroundColor Cyan
$flags = Get-HordeFileMoveNewFlags
Check ($flags -is [int] -and ($flags -band 0x8) -eq 0x8) ("MOVEFILE_WRITE_THROUGH (0x8) is set: the move does not return until it is on disk (flags " + $flags + ")")
Check (($flags -band 0x1) -eq 0) "MOVEFILE_REPLACE_EXISTING (0x1) is not: the move never replaces"
Check ($flags -eq 0x8) "and nothing else is: no copy across volumes, no delay until restart"
# That function's answer is what the call is given: read from the syntax tree, with a control.
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root "core\FileAtomic.ps1"), [ref]$tokens, [ref]$errors)
$mover = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq "Move-HordeFileNewDurable" }, $true))
$nativeCalls = @()
if ($mover.Count -eq 1) { $nativeCalls = @($mover[0].FindAll({ param($node) $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and "$($node.Member)" -ceq "MoveFileEx" }, $true)) }
Check (@($errors).Count -eq 0 -and $mover.Count -eq 1 -and $nativeCalls.Count -eq 1) ("CONTROL: the function is found, and it makes one native move (" + $nativeCalls.Count + ")")
Check ($nativeCalls.Count -eq 1 -and @($nativeCalls[0].Arguments).Count -eq 3 -and "$($nativeCalls[0].Arguments[2])" -ceq '(Get-HordeFileMoveNewFlags)') "the flags of that move are that function's answer, and no number written at the call"
$otherMoves = @()
if ($mover.Count -eq 1) { $otherMoves = @($mover[0].FindAll({ param($node) $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and @("Move", "Copy", "Replace", "Delete") -ccontains "$($node.Member)" }, $true)) }
Check ($otherMoves.Count -eq 0) "and the function has no other way to move, copy, replace or delete a file"

Write-Host ""
Write-Host "--- a system with no durable move here is refused in words ---" -ForegroundColor Cyan
$p = New-Pair
$got = Move-Safely $p.from $p.to $null "Unix"
Check ($got -like "THREW:*no durable move for this system*Unix*") ("asked as another system, it refuses and says which (" + $got + ")")
Check ([System.IO.File]::Exists($p.from) -and -not [System.IO.File]::Exists($p.to)) "and moves nothing: a move that is not durable is never used in its place"
Check ((Move-Safely $p.from $p.to $null "Win32NT") -ceq "moved") "CONTROL: asked as Windows, the same move is made"

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-file-move-new-test-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"

Complete-HordeSuite -Success "a file takes a new name only when the name is free, and the caller is told exactly what was done to make it durable"
