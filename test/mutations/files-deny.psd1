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
        @{ Name = "credential-off-the-list"
           Find = 'words = @("credential", "secret", "token", "key", "password", ".env")'
           Replace = 'words = @("secret", "token", "key", "password", ".env")' }
        @{ Name = "secret-off-the-list"
           Find = 'words = @("credential", "secret", "token", "key", "password", ".env")'
           Replace = 'words = @("credential", "token", "key", "password", ".env")' }
        @{ Name = "token-off-the-list"
           Find = 'words = @("credential", "secret", "token", "key", "password", ".env")'
           Replace = 'words = @("credential", "secret", "key", "password", ".env")' }
        @{ Name = "key-off-the-list"
           Find = 'words = @("credential", "secret", "token", "key", "password", ".env")'
           Replace = 'words = @("credential", "secret", "token", "password", ".env")' }
        @{ Name = "password-off-the-list"
           Find = 'words = @("credential", "secret", "token", "key", "password", ".env")'
           Replace = 'words = @("credential", "secret", "token", "key", ".env")' }
        @{ Name = "env-off-the-list"
           Find = 'words = @("credential", "secret", "token", "key", "password", ".env")'
           Replace = 'words = @("credential", "secret", "token", "key", "password")' }
        @{ Name = "secrets-folder-under-another-name"
           Find = 'secretsFolder = ".horde-secrets"'
           Replace = 'secretsFolder = ".horde-secret"' }
        @{ Name = "ssh-folder-under-another-name"
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
        @{ Name = "force-does-not-lift-ssh"
           Find = 'path = (Join-Path $profileDir $list.sshFolder); force = $true'
           Replace = 'path = (Join-Path $profileDir $list.sshFolder); force = $false' }
        @{ Name = "force-does-not-lift-a-harness-folder"
           Find = 'kind = "agent"; path = ("" + $storeRoot); force = $true'
           Replace = 'kind = "agent"; path = ("" + $storeRoot); force = $false' }
        @{ Name = "home-not-a-place"
           Find = '[void]$places.Add([pscustomobject]@{ kind = "home"; path = $base; force = $false })'
           Replace = '' }
        @{ Name = "home-is-the-ambient-one-whatever-home-is-given"
           Find = 'if ($base -eq "") { $base = Get-HordeHome }'
           Replace = '$base = Get-HordeHome' }
        @{ Name = "secrets-folder-of-the-profile-not-a-place"
           Find = '[void]$places.Add([pscustomobject]@{ kind = "secrets"; path = (Join-Path $profileDir $list.secretsFolder); force = $false })'
           Replace = '' }
        @{ Name = "ssh-not-a-place"
           Find = '[void]$places.Add([pscustomobject]@{ kind = "ssh"; path = (Join-Path $profileDir $list.sshFolder); force = $true })'
           Replace = '' }
        @{ Name = "harness-folders-not-places"
           Find = '[void]$places.Add([pscustomobject]@{ kind = "agent"; path = ("" + $storeRoot); force = $true })'
           Replace = '' }
        @{ Name = "harnesses-read-from-the-real-repository-whatever-is-given"
           Find = 'if ($RepoRoot -eq "") { $stores = Get-HordeAgentStoreRoots } else {'
           Replace = 'if ($true) { $stores = Get-HordeAgentStoreRoots } else {' }
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
           Find = 'if ((Get-HordeFilesAliasRefusal -Path $whole) -ne "" -or '
           Replace = 'if (' }
        @{ Name = "path-that-is-no-path-taken-for-absent"
           Find = 'catch { return [pscustomobject]@{ paths = @(); unknown = $true } }'
           Replace = 'catch { return [pscustomobject]@{ paths = @(); unknown = $false } }' }
        # --- the refusal ---
        @{ Name = "force-lifts-nothing"
           Find = 'if ($Force) { return "" }'
           Replace = '' }
        @{ Name = "force-lifts-everything"
           Find = '    foreach ($lifted in @($false, $true)) {'
           Replace = '    if ($Force) { return "" }; foreach ($lifted in @($false, $true)) {' }
        @{ Name = "what-force-lifts-judged-as-what-it-never-lifts"
           Find = 'Where-Object { $_.force -eq $lifted }'
           Replace = 'Where-Object { $true }' }
        @{ Name = "liftable-refusal-says-force-does-not-change-it"
           Find = '$ending = $never; if ($lifted) { $ending = $insist }'
           Replace = '$ending = $never' }
        @{ Name = "never-lifted-refusal-says-force-shares-it"
           Find = '$ending = $never; if ($lifted) { $ending = $insist }'
           Replace = '$ending = $insist' }
        @{ Name = "secrets-folder-anywhere-on-the-way-not-looked-for"
           Find = 'for ($at = 1; $at -lt ($parts.Count - 1); $at++) {'
           Replace = 'for ($at = 1; $at -lt 0; $at++) {' }
        @{ Name = "file-named-as-the-secrets-folder-taken-for-one"
           Find = 'for ($at = 1; $at -lt ($parts.Count - 1); $at++) {'
           Replace = 'for ($at = 1; $at -lt $parts.Count; $at++) {' }
        @{ Name = "secrets-folder-anywhere-compared-with-its-case"
           Find = '[string]::Equals((ConvertTo-HordeAsciiLower -Text $parts[$at]), $list.secretsFolder, [System.StringComparison]::Ordinal)'
           Replace = '[string]::Equals($parts[$at], $list.secretsFolder, [System.StringComparison]::Ordinal)' }
        @{ Name = "harness-that-does-not-say-not-refused"
           Find = 'if ($found.unknown -ne "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "place-that-cannot-be-asked-not-refused"
           Find = 'if ($where.unknown) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "file-in-a-place-not-refused"
           Find = 'if (Test-HordeFilesPathUnder -Path $FinalPath -Folder $folder) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "name-not-judged"
           Find = 'if ($word -ne "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "folders-judged-as-names"
           Find = '$leaf = $parts[$parts.Count - 1]'
           Replace = '$leaf = $FinalPath' }
    )
}
