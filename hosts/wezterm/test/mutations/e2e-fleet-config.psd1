# Mutations of test/e2e/e2e-fleet.ps1's terminal config. Run:
#   powershell -File tools\Mutate.ps1 -Spec hosts\wezterm\test\mutations\e2e-fleet-config.psd1
# The scenario must give every command it runs an empty config of its own, or a cli call loads the person's
# config and its plugin manager clones into the scenario's profile (T-0216); hosts\wezterm\test\test-isolation.ps1
# must fail a check for each of these.
@{
    Target = "test\e2e\e2e-fleet.ps1"
    Suite  = "hosts\wezterm\test\test-isolation.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "scenario-commands-load-the-persons-config"
           Find = 'WEZTERM_CONFIG_FILE = $emptyTermConfig; PATH ='
           Replace = 'PATH =' }
        @{ Name = "empty-config-outside-the-scenario"
           Find = '$emptyTermConfig = Join-Path $work "terminal-empty.lua"'
           Replace = '$emptyTermConfig = Join-Path $env:TEMP "terminal-empty.lua"' }
    )
}
