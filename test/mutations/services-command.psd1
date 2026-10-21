# Mutations of cli/commands/services.ps1 (the real command's wiring of the installed CLI). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\services-command.psd1
# Each deletes one hand-over the command makes; test\test-services-cli.ps1 drives the real command and must fail for every one.
@{
    Target = "cli\commands\services.ps1"
    Suite  = "test\test-services-cli.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "cli-follow-block-removed"
           Find = '$tools["CliFollow"] = {'
           Replace = '$tools["CliFollowRemoved"] = {' }
        @{ Name = "cli-status-block-removed"
           Find = '$tools["CliStatus"] = {'
           Replace = '$tools["CliStatusRemoved"] = {' }
        @{ Name = "cli-follow-ignores-settings"
           Find = 'return (Invoke-HordeInstalledCliFollow -HordeHome $HordeHome -Policy $Policy -Now $Now -Tell $Teller)'
           Replace = 'return @()' }
    )
}
