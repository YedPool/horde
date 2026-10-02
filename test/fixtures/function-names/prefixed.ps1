# Fixture for test/test-function-names.ps1: every other way the guard counts a definition.
function script:Get-FixtureThing { return "prefixed" }
function Get-FixtureHolder {
    function global:Get-FixtureNested { return "nested but global" }
}
Set-Item -Path 'function:Get-FixtureItem' -Value { return "item" }
Set-Alias -Name 'Get-FixtureAlias' -Value 'Get-FixtureHolder'
