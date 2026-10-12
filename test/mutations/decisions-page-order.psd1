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
           Find = '  function newestFirst(a, b) { return (askedAt(b) - askedAt(a)) || (Number(b.number) - Number(a.number)); }'
           Replace = '  function newestFirst(a, b) { return (askedAt(a) - askedAt(b)) || (Number(b.number) - Number(a.number)); }' }
        @{ Name = "asked-in-one-instant-the-lower-number-first"
           Find = '  function newestFirst(a, b) { return (askedAt(b) - askedAt(a)) || (Number(b.number) - Number(a.number)); }'
           Replace = '  function newestFirst(a, b) { return (askedAt(b) - askedAt(a)) || (Number(a.number) - Number(b.number)); }' }
        @{ Name = "the-time-is-not-compared-at-all"
           Find = '  function newestFirst(a, b) { return (askedAt(b) - askedAt(a)) || (Number(b.number) - Number(a.number)); }'
           Replace = '  function newestFirst(a, b) { return (Number(b.number) - Number(a.number)); }' }
        @{ Name = "a-question-with-no-time-stands-first"
           Find = '    return isNaN(t) ? 0 : t;'
           Replace = '    return isNaN(t) ? 8640000000000000 : t;' }
        @{ Name = "times-compared-as-text"
           Find = '    var t = Date.parse(textOf(q.addedAt));'
           Replace = '    var t = Number(textOf(q.addedAt).replace(/[^0-9]/g, "").slice(0, 15));' }
        @{ Name = "task-importance-sorts-by-date"
           Find = '    if (key === "importance") { return function (a, b) {'
           Replace = '    if (key === "importance-never") { return function (a, b) {' }
        @{ Name = "blocking-sorts-by-date"
           Find = '    if (key === "blocks") { return function (a, b) {'
           Replace = '    if (key === "blocks-never") { return function (a, b) {' }
        @{ Name = "blocking-sorts-by-the-importances-words"
           Find = 'return (placeIn(BLOCKINGS, a.blocks, DEFAULT_BLOCKS) - placeIn(BLOCKINGS, b.blocks, DEFAULT_BLOCKS)) || newestFirst(a, b); }; }'
           Replace = 'return (placeIn(IMPORTANCES, a.blocks, DEFAULT_IMPORTANCE) - placeIn(IMPORTANCES, b.blocks, DEFAULT_IMPORTANCE)) || newestFirst(a, b); }; }' }
        @{ Name = "task-importance-sorts-by-the-blocking"
           Find = 'return (placeIn(IMPORTANCES, a.importance, DEFAULT_IMPORTANCE) - placeIn(IMPORTANCES, b.importance, DEFAULT_IMPORTANCE)) || newestFirst(a, b); }; }'
           Replace = 'return (placeIn(BLOCKINGS, a.blocks, DEFAULT_BLOCKS) - placeIn(BLOCKINGS, b.blocks, DEFAULT_BLOCKS)) || newestFirst(a, b); }; }' }
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
           Find = '  function inOrder(list, key) { return listOf(list).slice().sort(compareBy(orderOf(key))); }'
           Replace = '  function inOrder(list, key) { return listOf(list).sort(compareBy(orderOf(key))); }' }
        @{ Name = "what-is-not-a-list-is-sorted"
           Find = '  function inOrder(list, key) { return listOf(list).slice().sort(compareBy(orderOf(key))); }'
           Replace = '  function inOrder(list, key) { return list.slice().sort(compareBy(orderOf(key))); }' }
        @{ Name = "the-sorting-is-not-handed-out"
           Find = 'order: { orders: ORDERS.map(function (o) { return o.key; }), inOrder: inOrder } };'
           Replace = 'order: { orders: ORDERS.map(function (o) { return o.key; }) } };' }
    )
}
