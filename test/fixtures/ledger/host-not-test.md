module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 A host file outside its test folder is not a test
- source: somewhere
- disposition: test
- where: hosts/demo/tool.ps1 :: "a host suite carries its own lesson"
