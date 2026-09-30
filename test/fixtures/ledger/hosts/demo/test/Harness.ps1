# A HARNESS in a host's test folder, not a suite: it is dot-sourced by suites and asserts nothing
# of its own. It quotes a test name so that its being a harness is the only thing wrong with it.
Check ($x -eq "carried") "a host suite carries its own lesson"
