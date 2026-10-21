# Mutations of the fleet meter's collector (fleet-metrics/collect.mjs): the per-file catch that keeps one
# bad file from stopping the pass, the offset rules, and the backfill bounds. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-meter-collect.psd1
# test\test-fleet-meter.ps1 (the meter's node tests, on synthetic transcripts) must fail for every one.
# Every find string occurs once.
@{
    Target = "fleet-metrics\collect.mjs"
    Suite  = "test\test-fleet-meter.ps1"
    Mutations = @(
        @{ Name = "a-bad-file-stops-the-pass"
           Find = 'failures.push({ file: todo[i].file, message: e && e.message ? e.message : String(e) });'
           Replace = 'throw e;' }
        @{ Name = "a-bad-file-not-counted"
           Find = 'errors: failures.length, failures };'
           Replace = 'errors: 0, failures };' }
        @{ Name = "rewrite-at-equal-size-not-noticed"
           Find = ' && headOf(fd, headLen) === wantHead) offset = prev.offset;'
           Replace = ') offset = prev.offset;' }
        @{ Name = "shrunk-file-not-reread"
           Find = 'st.size >= prev.offset && Number.isFinite(headLen)'
           Replace = 'Number.isFinite(headLen)' }
        @{ Name = "partial-line-consumed"
           Find = 'const next = offset + nl + 1;'
           Replace = 'const next = offset + buf.length;' }
        @{ Name = "old-files-not-skipped"
           Find = 'if (st.mtimeMs < cutoff) { skippedOld++; continue; }'
           Replace = '' }
        @{ Name = "time-budget-ignored"
           Find = 'if (clock() - t0 >= maxMs) { left = todo.length - i; break; }'
           Replace = '' }
        @{ Name = "default-window-sixty-days"
           Find = 'export const DEFAULT_SINCE_DAYS = 14;'
           Replace = 'export const DEFAULT_SINCE_DAYS = 60;' }
        @{ Name = "reader-skips-not-added-up"
           Find = 'acc.skipped += batch.skipped || 0;'
           Replace = '' }
    )
}
