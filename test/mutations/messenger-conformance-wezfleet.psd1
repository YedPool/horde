# Mutations of the wezfleet messenger, against the conformance suite: each makes it do something its
# capabilities.json says it does not, and the suite, reading the fake fleet command's own records, must
# see it. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\messenger-conformance-wezfleet.psd1
@{
    Target = "messengers\wezfleet\Messenger.ps1"
    Suite  = "test\test-messenger-conformance.ps1"
    Mutations = @(
        @{ Name = "taken-read-as-handed-over"
           Find = '"taken" = "seen";'
           Replace = '"taken" = "handed-over";' }
        @{ Name = "body-mangled"
           Find = '[System.IO.File]::WriteAllText($file, [string]$Message.body,'
           Replace = '[System.IO.File]::WriteAllText($file, ([string]$Message.body -split "`n")[0],' }
        @{ Name = "absent-read-as-unknown"
           Find = 'if ($Command -ceq "status" -and $j.stage -ceq "absent") { return (New-HordeAbsent'
           Replace = 'if ($false) { return (New-HordeAbsent' }
    )
}
