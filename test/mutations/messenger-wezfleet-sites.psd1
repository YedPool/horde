# Mutations of the wezfleet messenger's start site, against the family's list of start sites (remote plan
# R21, slice 3b, merge condition 2). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\messenger-wezfleet-sites.psd1
# test\test-start-sites.ps1 must fail for each: the suite only parses, so no mutant here is ever run.
@{
    Target = "messengers\wezfleet\Messenger.ps1"
    Suite  = "test\test-start-sites.ps1"
    Mutations = @(
        @{ Name = "another-program"
           Find = '"WindowsPowerShell", "v1.0", "powershell.exe"), (ConvertTo-HordeWezfleetMessengerCommandLine'
           Replace = '"cmd.exe"), (ConvertTo-HordeWezfleetMessengerCommandLine' }
        @{ Name = "program-from-path"
           Find = '[System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")'
           Replace = '"powershell.exe"' }
        @{ Name = "second-start"
           Find = 'try { $p = [System.Diagnostics.Process]::Start($psi) }'
           Replace = '$q = [System.Diagnostics.Process]::Start($psi); try { $p = [System.Diagnostics.Process]::Start($psi) }' }
        @{ Name = "shell-start"
           Find = '$psi.UseShellExecute = $false'
           Replace = '$psi.UseShellExecute = $false; Start-Process $Script' }
    )
}
