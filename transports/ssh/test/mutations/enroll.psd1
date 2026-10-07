# Mutations of the ssh link's enrolment (transports/ssh/Enroll.ps1, remote plan R17b). Run:
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\enroll.psd1
# transports\ssh\test\test-enroll.ps1 must fail for each, except the one declared to survive.
@{
    Target = "transports\ssh\Enroll.ps1"
    Suite  = "transports\ssh\test\test-enroll.ps1"
    Mutations = @(
        # --- the coordinator's limits on the one ssh-keygen start (2026-10-06) ---
        @{ Name = "keygen-found-on-path"
           Find = '$exe = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh-keygen.exe")'
           Replace = '$exe = "ssh-keygen.exe"' }
        @{ Name = "keygen-rooted-check-dropped"
           Find = 'if (-not ([System.IO.Path]::IsPathRooted($exe) -and $exe.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $exe -PathType Leaf))) {'
           Replace = 'if ($false) {'
           Expect = "survives"
           Reason = "the check guards the system directory's answer, which no test can change; the program the start names is pinned by the exec guard's canonical setup, and keygen-found-on-path shows a wrong path fails" }
        @{ Name = "passphrase-accepted"
           Find = 'if ($Passphrase -cne "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "key-outside-home"
           Find = 'if ($where -ne "") { return (New-HordeSshEnrolResult -Ok $false -Reason ("refused to write a key outside Horde''s home: " + $where)) }'
           Replace = '' }
        @{ Name = "key-overwritten"
           Find = 'if ((Test-Path -LiteralPath $full) -or (Test-Path -LiteralPath ($full + ".pub"))) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "key-acl-not-set"
           Find = '$acl = Set-HordeSshKeyAcl -Path $full'
           Replace = '$acl = ""' }
        @{ Name = "key-acl-check-admits-others"
           Find = 'if ($rules.Count -lt 1 -or $others.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "key-acl-inheritance-allowed"
           Find = 'if (-not $read.AreAccessRulesProtected) {'
           Replace = 'if ($false) {' }
        @{ Name = "key-type-rsa"
           Find = '"-q", "-t", "ed25519", "-N"'
           Replace = '"-q", "-t", "rsa", "-N"' }
        # --- what is admitted, pinned and revoked ---
        @{ Name = "rsa-key-line-accepted"
           Find = '$script:HordeSshKeyLinePattern = ''\Assh-ed25519 (?<b64>'
           Replace = '$script:HordeSshKeyLinePattern = ''\Assh-(ed25519|rsa) (?<b64>' }
        @{ Name = "blob-not-checked"
           Find = 'if ($blob.Length -ne 51 -or [System.Text.Encoding]::ASCII.GetString($blob, 4, 11) -cne "ssh-ed25519") {'
           Replace = 'if ($false) {' }
        @{ Name = "changed-pin-replaced-silently"
           Find = 'if (-not $Replace) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "revoked-key-enrolled-again"
           Find = 'if ($rk.ok -and $rk.b64 -ceq $k.b64) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "device-takes-a-second-key"
           Find = 'return (New-HordeSshEnrolResult -Ok $false -Reason ("device " + $DeviceId + " is already enrolled with another key; revoke it first"))'
           Replace = '$null = 0' }
        @{ Name = "key-shared-by-two-devices"
           Find = 'foreach ($l in $lines) { if ($l.Contains(" " + $k.b64 + " ")) { return'
           Replace = 'foreach ($l in $lines) { if ($false) { return' }
        @{ Name = "no-expiry-time"
           Find = '''",restrict,expiry-time="'' + $expiry + ''" '''
           Replace = '''",restrict '' + '''' + '''' + '' ''' }
        @{ Name = "no-restrict"
           Find = '''",restrict,expiry-time="'''
           Replace = '''",expiry-time="''' }
        @{ Name = "quote-in-command-accepted"
           Find = '-or $Command.Contains(''"'')) {'
           Replace = ') {' }
        @{ Name = "revoked-key-not-recorded"
           Find = 'Write-HordeSshLines -Path $lp.revoked -Lines (@(Read-HordeSshLines -Path $lp.revoked) + @($m.Groups["key"].Value))'
           Replace = '' }
    )
}
