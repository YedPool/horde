# Mutations of tools\MutateInstalled.ps1 (part 1: how a shim is read), the rule that the installed Horde is never mutated (T-0466);
# test\test-mutate.ps1 must fail for every one. Each breaks one branch of the refusal: a signal that no
# longer fires, a match that is too narrow or too wide, a comment read as a launch, the profile taken
# from the wrong place, the words that tell a person what to do. The checks run the rule against fixture
# folders under the temp folder, so none of them needs PowerShell 7 or this machine's own profile.
# Round 2 of PR 507 added the machine-profile, anchoring, spelling, size-cap, parent-guard and
# bad-path mutants, among them the four the first review wrote and found surviving. Part 2 is
# mutate-installed-rest.psd1: a spec runs the whole suite once per mutant, and one file of all of
# them would not finish inside the gate's 30 minutes.
@{
    Target = "tools\MutateInstalled.ps1"
    Suite  = "test\test-mutate.ps1"
    Mutations = @(
        @{ Name = "shim-signal-off"
           Find = 'if ($text -ne "" -and (Test-HordeMutateInstalledShimLaunches'
           Replace = 'if ($false -and (Test-HordeMutateInstalledShimLaunches' }
        @{ Name = "shim-names-any-folder"
           Find = '[regex]::Escape($Leaf)'
           Replace = '''[^\\]+''' }
        @{ Name = "shim-absolute-form-ignored"
           Find = '[regex]::Escape($Full)'
           Replace = '''NO-SUCH-FOLDER''' }
        @{ Name = "shim-sibling-form-ignored"
           Find = '%~dp0(?:\.?\\)?'
           Replace = 'NO-SUCH-FORM' }
        @{ Name = "shim-dot-form-not-accepted"
           Find = '%~dp0(?:\.?\\)?'
           Replace = '%~dp0(?:\\)?' }
        @{ Name = "own-absolute-form-matches-bare-path"
           Find = '\\horde\.ps1(?=["\s]|$)'
           Replace = '\\[^\s"]+(?=["\s]|$)' }
        @{ Name = "shim-end-not-anchored"
           Find = '(?=["\s]|$)'
           Replace = '(?:)' }
        @{ Name = "shim-file-flag-not-required"
           Find = '-File\s+"?(?:'
           Replace = '(?:' }
        @{ Name = "shim-comments-read-as-launches"
           Find = 'if ($line.TrimStart() -match'
           Replace = 'if ($false -and $line.TrimStart() -match' }
        @{ Name = "shim-rem-not-a-comment"
           Find = '^(rem(\s|$)|::)'
           Replace = '^(::)' }
        @{ Name = "shim-colons-not-a-comment"
           Find = '^(rem(\s|$)|::)'
           Replace = '^(rem(\s|$))' }
        @{ Name = "shim-slash-not-normalised"
           Find = '.Replace(''/'', ''\'')'
           Replace = '.Replace(''/'', ''/'')' }
        @{ Name = "shim-userprofile-not-expanded"
           Find = 'if ($ProfileDir -ne "") { $t = $t -ireplace'
           Replace = 'if ($false) { $t = $t -ireplace' }
        @{ Name = "shim-userprofile-case-sensitive"
           Find = '$t -ireplace'
           Replace = '$t -creplace' }
        @{ Name = "shim-leaf-case-sensitive"
           Find = 'if ($line -match $launch)'
           Replace = 'if ($line -cmatch $launch)' }
    )
}
