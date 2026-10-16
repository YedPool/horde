# Mutations of `horde orcs` at a command line (orcs/Console.ps1): how a seed file is found and read. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\orcs-console.psd1
# test\test-orcs-registry.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "orcs\Console.ps1"
    Suite  = "test\test-orcs-registry.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-relative-seed-path-is-the-process-folders"
           Find = 'if (-not [System.IO.Path]::IsPathRooted($File)) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-seed-that-is-not-utf8-throws"
           Find = 'catch { return [pscustomobject]@{ lines = @(); failure = ("the seed file " + $File + " could not be read as UTF-8 text: " + $_.Exception.Message) } }'
           Replace = 'catch { throw }' }
        @{ Name = "a-seed-value-that-is-not-text-is-taken"
           Find = 'if ($p.Value -isnot [string]) { $ok = $false }'
           Replace = '' }
    )
}
