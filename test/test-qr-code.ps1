# IS cli/QrCode.ps1 A QR CODE ENCODER THE STANDARD WOULD RECOGNISE, AND IS ITS PNG A PICTURE OF THAT CODE?
#
# The tables against the standard's own capacities and codeword counts; the Reed-Solomon code, the
# format bits, the version bits and the alignment positions against published values; whole symbols
# against known-answer vectors made by another encoder (test/fixtures/qr/vectors.json says which); the
# mask choice against the penalty rules; and the PNG read back byte by byte. Pure: no file, no process.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "cli\QrCode.ps1")
Set-StrictMode -Version Latest

Write-Host ""
Write-Host "--- 1. the tables hold the standard's numbers ---" -ForegroundColor Cyan
# ISO/IEC 18004:2015 table 7 (byte mode capacities) and table 9 (codewords per version).
$cap = @{ "1" = @(17, 14, 11, 7); "10" = @(271, 213, 151, 119); "20" = @(858, 666, 482, 382); "40" = @(2953, 2331, 1663, 1273) }
foreach ($v in @($cap.Keys | Sort-Object { [int]$_ })) {
    $got = @(Get-HordeQrLevels | ForEach-Object { Get-HordeQrByteCapacity -Version ([int]$v) -Level $_ })
    Check (($got -join ",") -ceq ($cap[$v] -join ",")) ("version " + $v + " holds " + ($cap[$v] -join ", ") + " bytes at L, M, Q, H (got " + ($got -join ", ") + ")")
}
Check ((Get-HordeQrRawModules -Version 1) -eq 208 -and (Get-HordeQrRawModules -Version 2) -eq 359 -and (Get-HordeQrRawModules -Version 7) -eq 1568 -and (Get-HordeQrRawModules -Version 40) -eq 29648) "versions 1, 2, 7 and 40 leave 208, 359, 1568 and 29648 modules for codewords (26, 44, 196 and 3706 codewords and their remainder bits)"
$bad = New-Object System.Collections.ArrayList
for ($v = 1; $v -le 40; $v++) {
    $raw = [int][System.Math]::Floor((Get-HordeQrRawModules -Version $v) / 8)
    $prev = 0
    foreach ($l in @(Get-HordeQrLevels)) {
        $d = Get-HordeQrDataCodewords -Version $v -Level $l
        $blocks = $script:HordeQrBlocks[$l][$v]
        # Every block holds its error correction plus at least one data codeword, and the levels run
        # from most data (L) to least (H).
        if ($d -le $blocks -or $d -ge $raw -or ($prev -gt 0 -and $d -ge $prev)) { [void]$bad.Add("v" + $v + $l) }
        $prev = $d
    }
}
Check ($bad.Count -eq 0) ("every version and level splits its codewords into blocks that each hold data, L holding most and H least (" + ($bad -join ", ") + ")")
Check (((Get-HordeQrAlignmentPositions -Version 1) -join ",") -ceq "" -and ((Get-HordeQrAlignmentPositions -Version 2) -join ",") -ceq "6,18" -and ((Get-HordeQrAlignmentPositions -Version 7) -join ",") -ceq "6,22,38" -and
    ((Get-HordeQrAlignmentPositions -Version 32) -join ",") -ceq "6,34,60,86,112,138" -and ((Get-HordeQrAlignmentPositions -Version 40) -join ",") -ceq "6,30,58,86,114,142,170") "the alignment patterns sit where annex E puts them (versions 1, 2, 7, 32 and 40)"

Write-Host ""
Write-Host "--- 2. the codes: Reed-Solomon, format bits, version bits ---" -ForegroundColor Cyan
# The standard's worked example, 1-M "HELLO WORLD": its 16 data codewords and their 10 of error correction.
$ecc = Get-HordeQrRsRemainder -Data @(32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17) -Divisor (Get-HordeQrRsDivisor -Degree 10)
Check (($ecc -join ",") -ceq "196,35,39,119,235,215,231,226,93,23") ("the Reed-Solomon code gives the worked example's error correction (" + ($ecc -join ",") + ")")
$fmt = @(@("L", 0x77C4), @("M", 0x5412), @("Q", 0x355F), @("H", 0x1689)) | Where-Object { (Get-HordeQrFormatBits -Level $_[0] -Mask 0) -ne $_[1] }
Check (@($fmt).Count -eq 0) "the format bits of mask 0 at L, M, Q and H are annex C's 77C4, 5412, 355F and 1689"
$ver = @(@(7, 0x07C94), @(8, 0x085BC), @(9, 0x09A99), @(10, 0x0A4D3), @(40, 0x28C69)) | Where-Object { (Get-HordeQrVersionBits -Version $_[0]) -ne $_[1] }
Check (@($ver).Count -eq 0) "the version bits of versions 7 to 10 and 40 are annex D's 07C94, 085BC, 09A99, 0A4D3 and 28C69"
# The masks are written out twice (Test-HordeQrMasked and, inline for speed, Set-HordeQrMaskApplied).
$apart = 0
for ($m = 0; $m -lt 8; $m++) {
    $mods = New-Object int[] (30 * 30)
    Set-HordeQrMaskApplied -Modules $mods -Function (New-Object bool[] (30 * 30)) -Size 30 -Mask $m
    for ($y = 0; $y -lt 30; $y++) { for ($x = 0; $x -lt 30; $x++) { if (($mods[$y * 30 + $x] -eq 1) -ne (Test-HordeQrMasked -Mask $m -X $x -Y $y)) { $apart++ } } }
}
Check ($apart -eq 0) ("the inline masks are the standard's eight, module for module (" + $apart + " apart)")

Write-Host ""
Write-Host "--- 3. whole symbols: the known-answer vectors ---" -ForegroundColor Cyan
$fx = [System.IO.File]::ReadAllText((Join-Path $here "fixtures\qr\vectors.json")) | ConvertFrom-Json
Check (@($fx.vectors).Count -ge 5) ("CONTROL: the vectors are read (" + @($fx.vectors).Count + ")")
foreach ($vec in @($fx.vectors)) {
    $q = New-HordeQrCode -Text $vec.text -Level $vec.level -Mask $vec.mask -MinVersion $vec.version
    $rows = @(ConvertTo-HordeQrRows -Code $q)
    $skip = @{}
    foreach ($r in @($vec.remainder)) { $skip["" + $r.row + "," + $r.col] = $true }
    $diff = 0; $remainderLight = $true
    for ($y = 0; $y -lt $rows.Count; $y++) {
        for ($x = 0; $x -lt $rows[$y].Length; $x++) {
            if ($skip.ContainsKey("" + $y + "," + $x)) { if ($rows[$y][$x] -ne [char]'0') { $remainderLight = $false }; continue }
            if ($rows[$y][$x] -ne $vec.rows[$y][$x]) { $diff++ }
        }
    }
    Check ($q.version -eq $vec.version -and $rows.Count -eq @($vec.rows).Count -and $diff -eq 0 -and $remainderLight) ("version " + $vec.version + "-" + $vec.level + ", mask " + $vec.mask + ", " + $vec.text.Length + " bytes: every module is the vector's (" + $diff + " apart)")
}
$auto = New-HordeQrCode -Text "horde relay pair: a version 7 symbol with its version bits, level Q" -Level "Q"
$scores = @(0..7 | ForEach-Object { $t = New-HordeQrCode -Text "horde relay pair: a version 7 symbol with its version bits, level Q" -Level "Q" -Mask $_; Get-HordeQrPenalty -Modules $t.modules -Size $t.size })
$min = ($scores | Measure-Object -Minimum).Minimum
Check ($scores[$auto.mask] -eq $min -and [array]::IndexOf($scores, [int]$min) -eq $auto.mask) ("with no mask asked, the first of the lowest penalty is chosen: mask " + $auto.mask + " (scores " + ($scores -join ", ") + ")")
Check ((New-HordeQrCode -Text "Horde").version -eq 1 -and (New-HordeQrCode -Text ("x" * 15)).version -eq 2 -and (New-HordeQrCode -Text ("x" * 14)).version -eq 1) "the smallest version that holds the text is chosen: 14 bytes fit version 1-M, 15 do not"
Check ((New-HordeQrCode -Text "").version -eq 1) "an empty text is a version 1 code"
Check (Throws { New-HordeQrCode -Text ("caf" + [char]0x00E9) } "printable ASCII") "a text that is not printable ASCII is refused"
Check (Throws { New-HordeQrCode -Text ("x" + [char]10) } "printable ASCII") "a line break is refused"
Check (Throws { New-HordeQrCode -Text ("x" * 2332) -Level "M" } "more than a QR code holds") "a text over version 40's capacity is refused"

Write-Host ""
Write-Host "--- 4. the PNG is a picture of the code ---" -ForegroundColor Cyan
$q = New-HordeQrCode -Text "https://relay.example.test/pair" -Level "M" -Mask 0 -MinVersion 3
$png = ConvertTo-HordeQrPng -Code $q -Scale 4 -Border 4
$side = ($q.size + 8) * 4
Check ([System.BitConverter]::ToString($png, 0, 8) -ceq "89-50-4E-47-0D-0A-1A-0A") "it starts with the PNG signature"
function Read-Be32 { param([byte[]]$B, [int]$At) return ([long]$B[$At] -shl 24) + ([long]$B[$At + 1] -shl 16) + ([long]$B[$At + 2] -shl 8) + [long]$B[$At + 3] }
[long]$poly = 3988292384
$crcTable = New-Object long[] 256
for ($n = 0; $n -lt 256; $n++) { [long]$c = $n; for ($k = 0; $k -lt 8; $k++) { if ($c -band 1) { $c = $poly -bxor ($c -shr 1) } else { $c = $c -shr 1 } }; $crcTable[$n] = $c }
$at = 8; $chunks = @(); $crcOk = $true; $idat = $null; $ihdr = $null
while ($at -lt $png.Length) {
    $len = [int](Read-Be32 $png $at)
    $type = [System.Text.Encoding]::ASCII.GetString($png, $at + 4, 4)
    [long]$crc = 4294967295
    for ($i = $at + 4; $i -lt $at + 8 + $len; $i++) { $crc = $crcTable[($crc -bxor $png[$i]) -band 255] -bxor ($crc -shr 8) }
    if (($crc -bxor 4294967295) -ne (Read-Be32 $png ($at + 8 + $len))) { $crcOk = $false }
    $data = New-Object byte[] $len; [System.Array]::Copy($png, $at + 8, $data, 0, $len)
    if ($type -ceq "IHDR") { $ihdr = $data } elseif ($type -ceq "IDAT") { $idat = $data }
    $chunks += $type
    $at += 12 + $len
}
Check (($chunks -join ",") -ceq "IHDR,IDAT,IEND" -and $crcOk) ("its chunks are IHDR, IDAT and IEND, each with a CRC-32 that holds (" + ($chunks -join ",") + ")")
Check ((Read-Be32 $ihdr 0) -eq $side -and (Read-Be32 $ihdr 4) -eq $side -and $ihdr[8] -eq 8 -and $ihdr[9] -eq 0) ("it is " + $side + " pixels square, 8-bit greyscale: four pixels a module and a quiet zone of four modules")
$ms = New-Object System.IO.MemoryStream -ArgumentList @(, [byte[]]$idat[2..($idat.Length - 5)])
$inflate = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
$plain = New-Object System.IO.MemoryStream
$inflate.CopyTo($plain); $inflate.Dispose()
$pix = $plain.ToArray()
$wrong = 0
for ($y = 0; $y -lt $q.size; $y++) {
    for ($x = 0; $x -lt $q.size; $x++) {
        $py = ($y + 4) * 4 + 2; $px = ($x + 4) * 4 + 2
        $want = $(if ($q.modules[$y * $q.size + $x] -eq 1) { 0 } else { 255 })
        if ($pix[$py * ($side + 1) + 1 + $px] -ne $want) { $wrong++ }
    }
}
Check ($pix.Length -eq $side * ($side + 1) -and $wrong -eq 0 -and $pix[0] -eq 0 -and $pix[1] -eq 255) ("inflated, every module is black or white as the code says and the quiet zone is white (" + $wrong + " wrong)")

Complete-HordeSuite -Success "the QR encoder matches the standard's tables, codes and an independent encoder's symbols, and its PNG pictures the code"
