module: fixture/sample
replaces: nothing - this is a fixture for the ledger gate
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 A path that climbs with .. is refused though it lands on a test
- source: somewhere
- disposition: test
- where: hosts/demo/test/../../../test/test-sample.ps1 :: "an unreadable source reads as unknown"
