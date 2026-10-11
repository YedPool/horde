# decisions/Format.ps1 - the one number the decisions store's format is built on.
#
# THE ONE JOB of this file is to say how wide a record's sequence number is written, and so how large
# one can be. Two files need it and neither may get it from the other: decisions/Store.ps1 names a
# record's file by it, and decisions/Rules.ps1 - which opens no file and loads no store - refuses a
# record that claims a sequence number no file name could hold. Before this file each wrote the number
# down for itself (the store as a width, the rules as 9999999999), and a suite held the two together.
# Now there is one definition, and both read it.
#
# IT IS A CONSTANT, NOT A SETTING, and here is the reason. A setting is something a person may change
# and the module goes on working. This cannot be changed for a store that has records: a record written
# under one width is not a record under another - its name no longer matches - so every question
# already asked would become a stray file and the list would read as empty. Changing it is a migration
# of the store, which is code and a decision, not a value in a table.
#
# WHY TEN. Names sort as numbers do only when they are all one width. Ten digits is 9,999,999,999
# records; at a hundred records a day that is some 270,000 years. And a whole number of that size is
# exact in every type this module holds it in (a 64-bit integer, and a JSON number read as a Double up
# to 2^53).
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.
# FUNCTIONS, NOT $script: VARIABLES, so that a caller in any scope reads the same value (core/Platform.ps1
# says why).

function Get-HordeDecisionSequenceDigits {
    # How many digits a record's sequence number is written in, in its file name.
    return 10
}

function Get-HordeDecisionMaxSequence {
    # The largest sequence number that many digits hold: 9999999999 for ten. Worked out, never written.
    return [long]("9" * (Get-HordeDecisionSequenceDigits))
}
