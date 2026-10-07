# Mutations of decisions/settings.json, the defaults the decisions STORE runs on. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-settings.psd1
# Each changes one default; test\test-decisions-store.ps1 must fail for every one. A default nobody
# tests is a number nobody chose. The defaults a WRITE runs on are in
# test\mutations\decisions-settings-write.psd1, because another suite sees them.
@{
    Target = "decisions\settings.json"
    Suite  = "test\test-decisions-store.ps1"
    Mutations = @(
        @{ Name = "name-of-nine-digits"
           Find = '"decisions.store.sequenceDigits": { "kind": "whole-number", "default": 10,'
           Replace = '"decisions.store.sequenceDigits": { "kind": "whole-number", "default": 9,' }
        @{ Name = "name-of-eleven-digits"
           Find = '"decisions.store.sequenceDigits": { "kind": "whole-number", "default": 10,'
           Replace = '"decisions.store.sequenceDigits": { "kind": "whole-number", "default": 11,' }
        @{ Name = "gap-limit-one-more"
           Find = '"decisions.store.maxGap": { "kind": "whole-number", "default": 100,'
           Replace = '"decisions.store.maxGap": { "kind": "whole-number", "default": 101,' }
        @{ Name = "gap-limit-one-less"
           Find = '"decisions.store.maxGap": { "kind": "whole-number", "default": 100,'
           Replace = '"decisions.store.maxGap": { "kind": "whole-number", "default": 99,' }
        @{ Name = "held-record-not-waited-for"
           Find = '"decisions.store.heldReadTries": { "kind": "whole-number", "default": 40,'
           Replace = '"decisions.store.heldReadTries": { "kind": "whole-number", "default": 1,' }
        @{ Name = "held-record-waited-for-a-tenth-of-the-time"
           Find = '"decisions.store.heldReadWaitMs": { "kind": "whole-number", "default": 50,'
           Replace = '"decisions.store.heldReadWaitMs": { "kind": "whole-number", "default": 5,' }
        @{ Name = "leftover-swept-after-a-minute"
           Find = '"decisions.store.leftoverMinAgeSeconds": { "kind": "whole-number", "default": 600,'
           Replace = '"decisions.store.leftoverMinAgeSeconds": { "kind": "whole-number", "default": 60,' }
        @{ Name = "leftover-kept-for-an-hour"
           Find = '"decisions.store.leftoverMinAgeSeconds": { "kind": "whole-number", "default": 600,'
           Replace = '"decisions.store.leftoverMinAgeSeconds": { "kind": "whole-number", "default": 3600,' }
    )
}
