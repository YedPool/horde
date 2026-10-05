# Mutations of test/lib/SuiteFiles.ps1, the list of where suites live. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\suite-files.psd1
# test\test-suite.ps1 must fail for each.
@{
    Target = "test\lib\SuiteFiles.ps1"
    Suite  = "test\test-suite.ps1"
    Mutations = @(
        @{ Name = "transports-not-gated"
           Find = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test", "agents/*/test")'
           Replace = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "agents/*/test")' }
        @{ Name = "agents-not-gated"
           Find = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test", "agents/*/test")'
           Replace = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test")' }
        @{ Name = "fixtures-counted-as-stray"
           Find = 'if ($rel -like ".git/*" -or $rel -like ($script:HordeSuiteDataFolder + "/*")) { continue }'
           Replace = 'if ($rel -like ".git/*") { continue }' }
        @{ Name = "strays-never-reported"
           Find = 'if (-not $known.ContainsKey($f.FullName.ToLowerInvariant())) { [void]$stray.Add($rel) }'
           Replace = '' }
        @{ Name = "extension-not-exact"
           Find = 'foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter "test-*.ps1" -File | Where-Object { $_.Extension -ceq ".ps1" })) { [void]$out.Add($f) }'
           Replace = 'foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter "test-*" -File)) { [void]$out.Add($f) }' }
        @{ Name = "machine-bound-suite-renamed"
           Find = '"transports/local/test/test-local.ps1" = '
           Replace = '"transports/local/test/test-locals.ps1" = ' }
    )
}
