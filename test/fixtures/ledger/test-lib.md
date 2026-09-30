module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 A file in test/lib/ is not a test, whatever its name
- source: somewhere
- disposition: test
- where: test/lib/test-lib-sample.ps1 :: "a host suite carries its own lesson"
