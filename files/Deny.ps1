# files/Deny.ps1 - the deny list: the places and the names `horde files share` refuses.
#
# THE ONE JOB of this file, and THE ONE PLACE the list is written. Until 2026-10-13 a share copied
# anything the user could read that had an allowed extension: measured that day, a JSON file in the
# Horde home's settings folder, one under .horde-secrets, one under .ssh, one in each agent harness's
# own folder and one named api-key.txt were each shared (review of the files store). A shared file
# leaves the machine, so those are refused here, each with its reason.
#
# THE PLACES. A file in one of these folders, at any depth, is refused:
#   never, whatever the caller says   the Horde home (its records, its keys and its settings), and
#                                     .horde in the user's profile, which is the home unless a
#                                     variable moved it; .horde-secrets in the user's profile; and
#                                     any folder named .horde or .horde-secrets anywhere on the way
#                                     to the file;
#   unless the caller gives -Force    .ssh in the user's profile; and every folder an agent harness
#                                     keeps its own files in.
#   WHICH FOLDERS ARE A HARNESS'S is each adapter's to say and is read as data
#   (agents/<name>/stores.json, through core/MetricsStore.ps1's Get-HordeAgentStoreRoots): its
#   folder in the profile, and the folder a variable of its own moves its store to. No harness is
#   named here (CONTRIBUTING 14), and a new one is covered the day its folder declares its stores.
#   An adapter that does not say makes the answer unknown, and that is a refusal: a harness nobody
#   described is not left open.
#   EVERY PLACE IS WORKED OUT TWICE, AND BOTH ANSWERS ARE REFUSED. The review of this list
#   (2026-10-13) set USERPROFILE to an empty folder and shared, with no -Force, a file in the real
#   .ssh, a harness's real sign-in file and the real home's settings; and with HORDE_HOME set
#   elsewhere, a file in the profile's own .horde. Whoever runs the command sets its variables, so
#   a place that only a variable names is a place the caller chose. So the profile is asked of the
#   variable, as before - a home or a store that really was moved is where the variable says - AND
#   of the operating system (Get-HordeFilesOsProfile), which no variable moves: measured the same
#   day on Windows PowerShell 5.1.26100, with USERPROFILE, HOMEDRIVE and HOMEPATH all changed in
#   the process, the answer was the one from before. Under each of the two: .horde,
#   .horde-secrets, .ssh, and every harness's folder. The configured home is beside them, and a
#   harness's folder that its own variable moved is beside its usual one, which is still refused.
#
# THE NAMES. A file whose NAME holds one of the words credential, secret, token, key, password or
# .env is refused unless the caller gives -Force.
#   - THE FILE'S OWN NAME ONLY, extension included; not the folders it is in. A folder is a place,
#     and the places are above. KNOWN COST: an innocently named file in a folder called "secrets"
#     is shared. Judging every folder's name was weighed and left out: a session's own working
#     folder is often named for its task (a branch about token budgets, say), every share from it
#     would then need -Force, and a -Force that is always given protects nothing.
#   - ANYWHERE IN THE NAME, in any case of A to Z: api-key.txt, API_KEY.txt, MySecretNotes.md,
#     passwords.md, prod.env.txt. The fold is the code's own (A to Z only, no case table of the
#     runtime's), and the comparison is by code units. Measured 2026-10-13: PowerShell's -ceq and
#     -ccontains, and a hashtable's keys, take a name holding U+00AD for the name without it; the
#     calls used here (.Contains, .Replace, an ordinal Equals and StartsWith) do not.
#     KNOWN LIMIT: a look-alike letter is not the letter, and a word broken by a character
#     (pass-word, s3cret) is not the word. The list catches the names secrets are usually given.
#   - "key" WOULD REFUSE keyboard.md AND monkey.png, so the ordinary words below are taken out of
#     the name before "key" is looked for. The rule fails towards refusing: api-key.txt,
#     id_rsa.key.txt, keys.json, mykey.txt and keyed.md are refused, monkey-api-key.txt is refused
#     (the word that is left is "key"), and an ordinary word that is not on the list (a surname, a
#     product) costs its owner a -Force. The other words have no such list: tokenizer.md and
#     secretary.txt are refused, and -Force shares them.
#
# -Force IS THE CALLER SAYING "this file holds no secret". It lifts the names, .ssh and the
# harness folders. It is never honoured for the Horde home or .horde-secrets, and the refusal says so.
#
# EVERY RULE JUDGES THE FINAL PATH OF THE OPEN HANDLE, never the path that was written
# (files/Path.ps1): a link, a junction, a subst drive, an 8.3 short name or the long-path prefix
# would otherwise walk round the list. AND THE PLACES ARE ASKED THE SAME QUESTION: each folder is
# opened and its own final path taken (Get-HordeFilesFolderFinalPath), so a HORDE_HOME that is
# itself reached through a link is still the folder the file is in. A place that is there and
# cannot be asked is a refusal, not a pass.
#   WHAT THIS DOES NOT SEE: a hard link. Measured 2026-10-13, a second name outside .ssh for a file
#   inside it: the handle's final path is the name that was opened, and nothing marks the file. A
#   hard link is made on purpose, as a copy is; the list is for the share nobody meant to make.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
# The fold of A to Z, and the questions asked of a path's text: the one copy, core's.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\PathText.ps1")
# Where each agent harness keeps its own files: read as data, never named.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\MetricsStore.ps1")
. (Join-Path $PSScriptRoot "Path.ps1")

function Get-HordeFilesDenyList {
    # THE LIST, and the only copy of it: test/test-files-deny.ps1 attacks every entry from both sides.
    #   secretsFolder, sshFolder   folder names, in the user's profile.
    #   words                      what a file's name may not hold, in lower case.
    #   ordinary                   for a word, the ordinary words holding it that are no secret.
    return [pscustomobject]@{
        # What core/Home.ps1 calls the home when no variable moves it. That file is the one that
        # decides; test/test-files-deny.ps1 fails when the two names come to differ.
        homeFolder = ".horde"
        secretsFolder = ".horde-secrets"
        sshFolder = ".ssh"
        words = @("credential", "secret", "token", "key", "password", ".env")
        ordinary = @{ key = @("keyboard", "keybind", "keymap", "keynote", "keyword", "keyframe", "keystroke", "keypad", "hotkey", "monkey", "donkey", "turkey", "hockey", "jockey", "whiskey") }
    }
}

function Get-HordeFilesDenyWord {
    # The word of the list that the file name -Name holds, or "" when it holds none.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name)
    $list = Get-HordeFilesDenyList
    $lowered = ConvertTo-HordeAsciiLower -Text $Name
    foreach ($word in $list.words) {
        $rest = $lowered
        # An ordinary word leaves a bar, which no file name holds, so what stood on its two sides
        # never joins into the word.
        foreach ($plain in @($list.ordinary[$word])) { if ("$plain" -ne "") { $rest = $rest.Replace($plain, "|") } }
        if ($rest.Contains($word)) { return $word }
    }
    return ""
}

function Test-HordeFilesPathUnder {
    # Is -Path the folder -Folder, or anything inside it? Both are final paths, so the names are as
    # the disk holds them; A to Z are folded and nothing else, and the comparison is by code units.
    # The separator is part of it: C:\x\abc is not inside C:\x\ab.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Folder)
    $inner = ConvertTo-HordeAsciiLower -Text $Path
    $outer = (ConvertTo-HordeAsciiLower -Text $Folder).TrimEnd('\')
    return ([string]::Equals($inner, $outer, [System.StringComparison]::Ordinal) -or $inner.StartsWith(($outer + "\"), [System.StringComparison]::Ordinal))
}

function Get-HordeFilesOsProfile {
    # The user's profile AS THE OPERATING SYSTEM SAYS IT, which no variable of the caller's moves
    # (the header has the measurement), or "" when it will not say. THE ONE PLACE THAT QUESTION IS
    # ASKED: a suite replaces this function, called exactly as it is here, so that no test looks
    # at the real profile of the machine it runs on.
    return ("" + [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile))
}

function Get-HordeFilesDenyProfiles {
    # The profiles the places are worked out under: { variable; system }, each a path or "".
    # variable is what USERPROFILE says now, system what the operating system says. Both are used,
    # and the header says why neither is enough alone.
    return [pscustomobject]@{ variable = "$env:USERPROFILE".Trim(); system = ("" + (Get-HordeFilesOsProfile)).Trim() }
}

function Get-HordeFilesDenyPlaces {
    # The folders of the list for this user and this home: { places; unknown; unknownNever }.
    # places is { kind: home | secrets | ssh | agent; path; force }, path as it is written and
    # force whether -Force lifts it; a folder that two ways of asking both name is there once.
    # unknown is why the harnesses' folders could not be learned, or "". unknownNever is why a
    # place -Force never lifts could not be learned, or "".
    # -RepoRoot is where the agents folder is read from, for a caller that must not use the real one.
    param([string]$HordeHome = "", [string]$RepoRoot = "")
    $list = Get-HordeFilesDenyList
    $places = New-Object System.Collections.ArrayList
    $base = $HordeHome
    if ($base -eq "") { $base = Get-HordeHome }
    [void]$places.Add([pscustomobject]@{ kind = "home"; path = $base; force = $false })
    # THE TWO PROFILES (the header says why two). With none in the variable there is no such folder
    # to name: core/Home.ps1 has already refused a home then. THE SYSTEM'S IS NOT LET OFF SO: when it
    # will not say, where the real home, .horde-secrets and .ssh are is not known, and that is a
    # refusal -Force does not lift.
    $profiles = Get-HordeFilesDenyProfiles
    $unknownNever = ""
    if ($profiles.system -eq "") { $unknownNever = "the operating system would not say where the user's profile is" }
    foreach ($profileDir in @($profiles.variable, $profiles.system)) {
        if ($profileDir -eq "") { continue }
        [void]$places.Add([pscustomobject]@{ kind = "home"; path = (Join-Path $profileDir $list.homeFolder); force = $false })
        [void]$places.Add([pscustomobject]@{ kind = "secrets"; path = (Join-Path $profileDir $list.secretsFolder); force = $false })
        [void]$places.Add([pscustomobject]@{ kind = "ssh"; path = (Join-Path $profileDir $list.sshFolder); force = $true })
    }
    # THE HARNESSES, ASKED TWICE: under the profile the variable names, with wherever a harness's
    # own variable moved its store, and then under the system's profile.
    $unknown = ""
    $from = @{}
    if ($RepoRoot -ne "") { $from = @{ Root = $RepoRoot } }
    foreach ($under in @("", $profiles.system)) {
        $stores = $null
        if ($under -eq "") { $stores = Get-HordeAgentStoreRoots @from } else { $stores = Get-HordeAgentStoreRoots @from -ProfileRoot $under }
        if ($stores.state -cne "known") { $unknown = "" + $stores.reason }
        else { foreach ($storeRoot in @($stores.value)) { [void]$places.Add([pscustomobject]@{ kind = "agent"; path = ("" + $storeRoot); force = $true }) } }
    }
    # A folder that two ways of asking both name is one place, and is opened and asked once.
    $once = New-Object System.Collections.ArrayList
    foreach ($place in $places) {
        $have = $false
        foreach ($kept in $once) { if ($kept.kind -ceq $place.kind -and [string]::Equals($kept.path, $place.path, [System.StringComparison]::Ordinal)) { $have = $true } }
        if (-not $have) { [void]$once.Add($place) }
    }
    return [pscustomobject]@{ places = @($once.ToArray()); unknown = $unknown; unknownNever = $unknownNever }
}

function Resolve-HordeFilesDenyPlace {
    # The paths one folder of the list is known by: { paths; unknown }. paths holds it as written,
    # made whole, and where it really is when that is another path; unknown is true when it is there
    # and Windows would not say where, or it is no path at all.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path)
    $whole = ""
    try { $whole = [System.IO.Path]::GetFullPath($Path) } catch { return [pscustomobject]@{ paths = @(); unknown = $true } }
    if ($whole -cmatch '\A\\\\\?\\[A-Za-z]:\\') { $whole = $whole.Substring(4) }
    # A FOLDER ON THE NETWORK IS NEVER LOOKED AT, here as anywhere (files/Path.ps1), and holds no
    # file of this machine's drives; what is no drive path at all holds none either.
    if ((Get-HordeDriveAliasRefusal -Path $whole) -ne "" -or (Get-HordeNetworkPathRefusal -Path $whole) -ne "" -or $whole -cnotmatch '\A[A-Za-z]:\\') { return [pscustomobject]@{ paths = @(); unknown = $false } }
    $known = New-Object System.Collections.ArrayList
    [void]$known.Add($whole.TrimEnd('\'))
    # Behind the long-path prefix, so a deep folder is opened too; the path is already whole.
    $asked = Get-HordeFilesFolderFinalPath -Path ("\\?\" + $whole)
    if ($asked.state -ceq "unknown") { return [pscustomobject]@{ paths = @($known.ToArray()); unknown = $true } }
    if ($asked.state -ceq "ok") {
        $real = Resolve-HordeFilesLocalPath -Final $asked.path
        if ($real.ok) { [void]$known.Add($real.path.TrimEnd('\')) }
    }
    return [pscustomobject]@{ paths = @($known.ToArray()); unknown = $false }
}

function Get-HordeFilesDenyRefusal {
    # Why the file whose open handle's path is -FinalPath is not shared, or "" when the list has
    # nothing against it. The header has every rule. What -Force never lifts is judged first, so
    # that a file in the Horde home is refused for that and not for its name.
    param([Parameter(Mandatory = $true)][string]$FinalPath, [string]$HordeHome = "", [string]$RepoRoot = "", [switch]$Force)
    $list = Get-HordeFilesDenyList
    $what = @{ home = "the Horde home, where Horde keeps its own records, keys and settings"; homeNamed = ("a " + $list.homeFolder + " folder, where Horde keeps its own records, keys and settings"); secrets = ("a " + $list.secretsFolder + " folder, where credentials are kept"); ssh = "the folder the user's SSH keys are kept in"; agent = "a folder an agent harness keeps its own files in (its settings, its sign-in and what was said to it)" }
    $never = ". Nothing there is ever shared, and -Force does not change that"
    $insist = ". If this file holds no secret, share it again with -Force"
    $found = Get-HordeFilesDenyPlaces -HordeHome $HordeHome -RepoRoot $RepoRoot
    # Cut by hand, not handed to System.IO.Path: a final path may be far longer than 260 characters
    # (the store's suite shares one of 578), and files/Share.ps1 measured that a path that long
    # cannot be looked at without its prefix. The first part is the drive, the last the file's
    # name, and what is between are the folders.
    $parts = @($FinalPath -split '\\')
    if ($found.unknownNever -ne "") { return ($found.unknownNever + ", so whether '" + $FinalPath + "' is in " + $what.home + " or among the user's own keys cannot be told" + $never) }
    foreach ($lifted in @($false, $true)) {
        if ($lifted) {
            # BETWEEN THE TWO ROUNDS: the two folder names that are refused wherever they stand - a
            # copy of a home, or a home on another drive, still holds a home's files - and then
            # everything after this is what -Force lifts.
            for ($at = 1; $at -lt ($parts.Count - 1); $at++) {
                $folderName = ConvertTo-HordeAsciiLower -Text $parts[$at]
                if ([string]::Equals($folderName, $list.secretsFolder, [System.StringComparison]::Ordinal)) { return ("'" + $FinalPath + "' is under " + $what.secrets + $never) }
                if ([string]::Equals($folderName, $list.homeFolder, [System.StringComparison]::Ordinal)) { return ("'" + $FinalPath + "' is under " + $what.homeNamed + $never) }
            }
            if ($Force) { return "" }
            if ($found.unknown -ne "") { return ("which folders the agent harnesses keep their own files in is not known (" + $found.unknown + "), so whether '" + $FinalPath + "' is in one cannot be told" + $insist) }
        }
        foreach ($place in @($found.places | Where-Object { $_.force -eq $lifted })) {
            $where = Resolve-HordeFilesDenyPlace -Path $place.path
            $ending = $never; if ($lifted) { $ending = $insist }
            if ($where.unknown) { return ("where " + $what[$place.kind] + " ('" + $place.path + "') really is could not be told, so whether '" + $FinalPath + "' is in it cannot be told either" + $ending) }
            foreach ($folder in @($where.paths)) {
                if (Test-HordeFilesPathUnder -Path $FinalPath -Folder $folder) { return ("'" + $FinalPath + "' is under " + $what[$place.kind] + " ('" + $place.path + "')" + $ending) }
            }
        }
    }
    $leaf = $parts[$parts.Count - 1]
    $word = Get-HordeFilesDenyWord -Name $leaf
    if ($word -ne "") { return ("its name, '" + $leaf + "', holds '" + $word + "', as a file of secrets is named, so it is not shared" + $insist) }
    return ""
}
