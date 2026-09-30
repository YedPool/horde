module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 cites a test name that survives only in a comment
- source: s
- disposition: test
- where: test/test-sample.ps1 :: "the lesson is fully enforced"
