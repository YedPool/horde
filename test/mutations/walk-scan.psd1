# The ExecScan entries the link walk adds (fix/link-writer-speed). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\walk-scan.psd1
# Each mutation takes one entry away again, so remote/Contract.ps1 is a finding, and the exec-scan suite,
# which scans every file in remote/, must fail. Each entry is needed, and only for the walk.
@{
    Target = "tools\ExecScan.ps1"
    Suite  = "test\test-exec-scan.ps1"
    Mutations = @(
        @{ Name = "schema-node-not-allowed"
           Find = '"Get-HordeSchemaNode", '
           Replace = '"New-HordeKnown", ' }
        @{ Name = "assert-schema-not-allowed"
           Find = '"Assert-HordeSchema", '
           Replace = '"New-HordeKnown", ' }
        @{ Name = "schema-type-not-allowed"
           Find = '"Test-HordeSchemaType", '
           Replace = '"New-HordeKnown", ' }
        @{ Name = "schema-is-number-not-allowed"
           Find = '"Test-HordeSchemaIsNumber", '
           Replace = '"New-HordeKnown", ' }
        @{ Name = "compare-number-not-allowed"
           Find = '"Compare-HordeSchemaNumber")'
           Replace = '"New-HordeKnown")' }
        @{ Name = "dictionary-not-allowed"
           Find = '    "System.Collections.Generic.Dictionary[string,object]")'
           Replace = '    "System.Collections.ArrayList")' }
        @{ Name = "ignore-case-comparer-not-allowed"
           Find = '"stringcomparer" = @("Ordinal", "OrdinalIgnoreCase")'
           Replace = '"stringcomparer" = @("Ordinal")' }
        @{ Name = "is-match-not-allowed"
           Find = '    "IsMatch")'
           Replace = '    "Add")' }
        @{ Name = "enumerable-not-allowed"
           Find = '    "collections.ienumerable")'
           Replace = '    "io.path")' }
    )
}
