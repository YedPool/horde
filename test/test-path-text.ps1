# ARE A PATH'S LETTERS A TO Z FOLDED BY NO TABLE OF THE RUNTIME'S, AND IS A NETWORK PATH - OR A DRIVE
# LETTER THAT STANDS FOR ONE - KNOWN BEFORE ANYTHING LOOKS AT IT?
#
# core/PathText.ps1, in this process. The first two functions were moved here from the files store on
# 2026-10-13, so that there is one copy for every caller; the third was added the same day; test/test-files-store.ps1 keeps
# the checks that the share USES them (the pinned file id among them). The suite attacks the rules:
#   - the fold changes exactly 26 of the 65536 code units there are, and asks no case table: a
#     capital outside A to Z that some runtime's table lowers is left as it is;
#   - a network path is refused in every spelling, with the reason, and NOT ONE of the hosts named
#     is looked up: the answer comes from the text;
#   - a network drive is refused by its type, behind the long-path prefix and in small letters too.
#     THE TYPE IS ANSWERED BY THIS SUITE, not by a drive it makes: a drive letter is seen by every
#     process of the user, and a suite must not change what other processes see. One real letter
#     is made, in the one place marked below, over a folder of this machine's own drive;
#   - what is not a network path is not refused: a local drive, the long-path prefix, the device
#     form, a relative path, a letter no drive has;
#   - what the function cannot see, it is shown not to see, so that a caller knows to ask twice:
#     a PowerShell drive over a share, and the spelling PowerShell's resolver takes for a local path;
#   - the reason speaks for every caller: no word of sharing, which is one caller's;
#   - a drive letter that stands for a network drive, or straight for a share, is refused from the
#     system's table of names, a chain of letters to its end and a ring of them too. THE TABLE IS
#     ANSWERED BY THIS SUITE as the type is: only the last letter of a chain is asked its type,
#     never the letter that stands over it, which is the asking that was measured looking a host up.
#
# Nothing here is written to a disk, and no host that exists is named. The PowerShell drive made at
# the end is this process's own: it is no drive letter of the system's, and no other process sees it.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\PathText.ps1")

function Write-Skip { param([string]$What) Write-Host ("  [SKIP] " + $What) -ForegroundColor Yellow }
function Get-Said {
    # What the network question says of -Path, or "threw: <why>": no path may make it throw.
    param([AllowEmptyString()][string]$Path)
    try { return ("" + (Get-HordeNetworkPathRefusal -Path $Path)) } catch { return ("threw: " + $_.Exception.Message) }
}
# What the reason ends in: true for every caller, with no word of what the caller was doing with the path.
$ownDrives = "only a path on one of this machine's own drives is taken"
function Test-NetworkPath {
    # Is -Path refused as a network path, in exactly the function's words?
    param([string]$Path)
    $said = Get-Said $Path
    $ok = ($said -ceq ("'" + $Path + "' is a network path, and " + $ownDrives))
    if (-not $ok) { Write-Host ("         got: " + $said) -ForegroundColor Red }
    return $ok
}
function Test-NotRefused {
    param([AllowEmptyString()][string]$Path)
    $said = Get-Said $Path
    if ($said -cne "") { Write-Host ("         got: " + $said) -ForegroundColor Red }
    return ($said -ceq "")
}

Write-Host ""
Write-Host "--- loading the file ---" -ForegroundColor Cyan
$strictKept = & { Set-StrictMode -Version Latest; . (Join-Path $root "core\PathText.ps1"); try { $null = $hordeNeverAssignedVariable; $false } catch { $true } }
Check ($strictKept -eq $true) "dot-sourcing core/PathText leaves the caller's strict mode on"

Write-Host ""
Write-Host "--- the fold: A to Z by the code's own hand, every other character as it is ---" -ForegroundColor Cyan
# WHAT IS FOLDED GOES INTO SOMETHING PERMANENT, so it may not depend on the runtime's case table.
# Measured 2026-10-13 on one machine: ToLowerInvariant leaves U+1E9E, U+2126 and U+A7AE as they are
# under Windows PowerShell 5.1 and changes all three under PowerShell 7.6 (to U+00DF, U+03C9, U+026A).
$printable = -join (32..126 | ForEach-Object { [char]$_ })
Check ((ConvertTo-HordeAsciiLower -Text $printable) -ceq ' !"#$%&''()*+,-./0123456789:;<=>?@abcdefghijklmnopqrstuvwxyz[\]^_`abcdefghijklmnopqrstuvwxyz{|}~') "of the 95 printable ASCII characters, exactly the 26 capitals are changed: @ before A and [ after Z are as they were"
Check ((ConvertTo-HordeAsciiLower -Text "") -ceq "") "nothing folded is nothing"
# Capitals outside A to Z, each with a lower case in some runtime's table: the three of the review,
# then E acute, I with a dot, the Kelvin sign (whose lower case is the ASCII k), a full-width A,
# and a Greek and a Cyrillic capital.
$capitals = @(0x1E9E, 0x2126, 0xA7AE, 0x00C9, 0x0130, 0x212A, 0xFF21, 0x0391, 0x0410)
$kept = @(foreach ($code in $capitals) { [int][char](ConvertTo-HordeAsciiLower -Text ([string][char]$code)) })
Check (($kept -join ",") -ceq ($capitals -join ",")) ("a capital that is not one of A to Z is left as it is: " + (($kept | ForEach-Object { "U+{0:X4}" -f $_ }) -join " "))
# E acute is the one this suite's own runtime can see a table with: Windows PowerShell 5.1 does not
# change the three of the review, so without it the check above could not fail for a table there.
Check (([string][char]0x00C9).ToLowerInvariant() -cne ([string][char]0x00C9)) "CONTROL: this runtime's own table DOES change one of those capitals (U+00C9), so the check above can see a table"
# EVERY CODE UNIT THERE IS, a lone surrogate among them, in one text: folded here another way (a
# count over the code units, not a pattern and not a table) and compared place by place.
$every = New-Object System.Text.StringBuilder 65536
for ($unit = 0; $unit -le 0xFFFF; $unit++) { [void]$every.Append([char]$unit) }
$foldedEvery = ConvertTo-HordeAsciiLower -Text $every.ToString()
$changed = New-Object System.Collections.ArrayList
$wrong = 0
if ($foldedEvery.Length -eq 65536) {
    for ($unit = 0; $unit -le 0xFFFF; $unit++) {
        $got = [int]$foldedEvery[$unit]
        if ($got -ne $unit) { [void]$changed.Add($unit); if ($got -ne ($unit + 32)) { $wrong++ } }
    }
}
Check ($foldedEvery.Length -eq 65536 -and (($changed.ToArray()) -join ",") -ceq ((65..90) -join ",") -and $wrong -eq 0) ("of all 65536 code units, the 26 from 65 to 90 are each made 32 more and no other is touched (changed: " + $changed.Count + ", length " + $foldedEvery.Length + ")")
Check ((ConvertTo-HordeAsciiLower -Text "C:\Dir\FILE Z.md") -ceq "c:\dir\file z.md") "a path's drive letter, folders and name come out in small letters, its separators and blanks as they were"

Write-Host ""
Write-Host "--- a network path is known from its text, in every spelling, and nothing is looked up ---" -ForegroundColor Cyan
# TO LOOK AT A NETWORK PATH IS THE HARM: asking whether it exists sends the user's sign-in to the host
# it names. So "refused" is not enough to check; nothing may have ASKED.
# THE INSTRUMENT is the DNS cache of this machine. A host name nobody has ever used (ten digits made
# here, one label) is in that cache after anything asks the network about a path under it, and is not
# there otherwise. Measured 2026-10-13: 12 of 12 after File.Exists, Directory.Exists and an open; 0 of
# 4 with nothing called. A name with dots in it was no instrument (3 of 36), and neither was time (a
# lookup of such a name came back in 15 ms).
function New-NoHost { return ("horde-" + [guid]::NewGuid().ToString("N").Substring(0, 10)) }
function Get-LookedUp { return ((& ipconfig.exe /displaydns) -join "`n") }
$seenHost = New-NoHost
$null = [System.IO.File]::Exists("\\" + $seenHost + "\share\x.md")
$cacheNow = Get-LookedUp
$canSee = ($cacheNow.Contains($seenHost) -and -not $cacheNow.Contains((New-NoHost)))
if ($canSee) { Check $true "CONTROL: the instrument can see a lookup: a host asked about is in the DNS cache, and a name nobody asked about is not" }
else { Write-Skip "WHETHER A NETWORK PATH WAS LOOKED AT COULD NOT BE SEEN: this machine's DNS cache does not show a host that was just asked about. The refusals below are still checked by their reasons." }
# EVERY SPELLING, each under a host of its own that does not exist.
$spellings = @(
    @("two backslashes", "\\{0}\share\x.md"), @("two forward slashes", "//{0}/share/x.md"), @("a backslash and then a forward slash", "\/{0}\share\x.md"),
    @("a forward slash and then a backslash", "/\{0}/share/x.md"), @("three backslashes", "\\\{0}\share\x.md"),
    @("the long-path UNC prefix", "\\?\UNC\{0}\share\x.md"), @("the long-path UNC prefix in small letters", "\\?\unc\{0}\share\x.md"), @("the long-path UNC prefix in mixed case", "\\?\uNc\{0}\share\x.md"),
    @("the long-path UNC prefix with forward slashes", "//?/UNC/{0}/share/x.md"), @("the device-prefix UNC form", "\\.\UNC\{0}\share\x.md"), @("the device-prefix UNC form with forward slashes", "//./unc/{0}/share/x.md"),
    @("the NT form of a UNC path", "\??\UNC\{0}\share\x.md"), @("a server's own drive share", "\\{0}\C$\x.md"), @("a share with nothing under it", "\\{0}\share"), @("a server and nothing else", "\\{0}"),
    @("the long-path UNC prefix and nothing else", "\\?\UNC"), @("a device's name on a share", "\\{0}\share\NUL"), @("a stream of a file on a share", "\\{0}\share\x.md:y.txt"), @("a folder on a share", "\\{0}\share\folder\"))
$askedHosts = New-Object System.Collections.ArrayList
foreach ($spelling in $spellings) {
    $noHost = New-NoHost
    [void]$askedHosts.Add($noHost)
    Check (Test-NetworkPath ($spelling[1] -f $noHost)) ("a network path is refused from its text: " + $spelling[0] + " (" + ($spelling[1] -f "<host>") + ")")
}
$cacheNow = Get-LookedUp
$lookedUp = @($askedHosts | Where-Object { $cacheNow.Contains($_) })
if ($canSee) { Check ($lookedUp.Count -eq 0 -and $askedHosts.Count -eq 19) ("and not one of those " + $askedHosts.Count + " hosts was looked up: the answer came from the text (looked up: " + $lookedUp.Count + ")") }
# THIS MACHINE'S OWN NAME IS A HOST LIKE ANY OTHER: what a server says of itself is the server's to say.
$system = ("" + $env:SystemDrive).Substring(0, 1)
Check (Test-NetworkPath ("\\localhost\" + $system + "$\folder\x.md")) "this machine's own drive share (\\localhost\C$\...) is a network path"
Check (Test-NetworkPath ("\\127.0.0.1\" + $system + "$\folder\x.md")) "and so it is by this machine's address"
Check (Test-NetworkPath ("\\?\UNC\localhost\" + $system + "$\folder\x.md")) "and by the long-path form of that"

Write-Host ""
Write-Host "--- what is not a network path is not refused ---" -ForegroundColor Cyan
Check (Test-NotRefused ($system + ":\folder\x.md")) "a path on one of this machine's own drives"
Check (Test-NotRefused (($system + ":\folder\x.md").ToLowerInvariant())) "the same with its letter in small"
Check (Test-NotRefused ("\\?\" + $system + ":\folder\x.md")) "the same behind the long-path prefix (\\?\C:\...): two separators and a question mark are not a server"
Check (Test-NotRefused ("//?/" + $system + ":/folder/x.md")) "and that prefix written with forward slashes"
Check (Test-NotRefused ("\\.\" + $system + ":\folder\x.md")) "the device form (\\.\C:\...) is not a NETWORK path: whether it may be opened is another question, and not this function's"
Check (Test-NotRefused "\\.\pipe\x") "nor is a pipe"
Check (Test-NotRefused ("\??\" + $system + ":\folder\x.md")) "nor the NT form of a path on a drive"
Check (Test-NotRefused "\\?\UNCLE\share\x.md") "a name that only BEGINS with UNC behind the prefix is not the UNC form"
Check (Test-NotRefused ($system + ":\UNC\server\share\x.md")) "a folder named UNC on a local drive is a folder"
Check (Test-NotRefused "folder\x.md") "a relative path says nothing of where it is"
Check (Test-NotRefused "x.md") "nor does a bare name"
Check (Test-NotRefused "\folder\x.md") "one leading backslash is the current drive's root, not a server"
Check (Test-NotRefused "/folder/x.md") "and so is one leading forward slash"
Check (Test-NotRefused "folder\\server\share\x.md") "two separators that are not first are not a server"
Check (Test-NotRefused "") "nothing at all is not a network path, and does not throw"

Write-Host ""
Write-Host "--- a network drive is known by its type: the question is answered here, and no drive is made ---" -ForegroundColor Cyan
# A SUITE MUST NOT CHANGE WHAT OTHER PROCESSES OF THE USER SEE. A drive letter is seen by every
# process of the user while it exists, and until 2026-10-13 this suite made one aimed at a host that
# does not exist: while it stood, a fresh powershell of any other session printed "Attempting to
# perform the InitializeDefaultDrives operation on the 'FileSystem' provider failed" (measured that
# day: 7 of 8 starts, each taking 1.4 s where 0.2 is usual). So the one function that asks a drive's
# type is REPLACED here by one that answers from a table of this suite's, and counts who asked. It
# is called exactly as the real one is: one -Letter, a text back. The real one is kept, and asked
# of real drives further down.
$script:realDriveType = ${function:Get-HordeDriveLetterType}
$script:driveTypes = @{}
$script:driveAsked = New-Object System.Collections.ArrayList
function Get-HordeDriveLetterType {
    param([Parameter(Mandatory = $true)][string]$Letter)
    [void]$script:driveAsked.Add($Letter)
    $known = "" + $script:driveTypes[$Letter.ToUpperInvariant()]
    if ($known -ceq "") { return "NoRootDirectory" }
    if ($known -ceq "cannot be asked") { return "" }
    return $known
}
$script:driveTypes = @{ "R" = "Network"; "S" = "Fixed"; "T" = "Removable"; "U" = "CDRom"; "V" = "Ram"; "W" = "Unknown"; "X" = "cannot be asked" }
Check ((Get-Said "R:\x.md") -ceq ("'R:\x.md' is on a network drive (R:), and " + $ownDrives)) "a path on a drive whose type is Network is refused, in the words it has always used, naming the drive"
Check ((Get-Said "\\?\R:\x.md") -like "*is on a network drive (R:)*") "and behind the long-path prefix"
Check ((Get-Said "R:x.md") -like "*is on a network drive (R:)*") "and named from wherever that drive stands"
Check ((Get-Said "r:\x.md") -clike "*is on a network drive (r:)*") "and with its letter in small, which the reason gives as it was written"
Check ((Get-Said "R:") -like "*is on a network drive (R:)*") "and the drive named alone"
Check ((@($script:driveAsked) -join ",") -ceq "R,R,R,r,R") ("the type was asked once for each of those five, of that path's own letter as it was written (" + (@($script:driveAsked) -join ",") + ")")
foreach ($other in @("S", "T", "U", "V", "W")) { Check (Test-NotRefused ($other + ":\x.md")) ("a drive whose type is " + $script:driveTypes[$other] + " is not a network drive: it is not refused") }
Check (Test-NotRefused "Q:\x.md") "a letter no drive has (its type is NoRootDirectory) is not thereby a network drive: it is not refused here"
Check (Test-NotRefused "X:\x.md") "nor is a letter whose type cannot be asked: it goes on, and the open handle's own path decides"
$script:driveAsked.Clear()
$null = Get-Said "\\server\share\x.md"; $null = Get-Said "folder\x.md"; $null = Get-Said "\\?\UNC\server\share\x.md"; $null = Get-Said ""
Check ($script:driveAsked.Count -eq 0) "a path with no drive letter, and a network path known from its text, ask no drive its type"
# A TYPE THAT ONLY LOOKS LIKE THE WORD is not the type.
$script:driveTypes = @{ "R" = "network"; "S" = "Network "; "T" = "NetworkDrive" }
Check ((Test-NotRefused "R:\x.md") -and (Test-NotRefused "S:\x.md") -and (Test-NotRefused "T:\x.md")) "the type is compared exactly: only Network, as Windows writes it, is a network drive"
Set-Item -Path function:Get-HordeDriveLetterType -Value $script:realDriveType
# THE REAL QUESTION, of drives that are really there and of letters nobody made.
Check ((Get-HordeDriveLetterType -Letter $system) -ceq "Fixed") ("CONTROL: the real question says the system drive " + $system + ": is a fixed drive of this machine")
Check ((Get-HordeDriveLetterType -Letter $system.ToLowerInvariant()) -ceq "Fixed") "and so with its letter in small"
$nothingThere = @("QRSTUVWXYZPONMLKJ".ToCharArray() | ForEach-Object { "" + $_ } | Where-Object { -not [System.IO.Directory]::Exists($_ + ":\") -and $null -eq (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) -and @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1) }) -cnotcontains $_ })
Check ($nothingThere.Count -ge 1 -and (Get-HordeDriveLetterType -Letter $nothingThere[0]) -ceq "NoRootDirectory") "a letter that names nothing is of the type NoRootDirectory"
# Asked inside a try, so that an error is a FAILED CHECK and not a broken suite: the changed-mutants
# run of 2026-10-13 showed the mutant that makes this throw crashing the suite, which catches nothing.
function Get-TypeOrThrew { param([string]$Letter) try { return ("" + (Get-HordeDriveLetterType -Letter $Letter)) } catch { return ("threw: " + $_.Exception.Message) } }
Check ((Get-TypeOrThrew "1") -ceq "" -and (Get-TypeOrThrew "??") -ceq "") ("what is no drive letter cannot be asked, and that is an empty answer, never an error ('" + (Get-TypeOrThrew "1") + "', '" + (Get-TypeOrThrew "??") + "')")
Check (Test-NotRefused ($system + ":\folder\x.md")) "CONTROL: with the real question back, a path on a local drive is not refused"

Write-Host ""
Write-Host "--- THE ONE PLACE a real drive letter is made: over a folder of this machine's own drive ---" -ForegroundColor Cyan
# ===================================================================================================
# THIS IS THE ONLY PLACE IN ANY SUITE WHERE A DRIVE LETTER IS DEFINED (test/lib/SuiteFiles.ps1,
# Get-HordeDriveLetterMakers, fails test/test-suite.ps1 for any other). It is aimed at a folder that
# EXISTS on this machine's own drive - never at a host, never at another letter, never at a folder
# that is not there - so that every other process of the user can reach it for the moment it stands
# (measured 2026-10-13: a fresh powershell started while such a letter stood printed nothing and took
# no longer). It stands for five questions and one open, and is removed in the finally.
# WHAT IT IS FOR: everything above answers the type question itself, and so proves nothing about what
# Windows says of a letter that is not a volume. This asks Windows once.
# ===================================================================================================
$oneLetter = ""
if ($nothingThere.Count -ge 1) { $oneLetter = $nothingThere[0] }
$oneFolder = ("" + $env:SystemRoot).TrimEnd('\')
$oneMade = $false; $oneType = "?"; $oneSaid = "?"; $oneOpened = "?"; $oneFile = ""; $oneStands = "?"; $oneAlias = "?"
# files/Path.ps1 asks an open handle where it really is; it loads core/PathText.ps1 again, unchanged.
. (Join-Path $root "files\Path.ps1")
foreach ($there in @("explorer.exe", "notepad.exe", "win.ini")) { if ($oneFile -eq "" -and [System.IO.File]::Exists((Join-Path $oneFolder $there))) { $oneFile = $there } }
if ($oneLetter -ne "" -and [System.IO.Directory]::Exists($oneFolder)) {
    $null = & subst.exe ($oneLetter + ":") $oneFolder
    try {
        $oneMade = ($LASTEXITCODE -eq 0 -and [System.IO.Directory]::Exists($oneLetter + ":\"))
        $oneType = Get-HordeDriveLetterType -Letter $oneLetter
        $oneSaid = Get-Said ($oneLetter + ":\x.md")
        $oneStands = Get-HordeDriveLetterTarget -Letter $oneLetter
        $oneAlias = "" + (Get-HordeDriveAliasRefusal -Path ($oneLetter + ":\x.md"))
        $through = Open-HordeFilesSource -Path ($oneLetter + ":\" + $oneFile)
        if ($through.ok) { $through.stream.Dispose(); $oneOpened = $through.path } else { $oneOpened = "not opened: " + $through.reason }
    } finally { $null = & subst.exe ($oneLetter + ":") /D }
}
Check $oneMade ("CONTROL: a letter (" + $oneLetter + ":) was made over a folder of this machine's own drive that exists (if this fails, the real question was NOT asked of such a letter)")
Check ($oneType -ceq "Fixed") ("the real question says a letter that stands for a folder of a fixed drive is itself Fixed (" + $oneType + ")")
Check ($oneSaid -ceq "") "and a path on it is not refused: it is on this machine's own drive"
Check ($oneStands -ceq ("\??\" + $oneFolder)) ("the real table says that letter stands for the folder it was made over, behind the device prefix (" + $oneStands + ")")
Check ($oneAlias -ceq "") "and the drive-letter question, asked for real, lets a path on it by: it stands for a folder of this machine's own drive"
Check ($oneFile -ne "" -and [string]::Equals($oneOpened, (Join-Path $oneFolder $oneFile), [System.StringComparison]::OrdinalIgnoreCase)) ("a file opened THROUGH that letter has the folder's own path as its open handle's path, with no letter of the alias in it: the one fact of Windows' that the files store's ids rest on, and which no other suite can show without a letter (" + $oneFile + ")")
Check ($oneLetter -ne "" -and -not [System.IO.Directory]::Exists($oneLetter + ":\") -and (Get-HordeDriveLetterType -Letter $oneLetter) -ceq "NoRootDirectory") "that letter is gone again"

Write-Host ""
Write-Host "--- what the text does not show: why a caller asks before it resolves a path AND after ---" -ForegroundColor Cyan
# The function resolves nothing. These two are not its failures; they are what a caller must know.
# Both stand on this machine's own drive, so that "the current drive" is a local one.
Push-Location -LiteralPath ($system + ":\")
try {
    # THE SURPRISE. Windows reads a backslash and then a forward slash as the start of a network
    # path; PowerShell's resolver reads it as a path on the current drive. So a caller that asked
    # only AFTER resolving would be told nothing, and the path as written would still be a server's.
    $slashHost = New-NoHost
    $written = "\/" + $slashHost + "\share\x.md"
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($written)
    Check ($resolved -ceq ($system + ":\" + $slashHost + "\share\x.md")) ("CONTROL: PowerShell resolves \/<host>\share\x.md to a LOCAL path on the current drive (" + ($resolved -replace [regex]::Escape($slashHost), "<host>") + ")")
    Check ((Test-NotRefused $resolved) -and (Test-NetworkPath $written)) "so asked only of the resolved path the function says nothing, and asked of the path AS WRITTEN it refuses: the question comes before the resolve"
} finally { Pop-Location }
# AND THE OTHER WAY ROUND: a PowerShell drive over a share is a network path only once resolved. The
# drive is made here, which looks its host up, so only the answers are checked.
$psLetter = $nothingThere[0]
$psHost = New-NoHost
$null = New-PSDrive -Name $psLetter -PSProvider FileSystem -Root ("\\" + $psHost + "\share") -Scope Script
try {
    $psResolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($psLetter + ":\x.md")
    Check ($psResolved -ceq ("\\" + $psHost + "\share\x.md")) ("CONTROL: a PowerShell drive " + $psLetter + ": was made over a share, and a path on it resolves to the share")
    Check ((Test-NotRefused ($psLetter + ":\x.md")) -and (Test-NetworkPath $psResolved)) "asked of the path as written the function says nothing, and asked of what it resolved to it refuses: the question comes after the resolve too"
} finally { Remove-PSDrive -Name $psLetter -Scope Script }

Write-Host ""
Write-Host "--- the reason is every caller's: it says nothing of what the caller was doing ---" -ForegroundColor Cyan
$anyReason = Get-Said ("\\" + (New-NoHost) + "\folder\x.md")
Check ($anyReason -like "*is a network path, and only a path on one of this machine's own drives is taken" -and $anyReason -notlike "*shar*" -and $anyReason -notlike "*file*") "the reason says the path is a network path and that only a path on this machine's own drives is taken: no word of sharing, or of files, which are one caller's"

Write-Host ""
Write-Host "--- what a drive letter stands for: the system's table is answered here, and no letter is made ---" -ForegroundColor Cyan
function Get-AliasSaid {
    # What the drive-letter question says of -Path, or "threw: <why>": no path may make it throw.
    param([AllowEmptyString()][string]$Path)
    try { return ("" + (Get-HordeDriveAliasRefusal -Path $Path)) } catch { return ("threw: " + $_.Exception.Message) }
}
# THE REAL QUESTION FIRST, of what is really there: it only reads the table.
Check ((Get-HordeDriveLetterTarget -Letter $system) -like "\Device\*") ("the real question says the system drive stands for a volume (" + (Get-HordeDriveLetterTarget -Letter $system) + ")")
Check ((Get-HordeDriveLetterTarget -Letter $nothingThere[0]) -ceq "") "and that a letter that names nothing stands for nothing"
# THEN BOTH QUESTIONS ARE ANSWERED HERE, as the type question was above and for the same reason: a
# letter that stands for another letter, or for a share, is a letter every other process of the
# user would see, and until 2026-10-13 this suite made eleven of them. Each stand-in is called
# exactly as the real function is - one -Letter, a text back - and counts who asked. THE TABLE BELOW
# IS THE SYSTEM'S TABLE OF NAMES AS THIS SUITE SAYS IT IS:
#   C  a volume                         L  a folder of C, as subst makes
#   N  a network drive the system mapped (a redirector's device, not written as a share)
#   R  a share, straight (the device prefix and then UNC)
#   O  the letter N, and P the letter O          (a letter over a network drive, and a chain)
#   G  the letter R                              (a letter over a letter that is straight over a share)
#   M  the letter L, and T the letter M          (a chain that ends at a folder of this machine)
#   J and K each other                           (a ring)
#   A B D E F H I U V                            (the long chains, further down)
$script:realLetterTarget = ${function:Get-HordeDriveLetterTarget}
$script:stands = @{}
$script:targetAsked = New-Object System.Collections.ArrayList
function Get-HordeDriveLetterTarget {
    param([Parameter(Mandatory = $true)][string]$Letter)
    [void]$script:targetAsked.Add($Letter)
    return ("" + $script:stands[$Letter.ToUpperInvariant()])
}
function Get-HordeDriveLetterType {
    param([Parameter(Mandatory = $true)][string]$Letter)
    [void]$script:driveAsked.Add($Letter)
    $known = "" + $script:driveTypes[$Letter.ToUpperInvariant()]
    if ($known -ceq "") { return "NoRootDirectory" }
    if ($known -ceq "cannot be asked") { return "" }
    return $known
}
$aliasHost = New-NoHost
$script:stands = @{ "C" = "\Device\HarddiskVolume3"; "L" = "\??\C:\Windows"; "N" = ("\Device\LanmanRedirector\;N:0000000000012345\" + $aliasHost + "\share"); "R" = ("\??\UNC\" + $aliasHost + "\share")
    "O" = "\??\N:\"; "P" = "\??\O:"; "G" = "\??\R:\"; "M" = "\??\L:"; "T" = "\??\M:"; "J" = "\??\K:"; "K" = "\??\J:" }
$script:driveTypes = @{ "C" = "Fixed"; "L" = "Fixed"; "N" = "Network"; "R" = "Network"; "O" = "NoRootDirectory"; "P" = "NoRootDirectory"; "G" = "NoRootDirectory"; "M" = "Fixed"; "T" = "Fixed" }
$script:driveAsked.Clear()
foreach ($plain in @("C:\folder\x.md", "\\?\C:\folder\x.md", "Q:\x.md", "x.md", "folder\x.md", "", ("\\" + (New-NoHost) + "\share\x.md"), "\\?\UNC\server\share\x.md", "\\.\pipe\x")) {
    Check ((Get-AliasSaid $plain) -ceq "") ("not this question's, and not refused by it: '" + $plain + "'")
}
Check ($script:driveAsked.Count -eq 0) "and for none of those was any drive asked its type: a letter that stands for no other letter is not asked here"
# A LETTER OVER A FOLDER OF THIS MACHINE'S OWN DRIVE, which is what subst is for: let by.
$script:targetAsked.Clear()
Check ((Get-AliasSaid "L:\x.md") -ceq "") "a letter that stands for a folder of this machine's own drive is not refused"
Check ((@($script:targetAsked) -join ",") -ceq "L,C" -and (@($script:driveAsked) -join ",") -ceq "C") ("it was followed to the drive that folder is on, and that drive, the last of the chain, is the one asked its type (asked what they stand for: " + (@($script:targetAsked) -join ",") + "; asked their type: " + (@($script:driveAsked) -join ",") + ")")
# A LETTER OVER A NETWORK DRIVE, and a letter over that.
$script:driveAsked.Clear()
$said = Get-AliasSaid "O:\x.md"
Check ($said -ceq ("'O:\x.md' is on a drive (O:) that stands for a network drive (N:), and " + $ownDrives)) "a letter that stands for a network drive is refused, naming both letters, in every caller's words"
Check ((Get-AliasSaid "\\?\O:\x.md") -like "*is on a drive (O:) that stands for a network drive (N:)*") "and behind the long-path prefix"
Check ((Get-AliasSaid "O:x.md") -like "*is on a drive (O:) that stands for a network drive (N:)*") "and named from wherever that drive stands"
Check ((Get-AliasSaid "o:\x.md") -clike "*is on a drive (o:) that stands for a network drive (N:)*") "and with its letter in small, which the reason gives as it was written"
Check ((Get-AliasSaid "P:\x.md") -like "*is on a drive (P:) that stands for a network drive (N:)*") "a letter that stands for a letter that stands for a network drive is refused too: the chain is followed to its end"
Check ((Get-AliasSaid "G:\x.md") -like "*is on a drive (G:) that stands for a network drive (R:)*") "and so is a letter over a letter that is straight over a share"
# WHO WAS ASKED THEIR TYPE. Measured 2026-10-13 with real letters, when this suite still made them:
# asking the type of the letter that stands OVER a network drive looked the host up, and asking the
# type of the network drive itself did not. So the order is the rule: only the last letter is asked.
$typeAskedOf = @($script:driveAsked | Select-Object -Unique)
Check (($typeAskedOf -join ",") -ceq "N,R" -and $script:driveAsked.Count -eq 6) ("through all six questions only the LAST letter of each chain was asked its type, never the letter that stands over it - which is the asking that looks a host up (asked: " + (@($script:driveAsked) -join ",") + ")")
Check ((Get-AliasSaid "N:\x.md") -ceq "") "a network drive the system mapped stands for no other letter, and its target is not written as a share: this question answers nothing, and the network question refuses it"
Check ((Get-Said "N:\x.md") -like "*is on a network drive (N:)*") "CONTROL: which it does, by the drive's type"
# A LETTER STRAIGHT OVER A SHARE, in the ways the table can hold it, and what only looks like one.
$script:driveAsked.Clear()
foreach ($written in @(("\??\UNC\" + $aliasHost + "\share"), ("\??\unc\" + $aliasHost + "\share"), ("\??\Unc\" + $aliasHost + "\share\deeper"), "\??\UNC")) {
    $script:stands["R"] = $written
    Check ((Get-AliasSaid "R:\x.md") -ceq ("'R:\x.md' is on a drive (R:) that stands for a network share, and " + $ownDrives)) ("a letter that stands for " + ($written -replace [regex]::Escape($aliasHost), "<host>") + " is refused: it stands for a network share")
    Check ((Get-AliasSaid "\\?\R:\x.md") -like "*is on a drive (R:) that stands for a network share*") "behind the long-path prefix too"
}
Check ($script:driveAsked.Count -eq 0) "and for those eight nobody was asked a type at all: the table had already said what the letter is"
foreach ($written in @("\??\UNCLE\share", "\??\C:\UNC\share", "\Device\UNC\share", "\??\UNCshare", "UNC\share")) {
    $script:stands["R"] = $written
    Check ((Get-AliasSaid "R:\x.md") -notlike "*network share*") ("CONTROL: a letter over " + $written + " does not stand for a share, and this rule does not say it does")
}
$script:stands["R"] = "\??\UNC\" + $aliasHost + "\share"
# A RING: two letters that stand for each other never end, and are refused.
Check ((Get-AliasSaid "J:\x.md") -ceq ("'J:\x.md' is on a drive (J:) that stands for another drive letter, and that for another, without end: where it really is cannot be told, and " + $ownDrives)) "two letters that stand for each other are refused: where the path really is cannot be told"
$script:stands["J"] = "\??\J:"
Check ((Get-AliasSaid "J:\x.md") -like "*without end*") "and so is a letter that stands for itself"
# A CHAIN THAT ENDS AT HOME: three letters deep, ending at a folder of this machine's own drive.
Check ((Get-AliasSaid "T:\x.md") -ceq "") "CONTROL: a chain of three letters that ends at a folder of this machine's own drive is not refused"
# HOW LONG A CHAIN IS FOLLOWED. Seven letters that each stand for the next, and then a volume, is
# followed to its end; eight is one more than is followed, and is refused as a ring is. No suite
# could make such a chain while the letters were real.
$links = @("A", "B", "D", "E", "F", "H", "I", "U", "V")
for ($at = 0; $at -lt 7; $at++) { $script:stands[$links[$at]] = "\??\" + $links[$at + 1] + ":" }
$script:stands[$links[7]] = "\Device\HarddiskVolume9"; $script:driveTypes[$links[7]] = "Fixed"
Check ((Get-AliasSaid ($links[0] + ":\x.md")) -ceq "") "a chain of seven letters and then a volume is followed to its end, and is not refused"
$script:driveTypes[$links[7]] = "Network"
Check ((Get-AliasSaid ($links[0] + ":\x.md")) -like ("*is on a drive (A:) that stands for a network drive (" + $links[7] + ":)*")) "and refused when the eighth is a network drive"
$script:stands[$links[7]] = "\??\" + $links[8] + ":"; $script:stands[$links[8]] = "\Device\HarddiskVolume9"; $script:driveTypes[$links[8]] = "Fixed"
Check ((Get-AliasSaid ($links[0] + ":\x.md")) -like "*without end*") "a chain of eight letters is one more than is followed: where it ends is not looked for, and it is refused"
Set-Item -Path function:Get-HordeDriveLetterTarget -Value $script:realLetterTarget
Set-Item -Path function:Get-HordeDriveLetterType -Value $script:realDriveType
Check ((Get-HordeDriveLetterTarget -Letter $system) -like "\Device\*" -and (Get-HordeDriveLetterType -Letter $system) -ceq "Fixed" -and (Get-AliasSaid ($system + ":\folder\x.md")) -ceq "") "the two real questions are back, and a path on the system drive is not refused"

Complete-HordeSuite -Success "A to Z are folded by the code's own hand and nothing else is touched, a network path is refused from its text or its drive's type, and a drive letter that stands for a network drive from the system's table, with nobody asked"
