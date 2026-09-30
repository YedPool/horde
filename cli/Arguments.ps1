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
# is not. So an argument that is exactly the WORD "$true", "$false" or "$null", in any case - a
# [string], never the value a typed $false is - is refused with exit 2, saying why. It can only have
# come from a script, where it almost certainly meant a value, and horde does not guess which
# parameter it was for. "$null" joined them in the third review of PR #12 (finding 4): from a
# script `-Verb:$null x` bound verb=[$null] target=[x], the literal text, exit 0.
#
# A SWITCH FOLLOWED BY A TRUTH WORD IS REFUSED TOO. From a script "-Json:false" arrives as "-Json"
# "false", the same as "-Json false", and bound json=True target=[false] with exit 0 (measured
# 2026-09-29). The word "false" is also a perfectly good positional value, so the word alone cannot
# be refused as "$false" is. What horde can know is which parameters are switches - the registry
# reads them from the run block's param AST without running it - so a switch followed IMMEDIATELY by
# an untagged word that is true, false, $true, $false, 0, 1, yes, no, on or off, in any case, exits
# 2: the user is told to omit the switch, give it bare, or put the word before it. The third review
# of PR #12 (finding 4) measured -Json:0, :1, :no and :off from a script binding json=True and the
# word as the target, exit 0; typed, PowerShell refuses each of them, so a caller cannot have meant
# a positional by them either way. Typed, "-Json false" arrives the same way and is refused the same
# way; typed "-Json:false" keeps the colon and is PowerShell's to refuse. Typed "-Json 0" is NOT
# refused: there 0 arrives as a number, which only PowerShell's own parsing makes, so it is a
# positional as the line says.
#
# A SWITCH FOLLOWED BY A TRUTH VALUE IS REFUSED. Typed or in-process, `-Json $false` arrives as the
# tagged switch and a [bool] - not a word - and PowerShell binds it as the switch ON and $false an
# argument: json=True target=[False], exit 0 (third review of PR #12, finding 3). A [bool] cannot
# arrive from a script, where every argument is text, so this is a typed or in-process caller asking
# for the opposite of what it gets; it exits 2 and is told to join the value with a colon.
#
# WHAT IS STILL NOT CAUGHT, measured 2026-09-29, from a script: "-Json:" with nothing after it
# arrives as nothing, or swallows the next word ("-Json: -Count 5" delivers -Json, then the words
# "-Count" and "5"). It leaves no trace in $args. And a switch's colon value outside the words above
# - "-Json:2", "-Json:y", "-Json:$x" - arrives exactly as the switch and an argument would, and binds
# that way (measured 2026-09-30: json=True target=[2], [y] and [$x], exit 0).
#
# NOR A WRAPPER THAT FORWARDS ONE ITEM OF ITS OWN $args: the item keeps its tag. `function F { &
# horde.ps1 echo-args $args[0] }; F -Json`, meaning "-Json" as the target, bound json=True target=[],
# exit 0 (measured 2026-09-30, third review of PR #12, finding 5). horde receives exactly what a
# caller giving the switch would give it, so nothing here can tell the two apart. A wrapper that
# means a value passes it as text: `"$($args[0])"` bound target=[-Json].
#
# "--" IS REFUSED WHEREVER IT ARRIVES. Typed, PowerShell consumes it before horde runs and what
# follows is plain words, so horde never sees it. From a script it arrives as an argument, and a
# -Name after it is still tagged as a parameter, so its meaning cannot be given; it exits 2 instead.
#
# NO LONGER READ: THE PROCESS COMMAND LINE. The first fix re-read [Environment]::GetCommandLineArgs()
# to learn where the colons had been. The second review of PR #12 measured it binding wrong values
# silently when horde was called from inside a command (it read the OUTER horde's command line), and
# refusing lines .NET and powershell.exe split differently (`"x"" -Json"`: two items to PowerShell,
# one to .NET). It reconstructed information -File mode had already discarded, so it was removed.
#
# The parameter tag is a note property PowerShell puts on each item it parsed as a parameter; it
# lives on PowerShell's wrapper around the string, not on the string. Measured 2026-09-30 on
# PowerShell 5.1 by copying $args holding -Json and splatting the copy (third review of PR #12,
# finding 6): the tag SURVIVED an index slice, +=, an [object[]] or [List[object]] cast,
# [ArrayList]$args, ArrayList.AddRange, Select-Object and ForEach-Object { $_ }. It was LOST - "-Json"
# bound as a plain string to the first positional parameter - by ArrayList.Add($item) in a loop (a
# .NET method's argument is unwrapped), a [string[]] cast, and anything that makes a new string:
# "$_", "$item", [string]. The note here once said any copy into a .NET list loses it: ArrayList.Add
# does, the ArrayList cast and AddRange do not. Items are moved only in ways measured to keep it, and
# Resolve-HordeArguments makes a new string on purpose where it must drop a tag.

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
    # Items: the command's items from $args. Parameters: the run block's parameters, as the registry
    # read them ({ name; aliases; switch }); with none, no argument is taken for a switch.
    param($Items, $Parameters = @())
    $named = @{}
    $positional = @()
    $items = @($Items)
    $fail = { param($m) return [pscustomobject]@{ named = @{}; positional = @(); problem = $m } }

    for ($j = 0; $j -lt $items.Count; $j++) {
        $item = $items[$j]
        if ("$item" -ceq "--") {
            # Typed, PowerShell consumes "--" itself and passes what follows as words. From a script it
            # arrives as an item - quoted, tagged as a parameter with an empty name, which PowerShell
            # then reported as "parameter name '' is ambiguous" - and a -Name after it is still a
            # parameter. Measured 2026-09-29. horde cannot give it its meaning there, so it says so.
            return (& $fail ("'--' is not supported: run as a script (powershell -File) it arrives as an ordinary argument, not as the end of the parameters, so horde cannot give it that meaning"))
        }
        $pname = Get-HordeParameterName -Item $item
        if ($pname -and "$item".EndsWith(":")) {
            # Typed, "-Json:" with nothing after it is a parse error before horde runs, and -Json:$m
            # with $m unset arrives as "-Json:" and a $null item, which horde.ps1 keeps. It did not
            # always: taken through a pipeline the $null was dropped and the NEXT word became the
            # value (third review of PR #12, finding 1). A colon item with nothing after it means an
            # item was lost before this point; it is refused, never guessed.
            if ($j + 1 -ge $items.Count) { return (& $fail ("parameter " + $item + " needs a value after the colon")) }
            if ($named.ContainsKey($pname)) { return (& $fail ("parameter -" + $pname + " is given more than once")) }
            $value = $items[$j + 1]
            if (Test-HordeTextValue -Item $value) {
                # Typed as the quoted text '$false': still a word, not a truth value.
                return (& $fail (Get-HordeTextValueProblem -Text $value))
            }
            $named[$pname] = $value
            $j++
            continue
        }
        if (Test-HordeTextValue -Item $item) {
            return (& $fail (Get-HordeTextValueProblem -Text $item))
        }
        if ($pname -and $j + 1 -lt $items.Count) {
            $next = $items[$j + 1]
            # A [bool] can only come from PowerShell's own parsing - typed, or in-process - where
            # `-Json $false` means the switch ON and $false an argument: it bound json=True
            # target=[False], exit 0 (third review of PR #12, finding 3). No caller writes that
            # meaning it, so it is refused; -Json:$false is how a switch is given a value.
            if ($next -is [bool] -and (Get-HordeParameterKind -Name $pname -Parameters $Parameters) -eq "switch") {
                return (& $fail (Get-HordeSwitchBoolProblem -Switch "$item" -Value $next))
            }
            # No separate "is it untagged" test: a tagged item's text starts with "-", so it never
            # matches the pattern, and a check that cannot change the outcome is one no test can hold.
            if ($next -is [string] -and $next -imatch '\A(\$?(true|false)|[01]|yes|no|on|off)\z' -and
                (Get-HordeParameterKind -Name $pname -Parameters $Parameters) -eq "switch") {
                return (& $fail (Get-HordeSwitchWordProblem -Switch "$item" -Word $next))
            }
        }
        if ($pname -and @("-?", "-h", "--help") -contains "$item" -and
            (Test-HordeParameterValue -Items $items -Index $j -Parameters $Parameters)) {
            # A help word that is a parameter's value (see Test-HordeHelpRequest) goes on as plain
            # text. Still tagged, "-?" is PowerShell's own help switch: -Verb -? failed with
            # '"helpTarget" is null', exit 1 (measured 2026-09-30); "$item" is a new string, untagged.
            $item = "$item"
        }
        $positional += $item
    }
    return [pscustomobject]@{ named = $named; positional = $positional; problem = $null }
}

function Get-HordeParameterKind {
    # What a parameter name, as typed, names in the run block: "switch", "value" for a parameter that
    # takes a value, or "" for none. PowerShell accepts a parameter's full name, an alias, or any
    # unambiguous prefix, and every [CmdletBinding()] block also takes the common parameters, -Verbose
    # and -Debug among them as switches ("-Verbose false" bound target=[false], measured 2026-09-29).
    # An exact name or alias decides; otherwise the name is a switch if ANY parameter it is a prefix of
    # is one, and a value if it is a prefix only of parameters that take one. Where that prefix is
    # ambiguous, PowerShell refuses the line with exit 2 anyway, so either answer costs nothing.
    param([string]$Name, $Parameters)
    $switches = @("Verbose", "Debug", "WhatIf", "Confirm")
    $others = @("ErrorAction", "WarningAction", "InformationAction", "ErrorVariable", "WarningVariable",
        "InformationVariable", "OutVariable", "OutBuffer", "PipelineVariable")
    $names = New-Object System.Collections.ArrayList
    foreach ($p in @($Parameters)) {
        foreach ($n in @(@($p.name) + @($p.aliases))) { if ("$n") { [void]$names.Add([pscustomobject]@{ n = "$n"; s = [bool]$p.switch }) } }
    }
    foreach ($n in $switches) { [void]$names.Add([pscustomobject]@{ n = $n; s = $true }) }
    foreach ($n in $others) { [void]$names.Add([pscustomobject]@{ n = $n; s = $false }) }
    $exact = @($names | Where-Object { $_.n -ieq $Name })
    if ($exact.Count -gt 0) { if ($exact[0].s) { return "switch" } else { return "value" } }
    $prefixed = @($names | Where-Object { $_.n.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase) })
    if (@($prefixed | Where-Object { $_.s }).Count -gt 0) { return "switch" }
    if ($prefixed.Count -gt 0) { return "value" }
    return ""
}

function Test-HordeParameterValue {
    # Whether the item at Index is the VALUE of the item before it, and so means nothing on its own:
    # the item before is a parameter joined to it by a colon (typed "-Target:" then "-h"), or a
    # parameter that takes a value ("-Verb" then "-h"; from a script "-Target:-h" arrives this way too,
    # the colon gone). After a switch, or a name the run block does not have, it stands on its own.
    param($Items, [int]$Index, $Parameters)
    if ($Index -lt 1) { return $false }
    $before = $Items[$Index - 1]
    $name = Get-HordeParameterName -Item $before
    if (-not $name) { return $false }
    if ("$before".EndsWith(":")) { return $true }
    return ((Get-HordeParameterKind -Name $name -Parameters $Parameters) -eq "value")
}

function Test-HordeHelpRequest {
    # Whether a command's items ask for its help: -?, -h or --help anywhere, UNLESS it is a
    # parameter's value. `echo-args -Target:-h`, `-Verb:--help` and `-Verb -h` printed the usage and
    # exited 0 instead of running with that value (third review of PR #12, finding 2).
    # Resolve-HordeArguments passes such a value on as plain text; see there for why.
    param($Items, $Parameters)
    $items = @($Items)
    for ($j = 0; $j -lt $items.Count; $j++) {
        if (@("-?", "-h", "--help") -contains "$($items[$j])" -and
            -not (Test-HordeParameterValue -Items $items -Index $j -Parameters $Parameters)) { return $true }
    }
    return $false
}

function Get-HordeSwitchWordProblem {
    # The message for a switch followed by the word true or false.
    param([string]$Switch, [string]$Word)
    return ("the switch " + $Switch + " is followed by the word '" + $Word + "', which arrived as text: run as a script " +
        "(powershell -File), PowerShell passes " + $Switch + ":" + $Word + " as " + $Switch + " and a separate word, so horde " +
        "cannot tell whether '" + $Word + "' was the switch's value or an argument. Omit the switch to keep it off, give it " +
        "bare to turn it on, or reorder the arguments so the word comes before the switch if it is an argument")
}

function Get-HordeSwitchBoolProblem {
    # The message for a switch followed by the value $true or $false as a separate argument.
    param([string]$Switch, [bool]$Value)
    $v = "`$" + "$Value".ToLower()
    return ("the switch " + $Switch + " is followed by the value " + $v + " as a separate argument: PowerShell turns " +
        "the switch on and passes " + $v + " on as an argument, so it never reaches the switch. Join it with a colon (" +
        $Switch + ":" + $v + ") to set the switch, omit the switch to keep it off, or reorder the arguments so the value " +
        "comes before the switch if it is an argument")
}

function Test-HordeTextValue {
    # Whether an item is the WORD "$true", "$false" or "$null", in any case - text, never the value.
    param($Item)
    return ($Item -is [string] -and @('$true', '$false', '$null') -contains $Item)
}

function Get-HordeTextValueProblem {
    # The message for an argument that is the word "$true", "$false" or "$null" rather than the value.
    param([string]$Text)
    return ("the argument '" + $Text + "' arrived as text, not as " + $Text + ": run as a script (powershell -File), " +
        "PowerShell drops the colon from -Name:" + $Text + " and passes the value as a word, so horde cannot tell which " +
        "parameter it was for. Leave the parameter out, or give a switch bare to turn it on")
}
