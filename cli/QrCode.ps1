# cli/QrCode.ps1 - a QR code (ISO/IEC 18004) from text, in plain PowerShell, and a PNG of it.
#
# WHY HERE AND WHY WRITTEN OUT. `horde relay pair` shows a pairing offer for the founder's phone to scan
# (relay/Pairing.ps1). Horde installs nothing it did not write (no package, no download), so the encoder
# is this file: byte mode only - the offer is printable ASCII - every version 1 to 40, the four error
# correction levels, and the eight masks chosen by the standard's penalty rules. It is the structure of
# Project Nayuki's public QR Code generator (MIT), re-derived from the standard: the tables, the
# Reed-Solomon code over GF(2^8) with the polynomial 0x11D, the format bits (BCH 15,5, mask 0x5412) and
# version bits (BCH 18,6), the placement order and the masks.
#
# HOW IT IS CHECKED (test/test-qr-code.ps1): every table against the standard's capacities, the
# Reed-Solomon code and the format and version bits against published values, and whole symbols against
# known-answer vectors made by another encoder (test/fixtures/qr/vectors.json says which and how).
#
# WHY A PNG AND NOT TEXT IN THE TERMINAL (the brief let this file choose). An offer is about 700
# characters: version 20 or so at level M, 97 modules a side. Drawn in a terminal with ASCII characters
# only, a module needs two columns to come out square (a cell is about twice as tall as wide), so the
# code with its quiet zone is over 200 columns - wider than a terminal is - and a terminal drawn light on
# dark shows it inverted, which phone scanners (the PWA reads it with the browser's BarcodeDetector) may
# not read at all. A PNG has square black modules on white, at any size, and nothing but this file makes
# it. So the code is a PNG the command opens locally; the offer's TEXT is printed too, for a paste.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

# The standard's tables, indexed by version 1 to 40 (index 0 unused), in the order L, M, Q, H.
$script:HordeQrEccPerBlock = @{
    L = @(-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30)
    M = @(-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28)
    Q = @(-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30)
    H = @(-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30)
}
$script:HordeQrBlocks = @{
    L = @(-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25)
    M = @(-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49)
    Q = @(-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68)
    H = @(-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81)
}
# The two format bits of each level (the standard's table 12): L 01, M 00, Q 11, H 10.
$script:HordeQrLevelBits = @{ L = 1; M = 0; Q = 3; H = 2 }

function Get-HordeQrLevels { return @("L", "M", "Q", "H") }

function Get-HordeQrRawModules {
    # The modules of a version left for data and error correction once every function pattern is drawn.
    param([Parameter(Mandatory = $true)][ValidateRange(1, 40)][int]$Version)
    $n = (16 * $Version + 128) * $Version + 64
    if ($Version -ge 2) {
        $align = [int][System.Math]::Floor($Version / 7) + 2
        $n -= (25 * $align - 10) * $align - 55
        if ($Version -ge 7) { $n -= 36 }
    }
    return $n
}

function Get-HordeQrDataCodewords {
    # The data codewords a version holds at a level.
    param([Parameter(Mandatory = $true)][ValidateRange(1, 40)][int]$Version, [Parameter(Mandatory = $true)][ValidateSet("L", "M", "Q", "H")][string]$Level)
    return ([int][System.Math]::Floor((Get-HordeQrRawModules -Version $Version) / 8) - $script:HordeQrEccPerBlock[$Level][$Version] * $script:HordeQrBlocks[$Level][$Version])
}

function Get-HordeQrByteCapacity {
    # The most bytes one byte-mode segment holds in a version at a level.
    param([Parameter(Mandatory = $true)][ValidateRange(1, 40)][int]$Version, [Parameter(Mandatory = $true)][ValidateSet("L", "M", "Q", "H")][string]$Level)
    $countBits = $(if ($Version -lt 10) { 8 } else { 16 })
    return [int][System.Math]::Floor(((Get-HordeQrDataCodewords -Version $Version -Level $Level) * 8 - 4 - $countBits) / 8)
}

function Get-HordeQrAlignmentPositions {
    # The centre coordinates of a version's alignment patterns, on both axes.
    param([Parameter(Mandatory = $true)][ValidateRange(1, 40)][int]$Version)
    if ($Version -eq 1) { return @() }
    $num = [int][System.Math]::Floor($Version / 7) + 2
    $step = [int][System.Math]::Floor(($Version * 8 + $num * 3 + 5) / ($num * 4 - 4)) * 2
    $size = $Version * 4 + 17
    $out = New-Object System.Collections.ArrayList
    [void]$out.Add(6)
    for ($i = $num - 2; $i -ge 0; $i--) { [void]$out.Add($size - 7 - $i * $step) }
    return @($out.ToArray())
}

function Get-HordeQrGfMultiply {
    # x * y in GF(2^8) modulo x^8 + x^4 + x^3 + x^2 + 1 (0x11D), Russian peasant style.
    param([int]$X, [int]$Y)
    $z = 0
    for ($i = 7; $i -ge 0; $i--) {
        $z = ($z -shl 1) -bxor (($z -shr 7) * 0x11D)
        $z = $z -bxor ((($Y -shr $i) -band 1) * $X)
    }
    return $z
}

function Get-HordeQrRsDivisor {
    # The Reed-Solomon generator polynomial of a degree, highest term dropped (it is always 1), as
    # coefficients from the next highest power down.
    param([Parameter(Mandatory = $true)][ValidateRange(1, 255)][int]$Degree)
    $r = New-Object int[] $Degree
    $r[$Degree - 1] = 1
    $root = 1
    for ($i = 0; $i -lt $Degree; $i++) {
        for ($j = 0; $j -lt $Degree; $j++) {
            $r[$j] = Get-HordeQrGfMultiply -X $r[$j] -Y $root
            if ($j + 1 -lt $Degree) { $r[$j] = $r[$j] -bxor $r[$j + 1] }
        }
        $root = Get-HordeQrGfMultiply -X $root -Y 2
    }
    return , $r
}

function Get-HordeQrRsRemainder {
    # The error correction codewords of -Data under -Divisor: the remainder of the division.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][int[]]$Data, [Parameter(Mandatory = $true)][int[]]$Divisor)
    $n = $Divisor.Length
    $r = New-Object int[] $n
    foreach ($b in $Data) {
        $factor = $b -bxor $r[0]
        for ($i = 0; $i -lt $n - 1; $i++) { $r[$i] = $r[$i + 1] }
        $r[$n - 1] = 0
        for ($i = 0; $i -lt $n; $i++) { $r[$i] = $r[$i] -bxor (Get-HordeQrGfMultiply -X $Divisor[$i] -Y $factor) }
    }
    return , $r
}

function Get-HordeQrFormatBits {
    # The 15 format bits of a level and mask: 5 data bits, 10 BCH bits, masked with 0x5412.
    param([Parameter(Mandatory = $true)][ValidateSet("L", "M", "Q", "H")][string]$Level, [Parameter(Mandatory = $true)][ValidateRange(0, 7)][int]$Mask)
    $data = ($script:HordeQrLevelBits[$Level] -shl 3) -bor $Mask
    $rem = $data
    for ($i = 0; $i -lt 10; $i++) { $rem = ($rem -shl 1) -bxor (($rem -shr 9) * 0x537) }
    return ((($data -shl 10) -bor $rem) -bxor 0x5412)
}

function Get-HordeQrVersionBits {
    # The 18 version bits of a version from 7 on: 6 data bits and 12 BCH bits.
    param([Parameter(Mandatory = $true)][ValidateRange(7, 40)][int]$Version)
    $rem = $Version
    for ($i = 0; $i -lt 12; $i++) { $rem = ($rem -shl 1) -bxor (($rem -shr 11) * 0x1F25) }
    return (($Version -shl 12) -bor $rem)
}

function Get-HordeQrCodewords {
    # The final codeword sequence of -Bytes in -Version at -Level: the byte-mode segment, terminator,
    # padding, then each block's error correction, interleaved as the standard places them.
    param([byte[]]$Bytes, [int]$Version, [string]$Level)
    $capBits = (Get-HordeQrDataCodewords -Version $Version -Level $Level) * 8
    $bits = New-Object System.Collections.Generic.List[int]
    $put = { param([int]$Value, [int]$Count) for ($i = $Count - 1; $i -ge 0; $i--) { $bits.Add(($Value -shr $i) -band 1) } }
    & $put 4 4
    & $put $Bytes.Length $(if ($Version -lt 10) { 8 } else { 16 })
    foreach ($b in $Bytes) { & $put ([int]$b) 8 }
    & $put 0 ([System.Math]::Min(4, $capBits - $bits.Count))
    & $put 0 ((8 - $bits.Count % 8) % 8)
    $data = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $bits.Count; $i += 8) {
        $v = 0
        for ($j = 0; $j -lt 8; $j++) { $v = ($v -shl 1) -bor $bits[$i + $j] }
        $data.Add($v)
    }
    $pad = 0xEC
    while ($data.Count * 8 -lt $capBits) { $data.Add($pad); $pad = $pad -bxor (0xEC -bxor 0x11) }
    $numBlocks = $script:HordeQrBlocks[$Level][$Version]
    $eccLen = $script:HordeQrEccPerBlock[$Level][$Version]
    $raw = [int][System.Math]::Floor((Get-HordeQrRawModules -Version $Version) / 8)
    $numShort = $numBlocks - $raw % $numBlocks
    $shortLen = [int][System.Math]::Floor($raw / $numBlocks)
    $divisor = Get-HordeQrRsDivisor -Degree $eccLen
    $blocks = New-Object System.Collections.ArrayList
    $k = 0
    for ($i = 0; $i -lt $numBlocks; $i++) {
        $datLen = $shortLen - $eccLen + $(if ($i -lt $numShort) { 0 } else { 1 })
        $dat = [int[]]$data.GetRange($k, $datLen).ToArray()
        $k += $datLen
        $ecc = Get-HordeQrRsRemainder -Data $dat -Divisor $divisor
        $block = New-Object System.Collections.Generic.List[int]
        $block.AddRange($dat)
        # A short block holds one place-holder so every block is as long; it is skipped below.
        if ($i -lt $numShort) { $block.Add(-1) }
        $block.AddRange($ecc)
        [void]$blocks.Add($block)
    }
    $out = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $blocks[0].Count; $i++) {
        for ($j = 0; $j -lt $blocks.Count; $j++) {
            if ($i -ne $shortLen - $eccLen -or $j -ge $numShort) { $out.Add($blocks[$j][$i]) }
        }
    }
    return , ([int[]]$out.ToArray())
}

function Test-HordeQrMasked {
    # Does mask -Mask invert the module at column -X, row -Y?
    param([int]$Mask, [int]$X, [int]$Y)
    switch ($Mask) {
        0 { return (($X + $Y) % 2 -eq 0) }
        1 { return ($Y % 2 -eq 0) }
        2 { return ($X % 3 -eq 0) }
        3 { return (($X + $Y) % 3 -eq 0) }
        4 { return (([int][System.Math]::Floor($X / 3) + [int][System.Math]::Floor($Y / 2)) % 2 -eq 0) }
        5 { return (($X * $Y) % 2 + ($X * $Y) % 3 -eq 0) }
        6 { return ((($X * $Y) % 2 + ($X * $Y) % 3) % 2 -eq 0) }
        default { return ((($X + $Y) % 2 + ($X * $Y) % 3) % 2 -eq 0) }
    }
}

function Set-HordeQrFormat {
    # Draw the format bits of -Level and -Mask, both copies, and the dark module.
    param([int[]]$Modules, [int]$Size, [string]$Level, [int]$Mask)
    $bits = Get-HordeQrFormatBits -Level $Level -Mask $Mask
    $b = { param([int]$i) ($bits -shr $i) -band 1 }
    for ($i = 0; $i -le 5; $i++) { $Modules[$i * $Size + 8] = & $b $i }
    $Modules[7 * $Size + 8] = & $b 6
    $Modules[8 * $Size + 8] = & $b 7
    $Modules[8 * $Size + 7] = & $b 8
    for ($i = 9; $i -lt 15; $i++) { $Modules[8 * $Size + (14 - $i)] = & $b $i }
    for ($i = 0; $i -lt 8; $i++) { $Modules[8 * $Size + ($Size - 1 - $i)] = & $b $i }
    for ($i = 8; $i -lt 15; $i++) { $Modules[($Size - 15 + $i) * $Size + 8] = & $b $i }
    $Modules[($Size - 8) * $Size + 8] = 1
}

function Get-HordeQrPenalty {
    # The standard's penalty score of a finished symbol (rules N1 to N4: runs, 2x2 blocks, finder-like
    # patterns, dark balance), the lower the better.
    param([int[]]$Modules, [int]$Size)
    $score = 0
    foreach ($axis in 0, 1) {
        for ($a = 0; $a -lt $Size; $a++) {
            $runColor = 0; $run = 0
            $h = New-Object int[] 7
            $base = $(if ($axis -eq 0) { $a * $Size } else { $a })
            $stride = $(if ($axis -eq 0) { 1 } else { $Size })
            for ($b = 0; $b -lt $Size; $b++) {
                $m = $Modules[$base + $b * $stride]
                if ($m -eq $runColor) {
                    $run++
                    if ($run -eq 5) { $score += 3 } elseif ($run -gt 5) { $score++ }
                } else {
                    $len = $run; if ($h[0] -eq 0) { $len += $Size }
                    for ($i = 6; $i -gt 0; $i--) { $h[$i] = $h[$i - 1] }; $h[0] = $len
                    # Get-HordeQrFinderCount's test, inline: it runs once per run of every line.
                    if ($runColor -eq 0) {
                        $n = $h[1]
                        if ($n -gt 0 -and $h[2] -eq $n -and $h[3] -eq $n * 3 -and $h[4] -eq $n -and $h[5] -eq $n) {
                            if ($h[0] -ge $n * 4 -and $h[6] -ge $n) { $score += 40 }
                            if ($h[6] -ge $n * 4 -and $h[0] -ge $n) { $score += 40 }
                        }
                    }
                    $runColor = $m; $run = 1
                }
            }
            # The end of the line: the run is closed, and the light border beyond it counted.
            if ($runColor -eq 1) {
                $len = $run; if ($h[0] -eq 0) { $len += $Size }
                for ($i = 6; $i -gt 0; $i--) { $h[$i] = $h[$i - 1] }; $h[0] = $len
                $run = 0
            }
            $len = $run + $Size; if ($h[0] -eq 0) { $len += $Size }
            for ($i = 6; $i -gt 0; $i--) { $h[$i] = $h[$i - 1] }; $h[0] = $len
            $score += 40 * (Get-HordeQrFinderCount -History $h)
        }
    }
    $dark = 0
    for ($y = 0; $y -lt $Size; $y++) {
        for ($x = 0; $x -lt $Size; $x++) {
            $c = $Modules[$y * $Size + $x]
            $dark += $c
            if ($y -lt $Size - 1 -and $x -lt $Size - 1 -and $c -eq $Modules[$y * $Size + $x + 1] -and $c -eq $Modules[($y + 1) * $Size + $x] -and $c -eq $Modules[($y + 1) * $Size + $x + 1]) { $score += 3 }
        }
    }
    $total = $Size * $Size
    $k = [int][System.Math]::Floor(([System.Math]::Abs($dark * 20 - $total * 10) + $total - 1) / $total) - 1
    return ($score + $k * 10)
}

function Get-HordeQrFinderCount {
    # How many finder-like patterns (1:1:3:1:1 with four light on one side) a run history ends with.
    param([int[]]$History)
    $n = $History[1]
    $core = ($n -gt 0 -and $History[2] -eq $n -and $History[3] -eq $n * 3 -and $History[4] -eq $n -and $History[5] -eq $n)
    $c = 0
    if ($core -and $History[0] -ge $n * 4 -and $History[6] -ge $n) { $c++ }
    if ($core -and $History[6] -ge $n * 4 -and $History[0] -ge $n) { $c++ }
    return $c
}

function New-HordeQrCode {
    # The QR code of -Text (printable ASCII, as one byte-mode segment) at -Level, in the smallest
    # version from -MinVersion that holds it. -Mask 0 to 7 forces a mask; -1 picks the one the penalty
    # rules score lowest. { version; level; mask; size; modules } - modules is size * size ints, row by
    # row, 1 dark. Throws when the text is not printable ASCII or holds more than version 40 can.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [ValidateSet("L", "M", "Q", "H")][string]$Level = "M",
        [ValidateRange(-1, 7)][int]$Mask = -1, [ValidateRange(1, 40)][int]$MinVersion = 1)
    if ($Text -cnotmatch '\A[\x20-\x7E]*\z') { throw "a QR code here holds printable ASCII only" }
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Text)
    $version = 0
    for ($v = $MinVersion; $v -le 40; $v++) { if ($bytes.Length -le (Get-HordeQrByteCapacity -Version $v -Level $Level)) { $version = $v; break } }
    if ($version -eq 0) { throw ("the text is " + $bytes.Length + " bytes, more than a QR code holds at level " + $Level) }
    $size = $version * 4 + 17
    $mods = New-Object int[] ($size * $size)
    $fn = New-Object bool[] ($size * $size)
    $set = { param([int]$x, [int]$y, [int]$dark) $mods[$y * $size + $x] = $dark; $fn[$y * $size + $x] = $true }
    for ($i = 0; $i -lt $size; $i++) { & $set 6 $i ([int]($i % 2 -eq 0)); & $set $i 6 ([int]($i % 2 -eq 0)) }
    foreach ($c in @(@(3, 3), @(($size - 4), 3), @(3, ($size - 4)))) {
        for ($dy = -4; $dy -le 4; $dy++) {
            for ($dx = -4; $dx -le 4; $dx++) {
                $x = $c[0] + $dx; $y = $c[1] + $dy
                if ($x -lt 0 -or $x -ge $size -or $y -lt 0 -or $y -ge $size) { continue }
                $d = [System.Math]::Max([System.Math]::Abs($dx), [System.Math]::Abs($dy))
                & $set $x $y ([int]($d -ne 2 -and $d -ne 4))
            }
        }
    }
    $pos = @(Get-HordeQrAlignmentPositions -Version $version)
    for ($i = 0; $i -lt $pos.Count; $i++) {
        for ($j = 0; $j -lt $pos.Count; $j++) {
            if (($i -eq 0 -and $j -eq 0) -or ($i -eq 0 -and $j -eq $pos.Count - 1) -or ($i -eq $pos.Count - 1 -and $j -eq 0)) { continue }
            for ($dy = -2; $dy -le 2; $dy++) { for ($dx = -2; $dx -le 2; $dx++) { & $set ($pos[$i] + $dx) ($pos[$j] + $dy) ([int]([System.Math]::Max([System.Math]::Abs($dx), [System.Math]::Abs($dy)) -ne 1)) } }
        }
    }
    # The format areas are reserved now (drawn for real once the mask is known), and the version bits.
    Set-HordeQrFormat -Modules $mods -Size $size -Level $Level -Mask 0
    for ($i = 0; $i -le 8; $i++) { $fn[$i * $size + 8] = $true; $fn[8 * $size + $i] = $true }
    for ($i = 0; $i -lt 8; $i++) { $fn[8 * $size + ($size - 1 - $i)] = $true }
    for ($i = 0; $i -lt 8; $i++) { $fn[($size - 1 - $i) * $size + 8] = $true }
    if ($version -ge 7) {
        $vb = Get-HordeQrVersionBits -Version $version
        for ($i = 0; $i -lt 18; $i++) {
            $bit = ($vb -shr $i) -band 1
            $a = $size - 11 + $i % 3; $b = [int][System.Math]::Floor($i / 3)
            & $set $a $b $bit; & $set $b $a $bit
        }
    }
    $words = Get-HordeQrCodewords -Bytes $bytes -Version $version -Level $Level
    $i = 0
    $total = $words.Length * 8
    for ($right = $size - 1; $right -ge 1; $right -= 2) {
        if ($right -eq 6) { $right = 5 }
        $upward = ((($right + 1) -band 2) -eq 0)
        for ($vert = 0; $vert -lt $size; $vert++) {
            for ($j = 0; $j -lt 2; $j++) {
                $x = $right - $j
                $y = $(if ($upward) { $size - 1 - $vert } else { $vert })
                if (-not $fn[$y * $size + $x] -and $i -lt $total) {
                    $mods[$y * $size + $x] = ($words[$i -shr 3] -shr (7 - ($i -band 7))) -band 1
                    $i++
                }
            }
        }
    }
    $best = $Mask
    if ($Mask -lt 0) {
        $bestScore = [int]::MaxValue
        for ($m = 0; $m -lt 8; $m++) {
            $trial = [int[]]$mods.Clone()
            Set-HordeQrMaskApplied -Modules $trial -Function $fn -Size $size -Mask $m
            Set-HordeQrFormat -Modules $trial -Size $size -Level $Level -Mask $m
            $s = Get-HordeQrPenalty -Modules $trial -Size $size
            if ($s -lt $bestScore) { $bestScore = $s; $best = $m }
        }
    }
    Set-HordeQrMaskApplied -Modules $mods -Function $fn -Size $size -Mask $best
    Set-HordeQrFormat -Modules $mods -Size $size -Level $Level -Mask $best
    return [pscustomobject]@{ version = $version; level = $Level; mask = $best; size = $size; modules = $mods }
}

function Set-HordeQrMaskApplied {
    # Invert, under -Mask, every module that is not part of a function pattern.
    # The masks are written out here rather than calling Test-HordeQrMasked per module: a function call
    # per module made a version 20 code take seconds longer under Windows PowerShell (measured
    # 2026-10-10); test/test-qr-code.ps1 holds the two to each other.
    param([int[]]$Modules, [bool[]]$Function, [int]$Size, [int]$Mask)
    for ($y = 0; $y -lt $Size; $y++) {
        $row = $y * $Size
        for ($x = 0; $x -lt $Size; $x++) {
            if ($Function[$row + $x]) { continue }
            $p = $x * $y
            if ($Mask -eq 0) { $inv = (($x + $y) % 2 -eq 0) }
            elseif ($Mask -eq 1) { $inv = ($y % 2 -eq 0) }
            elseif ($Mask -eq 2) { $inv = ($x % 3 -eq 0) }
            elseif ($Mask -eq 3) { $inv = (($x + $y) % 3 -eq 0) }
            elseif ($Mask -eq 4) { $inv = ((($x - $x % 3) / 3 + ($y - $y % 2) / 2) % 2 -eq 0) }
            elseif ($Mask -eq 5) { $inv = ($p % 2 + $p % 3 -eq 0) }
            elseif ($Mask -eq 6) { $inv = (($p % 2 + $p % 3) % 2 -eq 0) }
            else { $inv = ((($x + $y) % 2 + $p % 3) % 2 -eq 0) }
            if ($inv) { $Modules[$row + $x] = 1 - $Modules[$row + $x] }
        }
    }
}

function ConvertTo-HordeQrRows {
    # The symbol as one string of 1 (dark) and 0 per row: what the known-answer vectors hold.
    param([Parameter(Mandatory = $true)]$Code)
    $rows = New-Object System.Collections.ArrayList
    for ($y = 0; $y -lt $Code.size; $y++) {
        $sb = New-Object System.Text.StringBuilder
        for ($x = 0; $x -lt $Code.size; $x++) { [void]$sb.Append([char](48 + $Code.modules[$y * $Code.size + $x])) }
        [void]$rows.Add($sb.ToString())
    }
    return @($rows.ToArray())
}

function ConvertTo-HordeQrPng {
    # A PNG of the symbol: -Scale pixels a module, a quiet zone of -Border modules, black on white,
    # 8-bit greyscale, no filter; zlib by DeflateStream with its Adler-32 and each chunk's CRC-32.
    param([Parameter(Mandatory = $true)]$Code, [ValidateRange(1, 32)][int]$Scale = 8, [ValidateRange(0, 16)][int]$Border = 4)
    $side = ($Code.size + 2 * $Border) * $Scale
    $rowLen = 1 + $side
    $raw = New-Object byte[] ($rowLen * $side)
    for ($py = 0; $py -lt $side; $py++) {
        $my = [int][System.Math]::Floor($py / $Scale) - $Border
        $at = $py * $rowLen
        for ($px = 0; $px -lt $side; $px++) {
            $mx = [int][System.Math]::Floor($px / $Scale) - $Border
            $dark = ($mx -ge 0 -and $my -ge 0 -and $mx -lt $Code.size -and $my -lt $Code.size -and $Code.modules[$my * $Code.size + $mx] -eq 1)
            $raw[$at + 1 + $px] = $(if ($dark) { 0 } else { 255 })
        }
    }
    $deflated = New-Object System.IO.MemoryStream
    $z = New-Object System.IO.Compression.DeflateStream($deflated, [System.IO.Compression.CompressionMode]::Compress, $true)
    $z.Write($raw, 0, $raw.Length); $z.Dispose()
    # Checksums as [long]: Windows PowerShell reads 0xFFFFFFFF as the Int32 -1 (surfaces/pwa/Site.ps1
    # measured it), so every value stays a non-negative long under a mask.
    [long]$a = 1; [long]$b = 0
    foreach ($v in $raw) { $a = ($a + $v) % 65521; $b = ($b + $a) % 65521 }
    [long]$adler = ($b * 65536) + $a
    $idat = New-Object System.IO.MemoryStream
    $idat.WriteByte(0x78); $idat.WriteByte(0x01)
    $d = $deflated.ToArray(); $idat.Write($d, 0, $d.Length)
    foreach ($s in 24, 16, 8, 0) { $idat.WriteByte([byte](($adler -shr $s) -band 255)) }
    [long]$poly = 3988292384
    [long]$all = 4294967295
    $crcTable = New-Object long[] 256
    for ($n = 0; $n -lt 256; $n++) { [long]$c = $n; for ($k = 0; $k -lt 8; $k++) { if ($c -band 1) { $c = $poly -bxor ($c -shr 1) } else { $c = $c -shr 1 } }; $crcTable[$n] = $c }
    $out = New-Object System.IO.MemoryStream
    $sig = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A); $out.Write($sig, 0, 8)
    $chunk = {
        param([string]$Type, [byte[]]$Data)
        $len = $Data.Length
        foreach ($s in 24, 16, 8, 0) { $out.WriteByte([byte](($len -shr $s) -band 255)) }
        $td = New-Object byte[] (4 + $len)
        [System.Text.Encoding]::ASCII.GetBytes($Type).CopyTo($td, 0); $Data.CopyTo($td, 4)
        $out.Write($td, 0, $td.Length)
        [long]$crc = $all
        foreach ($v in $td) { $crc = $crcTable[($crc -bxor $v) -band 255] -bxor ($crc -shr 8) }
        $crc = $crc -bxor $all
        foreach ($s in 24, 16, 8, 0) { $out.WriteByte([byte](($crc -shr $s) -band 255)) }
    }
    $hdr = New-Object byte[] 13
    foreach ($i in 0..3) { $hdr[$i] = [byte](($side -shr (24 - 8 * $i)) -band 255); $hdr[4 + $i] = $hdr[$i] }
    $hdr[8] = 8; $hdr[9] = 0
    & $chunk "IHDR" $hdr
    & $chunk "IDAT" $idat.ToArray()
    & $chunk "IEND" (New-Object byte[] 0)
    return , $out.ToArray()
}
