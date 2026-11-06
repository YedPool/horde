# Mutations of the job command (cli/commands/job.ps1): which flags belong to which verb, which flags reach node. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\job-command.psd1
# test\test-job-signal.ps1 must fail a check for every one. Every find string occurs once.
@{
    Target = "cli\commands\job.ps1"
    Suite  = "test\test-job-signal.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "flag-of-another-verb-accepted"
           Find = 'if ($flag -ne "Verb" -and $own[$Verb] -notcontains $flag) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "list-takes-a-proof"
           Find = 'list   = @("Owner", "Open", "Overdue", "Json")'
           Replace = 'list   = @("Owner", "Open", "Overdue", "Json", "Proof")' }
        @{ Name = "id-not-passed"
           Find = '"--id" = "Id"; '
           Replace = '' }
        @{ Name = "owner-not-passed"
           Find = '"--owner" = "Owner"; '
           Replace = '' }
        @{ Name = "job-text-not-passed"
           Find = '"--job" = "Job"; '
           Replace = '' }
        @{ Name = "proof-not-passed"
           Find = '"--proof" = "Proof"; '
           Replace = '' }
        @{ Name = "file-not-passed"
           Find = '"--file" = "File"; '
           Replace = '' }
        @{ Name = "session-not-passed"
           Find = '"--session" = "Session"'
           Replace = '"--unused" = "Unused"' }
        @{ Name = "started-not-passed"
           Find = '"--started" = "Started"; '
           Replace = '' }
        @{ Name = "due-not-passed"
           Find = '"--due" = "Due"; '
           Replace = '' }
        @{ Name = "by-not-passed"
           Find = '"--by" = "By"; '
           Replace = '' }
        @{ Name = "at-not-passed"
           Find = '; "--at" = "At"'
           Replace = '' }
        @{ Name = "open-not-passed"
           Find = 'if ($Open) { $bare += "--open" }'
           Replace = '' }
        @{ Name = "overdue-not-passed"
           Find = 'if ($Overdue) { $bare += "--overdue" }'
           Replace = '' }
        @{ Name = "json-not-passed"
           Find = 'if ($Json) { $bare += "--json" }'
           Replace = '' }
    )
}
