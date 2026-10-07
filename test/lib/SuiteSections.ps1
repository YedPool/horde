# test/lib/SuiteSections.ps1 - what sections a suite declares, read from its text, and whether a
# mutant's section map names only those. One rule for both readers: tools\Mutate.ps1 refuses a wrong
# map before it runs anything, and test\test-mutation-specs.ps1 checks every spec's map on every gate
# run without running a suite.
#
# WHY READ THE TEXT AND NOT RUN THE SUITE. A suite run costs seconds to minutes; the declaration is one
# literal list (test\lib\Suite.ps1, Register-HordeSuiteSections), so the syntax tree answers exactly.
# A list built at run time - a variable, a call, an expandable string - cannot be read this way, and is
# refused rather than guessed at.
#
# WHY A WRONG MAP MUST BE REFUSED AND NOT JUST RUN. A suite given a section it does not have fails the
# run with an [ERROR]; that is not a catch, so the mutant would read "the suite broke" and the spec would
# fail for a reason that hides the real one. And an EMPTY map would leave HORDE_SECTIONS empty, which a
# suite reads as "every section" - a whole run that looks like a mapped one.

function Get-HordeSuiteSectionIds {
    # The section ids a suite file declares: { ok; ids; error }. ok is false when the file declares none,
    # declares them more than once, or builds the list at run time.
    param([string]$Path)
    $tk = $null; $pe = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tk, [ref]$pe)
    $calls = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq "Register-HordeSuiteSections" }, $true))
    if ($calls.Count -eq 0) { return [pscustomobject]@{ ok = $false; ids = @(); error = "declares no sections" } }
    if ($calls.Count -gt 1) { return [pscustomobject]@{ ok = $false; ids = @(); error = ("declares its sections " + $calls.Count + " times, not once") } }
    $els = @($calls[0].CommandElements)
    $arg = $null
    for ($i = 1; $i -lt $els.Count; $i++) {
        if ($els[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and $els[$i].ParameterName -eq "Ids" -and ($i + 1) -lt $els.Count) { $arg = $els[$i + 1]; break }
    }
    if ($null -eq $arg) { return [pscustomobject]@{ ok = $false; ids = @(); error = "declares its sections without -Ids" } }
    # Only string constants: anything computed is refused, since its value is not in the text.
    $computed = @($arg.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] -or $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -or $n -is [System.Management.Automation.Language.CommandAst] -or $n -is [System.Management.Automation.Language.SubExpressionAst] }, $true))
    if ($computed.Count -gt 0) { return [pscustomobject]@{ ok = $false; ids = @(); error = "builds its section list at run time, so it cannot be read" } }
    $ids = @($arg.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { "$($_.Value)" })
    return [pscustomobject]@{ ok = $true; ids = $ids; error = "" }
}

function Get-HordeSectionTrapProblems {
    # Each section of a suite file without a trap line of its own, as "line N: section <id> ...". The
    # suite's trap resumes after the statement that failed, and a section is one statement, so without
    # its own trap one unexpected error skips every check left in the section (test\lib\Suite.ps1).
    param([string]$Path)
    $tk = $null; $pe = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tk, [ref]$pe)
    $out = New-Object System.Collections.ArrayList
    foreach ($if in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] }, $true))) {
        foreach ($clause in @($if.Clauses)) {
            $cond = $clause.Item1.Extent.Text
            if ($cond -notmatch '^\s*Enter-HordeSuiteSection\s+"([^"]*)"') { continue }
            $traps = @($clause.Item2.Traps | Where-Object { $null -ne $_ -and $_.Body.Extent.Text -match 'Register-HordeSuiteError' })
            if ($traps.Count -ne 1) { [void]$out.Add("line " + $clause.Item1.Extent.StartLineNumber + ": section " + $Matches[1] + " has " + $traps.Count + " trap lines of its own, not one") }
        }
    }
    return @($out)
}

function Get-HordeMutantSectionProblem {
    # Why a mutant's section map cannot run, or "" when it can. -Declared is Get-HordeSuiteSectionIds'
    # answer for the spec's suite; -Suite its path as the spec writes it, for the message. A spec whose
    # Environment already narrows its suite (HORDE_SECTIONS) may map a mutant only inside that filter:
    # the whole-suite rerun of a mutant that passes its sections runs the spec's filter, and a section
    # outside it would be one no whole run ever tries.
    param($Mutant, [string]$Suite, $Declared, $SpecEnvironment = $null)
    $names = @(@($Mutant.Sections) | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    if ($names.Count -eq 0) { return "its Sections names no section" }
    if (-not $Declared.ok) { return ("its suite " + $Suite + " " + $Declared.error) }
    foreach ($n in $names) {
        if ($Declared.ids -cnotcontains $n) { return ("section '" + $n + "' is not one " + $Suite + " declares") }
    }
    if ($SpecEnvironment -is [hashtable] -and $SpecEnvironment.ContainsKey("HORDE_SECTIONS")) {
        $filter = @("$($SpecEnvironment.HORDE_SECTIONS)" -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        foreach ($n in $names) {
            if ($filter -cnotcontains $n) { return ("section '" + $n + "' is outside the spec's own HORDE_SECTIONS (" + ($filter -join ",") + ")") }
        }
    }
    return ""
}
