module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 A host-specific lesson is tested in the host's own test folder
- source: somewhere
- disposition: test
- where: hosts/demo/test/test-host-sample.ps1 :: "a host suite carries its own lesson"
