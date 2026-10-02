# Fixture for test/test-function-names.ps1: a name used only inside another function is local to it,
# so it is not a second top-level definition.
function Get-FixtureOuter {
    function Get-FixtureThing { return "nested" }
    return (Get-FixtureThing)
}
