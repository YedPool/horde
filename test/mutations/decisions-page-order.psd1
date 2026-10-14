# Mutations of decisions/page/list.js's ONE SORTING of the founder's list (THE ORDER IS HIS): by date,
# by task importance, by how much a question blocks. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-page-order.psd1
# test\test-decisions-page-order.ps1 must fail for each: it runs the sorting without a page, in
# seconds, and holds the words the page sorts by to decisions/Rules.ps1's own. What the page DRAWS in
# that order is test\mutations\decisions-page-answered.psd1, whose suite is a real window.
@{
    Target = "decisions\page\list.js"
    Suite  = "test\test-decisions-page-order.ps1"
    Mutations = @(
        @{ Name = "the-oldest-question-first"
           Find = '  function newestFirst(a, b) { return (askedAt(b) - askedAt(a)) || (numberOf(b) - numberOf(a)); }'
           Replace = '  function newestFirst(a, b) { return (askedAt(a) - askedAt(b)) || (numberOf(b) - numberOf(a)); }' }
        @{ Name = "asked-in-one-instant-the-lower-number-first"
           Find = '  function newestFirst(a, b) { return (askedAt(b) - askedAt(a)) || (numberOf(b) - numberOf(a)); }'
           Replace = '  function newestFirst(a, b) { return (askedAt(b) - askedAt(a)) || (numberOf(a) - numberOf(b)); }' }
        @{ Name = "the-time-is-not-compared-at-all"
           Find = '  function newestFirst(a, b) { return (askedAt(b) - askedAt(a)) || (numberOf(b) - numberOf(a)); }'
           Replace = '  function newestFirst(a, b) { return (numberOf(b) - numberOf(a)); }' }
        @{ Name = "a-question-with-no-time-stands-first"
           Find = '  function timeOf(text) { var t = Date.parse(textOf(text)); return isNaN(t) ? 0 : t; }'
           Replace = '  function timeOf(text) { var t = Date.parse(textOf(text)); return isNaN(t) ? 8640000000000000 : t; }' }
        @{ Name = "times-compared-as-text"
           Find = '  function timeOf(text) { var t = Date.parse(textOf(text)); return isNaN(t) ? 0 : t; }'
           Replace = '  function timeOf(text) { var t = Number(textOf(text).replace(/[^0-9]/g, "").slice(0, 15)); return isNaN(t) ? 0 : t; }' }
        # NEWEST IS LAST ASKED (list.js): the date order sorts by lastAskedAt, an older list by addedAt.
        @{ Name = "the-date-order-ignores-when-it-was-last-asked"
           Find = '  function askedAt(q) { return timeOf(q.lastAskedAt) || timeOf(q.addedAt); }'
           Replace = '  function askedAt(q) { return timeOf(q.addedAt); }' }
        @{ Name = "a-list-from-an-earlier-version-has-no-time-at-all"
           Find = '  function askedAt(q) { return timeOf(q.lastAskedAt) || timeOf(q.addedAt); }'
           Replace = '  function askedAt(q) { return timeOf(q.lastAskedAt); }' }
        @{ Name = "first-asked-is-the-last-asking"
           Find = '    return (first && timeOf(first.at)) || timeOf(q.addedAt);'
           Replace = '    return askedAt(q);' }
        @{ Name = "first-asked-from-an-earlier-list-is-no-time"
           Find = '    return (first && timeOf(first.at)) || timeOf(q.addedAt);'
           Replace = '    return (first && timeOf(first.at)) || 0;' }
        @{ Name = "a-moment-in-words-always-says-its-year"
           Find = '    var year = d.getFullYear() === new Date(now || Date.now()).getFullYear() ? "" : " " + d.getFullYear();'
           Replace = '    var year = " " + d.getFullYear();' }
        @{ Name = "task-importance-sorts-by-date"
           Find = '    if (key === "importance") { return function (a, b) {'
           Replace = '    if (key === "importance-never") { return function (a, b) {' }
        @{ Name = "blocking-sorts-by-date"
           Find = '    if (key === "blocks") { return function (a, b) {'
           Replace = '    if (key === "blocks-never") { return function (a, b) {' }
        @{ Name = "blocking-sorts-by-the-importances-words"
           Find = 'return way * (placeIn(BLOCKINGS, a.blocks, DEFAULT_BLOCKS) - placeIn(BLOCKINGS, b.blocks, DEFAULT_BLOCKS)) || newestFirst(a, b); }; }'
           Replace = 'return way * (placeIn(IMPORTANCES, a.blocks, DEFAULT_IMPORTANCE) - placeIn(IMPORTANCES, b.blocks, DEFAULT_IMPORTANCE)) || newestFirst(a, b); }; }' }
        @{ Name = "task-importance-sorts-by-the-blocking"
           Find = 'return way * (placeIn(IMPORTANCES, a.importance, DEFAULT_IMPORTANCE) - placeIn(IMPORTANCES, b.importance, DEFAULT_IMPORTANCE)) || newestFirst(a, b); }; }'
           Replace = 'return way * (placeIn(BLOCKINGS, a.blocks, DEFAULT_BLOCKS) - placeIn(BLOCKINGS, b.blocks, DEFAULT_BLOCKS)) || newestFirst(a, b); }; }' }
        @{ Name = "a-tie-in-importance-is-left-as-it-came"
           Find = 'placeIn(IMPORTANCES, b.importance, DEFAULT_IMPORTANCE)) || newestFirst(a, b); }; }'
           Replace = 'placeIn(IMPORTANCES, b.importance, DEFAULT_IMPORTANCE)); }; }' }
        @{ Name = "a-tie-in-blocking-is-left-as-it-came"
           Find = 'placeIn(BLOCKINGS, b.blocks, DEFAULT_BLOCKS)) || newestFirst(a, b); }; }'
           Replace = 'placeIn(BLOCKINGS, b.blocks, DEFAULT_BLOCKS)); }; }' }
        @{ Name = "a-word-the-page-does-not-know-stands-first"
           Find = '    return at >= 0 ? at : words.indexOf(fallback);'
           Replace = '    return at >= 0 ? at : -1;' }
        @{ Name = "a-word-the-page-does-not-know-stands-last"
           Find = '    return at >= 0 ? at : words.indexOf(fallback);'
           Replace = '    return at >= 0 ? at : words.length;' }
        @{ Name = "the-importances-in-another-order"
           Find = '  var IMPORTANCES = ["high", "normal", "low"];'
           Replace = '  var IMPORTANCES = ["low", "normal", "high"];' }
        @{ Name = "the-blockings-in-another-order"
           Find = '  var BLOCKINGS = ["all", "part", "none"];'
           Replace = '  var BLOCKINGS = ["none", "part", "all"];' }
        @{ Name = "a-question-with-no-importance-reads-as-high"
           Find = '  var DEFAULT_IMPORTANCE = "normal";'
           Replace = '  var DEFAULT_IMPORTANCE = "high";' }
        @{ Name = "a-question-with-no-blocking-reads-as-all"
           Find = '  var DEFAULT_BLOCKS = "part";'
           Replace = '  var DEFAULT_BLOCKS = "all";' }
        @{ Name = "the-order-he-gets-before-he-chooses-is-importance"
           Find = '  var DEFAULT_ORDER = "date";'
           Replace = '  var DEFAULT_ORDER = "importance";' }
        @{ Name = "the-list-handed-in-is-sorted-in-place"
           Find = '  function inOrder(list, key, turned) { return listOf(list).slice().sort(compareBy(orderOf(key), turned === true)); }'
           Replace = '  function inOrder(list, key, turned) { return listOf(list).sort(compareBy(orderOf(key), turned === true)); }' }
        @{ Name = "what-is-not-a-list-is-sorted"
           Find = '  function inOrder(list, key, turned) { return listOf(list).slice().sort(compareBy(orderOf(key), turned === true)); }'
           Replace = '  function inOrder(list, key, turned) { return list.slice().sort(compareBy(orderOf(key), turned === true)); }' }
        @{ Name = "the-sorting-is-not-handed-out"
           Find = 'order: { orders: ORDERS.map(function (o) { return o.key; }), inOrder: inOrder }, asked:'
           Replace = 'order: { orders: ORDERS.map(function (o) { return o.key; }) }, asked:' }
        @{ Name = "turned-over-is-never-turned"
           Find = '    var way = turned === true ? -1 : 1;'
           Replace = '    var way = 1;' }
        @{ Name = "anything-truthy-turns-it-over"
           Find = 'sort(compareBy(orderOf(key), turned === true)); }'
           Replace = 'sort(compareBy(orderOf(key), !!turned)); }' }
        @{ Name = "turned-over-the-ties-turn-too"
           Find = 'placeIn(IMPORTANCES, b.importance, DEFAULT_IMPORTANCE)) || newestFirst(a, b); }; }'
           Replace = 'placeIn(IMPORTANCES, b.importance, DEFAULT_IMPORTANCE)) || way * newestFirst(a, b); }; }' }
        @{ Name = "the-date-never-turns-over"
           Find = '    return function (a, b) { return way * newestFirst(a, b); };'
           Replace = '    return newestFirst;' }
        @{ Name = "the-turn-is-not-handed-to-the-sort"
           Find = 'sort(compareBy(orderOf(key), turned === true)); }'
           Replace = 'sort(compareBy(orderOf(key), false)); }' }
        @{ Name = "a-question-with-no-number-is-NaN-again"
           Find = '  function numberOf(q) { var n = Number(q.number); return isNaN(n) ? 0 : n; }'
           Replace = '  function numberOf(q) { return Number(q.number); }' }
    )
}
