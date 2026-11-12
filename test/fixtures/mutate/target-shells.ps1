function Get-Two { return 2 }
# One answer, reached by a different branch under PowerShell 7 than under 5.1 - as code is where a .NET
# method became an extension method (T-0422). Only a run under 7 takes the Core branch.
function Get-EditionTwo { if (("" + $PSVersionTable.PSEdition) -ceq "Core") { return 2 } return 2 }
