# Mutations of core/GuardList.ps1, the reading of test\guards.txt that `horde merge` and the CI runner share
# (T-0247). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\guard-list.psd1
# Each makes a bad line pass, drops a guard from the run, lets a guard run twice, gives a shell the wrong
# PSModulePath or PowerShell 7 the wrong program; test\test-guard-list.ps1 must fail for every one.
@{
    Target = "core\GuardList.ps1"
    Suite  = "test\test-guard-list.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "comment-not-skipped"
           Find = 'if ($line -eq "" -or $line.StartsWith("#")) { continue }'
           Replace = 'if ($line -eq "") { continue }' }
        @{ Name = "bad-line-skipped"
           Find = 'return [pscustomobject]@{ ok = $false; why = ("line " + $n + " of " + $path + " is not a guard script under test/ ending .ps1: ''" + $line + "''"); guards = @() }'
           Replace = 'continue' }
        @{ Name = "pattern-takes-any-path"
           Find = '''\Atest[\\/][A-Za-z0-9][A-Za-z0-9._-]*\.ps1\z'''
           Replace = '''\Atest[\\/].*\.ps1\z''' }
        @{ Name = "duplicate-guard-taken"
           Find = 'if ($guards -ccontains $guard) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "empty-list-taken"
           Find = 'if ($guards.Count -eq 0) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "slash-not-normalised"
           Find = '$guard = $line.Replace("/", "\")'
           Replace = '$guard = $line' }
        @{ Name = "byte-order-mark-kept"
           Find = 'if ($n -eq 1 -and $line.Length -gt 0 -and [int][char]$line[0] -eq 0xFEFF)'
           Replace = 'if ($false)' }
        @{ Name = "join-drops-the-bases-guards"
           Find = 'foreach ($g in @($Base)) { if ($null -ne $g -and -not ($all -ccontains $g)) { [void]$all.Add($g) } }'
           Replace = '' }
        @{ Name = "join-drops-the-trees-guards"
           Find = 'foreach ($g in @($Tree)) { if ($null -ne $g -and -not ($all -ccontains $g)) { [void]$all.Add($g) } }'
           Replace = '' }
        @{ Name = "join-repeats-a-guard"
           Find = 'foreach ($g in @($Tree)) { if ($null -ne $g -and -not ($all -ccontains $g)) { [void]$all.Add($g) } }'
           Replace = 'foreach ($g in @($Tree)) { if ($null -ne $g) { [void]$all.Add($g) } }' }
        @{ Name = "shell-5-1-gets-no-module-path"
           Find = 'if ($Shell -ceq "5.1" -and'
           Replace = 'if ($false -and' }
        @{ Name = "shell-7-gets-the-module-path"
           Find = 'if ($Shell -ceq "5.1" -and "" + $MachinePsModulePath -ne "")'
           Replace = 'if ("" + $MachinePsModulePath -ne "")' }
        @{ Name = "pwsh7-setting-ignored"
           Find = 'if ("" + $Setting -ne "") { return ("" + $Setting) }'
           Replace = '' }
        @{ Name = "pwsh7-from-the-search-path"
           Find = 'return [System.IO.Path]::Combine($pf, "PowerShell", "7", "pwsh.exe")'
           Replace = 'return "pwsh.exe"' }
        @{ Name = "shell-5-1-not-run"
           Find = '@{ key = "5.1"; label = "Windows PowerShell 5.1" },'
           Replace = '' }
    )
}
