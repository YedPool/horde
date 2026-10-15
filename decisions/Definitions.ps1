# decisions/Definitions.ps1 - the decisions module's tables, read from disk once.
#
# THE ONE JOB of this file is to read the definitions everything else is handed: the four schemas
# (schema/decision-*.v1.json) and the table of question kinds (decisions/question-kinds.json). The
# rules (decisions/Rules.ps1) open no file, so they are given these; the operations and every way of
# showing a question read the same object, so there is one definition of each thing.
#
# THE KIND TABLE IS DATA, NOT CODE, so that a page in a window can read the very file the command line
# reads. A new kind of question is one entry in it: its label (how a list names it), what it means in
# a sentence, and which list of a question it needs - options, parts, or none.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")

$script:HordeDecisionDefinitions = $null
# The lists of a question that a kind may need. "" is none.
$script:HordeDecisionKindLists = @("", "options", "parts")

function Read-HordeDecisionKinds {
    # The question-kind table from -Path, checked: a table with a kind that has no label, or that
    # needs a list no question has, would be shown wrongly everywhere at once, so it is refused here.
    param([Parameter(Mandatory = $true)][string]$Path)
    $table = (ConvertFrom-HordeJson ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)))
    $kindsProp = $table.PSObject.Properties["kinds"]
    $versionProp = $table.PSObject.Properties["schemaVersion"]
    if ($null -eq $versionProp -or $versionProp.Value -ne 1 -or $null -eq $kindsProp -or $kindsProp.Value -isnot [System.Management.Automation.PSCustomObject]) {
        throw ("'" + $Path + "' is not a question-kind table this version reads: it needs schemaVersion 1 and a kinds object")
    }
    $names = @($kindsProp.Value.PSObject.Properties | ForEach-Object { $_.Name })
    if ($names.Count -eq 0) { throw ("'" + $Path + "' names no kind of question") }
    foreach ($name in $names) {
        if ($name -cnotmatch '\A[a-z][a-z-]{0,31}\z') { throw ("the question kind '" + $name + "' is not lowercase letters and hyphens") }
        $entry = $kindsProp.Value.PSObject.Properties[$name].Value
        foreach ($member in @("label", "means", "list")) {
            $p = $null
            if ($entry -is [System.Management.Automation.PSCustomObject]) { $p = $entry.PSObject.Properties[$member] }
            if ($null -eq $p -or $p.Value -isnot [string]) { throw ("the question kind '" + $name + "' has no '" + $member + "' text") }
        }
        if ("$($entry.label)".Trim() -eq "" -or "$($entry.means)".Trim() -eq "") { throw ("the question kind '" + $name + "' has a blank label or meaning") }
        if ($script:HordeDecisionKindLists -cnotcontains $entry.list) { throw ("the question kind '" + $name + "' needs the list '" + $entry.list + "', and a question has only options and parts") }
    }
    return $kindsProp.Value
}

function Get-HordeDecisionDefinitions {
    # { eventSchema; questionSchema; requestSchema; resultSchema; kinds }, read once for the process.
    # Get-HordeSchema checks each schema as it reads it (core/Schema.ps1), so a bad schema file fails
    # here, at the first operation, and not at the first value that reaches the broken part.
    if ($null -ne $script:HordeDecisionDefinitions) { return $script:HordeDecisionDefinitions }
    $script:HordeDecisionDefinitions = [pscustomobject]@{
        eventSchema = (Get-HordeSchema -Name "decision-event.v1")
        questionSchema = (Get-HordeSchema -Name "decision-question.v1")
        requestSchema = (Get-HordeSchema -Name "decision-request.v1")
        resultSchema = (Get-HordeSchema -Name "decision-result.v1")
        kinds = (Read-HordeDecisionKinds -Path (Join-Path $PSScriptRoot "question-kinds.json"))
    }
    return $script:HordeDecisionDefinitions
}
