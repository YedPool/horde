module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 A harness in a host's test folder is not a test
- source: somewhere
- disposition: test
- where: hosts/demo/test/Harness.ps1 :: "a host suite carries its own lesson"
