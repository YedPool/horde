module: fixture/sample
sources:
- comments: searched
- history: searched
- pull requests: searched
- docs: searched
- tests: searched

### L-001 An unreadable source is unknown, never empty
- source: YedPool/wezfleet lib/Hosts.ps1:59
- disposition: test
- where: test/test-sample.ps1 :: "an unreadable source reads as unknown"
