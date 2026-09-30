module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 quotes text that is not a quoted string
- source: s
- disposition: test
- where: test/test-sample.ps1 :: "stand-in test file for"
