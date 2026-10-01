# Run at LOW integrity by transports/local/test/LowIntegrity.ps1, for test-local.ps1. Not a suite.
# It plays the attacker of the review of PR #42 and writes what it managed to -Out, one line at a time:
#   squat  create the pipe -Pipe first, wait up to 20 s for a client, and talk to it
#   hold   open -Pipe read-only and read what the node sends
param([string]$Mode, [string]$Pipe, [string]$Out)

function Report { param([string]$Line) [System.IO.File]::AppendAllText($Out, $Line + [Environment]::NewLine) }
function Inner { param($E) while ($null -ne $E.InnerException) { $E = $E.InnerException }; return ($E.GetType().Name + ": " + $E.Message) }

Report "started"
if ($Mode -eq "squat") {
    try {
        $s = New-Object System.IO.Pipes.NamedPipeServerStream($Pipe, [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous)
        Report "squat: CREATED"
        $wait = $s.WaitForConnectionAsync()
        if ($wait.Wait(20000)) {
            Report "squat: a client connected"
            $w = New-Object System.IO.StreamWriter($s)
            $w.AutoFlush = $true
            $w.Write("hello-from-squatter`n")
            $r = New-Object System.IO.StreamReader($s)
            $line = $r.ReadLine()
            Report ("squat: client sent: " + $line)
        } else { Report "squat: no client" }
        $s.Dispose()
    } catch { Report ("squat: " + (Inner $_.Exception)) }
}
if ($Mode -eq "hold") {
    try {
        $c = New-Object System.IO.Pipes.NamedPipeClientStream(".", $Pipe, [System.IO.Pipes.PipeDirection]::In)
        $c.Connect(3000)
        Report "hold: CONNECTED read-only"
        $buf = New-Object byte[] 256
        $n = $c.Read($buf, 0, 256)
        Report ("hold: read " + $n + " bytes: " + [System.Text.Encoding]::ASCII.GetString($buf, 0, $n))
        $c.Dispose()
    } catch { Report ("hold: " + (Inner $_.Exception)) }
}
Report "done"
