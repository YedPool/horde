# Reading a command's arguments out of $args, so that each one reaches the command's run block
# meaning what it meant on the command line - or is refused when horde cannot know what it meant.
#
# WHY THIS EXISTS. horde forwards $args, and PowerShell hands a script its unbound arguments in a
# form that loses one thing: a value joined to its parameter by a colon. Measured 2026-09-29 on
# PowerShell 5.1, `horde echo-args -Json:$false`:
#   typed, or called in-process   $args = "-Json:" (tagged as a parameter), $false (a [bool])
#   from a script, -File          $args = "-Json" (tagged as a parameter), "$false" (a [string])
# Splatted on as they stand, -Json became a bare switch - ON - and $false went to the first
# positional parameter: json=True target=[False], exit 0 (review of PR #12, finding 1).
#
# TYPED, OR IN-PROCESS, THE PAIR IS REJOINED. PowerShell itself parsed the line, the colon survives
# on the parameter's text, and the value is the object PowerShell made. Nothing is guessed.
#
# FROM A SCRIPT, THE COLON IS GONE, and nothing in $args says it was ever there: "-Count:5" and
# "-Count 5" arrive identical, which is harmless, but so do "-Json:$false" and "-Json $false", which
# is not. So an argument that is exactly the WORD "$true" or "$false" - a [string], never the [bool]
# a typed $false is - is refused with exit 2, saying why. It can only have come from a script, where
# it almost certainly meant a switch's value, and horde does not guess which parameter it was for.
#
# WHAT IS NOT CAUGHT, measured 2026-09-29, from a script: "-Json:false" arrives as "-Json" "false",
# the same as "-Json false", and binds that way; "-Json:" with nothing after it arrives as nothing,
# or swallows the next word ("-Json: -Count 5" delivers -Json, then the words "-Count" and "5").
# Neither leaves a trace in $args.
#
# NO LONGER READ: THE PROCESS COMMAND LINE. The first fix re-read [Environment]::GetCommandLineArgs()
# to learn where the colons had been. The second review of PR #12 measured it binding wrong values
# silently when horde was called from inside a command (it read the OUTER horde's command line), and
# refusing lines .NET and powershell.exe split differently (`"x"" -Json"`: two items to PowerShell,
# one to .NET). It reconstructed information -File mode had already discarded, so it was removed.
#
# The parameter tag is a note property PowerShell puts on each item it parsed as a parameter. Only
# the items of $args carry it: copied into a .NET list the tag is lost, and splatting then passes
# "-Json" as a plain string (measured). So items are only ever moved with PowerShell's own arrays.

function Get-HordeParameterName {
    # The parameter name PowerShell tagged an argument with, or $null if it is not a parameter.
    param($Item)
    if ($null -eq $Item) { return $null }
    $p = $Item.PSObject.Properties["<CommandParameterName>"]
    if ($p) { return "$($p.Value)" }
    return $null
}

function Resolve-HordeArguments {
    # Split a command's arguments into { named; positional; problem } for `& $run @named @positional`.
    # named holds every parameter given with a colon that survived (typed or in-process); positional
    # holds everything else, in order, as the very objects $args held. problem is a message when the
    # arguments cannot be read faithfully, and the caller exits 2 with it.
    #
    # Items: the command's items from $args.
    param($Items)
    $named = @{}
    $positional = @()
    $items = @($Items)
    $fail = { param($m) return [pscustomobject]@{ named = @{}; positional = @(); problem = $m } }

    for ($j = 0; $j -lt $items.Count; $j++) {
        $item = $items[$j]
        $pname = Get-HordeParameterName -Item $item
        if ($pname -and "$item".EndsWith(":")) {
            # Typed, "-Json:" with nothing after it is a parse error before horde runs, so a colon
            # with no item after it cannot arrive this way; refused all the same, never guessed.
            if ($j + 1 -ge $items.Count) { return (& $fail ("parameter " + $item + " needs a value after the colon")) }
            if ($named.ContainsKey($pname)) { return (& $fail ("parameter -" + $pname + " is given more than once")) }
            $item = $items[$j + 1]
            if ($item -is [string] -and ($item -ieq '$true' -or $item -ieq '$false')) {
                # Typed as the quoted text '$false': still a word, not a truth value.
                return (& $fail (Get-HordeTextBoolProblem -Text $item))
            }
            $named[$pname] = $item
            $j++
            continue
        }
        if ($item -is [string] -and ($item -ieq '$true' -or $item -ieq '$false')) {
            return (& $fail (Get-HordeTextBoolProblem -Text $item))
        }
        $positional += $item
    }
    return [pscustomobject]@{ named = $named; positional = $positional; problem = $null }
}

function Get-HordeTextBoolProblem {
    # The message for an argument that is the word "$true" or "$false" rather than the value.
    param([string]$Text)
    return ("the argument '" + $Text + "' arrived as text, not as " + $Text + ": run as a script (powershell -File), " +
        "PowerShell drops the colon from -Name:" + $Text + " and passes the value as a word, so horde cannot tell which " +
        "parameter it was for. Leave the switch out to keep it off, or give it bare to turn it on")
}
