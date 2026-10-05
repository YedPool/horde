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
        # OWNED BY THIS USER, SAID EXPLICITLY (issue #89). Left to the default, an elevated admin token
        # makes Administrators (S-1-5-32-544) the owner of what it creates, so the hub refused this pipe
        # for its owner before its integrity was looked at, and the checks that pin the integrity
        # refusal failed (measured 2026-10-05, High token, session 1). The attacker this plays is this
        # user under a lowered token, so its pipe is this user's.
        $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $sec = New-Object System.IO.Pipes.PipeSecurity
        $sec.SetOwner($me)
        $sec.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule($me, [System.IO.Pipes.PipeAccessRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)))
        $s = New-Object System.IO.Pipes.NamedPipeServerStream($Pipe, [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous, 0, 0, $sec)
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
