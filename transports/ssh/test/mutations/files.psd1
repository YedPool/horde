# Mutations of who may write the ssh link's files (transports/ssh/Files.ps1, issue #123): the checks the
# listener runs before it starts. Run:
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\files.psd1
# transports\ssh\test\test-listen.ps1 must fail for each, except the one declared to survive. The writer
# itself is files-write.psd1.
@{
    Target = "transports\ssh\Files.ps1"
    Suite  = "transports\ssh\test\test-listen.ps1"
    Mutations = @(
        @{ Name = "inherit-only-rule-counted"
           Find = 'if ((([int]$r.PropagationFlags) -band 2) -ne 0) { continue }'
           Replace = '' }
        @{ Name = "deny-rule-counted"
           Find = 'if ("$($r.AccessControlType)" -cne "Allow") { continue }'
           Replace = '' }
        @{ Name = "read-only-rule-counted"
           Find = 'if ((([long]$r.FileSystemRights) -band $script:HordeSshWriteRights) -eq 0) { continue }'
           Replace = '' }
        @{ Name = "anyone-trusted"
           Find = 'if ($ok -ccontains $sid) { continue }'
           Replace = 'continue' }
        @{ Name = "system-and-administrators-not-trusted"
           Find = '$script:HordeSshTrustedWriters = @("S-1-5-18", "S-1-5-32-544")'
           Replace = '$script:HordeSshTrustedWriters = @()' }
        @{ Name = "delete-child-not-a-write"
           Find = '$script:HordeSshWriteRights = 0x2 -bor 0x4 -bor'
           Replace = '$script:HordeSshWriteRights = 0x0 -bor 0x0 -bor'
           Expect = "survives"
           Reason = "equivalent for the suite's widenings: Modify and Write each carry WriteAttributes (0x100), which still marks them; the full mask is there for a rule that grants CreateFiles or DeleteSubdirectoriesAndFiles alone, which no case makes" }
        @{ Name = "owner-not-checked"
           Find = 'if ($ok -cnotcontains $owner) {'
           Replace = 'if ($false) {'
           Expect = "survives"
           Reason = "untestable without privilege: giving a file an owner other than this user, SYSTEM or Administrators needs SeRestorePrivilege, which the suite does not take; the check is kept for a home made by another account" }
        @{ Name = "parents-not-walked"
           Find = '$cur = Split-Path -Parent $cur'
           Replace = 'break' }
        @{ Name = "findings-dropped"
           Find = 'if ($w.Count -gt 0) { [void]$out.Add('
           Replace = 'if ($false) { [void]$out.Add(' }
    )
}
