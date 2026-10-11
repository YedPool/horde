# Mutations of the enrolment verbs' register writes (cli/Enroll.ps1; issue #144 item 3, issue #124). Run:
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\enroll-cli.psd1
# transports\ssh\test\test-enroll.ps1 drives the real horde CLI and must fail for each.
@{
    Target = "cli\Enroll.ps1"
    Suite  = "transports\ssh\test\test-enroll.ps1"
    Mutations = @(
        @{ Name = "enroll-leaves-register-unwritten"
           Find = 'try { $null = Add-HordeHubEnrolment -HordeHome $hh -DeviceId $Device -Transport $e.name -Key "$($r.key)" -Expires "$($r.expires)" }'
           Replace = 'try { }' }
        @{ Name = "register-failure-silent"
           Find = 'catch { throw ("device " + $Device + "''s key is written for the "'
           Replace = 'catch { $null = ("device " + $Device + "''s key is written for the "' }
        @{ Name = "revoke-leaves-register-live"
           Find = '$why = Set-HordeHubEnrolmentRevoked -HordeHome $hh -DeviceId $Device'
           Replace = '$why = ""' }
        @{ Name = "revoke-register-failure-ignored"
           Find = 'if ($why -ne "") { throw ("device " + $Device + "''s key is revoked for the "'
           Replace = 'if ($false) { throw ("device " + $Device + "''s key is revoked for the "' }
    )
}
