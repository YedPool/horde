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
#   - a network drive is refused by its type, behind the long-path prefix and in small letters too,
#     and asking the type looks nobody up;
#   - what is not a network path is not refused: a local drive, the long-path prefix, the device
#     form, a relative path, a letter no drive has;
#   - what the function cannot see, it is shown not to see, so that a caller knows to ask twice:
#     a PowerShell drive over a share, and the spelling PowerShell's resolver takes for a local path;
#   - the reason speaks for every caller: no word of sharing, which is one caller's;
#   - a drive letter that stands for a network drive is refused from the system's table of names, a
#     chain of letters to its end and a ring of them too, and the host is NOT looked up - while the
#     network question, asked of the same letter, refuses nothing and does look it up (the control).
#
# Nothing here is written to a disk, no host that exists is named, and every drive letter the suite
# defines it takes away again.

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
Check ((New-Object System.IO.DriveInfo($system)).DriveType -eq [System.IO.DriveType]::Fixed) ("CONTROL: the system drive " + $system + ": is a fixed drive of this machine")
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
Write-Host "--- a network drive is known by its type, and asking the type looks nobody up ---" -ForegroundColor Cyan
if (-not ([System.Management.Automation.PSTypeName]"HordeTest.DosDevice").Type) {
    Add-Type -Namespace HordeTest -Name DosDevice -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool DefineDosDevice(int dwFlags, string lpDeviceName, string lpTargetPath); [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern int QueryDosDevice(string lpDeviceName, System.Text.StringBuilder lpTargetPath, int ucchMax);'
}
function Test-DosDevice { param([string]$Letter) return ([HordeTest.DosDevice]::QueryDosDevice($Letter + ":", (New-Object System.Text.StringBuilder 1024), 1024) -gt 0) }
function Get-FreeLetter {
    # A drive letter that names nothing: no drive, no device, and no PowerShell drive.
    foreach ($candidate in "RSTUVWQPONMLKJ".ToCharArray()) { if (-not (Test-DosDevice ("" + $candidate)) -and $null -eq (Get-PSDrive -Name ("" + $candidate) -ErrorAction SilentlyContinue)) { return ("" + $candidate) } }
    return ""
}
$noLetter = Get-FreeLetter
Check ($noLetter -ne "" -and (Test-NotRefused ($noLetter + ":\x.md"))) ("a letter no drive has (" + $noLetter + ":) is not thereby a network drive: it is not refused here")
# A NETWORK DRIVE: a drive letter aimed at a host that does not exist, which connects to nothing.
$netLetter = Get-FreeLetter
$netHost = New-NoHost
$netTarget = "\??\UNC\" + $netHost + "\share"
$netMade = [HordeTest.DosDevice]::DefineDosDevice(1, $netLetter + ":", $netTarget)
try {
    Check ($netLetter -ne "" -and $netMade -and (New-Object System.IO.DriveInfo($netLetter)).DriveType -eq [System.IO.DriveType]::Network) ("CONTROL: the drive letter " + $netLetter + ": was aimed at a share, and its type is Network (if this fails, a network drive was NOT tested)")
    Check ((Get-Said ($netLetter + ":\x.md")) -ceq ("'" + $netLetter + ":\x.md' is on a network drive (" + $netLetter + ":), and " + $ownDrives)) "a path on a network drive is refused by the drive's type, in every caller's words, naming the drive"
    Check ((Get-Said ("\\?\" + $netLetter + ":\x.md")) -like ("*is on a network drive (" + $netLetter + ":)*")) "and behind the long-path prefix"
    Check ((Get-Said ($netLetter + ":x.md")) -like ("*is on a network drive (" + $netLetter + ":)*")) "and named from wherever that drive stands"
    Check ((Get-Said (($netLetter + ":\x.md").ToLowerInvariant())) -clike ("*is on a network drive (" + $netLetter.ToLowerInvariant() + ":)*")) "and with its letter in small, which the reason gives as it was written"
    $cacheNow = Get-LookedUp
    if ($canSee) { Check (-not $cacheNow.Contains($netHost)) "and the drive's host was not looked up: asking a drive's type asks nobody" }
    $null = [System.IO.File]::Exists($netLetter + ":\x.md")
    if ($canSee) { Check ((Get-LookedUp).Contains($netHost)) "CONTROL: asked whether a file on that drive exists, the host IS looked up - that is what the question comes before" }
} finally { $null = [HordeTest.DosDevice]::DefineDosDevice(7, $netLetter + ":", $netTarget) }
Check (-not (Test-DosDevice $netLetter)) "the network drive letter is gone again"
Check (Test-NotRefused ($system + ":\folder\x.md")) "CONTROL: after all that, a path on a local drive is still not refused"

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
$psLetter = Get-FreeLetter
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
Write-Host "--- what a drive letter stands for: read from the system's table, and nobody is asked ---" -ForegroundColor Cyan
function Get-AliasSaid {
    # What the drive-letter question says of -Path, or "threw: <why>": no path may make it throw.
    param([AllowEmptyString()][string]$Path)
    try { return ("" + (Get-HordeDriveAliasRefusal -Path $Path)) } catch { return ("threw: " + $_.Exception.Message) }
}
function Get-Stands { param([string]$Letter) $text = New-Object System.Text.StringBuilder 1024; if ([HordeTest.DosDevice]::QueryDosDevice($Letter + ":", $text, 1024) -le 0) { return "" }; return $text.ToString() }
function Remove-Letter { param([string]$Letter) $was = Get-Stands $Letter; if ($was -ne "") { $null = [HordeTest.DosDevice]::DefineDosDevice(7, $Letter + ":", $was) } }
$free = @("RSTUVWQPONMLKJ".ToCharArray() | ForEach-Object { "" + $_ } | Where-Object { -not (Test-DosDevice $_) -and -not [System.IO.Directory]::Exists($_ + ":\") -and $null -eq (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) })
Check ($free.Count -ge 3) ("CONTROL: three drive letters that name nothing were found (" + $free.Count + ")")
Check ((Get-HordeDriveLetterTarget -Letter $system) -like "\Device\*") ("the system drive stands for a volume (" + (Get-HordeDriveLetterTarget -Letter $system) + ")")
Check ((Get-HordeDriveLetterTarget -Letter $free[0]) -ceq "") "a letter that names nothing stands for nothing"
foreach ($plain in @(($system + ":\folder\x.md"), ("\\?\" + $system + ":\folder\x.md"), ($free[0] + ":\x.md"), "x.md", "folder\x.md", "", ("\\" + (New-NoHost) + "\share\x.md"), "\\?\UNC\server\share\x.md", "\\.\pipe\x")) {
    Check ((Get-AliasSaid $plain) -ceq "") ("not this question's, and not refused by it: '" + $plain + "'")
}
# A LETTER OVER A FOLDER OF THIS MACHINE'S OWN DRIVE, which is what subst is for: let by.
$localFolder = ("" + $env:SystemRoot).TrimEnd('\')
$overLocal = "?"; $overLocalTarget = ""
$null = & subst.exe ($free[0] + ":") $localFolder
try { $overLocalTarget = Get-HordeDriveLetterTarget -Letter $free[0]; $overLocal = Get-AliasSaid ($free[0] + ":\x.md") } finally { $null = & subst.exe ($free[0] + ":") /D }
Check ($overLocalTarget -ceq ("\??\" + $localFolder)) ("CONTROL: a subst drive stands for the folder it was made over (" + $overLocalTarget + ")")
Check ($overLocal -ceq "") "a letter that stands for a folder of this machine's own drive is not refused"
# A LETTER OVER A NETWORK DRIVE, and a letter over that. The network drive is a letter aimed at a host
# that does not exist; every question below is asked before the cache is read.
$netLetter = $free[0]; $overLetter = $free[1]; $overOver = $free[2]
$aliasHost = New-NoHost
$aliasTarget = "\??\UNC\" + $aliasHost + "\share"
$netIs = $false; $overIs = ""; $said = "?"; $saidPrefix = "?"; $saidRelative = "?"; $saidSmall = "?"; $saidChain = "?"; $saidNet = "?"; $seenAfter = $true; $typeOver = ""; $controlSeen = $false; $networkSaysOfOver = "?"
$null = [HordeTest.DosDevice]::DefineDosDevice(1, $netLetter + ":", $aliasTarget)
try {
    $netIs = ((New-Object System.IO.DriveInfo($netLetter)).DriveType -eq [System.IO.DriveType]::Network)
    $null = [HordeTest.DosDevice]::DefineDosDevice(0, $overLetter + ":", $netLetter + ":\")
    $overIs = Get-Stands $overLetter
    $null = [HordeTest.DosDevice]::DefineDosDevice(1, $overOver + ":", "\??\" + $overLetter + ":")
    $said = Get-AliasSaid ($overLetter + ":\x.md")
    $saidPrefix = Get-AliasSaid ("\\?\" + $overLetter + ":\x.md")
    $saidRelative = Get-AliasSaid ($overLetter + ":x.md")
    $saidSmall = Get-AliasSaid (($overLetter + ":\x.md").ToLowerInvariant())
    $saidChain = Get-AliasSaid ($overOver + ":\x.md")
    $saidNet = Get-AliasSaid ($netLetter + ":\x.md")
    $seenAfter = (Get-LookedUp).Contains($aliasHost)
    # THE CONTROL, and why this question comes before the other: the network question asks the
    # letter's type, the type is not Network, and the asking looks the host up.
    $typeOver = "" + (New-Object System.IO.DriveInfo($overLetter)).DriveType
    $networkSaysOfOver = Get-Said ($overLetter + ":\x.md")
    $controlSeen = (Get-LookedUp).Contains($aliasHost)
} finally { Remove-Letter $overOver; Remove-Letter $overLetter; $null = [HordeTest.DosDevice]::DefineDosDevice(7, $netLetter + ":", $aliasTarget) }
Check ($netIs -and $overIs -ceq ("\??\" + $netLetter + ":\")) ("CONTROL: " + $netLetter + ": was aimed at a share and is a network drive, and " + $overLetter + ": stands for it (" + $overIs + "); if this fails, the case was NOT tested")
Check ($said -ceq ("'" + $overLetter + ":\x.md' is on a drive (" + $overLetter + ":) that stands for a network drive (" + $netLetter + ":), and " + $ownDrives)) "a letter that stands for a network drive is refused, naming both letters, in every caller's words"
Check ($saidPrefix -like ("*is on a drive (" + $overLetter + ":) that stands for a network drive (" + $netLetter + ":)*")) "and behind the long-path prefix"
Check ($saidRelative -like ("*is on a drive (" + $overLetter + ":) that stands for a network drive (" + $netLetter + ":)*")) "and named from wherever that drive stands"
Check ($saidSmall -clike ("*is on a drive (" + $overLetter.ToLowerInvariant() + ":) that stands for a network drive (" + $netLetter + ":)*")) "and with its letter in small, which the reason gives as it was written"
Check ($saidChain -like ("*is on a drive (" + $overOver + ":) that stands for a network drive (" + $netLetter + ":)*")) "a letter that stands for a letter that stands for a network drive is refused too: the chain is followed to its end"
Check ($saidNet -ceq "") "a network drive itself stands for no other letter: this question answers nothing, and the network question refuses it"
if ($canSee) { Check (-not $seenAfter) "and through all six questions the host was NOT looked up: the system's table was read, and nobody was asked" }
if ($canSee) { Check ($typeOver -cne "Network" -and $networkSaysOfOver -ceq "" -and $controlSeen) ("CONTROL: the network question, asked of that letter, refuses nothing (its type is " + $typeOver + ", not Network) and the host IS looked up - which is why this question is asked first") }
else { Write-Skip "WHETHER THE DRIVE-LETTER QUESTION LOOKED A HOST UP COULD NOT BE SEEN on this machine; its answers were still checked." }
Check (-not (Test-DosDevice $netLetter) -and -not (Test-DosDevice $overLetter) -and -not (Test-DosDevice $overOver)) "all three drive letters are gone again"
# A RING: two letters that stand for each other never end, and are refused.
$ring = "?"
$null = [HordeTest.DosDevice]::DefineDosDevice(1, $free[0] + ":", "\??\" + $free[1] + ":")
$null = [HordeTest.DosDevice]::DefineDosDevice(1, $free[1] + ":", "\??\" + $free[0] + ":")
try { $ring = Get-AliasSaid ($free[0] + ":\x.md") } finally { Remove-Letter $free[0]; Remove-Letter $free[1] }
Check ($ring -ceq ("'" + $free[0] + ":\x.md' is on a drive (" + $free[0] + ":) that stands for another drive letter, and that for another, without end: where it really is cannot be told, and " + $ownDrives)) "two letters that stand for each other are refused: where the path really is cannot be told"
# A CHAIN THAT ENDS AT HOME: three letters deep, ending at a folder of this machine's own drive.
$deep = "?"
$null = & subst.exe ($free[0] + ":") $localFolder
$null = [HordeTest.DosDevice]::DefineDosDevice(1, $free[1] + ":", "\??\" + $free[0] + ":")
$null = [HordeTest.DosDevice]::DefineDosDevice(1, $free[2] + ":", "\??\" + $free[1] + ":")
try { $deep = Get-AliasSaid ($free[2] + ":\x.md") } finally { Remove-Letter $free[2]; Remove-Letter $free[1]; $null = & subst.exe ($free[0] + ":") /D }
Check ($deep -ceq "") "CONTROL: a chain of three letters that ends at a folder of this machine's own drive is not refused"
Check (-not (Test-DosDevice $free[0]) -and -not (Test-DosDevice $free[1]) -and -not (Test-DosDevice $free[2])) "and every letter this suite defined is gone again"

Complete-HordeSuite -Success "A to Z are folded by the code's own hand and nothing else is touched, a network path is refused from its text or its drive's type, and a drive letter that stands for a network drive from the system's table, with nobody asked"
