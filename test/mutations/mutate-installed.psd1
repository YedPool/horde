# Mutations of tools\MutateInstalled.ps1, the rule that the installed Horde is never mutated (T-0466);
# test\test-mutate.ps1 must fail for every one. Each breaks one branch of the refusal: a signal that no
# longer fires, a match that is too narrow or too wide, the profile taken from the wrong place, the
# words that tell a person what to do. The checks run the tool from fixture folders under the temp
# folder, so none of them needs PowerShell 7.
@{
    Target = "tools\MutateInstalled.ps1"
    Suite  = "test\test-mutate.ps1"
    Mutations = @(
        @{ Name = "shim-signal-off"
           Find = 'if ($text -match $bySibling -or $text -imatch $byFull) {'
           Replace = 'if ($false) {' }
        @{ Name = "shim-sibling-form-ignored"
           Find = 'if ($text -match $bySibling -or $text -imatch $byFull) {'
           Replace = 'if ($text -imatch $byFull) {' }
        @{ Name = "shim-absolute-form-ignored"
           Find = 'if ($text -match $bySibling -or $text -imatch $byFull) {'
           Replace = 'if ($text -match $bySibling) {' }
        @{ Name = "shim-names-any-folder"
           Find = '\\?'' + [regex]::Escape($leaf)'
           Replace = '\\?'' + ''[^\\]+''' }
        @{ Name = "shim-leaf-case-sensitive"
           Find = '$bySibling = ''(?i)%~dp0'
           Replace = '$bySibling = ''(?-i)%~dp0' }
        @{ Name = "trailing-slash-kept"
           Find = '$full = [System.IO.Path]::GetFullPath($Repo).TrimEnd(''\'', ''/'')'
           Replace = '$full = [System.IO.Path]::GetFullPath($Repo)' }
        @{ Name = "default-place-signal-off"
           Find = 'if ($default -ieq $full) {'
           Replace = 'if ($false) {' }
        @{ Name = "default-place-case-sensitive"
           Find = 'if ($default -ieq $full) {'
           Replace = 'if ($default -ceq $full) {' }
        @{ Name = "default-place-ignores-given-profile"
           Find = '$profileDir = "" + $ProfileDir'
           Replace = '$profileDir = ""' }
        @{ Name = "default-place-any-bin-folder"
           Find = '[System.IO.Path]::Combine($profileDir, "bin", "horde")'
           Replace = '[System.IO.Path]::Combine($profileDir, "bin", $leaf)' }
        @{ Name = "refusal-without-the-path"
           Find = 'installed Horde, " + $full + " (" + $why'
           Replace = 'installed Horde (" + $why' }
        @{ Name = "refusal-without-what-to-do"
           Find = 'Run the tools\Mutate.ps1 of your own clone instead'
           Replace = 'That is all' }
    )
}
