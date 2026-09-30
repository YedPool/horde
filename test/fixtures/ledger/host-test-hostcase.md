module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 A host folder written in another case than on disk is refused
- source: somewhere
- disposition: test
- where: hosts/Demo/test/test-host-sample.ps1 :: "a host suite carries its own lesson"
