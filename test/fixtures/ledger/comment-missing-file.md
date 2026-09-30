module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 carries a comment in a missing file
- source: s
- disposition: comment
- where: docs/nope.ps1 :: "some words that are here"
