# A class method is not a command: Compare below is a method, and must not be counted with the
# top-level function of the same name in this file.
class FixtureSorter {
    [int] Compare([object]$a, [object]$b) { return 0 }
}

function Compare { "the real one" }
