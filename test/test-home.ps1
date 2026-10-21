# DOES HORDE FIND ITS HOME FROM HORDE_HOME, THEN THE POINTER FILE, AND ONLY AS A PATH?
#
# core/Home.ps1 (T-0299: HORDE_HOME, else the pointer file %USERPROFILE%\.horde-home.json, else .horde). Every check
# restores the two variables it changes, so the suite leaves the process as it found it. Every pointer check names a
# USERPROFILE this suite made under %TEMP%: the real pointer is never read or written (CONTRIBUTING 9).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\Home.ps1")

$origHome = $env:HORDE_HOME
$origProfile = $env:USERPROFILE
try {
    Write-Host ""
    Write-Host "--- the home ---" -ForegroundColor Cyan
    $fake = Join-Path $env:TEMP ("horde-home-test-" + [guid]::NewGuid().ToString("N"))
    $env:HORDE_HOME = $fake
    Check ((Get-HordeHome) -eq $fake) "HORDE_HOME names the home when it is set"
    $env:HORDE_HOME = ""
    $env:USERPROFILE = "C:\profile-for-test"
    Check ((Get-HordeHome) -eq "C:\profile-for-test\.horde") "with HORDE_HOME unset the home is .horde in the user profile"
    $env:HORDE_HOME = "relative\home"
    Check (Throws { Get-HordeHome } "absolute") "a relative HORDE_HOME is refused, not resolved against the current folder"
    $env:HORDE_HOME = ""
    $env:USERPROFILE = ""
    Check (Throws { Get-HordeHome } "no home") "with neither variable there is no home, and it says so"
    $env:HORDE_HOME = $fake
    $null = Get-HordeHome
    Check (-not (Test-Path -LiteralPath $fake)) "finding the home does not create it"
} finally {
    $env:HORDE_HOME = $origHome
    $env:USERPROFILE = $origProfile
}

Write-Host ""
Write-Host "--- the pointer file ---" -ForegroundColor Cyan
$work = Join-Path $env:TEMP ("horde-home-pointer-" + [guid]::NewGuid().ToString("N"))
$prof = Join-Path $work "profile"
$homeA = Join-Path $work "homeA"
$homeB = Join-Path $work "homeB"
New-Item -ItemType Directory -Path $prof, $homeA, $homeB -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pointer = Join-Path $prof ".horde-home.json"
function Put-Pointer { param([string]$Text) [System.IO.File]::WriteAllText($pointer, $Text, $utf8) }
function Pointer-Json { param([string]$Dir) return ('{"v":1,"hordeHome":"' + $Dir.Replace("\", "\\") + '"}') }
try {
    $env:USERPROFILE = $prof
    $env:HORDE_HOME = ""
    Check ((Get-HordeHomePointerPath) -eq $pointer) "the pointer is .horde-home.json in the user profile"
    $r = Resolve-HordeHome
    Check ($r.source -ceq "default" -and $r.path -eq (Join-Path $prof ".horde")) "no pointer: the old default, source default"
    Put-Pointer (Pointer-Json $homeA)
    $r = Resolve-HordeHome
    Check ($r.source -ceq "pointer" -and $r.path -eq $homeA -and (Get-HordeHome) -eq $homeA) "HORDE_HOME unset: the pointer names the home"
    $env:HORDE_HOME = $homeB
    $r = Resolve-HordeHome
    Check ($r.source -ceq "HORDE_HOME" -and $r.path -eq $homeB) "HORDE_HOME wins over the pointer"
    $env:HORDE_HOME = "relative\home"
    Check (Throws { Get-HordeHome } "absolute") "a relative HORDE_HOME is refused, and does not fall back to the pointer"
    $env:HORDE_HOME = "   "
    Check ((Resolve-HordeHome).source -ceq "pointer") "a blank HORDE_HOME is no HORDE_HOME"
    $env:HORDE_HOME = ""
    Put-Pointer (Pointer-Json $homeB)
    Check ((Get-HordeHome) -eq $homeB) "the pointer is read on every call: a change is seen at the next one"
    # Folders that EXIST, so only the rule under test can refuse them (a relative path is relative to this folder).
    $accented = Join-Path $work ("h" + [char]0x00E9 + "me")
    New-Item -ItemType Directory -Path $accented -Force | Out-Null
    Push-Location -LiteralPath $work
    $bad = [ordered]@{
        "missing hordeHome"        = '{"v":1}'
        "blank hordeHome"          = '{"v":1,"hordeHome":"  "}'
        "hordeHome not a string"   = '{"v":1,"hordeHome":7}'
        "v 2"                      = (Pointer-Json $homeA).Replace('"v":1', '"v":2')
        "v a string"               = (Pointer-Json $homeA).Replace('"v":1', '"v":"1"')
        "no v"                     = ('{"hordeHome":"' + $homeA.Replace("\", "\\") + '"}')
        "relative path"            = '{"v":1,"hordeHome":"some\\folder"}'
        "drive-less path"          = '{"v":1,"hordeHome":"\\some\\folder"}'
        "relative path that exists" = '{"v":1,"hordeHome":"homeA"}'
        "drive-less path that exists" = (Pointer-Json ($homeA.Substring(2)))
        "folder missing"           = (Pointer-Json (Join-Path $work "no-such-folder"))
        "a file, not a folder"     = (Pointer-Json $pointer)
        "not JSON"                 = '{"v":1,'
        "a JSON array"             = '[1]'
        "empty file"               = ''
        "non-ASCII (an existing folder)" = ('{"v":1,"hordeHome":"' + $accented.Replace("\", "\\") + '"}')
    }
    foreach ($k in $bad.Keys) {
        Put-Pointer $bad[$k]
        Check (Throws { Get-HordeHome } $pointer) ("a bad pointer is refused, naming the file: " + $k)
        Check (Throws { Resolve-HordeHome } "is refused") ("   and not skipped for the default: " + $k)
    }
    Pop-Location
    [System.IO.File]::WriteAllBytes($pointer, [byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::ASCII.GetBytes((Pointer-Json $homeA))))
    Check (Throws { Get-HordeHome } $pointer) "a pointer with a byte-order mark is refused, naming the file"
    $env:HORDE_HOME = $homeA
    Check ((Get-HordeHome) -eq $homeA) "HORDE_HOME wins even over a bad pointer (it is not read)"
    $env:HORDE_HOME = ""
    Remove-Item -LiteralPath $pointer -Force
    New-Item -ItemType Directory -Path $pointer | Out-Null
    Check (Throws { Get-HordeHome } $pointer) "a pointer that is a folder cannot be read: refused, naming it"
    Remove-Item -LiteralPath $pointer -Recurse -Force

    Write-Host ""
    Write-Host "--- set and clear ---" -ForegroundColor Cyan
    Check (Throws { Set-HordeHomePointer -Path "relative\home" } "absolute") "set refuses a relative path"
    Check (Throws { Set-HordeHomePointer -Path "\no\drive" } "absolute") "set refuses a path with no drive"
    Check (Throws { Set-HordeHomePointer -Path (Join-Path $work "nope") } "not an existing folder") "set refuses a folder that is not there"
    Check (Throws { Set-HordeHomePointer -Path $homeA } "no fleet.db") "set refuses a folder without fleet.db"
    Check (Throws { Set-HordeHomePointer -Path ($homeA + [char]0x00E9) } "ASCII") "set refuses a path the ASCII pointer cannot hold"
    Check (-not (Test-Path -LiteralPath $pointer)) "and none of the refusals wrote a pointer"
    [System.IO.File]::WriteAllText((Join-Path $homeA "fleet.db"), "x", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $homeB "fleet.db"), "x", $utf8)
    $r = Set-HordeHomePointer -Path $homeA
    Check ($r.old -eq (Join-Path $prof ".horde") -and $r.new -eq $homeA -and $r.file -eq $pointer) "set returns the old home and the new"
    Check (([System.IO.File]::ReadAllText($pointer)) -ceq ('{"v":1,"hordeHome":"' + $homeA.Replace("\", "\\") + '"}')) "the pointer is exactly {v 1, hordeHome}, one line"
    Check (@([System.IO.File]::ReadAllBytes($pointer) | Where-Object { $_ -gt 0x7E }).Count -eq 0) "and plain ASCII"
    Check ((Get-HordeHome) -eq $homeA) "and the home is read from it"
    $r = Set-HordeHomePointer -Path $homeB
    Check ($r.old -eq $homeA -and (Get-HordeHome) -eq $homeB) "set again: old is the previous pointer home"
    Check (@(Get-ChildItem -LiteralPath $prof -Force | Where-Object { $_.Name -ne ".horde-home.json" }).Count -eq 0) "no temp file is left in the profile"
    # ATOMIC: a second name (a hard link) for the pointer's file still reads the OLD, whole text after the set, because
    # the new text was written to a temp file and renamed over the pointer. An in-place write would change what the link reads.
    $linkName = Join-Path $work 'pointer-link.json'
    $null = New-Item -ItemType HardLink -Path $linkName -Target $pointer
    $null = Set-HordeHomePointer -Path $homeA
    $held = [System.IO.File]::ReadAllText($linkName)
    Check ($held -ceq (Pointer-Json $homeB)) 'the write is atomic: the old file is left whole and a new one renamed over it (temp file, then rename)'
    Check ((Get-HordeHome) -eq $homeA) "   while the next reader sees the new pointer"
    $c = Clear-HordeHomePointer
    Check ($c.removed -and -not (Test-Path -LiteralPath $pointer)) "clear removes the pointer"
    Check ((Get-HordeHome) -eq (Join-Path $prof ".horde")) "and the home is the default again"
    $c = Clear-HordeHomePointer
    Check (-not $c.removed) "clear with no pointer is a no-op"
    Put-Pointer '{"v":2}'
    $r = Set-HordeHomePointer -Path $homeB
    Check ($r.old -eq "" -and (Get-HordeHome) -eq $homeB) "set mends a bad pointer (old is empty: none could be resolved)"
    $env:USERPROFILE = ""
    Check (Throws { Set-HordeHomePointer -Path $homeA } "USERPROFILE") "with no user profile there is no place for a pointer"
} finally {
    $env:HORDE_HOME = $origHome
    $env:USERPROFILE = $origProfile
    if ((Split-Path -Leaf $work) -match '\Ahorde-home-pointer-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "Horde's home comes from HORDE_HOME, then the pointer file, then the user profile, and is never guessed"
