# Mutations of tools\MutateInstalled.ps1, the rule that the installed Horde is never mutated (T-0466);
# test\test-mutate.ps1 must fail for every one. Each breaks one branch of the refusal: a signal that no
# longer fires, a match that is too narrow or too wide, a comment read as a launch, the profile taken
# from the wrong place, the words that tell a person what to do. The checks run the rule against fixture
# folders under the temp folder, so none of them needs PowerShell 7 or this machine's own profile.
# Round 2 of PR 507 added the machine-profile, anchoring, spelling, size-cap, parent-guard and
# bad-path mutants, among them the four the first review wrote and found surviving.
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
        @{ Name = "own-size-cap-huge"
           Find = '-gt 65536'
           Replace = '-gt 65536000' }
        @{ Name = "own-parent-guard-off"
           Find = 'if ($parent -and $leaf) {'
           Replace = 'if ($true) {' }
        @{ Name = "own-leaf-only-test"
           Find = '-PathType Leaf)) { return "" }'
           Replace = '-PathType Any)) { return "" }'
           Expect = "survives"
           Reason = "Equivalent: the read below sits in a try, so a folder named horde.cmd, which Any would let through, throws there and gives the same empty text the Leaf test returns. The behaviour is pinned instead: test-mutate checks that a folder named horde.cmd is not a shim and does not throw." }
        @{ Name = "trailing-slash-kept"
           Find = '$full = [System.IO.Path]::GetFullPath($Repo).TrimEnd(''\'', ''/'')'
           Replace = '$full = [System.IO.Path]::GetFullPath($Repo)' }
        @{ Name = "bad-path-throws"
           Find = '$Repo).TrimEnd(''\'', ''/'') } catch {'
           Replace = '$Repo).TrimEnd(''\'', ''/'') } catch { throw }; if ($false) {' }
        @{ Name = "default-place-signal-off"
           Find = 'if ($default -ne "" -and $default -ieq $full) {'
           Replace = 'if ($false) {' }
        @{ Name = "default-place-case-sensitive"
           Find = '$default -ieq $full'
           Replace = '$default -ceq $full' }
        @{ Name = "default-place-ignores-given-profile"
           Find = '$prof = ("" + $ProfileDir).Trim()'
           Replace = '$prof = ""' }
        @{ Name = "default-place-any-bin-folder"
           Find = '[System.IO.Path]::Combine($prof, "bin", "horde")'
           Replace = '[System.IO.Path]::Combine($prof, "bin", $leaf)' }
        @{ Name = "profile-machine-ignored"
           Find = 'try { $p = ("" + (& $script:HordeMutateProfileProbe)).Trim() } catch { $p = "" }'
           Replace = '$p = ""' }
        @{ Name = "profile-environment-first"
           Find = 'if ($p -eq "") { $p = ("" + $env:USERPROFILE).Trim() }'
           Replace = 'if ($env:USERPROFILE) { $p = ("" + $env:USERPROFILE).Trim() }' }
        @{ Name = "profile-environment-fallback-dropped"
           Find = 'if ($p -eq "") { $p = ("" + $env:USERPROFILE).Trim() }'
           Replace = 'if ($false) { $p = ("" + $env:USERPROFILE).Trim() }' }
        @{ Name = "profile-machine-error-not-caught"
           Find = 'catch { $p = "" }'
           Replace = 'catch { throw }' }
        @{ Name = "refusal-without-the-path"
           Find = 'installed Horde, " + $full + " (" + $why'
           Replace = 'installed Horde (" + $why' }
        @{ Name = "refusal-without-what-to-do"
           Find = 'Run the tools\Mutate.ps1 of your own clone instead (a worktree made'
           Replace = 'That is all (a worktree made' }
    )
}
