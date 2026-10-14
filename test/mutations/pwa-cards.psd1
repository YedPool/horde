# Mutations of the phone's side of the cards (relay/js/protocol.js, the cards channel section): reading a
# snapshot, merging machines by name, and the lane filter a card's stream uses. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-cards.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its units.mjs, section 10e). Every find string
# occurs exactly once.
@{
    Target = "relay\js\protocol.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "area-wins-over-the-entrys-own-lane"
           Find = 'if (own.length) return own;'
           Replace = 'if (own.length && !(areas || []).length) return own;' }
        @{ Name = "only-the-first-of-two-lanes-is-kept"
           Find = 'const own = String(entry && entry.lane || "").split(",").map((x) => x.trim()).filter((x) => x);'
           Replace = 'const own = String(entry && entry.lane || "").split(",").map((x) => x.trim()).filter((x) => x).slice(0, 1);' }
        @{ Name = "an-unmapped-entry-shows-in-every-lane"
           Find = 'for (const a of areas || []) if (a.area.trim().toLowerCase() === area) return a.lanes.slice();'
           Replace = 'for (const a of areas || []) if (a.area.trim().toLowerCase() === area) return a.lanes.slice(); if (area) return ["B", "C", "E", "F", "G"];' }
        @{ Name = "area-compared-with-case"
           Find = 'const area = String(entry && entry.area || "").trim().toLowerCase();'
           Replace = 'const area = String(entry && entry.area || "");' }
        @{ Name = "the-thrall-stream-is-filtered"
           Find = 'if (!lane) return items.slice();'
           Replace = 'if (!lane) return items.filter((it) => entryLanes(it, areas).length > 0);' }
        @{ Name = "machines-not-merged-by-name"
           Find = 'const had = byName.get(s.value.name);'
           Replace = 'const had = byName.get(s.value.name + "/" + s.entry);' }
        @{ Name = "older-snapshot-of-a-name-wins"
           Find = 'if (!had || s.value.made > had.value.made || (s.value.made === had.value.made && s.seq > had.seq)) byName.set(s.value.name, s);'
           Replace = 'if (!had) byName.set(s.value.name, s);' }
        @{ Name = "cards-of-another-machine-read"
           Find = 'if (b.horde !== horde || b.machine !== machine) return no("the cards body names another horde or machine");'
           Replace = '' }
        @{ Name = "a-bad-lane-id-shown"
           Find = 'if (!c || typeof c !== "object" || typeof c.lane !== "string" || !CARD_LANE.test(c.lane) || CARD_FORMS.indexOf(c.form) < 0 || lanesSeen.has(c.lane)) { dropped++; continue; }'
           Replace = 'if (!c || typeof c !== "object" || lanesSeen.has(c.lane)) { dropped++; continue; }' }
        @{ Name = "the-machines-note-words-shown"
           Find = 'blockedText: cardText(c.blockedText), note: cardFormNote(c.form, cardText(c.problems)),'
           Replace = 'blockedText: cardText(c.blockedText), note: cardText(c.note) || cardFormNote(c.form, cardText(c.problems)),' }
        @{ Name = "the-broken-rules-not-said"
           Find = 'if (form === "other" && problems) return'
           Replace = 'if (false) return' }
        @{ Name = "a-control-character-shown"
           Find = 'const cardText = (v) => (typeof v === "string" && v.length <= CARD_TEXT && PLAIN.test(v) ? v : "");'
           Replace = 'const cardText = (v) => (typeof v === "string" ? v : "");' }
        @{ Name = "the-stream-limit-not-said"
           Find = 'export const STREAM_LIMIT_WORDS = "This phone holds only the newest part of the progress log (its last 100 sends), so a quiet lane may show few of its older updates here.";'
           Replace = 'export const STREAM_LIMIT_WORDS = "";' }
        @{ Name = "a-lane-card-may-be-the-thralls"
           Find = 'const lanesSeen = new Set(["thrall"]);'
           Replace = 'const lanesSeen = new Set();' }
        @{ Name = "two-cards-of-one-id-both-kept"
           Find = '    lanesSeen.add(c.lane);'
           Replace = '' }
        @{ Name = "areas-left-out-not-read"
           Find = 'areasLeftOut: cardCount(b.areasLeftOut) || 0, dropped } };'
           Replace = 'areasLeftOut: 0, dropped } };' }
        @{ Name = "areas-left-out-not-carried-per-machine"
           Find = 'cardsLeftOut: s.value.cardsLeftOut, areasLeftOut: s.value.areasLeftOut || 0 });'
           Replace = 'cardsLeftOut: s.value.cardsLeftOut, areasLeftOut: 0 });' }
        @{ Name = "the-place-moves-in-a-lanes-stream"
           Find = 'return !!stream && stream.lane === "" && stream.entry === picked;'
           Replace = 'return !!stream && stream.entry === picked;' }
        @{ Name = "the-place-moves-in-another-pairings-log"
           Find = 'return !!stream && stream.lane === "" && stream.entry === picked;'
           Replace = 'return !!stream && stream.lane === "";' }
    )
}
