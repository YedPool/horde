# Runs one command's run block, and nothing else. horde.ps1 calls it; nothing else should.
#
# WHY A SEPARATE SCRIPT WITH ONE CALL IN IT. A ParameterBindingException means the command line was
# wrong only when it is the run block's OWN binding that failed. One raised inside the body - a
# command calling `Get-ChildItem -NoSuchParam` - is the command failing, and used to be reported as
# exit 2 with the usage (review of PR #12, finding 5). The exception names the invocation that failed
# to bind; when that invocation is in THIS file it can only be the call below, because nothing else
# here calls anything. Measured 2026-09-29 on PowerShell 5.1: the run block's own failure carries this
# file as its ScriptName, and the body's carries the command file.
#
# AND WHY `exit` STOPS HERE. `exit` inside a script block ends the nearest SCRIPT on the call stack.
# Called straight from horde.ps1, a command's `exit 7` made horde exit 7 and a bare `exit` made it
# exit 0 (review of PR #12, finding 6). Called from here, it ends this script instead, the line after
# the call never runs, and horde sees $State.completed still false. Measured 2026-09-29.
#
# AND WHY THE LOOP THAT NEVER LOOPS. `break` and `continue` travel up the call stack to the nearest
# enclosing loop, across script boundaries. With no loop here, a body's `cmd /c exit 3; break` left
# this script and horde's without running either's remaining lines, and horde exited 0 (second
# review of PR #12, finding 3). The do-while is that nearest loop: it takes an unlabelled break or
# continue, the completion line is skipped, and horde reports the command as not having returned.
# A LABELLED break whose label matches nothing passes this loop too - measured 2026-09-29 - and
# horde.ps1 catches that in its finally block.
param($Run, $Named, $Positional, $State)
# The body runs in a scope below this one and could read and change these four - $State.completed
# included (second review of PR #12, finding 5). A parameter cannot be declared $private:, so each is
# made private once bound; measured 2026-09-29, the body then sees none of them by name. As in
# horde.ps1, Get-Variable -Scope 1 still reaches them: this stops accidents, not intent.
foreach ($private:hordeParam in @("Run", "Named", "Positional", "State")) { (Get-Variable -Name $hordeParam -Scope Local).Options = "Private" }
do { & $Run @Named @Positional; $State.completed = $true } while ($false)
