module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 Points at an assertion that is not there
- source: somewhere
- disposition: test
- where: test/test-sample.ps1 :: "this text appears nowhere"
