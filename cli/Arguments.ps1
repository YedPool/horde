# Reading a command's arguments out of $args, so that each one reaches the command's run block
# meaning what it meant on the command line.
#
# WHY THIS EXISTS. horde forwards $args, and PowerShell hands a script its unbound arguments in a
# form that loses one thing: a value joined to its parameter by a colon. Measured 2026-09-29 on
# PowerShell 5.1, `horde echo-args -Json:$false`:
#   typed at a prompt   $args = "-Json:" (tagged as a parameter), $false (a [bool])
#   from a script, -File $args = "-Json" (tagged as a parameter), "$false" (a string)
# Splatted on as they stand, -Json became a bare switch - ON - and $false went to the first
# positional parameter: json=True target=[False], exit 0 (review of PR #12, finding 1).
#
# Typed, the colon survives on the parameter's text, so the pair can be rejoined from $args alone.
# From a script it does not: "-Json:$false" and "-Json" "$false" arrive identical. The only record of
# the colon is the process's own command line, so that is read to learn WHICH items were joined -
# and the values themselves are still taken from $args, the objects PowerShell made.
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

function Get-HordeFileModeArguments {
    # When this process was started as `powershell -File <ScriptPath> ...`, the arguments after the
    # script path exactly as the process received them: { found; args }. Otherwise found is $false -
    # typed at a prompt, or called from another script, the command line belongs to someone else.
    param([string]$ScriptPath)
    $none = [pscustomobject]@{ found = $false; args = @() }
    if (-not $ScriptPath) { return $none }
    $cl = [Environment]::GetCommandLineArgs()
    $want = [System.IO.Path]::GetFullPath($ScriptPath)
    for ($k = 1; $k -lt $cl.Count - 1; $k++) {
        if ($cl[$k] -notmatch '\A[-/]f(i(le?)?)?\z') { continue }
        $target = $null
        try { $target = [System.IO.Path]::GetFullPath($cl[$k + 1]) } catch { continue }
        if ($target -ieq $want) {
            return [pscustomobject]@{ found = $true; args = @($cl | Select-Object -Skip ($k + 2)) }
        }
    }
    return $none
}

function ConvertFrom-HordeFileModeValue {
    # A colon value from a script's command line is always a string. "$true" and "$false" are the two
    # PowerShell documents for a switch in -File mode, so they become booleans; anything else stays a
    # string for the parameter's own type to convert, or refuse.
    param([string]$Text)
    if ($Text -ieq '$true') { return $true }
    if ($Text -ieq '$false') { return $false }
    return $Text
}

function Resolve-HordeArguments {
    # Split a command's arguments into { named; positional; problem } for `& $run @named @positional`.
    # named holds every parameter given with a colon; positional holds everything else, in order, as
    # the very objects $args held. problem is a message when the arguments cannot be read faithfully.
    #
    # Items: the command's items from $args. Raw: the same arguments as the process received them,
    # when it was started with -File (Get-HordeFileModeArguments), else $null.
    param($Items, $Raw)
    $named = @{}
    $positional = @()
    $items = @($Items)
    $fail = { param($m) return [pscustomobject]@{ named = @{}; positional = @(); problem = $m } }

    if ($null -eq $Raw) {
        for ($j = 0; $j -lt $items.Count; $j++) {
            $pname = Get-HordeParameterName -Item $items[$j]
            if ($pname -and "$($items[$j])".EndsWith(":")) {
                if ($j + 1 -ge $items.Count) { return (& $fail ("parameter " + $items[$j] + " needs a value after the colon")) }
                if ($named.ContainsKey($pname)) { return (& $fail ("parameter -" + $pname + " is given more than once")) }
                $named[$pname] = $items[$j + 1]
                $j++
                continue
            }
            $positional += $items[$j]
        }
        return [pscustomobject]@{ named = $named; positional = $positional; problem = $null }
    }

    # From a script: walk the raw arguments and $args together. A raw "-Name:value" arrives as two
    # items - the parameter, then the value - and is joined; every other raw argument is one item.
    # A raw "-Name:" with nothing after the colon arrived as a bare -Name, or as nothing at all,
    # depending on its position (measured), so it is refused rather than guessed at.
    $j = 0
    foreach ($r in @($Raw)) {
        if ($r -match '\A-([^:]+):(.*)\z') {
            $pname = $Matches[1]; $value = $Matches[2]
            if ($value -eq "") { return (& $fail ("parameter " + $r + " needs a value after the colon")) }
            if ($j + 1 -lt $items.Count -and (Get-HordeParameterName -Item $items[$j]) -ceq $pname -and "$($items[$j + 1])" -ceq $value) {
                if ($named.ContainsKey($pname)) { return (& $fail ("parameter -" + $pname + " is given more than once")) }
                $named[$pname] = ConvertFrom-HordeFileModeValue -Text $value
                $j += 2
                continue
            }
        }
        if ($j -ge $items.Count) { $j = -1; break }
        $positional += $items[$j]
        $j++
    }
    if ($j -ne $items.Count) {
        return (& $fail ("could not match the command line to the arguments PowerShell delivered (" + @($Raw).Count + " given, " + $items.Count + " delivered)"))
    }
    return [pscustomobject]@{ named = $named; positional = $positional; problem = $null }
}
