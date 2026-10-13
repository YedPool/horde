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
#                                     ANY FOLDER NAMED .horde, OR WHOSE NAME BEGINS WITH .horde-,
#                                     anywhere on the way to the file: one rule and no list, so
#                                     that the next folder of that family is covered unnamed;
#                                     .ssh in the user's profile;
#   unless the caller gives -Force    every folder an agent harness keeps its own files in.
#   WHICH FOLDERS ARE A HARNESS'S is each adapter's to say and is read as data
#   (agents/<name>/stores.json, through core/MetricsStore.ps1's Get-HordeAgentStoreRoots): its
#   folder in the profile, and the folder a variable of its own moves its store to. No harness is
#   named here (CONTRIBUTING 14), and a new one is covered the day its folder declares its stores.
#   A HARNESS'S OWN FILE IS NEVER SHARED, whatever the caller says (the review's second round,
#   2026-10-13). A root an adapter declares may be a FILE and not a folder: the one a harness
#   keeps beside its folder, in the profile itself, with its account in it. Until then it was a
#   place like the folder, and -Force shared it. WHETHER A ROOT IS A FILE IS ASKED OF THE DISK,
#   not of its name, so it holds for any root of any adapter, a root its variable names too; a
#   root that is a folder stays a place -Force lifts. AND SO IS ANY FILE BESIDE IT WHOSE NAME
#   BEGINS WITH ITS NAME, in the same folder: measured that day, another tool had left a copy
#   of such a file there with a suffix after its name, and the next suffix is not known. The
#   beginning is compared with A to Z folded, by code units. NOT refused by this: a name that
#   only holds the declared name further on, and the same beginning in any other folder - the
#   rule is about the place the adapter declares, and a copy carried elsewhere is made on
#   purpose, as a hard link is (below); what it holds is still looked into.
#   KNOWN LIMIT: when the declared file is not on the disk, nothing says it is a file, so a copy
#   of it left beside where it was is an ordinary file. The adapter saying "this root is a file"
#   would close that; it is core's reader to change.
#   An adapter that does not say makes the answer unknown, and that is a refusal: a harness nobody
#   described is not left open. So does an agents folder that is not there at all: core answers
#   that with an empty list, which here would deny nothing and say nothing.
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
# THE NAMES. A file whose NAME holds one of the list's words is refused unless the caller gives
# -Force. EACH WORD SAYS WHICH OF TWO WAYS IT IS LOOKED FOR (the list has one entry a word):
#   anywhere   the letters, wherever they stand in the name: credential, secret, key, password,
#              passwd, .env, passphrase, mnemonic, kubeconfig, accesstoken, refreshtoken,
#              authtoken. So htpasswd.txt, MySecretNotes.md and ACCESSTOKEN.txt are refused.
#              THE THREE TOKEN WORDS (the review's next round, 2026-10-13): token is a whole word
#              (below), and as one it let ACCESSTOKEN.txt through, the three words run together
#              with no capital between them. Run together, those three are no ordinary word.
#              NOT CAUGHT, ON PURPOSE: mytoken.txt. Catching it needs a third way of looking (a
#              word that ENDS in token), and the reviewer's word was for these three entries and
#              no new way; the content check still looks into such a file for a token's shape.
#   word       only as a whole word of the name. The name is cut into words at every character
#              that is not a letter or digit of ASCII and where a small letter meets a capital
#              (Get-HordeFilesNameWords), and the entry must be one of them, or one of them with a
#              single s after it: auth.json, oauth_creds.json, cookies.json and oauthCreds.json
#              are refused; author-notes.md, credits.md, privateer.txt and cookiecutter.md are
#              not. An entry of several words (service-account, id_rsa) is those words standing
#              together in order, whatever is between them: serviceAccount.json, id-rsa.txt.
#              THESE WORDS ARE SHORT, and anywhere in a name they would refuse ordinary files
#              (the review's decision, 2026-10-13: "auth" is in author, "cred" in credits, "pem"
#              in template). token IS ONE OF THESE since the second round of that review:
#              anywhere, it refused tokenizer-comparison.md; as a word it still refuses
#              token-budget-analysis.md, and that is accepted. So are pwd, totp, seed, jwt, vault
#              and 2fa (a digit is a letter of a word here, so 2fa is one word).
#   WHAT THE WORD WAY MISSES: a word run into another with no capital between them (authfile.json,
#   AUTHFile.json), and digits count as letters (auth2.json is the word auth2).
#   env IS A WORD AS WELL AS .env ANYWHERE: env.json was shared, because the name has no dot
#   before the letters; as a word it is refused, and so is test-env.md.
#   A PUBLIC KEY (id_rsa.pub) is refused by its name like the private one beside it. Accepted: no
#   type of key file is shared in any case, and -Force is there for a copy saved as text.
# ONE MORE, BY NAME AND FOLDER TOGETHER: a file named exactly config.json in a folder named
# exactly .aws, .azure, .kube or .docker, on the final path, is a cloud tool's sign-in and is
# refused the same way. (The other file such a folder keeps, credentials, holds a word of the
# list and is refused wherever it is.)
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
#     product) costs its owner a -Force. The other words have no such list: secretary.txt and
#     passwordless.md are refused, and -Force shares them.
#
# -Force IS THE CALLER SAYING "this file holds no secret". It lifts the names and the harness
# folders, and the shapes of a token in a text. It is never honoured for the Horde home,
# .horde-secrets, .ssh, a harness's own file or a private key in a text, and the refusal says so.
#   BY DESIGN, AND SAID PLAINLY (the review's second round): with -Force NO shape of a token is
#   looked for at all, only the first line of a private key. And with -Force a file whose name
#   holds no word of the list is shared even when the agents folder is missing or a harness did
#   not say where its folders are: what cannot be told then is only whether the file is in a
#   harness's folder, and that is the thing -Force lifts.
#   INSIDE A HARNESS'S FOLDER -Force LIFTS THE PLACE AND NEVER THE NAME (the review's decision,
#   2026-10-13). What sessions said to a harness is there, and a founder may well want one of
#   those shared; the harness's sign-in is there too, under a name like the ones above. So with
#   -Force a transcript is shared from there and a file named as a secret never is, and the
#   refusal says which of the two rules refused.
#
# WHAT A TEXT FILE HOLDS IS LOOKED AT TOO, before its bytes are kept
# (Get-HordeFilesContentRefusal): a private key's first line is refused whatever the caller
# says, and a token of a known shape unless the caller gives -Force; and, the same way, a secret
# written under its own name (client_secret, api_key, password and three more, in any case, with
# or without underscores or dashes and after any prefix, as a JSON member, as name=value or as YAML:
# core/Secrets.ps1 has the rule, and the names). A picture and a PDF are not
# looked into.
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
# What looks like a credential in a text: the one statement of it, core's.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Secrets.ps1")
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
        words = @(
            @{ word = "credential"; how = "anywhere" }, @{ word = "secret"; how = "anywhere" },
            @{ word = "key"; how = "anywhere" }, @{ word = "password"; how = "anywhere" }, @{ word = "passwd"; how = "anywhere" },
            @{ word = ".env"; how = "anywhere" }, @{ word = "passphrase"; how = "anywhere" }, @{ word = "mnemonic"; how = "anywhere" },
            @{ word = "kubeconfig"; how = "anywhere" },
            @{ word = "accesstoken"; how = "anywhere" }, @{ word = "refreshtoken"; how = "anywhere" }, @{ word = "authtoken"; how = "anywhere" },
            @{ word = "token"; how = "word" },
            @{ word = "auth"; how = "word" }, @{ word = "oauth"; how = "word" }, @{ word = "cred"; how = "word" },
            @{ word = "private"; how = "word" }, @{ word = "wallet"; how = "word" }, @{ word = "cookie"; how = "word" },
            @{ word = "recovery"; how = "word" }, @{ word = "env"; how = "word" }, @{ word = "service-account"; how = "word" },
            @{ word = "id_rsa"; how = "word" }, @{ word = "id_dsa"; how = "word" }, @{ word = "id_ecdsa"; how = "word" }, @{ word = "id_ed25519"; how = "word" },
            @{ word = "pem"; how = "word" }, @{ word = "pfx"; how = "word" }, @{ word = "p12"; how = "word" }, @{ word = "ppk"; how = "word" },
            @{ word = "kdbx"; how = "word" }, @{ word = "jks"; how = "word" }, @{ word = "netrc"; how = "word" }, @{ word = "npmrc"; how = "word" },
            @{ word = "pypirc"; how = "word" }, @{ word = "tfstate"; how = "word" },
            @{ word = "pwd"; how = "word" }, @{ word = "totp"; how = "word" }, @{ word = "seed"; how = "word" }, @{ word = "jwt"; how = "word" },
            @{ word = "vault"; how = "word" }, @{ word = "2fa"; how = "word" }
        )
        ordinary = @{ key = @("keyboard", "keybind", "keymap", "keynote", "keyword", "keyframe", "keystroke", "keypad", "hotkey", "monkey", "donkey", "turkey", "hockey", "jockey", "whiskey") }
        # A file of exactly one of these names, in a folder of exactly one of these names, is a
        # cloud tool's sign-in: its name alone says nothing (config.json is anybody's). The other
        # name such a folder keeps, credentials, is refused wherever it is by the word above.
        signInFolders = @(".aws", ".azure", ".kube", ".docker")
        signInNames = @("config.json")
        # WHAT A TEXT FILE MAY NOT HOLD, by the names core/Secrets.ps1 gives its kinds: only the
        # kinds that know a credential by its SHAPE (Get-HordeFilesContentRefusal says why only
        # those). never is refused whatever the caller says; lifted is what -Force lifts.
        shapes = @{ never = @("a private key"); lifted = @("an access token", "a signed web token", "a webhook address", "a secret written under a name such as client_secret or password") }
    }
}

function Get-HordeFilesNameWords {
    # The words of a file name, in order and in lower case: the name cut at every character that
    # is not one of A to Z, a to z or 0 to 9 - a dot, a dash, an underscore, a blank, and any
    # letter outside ASCII, which so ends a word and never hides one - and where a small letter
    # is followed by a capital (oauthCreds is oauth and creds). The header says what this misses.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name)
    $found = New-Object System.Collections.ArrayList
    $word = New-Object System.Text.StringBuilder
    $afterSmall = $false
    foreach ($character in $Name.ToCharArray()) {
        $code = [int]$character
        $capital = ($code -ge 65 -and $code -le 90)
        $small = ($code -ge 97 -and $code -le 122)
        if (-not ($capital -or $small -or ($code -ge 48 -and $code -le 57))) {
            if ($word.Length -gt 0) { [void]$found.Add($word.ToString()); [void]$word.Clear() }
            $afterSmall = $false
            continue
        }
        if ($capital -and $afterSmall -and $word.Length -gt 0) { [void]$found.Add($word.ToString()); [void]$word.Clear() }
        if ($capital) { $code += 32 }
        [void]$word.Append([char]$code)
        $afterSmall = $small
    }
    if ($word.Length -gt 0) { [void]$found.Add($word.ToString()) }
    return @($found.ToArray())
}

function Get-HordeFilesDenyWord {
    # The word of the list that the file name -Name holds, or "" when it holds none. The words
    # are tried in the list's order, each in its own way (the header has the two ways).
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name)
    $list = Get-HordeFilesDenyList
    $lowered = ConvertTo-HordeAsciiLower -Text $Name
    $nameWords = @(Get-HordeFilesNameWords -Name $Name)
    foreach ($entry in $list.words) {
        $word = "" + $entry.word
        if ($entry.how -ceq "anywhere") {
            $rest = $lowered
            # An ordinary word leaves a bar, which no file name holds, so what stood on its two
            # sides never joins into the word.
            foreach ($plain in @($list.ordinary[$word])) { if ("$plain" -ne "") { $rest = $rest.Replace($plain, "|") } }
            if ($rest.Contains($word)) { return $word }
            continue
        }
        # AS WHOLE WORDS: the entry's own words (service-account is two), standing together and
        # in order among the name's. The last may have one s after it: cookies, creds.
        $wanted = @(Get-HordeFilesNameWords -Name $word)
        for ($at = 0; $at + $wanted.Count -le $nameWords.Count; $at++) {
            $fits = $true
            for ($part = 0; $part -lt $wanted.Count; $part++) {
                $have = $nameWords[$at + $part]
                $same = [string]::Equals($have, $wanted[$part], [System.StringComparison]::Ordinal)
                if (-not $same -and $part -eq ($wanted.Count - 1)) { $same = [string]::Equals($have, ($wanted[$part] + "s"), [System.StringComparison]::Ordinal) }
                if (-not $same) { $fits = $false; break }
            }
            if ($fits) { return $word }
        }
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
        [void]$places.Add([pscustomobject]@{ kind = "ssh"; path = (Join-Path $profileDir $list.sshFolder); force = $false })
    }
    # THE HARNESSES, ASKED TWICE: under the profile the variable names, with wherever a harness's
    # own variable moved its store, and then under the system's profile.
    $unknown = ""
    $from = @{}
    if ($RepoRoot -ne "") { $from = @{ Root = $RepoRoot } }
    # NO agents FOLDER IS NOT "NO HARNESSES" (the header says why): it is asked here, of the same
    # folder core reads, before core answers with a list that is empty.
    $shipped = $RepoRoot
    if ($shipped -eq "") { $shipped = Split-Path -Parent $PSScriptRoot }
    $agentsFolder = Join-Path $shipped "agents"
    $agentsThere = [System.IO.Directory]::Exists($agentsFolder)
    if (-not $agentsThere) { $unknown = "there is no folder '" + $agentsFolder + "', where each harness says which folders are its own" }
    foreach ($under in @("", $profiles.system)) {
        if (-not $agentsThere) { break }
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

function Get-HordeFilesHarnessFile {
    # The declared root that makes the file at -FinalPath a harness's own file, or "" when none
    # does: one of -Known, the paths a root is known by (Resolve-HordeFilesDenyPlace), that IS A
    # FILE on the disk, with -FinalPath in the same folder under a name that begins with its name
    # (the header says why, and what this does not see). The root itself is the plainest case of
    # it. A to Z are folded and nothing else; the comparison is by code units.
    param([Parameter(Mandatory = $true)][string]$FinalPath, [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Known)
    $cut = $FinalPath.LastIndexOf('\')
    if ($cut -lt 0) { return "" }
    $folderOfIt = ConvertTo-HordeAsciiLower -Text $FinalPath.Substring(0, $cut)
    $nameOfIt = ConvertTo-HordeAsciiLower -Text $FinalPath.Substring($cut + 1)
    foreach ($declared in @($Known)) {
        $at = $declared.LastIndexOf('\')
        if ($at -lt 0 -or $at -eq ($declared.Length - 1)) { continue }
        # ASKED OF THE DISK, and only whether a file has that name: nothing is opened.
        if (-not [System.IO.File]::Exists($declared)) { continue }
        $sameFolder = [string]::Equals($folderOfIt, (ConvertTo-HordeAsciiLower -Text $declared.Substring(0, $at)), [System.StringComparison]::Ordinal)
        if ($sameFolder -and $nameOfIt.StartsWith((ConvertTo-HordeAsciiLower -Text $declared.Substring($at + 1)), [System.StringComparison]::Ordinal)) { return $declared }
    }
    return ""
}

function Get-HordeFilesNameRefusal {
    # Why the NAME of the file at -FinalPath is one a file of secrets has, as the start of a
    # sentence, or "" when it is not: a word of the list in the file's own name, or a cloud
    # tool's sign-in by its name and its folder's together. -Parts is the path cut at its
    # separators, as Get-HordeFilesDenyRefusal cut it.
    param([Parameter(Mandatory = $true)][string[]]$Parts)
    $list = Get-HordeFilesDenyList
    $leaf = $Parts[$Parts.Count - 1]
    $word = Get-HordeFilesDenyWord -Name $leaf
    if ($word -ne "") { return ("its name, '" + $leaf + "', holds '" + $word + "', as a file of secrets is named") }
    if ($Parts.Count -ge 3) {
        $folderOfIt = ConvertTo-HordeAsciiLower -Text $Parts[$Parts.Count - 2]
        $nameOfIt = ConvertTo-HordeAsciiLower -Text $leaf
        $inSignInFolder = $false
        foreach ($listed in $list.signInFolders) { if ([string]::Equals($folderOfIt, $listed, [System.StringComparison]::Ordinal)) { $inSignInFolder = $true } }
        if ($inSignInFolder) {
            foreach ($listed in $list.signInNames) { if ([string]::Equals($nameOfIt, $listed, [System.StringComparison]::Ordinal)) { return ("its name, '" + $leaf + "', in a folder named '" + $Parts[$Parts.Count - 2] + "', is what a cloud tool calls the file it keeps its sign-in in") } }
        }
    }
    return ""
}

function Get-HordeFilesDenyRefusal {
    # Why the file whose open handle's path is -FinalPath is not shared, or "" when the list has
    # nothing against it. The header has every rule. What -Force never lifts is judged first, so
    # that a file in the Horde home is refused for that and not for its name.
    param([Parameter(Mandatory = $true)][string]$FinalPath, [string]$HordeHome = "", [string]$RepoRoot = "", [switch]$Force)
    $list = Get-HordeFilesDenyList
    $what = @{ home = "the Horde home, where Horde keeps its own records, keys and settings"; secrets = ("a " + $list.secretsFolder + " folder, where credentials are kept"); ssh = "the folder the user's SSH keys are kept in"; agent = "a folder an agent harness keeps its own files in (its settings, its sign-in and what was said to it)" }
    $never = ". Nothing there is ever shared, and -Force does not change that"
    $insist = ". If this file holds no secret, share it again with -Force"
    $found = Get-HordeFilesDenyPlaces -HordeHome $HordeHome -RepoRoot $RepoRoot
    # Cut by hand, not handed to System.IO.Path: a final path may be far longer than 260 characters
    # (the store's suite shares one of 578), and files/Share.ps1 measured that a path that long
    # cannot be looked at without its prefix. The first part is the drive, the last the file's
    # name, and what is between are the folders.
    $parts = @($FinalPath -split '\\')
    if ($found.unknownNever -ne "") { return ($found.unknownNever + ", so whether '" + $FinalPath + "' is in " + $what.home + " or among the user's own keys cannot be told" + $never) }
    # The harness folder the file is in, as it is written; and, when that cannot be told, why not.
    $harness = ""
    $harnessDoubt = ""
    foreach ($lifted in @($false, $true)) {
        if ($lifted) {
            # BETWEEN THE TWO ROUNDS: the two folder names that are refused wherever they stand - a
            # copy of a home, or a home on another drive, still holds a home's files - and then
            # everything after this is what -Force lifts.
            for ($at = 1; $at -lt ($parts.Count - 1); $at++) {
                # ONE RULE, NOT A LIST (the review's decision, 2026-10-13): a folder named exactly
                # as the home is, or beginning with that name and a dash, is Horde's own. The
                # home, its credentials folder, and whatever folder of that family comes next are
                # covered the day they are made, with nobody adding a name here.
                $folderName = ConvertTo-HordeAsciiLower -Text $parts[$at]
                $isHordes = [string]::Equals($folderName, $list.homeFolder, [System.StringComparison]::Ordinal)
                if (-not $isHordes) { $isHordes = $folderName.StartsWith(($list.homeFolder + "-"), [System.StringComparison]::Ordinal) }
                if ($isHordes) { return ("'" + $FinalPath + "' is under a folder named '" + $parts[$at] + "': a folder named " + $list.homeFolder + ", or one whose name begins with " + $list.homeFolder + "-, is Horde's own, where it keeps its records, keys and credentials" + $never) }
            }
            if ($found.unknown -ne "") { $harnessDoubt = "which folders the agent harnesses keep their own files in is not known (" + $found.unknown + "), so whether '" + $FinalPath + "' is in one cannot be told" }
        }
        foreach ($place in @($found.places | Where-Object { $_.force -eq $lifted })) {
            $where = Resolve-HordeFilesDenyPlace -Path $place.path
            if ($where.unknown) {
                $untold = "where " + $what[$place.kind] + " ('" + $place.path + "') really is could not be told, so whether '" + $FinalPath + "' is in it cannot be told either"
                if (-not $lifted) { return ($untold + $never) }
                if ($harnessDoubt -eq "") { $harnessDoubt = $untold }
                continue
            }
            # A HARNESS'S OWN FILE, AND A COPY LEFT BESIDE IT: never lifted (the header says why),
            # so it is answered here, before anything -Force lifts is weighed.
            if ($lifted) {
                $ownFile = Get-HordeFilesHarnessFile -FinalPath $FinalPath -Known @($where.paths)
                if ($ownFile -ne "") {
                    $itself = [string]::Equals((ConvertTo-HordeAsciiLower -Text $FinalPath), (ConvertTo-HordeAsciiLower -Text $ownFile), [System.StringComparison]::Ordinal)
                    $ownsIt = ". A harness's own file is never shared, and -Force does not change that"
                    if ($itself) { return ("'" + $FinalPath + "' is an agent harness's own file, the one it keeps beside its folder with its account and its settings in it ('" + $place.path + "')" + $ownsIt) }
                    return ("'" + $FinalPath + "' is beside an agent harness's own file ('" + $place.path + "') and its name begins with that file's name, as a copy or a backup of it does" + $ownsIt)
                }
            }
            foreach ($folder in @($where.paths)) {
                if (-not (Test-HordeFilesPathUnder -Path $FinalPath -Folder $folder)) { continue }
                if (-not $lifted) { return ("'" + $FinalPath + "' is under " + $what[$place.kind] + " ('" + $place.path + "')" + $never) }
                if ($harness -eq "") { $harness = "" + $place.path }
            }
        }
    }
    # WHAT -Force LIFTS: the harness folders, and the name. The place is said first, so that
    # without -Force a file in a harness's folder is refused for the folder, whatever its name.
    $named = Get-HordeFilesNameRefusal -Parts $parts
    if (-not $Force) {
        if ($harness -ne "") { return ("'" + $FinalPath + "' is under " + $what.agent + " ('" + $harness + "')" + $insist) }
        if ($harnessDoubt -ne "") { return ($harnessDoubt + $insist) }
        if ($named -ne "") { return ($named + ", so it is not shared" + $insist) }
        return ""
    }
    # WITH -Force THE PLACE IS LIFTED AND THE NAME, INSIDE A HARNESS'S FOLDER, IS NOT (the header
    # says why). A folder that cannot be told to be no harness's is held to the same: -Force must
    # not share a harness's sign-in because nobody could say where the harness keeps it.
    if ($named -ne "" -and $harness -ne "") { return ($named + ", and it is under " + $what.agent + " ('" + $harness + "'). -Force shares other files from such a folder, and never one that is named so") }
    if ($named -ne "" -and $harnessDoubt -ne "") { return ($named + ", and " + $harnessDoubt + ". -Force never shares a file that is named so from a harness's folder, so it is not shared from here either") }
    return ""
}

function Get-HordeFilesContentRefusal {
    # Why a TEXT file holding -Bytes is not shared for what it holds, or "" when nothing in it has
    # the shape of a credential. Asked after the bytes are known to be strict UTF-8
    # (files/Text.ps1) and BEFORE anything is kept: a shared file leaves the machine, and a key
    # pasted into a report leaves with it whatever the report is called.
    #   - THE ONE STATEMENT OF WHAT A CREDENTIAL LOOKS LIKE IS core/Secrets.ps1's, and no pattern
    #     is written here. The list (Get-HordeFilesDenyList, shapes) names which of its kinds are
    #     asked for, and a name core does not have throws there rather than finding nothing.
    #   - ONLY THE KINDS THAT KNOW A CREDENTIAL BY ITS SHAPE (the review's decision, 2026-10-13): a
    #     private key's first line, a token with a known prefix, a signed web token, a webhook
    #     address. core's other kinds go by a word beside any text (password=..., a bearer value)
    #     or by how random a long run looks, and those are what ordinary reports are full of: a
    #     page that explains a setting, a hash, a picture written as base64. A refusal that fires
    #     on ordinary files teaches everyone to type -Force, so they are not asked for at all.
    #     Measured 2026-10-13 on a sample of what sessions write: the pull request has the count.
    #     ONE KIND GOES BY A NAME AND IS ASKED FOR ALL THE SAME (the review's second round): a
    #     secret under one of six member names, as a client file of a sign-in provider holds it.
    #     It is asked for because a placeholder is told from a value there; the pull request
    #     has its count on the same sample.
    #   - A PRIVATE KEY IS NEVER LIFTED; the other shapes are what -Force lifts. WITH -Force
    #     THEY ARE NOT LOOKED FOR AT ALL: that is by design, and the command's help says it.
    #   - THE REFUSAL NAMES THE KIND AND NEVER WHAT WAS FOUND: a reason is printed and logged.
    #   WHAT THIS DOES NOT SEE: a picture or a PDF (never looked into); a credential written in
    #   another encoding of itself (base64 of a key, an escaped form); one cut across two lines;
    #   and any secret that has no shape, which is most passwords.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes, [switch]$Force)
    $list = Get-HordeFilesDenyList
    $text = [System.Text.Encoding]::UTF8.GetString($Bytes)
    $neverKind = Find-HordeSecretKind -Text $text -Kinds @($list.shapes.never)
    if ($neverKind -ne "") { return ("what it holds looks like " + $neverKind + ": the line such a key begins with is in it. A file that holds one is never shared, and -Force does not change that") }
    if ($Force) { return "" }
    $liftedKind = Find-HordeSecretKind -Text $text -Kinds @($list.shapes.lifted)
    if ($liftedKind -ne "") { return ("what it holds looks like " + $liftedKind + ", by its shape; what was found is not repeated here. If this file holds no secret, share it again with -Force") }
    return ""
}
