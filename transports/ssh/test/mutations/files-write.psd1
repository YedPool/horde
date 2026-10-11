# Mutations of the ssh link's file writer (transports/ssh/Files.ps1, issue #123): authorized_keys,
# revoked_keys and known_hosts this user's alone on every write. Run:
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\files-write.psd1
# transports\ssh\test\test-enroll.ps1 must fail for each, except the one declared to survive.
@{
    Target = "transports\ssh\Files.ps1"
    Suite  = "transports\ssh\test\test-enroll.ps1"
    Mutations = @(
        # Moved from enroll.psd1 with the functions they mutate (Set-HordeSshKeyAcl, Test-HordeSshKeyAcl,
        # Write-HordeSshLines), unchanged.
        @{ Name = "key-acl-check-admits-others"
           Find = 'if ($rules.Count -lt 1 -or $others.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "key-acl-inheritance-allowed"
           Find = 'if (-not $read.AreAccessRulesProtected) {'
           Replace = 'if ($false) {' }
        @{ Name = "written-in-place"
           Find = 'Move-HordeFileAtomic -From $tmp -To $Path'
           Replace = '[System.IO.File]::WriteAllText($Path, $text, [System.Text.Encoding]::ASCII)' }
        @{ Name = "written-without-own-acl"
           Find = '$acl = Set-HordeSshKeyAcl -Path $tmp'
           Replace = '$acl = ""' }
        @{ Name = "acl-failure-ignored"
           Find = 'if ($acl -ne "") { throw ("the new "'
           Replace = 'if ($false) { throw ("the new "'
           Expect = "survives"
           Reason = "untestable without a file system that refuses this user's own Set-Acl on a file it just made; the throw keeps such a file from being renamed into place" }
        @{ Name = "acl-inheritance-kept"
           Find = '$acl.SetAccessRuleProtection($true, $false)'
           Replace = '$acl.SetAccessRuleProtection($false, $true)' }
    )
}
