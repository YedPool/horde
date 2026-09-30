module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 A file in a test-named subfolder is not a suite
- source: somewhere
- disposition: test
- where: hosts/demo/test/test-support/Harness.ps1 :: "a host suite carries its own lesson"
