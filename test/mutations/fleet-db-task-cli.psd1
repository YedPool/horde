# Mutations of the task list verb (fleet-db/task-cli.mjs): every live task shown, nothing written, exit codes. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-task-cli.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/task-cli.test.mjs). Every find string occurs once.
@{
    Target = "fleet-db\task-cli.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "owned-elsewhere-left-out"
           Find = "WHERE ?1 IS NULL OR t.owner_orc_id = ?1 OR n.owner_orc_id = ?1"
           Replace = "WHERE ?1 IS NULL OR t.owner_orc_id = ?1" }
        @{ Name = "orc-own-list-left-out"
           Find = "WHERE ?1 IS NULL OR t.owner_orc_id = ?1 OR n.owner_orc_id = ?1"
           Replace = "WHERE ?1 IS NULL OR n.owner_orc_id = ?1" }
        @{ Name = "orc-shows-everything"
           Find = "WHERE ?1 IS NULL OR t.owner_orc_id = ?1 OR n.owner_orc_id = ?1"
           Replace = "WHERE ?1 IS NULL OR 1" }
        @{ Name = "no-orc-tasks-hidden"
           Find = "FROM task_tree t JOIN task_now n ON n.id = t.id"
           Replace = "FROM task_tree t JOIN task_now n ON n.id = t.id AND t.owner_orc_id IS NOT NULL" }
        @{ Name = "no-orc-list-first"
           Find = "ORDER BY l.letter IS NULL, l.letter, t.sort"
           Replace = "ORDER BY l.letter IS NOT NULL, l.letter, t.sort" }
        @{ Name = "sort-ignored"
           Find = "ORDER BY l.letter IS NULL, l.letter, t.sort"
           Replace = "ORDER BY l.letter IS NULL, l.letter, t.key DESC" }
        @{ Name = "done-count-ignores-the-orc"
           Find = "WHERE state = 'done' AND (?1 IS NULL OR owner_orc_id = ?1)"
           Replace = "WHERE state = 'done' AND (?1 IS NULL OR 1)" }
        @{ Name = "verified-counted-as-done"
           Find = "WHERE state = 'done' AND (?1 IS NULL OR owner_orc_id = ?1)"
           Replace = "WHERE state IN ('done', 'verified') AND (?1 IS NULL OR owner_orc_id = ?1)" }
        @{ Name = "unknown-orc-shows-all"
           Find = "if (!o) throw refusal('no Orc is called ' + orc);"
           Replace = "if (!o) return { tasks: [], unverified: 0 };" }
        @{ Name = "lane-folder-not-taken"
           Find = "SELECT id FROM orc WHERE letter = ? OR lane_dir = ?"
           Replace = "SELECT id FROM orc WHERE letter = ? AND ? = ?1" }
        @{ Name = "owner-never-marked"
           Find = "if (r.owner !== r.list) words.push("
           Replace = "if (false) words.push(" }
        @{ Name = "no-indent"
           Find = "const indent = '  '.repeat(r.depth);"
           Replace = "const indent = '';" }
        @{ Name = "due-not-printed"
           Find = "if (r.due_at !== null) words.push("
           Replace = "if (false) words.push(" }
        @{ Name = "json-due-epoch-bad"
           Find = "due: r.due_at === null ? null : when(r.due_at)"
           Replace = "due: when(r.due_at)" }
        @{ Name = "impossible-due-throws"
           Find = "return Number.isNaN(d.getTime()) ? 'unreadable' : d.toISOString();"
           Replace = "return d.toISOString();" }
        @{ Name = "json-not-ascii"
           Find = "out(ascii(JSON.stringify({ tasks:"
           Replace = "out((JSON.stringify({ tasks:" }
        @{ Name = "title-not-ascii"
           Find = "out(ascii(line(r)));"
           Replace = "out(line(r));" }
        @{ Name = "list-name-every-row"
           Find = "if (name !== shown) {"
           Replace = "if (true) {" }
        @{ Name = "counts-line-gone"
           Find = "out(tasks.length + ' open, and ' + unverified + ' done, not yet verified, not listed');"
           Replace = "" }
        @{ Name = "opens-for-writing"
           Find = "db = openStore(file, { readOnly: true, busyMs });"
           Replace = "db = openStore(file, { busyMs });" }
        @{ Name = "makes-a-missing-file"
           Find = "if (!fs.existsSync(file)) { err('fleet.db does not exist yet (run horde db init)'); return 4; }"
           Replace = "" }
        @{ Name = "no-home-wrong-code"
           Find = "err('fleet.db: ' + ascii(e.message));"
           Replace = "err('fleet.db: ' + ascii(e.message)); return 1;" }
        @{ Name = "unknown-flag-accepted"
           Find = "if (a !== '--orc' && a !== '--json') {"
           Replace = "if (false) {" }
        @{ Name = "flag-twice-accepted"
           Find = "if (a in flags) {"
           Replace = "if (false) {" }
        @{ Name = "orc-without-value-accepted"
           Find = "if (a === '--orc' && i + 1 >= argv.length) {"
           Replace = "if (false) {" }
        @{ Name = "other-verb-accepted"
           Find = "if (argv[0] !== 'list') {"
           Replace = "if (false) {" }
        @{ Name = "busy-not-told-apart"
           Find = "if (isBusy(e)) { err('fleet.db busy'); return 3; }"
           Replace = "" }
        @{ Name = "refusal-loses-its-word"
           Find = "if (e.refusal) { err('refused: ' + ascii(e.message)); return 1; }"
           Replace = "" }
        @{ Name = "older-file-says-open-for-writing"
           Find = ".replace('open it for writing once', 'run horde db init')"
           Replace = "" }
    )
}
