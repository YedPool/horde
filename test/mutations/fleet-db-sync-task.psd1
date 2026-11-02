# Mutations of the scheduled task definition (fleet-db/register-sync.ps1): its pace and every setting its header explains. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-sync-task.psd1
# test\test-db-sync.ps1 must fail a check for every one (it reads the file and lists the task with -WhatIf; nothing is
# registered). Every find string occurs once.
@{
    Target = "fleet-db\register-sync.ps1"
    Suite  = "test\test-db-sync.ps1"
    Mutations = @(
        @{ Name = "every-two-minutes"
           Find = '$everyMinutes = 1'
           Replace = '$everyMinutes = 2' }
        @{ Name = "overlap-allowed"
           Find = '-MultipleInstances IgnoreNew'
           Replace = '-MultipleInstances Parallel' }
        @{ Name = "normal-priority"
           Find = '$settings.Priority = 7'
           Replace = '$settings.Priority = 4' }
        @{ Name = "limit-five-minutes"
           Find = '$limitMinutes = 2'
           Replace = '$limitMinutes = 5' }
        @{ Name = "runs-elevated"
           Find = '-RunLevel Limited'
           Replace = '-RunLevel Highest' }
        @{ Name = "window-every-minute"
           Find = '$argument = ''--headless "'' + $shell'
           Replace = '$argument = ''"'' + $shell' }
        @{ Name = "home-baked-into-the-command"
           Find = '$command = "& ''" + $scriptQ + "'' db sync; exit $" + "LASTEXITCODE"'
           Replace = '$command = "$" + "env:HORDE_HOME = ''" + $effective + "''; & ''" + $scriptQ + "'' db sync; exit $" + "LASTEXITCODE"' }
    )
}
