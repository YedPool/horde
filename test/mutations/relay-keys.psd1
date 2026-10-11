# Mutations of relay/Keys.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-keys.psd1
# Each loosens one promise about the machine's keys - made once, never exportable, proved before kept,
# only relay names, the scope asked for - and test\test-relay-keys.ps1 must fail for every one. The
# suite makes and removes only keys named horde-relay-test-<random>, so a mutant cannot reach a real
# key. Every find string occurs once in the target.
@{
    Target = "relay\Keys.ps1"
    Suite  = "test\test-relay-keys.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "keys-made-exportable"
           Find = '$params.ExportPolicy = [System.Security.Cryptography.CngExportPolicies]::None'
           Replace = '$params.ExportPolicy = [System.Security.Cryptography.CngExportPolicies]::AllowPlaintextExport' }
        @{ Name = "exportable-key-used"
           Find = 'if ($cng.ExportPolicy -ne [System.Security.Cryptography.CngExportPolicies]::None) {'
           Replace = 'if ($false) {' }
        @{ Name = "existing-key-overwritten"
           Find = 'if ($existing -cne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "key-kept-without-proof"
           Find = '$why = Test-HordeRelayKeyWorks -KeyObject $obj -Use $Use'
           Replace = '$why = ""' }
        @{ Name = "any-key-name"
           Find = 'if ($Name -cnotmatch ''\Ahorde-relay-[a-z0-9][a-z0-9-]{0,47}\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "kind-not-checked"
           Find = 'if (-not (Test-HordeRelayCngKeyKind -CngKey $cng -Use $Use)) {'
           Replace = 'if ($false) {' }
        @{ Name = "machine-scope-ignored"
           Find = 'if ($Scope -ceq "machine") { $params.KeyCreationOptions = [System.Security.Cryptography.CngKeyCreationOptions]::MachineKey }'
           Replace = '' }
    )
}
