# Mutations of decisions/Operations.ps1, the one API of the decisions list. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-operations.psd1
# Each removes one thing a caller relies on; test\test-decisions-operations.ps1 must fail for every
# one, except those declared Expect = "survives".
@{
    Target = "decisions\Operations.ps1"
    Suite  = "test\test-decisions-operations.ps1"
    Mutations = @(
        # --- kinds: the table, from the operations, with no store ---
        @{ Name = "kinds-waits-on-the-store"
           Find = 'if ($entry.ContainsKey("noStore")) { return (& $entry.read $plain $null $definitions $Now) }'
           Replace = '' }
        @{ Name = "kinds-answers-without-the-table"
           Find = '-More ([ordered]@{ kinds = $Definitions.kinds })'
           Replace = '-More ([ordered]@{ kinds = [pscustomobject]@{} })' }
        # --- list: the listed states in any case, and nothing else ---
        @{ Name = "state-in-capitals-refused"
           Find = '$want = ([string]$Request.state).ToLowerInvariant() }'
           Replace = '$want = [string]$Request.state }' }
        @{ Name = "refused-state-repeated-whatever-it-is"
           Find = 'if ($want -cmatch ''\A[a-z][a-z-]{0,31}\z'') { $named ='
           Replace = 'if ($true) { $named =' }
        # --- a write's wait on a held record has an end ---
        # How long is the setting decisions.write.heldReads: its default's mutants are in
        # test\mutations\decisions-settings-write.psd1. Here, that the setting is what is counted to.
        @{ Name = "held-record-given-up-on-at-the-first-read"
           Find = 'if ($busyReads -ge $heldReads) {'
           Replace = 'if ($busyReads -ge 1) {' }
        @{ Name = "held-record-written-past"
           Find = 'if ($null -ne $read.busy) {'
           Replace = 'if ($false) {' }
        # --- a stray file in the store is named in every result ---
        @{ Name = "stray-files-not-named"
           Find = 'foreach ($stray in @($loaded.strays)) { [void]$list.strays.Add($stray) }'
           Replace = '' }
        # --- a number no question can have is answered, never cast ---
        @{ Name = "huge-request-number-cast"
           Find = 'if ((Test-HordeDecisionMember -Object $plain -Name "number") -and -not (Test-HordeDecisionCount -Value $plain.number -Most (Get-HordeDecisionMaxNumber))) {'
           Replace = 'if ($false) {' }
        # --- a request is checked before anything is read ---
        @{ Name = "secrets-not-looked-for"
           Find = 'if ($secrets.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "request-shape-not-checked"
           Find = 'if ($shape.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "question-shape-not-checked"
           Find = 'if ($bad.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "role-not-checked-by-name"
           Find = 'if (@($allowed.roles) -cnotcontains $actor) {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-operation-runs"
           Find = 'if ($Operation -cmatch ''\A[a-z][a-z-]{0,31}\z'') { $entry = $script:HordeDecisionOperations[$Operation] }'
           Replace = '$entry = $script:HordeDecisionOperations["list"]' }
        # --- one id, one record ---
        @{ Name = "repost-written-again"
           Find = 'if ($list.ids.ContainsKey($id)) {'
           Replace = 'if ($false) {' }
        @{ Name = "reused-id-replayed"
           Find = 'if ($requestHash -ne "" -and $prior.requestHash -ceq $requestHash) {'
           Replace = 'if ($requestHash -ne "") {' }
        @{ Name = "hash-ignores-the-operation"
           Find = '$hashed = [ordered]@{ operation = $Operation; actor = $actor; number = $number; body = $sameness }'
           Replace = '$hashed = [ordered]@{ actor = $actor; number = $number; body = $sameness }'
           Expect = "survives"
           Reason = "the four writes have bodies of four different shapes (question, changes, outcome, reason), so no two operations can hash alike today; the operation is hashed so that a later operation with the same body as an existing one cannot replay it" }
        @{ Name = "hash-ignores-the-question"
           Find = '$hashed = [ordered]@{ operation = $Operation; actor = $actor; number = $number; body = $sameness }'
           Replace = '$hashed = [ordered]@{ operation = $Operation; actor = $actor; number = $number }' }
        # --- what must not be written ---
        @{ Name = "rules-not-applied"
           Find = 'if (@($content.findings).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "changed-question-not-judged"
           Find = 'if ($Operation -ceq "update") {'
           Replace = 'if ($false) {' }
        @{ Name = "record-that-does-not-apply-is-written"
           Find = 'if ($why -ne "") { return (& $refuse ("nothing was written: " + $why) @($why) $before) }'
           Replace = '' }
        @{ Name = "empty-change-not-named"
           Find = 'if ($fields.Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "outcome-not-checked"
           Find = 'findings = @(Test-HordeDecisionNote -Text ([string]$Request.outcome) -Name "outcome") }'
           Replace = 'findings = @() }' }
        @{ Name = "reason-may-have-lines"
           Find = 'findings = @(Test-HordeDecisionNote -Text ([string]$Request.reason) -Name "reason" -OneLine) }'
           Replace = 'findings = @(Test-HordeDecisionNote -Text ([string]$Request.reason) -Name "reason") }' }
        # --- a number is permanent ---
        @{ Name = "number-counted-from-the-questions-shown"
           Find = '$data["number"] = Get-HordeDecisionNextNumber -State $list }'
           Replace = '$data["number"] = $list.questions.Count + 1 }' }
        @{ Name = "missing-number-written-to"
           Find = 'if ($null -ne $not) { return $not }'
           Replace = '' }
        @{ Name = "unreadable-question-reads-as-absent"
           Find = 'if ($status -eq "unreadable") {'
           Replace = 'if ($false) {' }
        @{ Name = "show-of-a-missing-number-throws"
           Find = 'if ($null -ne $missing) { return $missing }'
           Replace = '' }
        # --- several writers ---
        @{ Name = "lost-sequence-number-reported-as-written"
           Find = 'if ($made -cne "created") { continue }'
           Replace = '' }
        @{ Name = "unconfirmed-record-reported-as-saved"
           Find = 'if ($made -ceq "unconfirmed") {'
           Replace = 'if ($false) {' }
        @{ Name = "repost-answered-without-confirming-the-record"
           Find = 'if ($sure -cne "confirmed") {'
           Replace = 'if ($false) {' }
        @{ Name = "repost-confirmed-without-asking-the-store"
           Find = 'try { $sure = Confirm-HordeDecisionRecord -Root $Root -Sequence ([long]$prior.sequence) } catch { $sure = "unconfirmed" }'
           Replace = '$sure = "confirmed"' }
        @{ Name = "operation-goes-ahead-on-refused-settings"
           Find = '    if ($unfit -ne "") { return (New-HordeUnknown -Reason $unfit) }'
           Replace = '' }
        @{ Name = "sequence-not-from-the-list-read"
           Find = '$sequence = [long]$list.lastSequence + 1'
           Replace = '$sequence = [long]$list.lastSequence + 2' }
        @{ Name = "one-try-only"
           Find = 'for ($attempt = 1; $attempt -le $raceTries; $attempt++) {'
           Replace = 'for ($attempt = 1; $attempt -le 1; $attempt++) {' }
        # --- what a result holds ---
        @{ Name = "unreadable-records-left-out-of-results"
           Find = '$value["unreadable"] = $unreadable'
           Replace = '$value["unreadable"] = @()' }
        @{ Name = "refusal-blames-the-unwritten-record"
           Find = '$before = [pscustomobject]@{ unreadable = @($list.unreadable); ignored = @($list.ignored); strays = @($list.strays); notUnderstood = $list.notUnderstood }'
           Replace = '$before = $list' }
        @{ Name = "write-failure-reads-as-refused"
           Find = 'catch { return (New-HordeUnknown -Reason ("record " + $sequence + " could not be written, so nothing changed") -ErrorRecord $_) }'
           Replace = 'catch { return (& $refuse "it could not be written" @("it could not be written") $before) }' }
        @{ Name = "result-not-checked-against-its-schema"
           Find = 'if ($off.Count -gt 0) {'
           Replace = 'if ($false) {'
           Expect = "survives"
           Reason = "the check only fires on a result this module built wrongly, and no test can make it build one without changing the module; the suite holds every result to the schema itself, in Invoke-Op" }
        # --- list ---
        @{ Name = "list-shows-every-state-by-default"
           Find = '$want = "open"'
           Replace = '$want = "all"' }
        @{ Name = "unknown-state-lists-nothing"
           Find = 'if ($want -cne "all" -and $states -cnotcontains $want) {'
           Replace = 'if ($false) {' }
        @{ Name = "state-filter-ignored"
           Find = 'if ($want -ceq "all" -or "$($question.state)" -ceq $want) {'
           Replace = 'if ($true) {' }
        @{ Name = "counts-follow-the-filter"
           Find = 'if ($counts.Contains("$($question.state)")) { $counts["$($question.state)"] = [int]$counts["$($question.state)"] + 1 }'
           Replace = 'if ($counts.Contains("$($question.state)") -and "$($question.state)" -ceq $want) { $counts["$($question.state)"] = [int]$counts["$($question.state)"] + 1 }' }
        # --- where the store is ---
        @{ Name = "store-in-another-folder"
           Find = 'return (Join-Path (Join-Path (Get-HordeHome) "store") "decisions")'
           Replace = 'return (Join-Path (Join-Path (Get-HordeHome) "store") "decision")' }
        @{ Name = "home-error-thrown-at-the-caller"
           Find = 'catch { return (New-HordeUnknown -Reason "the decisions store could not be found" -ErrorRecord $_) }'
           Replace = 'catch { throw }' }
        # --- records of a later kind are in every result, once for each kind ---
        @{ Name = "later-kinds-left-out-of-results"
           Find = '$value["notUnderstood"] = $later'
           Replace = '$value["notUnderstood"] = @()' }
        @{ Name = "later-kinds-left-out-of-a-refusal"
           Find = 'strays = @($list.strays); notUnderstood = $list.notUnderstood }'
           Replace = 'strays = @($list.strays); notUnderstood = (New-Object System.Collections.Specialized.OrderedDictionary) }' }
        @{ Name = "set-aside-records-not-named-when-a-number-cannot-be-read"
           Find = ' + @($State.notUnderstood.Values | ForEach-Object {'
           Replace = ' + @(@() | ForEach-Object {' }
    )
}
