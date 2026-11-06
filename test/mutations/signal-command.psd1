# Mutations of the signal command (cli/commands/signal.ps1): which flags belong to which verb, which flags reach node. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\signal-command.psd1
# test\test-job-signal.ps1 must fail a check for every one. Every find string occurs once.
@{
    Target = "cli\commands\signal.ps1"
    Suite  = "test\test-job-signal.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "flag-of-another-verb-accepted"
           Find = 'if ($flag -ne "Verb" -and $own[$Verb] -notcontains $flag) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "close-takes-days"
           Find = 'close = @("Key", "By")'
           Replace = 'close = @("Key", "By", "Days")' }
        @{ Name = "key-not-passed"
           Find = '"--key" = "Key"; '
           Replace = '' }
        @{ Name = "kind-not-passed"
           Find = '"--kind" = "Kind"; '
           Replace = '' }
        @{ Name = "owner-not-passed"
           Find = '"--owner" = "Owner"; '
           Replace = '' }
        @{ Name = "text-not-passed"
           Find = '"--text" = "Text"; '
           Replace = '' }
        @{ Name = "file-not-passed"
           Find = '"--file" = "File"'
           Replace = '"--unused" = "Unused"' }
        @{ Name = "at-not-passed"
           Find = '"--at" = "At"; '
           Replace = '' }
        @{ Name = "by-not-passed"
           Find = '"--by" = "By"; '
           Replace = '' }
        @{ Name = "days-not-passed"
           Find = '; "--days" = "Days"'
           Replace = '' }
        @{ Name = "urgent-not-passed"
           Find = 'if ($Urgent) { $bare += "--urgent" }'
           Replace = '' }
        @{ Name = "quiet-not-passed"
           Find = 'if ($Quiet) { $bare += "--quiet" }'
           Replace = '' }
        @{ Name = "woke-takes-a-days-flag"
           Find = 'woke  = @("Key", "At")'
           Replace = 'woke  = @("Key", "At", "Days")' }
        @{ Name = "open-not-passed"
           Find = 'if ($Open) { $bare += "--open" }'
           Replace = '' }
        @{ Name = "unwoken-not-passed"
           Find = 'if ($Unwoken) { $bare += "--unwoken" }'
           Replace = '' }
        @{ Name = "mark-woke-not-passed"
           Find = 'if ($MarkWoke) { $bare += "--mark-woke" }'
           Replace = '' }
        @{ Name = "json-not-passed"
           Find = 'if ($Json) { $bare += "--json" }'
           Replace = '' }
    )
}
