# Mutations of transports/local/Native.ps1, the Win32 half of the local pipe. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\transport-local-native.psd1
# transports\local\test\test-local.ps1 must fail for each. The C# is compiled when the suite loads it,
# and each mutant runs in a fresh copy and a fresh process, so no compiled type is shared.
@{
    Target = "transports\local\Native.ps1"
    Suite  = "transports\local\test\test-local.ps1"
    Mutations = @(
        @{ Name = "remote-clients-accepted"
           Find = 'CreateNamedPipe(fullName, mode, PIPE_REJECT_REMOTE_CLIENTS,'
           Replace = 'CreateNamedPipe(fullName, mode, 0,' }
        @{ Name = "first-instance-not-required"
           Find = 'if (first) mode |= FILE_FLAG_FIRST_PIPE_INSTANCE;'
           Replace = '' }
        @{ Name = "integrity-read-as-system"
           Find = 'return Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(count - 1)));'
           Replace = 'return 16384;' }
        @{ Name = "invalid-handle-label-read"
           Find = 'if (h == null || h.IsInvalid || h.IsClosed) return "";'
           Replace = '' }
        @{ Name = "label-not-read"
           Find = 'try { return Marshal.PtrToStringUni(text); } finally { LocalFree(text); }'
           Replace = 'LocalFree(text); return "";' }
    )
}
