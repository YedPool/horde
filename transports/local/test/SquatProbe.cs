// transports/local/test/SquatProbe.cs - a small attacker program for test-local.ps1, compiled by the
// suite with the .NET Framework's own csc.exe into a temp folder. Not part of Horde.
//
// It is a native-looking executable on purpose: the node's image check (Test-HordeLocalNodeImage)
// refuses a pipe served by anything but the node's interpreter, and every process the suite can
// otherwise start is powershell.exe, which that check accepts (review of PR #42, second round). Built
// from the reviewer's csprobe.cs.
//
//   SquatProbe.exe serve <pipe> <report> [seconds]   create the pipe first and serve each client
//   SquatProbe.exe add   <pipe> <report> [seconds]   add an instance to a pipe someone else made
// Every line it writes to <report> says what it managed.
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;

public static class SquatProbe {
    static string report;
    static void R(string s) { File.AppendAllText(report, s + Environment.NewLine); }
    static string Inner(Exception e) { while (e.InnerException != null) e = e.InnerException; return e.GetType().Name + ": " + e.Message; }

    public static int Main(string[] a) {
        string mode = a[0], pipe = a[1];
        report = a[2];
        int secs = a.Length > 3 ? int.Parse(a[3]) : 15;
        R("started pid=" + Process.GetCurrentProcess().Id);
        try {
            // Owned by this user, said explicitly (issue #89): an elevated admin token would otherwise make
            // Administrators the owner, and the hub would refuse the pipe for its owner before the image
            // check this probe exists to reach. Set only on the first instance: on an instance added to a
            // pipe someone else made, Windows keeps the first one's security.
            PipeSecurity sec = new PipeSecurity();
            SecurityIdentifier me = WindowsIdentity.GetCurrent().User;
            sec.SetOwner(me);
            sec.AddAccessRule(new PipeAccessRule(me, PipeAccessRights.FullControl, AccessControlType.Allow));
            NamedPipeServerStream s = mode == "serve"
                ? new NamedPipeServerStream(pipe, PipeDirection.InOut, -1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 0, 0, sec)
                : new NamedPipeServerStream(pipe, PipeDirection.InOut, -1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
            R(mode + ": CREATED");
            var w = s.WaitForConnectionAsync();
            if (w.Wait(secs * 1000)) {
                R(mode + ": a client connected");
                byte[] hello = Encoding.ASCII.GetBytes("hello-from-squatter\n");
                s.Write(hello, 0, hello.Length);
                s.Flush();
                byte[] buf = new byte[512];
                var rt = s.ReadAsync(buf, 0, buf.Length);
                if (rt.Wait(3000) && rt.Result > 0) R(mode + ": client sent: " + Encoding.ASCII.GetString(buf, 0, rt.Result).TrimEnd());
                else R(mode + ": client sent nothing");
            } else R(mode + ": no client");
            s.Dispose();
        } catch (Exception e) { R(mode + ": " + Inner(e)); }
        R("done");
        return 0;
    }
}
