module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 A path written in another case than the file's is refused
- source: somewhere
- disposition: test
- where: HOSTS/demo/TEST/test-host-sample.PS1 :: "a host suite carries its own lesson"
