# Mutations of cli/commands/home.ps1, the `horde home` verb (T-0299), and of the db verb's home gate. Each breaks one rule
# of the verb; test\e2e\e2e-home.ps1 (the real horde.ps1, its own profile and homes) must fail a check for every one. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\home-verb.psd1
@{
    Target = "cli\commands\home.ps1"
    Suite  = "test\e2e\e2e-home.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "path-flag-accepted-on-clear"
           Find = 'if ($PSBoundParameters.ContainsKey("Path") -and $Verb -ne "set")'
           Replace = 'if ($false)' }
        @{ Name = "set-without-path-not-refused"
           Find = 'if (-not $PSBoundParameters.ContainsKey("Path"))'
           Replace = 'if ($false)' }
        @{ Name = "set-does-not-write"
           Find = '$r = Set-HordeHomePointer -Path $Path'
           Replace = '$r = [pscustomobject]@{ old = ""; new = $Path; file = "" }' }
        @{ Name = "set-hides-the-new-home"
           Find = 'Write-Output ("new home: " + $r.new)'
           Replace = '' }
        @{ Name = "clear-does-not-remove"
           Find = '$r = Clear-HordeHomePointer'
           Replace = '$r = [pscustomobject]@{ removed = $true; file = "" }' }
        @{ Name = "clear-hides-the-home-now"
           Find = 'Write-Output ("home now: " + $now.path + " (" + $now.source + ")")'
           Replace = '' }
        @{ Name = "clear-reports-removal-when-none"
           Find = '"no pointer to remove: "'
           Replace = '"pointer removed: "' }
        @{ Name = "pointer-source-not-shown"
           Find = '"pointer" { "pointer " + (Get-HordeHomePointerPath) }'
           Replace = '"pointer" { "default" }' }
        @{ Name = "default-source-mislabelled"
           Find = 'default { "default (the .horde folder in the user profile)" }'
           Replace = 'default { "HORDE_HOME" }' }
        @{ Name = "any-verb-accepted"
           Find = '[ValidateSet("set", "clear")]'
           Replace = '[ValidateSet("set", "clear", "nonsense")]' }
    )
}
