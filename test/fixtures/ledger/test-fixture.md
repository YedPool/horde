module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 A file in test/fixtures/ is not a test, whatever its name
- source: somewhere
- disposition: test
- where: test/fixtures/test-planted.ps1 :: "a host suite carries its own lesson"
