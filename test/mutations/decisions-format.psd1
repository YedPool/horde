# Mutations of decisions/Format.ps1, the one constant the decisions store's format is built on. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-format.psd1
# Each changes the width a record's sequence number is written in, or the largest number worked out
# from it; test\test-decisions-store.ps1 must fail for every one.
@{
    Target = "decisions\Format.ps1"
    Suite  = "test\test-decisions-store.ps1"
    Mutations = @(
        @{ Name = "name-of-nine-digits"
           Find = '    return 10'
           Replace = '    return 9' }
        @{ Name = "name-of-eleven-digits"
           Find = '    return 10'
           Replace = '    return 11' }
        @{ Name = "largest-sequence-one-digit-short"
           Find = 'return [long]("9" * (Get-HordeDecisionSequenceDigits))'
           Replace = 'return [long]("9" * ((Get-HordeDecisionSequenceDigits) - 1))' }
        @{ Name = "largest-sequence-written-down-as-nine-digits"
           Find = 'return [long]("9" * (Get-HordeDecisionSequenceDigits))'
           Replace = 'return [long]999999999' }
    )
}
