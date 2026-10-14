# Mutations of cli/ServicesTell.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\services-tell.psd1
# Each lets a notice carry text from outside, or lets a test's home tell someone;
# test\test-services-tend.ps1 must fail for every one.
@{
    Target = "cli\ServicesTell.ps1"
    Suite  = "test\test-services-tend.ps1"
    Mutations = @(
        @{ Name = "notice-text-told"
           Find = '    if ($said.Count -eq 0) { [void]$said.Add("it needs a person") }'
           Replace = '    [void]$said.Add("" + $Notice.text)' }
        @{ Name = "unknown-kind-told-in-its-own-words"
           Find = 'if ($script:HordeServiceTellSentences.Contains($w) -and -not $said.Contains($script:HordeServiceTellSentences[$w])) { [void]$said.Add($script:HordeServiceTellSentences[$w]) }'
           Replace = 'if ($script:HordeServiceTellSentences.Contains($w)) { [void]$said.Add($script:HordeServiceTellSentences[$w]) } else { [void]$said.Add($w) }' }
        @{ Name = "any-service-name-repeated"
           Find = 'if ($null -ne $named -and "" + $named.Value -cmatch $script:HordeServiceTellNamePattern) {'
           Replace = 'if ($null -ne $named) {' }
        @{ Name = "recovery-told-in-its-own-words"
           Find = ': what it was told about is over, and it is running`nSee it with: horde services status") }'
           Replace = ': " + $Notice.text + "`nSee it with: horde services status") }' }
        @{ Name = "tests-home-tells"
           Find = 'if (Test-HordeServiceHomeIsATests -HordeHome $HordeHome -TempRoot $TempRoot) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "beginning-with-temp-is-under-temp"
           Find = '        $root = [System.IO.Path]::GetFullPath($TempRoot).TrimEnd(''\'', ''/'') + ''\'''
           Replace = '        $root = [System.IO.Path]::GetFullPath($TempRoot).TrimEnd(''\'', ''/'')' }
        @{ Name = "temp-compared-by-case"
           Find = 'return [bool]$full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = 'return [bool]$full.StartsWith($root, [System.StringComparison]::Ordinal)' }
        @{ Name = "unresolvable-home-may-tell"
           Find = '    } catch { return $true }'
           Replace = '    } catch { return $false }'
           Expect = "survives"
           Reason = "no path a suite can hand in makes the resolving throw on this system without also failing earlier; the line errs towards telling nobody, and is held by its comment" }
        # --- the supervisor runs whether or not anyone is signed in (2026-10-14) ---
        @{ Name = "no-desktop-told-as-needs-a-person"
           Find = '    "no-desktop"       = '
           Replace = '    "no-desktop-x"     = ' }
    )
}
