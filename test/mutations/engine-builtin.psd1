# Mutations of the parts of core/EngineConfig.ps1 that engines E4 added and resolution reads: the
# built-in layer's reader and the registry's tuner field.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\engine-builtin.psd1
# test\test-engine-resolve.ps1 must fail for every one.
@{
    Target = "core\EngineConfig.ps1"
    Suite  = "test\test-engine-resolve.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "builtin-files-not-read"
           Find = '$out += (Read-HordeEngineLayerText'
           Replace = '$null = (Read-HordeEngineLayerText' }
        @{ Name = "builtin-read-as-user-layer"
           Find = '-Layer "L0" -Source ("agents/"'
           Replace = '-Layer "L1" -Source ("agents/"' }
        @{ Name = "tuner-field-unchecked"
           Find = 'if ($null -ne $tuner -and ("" + $tuner -cne "raise-only" -or $kind -cne "enum")) {'
           Replace = 'if ($false) {' }
        @{ Name = "tuner-allowed-off-an-enum"
           Find = 'if ($null -ne $tuner -and ("" + $tuner -cne "raise-only" -or $kind -cne "enum")) {'
           Replace = 'if ($null -ne $tuner -and ("" + $tuner -cne "raise-only")) {' }
    )
}
