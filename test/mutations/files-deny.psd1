# Mutations of files/Deny.ps1: the places and the names `horde files share` refuses. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-deny.psd1
# Each takes a word or a place off the list, lets -Force lift what it never may, or judges a path
# more loosely than code unit for code unit; test\test-files-deny.ps1 must fail for every one.
@{
    Target = "files\Deny.ps1"
    Suite  = "test\test-files-deny.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- the list itself ---
        @{ Name = "word-credential-off-the-list"
           Find = '@{ word = "credential"; how = "anywhere" }'
           Replace = '@{ word = "zzzzzz"; how = "anywhere" }' }
        @{ Name = "word-secret-off-the-list"
           Find = '@{ word = "secret"; how = "anywhere" }'
           Replace = '@{ word = "zzzzzz"; how = "anywhere" }' }
        @{ Name = "word-token-off-the-list"
           Find = '@{ word = "token"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-token-looked-for-anywhere-in-a-name"
           Find = '@{ word = "token"; how = "word" }'
           Replace = '@{ word = "token"; how = "anywhere" }' }
        @{ Name = "word-passphrase-off-the-list"
           Find = '@{ word = "passphrase"; how = "anywhere" }'
           Replace = '@{ word = "zzzzzz"; how = "anywhere" }' }
        @{ Name = "word-passphrase-only-as-a-whole-word"
           Find = '@{ word = "passphrase"; how = "anywhere" }'
           Replace = '@{ word = "passphrase"; how = "word" }' }
        @{ Name = "word-mnemonic-off-the-list"
           Find = '@{ word = "mnemonic"; how = "anywhere" }'
           Replace = '@{ word = "zzzzzz"; how = "anywhere" }' }
        @{ Name = "word-mnemonic-only-as-a-whole-word"
           Find = '@{ word = "mnemonic"; how = "anywhere" }'
           Replace = '@{ word = "mnemonic"; how = "word" }' }
        @{ Name = "word-kubeconfig-off-the-list"
           Find = '@{ word = "kubeconfig"; how = "anywhere" }'
           Replace = '@{ word = "zzzzzz"; how = "anywhere" }' }
        @{ Name = "word-kubeconfig-only-as-a-whole-word"
           Find = '@{ word = "kubeconfig"; how = "anywhere" }'
           Replace = '@{ word = "kubeconfig"; how = "word" }' }
        @{ Name = "word-pwd-off-the-list"
           Find = '@{ word = "pwd"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-pwd-looked-for-anywhere-in-a-name"
           Find = '@{ word = "pwd"; how = "word" }'
           Replace = '@{ word = "pwd"; how = "anywhere" }' }
        @{ Name = "word-totp-off-the-list"
           Find = '@{ word = "totp"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-totp-looked-for-anywhere-in-a-name"
           Find = '@{ word = "totp"; how = "word" }'
           Replace = '@{ word = "totp"; how = "anywhere" }' }
        @{ Name = "word-seed-off-the-list"
           Find = '@{ word = "seed"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-seed-looked-for-anywhere-in-a-name"
           Find = '@{ word = "seed"; how = "word" }'
           Replace = '@{ word = "seed"; how = "anywhere" }' }
        @{ Name = "word-jwt-off-the-list"
           Find = '@{ word = "jwt"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-jwt-looked-for-anywhere-in-a-name"
           Find = '@{ word = "jwt"; how = "word" }'
           Replace = '@{ word = "jwt"; how = "anywhere" }' }
        @{ Name = "word-vault-off-the-list"
           Find = '@{ word = "vault"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-vault-looked-for-anywhere-in-a-name"
           Find = '@{ word = "vault"; how = "word" }'
           Replace = '@{ word = "vault"; how = "anywhere" }' }
        @{ Name = "word-2fa-off-the-list"
           Find = '@{ word = "2fa"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-2fa-looked-for-anywhere-in-a-name"
           Find = '@{ word = "2fa"; how = "word" }'
           Replace = '@{ word = "2fa"; how = "anywhere" }' }
        @{ Name = "word-key-off-the-list"
           Find = '@{ word = "key"; how = "anywhere" }'
           Replace = '@{ word = "zzzzzz"; how = "anywhere" }' }
        @{ Name = "word-password-off-the-list"
           Find = '@{ word = "password"; how = "anywhere" }'
           Replace = '@{ word = "zzzzzz"; how = "anywhere" }' }
        @{ Name = "word-passwd-off-the-list"
           Find = '@{ word = "passwd"; how = "anywhere" }'
           Replace = '@{ word = "zzzzzz"; how = "anywhere" }' }
        @{ Name = "word-dot-env-off-the-list"
           Find = '@{ word = ".env"; how = "anywhere" }'
           Replace = '@{ word = "zzzzzz"; how = "anywhere" }' }
        @{ Name = "word-auth-off-the-list"
           Find = '@{ word = "auth"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-oauth-off-the-list"
           Find = '@{ word = "oauth"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-cred-off-the-list"
           Find = '@{ word = "cred"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-private-off-the-list"
           Find = '@{ word = "private"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-wallet-off-the-list"
           Find = '@{ word = "wallet"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-cookie-off-the-list"
           Find = '@{ word = "cookie"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-recovery-off-the-list"
           Find = '@{ word = "recovery"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-env-off-the-list"
           Find = '@{ word = "env"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-service-account-off-the-list"
           Find = '@{ word = "service-account"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-id-rsa-off-the-list"
           Find = '@{ word = "id_rsa"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-id-dsa-off-the-list"
           Find = '@{ word = "id_dsa"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-id-ecdsa-off-the-list"
           Find = '@{ word = "id_ecdsa"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-id-ed25519-off-the-list"
           Find = '@{ word = "id_ed25519"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-pem-off-the-list"
           Find = '@{ word = "pem"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-pfx-off-the-list"
           Find = '@{ word = "pfx"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-p12-off-the-list"
           Find = '@{ word = "p12"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-ppk-off-the-list"
           Find = '@{ word = "ppk"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-kdbx-off-the-list"
           Find = '@{ word = "kdbx"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-jks-off-the-list"
           Find = '@{ word = "jks"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-netrc-off-the-list"
           Find = '@{ word = "netrc"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-npmrc-off-the-list"
           Find = '@{ word = "npmrc"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-pypirc-off-the-list"
           Find = '@{ word = "pypirc"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        @{ Name = "word-tfstate-off-the-list"
           Find = '@{ word = "tfstate"; how = "word" }'
           Replace = '@{ word = "zzzzzz"; how = "word" }' }
        # --- the two ways a word is looked for, and how a name is cut into words ---
        @{ Name = "short-words-looked-for-anywhere"
           Find = 'if ($entry.how -ceq "anywhere") {'
           Replace = 'if ($true) {' }
        @{ Name = "long-words-looked-for-as-whole-words"
           Find = 'if ($entry.how -ceq "anywhere") {'
           Replace = 'if ($false) {' }
        @{ Name = "no-s-after-a-short-word"
           Find = 'if (-not $same -and $part -eq ($wanted.Count - 1)) {'
           Replace = 'if ($false) {' }
        @{ Name = "an-s-after-any-word-of-an-entry"
           Find = 'if (-not $same -and $part -eq ($wanted.Count - 1)) {'
           Replace = 'if (-not $same) {' }
        @{ Name = "any-ending-after-a-short-word"
           Find = '$same = [string]::Equals($have, ($wanted[$part] + "s"), [System.StringComparison]::Ordinal)'
           Replace = '$same = $have.StartsWith($wanted[$part], [System.StringComparison]::Ordinal)' }
        @{ Name = "words-of-an-entry-need-not-be-different-words"
           Find = '$have = $nameWords[$at + $part]'
           Replace = '$have = $nameWords[$at]' }
        @{ Name = "name-not-cut-where-a-small-letter-meets-a-capital"
           Find = 'if ($capital -and $afterSmall -and $word.Length -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "name-cut-at-every-capital"
           Find = 'if ($capital -and $afterSmall -and $word.Length -gt 0) {'
           Replace = 'if ($capital -and $word.Length -gt 0) {' }
        @{ Name = "a-digit-ends-a-word"
           Find = 'if (-not ($capital -or $small -or ($code -ge 48 -and $code -le 57))) {'
           Replace = 'if (-not ($capital -or $small)) {' }
        @{ Name = "a-letter-outside-ascii-joins-two-words"
           Find = 'if (-not ($capital -or $small -or ($code -ge 48 -and $code -le 57))) {'
           Replace = 'if (-not ($capital -or $small -or $code -gt 127 -or ($code -ge 48 -and $code -le 57))) {' }
        @{ Name = "words-of-a-name-keep-their-case"
           Find = 'if ($capital) { $code += 32 }'
           Replace = '' }
        @{ Name = "last-word-of-a-name-lost"
           Find = '    if ($word.Length -gt 0) { [void]$found.Add($word.ToString()) }'
           Replace = '' }
        # --- a cloud tool's sign-in: the name and the folder together ---
        @{ Name = "sign-in-folder-aws-off-the-list"
           Find = 'signInFolders = @(".aws", ".azure", ".kube", ".docker")'
           Replace = 'signInFolders = @(".zzzzzz", ".azure", ".kube", ".docker")' }
        @{ Name = "sign-in-folder-azure-off-the-list"
           Find = 'signInFolders = @(".aws", ".azure", ".kube", ".docker")'
           Replace = 'signInFolders = @(".aws", ".zzzzzz", ".kube", ".docker")' }
        @{ Name = "sign-in-folder-kube-off-the-list"
           Find = 'signInFolders = @(".aws", ".azure", ".kube", ".docker")'
           Replace = 'signInFolders = @(".aws", ".azure", ".zzzzzz", ".docker")' }
        @{ Name = "sign-in-folder-docker-off-the-list"
           Find = 'signInFolders = @(".aws", ".azure", ".kube", ".docker")'
           Replace = 'signInFolders = @(".aws", ".azure", ".kube", ".zzzzzz")' }
        @{ Name = "sign-in-name-off-the-list"
           Find = 'signInNames = @("config.json")'
           Replace = 'signInNames = @("zzzzzz.json")' }
        @{ Name = "sign-in-name-refused-in-every-folder"
           Find = 'if ($inSignInFolder) {'
           Replace = 'if ($true) {' }
        @{ Name = "sign-in-name-never-refused"
           Find = 'if ($inSignInFolder) {'
           Replace = 'if ($false) {' }
        @{ Name = "sign-in-folder-is-the-one-above"
           Find = '$folderOfIt = ConvertTo-HordeAsciiLower -Text $Parts[$Parts.Count - 2]'
           Replace = '$folderOfIt = ConvertTo-HordeAsciiLower -Text $Parts[$Parts.Count - 3]' }
        @{ Name = "sign-in-folder-compared-with-its-case"
           Find = '$folderOfIt = ConvertTo-HordeAsciiLower -Text $Parts[$Parts.Count - 2]'
           Replace = '$folderOfIt = $Parts[$Parts.Count - 2]' }
        @{ Name = "sign-in-name-compared-with-its-case"
           Find = '$nameOfIt = ConvertTo-HordeAsciiLower -Text $leaf'
           Replace = '$nameOfIt = $leaf' }
        @{ Name = "secrets-folder-under-another-name"
           Find = 'secretsFolder = ".horde-secrets"'
           Replace = 'secretsFolder = ".horde-secret"' }
        @{ Name = "another-name-for-the-folder-of-ssh"
           Find = 'sshFolder = ".ssh"'
           Replace = 'sshFolder = ".sshx"' }
        @{ Name = "first-ordinary-word-dropped"
           Find = '@("keyboard", "keybind", '
           Replace = '@("keybind", ' }
        @{ Name = "an-ordinary-word-in-the-middle-dropped"
           Find = '"keypad", "hotkey", "monkey", '
           Replace = '"keypad", "monkey", ' }
        @{ Name = "last-ordinary-word-dropped"
           Find = '"jockey", "whiskey") }'
           Replace = '"jockey") }' }
        # --- a name ---
        @{ Name = "ordinary-words-not-taken-out-of-a-name"
           Find = '{ $rest = $rest.Replace($plain, "|") }'
           Replace = '{ }' }
        @{ Name = "ordinary-word-leaves-no-gap"
           Find = '$rest = $rest.Replace($plain, "|")'
           Replace = '$rest = $rest.Replace($plain, "")' }
        @{ Name = "name-compared-with-its-case"
           Find = '$lowered = ConvertTo-HordeAsciiLower -Text $Name'
           Replace = '$lowered = $Name' }
        @{ Name = "word-looked-for-by-the-runtimes-own-comparison"
           Find = 'if ($rest.Contains($word)) { return $word }'
           Replace = 'if ($rest.IndexOf($word) -ge 0) { return $word }' }
        @{ Name = "every-name-holds-a-word"
           Find = 'if ($rest.Contains($word)) { return $word }'
           Replace = 'if ($true) { return $word }' }
        @{ Name = "no-name-holds-a-word"
           Find = 'if ($rest.Contains($word)) { return $word }'
           Replace = 'if ($false) { return $word }' }
        # --- is a path under a folder ---
        @{ Name = "separator-not-part-of-the-edge"
           Find = '$inner.StartsWith(($outer + "\"), [System.StringComparison]::Ordinal)'
           Replace = '$inner.StartsWith($outer, [System.StringComparison]::Ordinal)' }
        @{ Name = "folder-compared-by-the-runtimes-own-comparison"
           Find = '$inner.StartsWith(($outer + "\"), [System.StringComparison]::Ordinal)'
           Replace = '$inner.StartsWith(($outer + "\"))' }
        @{ Name = "every-case-of-every-letter-folded"
           Find = '$inner.StartsWith(($outer + "\"), [System.StringComparison]::Ordinal)'
           Replace = '$inner.StartsWith(($outer + "\"), [System.StringComparison]::OrdinalIgnoreCase)' }
        @{ Name = "the-folder-itself-is-not-under-it"
           Find = '[string]::Equals($inner, $outer, [System.StringComparison]::Ordinal) -or '
           Replace = '' }
        @{ Name = "path-compared-with-its-case"
           Find = '$inner = ConvertTo-HordeAsciiLower -Text $Path'
           Replace = '$inner = $Path' }
        @{ Name = "folder-compared-with-its-case"
           Find = '$outer = (ConvertTo-HordeAsciiLower -Text $Folder).TrimEnd(''\'')'
           Replace = '$outer = $Folder.TrimEnd(''\'')' }
        @{ Name = "folder-written-with-its-separator-is-another-folder"
           Find = '$outer = (ConvertTo-HordeAsciiLower -Text $Folder).TrimEnd(''\'')'
           Replace = '$outer = (ConvertTo-HordeAsciiLower -Text $Folder)' }
        # --- the places ---
        @{ Name = "force-lifts-the-home"
           Find = 'kind = "home"; path = $base; force = $false'
           Replace = 'kind = "home"; path = $base; force = $true' }
        @{ Name = "force-lifts-the-secrets-folder-of-the-profile"
           Find = 'path = (Join-Path $profileDir $list.secretsFolder); force = $false'
           Replace = 'path = (Join-Path $profileDir $list.secretsFolder); force = $true' }
        @{ Name = "force-lifts-ssh"
           Find = 'path = (Join-Path $profileDir $list.sshFolder); force = $false'
           Replace = 'path = (Join-Path $profileDir $list.sshFolder); force = $true' }
        @{ Name = "force-does-not-lift-a-harness-folder"
           Find = 'kind = "agent"; path = ("" + $storeRoot); force = $true'
           Replace = 'kind = "agent"; path = ("" + $storeRoot); force = $false' }
        @{ Name = "home-not-a-place"
           Find = '[void]$places.Add([pscustomobject]@{ kind = "home"; path = $base; force = $false; relay = ""; what = "" })'
           Replace = '' }
        @{ Name = "home-is-the-ambient-one-whatever-home-is-given"
           Find = 'if ($base -eq "") { $base = Get-HordeHome }'
           Replace = '$base = Get-HordeHome' }
        @{ Name = "secrets-folder-of-the-profile-not-a-place"
           Find = '[void]$places.Add([pscustomobject]@{ kind = "secrets"; path = (Join-Path $profileDir $list.secretsFolder); force = $false; relay = ""; what = "" })'
           Replace = '' }
        @{ Name = "no-place-for-the-profiles-ssh"
           Find = '[void]$places.Add([pscustomobject]@{ kind = "ssh"; path = (Join-Path $profileDir $list.sshFolder); force = $false; relay = ""; what = "" })'
           Replace = '' }
        @{ Name = "harness-folders-not-places"
           Find = '[void]$places.Add([pscustomobject]@{ kind = "agent"; path = ("" + $storeRoot); force = $true; relay = ""; what = "" })'
           Replace = '' }
        @{ Name = "harnesses-read-from-the-real-repository-whatever-is-given"
           Find = 'if ($RepoRoot -ne "") { $from = @{ Root = $RepoRoot } }'
           Replace = 'if ($false) { $from = @{ Root = $RepoRoot } }' }
        # --- the union: every place under the variable's profile AND under the system's ---
        @{ Name = "places-not-worked-out-under-the-systems-profile"
           Find = 'foreach ($profileDir in @($profiles.variable, $profiles.system)) {'
           Replace = 'foreach ($profileDir in @($profiles.variable)) {' }
        @{ Name = "places-not-worked-out-under-the-variables-profile"
           Find = 'foreach ($profileDir in @($profiles.variable, $profiles.system)) {'
           Replace = 'foreach ($profileDir in @($profiles.system)) {' }
        @{ Name = "harnesses-not-asked-under-the-systems-profile"
           Find = 'foreach ($under in @("", $profiles.system)) {'
           Replace = 'foreach ($under in @("")) {' }
        @{ Name = "harnesses-asked-only-under-the-systems-profile"
           Find = 'foreach ($under in @("", $profiles.system)) {'
           Replace = 'foreach ($under in @($profiles.system)) {' }
        @{ Name = "systems-profile-not-handed-to-the-harness-question"
           Find = '$stores = Get-HordeAgentStoreRoots @from -ProfileRoot $under }'
           Replace = '$stores = Get-HordeAgentStoreRoots @from }' }
        @{ Name = "the-profiles-own-home-folder-not-a-place"
           Find = '[void]$places.Add([pscustomobject]@{ kind = "home"; path = (Join-Path $profileDir $list.homeFolder); force = $false; relay = ""; what = "" })'
           Replace = '' }
        @{ Name = "force-lifts-the-profiles-own-home-folder"
           Find = 'path = (Join-Path $profileDir $list.homeFolder); force = $false'
           Replace = 'path = (Join-Path $profileDir $list.homeFolder); force = $true' }
        @{ Name = "the-system-is-asked-by-reading-the-variable"
           Find = 'return ("" + [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile))'
           Replace = 'return ("" + $env:USERPROFILE)' }
        @{ Name = "the-systems-profile-is-taken-from-the-variable"
           Find = 'system = ("" + (Get-HordeFilesOsProfile)).Trim() }'
           Replace = 'system = "$env:USERPROFILE".Trim() }' }
        @{ Name = "the-variables-profile-is-taken-from-the-system"
           Find = 'variable = "$env:USERPROFILE".Trim(); system'
           Replace = 'variable = ("" + (Get-HordeFilesOsProfile)).Trim(); system' }
        @{ Name = "a-system-that-will-not-say-is-not-a-refusal"
           Find = 'if ($profiles.system -eq "") { $unknownNever ='
           Replace = 'if ($false) { $unknownNever =' }
        @{ Name = "a-system-that-will-not-say-not-refused"
           Find = 'if ($found.unknownNever -ne "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-folder-named-twice-is-two-places"
           Find = 'if (-not $have) { [void]$once.Add($place) }'
           Replace = '[void]$once.Add($place)' }
        @{ Name = "home-folder-under-another-name"
           Find = 'homeFolder = ".horde"'
           Replace = 'homeFolder = ".hordes"' }
        @{ Name = "folder-on-the-way-compared-with-its-case"
           Find = '$folderName = ConvertTo-HordeAsciiLower -Text $parts[$at]'
           Replace = '$folderName = $parts[$at]' }
        @{ Name = "harness-that-does-not-say-is-left-open"
           Find = 'if ($stores.state -cne "known") { $unknown = "" + $stores.reason }'
           Replace = 'if ($false) { $unknown = "" + $stores.reason }' }
        # --- where a place really is ---
        @{ Name = "place-not-asked-where-it-really-is"
           Find = 'if ($asked.state -ceq "ok") {'
           Replace = 'if ($false) {' }
        @{ Name = "place-that-cannot-be-asked-taken-for-absent"
           Find = 'if ($asked.state -ceq "unknown") { return [pscustomobject]@{ paths = @($known.ToArray()); unknown = $true } }'
           Replace = '' }
        @{ Name = "place-not-known-by-its-written-path"
           Find = '[void]$known.Add($whole.TrimEnd(''\''))'
           Replace = '' }
        @{ Name = "place-behind-the-prefix-not-known"
           Find = 'if ($whole -cmatch ''\A\\\\\?\\[A-Za-z]:\\'') { $whole = $whole.Substring(4) }'
           Replace = '' }
        @{ Name = "place-on-a-network-drive-opened"
           Find = ' -or (Get-HordeNetworkPathRefusal -Path $whole) -ne "" -or '
           Replace = ' -or ' }
        @{ Name = "place-on-a-letter-over-a-network-drive-opened"
           Find = 'if ((Get-HordeDriveAliasRefusal -Path $whole) -ne "" -or '
           Replace = 'if (' }
        @{ Name = "path-that-is-no-path-taken-for-absent"
           Find = 'catch { return [pscustomobject]@{ paths = @(); unknown = $true } }'
           Replace = 'catch { return [pscustomobject]@{ paths = @(); unknown = $false } }' }
        # --- the refusal ---
        @{ Name = "force-lifts-everything"
           Find = '    foreach ($lifted in @($false, $true)) {'
           Replace = '    if ($Force) { return "" }; foreach ($lifted in @($false, $true)) {' }
        @{ Name = "what-force-lifts-judged-as-what-it-never-lifts"
           Find = 'Where-Object { $_.force -eq $lifted }'
           Replace = 'Where-Object { $true }' }
        # --- Horde's own folders by one rule: the name .horde, or a name that begins with .horde- ---
        @{ Name = "hordes-own-folder-by-its-exact-name-not-refused"
           Find = '$isHordes = [string]::Equals($folderName, $list.homeFolder, [System.StringComparison]::Ordinal)'
           Replace = '$isHordes = $false' }
        @{ Name = "hordes-own-folders-by-the-start-of-their-name-not-refused"
           Find = 'if (-not $isHordes) { $isHordes = $folderName.StartsWith(($list.homeFolder + "-"), [System.StringComparison]::Ordinal) }'
           Replace = '' }
        @{ Name = "any-folder-whose-name-begins-like-the-home-is-refused"
           Find = 'if (-not $isHordes) { $isHordes = $folderName.StartsWith(($list.homeFolder + "-"), [System.StringComparison]::Ordinal) }'
           Replace = 'if (-not $isHordes) { $isHordes = $folderName.StartsWith($list.homeFolder, [System.StringComparison]::Ordinal) }' }
        @{ Name = "a-folder-that-only-holds-the-name-is-refused"
           Find = 'if (-not $isHordes) { $isHordes = $folderName.StartsWith(($list.homeFolder + "-"), [System.StringComparison]::Ordinal) }'
           Replace = 'if (-not $isHordes) { $isHordes = $folderName.Contains(($list.homeFolder + "-")) }' }
        @{ Name = "force-lifts-hordes-own-folders"
           Find = 'if ($isHordes) { return'
           Replace = 'if ($isHordes -and -not $Force) { return' }
        @{ Name = "hordes-own-folder-refusal-does-not-name-the-folder"
           Find = 'is under a folder named ''" + $parts[$at] + "'': a folder'
           Replace = 'is under a folder named ''" + $list.homeFolder + "'': a folder' }
        @{ Name = "secrets-folder-anywhere-on-the-way-not-looked-for"
           Find = 'for ($at = 1; $at -lt ($parts.Count - 1); $at++) {'
           Replace = 'for ($at = 1; $at -lt 0; $at++) {' }
        @{ Name = "file-named-as-the-secrets-folder-taken-for-one"
           Find = 'for ($at = 1; $at -lt ($parts.Count - 1); $at++) {'
           Replace = 'for ($at = 1; $at -lt $parts.Count; $at++) {' }
        @{ Name = "force-lifts-nothing"
           Find = '    if (-not $Force) {'
           Replace = '    if ($true) {' }
        @{ Name = "force-lifts-a-name-inside-a-harness-folder"
           Find = 'if ($named -ne "" -and $harness -ne "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "force-shares-nothing-from-a-harness-folder"
           Find = 'if ($named -ne "" -and $harness -ne "") { return'
           Replace = 'if ($harness -ne "") { return' }
        @{ Name = "force-lifts-a-name-where-the-harness-folders-are-not-known"
           Find = 'if ($named -ne "" -and $harnessDoubt -ne "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "force-shares-nothing-where-the-harness-folders-are-not-known"
           Find = 'if ($named -ne "" -and $harnessDoubt -ne "") { return'
           Replace = 'if ($harnessDoubt -ne "") { return' }
        @{ Name = "file-in-a-harness-folder-refused-for-its-name-first"
           Find = 'if ($harness -ne "") { return ("''" + $FinalPath'
           Replace = 'if ($false) { return ("''" + $FinalPath' }
        @{ Name = "harness-folder-refusal-says-force-does-not-change-it"
           Find = '(''" + $harness + "'')" + $insist) }'
           Replace = '(''" + $harness + "'')" + $never) }' }
        @{ Name = "never-lifted-place-says-force-shares-it"
           Find = '(''" + $place.path + "'')" + $never) }'
           Replace = '(''" + $place.path + "'')" + $insist) }' }
        @{ Name = "never-lifted-place-that-cannot-be-asked-says-force-shares-it"
           Find = 'if (-not $lifted) { return ($untold + $never) }'
           Replace = 'if (-not $lifted) { return ($untold + $insist) }' }
        @{ Name = "never-lifted-place-that-cannot-be-asked-not-refused"
           Find = 'if (-not $lifted) { return ($untold + $never) }'
           Replace = '' }
        @{ Name = "harness-that-does-not-say-not-refused"
           Find = 'if ($found.unknown -ne "") { $harnessDoubt ='
           Replace = 'if ($false) { $harnessDoubt =' }
        @{ Name = "unknown-harnesses-refused-without-the-reason"
           Find = 'if ($harnessDoubt -ne "") { return ($harnessDoubt + $insist) }'
           Replace = 'if ($harnessDoubt -ne "") { return ("" + $insist) }' }
        @{ Name = "file-in-a-place-not-refused"
           Find = 'if (-not (Test-HordeFilesPathUnder -Path $FinalPath -Folder $folder)) { continue }'
           Replace = 'if ($true) { continue }' }
        @{ Name = "every-file-is-in-every-place"
           Find = 'if (-not (Test-HordeFilesPathUnder -Path $FinalPath -Folder $folder)) { continue }'
           Replace = '' }
        @{ Name = "folders-judged-as-names"
           Find = '$leaf = $Parts[$Parts.Count - 1]'
           Replace = '$leaf = ($Parts -join "\")' }
        @{ Name = "missing-agents-folder-is-no-harnesses"
           Find = 'if (-not $agentsThere) { $unknown ='
           Replace = 'if ($false) { $unknown =' }
        @{ Name = "name-not-judged"
           Find = 'if ($word -ne "") { return'
           Replace = 'if ($false) { return' }
        # --- what a text file holds ---
        @{ Name = "private-key-in-a-text-not-looked-for"
           Find = '$neverKind = Find-HordeSecretKind -Text $text -Kinds @($list.shapes.never)'
           Replace = '$neverKind = ""' }
        @{ Name = "force-lifts-a-private-key-in-a-text"
           Find = '    $text = [System.Text.Encoding]::UTF8.GetString($Bytes)'
           Replace = '    if ($Force) { return "" }; $text = [System.Text.Encoding]::UTF8.GetString($Bytes)' }
        @{ Name = "private-key-refusal-says-force-shares-it"
           Find = 'A file that holds one is never shared, and -Force does not change that")'
           Replace = 'If this file holds no secret, share it again with -Force")' }
        @{ Name = "force-does-not-lift-a-token-in-a-text"
           Find = '    if ($Force) { return "" }'
           Replace = '' }
        @{ Name = "tokens-in-a-text-not-looked-for"
           Find = '$liftedKind = Find-HordeSecretKind -Text $text -Kinds @($list.shapes.lifted)'
           Replace = '$liftedKind = ""' }
        @{ Name = "every-kind-of-secret-looked-for-in-a-text"
           Find = '$liftedKind = Find-HordeSecretKind -Text $text -Kinds @($list.shapes.lifted)'
           Replace = '$liftedKind = Find-HordeSecretKind -Text $text' }
        @{ Name = "access-token-off-the-shapes"
           Find = 'shapes = @{ never = @("a private key"); lifted = @("an access token", "a signed web token", "a webhook address", "a secret written under a name such as client_secret or password") }'
           Replace = 'shapes = @{ never = @("a private key"); lifted = @("a private key", "a signed web token", "a webhook address", "a secret written under a name such as client_secret or password") }' }
        @{ Name = "signed-web-token-off-the-shapes"
           Find = 'shapes = @{ never = @("a private key"); lifted = @("an access token", "a signed web token", "a webhook address", "a secret written under a name such as client_secret or password") }'
           Replace = 'shapes = @{ never = @("a private key"); lifted = @("an access token", "a private key", "a webhook address", "a secret written under a name such as client_secret or password") }' }
        @{ Name = "webhook-address-off-the-shapes"
           Find = 'shapes = @{ never = @("a private key"); lifted = @("an access token", "a signed web token", "a webhook address", "a secret written under a name such as client_secret or password") }'
           Replace = 'shapes = @{ never = @("a private key"); lifted = @("an access token", "a signed web token", "a private key", "a secret written under a name such as client_secret or password") }' }
        @{ Name = "private-key-is-a-shape-force-lifts"
           Find = 'shapes = @{ never = @("a private key"); lifted = @("an access token", "a signed web token", "a webhook address", "a secret written under a name such as client_secret or password") }'
           Replace = 'shapes = @{ never = @("a webhook address"); lifted = @("an access token", "a signed web token", "a private key", "a secret written under a name such as client_secret or password") }' }
        @{ Name = "long-runs-looked-for-in-a-text"
           Find = 'shapes = @{ never = @("a private key"); lifted = @("an access token", "a signed web token", "a webhook address", "a secret written under a name such as client_secret or password") }'
           Replace = 'shapes = @{ never = @("a private key"); lifted = @("an access token", "a signed web token", "a webhook address", "a long random-looking string, as a key or token is", "a secret written under a name such as client_secret or password") }' }
        @{ Name = "name-value-pairs-looked-for-in-a-text"
           Find = 'shapes = @{ never = @("a private key"); lifted = @("an access token", "a signed web token", "a webhook address", "a secret written under a name such as client_secret or password") }'
           Replace = 'shapes = @{ never = @("a private key"); lifted = @("an access token", "a signed web token", "a webhook address", "a password or key written as name=value", "a secret written under a name such as client_secret or password") }' }
        @{ Name = "named-secret-off-the-shapes"
           Find = 'lifted = @("an access token", "a signed web token", "a webhook address", "a secret written under a name such as client_secret or password") }'
           Replace = 'lifted = @("an access token", "a signed web token", "a webhook address", "a private key") }' }
        @{ Name = "named-secret-is-a-shape-force-never-lifts"
           Find = 'shapes = @{ never = @("a private key"); lifted = @("an access token", "a signed web token", "a webhook address", "a secret written under a name such as client_secret or password") }'
           Replace = 'shapes = @{ never = @("a private key", "a secret written under a name such as client_secret or password"); lifted = @("an access token", "a signed web token", "a webhook address") }' }
        # --- a harness's own file, and a copy left beside it (the review's second round, 2026-10-13) ---
        @{ Name = "harness-file-not-looked-for"
           Find = '$ownFile = Get-HordeFilesHarnessFile -FinalPath $FinalPath -Known @($where.paths)'
           Replace = '$ownFile = ""' }
        @{ Name = "force-lifts-a-harness-file"
           Find = 'if ($ownFile -ne "") {'
           Replace = 'if ($ownFile -ne "" -and -not $Force) {' }
        @{ Name = "harness-file-refused-only-with-force"
           Find = 'if ($ownFile -ne "") {'
           Replace = 'if ($ownFile -ne "" -and $Force) {' }
        @{ Name = "harness-file-refusal-says-force-shares-it"
           Find = '$ownsIt = ". A harness''s own file is never shared, and -Force does not change that"'
           Replace = '$ownsIt = $insist' }
        @{ Name = "a-copy-beside-a-harness-file-said-to-be-the-file"
           Find = 'if ($itself) { return'
           Replace = 'if ($true) { return' }
        @{ Name = "a-harness-file-said-to-be-a-copy-beside-it"
           Find = 'if ($itself) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-root-that-is-a-folder-is-taken-for-a-file"
           Find = 'if (-not [System.IO.File]::Exists($declared)) { continue }'
           Replace = '' }
        @{ Name = "a-root-that-is-not-there-is-taken-for-a-file"
           Find = 'if (-not [System.IO.File]::Exists($declared)) { continue }'
           Replace = 'if ([System.IO.Directory]::Exists($declared)) { continue }' }
        @{ Name = "a-copy-beside-a-harness-file-not-refused"
           Find = '$nameOfIt.StartsWith((ConvertTo-HordeAsciiLower -Text $declared.Substring($at + 1)), [System.StringComparison]::Ordinal)'
           Replace = '[string]::Equals($nameOfIt, (ConvertTo-HordeAsciiLower -Text $declared.Substring($at + 1)), [System.StringComparison]::Ordinal)' }
        @{ Name = "a-name-that-only-holds-a-harness-files-name-refused"
           Find = '$nameOfIt.StartsWith((ConvertTo-HordeAsciiLower -Text $declared.Substring($at + 1)), [System.StringComparison]::Ordinal)'
           Replace = '$nameOfIt.Contains((ConvertTo-HordeAsciiLower -Text $declared.Substring($at + 1)))' }
        @{ Name = "a-harness-files-name-refused-in-any-folder"
           Find = 'if ($sameFolder -and $nameOfIt.'
           Replace = 'if ($nameOfIt.' }
        @{ Name = "everything-beside-a-harness-file-refused"
           Find = 'if ($sameFolder -and $nameOfIt.StartsWith((ConvertTo-HordeAsciiLower -Text $declared.Substring($at + 1)), [System.StringComparison]::Ordinal)) { return $declared }'
           Replace = 'if ($sameFolder) { return $declared }' }
        @{ Name = "harness-file-name-compared-with-its-case"
           Find = '$nameOfIt = ConvertTo-HordeAsciiLower -Text $FinalPath.Substring($cut + 1)'
           Replace = '$nameOfIt = $FinalPath.Substring($cut + 1)' }
        @{ Name = "harness-file-folder-judged-one-level-up"
           Find = '$folderOfIt = ConvertTo-HordeAsciiLower -Text $FinalPath.Substring(0, $cut)'
           Replace = '$folderOfIt = ConvertTo-HordeAsciiLower -Text $FinalPath.Substring(0, $FinalPath.Substring(0, $cut).LastIndexOf([char]92))' }
        @{ Name = "token-refusal-does-not-name-the-kind"
           Find = '("what it holds looks like " + $liftedKind + ", by its shape'
           Replace = '("what it holds looks like a secret" + ", by its shape' }
        # --- the three token words, letters anywhere (the review's next round, 2026-10-13) ---
        @{ Name = "word-accesstoken-off-the-list"
           Find = '@{ word = "accesstoken"; how = "anywhere" }, '
           Replace = '' }
        @{ Name = "word-refreshtoken-off-the-list"
           Find = '@{ word = "refreshtoken"; how = "anywhere" }, '
           Replace = '' }
        @{ Name = "word-authtoken-off-the-list"
           Find = ', @{ word = "authtoken"; how = "anywhere" }'
           Replace = '' }
        @{ Name = "word-accesstoken-only-as-a-whole-word"
           Find = '@{ word = "accesstoken"; how = "anywhere" }'
           Replace = '@{ word = "accesstoken"; how = "word" }' }
        # --- the relays' own secret files (the relay port's question, 2026-10-13) ---
        @{ Name = "relays-not-loaded"
           Find = '    . $hordeFilesRelayFile'
           Replace = '    $null = $hordeFilesRelayFile' }
        @{ Name = "a-relay-already-registered-is-loaded-again"
           Find = 'if (@(Get-HordeRelayNames) -ccontains (Split-Path -Leaf (Split-Path -Parent $hordeFilesRelayFile))) { continue }'
           Replace = '' }
        @{ Name = "relays-never-asked"
           Find = '$relayFiles = Get-HordeRelaySecretFiles -HordeHome $HordeHome'
           Replace = '$relayFiles = New-HordeKnown -Value ([pscustomobject]@{ files = @(); asked = @("nobody") })' }
        @{ Name = "relays-asked-of-the-users-own-home"
           Find = '$relayFiles = Get-HordeRelaySecretFiles -HordeHome $HordeHome'
           Replace = '$relayFiles = Get-HordeRelaySecretFiles' }
        @{ Name = "relay-unknown-taken-for-known"
           Find = 'if ($relayFiles.state -cne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "relay-unknown-names-no-relay"
           Find = 'if ($null -ne $relayFiles.PSObject.Properties["relays"]) { $who = @($relayFiles.relays) }'
           Replace = '' }
        @{ Name = "relay-unknown-echoes-what-the-relay-said"
           Find = '"which files hold the relays'' secrets is not known: " + $named'
           Replace = '"which files hold the relays'' secrets is not known: " + $named + " (" + $relayFiles.reason + ")"' }
        @{ Name = "nobody-asked-taken-for-none"
           Find = '} elseif (@($relayFiles.value.asked).Count -eq 0) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "relay-files-not-places"
           Find = 'foreach ($entry in @($relayFiles.value.files)) {'
           Replace = 'foreach ($entry in @()) {' }
        @{ Name = "relay-file-lifted-by-force"
           Find = 'kind = "relay"; path = ("" + $entry.path); force = $false;'
           Replace = 'kind = "relay"; path = ("" + $entry.path); force = $true;' }
        @{ Name = "relay-unknown-not-refused"
           Find = 'if ($found.unknownRelays -ne "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "relay-unknown-lifted-by-force"
           Find = 'if ($found.unknownRelays -ne "") {'
           Replace = 'if ($found.unknownRelays -ne "" -and -not $Force) {' }
        @{ Name = "relay-unknown-refusal-says-force-shares-it"
           Find = '", so whether ''" + $FinalPath + "'' is one of them cannot be told" + $never)'
           Replace = '", so whether ''" + $FinalPath + "'' is one of them cannot be told" + $insist)' }
        @{ Name = "relay-refusal-does-not-name-the-relay"
           Find = '"'' is what the relay ''" + $place.relay + "'' calls " + $place.what'
           Replace = '"'' is what a relay calls " + $place.what' }
        @{ Name = "relay-refusal-does-not-say-what-the-file-is"
           Find = '"'' is what the relay ''" + $place.relay + "'' calls " + $place.what + " (''"'
           Replace = '"'' is what the relay ''" + $place.relay + "'' calls a file (''"' }
        # --- a relay's file by which file it is, and an entry that is no local path (review of PR 238) ---
        @{ Name = "relay-entry-with-no-local-path-is-shared"
           Find = 'if (@($where.paths).Count -eq 0) { return ($itsWords'
           Replace = 'if ($false) { return ($itsWords' }
        @{ Name = "relay-entry-with-no-local-path-said-force-shares-it"
           Find = 'is that file cannot be told" + $never) }'
           Replace = 'is that file cannot be told" + $insist) }' }
        @{ Name = "hard-link-to-a-relay-file-is-shared"
           Find = 'if ([string]::Equals($sharedIs, $entryIs.id, [System.StringComparison]::Ordinal)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "hard-link-refusal-does-not-name-the-relay"
           Find = '"'' is the very file the relay ''" + $place.relay + "'' calls "'
           Replace = '"'' is the very file a relay calls "' }
        @{ Name = "any-file-is-a-relay-file-by-identity"
           Find = 'if ([string]::Equals($sharedIs, $entryIs.id, [System.StringComparison]::Ordinal)) {'
           Replace = 'if ($entryIs.id -ne "") {' }
        @{ Name = "relay-refusal-says-force-shares-it"
           Find = '"''), a file it keeps a secret in" + $never)'
           Replace = '"''), a file it keeps a secret in" + $insist)' }
    )
}
