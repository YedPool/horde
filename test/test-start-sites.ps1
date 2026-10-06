# CAN ANYTHING UNDER messengers/ START A PROGRAM, RUN A SCRIPT BLOCK OR LOAD CODE WHERE ITS LIST DOES NOT SAY?
#
# Remote plan R21, slice 3b, merge condition 2 (review of #102): the wezfleet messenger starts exactly one
# program, from one place, and messengers/start-sites.txt lists every start site of the family. Proved
# here with tools/StartSites.ps1:
#   - the real tree against the real list: no finding at all, and exactly one process start;
#   - in a planted copy of messengers/, each way to start something refused for its own reason - a
#     second process start, another program, a changed program path, a site moved to another function -
#     and a stale list line refused too;
#   - a folder named test is not read, and a malformed list line is a finding.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "tools\StartSites.ps1")

function Says { param($Findings, [string]$Text) return (@($Findings | Where-Object { "$_".Contains($Text) }).Count -gt 0) }
function Show { param($Findings) foreach ($f in @($Findings)) { Write-Host ("         finding: " + $f) -ForegroundColor DarkYellow } }

Write-Host ""
Write-Host "--- the real tree: every start site is listed, and the one process start is the fixed PowerShell ---" -ForegroundColor Cyan

$f = @(Test-HordeStartSites -Root $root -Folder "messengers" -List "messengers\start-sites.txt")
Check ($f.Count -eq 0) "messengers/ has no start site outside messengers/start-sites.txt, and the list no stale line"; Show $f
$sites = @(Get-HordeStartSites -Root $root -Folder "messengers")
$starts = @($sites | Where-Object { $_.kind -ceq "method" -and $_.text -clike "*Process]::Start(*" })
Check ($starts.Count -eq 1) ("exactly one process start in the family (" + $starts.Count + ")")
$setup = @($sites | Where-Object { $_.kind -ceq "type" -and $_.text -clike "*ProcessStartInfo]::new(*" })
Check ($setup.Count -eq 1 -and $setup[0].text.Contains('[System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"')) ("and the program it starts is named once, as the fixed PowerShell in the system folder (" + $(if ($setup.Count) { $setup[0].text } else { "none" }) + ")")
Check ((@($sites | Where-Object { $_.kind -ceq "call" }).Count -ge 2)) "CONTROL: the port's two calls of a registered messenger are seen as sites"

Write-Host ""
Write-Host "--- a planted copy: each way to start something is refused for its own reason ---" -ForegroundColor Cyan

function Test-Planted {
    # Copy messengers/ and its list into a temp tree, apply Change to one file, and scan it.
    param([string]$File, [scriptblock]$Change, [string]$ListChange = "")
    $tree = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-startsites-" + [guid]::NewGuid().ToString("N").Substring(0, 10))
    try {
        Copy-Item -LiteralPath (Join-Path $root "messengers") -Destination (Join-Path $tree "messengers") -Recurse
        if ($File) {
            $p = Join-Path $tree $File
            $text = ""
            if (Test-Path -LiteralPath $p) { $text = [System.IO.File]::ReadAllText($p) }
            $new = & $Change $text
            [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p))
            [System.IO.File]::WriteAllText($p, $new)
        }
        if ($ListChange) { [System.IO.File]::AppendAllText((Join-Path $tree "messengers\start-sites.txt"), "`r`n" + $ListChange + "`r`n") }
        return @(Test-HordeStartSites -Root $tree -Folder "messengers" -List "messengers\start-sites.txt")
    } finally { if (Test-Path -LiteralPath $tree) { Remove-Item -LiteralPath $tree -Recurse -Force } }
}
$wf = "messengers\wezfleet\Messenger.ps1"
$mem = "messengers\memory\Messenger.ps1"
$f = @(Test-Planted -File "" -Change $null)
Check ($f.Count -eq 0) "CONTROL: an unchanged copy has no finding"; Show $f
$cases = @(
    @{ file = $wf; add = "function Start-Second { [System.Diagnostics.Process]::Start(`$x) }"; like = "method start site"; what = "a second process start" },
    @{ file = $mem; add = "function Get-X { Start-Process notepad.exe }"; like = "command start site"; what = "Start-Process" },
    @{ file = $mem; add = "function Get-X { cmd.exe /c dir }"; like = "command start site"; what = "a program named by its file name" },
    @{ file = $mem; add = "function Get-X { & 'C:\Windows\System32\cmd.exe' }"; like = "call start site"; what = "a program run with &" },
    @{ file = $mem; add = "function Get-X { Invoke-Expression `$s }"; like = "command start site"; what = "Invoke-Expression" },
    @{ file = $mem; add = "function Get-X { iex `$s }"; like = "command start site"; what = "iex, the alias" },
    @{ file = $mem; add = "function Get-X { Start-Job { 1 } }"; like = "command start site"; what = "a job" },
    @{ file = $mem; add = "function Get-X { `$b = [scriptblock]::Create(`$s) }"; like = "type start site"; what = "a script block compiled from text" },
    @{ file = $mem; add = "function Get-X { `$o.Invoke() }"; like = "method start site"; what = "an Invoke() call" },
    @{ file = $mem; add = "function Get-X { `$o.`$name() }"; like = "method start site"; what = "a method named by an expression" },
    @{ file = $mem; add = "function Get-X { . `$path }"; like = "dot start site"; what = "a dot-sourced file" },
    @{ file = $mem; add = "function Get-X { `$p = New-Object System.Diagnostics.ProcessStartInfo }"; like = "type start site"; what = "a ProcessStartInfo made with New-Object" },
    @{ file = $mem; add = "function Get-X { ([wmiclass]'Win32_Process').Create('x') }"; like = "type start site"; what = "a WMI process create" })
foreach ($c in $cases) {
    $add = $c.add
    $got = @(Test-Planted -File $c.file -Change ([scriptblock]::Create("param(`$t) return (`$t + `"`r`n`" + '" + $add.Replace("'", "''") + "')")))
    Check (Says $got $c.like) ("refused: " + $c.what)
    if (-not (Says $got $c.like)) { Show $got }
}
# THE PROGRAM IS PART OF THE SITE'S TEXT: pointing the one start at another program is a changed site,
# refused, and the old line becomes stale.
$got = @(Test-Planted -File $wf -Change { param($t) $t.Replace('"WindowsPowerShell", "v1.0", "powershell.exe"', '"cmd.exe"') })
Check ((Says $got "does not list") -and (Says $got "that is not there")) "pointing the one start at another program is refused, and its old list line is stale"
$got = @(Test-Planted -File $wf -Change { param($t) $t.Replace("function Start-HordeWezfleetMessengerProcess {", "function Start-HordeWezfleetMessengerProcess { }`r`nfunction Start-HordeWezfleetMessengerProcessMoved {") })
Check (Says $got "does not list") "the same start moved into another function is refused"
# ONE LINE IS ONE SITE: the same start written twice in its own function is a second start.
$got = @(Test-Planted -File $wf -Change { param($t) $t.Replace('try { $p = [System.Diagnostics.Process]::Start($psi) }', '$q = [System.Diagnostics.Process]::Start($psi); try { $p = [System.Diagnostics.Process]::Start($psi) }') })
Check (Says $got "does not list") "the one listed start written twice in its own function is refused: a line allows one site"
$got = @(Test-Planted -File "" -Change $null -ListChange "messengers/memory/Messenger.ps1 | Get-X | command | Start-Process x |")
Check (Says $got "does not say why") "a list line that does not say why is refused"
$got = @(Test-Planted -File "" -Change $null -ListChange "messengers/memory/Messenger.ps1 | Get-X | command | Start-Process notepad.exe | a planted permission")
Check (Says $got "that is not there") "a list line no site matches is refused: no stale permission waits for a later edit"
$got = @(Test-Planted -File "" -Change $null -ListChange "messengers/memory/Messenger.ps1 | Get-X | spawn | x | y")
Check (Says $got "not one of") "a list line with a kind outside the list is refused"
$got = @(Test-Planted -File "" -Change $null -ListChange "a line with no cells")
Check (Says $got "is not 'file | function | kind | text | why'") "a malformed list line is refused"
$got = @(Test-Planted -File "" -Change $null -ListChange "messengers/memory/Messenger.ps1 | Get-X | command")
Check (Says $got "is not 'file | function | kind | text | why'") "a list line with three of its five cells is refused"
$got = @(Test-Planted -File "messengers\wezfleet\test\Planted.ps1" -Change { param($t) "function Get-X { Start-Process notepad.exe }" })
Check ($got.Count -eq 0) "a file under a test folder is not read: tests start stand-in children on purpose"; Show $got
$got = @(Test-Planted -File $mem -Change { param($t) $t + "`r`nfunction Get-X {" })
Check (Says $got "does not parse") "a file that does not parse is a finding, never a pass"
$tree = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-startsites-" + [guid]::NewGuid().ToString("N").Substring(0, 10))
try {
    Copy-Item -LiteralPath (Join-Path $root "messengers") -Destination (Join-Path $tree "messengers") -Recurse
    Remove-Item -LiteralPath (Join-Path $tree "messengers\start-sites.txt")
    $got = @(Test-HordeStartSites -Root $tree -Folder "messengers" -List "messengers\start-sites.txt")
    Check (Says $got "is missing") "with no list at all, the family is refused, not passed"
} finally { if (Test-Path -LiteralPath $tree) { Remove-Item -LiteralPath $tree -Recurse -Force } }

Complete-HordeSuite -Success "nothing under messengers/ can start a program, run a script block or load code except at the sites messengers/start-sites.txt lists"
