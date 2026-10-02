# Fixture for test/test-function-names.ps1: defines the same name in another case, so the scan must
# compare names ignoring case, as PowerShell resolves them.
function get-fixturething { return "two" }
