function Get-Two { return 2 }
# One answer, reached by a different branch under PowerShell 7 than under 5.1 - as code is where a .NET
# method became an extension method (T-0422). Only a run under 7 takes the Core branch.
function Get-EditionTwo { if (("" + $PSVersionTable.PSEdition) -ceq "Core") { return 2 } return 2 }
# Its mutant makes the suite BREAK under 5.1 (a throw, no failed check) and fail a check under 7: a
# catch that only the second shell makes, after the first broke (review of PR 497, finding 1).
function Get-EditionThree { if (("" + $PSVersionTable.PSEdition) -ceq "Core") { return 3 } return 3 }
