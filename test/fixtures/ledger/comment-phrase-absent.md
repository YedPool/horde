module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 carries a phrase that is not there
- source: s
- disposition: comment
- where: docs/carried.ps1 :: "this phrase is not in the file"
