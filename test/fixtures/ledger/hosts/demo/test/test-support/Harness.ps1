# A helper inside a folder whose NAME begins test-. A suite sits directly in test/ or e2e/, so a file
# one folder deeper is refused whatever the folder is called.
Check ($x -eq "carried") "a host suite carries its own lesson"
